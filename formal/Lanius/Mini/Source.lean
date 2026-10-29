module

public import Lanius.Mini.Semantics
public import Lanius.Semantics
public import Lanius.Mini.SourceCore
-- import all: Lanius.Mini.Compiler
import all Lanius.Mini.Compiler.Types
import all Lanius.Mini.Compiler.P.Lists_empty
import all Lanius.Mini.Compiler.P.DivOp_size
import all Lanius.Mini.Compiler.P.codeSize
import all Lanius.Mini.Compiler.P.compileArgs
import all Lanius.Mini.Compiler.P.arities
import all Lanius.Mini.Compiler.P.pow2
import all Lanius.Mini.Compiler.P.moduleExports
import all Lanius.Mini.Compiler.P.importOk
import all Lanius.Mini.Compiler.P.importsOk
import all Lanius.Mini.Compiler.P.modulesOk
import all Lanius.Mini.Compiler.P.moduleFirsts
import all Lanius.Mini.Compiler.P.Instr_pieces
import all Lanius.Mini.Compiler.P.compileModules
import all Lanius.Mini.Compiler.P.render
import all Lanius.Mini.Compiler.P.UintTy_mask
import all Lanius.Mini.Compiler.P.UintTy_isWide
import all Lanius.Mini.Compiler.P.lookup
import all Lanius.Mini.Compiler.P.arithShiftRight
import all Lanius.Mini.Compiler.P.equality
import all Lanius.Mini.Compiler.P.conjunction
import all Lanius.Mini.Compiler.P.lowerLocal
import all Lanius.Mini.Compiler.P.guardAnd
import all Lanius.Mini.Compiler.P.leftTrue
import all Lanius.Mini.Compiler.P.applyGuard
import all Lanius.Mini.Compiler.P.SrcExpr_guard
import all Lanius.Mini.Compiler.P.copyBinding
import all Lanius.Mini.Compiler.P.lowerTagged
import all Lanius.Mini.Compiler.P.armScope
import all Lanius.Mini.Compiler.P.assignFrom
import all Lanius.Mini.Compiler.P.lowerMatchArms
import all Lanius.Mini.Compiler.P.lowerCallSig
import all Lanius.Mini.Compiler.P.consArgs
import all Lanius.Mini.Compiler.P.shortCircuit
import all Lanius.Mini.Compiler.P.evalNot
import all Lanius.Mini.Compiler.P.evalSame
import all Lanius.Mini.Compiler.P.matchDst
import all Lanius.Mini.Compiler.P.matchVariants
import all Lanius.Mini.Compiler.P.lowerSetValues
import all Lanius.Mini.Compiler.P.lowerSetCallArgs
import all Lanius.Mini.Compiler.P.lowerReturn
import all Lanius.Mini.Compiler.P.lowerAddress
import all Lanius.Mini.Compiler.P.structFields
import all Lanius.Mini.Compiler.P.enumVariants
import all Lanius.Mini.Compiler.P.usizeWidth
import all Lanius.Mini.Compiler.P.wordWidth
import all Lanius.Mini.Compiler.P.wordElement
import all Lanius.Mini.Compiler.P.widthOf
import all Lanius.Mini.Compiler.P.elementBase
import all Lanius.Mini.Compiler.P.iteThen
import all Lanius.Mini.Compiler.P.storeType
import all Lanius.Mini.Compiler.P.indexOf
import all Lanius.Mini.Compiler.P.elementAddress
import all Lanius.Mini.Compiler.P.lowerLoadType
import all Lanius.Mini.Compiler.P.storeEvalWord
import all Lanius.Mini.Compiler.P.sigs
import all Lanius.Mini.Compiler.P.lowerBody
import all Lanius.Mini.Compiler.P.declareFuncs
import all Lanius.Mini.Compiler.P.declareProgram
import all Lanius.Mini.Compiler.P.BinOp_folds
import all Lanius.Mini.Compiler.P.Word_compute
import all Lanius.Mini.Compiler.P.Word_narrows
import all Lanius.Mini.Compiler.P.binaryConstant
import all Lanius.Mini.Compiler.P.Expr_agrees
import all Lanius.Mini.Compiler.P.assignAgrees
import all Lanius.Mini.Compiler.P.callAgrees
import all Lanius.Mini.Compiler.P.substAll
import all Lanius.Mini.Compiler.P.Stmt_kills
import all Lanius.Mini.Compiler.P.optKill
import all Lanius.Mini.Compiler.P.optimizeNeg
import all Lanius.Mini.Compiler.P.optimizeLeft
import all Lanius.Mini.Compiler.P.optimizeIte
import all Lanius.Mini.Compiler.P.compileOr
import all Lanius.Mini.Compiler.P.compileSource
import all Lanius.Mini.Compiler.P.larger
import all Lanius.Mini.Compiler.P.Inline_arithOf
import all Lanius.Mini.Compiler.P.Inline_lowerSetScalar
import all Lanius.Mini.Compiler.P.Inline_branchAgrees
-- end import all
-- import parts: Lanius.Mini.Compiler BinOp.size Code.size DivOp.size Instr.size Piece.size SrcType.isI32 SrcType.isScalar SrcType.isUint SrcType.same SrcType.size arith boolBits compileOptimized compileSource declareProgram enumVariants fieldOffset funcsReturn lowerFuncs maxSize offsetOrArith sigs sizes storeEvalThen storeEvalWord structFields
public import Lanius.Mini.Compiler.P.DivOp_size
public import Lanius.Mini.Compiler.P.Lists_empty
public import Lanius.Mini.Compiler.P.arithShiftRight
public import Lanius.Mini.Compiler.P.compileModules
public import Lanius.Mini.Compiler.P.compileOr
public import Lanius.Mini.Compiler.P.compileSource
public import Lanius.Mini.Compiler.P.declareProgram
public import Lanius.Mini.Compiler.P.enumVariants
public import Lanius.Mini.Compiler.P.lookup
public import Lanius.Mini.Compiler.P.lowerBody
public import Lanius.Mini.Compiler.P.lowerLoadType
public import Lanius.Mini.Compiler.P.pow2
public import Lanius.Mini.Compiler.P.sigs
public import Lanius.Mini.Compiler.P.storeEvalWord
public import Lanius.Mini.Compiler.P.structFields
-- end import parts

@[expose] public section

/-! The Core meaning of source programs, and how a Core value sits in a slot.

`SrcProgram.toCore` is the specification side of the front pass: each source
construct is the Core construct of the same name, with functions numbered by
position. The theorem in `SourceCorrect.lean` is about Core's own evaluator
(`Lanius.Semantics.evalExpr`) on that program. -/

namespace Lanius.Mini

open Lanius.Core (Value)

/-- The struct and enum declarations the front pass derives from the
program's types (`declareProgram`); none for a program it rejects. -/
def SrcProgram.decls (prog : SrcProgram) : SrcDecls :=
  match declareProgram prog with
  | none => { structs := [], enums := [] }
  | some decls => decls

/-- Functions numbered by position, and one struct or enum declaration per
type id the program's types name. -/
def SrcProgram.toCore (prog : SrcProgram) : Core.Program where
  structures := prog.decls.structs.map SrcStructDecl.toCore
  enumerations := prog.decls.enums.map SrcEnumDecl.toCore
  functions := coreFuncs 0 prog.funcs

/-- What `compileSource` checks before it optimizes and compiles the lowered
functions. -/
theorem compileSource_some {sp : SrcProgram} {binary : Binary} (compiled : compileSource sp = some binary) :
    funcsReturn sp.funcs = true ∧ (∃ decls, declareProgram sp = some decls) ∧
      ∃ funcs, lowerFuncs (sigs sp.funcs) sp.decls sp.funcs = some funcs ∧
        compileOptimized { funcs := funcs } = some binary := by
  unfold compileSource at compiled
  split at compiled
  · rename_i returns
    unfold compileDeclared at compiled
    split at compiled
    · simp at compiled
    · rename_i decls found
      have same : sp.decls = decls := by simp [SrcProgram.decls, found]
      unfold compileLowered at compiled
      split at compiled
      · simp at compiled
      · rename_i funcs lowered
        exact ⟨returns, ⟨decls, found⟩, funcs, same ▸ lowered, compiled⟩
  · simp at compiled

theorem find_structs : ∀ (decls : List SrcStructDecl) (id : Nat),
    (decls.map SrcStructDecl.toCore).find? (fun decl => decl.id == id) =
      (structFields decls id).map fun fs => ⟨id, fs.map SrcType.toCore⟩
  | [], _ => rfl
  | decl :: rest, id => by
    simp only [List.map_cons, List.find?_cons, structFields]
    by_cases same : decl.id = id
    · simp [same, SrcStructDecl.toCore]
    · have ne : (decl.id == id) = false := by simpa using same
      simp [same, ne, SrcStructDecl.toCore, find_structs rest id]

theorem find_enums : ∀ (decls : List SrcEnumDecl) (id : Nat),
    (decls.map SrcEnumDecl.toCore).find? (fun decl => decl.id == id) =
      (enumVariants decls id).map fun vs => ⟨id, vs.map (List.map SrcType.toCore)⟩
  | [], _ => rfl
  | decl :: rest, id => by
    simp only [List.map_cons, List.find?_cons, enumVariants]
    by_cases same : decl.id = id
    · simp [same, SrcEnumDecl.toCore]
    · have ne : (decl.id == id) = false := by simpa using same
      simp [same, ne, SrcEnumDecl.toCore, find_enums rest id]

/-- A struct the front pass declared is declared in the program's Core meaning. -/
theorem structFields_toCore {sp : SrcProgram} {id : Nat} {fs : List SrcType}
    (found : structFields sp.decls.structs id = some fs) :
    sp.toCore.structure? id = some ⟨id, fs.map SrcType.toCore⟩ := by
  simp only [Core.Program.structure?, SrcProgram.toCore, find_structs, found, Option.map_some]

/-- What `offsetOrArith` accepts: an address moved by a `usize`, or arithmetic. -/
theorem offsetOrArith_some {op : BinOp} {l r t : Typed} (h : offsetOrArith op l r = some t) :
    (l.ty = .ptr ∧ r.ty = .uint .usize ∧ t = { expr := .binary .u64 op l.expr r.expr, ty := .ptr }) ∨
      arith op l r = some t := by
  unfold offsetOrArith at h
  split at h
  · rename_i cond
    simp only [Bool.and_eq_true] at cond
    obtain ⟨hp, hu⟩ := cond
    simp only [Option.some.injEq] at h
    refine .inl ⟨?_, ?_, h.symm⟩
    · cases hty : l.ty <;> simp [hty, SrcType.isPtr] at hp ⊢
    · cases hty : r.ty <;> simp [hty, SrcType.isUint] at hu ⊢
      rename_i k
      cases k <;> simp [UintTy.code] at hu ⊢
  · exact .inr h

/-- Core's `ptr + usize` and `ptr - usize` on x86: the address wraps at 2^64. -/
theorem eval_ptr_add (a o : BitVec 64) :
    Semantics.evalBinaryValue .x86_64 .add (.pointer a.toNat) (.unsigned .usize o.toNat) = .ok (.pointer (a + o).toNat) := by
  simp only [Semantics.evalBinaryValue, Semantics.pointerOffset, Bool.false_eq_true, if_false, Except.ok.injEq,
    Core.Value.pointer.injEq, BitVec.toNat_add]
  rw [show (2 : Int) ^ Core.Target.x86_64.pointerWidth.bits = 2 ^ 64 from rfl]
  have h : (Int.ofNat a.toNat + Int.ofNat o.toNat) % 2 ^ 64 = (((a.toNat + o.toNat) % 2 ^ 64 : Nat) : Int) := by
    simp only [Int.ofNat_eq_natCast]
    omega
  rw [h, Int.toNat_natCast]

theorem eval_ptr_sub (a o : BitVec 64) :
    Semantics.evalBinaryValue .x86_64 .subtract (.pointer a.toNat) (.unsigned .usize o.toNat) = .ok (.pointer (a - o).toNat) := by
  simp only [Semantics.evalBinaryValue, Semantics.pointerOffset, if_true, Except.ok.injEq,
    Core.Value.pointer.injEq, BitVec.toNat_sub]
  rw [show (2 : Int) ^ Core.Target.x86_64.pointerWidth.bits = 2 ^ 64 from rfl]
  have := a.isLt
  have := o.isLt
  have h : (Int.ofNat a.toNat - Int.ofNat o.toNat) % 2 ^ 64 =
      (((2 ^ 64 - o.toNat + a.toNat) % 2 ^ 64 : Nat) : Int) := by
    simp only [Int.ofNat_eq_natCast]
    omega
  rw [h, Int.toNat_natCast]

theorem enumVariants_toCore {sp : SrcProgram} {id : Nat} {vs : List (List SrcType)}
    (found : enumVariants sp.decls.enums id = some vs) :
    sp.toCore.enumeration? id = some ⟨id, vs.map (List.map SrcType.toCore)⟩ := by
  simp only [Core.Program.enumeration?, SrcProgram.toCore, find_enums, found, Option.map_some]

/-- `ty.Holds value bits`: one slot holding `bits` represents the Core `value`
of scalar type `ty`. An `i32` is its bits zero-extended; booleans are 1 and 0;
an unsigned value is the slot's number, below its type's bound; a pointer is
its address. -/
def SrcType.Holds : SrcType → Value → BitVec 64 → Prop
  | .i32, value, bits => value = .signed .i32 (low bits).toInt ∧ bits = widen (low bits)
  | .bool, value, bits => ∃ b, value = .boolean b ∧ bits = boolBits b
  | .uint kind, value, bits => value = .unsigned kind.toCore bits.toNat ∧ bits.toNat < 2 ^ kind.width
  | .struct _ _, _, _ => False
  | .enum _ _, _, _ => False
  | .ptr, value, bits => value = .pointer bits.toNat
  | .slice _, _, _ => False
  | .unit, _, _ => False
  | .isize, value, bits => value = .signed .isize bits.toInt

mutual
/-- `ty.HoldsAt value env slot`: the `ty.size` slots of `env` from `slot`
represent `value`. A struct's fields follow one another; an enum's tag is its
variant number, and its payload follows. -/
inductive SrcType.HoldsAt : SrcType → Value → Env → Nat → Prop where
  | i32 {value : Value} {env : Env} {slot : Nat} :
      SrcType.i32.Holds value (env slot) → SrcType.HoldsAt .i32 value env slot
  | bool {value : Value} {env : Env} {slot : Nat} :
      SrcType.bool.Holds value (env slot) → SrcType.HoldsAt .bool value env slot
  | uint {kind : UintTy} {value : Value} {env : Env} {slot : Nat} :
      (SrcType.uint kind).Holds value (env slot) → SrcType.HoldsAt (.uint kind) value env slot
  | struct {id : Nat} {fields : List SrcType} {vs : List Value} {env : Env} {slot : Nat} :
      FieldsHold fields vs env slot → SrcType.HoldsAt (.struct id fields) (.structure id vs) env slot
  | enum {id : Nat} {variants : List (List SrcType)} {k : Nat} {fs : List SrcType} {vs : List Value}
      {env : Env} {slot : Nat} :
      variants[k]? = some fs → env slot = BitVec.ofNat 64 k → FieldsHold fs vs env (slot + 1) →
      SrcType.HoldsAt (.enum id variants) (.enumeration id k vs) env slot
  | ptr {value : Value} {env : Env} {slot : Nat} :
      SrcType.ptr.Holds value (env slot) → SrcType.HoldsAt .ptr value env slot
  /-- A raw slice is its address, then its length, which is below `2 ^ 31`
  (an `i32`'s bound), so an `i32` index below 0, a word of at least `2 ^ 31`,
  is not below it. -/
  | slice {element : SrcType} {length : Nat} {env : Env} {slot : Nat} :
      (env (slot + 1)).toNat = length → length < 2 ^ 31 →
      SrcType.HoldsAt (.slice element) (.rawSlice element.toCore (env slot).toNat length) env slot
  /-- The unit value's one slot holds any bits. -/
  | unit {env : Env} {slot : Nat} : SrcType.HoldsAt .unit .unit env slot
  | isize {value : Value} {env : Env} {slot : Nat} :
      SrcType.isize.Holds value (env slot) → SrcType.HoldsAt .isize value env slot

/-- Values of these types, one after another from `slot`: a struct's fields,
a payload, or arguments. -/
inductive FieldsHold : List SrcType → List Value → Env → Nat → Prop where
  | nil {env : Env} {slot : Nat} : FieldsHold [] [] env slot
  | cons {ty : SrcType} {tys : List SrcType} {v : Value} {vs : List Value} {env : Env} {slot : Nat} :
      ty.HoldsAt v env slot → FieldsHold tys vs env (slot + ty.size) → FieldsHold (ty :: tys) (v :: vs) env slot
end

theorem SrcType.holdsAt_scalar {ty : SrcType} (scalar : ty.isScalar = true) {v : Value} {env : Env}
    {slot : Nat} : ty.HoldsAt v env slot ↔ ty.Holds v (env slot) := by
  cases ty with
  | i32 => exact ⟨fun | .i32 h => h, .i32⟩
  | bool => exact ⟨fun | .bool h => h, .bool⟩
  | uint => exact ⟨fun | .uint h => h, .uint⟩
  | struct => simp [SrcType.isScalar] at scalar
  | enum => simp [SrcType.isScalar] at scalar
  | ptr => exact ⟨fun | .ptr h => h, .ptr⟩
  | slice => simp [SrcType.isScalar] at scalar
  | unit => simp [SrcType.isScalar] at scalar
  | isize => exact ⟨fun | .isize h => h, .isize⟩

theorem FieldsHold.length : ∀ {fs vs env slot}, FieldsHold fs vs env slot → vs.length = fs.length
  | [], _, _, _, .nil => rfl
  | _ :: _, _, _, _, .cons _ rest => by simp [rest.length]

theorem sizes_le_maxSize : ∀ {variants : List (List SrcType)} {k : Nat} {fs : List SrcType},
    variants[k]? = some fs → sizes fs ≤ maxSize variants
  | [], _, _, found => by simp at found
  | v :: rest, 0, fs, found => by
    simp only [List.getElem?_cons_zero, Option.some.injEq] at found
    subst found
    simp only [maxSize]
    omega
  | v :: rest, k + 1, fs, found => by
    simp only [List.getElem?_cons_succ] at found
    have := sizes_le_maxSize found
    simp only [maxSize]
    omega

mutual
theorem SrcType.HoldsAt.congr : ∀ {ty : SrcType} {v : Value} {env : Env} {slot : Nat},
    ty.HoldsAt v env slot → ∀ {env' : Env} {slot' : Nat},
      (∀ i < ty.size, env' (slot' + i) = env (slot + i)) → ty.HoldsAt v env' slot'
  | .i32, _, _, _, .i32 holds, _, _, agree => by
    have := agree 0 (by simp [SrcType.size])
    simp only [Nat.add_zero] at this
    exact .i32 (by rw [this]; exact holds)
  | .bool, _, _, _, .bool holds, _, _, agree => by
    have := agree 0 (by simp [SrcType.size])
    simp only [Nat.add_zero] at this
    exact .bool (by rw [this]; exact holds)
  | .uint _, _, _, _, .uint holds, _, _, agree => by
    have := agree 0 (by simp [SrcType.size])
    simp only [Nat.add_zero] at this
    exact .uint (by rw [this]; exact holds)
  | .struct _ fields, _, _, _, .struct holds, _, _, agree =>
    .struct (FieldsHold.congr holds fun i below => agree i (by simp only [SrcType.size]; exact below))
  | .enum _ variants, _, _, slot, .enum found tag payload, _, slot', agree => by
    have bound := sizes_le_maxSize found
    refine .enum found ?_ (FieldsHold.congr payload fun i below => ?_)
    · have := agree 0 (by simp only [SrcType.size]; omega)
      simp only [Nat.add_zero] at this
      rw [this, tag]
    · have := agree (i + 1) (by simp only [SrcType.size]; omega)
      rw [show slot' + 1 + i = slot' + (i + 1) by omega, this]
      congr 1
      omega
  | .ptr, _, _, _, .ptr holds, _, _, agree => by
    have := agree 0 (by simp [SrcType.size])
    simp only [Nat.add_zero] at this
    exact .ptr (by rw [this]; exact holds)
  | .slice _, _, _, _, .slice len small, _, _, agree => by
    have := agree 0 (by simp [SrcType.size])
    have second := agree 1 (by simp [SrcType.size])
    simp only [Nat.add_zero] at this
    rw [← this]
    exact .slice (by rw [second]; exact len) small
  | .unit, _, _, _, .unit, _, _, _ => .unit
  | .isize, _, _, _, .isize holds, _, _, agree => by
    have := agree 0 (by simp [SrcType.size])
    simp only [Nat.add_zero] at this
    exact .isize (by rw [this]; exact holds)

theorem FieldsHold.congr : ∀ {fs : List SrcType} {vs : List Value} {env : Env} {slot : Nat},
    FieldsHold fs vs env slot → ∀ {env' : Env} {slot' : Nat},
      (∀ i < sizes fs, env' (slot' + i) = env (slot + i)) → FieldsHold fs vs env' slot'
  | [], _, _, _, .nil, _, _, _ => .nil
  | ty :: tys, _, _, slot, .cons head rest, _, slot', agree => by
    refine .cons (SrcType.HoldsAt.congr head fun i below => agree i (by simp only [sizes]; omega))
      (FieldsHold.congr rest fun i below => ?_)
    have := agree (ty.size + i) (by simp only [sizes]; omega)
    rw [show slot' + ty.size + i = slot' + (ty.size + i) by omega, this]
    congr 1
    omega
end

theorem fieldOffset_zero (fs : List SrcType) : fieldOffset fs 0 = 0 := by
  cases fs <;> simp [fieldOffset]

theorem fieldOffset_succ (ty : SrcType) (rest : List SrcType) (k : Nat) :
    fieldOffset (ty :: rest) (k + 1) = ty.size + fieldOffset rest k := by
  simp [fieldOffset]

/-- Field `k`, at its offset. -/
theorem FieldsHold.get : ∀ {fs vs env slot}, FieldsHold fs vs env slot → ∀ {k : Nat} {f : SrcType},
    fs[k]? = some f → ∃ v, vs[k]? = some v ∧ f.HoldsAt v env (slot + fieldOffset fs k)
  | [], _, _, _, .nil, _, _, found => by simp at found
  | _ :: _, _, _, _, .cons head rest, k, f, found => by
    cases k with
    | zero =>
      simp only [List.getElem?_cons_zero, Option.some.injEq] at found
      subst found
      exact ⟨_, rfl, by simpa [fieldOffset] using head⟩
    | succ k =>
      simp only [List.getElem?_cons_succ] at found ⊢
      obtain ⟨v, got, holdsV⟩ := rest.get found
      exact ⟨v, got, by rw [fieldOffset_succ, ← Nat.add_assoc]; exact holdsV⟩

theorem fieldOffset_lt : ∀ {fs : List SrcType} {k : Nat} {f : SrcType}, fs[k]? = some f →
    fieldOffset fs k + f.size ≤ sizes fs
  | [], _, _, found => by simp at found
  | ty :: rest, 0, f, found => by
    simp only [List.getElem?_cons_zero, Option.some.injEq] at found
    subst found
    simp [fieldOffset, sizes]
  | ty :: rest, k + 1, f, found => by
    simp only [List.getElem?_cons_succ] at found
    have := fieldOffset_lt found
    rw [fieldOffset_succ]
    simp only [sizes]
    omega

theorem SrcType.size_scalar {ty : SrcType} (scalar : ty.isScalar = true) : ty.size = 1 := by
  cases ty <;> simp_all [SrcType.isScalar, SrcType.size]

/-- Storing a scalar field `k`. -/
theorem FieldsHold.set : ∀ {fs vs env slot}, FieldsHold fs vs env slot → ∀ {k : Nat} {f : SrcType},
    fs[k]? = some f → f.isScalar = true → ∀ {nv : Value} {x : BitVec 64}, f.Holds nv x →
      FieldsHold fs (Semantics.setValue vs k nv) (env.set (slot + fieldOffset fs k) x) slot
  | [], _, _, _, .nil, _, _, found, _, _, _, _ => by simp at found
  | ty :: tys, v :: vs, env, slot, .cons head rest, k, f, found, scalar, nv, x, holdsNew => by
    cases k with
    | zero =>
      simp only [List.getElem?_cons_zero, Option.some.injEq] at found
      subst found
      have one := SrcType.size_scalar scalar
      refine .cons ((SrcType.holdsAt_scalar scalar).mpr (by simpa [Env.set, fieldOffset_zero] using holdsNew))
        (rest.congr fun i _ => ?_)
      simp only [Env.set, fieldOffset_zero]
      rw [if_neg (by omega)]
    | succ k =>
      simp only [List.getElem?_cons_succ] at found
      refine .cons (head.congr fun i below => ?_) ?_
      · simp only [Env.set]
        rw [fieldOffset_succ, if_neg (by omega)]
      · rw [fieldOffset_succ, ← Nat.add_assoc]
        exact rest.set found scalar holdsNew

theorem toInt_emod (x : BitVec 32) : x.toInt % 4294967296 = (x.toNat : Int) := by
  rw [BitVec.toInt_eq_toNat_bmod]
  have := x.isLt
  simp only [Int.bmod]
  split <;> omega

theorem wrap_add (x y : BitVec 32) :
    Semantics.wrapSigned Core.Target.x86_64 .i32 (x.toInt + y.toInt) = (x + y).toInt := by
  rw [wrapSigned_i32, BitVec.toInt_ofInt, BitVec.toInt_add]

theorem wrap_sub (x y : BitVec 32) :
    Semantics.wrapSigned Core.Target.x86_64 .i32 (x.toInt - y.toInt) = (x - y).toInt := by
  rw [wrapSigned_i32, BitVec.toInt_ofInt, BitVec.toInt_sub]

theorem wrap_mul (x y : BitVec 32) :
    Semantics.wrapSigned Core.Target.x86_64 .i32 (x.toInt * y.toInt) = (x * y).toInt := by
  rw [wrapSigned_i32, BitVec.toInt_ofInt, BitVec.toInt_mul]

theorem wrap_neg (x : BitVec 32) :
    Semantics.wrapSigned Core.Target.x86_64 .i32 (-x.toInt) = (-x).toInt := by
  rw [wrapSigned_i32, BitVec.toInt_ofInt, BitVec.toInt_neg]

theorem wrap_nat (n : Nat) :
    Semantics.wrapSigned Core.Target.x86_64 .i32 (Int.ofNat n) = (BitVec.ofNat 32 n).toInt := by
  rw [wrapSigned_i32]
  congr 1

@[simp] theorem low_widen (x : BitVec 32) : low (widen x) = x := by
  simp only [low, widen]
  rw [BitVec.setWidth_setWidth_of_le _ (by decide), BitVec.setWidth_eq]

theorem holds_i32 (x : BitVec 32) : SrcType.i32.Holds (.signed .i32 x.toInt) (widen x) := by
  simp [SrcType.Holds]

theorem boolBits_ne_zero (b : Bool) : (boolBits b ≠ 0) = (b = true) := by
  cases b <;> simp [boolBits]

/-- The checks of an effectful word element store. -/
theorem storeEvalThen_cond {i v : Evaluated} {e : SrcType} {slot : Nat} {g : Expr} {store : Option Stmt} {s : Stmt}
    (h : storeEvalThen i v e slot g store = some s) :
    ((i.ty.isI32 || i.ty.isUint .usize) && v.ty.same e) = true := by
  simp only [storeEvalThen] at h
  split at h
  · assumption
  · simp at h

theorem storeEvalWord_cond {decls : SrcDecls} {b : Binding} {e : SrcType} {slot : Nat} {i v : Evaluated}
    {s : Stmt} (h : storeEvalWord decls b e slot i v = some s) :
    ((i.ty.isI32 || i.ty.isUint .usize) && v.ty.same e) = true := by
  simp only [storeEvalWord] at h
  split at h
  · exact storeEvalThen_cond h
  · simp at h

end Lanius.Mini
