module

public import Lanius.Faithful.SelfPre.CompileSlots
public import Lanius.Faithful.SelfPre.NB
public import Lanius.Mini.Room
import all Lanius.Mini.Compiler.P.codeSize
import all Lanius.Mini.Compiler.P.compileExpr
import all Lanius.Mini.Compiler.P.Expr_temps
import all Lanius.Mini.Compiler.P.Expr_within
import all Lanius.Mini.Compiler.P.Stmt_temps
import all Lanius.Mini.Compiler.P.Stmt_within
import all Lanius.Mini.Compiler.P.allWithin
import all Lanius.Mini.Compiler.P.argSlots
import all Lanius.Mini.Compiler.P.argsRoom
import all Lanius.Mini.Compiler.P.argsTemps
import all Lanius.Mini.Compiler.P.arityIs
import all Lanius.Mini.Compiler.P.compileArgs
import all Lanius.Mini.Compiler.P.compileStmt
import all Lanius.Mini.Compiler.P.exprRoom
import all Lanius.Mini.Compiler.P.frameLimit
import all Lanius.Mini.Compiler.P.imageLimit
import all Lanius.Mini.Compiler.P.spend
import all Lanius.Mini.Compiler.P.stmtRoom
import all Lanius.Mini.Compiler.P.zeroLocals
import all Lanius.Mini.Compiler.P.DivOp_size
import all Lanius.Mini.Compiler.P.FOp_size
import all Lanius.Mini.Compiler.P.FloatTy_mask
import all Lanius.Mini.Compiler.P.FloatTy_number
import all Lanius.Mini.Compiler.P.FloatTy_rexSize
import all Lanius.Mini.Compiler.P.FloatTy_signBit
import all Lanius.Mini.Compiler.P.FloatTy_signWord
import all Lanius.Mini.Compiler.P.Instr_size
import all Lanius.Mini.Compiler.P.BinOp_bytes
import all Lanius.Mini.Compiler.P.BinOp_opcode
import all Lanius.Mini.Compiler.P.CmpOp_setcc
import all Lanius.Mini.Compiler.P.CmpOp_setccSigned
import all Lanius.Mini.Compiler.P.CmpOp_setccUnsigned
import all Lanius.Mini.Compiler.P.DivOp_bytes
import all Lanius.Mini.Compiler.P.DivOp_extend
import all Lanius.Mini.Compiler.P.DivOp_opcode
import all Lanius.Mini.Compiler.P.DivOp_result
import all Lanius.Mini.Compiler.P.Word_rex
import all Lanius.Mini.Compiler.P.arities
import all Lanius.Mini.Compiler.P.compileFuncs
import all Lanius.Mini.Compiler.P.fspLoad
import all Lanius.Mini.Compiler.P.fspSave
import all Lanius.Mini.Compiler.P.le32
import all Lanius.Mini.Compiler.P.le64
import all Lanius.Mini.Compiler.P.slotCompare
import all Lanius.Mini.Compiler.P.slotLoad
import all Lanius.Mini.Compiler.P.slotOffset
import all Lanius.Mini.Compiler.P.slotOperands
import all Lanius.Mini.Compiler.P.slotStore
import all Lanius.Mini.Compiler.P.compileFunc
import all Lanius.Mini.Compiler.P.roomFits
import all Lanius.Mini.Unique

@[expose] public section

/-! # A function's compiled code: its slots, size and numbers (F14)

The facts the open leaf `CompileFuncSlotsV2` states for `compileFunc`'s code,
by induction over `compileExpr`, `compileArgs` and `compileStmt`:

* slots (`codeSlotReach`): a body that is `Stmt.within locals` names locals
  below `locals`, and its temporaries sit at `locals + depth` with
  `depth < Stmt.temps` (`reach_compileStmt`);
* size: at most 64 bytes per unit of weight (`codeSize_le`, Mini/Room), which
  the room check bounds by `imageLimit`;
* numbers (`nb`): the statement's own, its temporaries' slots and its jump
  targets, which are positions in the code (`nb_compileStmt`). -/

set_option linter.unusedSimpArgs false

namespace Lanius.Faithful.SelfPre

open Lanius.Mini

theorem codeSlotReach_append : ∀ a b : List Instr,
    codeSlotReach (a ++ b) = max (codeSlotReach a) (codeSlotReach b)
  | [], b => by simp [codeSlotReach]
  | i :: a, b => by
    simp only [List.cons_append, codeSlotReach, codeSlotReach_append a b]; omega

theorem nb_append {α : Type} [NB α] : ∀ a b : List α, nb (a ++ b) = max (nb a) (nb b)
  | [], b => by simp only [List.nil_append, nb_nil]; omega
  | i :: a, b => by simp only [List.cons_append, nb_cons, nb_append a b]; omega

/-! ## Slots -/

theorem reach_compileExpr (locals : Nat) : ∀ (e : Expr) (depth : Nat), Expr.within e locals = true →
    codeSlotReach (compileExpr locals e depth) ≤ locals + depth + Expr.temps e
  | .lit _, _, _ => by simp [compileExpr, codeSlotReach, slotReach]
  | .var i, _, h => by
    simp only [Expr.within, decide_eq_true_eq] at h
    simp only [compileExpr, codeSlotReach, slotReach, Expr.temps]; omega
  | .neg o, d, h => by
    simp only [Expr.within] at h
    have := reach_compileExpr locals o d h
    simp only [compileExpr, codeSlotReach_append, codeSlotReach, slotReach, Expr.temps]; omega
  | .binary _ _ l r, d, h => by
    simp only [Expr.within, Bool.and_eq_true] at h
    have := reach_compileExpr locals l d h.1
    have := reach_compileExpr locals r (d + 1) h.2
    simp only [compileExpr, codeSlotReach_append, codeSlotReach, slotReach, Expr.temps]; omega
  | .compare _ _ l r, d, h => by
    simp only [Expr.within, Bool.and_eq_true] at h
    have := reach_compileExpr locals l d h.1
    have := reach_compileExpr locals r (d + 1) h.2
    simp only [compileExpr, codeSlotReach_append, codeSlotReach, slotReach, Expr.temps]; omega
  | .fp _ l r, d, h => by
    simp only [Expr.within, Bool.and_eq_true] at h
    have := reach_compileExpr locals l d h.1
    have := reach_compileExpr locals r (d + 1) h.2
    simp only [compileExpr, codeSlotReach_append, codeSlotReach, slotReach, Expr.temps]; omega

theorem reach_compileArgs (locals : Nat) : ∀ (args : List Expr) (k : Nat), allWithin locals args = true →
    codeSlotReach (compileArgs locals args k) ≤ locals + argsTemps args k
  | [], _, _ => by simp [compileArgs, codeSlotReach]
  | a :: rest, k, h => by
    simp only [allWithin, Bool.and_eq_true] at h
    have := reach_compileExpr locals a (k + 1) h.1
    have := reach_compileArgs locals rest (k + 1) h.2
    simp only [compileArgs, codeSlotReach_append, codeSlotReach, slotReach, argsTemps]; omega

theorem length_argSlots (base : Nat) : ∀ (args : List Expr) (k : Nat), (argSlots base args k).length = args.length
  | [], _ => rfl
  | _ :: rest, k => by simp only [argSlots, List.length_cons, length_argSlots base rest (k + 1)]

/-- Arguments from position k on: their temporaries reach past `k` by their number. -/
theorem length_le_argsTemps : ∀ (args : List Expr) (k : Nat), args.length + k ≤ max k (argsTemps args k)
  | [], k => by simp [argsTemps]
  | _ :: rest, k => by
    have := length_le_argsTemps rest (k + 1)
    simp only [argsTemps, List.length_cons]; omega

theorem top_argSlots (base : Nat) : ∀ (args : List Expr) (k : Nat),
    listSlotTop (argSlots base args k) ≤ base + argsTemps args k
  | [], _ => by simp [argSlots, listSlotTop]
  | _ :: rest, k => by
    have := top_argSlots base rest (k + 1)
    simp only [argSlots, listSlotTop, argsTemps]; omega

theorem reach_compileStmt (locals : Nat) (arities : List Arity) (results : Nat) :
    ∀ (s : Stmt) (pos brk cont : Nat), Stmt.within s locals arities results = true →
      codeSlotReach (compileStmt locals pos brk cont s) ≤ locals + Stmt.temps s
  | .skip, _, _, _, _ => by simp [compileStmt, codeSlotReach]
  | .assign i v, _, _, _, h => by
    simp only [Stmt.within, Bool.and_eq_true, decide_eq_true_eq] at h
    have := reach_compileExpr locals v 0 h.2
    simp only [compileStmt, codeSlotReach_append, codeSlotReach, slotReach, Stmt.temps]; omega
  | .seq a b, pos, brk, cont, h => by
    simp only [Stmt.within, Bool.and_eq_true] at h
    have := reach_compileStmt locals arities results a pos brk cont h.1
    have := reach_compileStmt locals arities results b
      (pos + codeSize (compileStmt locals pos brk cont a)) brk cont h.2
    simp only [compileStmt, codeSlotReach_append, Stmt.temps]; omega
  | .ite c t e, pos, brk, cont, h => by
    simp only [Stmt.within, Bool.and_eq_true] at h
    have := reach_compileExpr locals c 0 h.1.1
    have ht := reach_compileStmt locals arities results t
      (pos + codeSize (compileExpr locals c 0) + 9) brk cont h.1.2
    have he := reach_compileStmt locals arities results e
      (pos + codeSize (compileExpr locals c 0) + 9 +
        codeSize (compileStmt locals (pos + codeSize (compileExpr locals c 0) + 9) brk cont t) + 5) brk cont h.2
    simp only [compileStmt, codeSlotReach_append, codeSlotReach, slotReach, Stmt.temps]; omega
  | .loop c body, pos, brk, cont, h => by
    simp only [Stmt.within, Bool.and_eq_true] at h
    have := reach_compileExpr locals c 0 h.1
    have := reach_compileStmt locals arities results body
      (pos + codeSize (compileExpr locals c 0) + 9) (pos + codeSize (compileExpr locals c 0)) pos h.2
    simp only [compileStmt, codeSlotReach_append, codeSlotReach, slotReach, Stmt.temps]; omega
  | .call target count callee args, _, _, _, h => by
    simp only [Stmt.within, Bool.and_eq_true, decide_eq_true_eq] at h
    have := reach_compileArgs locals args 0 h.2
    have := top_argSlots locals args 0
    have := length_le_argsTemps args 0
    simp only [compileStmt, codeSlotReach_append, codeSlotReach, slotReach, Stmt.temps,
      length_argSlots]; omega
  | .ret values, _, _, _, h => by
    simp only [Stmt.within, Bool.and_eq_true, decide_eq_true_eq] at h
    have := reach_compileArgs locals values 0 h.2
    have := top_argSlots locals values 0
    have := length_le_argsTemps values 0
    simp only [compileStmt, codeSlotReach_append, codeSlotReach, slotReach, Stmt.temps,
      length_argSlots]; omega
  | .brk, _, _, _, _ => by simp [compileStmt, codeSlotReach, slotReach]
  | .cont, _, _, _, _ => by simp [compileStmt, codeSlotReach, slotReach]
  | .alloc target _ size, _, _, _, h => by
    simp only [Stmt.within, Bool.and_eq_true, decide_eq_true_eq] at h
    have := reach_compileExpr locals size 0 h.2
    simp only [compileStmt, codeSlotReach_append, codeSlotReach, slotReach, Stmt.temps,
      List.cons_append]; omega
  | .loadByte target address, _, _, _, h => by
    simp only [Stmt.within, Bool.and_eq_true, decide_eq_true_eq] at h
    have := reach_compileExpr locals address 0 h.2
    simp only [compileStmt, codeSlotReach_append, codeSlotReach, slotReach, Stmt.temps,
      List.cons_append]; omega
  | .storeByte address value, _, _, _, h => by
    simp only [Stmt.within, Bool.and_eq_true] at h
    have := reach_compileExpr locals address 0 h.1
    have := reach_compileExpr locals value 1 h.2
    simp only [compileStmt, codeSlotReach_append, codeSlotReach, slotReach, Stmt.temps]; omega
  | .loadWord _ target address, _, _, _, h => by
    simp only [Stmt.within, Bool.and_eq_true, decide_eq_true_eq] at h
    have := reach_compileExpr locals address 0 h.2
    simp only [compileStmt, codeSlotReach_append, codeSlotReach, slotReach, Stmt.temps,
      List.cons_append]; omega
  | .storeWord _ address value, _, _, _, h => by
    simp only [Stmt.within, Bool.and_eq_true] at h
    have := reach_compileExpr locals address 0 h.1
    have := reach_compileExpr locals value 1 h.2
    simp only [compileStmt, codeSlotReach_append, codeSlotReach, slotReach, Stmt.temps]; omega
  | .divide _ _ target l r, _, _, _, h => by
    simp only [Stmt.within, Bool.and_eq_true, decide_eq_true_eq] at h
    have := reach_compileExpr locals l 0 h.1.2
    have := reach_compileExpr locals r 1 h.2
    simp only [compileStmt, codeSlotReach_append, codeSlotReach, slotReach, Stmt.temps,
      List.cons_append]; omega
  | .sys _ target args, _, _, _, h => by
    simp only [Stmt.within, Bool.and_eq_true, decide_eq_true_eq] at h
    have := reach_compileArgs locals args 0 h.2
    have := length_le_argsTemps args 0
    simp only [compileStmt, codeSlotReach_append, codeSlotReach, slotReach, Stmt.temps,
      List.cons_append]; omega
  | .frame target _, _, _, _, h => by
    simp only [Stmt.within, Bool.and_eq_true, decide_eq_true_eq] at h
    simp only [compileStmt, codeSlotReach, slotReach, Stmt.temps]; omega
  | .static target _, _, _, _, h => by
    simp only [Stmt.within, Bool.and_eq_true, decide_eq_true_eq] at h
    simp only [compileStmt, codeSlotReach, slotReach, Stmt.temps]; omega

/-! ## Numbers -/

theorem nb_compileExpr (base : Nat) : ∀ (e : Expr) (depth : Nat),
    nb (compileExpr base e depth) ≤ max (nb e) (base + depth + Expr.temps e)
  | .lit _, _ => by simp only [compileExpr, nb_simp]; omega
  | .var i, _ => by simp only [compileExpr, nb_simp, Expr.temps]; omega
  | .neg o, d => by
    have := nb_compileExpr base o d
    simp only [compileExpr, nb_append, nb_simp, Expr.temps]; omega
  | .binary _ _ l r, d => by
    have := nb_compileExpr base l d
    have := nb_compileExpr base r (d + 1)
    simp only [compileExpr, nb_append, nb_simp, Expr.temps]; omega
  | .compare _ _ l r, d => by
    have := nb_compileExpr base l d
    have := nb_compileExpr base r (d + 1)
    simp only [compileExpr, nb_append, nb_simp, Expr.temps]; omega
  | .fp _ l r, d => by
    have := nb_compileExpr base l d
    have := nb_compileExpr base r (d + 1)
    simp only [compileExpr, nb_append, nb_simp, Expr.temps]; omega

theorem nb_compileArgs (base : Nat) : ∀ (args : List Expr) (k : Nat),
    nb (compileArgs base args k) ≤ max (nb args) (base + argsTemps args k)
  | [], _ => by simp only [compileArgs, nb_simp]; omega
  | a :: rest, k => by
    have := nb_compileExpr base a (k + 1)
    have := nb_compileArgs base rest (k + 1)
    simp only [compileArgs, nb_append, nb_simp, argsTemps]; omega

theorem nb_argSlots (base : Nat) : ∀ (args : List Expr) (k : Nat), nb (argSlots base args k) ≤ base + argsTemps args k
  | [], _ => by simp only [argSlots, nb_simp]; omega
  | _ :: rest, k => by
    have := nb_argSlots base rest (k + 1)
    simp only [argSlots, nb_simp, argsTemps]; omega

/-- A statement's code at `pos`, with `brk` and `cont` and its end below `X`, and its
numbers and temporaries' slots below `X`, has its numbers below `X`. -/
theorem nb_compileStmt (base : Nat) : ∀ (s : Stmt) (pos brk cont X : Nat),
    nb s ≤ X → base + Stmt.temps s ≤ X → brk ≤ X → cont ≤ X →
      pos + codeSize (compileStmt base pos brk cont s) ≤ X → nb (compileStmt base pos brk cont s) ≤ X
  | .skip, _, _, _, _, _, _, _, _, _ => by simp only [compileStmt, nb_simp]; omega
  | .assign i v, _, _, _, X, h1, h2, _, _, _ => by
    have := nb_compileExpr base v 0
    simp only [compileStmt, nb_append, nb_simp, Stmt.temps] at *; omega
  | .seq a b, pos, brk, cont, X, h1, h2, h3, h4, h5 => by
    simp only [compileStmt, codeSize_append, nb_simp, Stmt.temps] at h1 h2 h5
    have := nb_compileStmt base a pos brk cont X (by omega) (by omega) h3 h4 (by omega)
    have := nb_compileStmt base b (pos + codeSize (compileStmt base pos brk cont a)) brk cont X
      (by omega) (by omega) h3 h4 (by omega)
    simp only [compileStmt, nb_append]; omega
  | .ite c t e, pos, brk, cont, X, h1, h2, h3, h4, h5 => by
    simp only [compileStmt, codeSize_append, codeSize, Instr.size, nb_simp, Stmt.temps] at h1 h2 h5
    have := nb_compileExpr base c 0
    have := nb_compileStmt base t (pos + codeSize (compileExpr base c 0) + 9) brk cont X
      (by omega) (by omega) h3 h4 (by omega)
    have := nb_compileStmt base e (pos + codeSize (compileExpr base c 0) + 9 +
        codeSize (compileStmt base (pos + codeSize (compileExpr base c 0) + 9) brk cont t) + 5) brk cont X
      (by omega) (by omega) h3 h4 (by omega)
    simp only [compileStmt, nb_append, nb_simp]; omega
  | .loop c body, pos, brk, cont, X, h1, h2, h3, h4, h5 => by
    simp only [compileStmt, codeSize_append, codeSize, Instr.size, nb_simp, Stmt.temps] at h1 h2 h5
    have := nb_compileExpr base c 0
    have := nb_compileStmt base body (pos + codeSize (compileExpr base c 0) + 9)
      (pos + codeSize (compileExpr base c 0)) pos X (by omega) (by omega) (by omega) (by omega) (by omega)
    simp only [compileStmt, nb_append, nb_simp]; omega
  | .call target count callee args, _, _, _, X, h1, h2, _, _, _ => by
    have := nb_compileArgs base args 0
    have := nb_argSlots base args 0
    simp only [compileStmt, nb_append, nb_simp, Stmt.temps] at *; omega
  | .ret values, _, _, _, X, h1, h2, _, _, _ => by
    have := nb_compileArgs base values 0
    have := nb_argSlots base values 0
    simp only [compileStmt, nb_append, nb_simp, Stmt.temps] at *; omega
  | .brk, _, _, _, X, _, _, h3, _, _ => by simp only [compileStmt, nb_simp]; omega
  | .cont, _, _, _, X, _, _, _, h4, _ => by simp only [compileStmt, nb_simp]; omega
  | .alloc target _ size, _, _, _, X, h1, h2, _, _, _ => by
    have := nb_compileExpr base size 0
    simp only [compileStmt, nb_append, nb_simp, Stmt.temps] at *; omega
  | .loadByte target address, _, _, _, X, h1, h2, _, _, _ => by
    have := nb_compileExpr base address 0
    simp only [compileStmt, nb_append, nb_simp, Stmt.temps] at *; omega
  | .storeByte address value, _, _, _, X, h1, h2, _, _, _ => by
    have := nb_compileExpr base address 0
    have := nb_compileExpr base value 1
    simp only [compileStmt, nb_append, nb_simp, Stmt.temps] at *; omega
  | .loadWord _ target address, _, _, _, X, h1, h2, _, _, _ => by
    have := nb_compileExpr base address 0
    simp only [compileStmt, nb_append, nb_simp, Stmt.temps] at *; omega
  | .storeWord _ address value, _, _, _, X, h1, h2, _, _, _ => by
    have := nb_compileExpr base address 0
    have := nb_compileExpr base value 1
    simp only [compileStmt, nb_append, nb_simp, Stmt.temps] at *; omega
  | .divide _ _ target l r, _, _, _, X, h1, h2, _, _, _ => by
    have := nb_compileExpr base l 0
    have := nb_compileExpr base r 1
    simp only [compileStmt, nb_append, nb_simp, Stmt.temps] at *; omega
  | .sys _ target args, _, _, _, X, h1, h2, _, _, _ => by
    have := nb_compileArgs base args 0
    simp only [compileStmt, nb_append, nb_simp, Stmt.temps] at *; omega
  | .frame target _, _, _, _, X, h1, h2, _, _, _ => by
    simp only [compileStmt, nb_simp, Stmt.temps] at *; omega
  | .static target _, _, _, _, X, h1, h2, _, _, _ => by
    simp only [compileStmt, nb_simp, Stmt.temps] at *; omega

/-! ## The prologue -/

theorem zeroLocals_facts : ∀ (count first : Nat),
    codeSlotReach (zeroLocals first count) ≤ first + count ∧
      codeSize (zeroLocals first count) = 7 * count ∧ nb (zeroLocals first count) ≤ first + count
  | 0, first => by rw [zeroLocals]; simp [codeSlotReach, codeSize]
  | count + 1, first => by
    have := zeroLocals_facts count (first + 1)
    rw [zeroLocals]
    simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel, codeSlotReach, slotReach, codeSize,
      Instr.size, nb_simp]
    omega

/-- `CompileFuncSlotsV2`'s four facts for `compileFunc`'s code. -/
theorem compileFunc_slots (arities : List Arity) (func : Func) (c : Code)
    (h : compileFunc arities func = some c) :
    c.slots ≤ frameLimit ∧ codeSlotReach c.instrs ≤ c.slots ∧ codeSize c.instrs ≤ 2 ^ 40 ∧
      nb c.instrs ≤ max (nb func) (2 ^ 40) := by
  obtain ⟨params, results, locals, body⟩ := func
  unfold compileFunc at h
  split at h
  · rename_i fits
    rw [roomFits_stmtRoom, decide_eq_true_eq] at fits
    dsimp only at h fits
    split at h
    · rename_i ok
      simp only [Bool.and_eq_true, decide_eq_true_eq] at ok
      obtain ⟨⟨⟨⟨hp, _⟩, _⟩, hw⟩, hs⟩ := ok
      simp only [Option.some.injEq] at h
      subst h
      have hz := zeroLocals_facts (locals - params) params
      have hr := reach_compileStmt locals arities results body
        (codeSize (Instr.imm 0 :: zeroLocals params (locals - params))) 0 0 hw
      have hc := codeSize_le locals body (codeSize (Instr.imm 0 :: zeroLocals params (locals - params))) 0 0
      simp only [codeSize, Instr.size] at hr hc
      have hn := nb_compileStmt locals body (10 + codeSize (zeroLocals params (locals - params))) 0 0
        (max (nb (Func.mk params results locals body)) (2 ^ 40))
        (by simp only [nb_simp]; omega) (by simp only [frameLimit] at hs; omega) (by omega) (by omega)
        (by simp only [imageLimit] at fits; simp only [frameLimit] at hs; omega)
      simp only [frameLimit, imageLimit] at hs fits ⊢
      simp only [List.cons_append, codeSlotReach, slotReach, codeSlotReach_append, codeSize,
        codeSize_append, Instr.size, nb_cons, nb_append, nb_Instr_imm] at hn ⊢
      omega
    · simp at h
  · simp at h

end Lanius.Faithful.SelfPre
