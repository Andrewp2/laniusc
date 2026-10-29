module

public import Lanius.Mini.Semantics
public import Lanius.Mini.Unsigned
public import Lanius.Mini.Shifts
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
-- import parts: Lanius.Mini.Compiler SrcExpr.lower SrcOp.lower SrcStmt.lower UintTy.code
public import Lanius.Mini.Compiler.P.conjunction
public import Lanius.Mini.Compiler.P.lowerLocal
public import Lanius.Mini.Compiler.P.render
public import Lanius.Mini.Compiler.P.storeEvalWord
-- end import parts

@[expose] public section

/-! Expressions: a lowered subset expression evaluates in Core without changing
the state, to a value its lowered mini expression represents. -/

namespace Lanius.Mini

open Lanius.Core (Value)
open Lanius.Semantics (State evalExpr)

/-- Core's locals are the scope's bindings in the same order, each slot's cell
given by `frame`, and every binding's cell holds a value its slot represents. -/
structure Corr (scope : List Binding) (frame : Nat → Nat) (st : State) (env : Env) : Prop where
  locals : st.locals = scope.map fun b => (b.id, frame b.slot)
  values : ∀ b ∈ scope, ∃ v, st.cellEntry? (frame b.slot) = some ⟨frame b.slot, some v⟩ ∧
    b.ty.HoldsAt v env b.slot

theorem lookup_mem {scope : List Binding} {id : Nat} {b : Binding}
    (found : lookup scope id = some b) : b ∈ scope ∧ b.id = id := by
  induction scope with
  | nil => simp [lookup] at found
  | cons head rest ih =>
    simp only [lookup] at found
    split at found
    · cases found; exact ⟨List.mem_cons_self .., by assumption⟩
    · exact ⟨List.mem_cons_of_mem _ (ih found).1, (ih found).2⟩

theorem find_locals (scope : List Binding) (frame : Nat → Nat) (id : Nat) :
    (scope.map fun b => (b.id, frame b.slot)).find? (fun binding => binding.1 == id) =
      (lookup scope id).map fun b => (b.id, frame b.slot) := by
  induction scope with
  | nil => rfl
  | cons head rest ih =>
    simp only [List.map_cons, List.find?_cons, lookup]
    by_cases h : head.id = id
    · simp [h]
    · have : (head.id == id) = false := by simpa using h
      simp [h, ih, this]

theorem Corr.cellId {scope frame st env} (corr : Corr scope frame st env) (id : Nat) :
    st.cellId? id = (lookup scope id).map fun b => frame b.slot := by
  simp only [State.cellId?, corr.locals, find_locals, Option.map_map]
  rfl

theorem Corr.local {scope frame st env} (corr : Corr scope frame st env) {id : Nat} {b : Binding}
    (found : lookup scope id = some b) (fuel : Nat) (prog : Core.Program) :
    ∃ v, evalExpr (fuel + 1) prog st (.local id) = .done v st ∧ b.ty.HoldsAt v env b.slot := by
  obtain ⟨v, entry, holds⟩ := corr.values b (lookup_mem found).1
  refine ⟨v, ?_, holds⟩
  simp only [evalExpr, corr.cellId, found, Option.map_some, entry]

/-- A Core binary operation other than && and || evaluates both sides. -/
theorem binary_sound {prog : Core.Program} {st : State} {env : Env} {l r : Core.Expr}
    {tl tr : Typed} {cop : Core.BinaryOp} {fuel : Nat} {v : Value} {st' : State}
    (hl : ∀ {fuel v st'}, evalExpr fuel prog st l = .done v st' →
      st' = st ∧ tl.ty.Holds v (tl.expr.eval env))
    (hr : ∀ {fuel v st'}, evalExpr fuel prog st r = .done v st' →
      st' = st ∧ tr.ty.Holds v (tr.expr.eval env))
    (general : cop ≠ .logicalAnd ∧ cop ≠ .logicalOr)
    (run : evalExpr (fuel + 1) prog st (.binary cop l r) = .done v st') :
    st' = st ∧ ∃ vl vr, tl.ty.Holds vl (tl.expr.eval env) ∧ tr.ty.Holds vr (tr.expr.eval env) ∧
      Semantics.evalBinaryValue prog.target cop vl vr = .ok v := by
  cases cop <;> simp only [ne_eq, not_true_eq_false, false_and, and_false, reduceCtorEq,
    not_false_eq_true, and_self] at general <;>
  · simp only [evalExpr] at run
    split at run
    · rename_i vl midl leftRun
      obtain ⟨rfl, holdsl⟩ := hl leftRun
      split at run
      · rename_i vr midr rightRun
        obtain ⟨rfl, holdsr⟩ := hr rightRun
        split at run
        · rename_i result evaluated
          simp only [Semantics.Outcome.done.injEq] at run
          obtain ⟨rfl, rfl⟩ := run
          exact ⟨rfl, vl, vr, holdsl, holdsr, evaluated⟩
        · simp at run
      all_goals simp at run
    all_goals simp at run

section Values

open Semantics

theorem toInt_beq (a b : BitVec 32) : (a.toInt == b.toInt) = (a == b) := by
  rw [Bool.eq_iff_iff]
  simp [BitVec.toInt_inj]

variable (a b : BitVec 32)

theorem eval_add : evalBinaryValue .x86_64 .add (.signed .i32 a.toInt) (.signed .i32 b.toInt) =
    .ok (.signed .i32 (a + b).toInt) := by
  simp [evalBinaryValue, evalSignedBinary, wrap_add]

theorem eval_sub : evalBinaryValue .x86_64 .subtract (.signed .i32 a.toInt) (.signed .i32 b.toInt) =
    .ok (.signed .i32 (a - b).toInt) := by
  simp [evalBinaryValue, evalSignedBinary, wrap_sub]

theorem eval_mul : evalBinaryValue .x86_64 .multiply (.signed .i32 a.toInt) (.signed .i32 b.toInt) =
    .ok (.signed .i32 (a * b).toInt) := by
  simp [evalBinaryValue, evalSignedBinary, wrap_mul]

theorem eval_bitAnd : evalBinaryValue .x86_64 .bitAnd (.signed .i32 a.toInt) (.signed .i32 b.toInt) =
    .ok (.signed .i32 (a &&& b).toInt) := by
  simp only [evalBinaryValue, beq_self_eq_true, ↓reduceIte, evalSignedBinary,
    signedBits_i32_bitvec_x86 a _ rfl, signedBits_i32_bitvec_x86 b _ rfl, wrap_nat]
  congr 3
  apply BitVec.eq_of_toNat_eq
  have bound := (a &&& b).isLt
  rw [BitVec.toNat_and] at bound
  simp only [BitVec.toNat_ofNat, BitVec.toNat_and]
  exact Nat.mod_eq_of_lt bound

theorem eval_bitOr : evalBinaryValue .x86_64 .bitOr (.signed .i32 a.toInt) (.signed .i32 b.toInt) =
    .ok (.signed .i32 (a ||| b).toInt) := by
  simp only [evalBinaryValue, beq_self_eq_true, ↓reduceIte, evalSignedBinary,
    signedBits_i32_bitvec_x86 a _ rfl, signedBits_i32_bitvec_x86 b _ rfl, wrap_nat]
  congr 3
  apply BitVec.eq_of_toNat_eq
  have bound := (a ||| b).isLt
  rw [BitVec.toNat_or] at bound
  simp only [BitVec.toNat_ofNat, BitVec.toNat_or]
  exact Nat.mod_eq_of_lt bound

theorem eval_bitXor : evalBinaryValue .x86_64 .bitXor (.signed .i32 a.toInt) (.signed .i32 b.toInt) =
    .ok (.signed .i32 (a ^^^ b).toInt) := by
  simp only [evalBinaryValue, beq_self_eq_true, ↓reduceIte, evalSignedBinary,
    signedBits_i32_bitvec_x86 a _ rfl, signedBits_i32_bitvec_x86 b _ rfl, wrap_nat]
  congr 3
  apply BitVec.eq_of_toNat_eq
  have bound := (a ^^^ b).isLt
  rw [BitVec.toNat_xor] at bound
  simp only [BitVec.toNat_ofNat, BitVec.toNat_xor]
  exact Nat.mod_eq_of_lt bound

theorem eval_order (cop : Core.BinaryOp) (op : CmpOp)
    (h : (cop = .less ∧ op = .lt) ∨ (cop = .lessEqual ∧ op = .le) ∨
      (cop = .greater ∧ op = .gt) ∨ (cop = .greaterEqual ∧ op = .ge)) :
    evalBinaryValue .x86_64 cop (.signed .i32 a.toInt) (.signed .i32 b.toInt) =
      .ok (.boolean (op.holds a b)) := by
  rcases h with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ <;>
    simp [evalBinaryValue, evalSignedBinary, CmpOp.holds, BitVec.slt, BitVec.sle]

theorem eval_eq_int : evalBinaryValue .x86_64 .equal (.signed .i32 a.toInt) (.signed .i32 b.toInt) =
    .ok (.boolean (CmpOp.eq.holds a b)) := by
  simp [evalBinaryValue, scalarEqual, CmpOp.holds, toInt_beq]

theorem eval_ne_int : evalBinaryValue .x86_64 .notEqual (.signed .i32 a.toInt) (.signed .i32 b.toInt) =
    .ok (.boolean (CmpOp.ne.holds a b)) := by
  simp [evalBinaryValue, scalarEqual, CmpOp.holds, toInt_beq, bne]

theorem eval_eq_bool (x y : Bool) : evalBinaryValue .x86_64 .equal (.boolean x) (.boolean y) =
    .ok (.boolean (CmpOp.eq.holds (low (boolBits x)) (low (boolBits y)))) := by
  cases x <;> cases y <;> simp [evalBinaryValue, scalarEqual, CmpOp.holds, boolBits] <;> decide

theorem eval_ne_bool (x y : Bool) : evalBinaryValue .x86_64 .notEqual (.boolean x) (.boolean y) =
    .ok (.boolean (CmpOp.ne.holds (low (boolBits x)) (low (boolBits y)))) := by
  cases x <;> cases y <;> simp [evalBinaryValue, scalarEqual, CmpOp.holds, boolBits] <;> decide

end Values

theorem UintTy.eq_of_code {a b : UintTy} (same : a.code = b.code) : a = b := by
  cases a <;> cases b <;> simp_all [UintTy.code]

theorem SrcType.eq_of_isUint {ty : SrcType} {k : UintTy} (h : ty.isUint k = true) : ty = .uint k := by
  cases ty <;> simp only [SrcType.isUint, decide_eq_true_eq, reduceCtorEq] at h ⊢
  rw [UintTy.eq_of_code h]

theorem SrcType.eq_of_uintKind {ty : SrcType} {k : UintTy} (h : ty.uintKind = some k) : ty = .uint k := by
  cases ty <;> simp_all [SrcType.uintKind]

theorem arithUint_some {op : BinOp} {l r t : Typed} {kind : Option UintTy}
    (h : arithUint op l r kind = some t) : ∃ k, kind = some k ∧ r.ty = .uint k ∧
      t = { expr := wrap k (.binary .u64 op l.expr r.expr), ty := .uint k } := by
  cases kind with
  | none => simp [arithUint] at h
  | some k =>
    simp only [arithUint] at h
    split at h
    · rename_i hr
      simp only [Option.some.injEq] at h
      exact ⟨k, rfl, SrcType.eq_of_isUint hr, h.symm⟩
    · simp at h

theorem orderUint_some {op : CmpOp} {l r t : Typed} {kind : Option UintTy}
    (h : orderUint op l r kind = some t) : ∃ k, kind = some k ∧ r.ty = .uint k ∧
      t = { expr := .compare .u64 op l.expr r.expr, ty := .bool } := by
  cases kind with
  | none => simp [orderUint] at h
  | some k =>
    simp only [orderUint] at h
    split at h
    · rename_i hr
      simp only [Option.some.injEq] at h
      exact ⟨k, rfl, SrcType.eq_of_isUint hr, h.symm⟩
    · simp at h

theorem holds_compare (c : Bool) : SrcType.Holds .bool (.boolean c) (if c then 1 else 0) :=
  ⟨c, rfl, by cases c <;> rfl⟩

/-- `signKey` flips the sign bit. -/
theorem signKey_eval (e : Expr) (env : Env) : (signKey e).eval env = flip (e.eval env) := by
  simp only [signKey, Expr.eval, Word.apply, BinOp.apply, flip]

/-- A lowered cast holds Core's cast of the operand's value. -/
theorem cast_sound {ty : SrcType} {inner t : Typed} {env : Env} {w result : Value}
    (holds : inner.ty.Holds w (inner.expr.eval env)) (lowered : castTo ty inner = some t)
    (casted : Semantics.evalScalarCast .x86_64 ty.toScalar w = .ok result) :
    t.ty.Holds result (t.expr.eval env) := by
  cases ty with
  | i32 =>
    simp only [castTo, castToI32] at lowered
    split at lowered
    · rename_i hty
      simp only [Option.some.injEq] at lowered
      subst lowered
      rw [hty] at holds ⊢
      obtain ⟨rfl, bits⟩ := holds
      simp only [SrcType.toScalar, cast_i32_i32, Except.ok.injEq] at casted
      subst casted
      exact ⟨rfl, bits⟩
    · simp at lowered
    · rename_i kind hty
      simp only [Option.some.injEq] at lowered
      subst lowered
      rw [hty] at holds
      obtain ⟨rfl, bound⟩ := holds
      simp only [SrcType.toScalar, cast_i32_uint, Except.ok.injEq] at casted
      subst casted
      have low32 : BitVec.ofNat 64 ((inner.expr.eval env).toNat % 2 ^ UintTy.width .uint32) =
          widen (BitVec.ofNat 32 (inner.expr.eval env).toNat) := by
        apply BitVec.eq_of_toNat_eq
        simp only [widen, BitVec.toNat_ofNat, BitVec.toNat_setWidth, UintTy.width]
      simp only [wrap_eval, low32]
      exact holds_i32 _
    · simp at lowered
    · simp at lowered
    · simp at lowered
    · simp at lowered
    · simp at lowered
    · rename_i hty
      simp only [Option.some.injEq] at lowered
      subst lowered
      rw [hty] at holds
      subst holds
      simp only [SrcType.toScalar, cast_i32_isize, Except.ok.injEq] at casted
      subst casted
      have low32 : BitVec.ofNat 64 ((inner.expr.eval env).toNat % 2 ^ UintTy.width .uint32) =
          widen (BitVec.ofNat 32 (inner.expr.eval env).toNat) := by
        apply BitVec.eq_of_toNat_eq
        simp only [widen, BitVec.toNat_ofNat, BitVec.toNat_setWidth, UintTy.width]
      simp only [wrap_eval, low32]
      exact holds_i32 _
  | bool => simp [castTo] at lowered
  | uint kind =>
    have positive := Nat.two_pow_pos kind.width
    simp only [castTo, castToUint] at lowered
    split at lowered
    · rename_i hty
      simp only [Option.some.injEq] at lowered
      subst lowered
      rw [hty] at holds
      obtain ⟨rfl, bits⟩ := holds
      simp only [SrcType.toScalar, cast_uint_i32, Except.ok.injEq] at casted
      subst casted
      rw [fromI32_eval kind _ env bits]
      refine holds_uint kind ?_
      have : ((low (inner.expr.eval env)).toInt % (2 ^ kind.width : Nat)).toNat < 2 ^ kind.width := by
        have := Int.emod_lt_of_pos (low (inner.expr.eval env)).toInt (show (0 : Int) < (2 ^ kind.width : Nat) by omega)
        have := Int.emod_nonneg (low (inner.expr.eval env)).toInt (show ((2 ^ kind.width : Nat) : Int) ≠ 0 by omega)
        omega
      simpa using this
    · simp at lowered
    · rename_i source hty
      simp only [Option.some.injEq] at lowered
      subst lowered
      rw [hty] at holds
      obtain ⟨rfl, bound⟩ := holds
      simp only [SrcType.toScalar, cast_uint_uint, Except.ok.injEq] at casted
      subst casted
      rw [wrap_eval]
      exact holds_uint kind (Nat.mod_lt _ positive)
    · simp at lowered
    · simp at lowered
    · simp at lowered
    · simp at lowered
    · simp at lowered
    · rename_i hty
      simp only [Option.some.injEq] at lowered
      subst lowered
      rw [hty] at holds
      subst holds
      simp only [SrcType.toScalar, cast_uint_isize, Except.ok.injEq] at casted
      subst casted
      rw [wrap_eval]
      exact holds_uint kind (Nat.mod_lt _ positive)
  | struct => simp [castTo] at lowered
  | enum => simp [castTo] at lowered
  | ptr => simp [castTo] at lowered
  | slice => simp [castTo] at lowered
  | unit => simp [castTo] at lowered
  | isize =>
    simp only [castTo, castToIsize] at lowered
    split at lowered
    · rename_i hty
      simp only [Option.some.injEq] at lowered
      subst lowered
      rw [hty] at holds
      obtain ⟨rfl, bits⟩ := holds
      simp only [SrcType.toScalar, cast_isize_i32, Except.ok.injEq] at casted
      subst casted
      rw [fromI32_eval .uint64 _ env bits]
      show _ = _
      congr 2
      apply BitVec.eq_of_toNat_eq
      simp only [UintTy.width, BitVec.toNat_ofNat, BitVec.toNat_ofInt]
      omega
    · simp at lowered
    · rename_i kind hty
      simp only [Option.some.injEq] at lowered
      subst lowered
      rw [hty] at holds
      obtain ⟨rfl, -⟩ := holds
      simp only [SrcType.toScalar, cast_isize_uint, Except.ok.injEq] at casted
      subst casted
      show _ = _
      simp
    · simp at lowered
    · simp at lowered
    · simp at lowered
    · simp at lowered
    · simp at lowered
    · rename_i hty
      simp only [Option.some.injEq] at lowered
      subst lowered
      rw [hty] at holds ⊢
      subst holds
      simp only [SrcType.toScalar, cast_isize_isize, Except.ok.injEq] at casted
      subst casted
      rfl

/-- A strict operator's lowering, on operands that represent `vl` and `vr`,
represents Core's result. -/
theorem SrcOp.lower_holds {op : SrcOp} {tl tr t : Typed} (lowered : op.lower tl tr = some t)
    (strict : op ≠ .logicalAnd ∧ op ≠ .logicalOr) {env : Env} {vl vr v : Value}
    (holdsl : tl.ty.Holds vl (tl.expr.eval env)) (holdsr : tr.ty.Holds vr (tr.expr.eval env))
    (evaluated : Semantics.evalBinaryValue .x86_64 op.toCore vl vr = .ok v) :
    t.ty.Holds v (t.expr.eval env) := by
  cases op
  case plus | minus | times | bitAnd | bitOr | bitXor =>
    simp only [SrcOp.lower] at lowered
    try
      rcases offsetOrArith_some lowered with ⟨htl, htr, rfl⟩ | lowered
      · rw [htl] at holdsl
        rw [htr] at holdsr
        simp only [SrcType.Holds, UintTy.toCore] at holdsl holdsr
        obtain ⟨rfl, -⟩ := holdsr
        subst holdsl
        simp only [SrcOp.toCore] at evaluated
        first
          | rw [eval_ptr_add] at evaluated
          | rw [eval_ptr_sub] at evaluated
        simp only [Except.ok.injEq] at evaluated
        subst evaluated
        exact rfl
    simp only [arith] at lowered
    split at lowered
    · rename_i types
      simp only [Option.some.injEq] at lowered
      subst lowered
      cases htl : tl.ty <;> cases htr : tr.ty <;> simp [htl, htr, SrcType.isI32] at types
      rw [htl] at holdsl
      rw [htr] at holdsr
      obtain ⟨rfl, _⟩ := holdsl
      obtain ⟨rfl, _⟩ := holdsr
      simp only [SrcOp.toCore, eval_add, eval_sub, eval_mul, eval_bitAnd, eval_bitOr,
        eval_bitXor, Except.ok.injEq] at evaluated
      subst evaluated
      simp only [Expr.eval, Word.apply, BinOp.apply]; exact holds_i32 _
    split at lowered
    · rename_i types
      simp only [Option.some.injEq] at lowered
      subst lowered
      cases htl : tl.ty <;> cases htr : tr.ty <;> simp [htl, htr, SrcType.isIsize] at types
      rw [htl] at holdsl
      rw [htr] at holdsr
      subst holdsl
      subst holdsr
      simp only [SrcOp.toCore] at evaluated
      first
        | rw [eval_isize_binop (op := .add) (h := .inl ⟨rfl, rfl⟩)] at evaluated
        | rw [eval_isize_binop (op := .sub) (h := .inr (.inl ⟨rfl, rfl⟩))] at evaluated
        | rw [eval_isize_binop (op := .mul) (h := .inr (.inr (.inl ⟨rfl, rfl⟩)))] at evaluated
        | rw [eval_isize_binop (op := .and) (h := .inr (.inr (.inr (.inl ⟨rfl, rfl⟩))))] at evaluated
        | rw [eval_isize_binop (op := .or) (h := .inr (.inr (.inr (.inr (.inl ⟨rfl, rfl⟩)))))] at evaluated
        | rw [eval_isize_binop (op := .xor) (h := .inr (.inr (.inr (.inr (.inr ⟨rfl, rfl⟩)))))] at evaluated
      simp only [Except.ok.injEq] at evaluated
      subst evaluated
      rfl
    · obtain ⟨k, hk, htr, rfl⟩ := arithUint_some lowered
      rw [SrcType.eq_of_uintKind hk] at holdsl
      rw [htr] at holdsr
      obtain ⟨rfl, _⟩ := holdsl
      obtain ⟨rfl, boundr⟩ := holdsr
      simp only [SrcOp.toCore] at evaluated
      first
        | rw [eval_uint_binop k boundr (op := .add) (.inl ⟨rfl, rfl⟩)] at evaluated
        | rw [eval_uint_binop k boundr (op := .sub) (.inr (.inl ⟨rfl, rfl⟩))] at evaluated
        | rw [eval_uint_binop k boundr (op := .mul) (.inr (.inr (.inl ⟨rfl, rfl⟩)))] at evaluated
        | rw [eval_uint_binop k boundr (op := .and) (.inr (.inr (.inr (.inl ⟨rfl, rfl⟩))))] at evaluated
        | rw [eval_uint_binop k boundr (op := .or) (.inr (.inr (.inr (.inr (.inl ⟨rfl, rfl⟩)))))] at evaluated
        | rw [eval_uint_binop k boundr (op := .xor) (.inr (.inr (.inr (.inr (.inr ⟨rfl, rfl⟩)))))] at evaluated
      simp only [Except.ok.injEq] at evaluated
      subst evaluated
      rw [wrap_eval]
      exact holds_uint k (Nat.mod_lt _ (Nat.two_pow_pos _))
  case shiftLeft =>
    simp only [SrcOp.lower, arith] at lowered
    split at lowered
    · rename_i types
      simp only [Option.some.injEq] at lowered
      subst lowered
      cases htl : tl.ty <;> cases htr : tr.ty <;> simp [htl, htr, SrcType.isI32] at types
      rw [htl] at holdsl
      rw [htr] at holdsr
      obtain ⟨rfl, _⟩ := holdsl
      obtain ⟨rfl, _⟩ := holdsr
      obtain rfl := eval_shl_i32 _ _ evaluated
      simp only [Expr.eval, Word.apply, BinOp.apply]; exact holds_i32 _
    split at lowered
    · rename_i types
      simp only [Option.some.injEq] at lowered
      subst lowered
      cases htl : tl.ty <;> cases htr : tr.ty <;> simp [htl, htr, SrcType.isIsize] at types
      rw [htl] at holdsl
      rw [htr] at holdsr
      subst holdsl
      subst holdsr
      obtain rfl := eval_shl_isize _ _ evaluated
      rfl
    · obtain ⟨k, hk, htr, rfl⟩ := arithUint_some lowered
      rw [SrcType.eq_of_uintKind hk] at holdsl
      rw [htr] at holdsr
      obtain ⟨rfl, _⟩ := holdsl
      obtain ⟨rfl, _⟩ := holdsr
      obtain rfl := eval_uint_shift _ _ k (.inl ⟨rfl, rfl⟩) evaluated
      rw [wrap_eval]
      exact holds_uint k (Nat.mod_lt _ (Nat.two_pow_pos _))
  case shiftRight =>
    simp only [SrcOp.lower, arithShiftRight] at lowered
    split at lowered
    · rename_i signed
      simp only [arith] at lowered
      split at lowered
      · rename_i types
        simp only [Option.some.injEq] at lowered
        subst lowered
        cases htl : tl.ty <;> cases htr : tr.ty <;> simp [htl, htr, SrcType.isI32] at types
        rw [htl] at holdsl
        rw [htr] at holdsr
        obtain ⟨rfl, _⟩ := holdsl
        obtain ⟨rfl, _⟩ := holdsr
        obtain rfl := eval_sar_i32 _ _ evaluated
        simp only [Expr.eval, Word.apply, BinOp.apply]; exact holds_i32 _
      split at lowered
      · rename_i types
        simp only [Option.some.injEq] at lowered
        subst lowered
        cases htl : tl.ty <;> cases htr : tr.ty <;> simp [htl, htr, SrcType.isIsize] at types
        rw [htl] at holdsl
        rw [htr] at holdsr
        subst holdsl
        subst holdsr
        obtain rfl := eval_sar_isize _ _ evaluated
        rfl
      · obtain ⟨k, hk, -, -⟩ := arithUint_some lowered
        rw [SrcType.eq_of_uintKind hk] at signed
        simp [SrcType.isI32, SrcType.isIsize] at signed
    · rename_i signed
      simp only [arith] at lowered
      split at lowered
      · rename_i types
        cases htl : tl.ty <;> simp [htl, SrcType.isI32, SrcType.isIsize] at types signed
      split at lowered
      · rename_i types
        cases htl : tl.ty <;> simp [htl, SrcType.isI32, SrcType.isIsize] at types signed
      · obtain ⟨k, hk, htr, rfl⟩ := arithUint_some lowered
        rw [SrcType.eq_of_uintKind hk] at holdsl
        rw [htr] at holdsr
        obtain ⟨rfl, _⟩ := holdsl
        obtain ⟨rfl, _⟩ := holdsr
        obtain rfl := eval_uint_shift _ _ k (.inr ⟨rfl, rfl⟩) evaluated
        rw [wrap_eval]
        exact holds_uint k (Nat.mod_lt _ (Nat.two_pow_pos _))
  case less | lessEq | greater | greaterEq =>
    simp only [SrcOp.lower, order] at lowered
    split at lowered
    · rename_i types
      simp only [Option.some.injEq] at lowered
      subst lowered
      cases htl : tl.ty <;> cases htr : tr.ty <;> simp [htl, htr, SrcType.isI32] at types
      rw [htl] at holdsl
      rw [htr] at holdsr
      obtain ⟨rfl, _⟩ := holdsl
      obtain ⟨rfl, _⟩ := holdsr
      simp only [SrcOp.toCore] at evaluated
      first
        | rw [eval_order (op := .lt) (h := .inl ⟨rfl, rfl⟩)] at evaluated
        | rw [eval_order (op := .le) (h := .inr (.inl ⟨rfl, rfl⟩))] at evaluated
        | rw [eval_order (op := .gt) (h := .inr (.inr (.inl ⟨rfl, rfl⟩)))] at evaluated
        | rw [eval_order (op := .ge) (h := .inr (.inr (.inr ⟨rfl, rfl⟩)))] at evaluated
      simp only [Except.ok.injEq] at evaluated
      subst evaluated
      simp only [Expr.eval, Word.holds]
      exact holds_compare _
    split at lowered
    · rename_i types
      simp only [Option.some.injEq] at lowered
      subst lowered
      cases htl : tl.ty <;> cases htr : tr.ty <;> simp [htl, htr, SrcType.isIsize] at types
      rw [htl] at holdsl
      rw [htr] at holdsr
      subst holdsl
      subst holdsr
      simp only [SrcOp.toCore] at evaluated
      first
        | rw [eval_isize_order (op := .lt) (h := .inl ⟨rfl, rfl⟩)] at evaluated
        | rw [eval_isize_order (op := .le) (h := .inr (.inl ⟨rfl, rfl⟩))] at evaluated
        | rw [eval_isize_order (op := .gt) (h := .inr (.inr (.inl ⟨rfl, rfl⟩)))] at evaluated
        | rw [eval_isize_order (op := .ge) (h := .inr (.inr (.inr ⟨rfl, rfl⟩)))] at evaluated
      simp only [Except.ok.injEq] at evaluated
      subst evaluated
      simp only [Expr.eval, Word.holds, signKey_eval]
      exact holds_compare _
    · obtain ⟨k, hk, htr, rfl⟩ := orderUint_some lowered
      rw [SrcType.eq_of_uintKind hk] at holdsl
      rw [htr] at holdsr
      obtain ⟨rfl, _⟩ := holdsl
      obtain ⟨rfl, _⟩ := holdsr
      simp only [SrcOp.toCore] at evaluated
      first
        | rw [eval_uint_order k _ _ (op := .lt) (.inl ⟨rfl, rfl⟩)] at evaluated
        | rw [eval_uint_order k _ _ (op := .le) (.inr (.inl ⟨rfl, rfl⟩))] at evaluated
        | rw [eval_uint_order k _ _ (op := .gt) (.inr (.inr (.inl ⟨rfl, rfl⟩)))] at evaluated
        | rw [eval_uint_order k _ _ (op := .ge) (.inr (.inr (.inr ⟨rfl, rfl⟩)))] at evaluated
      simp only [Except.ok.injEq] at evaluated
      subst evaluated
      simp only [Expr.eval, Word.holds]
      exact holds_compare _
  case equal | notEqual =>
    simp only [SrcOp.lower, equality] at lowered
    split at lowered
    · rename_i types
      simp only [Option.some.injEq] at lowered
      subst lowered
      simp only [SrcOp.toCore] at evaluated
      cases htl : tl.ty <;> cases htr : tr.ty <;>
        simp [htl, htr, SrcType.same, SrcType.isI32, SrcType.isBool, SrcType.isUint, SrcType.isPtr, SrcType.isUnit, SrcType.isIsize] at types <;>
        rw [htl] at holdsl <;> rw [htr] at holdsr
      · obtain ⟨rfl, _⟩ := holdsl
        obtain ⟨rfl, _⟩ := holdsr
        simp only [eval_eq_int, eval_ne_int, Except.ok.injEq] at evaluated
        subst evaluated
        simp only [Expr.eval, SrcType.word, Word.holds]
        exact holds_compare _
      · obtain ⟨x, rfl, bitsl⟩ := holdsl
        obtain ⟨y, rfl, bitsr⟩ := holdsr
        simp only [eval_eq_bool, eval_ne_bool, Except.ok.injEq] at evaluated
        subst evaluated
        simp only [Expr.eval, SrcType.word, Word.holds, bitsl, bitsr]
        exact holds_compare _
      · cases UintTy.eq_of_code types
        obtain ⟨rfl, _⟩ := holdsl
        obtain ⟨rfl, _⟩ := holdsr
        simp only [eval_uint_eq, eval_uint_ne, Except.ok.injEq] at evaluated
        subst evaluated
        simp only [Expr.eval, htl, SrcType.word, Word.holds]
        exact holds_compare _
      · simp [SrcType.Holds] at holdsl
      · simp [SrcType.Holds] at holdsl
      · subst holdsl
        subst holdsr
        simp only [eval_ptr_eq, eval_ptr_ne, Except.ok.injEq] at evaluated
        subst evaluated
        simp only [Expr.eval, htl, SrcType.word, Word.holds]
        exact holds_compare _
      · simp [SrcType.Holds] at holdsl
      · simp [SrcType.Holds] at holdsl
      · subst holdsl
        subst holdsr
        simp only [eval_isize_eq, eval_isize_ne, Except.ok.injEq] at evaluated
        subst evaluated
        simp only [Expr.eval, htl, SrcType.word, Word.holds]
        exact holds_compare _
    · simp at lowered
  case logicalAnd => exact absurd rfl strict.1
  case logicalOr => exact absurd rfl strict.2

theorem SrcExpr.lower_sound (e : SrcExpr) {scope : List Binding} {frame : Nat → Nat} {st : State}
    {env : Env} {prog : Core.Program} (corr : Corr scope frame st env) (target : prog.target = .x86_64) :
    ∀ {t : Typed} {fuel : Nat} {v : Value} {st' : State}, e.lower scope = some t →
      evalExpr fuel prog st e.toCore = .done v st' → st' = st ∧ t.ty.Holds v (t.expr.eval env) := by
  induction e with
  | int x =>
    intro t fuel v st' lowered run
    cases fuel with
    | zero => simp [evalExpr] at run
    | succ fuel =>
      simp only [SrcExpr.lower, Option.some.injEq] at lowered
      subst lowered
      simp only [SrcExpr.toCore, evalExpr, Semantics.Outcome.done.injEq] at run
      obtain ⟨rfl, rfl⟩ := run
      exact ⟨rfl, holds_i32 x⟩
  | boolean x =>
    intro t fuel v st' lowered run
    cases fuel with
    | zero => simp [evalExpr] at run
    | succ fuel =>
      simp only [SrcExpr.lower, Option.some.injEq] at lowered
      subst lowered
      simp only [SrcExpr.toCore, evalExpr, Semantics.Outcome.done.injEq] at run
      obtain ⟨rfl, rfl⟩ := run
      exact ⟨rfl, x, rfl, rfl⟩
  | null =>
    intro t fuel v st' lowered run
    cases fuel with
    | zero => simp [evalExpr] at run
    | succ fuel =>
      simp only [SrcExpr.lower, Option.some.injEq] at lowered
      subst lowered
      simp only [SrcExpr.toCore, evalExpr, Semantics.Outcome.done.injEq] at run
      obtain ⟨rfl, rfl⟩ := run
      exact ⟨rfl, by simp [SrcType.Holds, Expr.eval]⟩
  | unsigned kind value =>
    intro t fuel v st' lowered run
    cases fuel with
    | zero => simp [evalExpr] at run
    | succ fuel =>
      simp only [SrcExpr.lower, lowerUnsigned] at lowered
      split at lowered
      · rename_i fits
        simp only [Option.some.injEq] at lowered
        subst lowered
        simp only [SrcExpr.toCore, evalExpr, Semantics.Outcome.done.injEq] at run
        obtain ⟨rfl, rfl⟩ := run
        have mask := kind.mask_toNat
        have positive := Nat.two_pow_pos kind.width
        rw [BitVec.le_def] at fits
        exact ⟨rfl, rfl, by simp only [Expr.eval]; omega⟩
      · simp at lowered
  | «local» id =>
    intro t fuel v st' lowered run
    cases fuel with
    | zero => simp [evalExpr] at run
    | succ fuel =>
      simp only [SrcExpr.lower, lowerLocal] at lowered
      split at lowered
      · simp at lowered
      · rename_i b found
        simp only [lowerScalarLocal] at lowered
        split at lowered
        · rename_i scalar
          simp only [Option.some.injEq] at lowered
          subst lowered
          obtain ⟨w, eval, holds⟩ := corr.local found fuel prog
          simp only [SrcExpr.toCore, eval, Semantics.Outcome.done.injEq] at run
          obtain ⟨rfl, rfl⟩ := run
          exact ⟨rfl, (SrcType.holdsAt_scalar scalar).mp holds⟩
        · simp at lowered
  | field id index =>
    intro t fuel v st' lowered run
    cases fuel with
    | zero => simp [evalExpr] at run
    | succ fuel =>
      cases fuel with
      | zero => simp [SrcExpr.toCore, evalExpr] at run
      | succ fuel =>
        simp only [SrcExpr.lower, lowerField] at lowered
        split at lowered
        · simp at lowered
        rename_i b found
        simp only [lowerFieldOf] at lowered
        split at lowered
        · simp at lowered
        · simp at lowered
        · simp at lowered
        rename_i sid fields hty
        simp only [lowerFieldAt] at lowered
        split at lowered
        · simp at lowered
        rename_i f fieldFound
        split at lowered
        · rename_i scalar
          simp only [Option.some.injEq] at lowered
          subst lowered
          obtain ⟨w, eval, holds⟩ := corr.local found fuel prog
          rw [hty] at holds
          cases holds with
          | struct fieldsHold =>
            obtain ⟨fv, got, holdsField⟩ := fieldsHold.get fieldFound
            simp only [SrcExpr.toCore, evalExpr] at run
            simp only [evalExpr] at eval
            rw [eval] at run
            simp only [got, Semantics.Outcome.done.injEq] at run
            obtain ⟨rfl, rfl⟩ := run
            exact ⟨rfl, by simpa [Expr.eval] using (SrcType.holdsAt_scalar scalar).mp holdsField⟩
        · simp at lowered
        all_goals simp at lowered
  | negate operand ih =>
    intro t fuel v st' lowered run
    cases fuel with
    | zero => simp [evalExpr] at run
    | succ fuel =>
      simp only [SrcExpr.lower, lowerNegate] at lowered
      split at lowered
      · simp at lowered
      · rename_i inner innerLowered
        simp only [lowerNegateTyped] at lowered
        split at lowered
        · rename_i isInt
          simp only [Option.some.injEq] at lowered
          subst lowered
          simp only [SrcExpr.toCore, evalExpr] at run
          split at run
          · rename_i w mid innerRun
            obtain ⟨rfl, holds⟩ := ih innerLowered innerRun
            cases hty : inner.ty <;> simp [hty, SrcType.isI32] at isInt
            rw [hty] at holds
            obtain ⟨rfl, _⟩ := holds
            simp only [Semantics.evalUnaryValue, target, Semantics.Outcome.done.injEq] at run
            obtain ⟨rfl, rfl⟩ := run
            exact ⟨rfl, by simp only [Expr.eval]; rw [wrap_neg]; exact holds_i32 _⟩
          all_goals simp at run
        · split at lowered
          · rename_i isIsize
            simp only [Option.some.injEq] at lowered
            subst lowered
            simp only [SrcExpr.toCore, evalExpr] at run
            split at run
            · rename_i w mid innerRun
              obtain ⟨rfl, holds⟩ := ih innerLowered innerRun
              cases hty : inner.ty <;> simp [hty, SrcType.isIsize] at isIsize
              rw [hty] at holds
              subst holds
              rw [target, eval_isize_neg] at run
              simp only [Semantics.Outcome.done.injEq] at run
              obtain ⟨rfl, rfl⟩ := run
              exact ⟨rfl, rfl⟩
            all_goals simp at run
          · simp at lowered
  | not operand ih =>
    intro t fuel v st' lowered run
    cases fuel with
    | zero => simp [evalExpr] at run
    | succ fuel =>
      simp only [SrcExpr.lower, lowerNot] at lowered
      split at lowered
      · simp at lowered
      · rename_i inner innerLowered
        simp only [lowerNotTyped] at lowered
        split at lowered
        · rename_i isBool
          simp only [Option.some.injEq] at lowered
          subst lowered
          simp only [SrcExpr.toCore, evalExpr] at run
          split at run
          · rename_i w mid innerRun
            obtain ⟨rfl, holds⟩ := ih innerLowered innerRun
            cases hty : inner.ty <;> simp [hty, SrcType.isBool] at isBool
            rw [hty] at holds
            obtain ⟨x, rfl, bits⟩ := holds
            simp only [Semantics.evalUnaryValue, Semantics.Outcome.done.injEq] at run
            obtain ⟨rfl, rfl⟩ := run
            refine ⟨rfl, !x, rfl, ?_⟩
            cases x <;> simp [Expr.eval, Word.holds, CmpOp.holds, bits, boolBits] <;> decide
          all_goals simp at run
        · simp at lowered
  | apply op left right ihl ihr =>
    intro t fuel v st' lowered run
    cases fuel with
    | zero => simp [evalExpr] at run
    | succ fuel =>
      simp only [SrcExpr.lower, lowerApply] at lowered
      split at lowered
      · simp at lowered
      rename_i tl leftLowered
      split at lowered
      · simp at lowered
      rename_i tr rightLowered
      have hl : ∀ {fuel v st'}, evalExpr fuel prog st left.toCore = .done v st' →
          st' = st ∧ tl.ty.Holds v (tl.expr.eval env) := fun h => ihl leftLowered h
      have hr : ∀ {fuel v st'}, evalExpr fuel prog st right.toCore = .done v st' →
          st' = st ∧ tr.ty.Holds v (tr.expr.eval env) := fun h => ihr rightLowered h
      simp only [SrcExpr.toCore] at run
      cases op
      case plus | minus | times | bitAnd | bitOr | bitXor | shiftLeft | shiftRight | less | lessEq | greater |
          greaterEq | equal | notEqual =>
        obtain ⟨rfl, vl, vr, holdsl, holdsr, evaluated⟩ :=
          binary_sound hl hr (by simp [SrcOp.toCore]) run
        rw [target] at evaluated
        exact ⟨rfl, SrcOp.lower_holds lowered (by simp) holdsl holdsr evaluated⟩
      case logicalAnd =>
        simp only [SrcOp.lower, conjunction] at lowered
        split at lowered
        · rename_i types
          simp only [Option.some.injEq] at lowered
          subst lowered
          cases htl : tl.ty <;> cases htr : tr.ty <;> simp [htl, htr, SrcType.isBool] at types
          simp only [SrcOp.toCore, evalExpr] at run
          split at run
          · rename_i mid leftRun
            obtain ⟨rfl, holdsl⟩ := hl leftRun
            rw [htl] at holdsl
            obtain ⟨x, hx, bitsl⟩ := holdsl
            cases hx
            simp only [Semantics.Outcome.done.injEq] at run
            obtain ⟨rfl, rfl⟩ := run
            refine ⟨rfl, false, rfl, ?_⟩
            simp [Expr.eval, Word.apply, BinOp.apply, bitsl, boolBits]
          · rename_i mid leftRun
            obtain ⟨rfl, holdsl⟩ := hl leftRun
            rw [htl] at holdsl
            obtain ⟨x, hx, bitsl⟩ := holdsl
            cases hx
            obtain ⟨rfl, holdsr⟩ := hr run
            rw [htr] at holdsr
            obtain ⟨y, rfl, bitsr⟩ := holdsr
            refine ⟨rfl, y, rfl, ?_⟩
            cases y <;> simp [Expr.eval, Word.apply, BinOp.apply, bitsl, bitsr, boolBits] <;> decide
          · rename_i w mid notFalse notTrue leftRun
            obtain ⟨rfl, holdsl⟩ := hl leftRun
            rw [htl] at holdsl
            obtain ⟨x, rfl, _⟩ := holdsl
            cases x <;> simp_all
          all_goals simp at run
        · simp at lowered
      case logicalOr =>
        simp only [SrcOp.lower, disjunction] at lowered
        split at lowered
        · rename_i types
          simp only [Option.some.injEq] at lowered
          subst lowered
          cases htl : tl.ty <;> cases htr : tr.ty <;> simp [htl, htr, SrcType.isBool] at types
          simp only [SrcOp.toCore, evalExpr] at run
          split at run
          · rename_i mid leftRun
            obtain ⟨rfl, holdsl⟩ := hl leftRun
            rw [htl] at holdsl
            obtain ⟨x, hx, bitsl⟩ := holdsl
            cases hx
            simp only [Semantics.Outcome.done.injEq] at run
            obtain ⟨rfl, rfl⟩ := run
            refine ⟨rfl, true, rfl, ?_⟩
            simp only [Expr.eval, Word.apply, Word.holds, BinOp.apply, CmpOp.holds, bitsl, boolBits,
              low_widen]
            have : low 1 ||| low (tr.expr.eval env) ≠ 0 := by
              intro h
              have := congrArg (fun x : BitVec 32 => x.getLsbD 0) h
              simp at this
            simp
          · rename_i mid leftRun
            obtain ⟨rfl, holdsl⟩ := hl leftRun
            rw [htl] at holdsl
            obtain ⟨x, hx, bitsl⟩ := holdsl
            cases hx
            obtain ⟨rfl, holdsr⟩ := hr run
            rw [htr] at holdsr
            obtain ⟨y, rfl, bitsr⟩ := holdsr
            refine ⟨rfl, y, rfl, ?_⟩
            cases y <;> simp [Expr.eval, Word.apply, Word.holds, BinOp.apply, CmpOp.holds, bitsl, bitsr,
              boolBits] <;> decide
          · rename_i w mid notTrue notFalse leftRun
            obtain ⟨rfl, holdsl⟩ := hl leftRun
            rw [htl] at holdsl
            obtain ⟨x, rfl, _⟩ := holdsl
            cases x <;> simp_all
          all_goals simp at run
        · simp at lowered

  | cast ty operand ih =>
    intro t fuel v st' lowered run
    cases fuel with
    | zero => simp [evalExpr] at run
    | succ fuel =>
      simp only [SrcExpr.lower, lowerCast] at lowered
      split at lowered
      · simp at lowered
      rename_i inner innerLowered
      simp only [SrcExpr.toCore, evalExpr] at run
      split at run
      · rename_i w mid innerRun
        obtain ⟨rfl, holds⟩ := ih innerLowered innerRun
        split at run
        · rename_i result casted
          simp only [Semantics.Outcome.done.injEq] at run
          obtain ⟨rfl, rfl⟩ := run
          rw [target] at casted
          exact ⟨rfl, cast_sound holds lowered casted⟩
        · simp at run
      all_goals simp at run

end Lanius.Mini
