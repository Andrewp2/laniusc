import Lanius.Mini.Determinism

/-! Separate compilation and linking (roadmap step 9).

`compileModule` (`Lanius.Mini.Compiler`, extracted from `compiler.lani`)
compiles one module alone into an `Object`: each function's machine code as
`Piece`s, literal bytes with a hole for the rel32 field of every call to an
import. `linkObjects` lays the objects out back to back and fills the holes.
`linkProgram` says what a list of modules means: one mini program of all
their functions, calls renamed to program indices.

The theorem (`link_eq`): separate compilation and linking give exactly what
`compileProgram` gives for that program, as an `Option`,

```text
(compileModules ms).bind linkObjects = ((linkProgram ms).bind compileProgram).map Binary.executable
```

so `compileProgram_correct` holds for a linked executable with no new
premises (`linked_correct`, `linked_deterministic`).

The proof has two layers. Code: renaming a module's callees commutes with
`compileFunc`, and the module's own arity table (its functions', then its
imports' declared arities) agrees with the program's at every renamed callee
(`compileFunc_rename`, `table_agrees`). Bytes: a piece renders to the
instruction's bytes at its place in the image; calls inside a module were
encoded with module offsets, which give the same rel32 field
(`relative_shift`), and a hole's field is computed by the linker from the
import's entry (`Instr.pieces_render`). -/

namespace Lanius.Mini
open Lanius.X86.Machine

/-! ## Code: renaming callees -/

/-- A call's callee becomes `table[callee]`, or `missing` past the end. -/
def Instr.rename (table : List Nat) (missing : Nat) : Instr → Instr
  | .imm value => .imm value
  | .load slot => .load slot
  | .store slot => .store slot
  | .neg => .neg
  | .op word operation slot => .op word operation slot
  | .cmp word operation slot => .cmp word operation slot
  | .jmp target => .jmp target
  | .jz target => .jz target
  | .call callee args target count => .call (table.getD callee missing) args target count
  | .ret sources => .ret sources
  | .bump shift => .bump shift
  | .loadAt => .loadAt
  | .storeAt slot => .storeAt slot
  | .loadWordAt width => .loadWordAt width
  | .storeWordAt width slot => .storeWordAt width slot
  | .div word operation slot => .div word operation slot
  | .sys kind slot => .sys kind slot

def Code.rename (table : List Nat) (missing : Nat) (code : Code) : Code :=
  { slots := code.slots, instrs := code.instrs.map (Instr.rename table missing) }

theorem Instr.rename_size (table : List Nat) (missing : Nat) (i : Instr) : (i.rename table missing).size = i.size := by
  cases i <;> rfl

theorem codeSize_rename (table : List Nat) (missing : Nat) (code : List Instr) :
    codeSize (code.map (Instr.rename table missing)) = codeSize code := by
  induction code with
  | nil => rfl
  | cons i rest ih => simp [codeSize, Instr.rename_size, ih]

theorem Code.rename_size (table : List Nat) (missing : Nat) (code : Code) :
    (code.rename table missing).size = code.size := by
  simp [Code.rename, Code.size, codeSize_rename]

theorem compileExpr_rename (table : List Nat) (missing base : Nat) (e : Expr) (depth : Nat) :
    (compileExpr base e depth).map (Instr.rename table missing) = compileExpr base e depth := by
  induction e generalizing depth <;> simp_all [compileExpr, Instr.rename]

theorem compileArgs_rename (table : List Nat) (missing base : Nat) (args : List Expr) (k : Nat) :
    (compileArgs base args k).map (Instr.rename table missing) = compileArgs base args k := by
  induction args generalizing k with
  | nil => rfl
  | cons arg rest ih => simp [compileArgs, ih, compileExpr_rename, Instr.rename]

theorem compileStmt_rename (table : List Nat) (missing base : Nat) (s : Stmt) (pos : Nat) :
    compileStmt base pos (s.rename table missing) = (compileStmt base pos s).map (Instr.rename table missing) := by
  induction s generalizing pos <;>
    simp_all [Stmt.rename, compileStmt, compileExpr_rename, compileArgs_rename, codeSize_rename, Instr.rename]

theorem Stmt.temps_rename (table : List Nat) (missing : Nat) (s : Stmt) :
    (s.rename table missing).temps = s.temps := by
  induction s <;> simp_all [Stmt.rename, Stmt.temps]

/-- Renaming keeps a statement within its bounds when the program's arity of
every renamed callee is the module's arity of the callee. -/
theorem Stmt.within_rename {table : List Nat} {missing : Nat} {program own : List Arity}
    (agree : ∀ callee, program[table.getD callee missing]? = own[callee]?) (locals results : Nat) (s : Stmt) :
    (s.rename table missing).within locals program results = s.within locals own results := by
  induction s <;> simp_all [Stmt.rename, Stmt.within, arityIs]

theorem zeroLocals_rename (table : List Nat) (missing first count : Nat) :
    (zeroLocals first count).map (Instr.rename table missing) = zeroLocals first count := by
  induction count generalizing first with
  | zero => rw [zeroLocals_zero]; rfl
  | succ count ih => rw [zeroLocals_succ]; simp [ih, Instr.rename]

theorem compileFunc_rename {table : List Nat} {missing : Nat} {program own : List Arity}
    (agree : ∀ callee, program[table.getD callee missing]? = own[callee]?) (func : Func) :
    compileFunc program
        { params := func.params, results := func.results, locals := func.locals, body := func.body.rename table missing } =
      (compileFunc own func).map (Code.rename table missing) := by
  simp only [compileFunc, Stmt.within_rename agree, Stmt.temps_rename]
  split
  · simp only [Option.map_some, Code.rename, List.map_append, List.map_cons,
      zeroLocals_rename, compileStmt_rename, Instr.rename]
  · rfl

theorem compileFuncs_rename {table : List Nat} {missing : Nat} {program own : List Arity}
    (agree : ∀ callee, program[table.getD callee missing]? = own[callee]?) (funcs : List Func) :
    compileFuncs program (renameFuncs table missing funcs) =
      (compileFuncs own funcs).map (List.map (Code.rename table missing)) := by
  induction funcs with
  | nil => rfl
  | cons func rest ih =>
    simp only [renameFuncs, compileFuncs, compileFunc_rename agree, ih]
    cases compileFunc own func <;> cases compileFuncs own rest <;> rfl

theorem compileFuncs_append (arities : List Arity) (first second : List Func) :
    compileFuncs arities (first ++ second) =
      (compileFuncs arities first).bind fun codes => (compileFuncs arities second).map (codes ++ ·) := by
  induction first with
  | nil => cases h : compileFuncs arities second <;> simp [compileFuncs, h]
  | cons func rest ih =>
    simp only [List.cons_append, compileFuncs, ih]
    cases compileFunc arities func <;> cases compileFuncs arities rest <;>
      cases compileFuncs arities second <;> rfl

theorem arities_append (first second : List Func) : arities (first ++ second) = arities first ++ arities second := by
  induction first <;> simp_all [arities]

theorem arities_renameFuncs (table : List Nat) (missing : Nat) (funcs : List Func) :
    arities (renameFuncs table missing funcs) = arities funcs := by
  induction funcs <;> simp_all [arities, renameFuncs]

theorem renameFuncs_length (table : List Nat) (missing : Nat) (funcs : List Func) :
    (renameFuncs table missing funcs).length = funcs.length := by
  induction funcs <;> simp_all [renameFuncs]

theorem resolveModules_arities (firsts : List Nat) (missing : Nat) :
    ∀ (ms : List Module) (first : Nat),
      arities (resolveModules firsts missing first ms) = (moduleExports ms).flatten
  | [], _ => rfl
  | m :: rest, first => by
    simp [resolveModules, moduleExports, arities_append, arities_renameFuncs,
      resolveModules_arities firsts missing rest]

theorem funcCount_eq (ms : List Module) : funcCount ms = ((moduleExports ms).flatten).length := by
  induction ms <;> simp_all [funcCount, moduleExports, arities_length]

theorem resolveModules_length (firsts : List Nat) (missing : Nat) :
    ∀ (ms : List Module) (first : Nat), (resolveModules firsts missing first ms).length = funcCount ms
  | [], _ => rfl
  | m :: rest, first => by
    simp [resolveModules, funcCount, renameFuncs_length, resolveModules_length firsts missing rest]

theorem importIndices_eq (firsts : List Nat) (imports : List Import) :
    importIndices firsts imports = imports.map fun imp => firsts.getD imp.owner 0 + imp.func := by
  induction imports <;> simp_all [importIndices]

theorem importArities_eq (imports : List Import) : importArities imports = imports.map (·.arity) := by
  induction imports <;> simp_all [importArities]

theorem importsOk_eq (exports : List (List Arity)) (imports : List Import) :
    importsOk exports imports = true ↔ ∀ imp ∈ imports, importOk exports imp = true := by
  induction imports <;> simp_all [importsOk]

theorem modulesOk_eq (exports : List (List Arity)) (ms : List Module) :
    modulesOk exports ms = true ↔ ∀ m ∈ ms, importsOk exports m.imports = true := by
  induction ms <;> simp_all [modulesOk]

/-- Where module `mod`'s arities sit in the program's. -/
theorem moduleFirsts_at : ∀ (ms : List Module) (first mod : Nat) (found : List Arity),
    (moduleExports ms)[mod]? = some found →
      ∃ k, (moduleFirsts first ms).getD mod 0 = first + k ∧
        ∀ j, j < found.length → ((moduleExports ms).flatten)[k + j]? = found[j]?
  | [], _, _, _, at_ => by simp [moduleExports] at at_
  | m :: rest, first, 0, found, at_ => by
    simp only [moduleExports, List.getElem?_cons_zero, Option.some.injEq] at at_
    subst at_
    refine ⟨0, by simp [moduleFirsts], fun j bound => ?_⟩
    simp only [moduleExports, List.flatten_cons, Nat.zero_add]
    rw [List.getElem?_append_left bound]
  | m :: rest, first, mod + 1, found, at_ => by
    simp only [moduleExports, List.getElem?_cons_succ] at at_
    obtain ⟨k, start, inside⟩ := moduleFirsts_at rest (first + m.funcs.length) mod found at_
    refine ⟨m.funcs.length + k, ?_, fun j bound => ?_⟩
    · simp only [moduleFirsts, List.getD_cons_succ, start]; omega
    · simp only [moduleExports, List.flatten_cons]
      rw [List.getElem?_append_right (by simp [arities_length]; omega)]
      have := inside j bound
      simp only [arities_length] at this ⊢
      rw [← this]; congr 1; omega

/-- A module's local arity table: its functions', then its imports'. -/
def localArities (m : Module) : List Arity := arities m.funcs ++ importArities m.imports

/-- The program index of each of a module's callees, when its first function
is program function `first`. -/
def callTable (firsts : List Nat) (first : Nat) (m : Module) : List Nat :=
  slotRange first m.funcs.length ++ importIndices firsts m.imports

theorem callTable_own {firsts : List Nat} {first : Nat} {m : Module} {missing callee : Nat}
    (own : callee < m.funcs.length) : (callTable firsts first m).getD callee missing = first + callee := by
  simp [callTable, slotRange_eq, List.getD_eq_getElem?_getD, List.getElem?_append_left, own]

theorem callTable_import {firsts : List Nat} {first : Nat} {m : Module} {missing callee : Nat}
    (imported : m.funcs.length ≤ callee) :
    (callTable firsts first m).getD callee missing = (importIndices firsts m.imports).getD (callee - m.funcs.length) missing := by
  simp only [callTable, List.getD_eq_getElem?_getD]
  rw [List.getElem?_append_right (by simp [slotRange_length]; omega), slotRange_length]

/-- The program's arity of every renamed callee is the module's arity of it,
when the module's imports check out. -/
theorem table_agrees {exports : List (List Arity)} {firsts : List Nat} {program : List Arity} {first : Nat}
    {m : Module} {rest : List Arity}
    (imports : ∀ mod found func, exports[mod]? = some found → func < found.length →
      program[firsts.getD mod 0 + func]? = found[func]?)
    (here : program.drop first = arities m.funcs ++ rest)
    (ok : importsOk exports m.imports = true) :
    ∀ callee, program[(callTable firsts first m).getD callee program.length]? = (localArities m)[callee]? := by
  intro callee
  have ownLength := arities_length m.funcs
  by_cases own : callee < m.funcs.length
  · rw [callTable_own own, localArities, List.getElem?_append_left (by omega)]
    have : program[first + callee]? = (program.drop first)[callee]? := by simp
    rw [this, here, List.getElem?_append_left (by omega)]
  · rw [callTable_import (by omega), localArities, List.getElem?_append_right (by omega), ownLength,
      importIndices_eq, importArities_eq]
    by_cases imported : callee - m.funcs.length < m.imports.length
    · have imp := List.getElem_mem imported
      have impOk := (importsOk_eq exports m.imports).1 ok _ imp
      simp only [importOk] at impOk
      split at impOk
      · contradiction
      · rename_i found at_
        obtain ⟨arity, arityAt, params, results⟩ := (arityIs_eq _ _ _ _).1 impOk
        have bound : m.imports[callee - m.funcs.length].func < found.length := by
          by_cases h : m.imports[callee - m.funcs.length].func < found.length
          · exact h
          · rw [List.getElem?_eq_none (by omega)] at arityAt
            contradiction
        simp only [List.getD_eq_getElem?_getD, List.getElem?_map, List.getElem?_eq_getElem imported,
          Option.map_some, Option.getD_some]
        have target := imports _ _ _ at_ bound
        simp only [List.getD_eq_getElem?_getD] at target
        rw [target, arityAt]
        congr 1
        cases arity
        cases h : m.imports[callee - m.funcs.length].arity
        simp_all
    · simp only [List.getD_eq_getElem?_getD, List.getElem?_map,
        List.getElem?_eq_none (show m.imports.length ≤ callee - m.funcs.length by omega), Option.map_none,
        Option.getD_none, List.getElem?_eq_none (Nat.le_refl _)]

/-! ## Modules and their objects -/

/-- The object `compileModule` makes of a module whose functions compiled to
`codes` against its own arity table. -/
def objectOf (m : Module) (codes : List Code) : Object :=
  { exports := arities m.funcs, imports := m.imports, funcs := objectFuncs m.funcs.length (layout 0 codes) 0 codes }

theorem compileModule_eq (m : Module) :
    compileModule m = (compileFuncs (localArities m) m.funcs).map (objectOf m) := by
  simp only [compileModule, localArities]
  cases compileFuncs (arities m.funcs ++ importArities m.imports) m.funcs <;> rfl

theorem objectFuncs_length (own : Nat) (entries : List Nat) :
    ∀ (codes : List Code) (start : Nat), (objectFuncs own entries start codes).length = codes.length
  | [], _ => rfl
  | code :: rest, start => by simp [objectFuncs, objectFuncs_length own entries rest]

/-- Exports, imports and function counts of separately compiled modules are
the modules'. -/
theorem compileModules_shape (exports : List (List Arity)) :
    ∀ {ms : List Module} {objs : List Object}, compileModules ms = some objs →
      objectExports objs = moduleExports ms ∧ objectsOk exports objs = modulesOk exports ms ∧
        ∀ first, objectFirsts first objs = moduleFirsts first ms
  | [], objs, compiled => by
    simp only [compileModules, Option.some.injEq] at compiled
    subst compiled
    exact ⟨rfl, rfl, fun _ => rfl⟩
  | m :: ms, objs, compiled => by
    simp only [compileModules, compileModule_eq] at compiled
    cases here : compileFuncs (localArities m) m.funcs with
    | none => simp [here] at compiled
    | some codes =>
      cases rest : compileModules ms with
      | none => simp [here, rest] at compiled
      | some objs' =>
        simp only [here, rest, Option.map_some, Option.some.injEq] at compiled
        subst compiled
        obtain ⟨exportsSame, okSame, firstsSame⟩ := compileModules_shape exports rest
        refine ⟨by simp [objectExports, moduleExports, objectOf, exportsSame], by
          simp [objectsOk, modulesOk, objectOf, okSame], fun first => ?_⟩
        simp only [objectFirsts, moduleFirsts, objectOf, objectFuncs_length, compileFuncs_length here,
          firstsSame]

/-- Separately compiled modules `ms`, the first of which starts at program
function `first`; their objects; and the program's codes of their functions. -/
inductive Agrees (firsts : List Nat) (missing : Nat) : Nat → List Module → List Object → List Code → Prop
  | nil (first : Nat) : Agrees firsts missing first [] [] []
  | cons {first : Nat} {m : Module} {ms : List Module} {objs : List Object} {codes own : List Code}
      (compiled : compileFuncs (localArities m) m.funcs = some own)
      (rest : Agrees firsts missing (first + m.funcs.length) ms objs codes) :
      Agrees firsts missing first (m :: ms) (objectOf m own :: objs)
        (own.map (Code.rename (callTable firsts first m) missing) ++ codes)

/-- Compiling the modules separately fails exactly when compiling the
program fails, and otherwise they agree. -/
theorem resolve_compile {exports : List (List Arity)} {firsts : List Nat} {program : List Arity}
    (imports : ∀ mod found func, exports[mod]? = some found → func < found.length →
      program[firsts.getD mod 0 + func]? = found[func]?) :
    ∀ (ms : List Module) (first : Nat), (∀ m ∈ ms, importsOk exports m.imports = true) →
      program.drop first = (moduleExports ms).flatten →
      (compileModules ms = none ∧ compileFuncs program (resolveModules firsts program.length first ms) = none) ∨
        ∃ objs codes, compileModules ms = some objs ∧
          compileFuncs program (resolveModules firsts program.length first ms) = some codes ∧
          Agrees firsts program.length first ms objs codes
  | [], first, _, _ => .inr ⟨[], [], rfl, rfl, .nil first⟩
  | m :: ms, first, ok, here => by
    have hereM : program.drop first = arities m.funcs ++ (moduleExports ms).flatten := by
      simpa [moduleExports] using here
    have agree := table_agrees imports hereM (ok m (by simp))
    have next : program.drop (first + m.funcs.length) = (moduleExports ms).flatten := by
      rw [← List.drop_drop, hereM, ← arities_length, List.drop_left]
    have restCase := resolve_compile imports ms (first + m.funcs.length) (fun m' h => ok m' (by simp [h])) next
    simp only [compileModules, compileModule_eq, resolveModules, compileFuncs_append]
    rw [show slotRange first m.funcs.length ++ importIndices firsts m.imports = callTable firsts first m from rfl,
      compileFuncs_rename agree]
    cases hm : compileFuncs (localArities m) m.funcs with
    | none => left; simp
    | some own =>
      rcases restCase with ⟨none1, none2⟩ | ⟨objs, codes, c1, c2, agrees⟩
      · left; simp [none1, none2]
      · right; exact ⟨_, _, by simp [c1], by simp [c2], .cons hm agrees⟩

/-! ## Bytes: rendering object code -/

theorem render_append (targets : List Nat) (pos : Nat) (first second : List Piece) :
    render targets pos (first ++ second) = render targets pos first ++ render targets (pos + piecesSize first) second := by
  induction first generalizing pos with
  | nil => simp [render, piecesSize]
  | cons piece rest ih => simp [render, piecesSize, ih, Nat.add_assoc]

theorem piecesSize_append (first second : List Piece) :
    piecesSize (first ++ second) = piecesSize first + piecesSize second := by
  induction first <;> simp_all [piecesSize, Nat.add_assoc]

theorem Instr.pieces_size (own : Nat) (place : Place) (pc : Nat) (i : Instr) :
    piecesSize (i.pieces own place pc) = i.size := by
  cases i with
  | call callee args target count =>
    simp only [Instr.pieces, callPieces]
    split
    · simp [piecesSize, Piece.size, copyBytes_length, slotRange_length, Instr.size]; omega
    · simp [piecesSize, Piece.size, Instr.encode_length]
  | _ => simp [Instr.pieces, piecesSize, Piece.size, Instr.encode_length]

theorem piecesFrom_size (own : Nat) (place : Place) :
    ∀ (code : List Instr) (pc : Nat), piecesSize (piecesFrom own place pc code) = codeSize code
  | [], _ => rfl
  | i :: rest, pc => by
    simp [piecesFrom, piecesSize_append, Instr.pieces_size, piecesFrom_size own place rest, codeSize]

/-- A rel32 field does not depend on where the pair of offsets sits. -/
theorem relative_shift (base source target : Nat) :
    relative (base + source) (base + target) = relative source target := by
  simp only [relative, BitVec.ofNat_add]
  bv_omega

/-- An instruction's pieces render to its bytes at its place in the image,
when the module's own entries sit at `pos` in the image and the linker's
targets are the imports' entries. -/
theorem Instr.pieces_render {table : List Nat} {missing own : Nat} {targets entries localEntries : List Nat}
    {pos : Nat}
    (ownCalls : ∀ callee, callee < own → entries.getD (table.getD callee missing) 0 = pos + localEntries.getD callee 0)
    (importCalls : ∀ callee, own ≤ callee →
      targets.getD (callee - own) 0 = entries.getD (table.getD callee missing) 0)
    (body slots pc : Nat) (i : Instr) :
    render targets (pos + body + pc) (i.pieces own ⟨body, slots, localEntries⟩ pc) =
      (i.rename table missing).encode ⟨pos + body, slots, entries⟩ pc := by
  cases i with
  | call callee args target count =>
    simp only [Instr.pieces, callPieces, Instr.rename, Instr.encode]
    split
    · rename_i imported
      simp only [render, Piece.render, Piece.size, List.length_append, copyBytes_length, List.length_cons,
        List.length_nil, List.append_nil, importCalls callee imported, List.append_assoc, List.cons_append,
        List.nil_append]
      rw [show pos + body + pc + (14 * args.length + (0 + 1)) + 4 = pos + body + pc + 14 * args.length + 5 by omega]
    · rename_i local_
      simp only [render, Piece.render, List.append_nil, ownCalls callee (by omega)]
      rw [show pos + body + pc + 14 * args.length + 5 = pos + (body + pc + 14 * args.length + 5) by omega,
        relative_shift]
  | _ => simp [Instr.pieces, render, Piece.render, Instr.rename, Instr.encode]

theorem piecesFrom_render {table : List Nat} {missing own : Nat} {targets entries localEntries : List Nat}
    {pos : Nat}
    (ownCalls : ∀ callee, callee < own → entries.getD (table.getD callee missing) 0 = pos + localEntries.getD callee 0)
    (importCalls : ∀ callee, own ≤ callee →
      targets.getD (callee - own) 0 = entries.getD (table.getD callee missing) 0)
    (body slots : Nat) : ∀ (code : List Instr) (pc : Nat),
      render targets (pos + body + pc) (piecesFrom own ⟨body, slots, localEntries⟩ pc code) =
        encodeFrom ⟨pos + body, slots, entries⟩ pc (code.map (Instr.rename table missing))
  | [], _ => rfl
  | i :: rest, pc => by
    simp only [piecesFrom, List.map_cons, encodeFrom, render_append, Instr.pieces_size, Instr.rename_size,
      Instr.pieces_render ownCalls importCalls]
    rw [show pos + body + pc + i.size = pos + body + (pc + i.size) by omega,
      piecesFrom_render ownCalls importCalls body slots rest (pc + i.size)]

/-- Code bytes of a list of codes. -/
def codesSize : List Code → Nat
  | [] => 0
  | code :: rest => code.size + codesSize rest

theorem codesSize_rename (table : List Nat) (missing : Nat) (codes : List Code) :
    codesSize (codes.map (Code.rename table missing)) = codesSize codes := by
  induction codes <;> simp_all [codesSize, Code.rename_size]

theorem objectFunc_size (own : Nat) (place : Place) (code : Code) :
    piecesSize (Piece.bytes (prologue code.slots) :: piecesFrom own place 0 code.instrs) = code.size := by
  simp [piecesSize, Piece.size, piecesFrom_size, Code.size, prologue_length]

theorem objectFuncs_facts (own : Nat) (entries : List Nat) :
    ∀ (codes : List Code) (start pos : Nat),
      funcsSize (objectFuncs own entries start codes) = codesSize codes ∧
        objectLayout pos (objectFuncs own entries start codes) = layout pos codes ∧
        funcsSlots (objectFuncs own entries start codes) = codes.map (·.slots)
  | [], _, _ => ⟨rfl, rfl, rfl⟩
  | code :: rest, start, pos => by
    obtain ⟨size, at_, slots⟩ := objectFuncs_facts own entries rest (start + code.size) (pos + code.size)
    simp only [objectFuncs, funcsSize, objectLayout, funcsSlots, objectFunc_size, size, at_, slots, codesSize,
      layout, List.map_cons]
    exact ⟨trivial, trivial, trivial⟩

/-- A module's functions render to the program's image of their renamed codes. -/
theorem objectFuncs_render {table : List Nat} {missing own : Nat} {targets entries localEntries : List Nat}
    {pos : Nat}
    (ownCalls : ∀ callee, callee < own → entries.getD (table.getD callee missing) 0 = pos + localEntries.getD callee 0)
    (importCalls : ∀ callee, own ≤ callee →
      targets.getD (callee - own) 0 = entries.getD (table.getD callee missing) 0) :
    ∀ (codes : List Code) (start : Nat),
      renderFuncs targets (pos + start) (objectFuncs own localEntries start codes) =
        linkFrom entries (pos + start) (codes.map (Code.rename table missing))
  | [], _ => rfl
  | code :: rest, start => by
    simp only [objectFuncs, renderFuncs, List.map_cons, linkFrom, Code.image, Code.rename, objectFunc_size]
    simp only [render, Piece.render, Piece.size, prologue_length]
    rw [show pos + start + 24 = pos + (start + 24) + 0 by omega,
      piecesFrom_render ownCalls importCalls (start + 24) code.slots code.instrs 0,
      show pos + start + code.size = pos + (start + code.size) by omega,
      objectFuncs_render ownCalls importCalls rest (start + code.size)]
    simp [Code.size, codeSize_rename, Nat.add_assoc]

theorem layout_append (start : Nat) (first second : List Code) :
    layout start (first ++ second) = layout start first ++ layout (start + codesSize first) second := by
  induction first generalizing start with
  | nil => simp [layout, codesSize]
  | cons code rest ih => simp [layout, codesSize, ih, Nat.add_assoc]

theorem linkFrom_append (entries : List Nat) (start : Nat) (first second : List Code) :
    linkFrom entries start (first ++ second) =
      linkFrom entries start first ++ linkFrom entries (start + codesSize first) second := by
  induction first generalizing start with
  | nil => simp [linkFrom, codesSize]
  | cons code rest ih => simp [linkFrom, codesSize, ih, Nat.add_assoc]

theorem layout_rename (table : List Nat) (missing : Nat) (start : Nat) (codes : List Code) :
    layout start (codes.map (Code.rename table missing)) = layout start codes := by
  induction codes generalizing start <;> simp_all [layout, Code.rename_size]

theorem layout_shift (pos start : Nat) (codes : List Code) :
    layout (pos + start) codes = (layout start codes).map (pos + ·) := by
  induction codes generalizing start with
  | nil => rfl
  | cons code rest ih => simp [layout, ← ih, Nat.add_assoc]

theorem entriesAt_getD {entries : List Nat} {missing : Nat} (short : entries.length ≤ missing)
    (indices : List Nat) (i : Nat) :
    (entriesAt entries indices).getD i 0 = entries.getD (indices.getD i missing) 0 := by
  induction indices generalizing i with
  | nil =>
    simp only [entriesAt, List.getD_eq_getElem?_getD, List.getElem?_nil, Option.getD_none]
    rw [List.getElem?_eq_none short]; rfl
  | cons index rest ih => cases i <;> simp_all [entriesAt]

theorem getD_append_left {α : Type} {first second : List α} {i : Nat} {fallback : α} (bound : i < first.length) :
    (first ++ second).getD i fallback = first.getD i fallback := by
  simp [List.getD_eq_getElem?_getD, List.getElem?_append_left bound]

theorem getD_append_length {α : Type} (first second : List α) (j : Nat) (fallback : α) :
    (first ++ second).getD (first.length + j) fallback = second.getD j fallback := by
  simp [List.getD_eq_getElem?_getD, List.getElem?_append_right]

theorem getD_map_add {items : List Nat} {pos i : Nat} (bound : i < items.length) :
    (items.map (pos + ·)).getD i 0 = pos + items.getD i 0 := by
  simp [List.getD_eq_getElem?_getD, List.getElem?_eq_getElem bound]

/-- Rendering agreeing objects gives the program's layout and image. -/
theorem Agrees.bytes {firsts : List Nat} {missing : Nat} {entries : List Nat} (short : entries.length ≤ missing) :
    ∀ {first : Nat} {ms : List Module} {objs : List Object} {codes : List Code},
      Agrees firsts missing first ms objs codes → ∀ pos,
      (∀ j, j < codes.length → entries.getD (first + j) 0 = (layout pos codes).getD j 0) →
      renderObjects firsts entries pos objs = linkFrom entries pos codes ∧
        objectsLayout pos objs = layout pos codes ∧ objectsSlots objs = codes.map (·.slots)
  | _, _, _, _, .nil _, _, _ => ⟨rfl, rfl, rfl⟩
  | first, m :: ms, _, _, .cons (codes := codes) (own := own) compiled rest, pos, here => by
    have ownLength := compileFuncs_length compiled
    have layoutLength := layout_length own 0
    have ownCalls : ∀ callee, callee < m.funcs.length →
        entries.getD ((callTable firsts first m).getD callee missing) 0 = pos + (layout 0 own).getD callee 0 := by
      intro callee bound
      rw [callTable_own bound, here callee (by simp; omega), layout_append, layout_rename,
        getD_append_left (by simp [layout_length]; omega),
        show layout pos own = (layout 0 own).map (pos + ·) by simpa using layout_shift pos 0 own,
        getD_map_add (by omega)]
    have importCalls : ∀ callee, m.funcs.length ≤ callee →
        (entriesAt entries (importIndices firsts m.imports)).getD (callee - m.funcs.length) 0 =
          entries.getD ((callTable firsts first m).getD callee missing) 0 := by
      intro callee bound
      rw [callTable_import bound, entriesAt_getD short]
    have next : ∀ j, j < codes.length →
        entries.getD (first + m.funcs.length + j) 0 = (layout (pos + codesSize own) codes).getD j 0 := by
      intro j bound
      have := here (m.funcs.length + j) (by simp; omega)
      rw [layout_append, layout_rename, codesSize_rename] at this
      have key := getD_append_length (layout pos own) (layout (pos + codesSize own) codes) j 0
      rw [layout_length, ownLength] at key
      rw [Nat.add_assoc, this, key]
    obtain ⟨image, at_, slots⟩ := Agrees.bytes short rest (pos + codesSize own) next
    obtain ⟨size, ownAt, ownSlots⟩ := objectFuncs_facts m.funcs.length (layout 0 own) own 0 pos
    have rendered := objectFuncs_render ownCalls importCalls own 0
    simp only [Nat.add_zero] at rendered
    refine ⟨?_, ?_, ?_⟩
    · simp only [renderObjects, objectOf, rendered, size, image, linkFrom_append, codesSize_rename]
    · simp only [objectsLayout, objectOf, ownAt, size, at_, layout_append, layout_rename, codesSize_rename]
    · simp only [objectsSlots, objectOf, ownSlots, slots, List.map_append, List.map_map]
      rfl

/-! ## The theorem -/

/-- What `compileProgram` gives that a linked executable has: each function's
frame slots, the entries and the image. -/
def Binary.executable (binary : Binary) : Executable :=
  { slots := binary.codes.map (·.slots), entries := binary.entries, image := binary.image }

/-- **Separate compilation is compilation.** Compiling each module alone and
linking the objects gives exactly what compiling the modules' program gives,
and fails exactly when that does. -/
theorem link_eq (ms : List Module) :
    (compileModules ms).bind linkObjects = ((linkProgram ms).bind compileProgram).map Binary.executable := by
  by_cases ok : modulesOk (moduleExports ms) ms = true
  · have meaning : linkProgram ms =
        some { funcs := resolveModules (moduleFirsts 0 ms) ((moduleExports ms).flatten.length) 0 ms } := by
      simp [linkProgram, ok, funcCount_eq]
    have imports : ∀ mod found func, (moduleExports ms)[mod]? = some found → func < found.length →
        ((moduleExports ms).flatten)[(moduleFirsts 0 ms).getD mod 0 + func]? = found[func]? := by
      intro mod found func at_ bound
      obtain ⟨k, start, inside⟩ := moduleFirsts_at ms 0 mod found at_
      rw [start, Nat.zero_add, inside func bound]
    have program := resolveModules_arities (moduleFirsts 0 ms) ((moduleExports ms).flatten.length) ms 0
    rcases resolve_compile imports ms 0 ((modulesOk_eq _ _).1 ok) (by simp) with
      ⟨none1, none2⟩ | ⟨objs, codes, c1, c2, agrees⟩
    · rw [none1, meaning]
      simp only [Option.bind_none, Option.bind_some, compileProgram]
      rw [program, none2]
      rfl
    · rw [c1, meaning]
      have codesLength : codes.length = ((moduleExports ms).flatten).length := by
        rw [compileFuncs_length c2, resolveModules_length, funcCount_eq]
      obtain ⟨exportsSame, okSame, firstsSame⟩ := compileModules_shape (moduleExports ms) c1
      obtain ⟨image, at_, slots⟩ :=
        agrees.bytes (entries := layout 0 codes) (by rw [layout_length, codesLength]; exact Nat.le_refl _) 0 (fun j _ => by simp)
      simp only [Option.bind_some, compileProgram, program, c2, linkObjects, firstsSame, at_, image, okSame, ok,
        exportsSame, slots, Bool.true_and]
      split <;> simp_all [Binary.executable]
  · have meaning : linkProgram ms = none := by simp [linkProgram, ok]
    rw [meaning]
    cases compiled : compileModules ms with
    | none => rfl
    | some objs =>
      obtain ⟨exportsSame, okSame, -⟩ := compileModules_shape (moduleExports ms) compiled
      simp [linkObjects, exportsSame, okSame, ok]

/-- A linked executable is the image `compileProgram` makes of the modules'
program. -/
theorem linked_spec {ms : List Module} {objs : List Object} {exe : Executable}
    (compiled : compileModules ms = some objs) (linked : linkObjects objs = some exe) :
    ∃ prog binary, linkProgram ms = some prog ∧ compileProgram prog = some binary ∧ binary.executable = exe := by
  have same := link_eq ms
  rw [compiled, Option.bind_some, linked] at same
  cases meaning : linkProgram ms with
  | none => rw [meaning] at same; contradiction
  | some prog =>
    rw [meaning, Option.bind_some] at same
    cases binaryOf : compileProgram prog with
    | none => rw [binaryOf] at same; contradiction
    | some binary =>
      rw [binaryOf, Option.map_some, Option.some.injEq] at same
      exact ⟨prog, binary, rfl, binaryOf, same.symm⟩

/-- Stack bytes one activation of any of the functions uses. -/
def slotsNeed : List Nat → Nat
  | [] => 0
  | slots :: rest => max (frameBytes slots + 16) (slotsNeed rest)

/-- `Binary.stackNeed` of the executable's frames. -/
def Executable.stackNeed (exe : Executable) (depth : Nat) : Nat := (depth + 2) * slotsNeed exe.slots

/-- `Binary.guard` of the executable's frames. -/
def Executable.guard (exe : Executable) : Nat := slotsNeed exe.slots + 8

theorem slotsNeed_map (codes : List Code) : slotsNeed (codes.map (·.slots)) = frameNeed codes := by
  induction codes <;> simp_all [slotsNeed, frameNeed]

theorem executable_stackNeed (binary : Binary) (depth : Nat) :
    binary.executable.stackNeed depth = binary.stackNeed depth := by
  simp [Executable.stackNeed, Binary.stackNeed, Binary.executable, slotsNeed_map]

theorem executable_guard (binary : Binary) : binary.executable.guard = binary.guard := by
  simp [Executable.guard, Binary.guard, Binary.executable, slotsNeed_map]

/-- **Separately compiled modules are correct.** `compileProgram_correct`
for a linked executable: if function `f` of the modules' program returns
`value`, the executable's code for `f` returns it, under the same premises
with the executable's image, entries and stack need. -/
theorem linked_correct {ms : List Module} {objs : List Object} {exe : Executable}
    (compiled : compileModules ms = some objs) (linked : linkObjects objs = some exe)
    {prog : Program} (meaning : linkProgram ms = some prog)
    {depth f : Nat} {args value : List (BitVec 64)} {heap after : Heap}
    (returns : prog.Returns depth f args heap value after)
    (s : State) (imageBase : BitVec 64) (window : Nat)
    (enough : exe.stackNeed depth ≤ window) (bounded : window ≤ 2 ^ 62)
    (loaded : CodeAt s.memory imageBase exe.image)
    (apart : ∀ index, index < exe.image.length →
      ¬Below (s.registers rspRegister) window (imageBase + BitVec.ofNat 64 index))
    (imageHeap : ∀ index, index < exe.image.length → ¬s.InHeap (imageBase + BitVec.ofNat 64 index))
    (entry : s.rip = imageBase + BitVec.ofNat 64 (exe.entries.getD f 0))
    (params : ∀ k (bound : k < args.length),
      read64 s.memory (s.registers rspRegister - BitVec.ofNat 64 (8 * k + 16)) = args[k])
    (heapAt : HeapAt window s heap) (stack : StackAt exe.guard window s) :
    ∃ n s', Steps n s s' ∧ Det n s s' ∧ Returned window s s' value after := by
  obtain ⟨prog', binary, meaning', binaryOf, same⟩ := linked_spec compiled linked
  rw [meaning, Option.some.injEq] at meaning'
  subst meaning' same
  exact compileProgram_correct binaryOf returns s imageBase window (by rwa [← executable_stackNeed]) bounded
    loaded apart imageHeap entry params heapAt (by rwa [← executable_guard])

/-- `compileProgram_deterministic` for a linked executable: every run of the
same length returns the same way. -/
theorem linked_deterministic {ms : List Module} {objs : List Object} {exe : Executable}
    (compiled : compileModules ms = some objs) (linked : linkObjects objs = some exe)
    {prog : Program} (meaning : linkProgram ms = some prog)
    {depth f : Nat} {args value : List (BitVec 64)} {heap after : Heap}
    (returns : prog.Returns depth f args heap value after)
    (s : State) (imageBase : BitVec 64) (window : Nat)
    (enough : exe.stackNeed depth ≤ window) (bounded : window ≤ 2 ^ 62)
    (loaded : CodeAt s.memory imageBase exe.image)
    (apart : ∀ index, index < exe.image.length →
      ¬Below (s.registers rspRegister) window (imageBase + BitVec.ofNat 64 index))
    (imageHeap : ∀ index, index < exe.image.length → ¬s.InHeap (imageBase + BitVec.ofNat 64 index))
    (entry : s.rip = imageBase + BitVec.ofNat 64 (exe.entries.getD f 0))
    (params : ∀ k (bound : k < args.length),
      read64 s.memory (s.registers rspRegister - BitVec.ofNat 64 (8 * k + 16)) = args[k])
    (heapAt : HeapAt window s heap) (stack : StackAt exe.guard window s) :
    ∃ n s', Steps n s s' ∧ Det n s s' ∧ Returned window s s' value after ∧
      ∀ t, Steps n s t → DataEq s' t ∧ Returned window s t value after := by
  obtain ⟨prog', binary, meaning', binaryOf, same⟩ := linked_spec compiled linked
  rw [meaning, Option.some.injEq] at meaning'
  subst meaning' same
  exact compileProgram_deterministic binaryOf returns s imageBase window (by rwa [← executable_stackNeed])
    bounded loaded apart imageHeap entry params heapAt (by rwa [← executable_guard])

end Lanius.Mini
