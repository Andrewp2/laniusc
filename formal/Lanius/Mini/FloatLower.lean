module

public import Lanius.Mini.Signed
-- import all: Lanius.Mini.Compiler
import all Lanius.Mini.Compiler.Types
import all Lanius.Mini.Compiler.P.Lists_empty
import all Lanius.Mini.Compiler.P.DivOp_size
import all Lanius.Mini.Compiler.P.codeSize
import all Lanius.Mini.Compiler.P.compileArgs
import all Lanius.Mini.Compiler.P.arities
import all Lanius.Mini.Compiler.P.FloatTy_rex
import all Lanius.Mini.Compiler.P.FArith_opcode
import all Lanius.Mini.Compiler.P.Code_image
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
import all Lanius.Mini.Compiler.P.UintTy_half
import all Lanius.Mini.Compiler.P.SrcType_size
import all Lanius.Mini.Compiler.P.arithUint
import all Lanius.Mini.Compiler.P.floatApply
import all Lanius.Mini.Compiler.P.lowerShift
import all Lanius.Mini.Compiler.P.arithShiftRight
import all Lanius.Mini.Compiler.P.equality
import all Lanius.Mini.Compiler.P.conjunction
import all Lanius.Mini.Compiler.P.lowerLocal
import all Lanius.Mini.Compiler.P.sintToUint
import all Lanius.Mini.Compiler.P.lowerApply
import all Lanius.Mini.Compiler.P.guardAnd
import all Lanius.Mini.Compiler.P.leftTrue
import all Lanius.Mini.Compiler.P.applyGuard
import all Lanius.Mini.Compiler.P.SrcExpr_guard
import all Lanius.Mini.Compiler.P.repeatType
import all Lanius.Mini.Compiler.P.lowerTagged
import all Lanius.Mini.Compiler.P.armScope
import all Lanius.Mini.Compiler.P.assignFrom
import all Lanius.Mini.Compiler.P.armBodyScope
import all Lanius.Mini.Compiler.P.armPayload
import all Lanius.Mini.Compiler.P.lowerCallSig
import all Lanius.Mini.Compiler.P.consArgs
import all Lanius.Mini.Compiler.P.shortCircuit
import all Lanius.Mini.Compiler.P.evalDivideSint
import all Lanius.Mini.Compiler.P.evalDivide
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
import all Lanius.Mini.Compiler.P.lowerSlice
import all Lanius.Mini.Compiler.P.indexOf
import all Lanius.Mini.Compiler.P.elementAddress
import all Lanius.Mini.Compiler.P.lowerLoadType
import all Lanius.Mini.Compiler.P.wordStride
import all Lanius.Mini.Compiler.P.storeEvalWord
import all Lanius.Mini.Compiler.P.storeArray
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
import all Lanius.Mini.Compiler.P.Inline_factOr
-- end import all
-- import parts: Lanius.Mini.Compiler castToFloat floatArith floatOrder negateFloat lowerFloat
public import Lanius.Mini.Compiler.P.floatApply
public import Lanius.Mini.Compiler.P.lowerLocal
public import Lanius.Mini.Compiler.P.sintToUint
-- end import parts

@[expose] public section

/-! Floats: a lowered float literal, operation, negation or conversion, on
operands that represent Core's values, represents Core's result. A slot
holds an `f32`'s pattern zero-extended and an `f64`'s pattern; each mini
operation is `Lanius.IEEE`'s, as is each of Core's. -/

namespace Lanius.Mini

open Lanius.Core (Value)

theorem UInt32.ofNat_mod' (n : Nat) : UInt32.ofNat (n % 2 ^ 32) = UInt32.ofNat n := by
  apply UInt32.toNat_inj.mp
  simp [UInt32.toNat_ofNat]

theorem UInt64.ofNat_mod' (n : Nat) : UInt64.ofNat (n % 2 ^ 64) = UInt64.ofNat n := by
  apply UInt64.toNat_inj.mp
  simp [UInt64.toNat_ofNat]

theorem FloatTy.eq_of_number {a b : FloatTy} (same : a.number = b.number) : a = b := by
  cases a <;> cases b <;> simp [FloatTy.number] at same ⊢

theorem SrcType.eq_of_isFloat {ty : SrcType} {t : FloatTy} (h : ty.isFloat t = true) : ty = .float t := by
  cases ty <;> simp [SrcType.isFloat] at h ⊢
  exact FloatTy.eq_of_number h

theorem SrcType.eq_of_floatTy {ty : SrcType} {t : FloatTy} (h : ty.floatTy = some t) : ty = .float t := by
  cases ty <;> simp [SrcType.floatTy] at h ⊢
  exact h

/-- The word of a pattern represents the pattern. -/
theorem FloatTy.holds_word (t : FloatTy) (n : Nat) :
    (SrcType.float t).Holds (match t with
      | .f32 => .f32Bits (UInt32.ofNat n)
      | .f64 => .f64Bits (UInt64.ofNat n)) (t.word n) := by
  cases t
  · have small : n % 2 ^ 32 < 2 ^ 64 := Nat.lt_of_lt_of_le (Nat.mod_lt _ (by decide)) (by decide)
    simp only [SrcType.Holds, FloatTy.value, FloatTy.word, FloatTy.width, BitVec.toNat_ofNat,
      Nat.mod_eq_of_lt small, UInt32.ofNat_mod', true_and]
    exact Nat.mod_lt _ (by decide)
  · simp only [SrcType.Holds, FloatTy.value, FloatTy.word, FloatTy.width, BitVec.toNat_ofNat,
      Nat.mod_mod, UInt64.ofNat_mod', true_and]
    exact Nat.mod_lt _ (by decide)

theorem holds_f32 {v : Value} {n : Nat} (h : v = .f32Bits (UInt32.ofNat n)) :
    (SrcType.float .f32).Holds v (FloatTy.f32.word n) := by
  subst h
  exact FloatTy.holds_word .f32 n

theorem holds_f64 {v : Value} {n : Nat} (h : v = .f64Bits (UInt64.ofNat n)) :
    (SrcType.float .f64).Holds v (FloatTy.f64.word n) := by
  subst h
  exact FloatTy.holds_word .f64 n

theorem toNat_f32 {x : BitVec 64} (h : x.toNat < 2 ^ 32) : (UInt32.ofNat x.toNat).toNat = x.toNat := by
  simp [UInt32.toNat_ofNat, Nat.mod_eq_of_lt h]

theorem toNat_f64 (x : BitVec 64) : (UInt64.ofNat x.toNat).toNat = x.toNat := by
  simp [UInt64.toNat_ofNat, Nat.mod_eq_of_lt x.isLt]

theorem bits_f32 {x : BitVec 64} (h : x.toNat < 2 ^ 32) : FloatTy.f32.bits x = x.toNat :=
  Nat.mod_eq_of_lt h

theorem bits_f64 (x : BitVec 64) : FloatTy.f64.bits x = x.toNat :=
  Nat.mod_eq_of_lt x.isLt

theorem toInt_small {x : BitVec 64} (h : x.toNat < 2 ^ 32) : x.toInt = (x.toNat : Int) := by
  rw [BitVec.toInt_eq_toNat_cond]
  split <;> omega

/-- The Core operation a float operation computes. -/
def FArith.toCore : FArith → Core.BinaryOp
  | .fAdd => .add
  | .fSub => .subtract
  | .fMul => .multiply
  | .fDiv => .divide

/-- The Core comparison a float comparison computes. -/
def CmpOp.floatCore : CmpOp → Core.BinaryOp
  | .eq => .equal
  | .ne => .notEqual
  | .lt => .less
  | .le => .lessEqual
  | .gt => .greater
  | .ge => .greaterEqual

/-- A lowered float literal represents its pattern. -/
theorem lowerFloat_holds {ft : FloatTy} {bits : BitVec 64} {t : Typed} {env : Env}
    (lowered : lowerFloat ft bits = some t) : t.ty.Holds (ft.value bits) (t.expr.eval env) := by
  simp only [lowerFloat] at lowered
  split at lowered
  · rename_i small
    simp only [Option.some.injEq] at lowered
    subst lowered
    refine ⟨rfl, ?_⟩
    simp only [Expr.eval]
    have := BitVec.le_def.mp small
    cases ft <;> simp [FloatTy.mask, FloatTy.width] at this ⊢ <;> omega
  · simp at lowered

/-- A lowered float operation represents Core's. -/
theorem floatArith_holds {op : BinOp} {cop : Core.BinaryOp} {tl tr t : Typed} {env : Env} {vl vr v : Value}
    (lowered : floatArith op tl tr tl.ty.floatTy = some t)
    (hop : ∀ a, floatOp op = some a → a.toCore = cop)
    (holdsl : tl.ty.Holds vl (tl.expr.eval env)) (holdsr : tr.ty.Holds vr (tr.expr.eval env))
    (evaluated : Semantics.evalBinaryValue .x86_64 cop vl vr = .ok v) :
    t.ty.Holds v (t.expr.eval env) := by
  simp only [floatArith] at lowered
  split at lowered
  · simp at lowered
  rename_i ft hft
  rw [SrcType.eq_of_floatTy hft] at holdsl
  split at lowered
  rotate_left
  · simp at lowered
  rename_i same
  rw [SrcType.eq_of_isFloat same] at holdsr
  simp only [floatApply] at lowered
  split at lowered
  · simp at lowered
  rename_i a ha
  simp only [Option.some.injEq] at lowered
  subst lowered
  have core := hop a ha
  subst core
  obtain ⟨rfl, bl⟩ := holdsl
  obtain ⟨rfl, br⟩ := holdsr
  cases ft <;> cases a <;>
    simp only [FloatTy.value, FArith.toCore, Semantics.evalBinaryValue, Semantics.evalF32Binary,
      Semantics.evalF64Binary, Except.ok.injEq] at evaluated <;>
    simp only [Expr.eval, FOp.apply, FArith.apply, FloatTy.format] <;>
    first
      | (rw [bits_f32 bl, bits_f32 br]
         exact holds_f32 (by
          rw [← evaluated]
          simp only [IEEE.F32.add, IEEE.F32.sub, IEEE.F32.mul, IEEE.F32.div, toNat_f32 bl, toNat_f32 br]))
      | (rw [bits_f64, bits_f64]
         exact holds_f64 (by
          rw [← evaluated]
          simp only [IEEE.F64.add, IEEE.F64.sub, IEEE.F64.mul, IEEE.F64.div, toNat_f64]))

theorem bool_ite (c : Bool) : SrcType.bool.Holds (.boolean c) (if c = true then 1 else 0) := by
  cases c <;> exact ⟨_, rfl, rfl⟩

theorem bool_ite_not (c : Bool) :
    SrcType.bool.Holds (.boolean !c) (if ((if c = true then 1 else 0 : BitVec 64) == 0) = true then 1 else 0) := by
  cases c <;> exact ⟨_, rfl, rfl⟩

/-- A lowered float comparison represents Core's. -/
theorem floatOrder_holds {op : CmpOp} {tl tr t : Typed} {env : Env} {vl vr v : Value}
    (lowered : floatOrder op tl tr tl.ty.floatTy = some t)
    (holdsl : tl.ty.Holds vl (tl.expr.eval env)) (holdsr : tr.ty.Holds vr (tr.expr.eval env))
    (evaluated : Semantics.evalBinaryValue .x86_64 op.floatCore vl vr = .ok v) :
    t.ty.Holds v (t.expr.eval env) := by
  simp only [floatOrder] at lowered
  split at lowered
  · simp at lowered
  rename_i ft hft
  rw [SrcType.eq_of_floatTy hft] at holdsl
  split at lowered
  rotate_left
  · simp at lowered
  rename_i same
  rw [SrcType.eq_of_isFloat same] at holdsr
  simp only [Option.some.injEq] at lowered
  subst lowered
  obtain ⟨rfl, bl⟩ := holdsl
  obtain ⟨rfl, br⟩ := holdsr
  cases ft <;> cases op <;>
    simp only [FloatTy.value, CmpOp.floatCore, Semantics.evalBinaryValue, Semantics.evalF32Binary,
      Semantics.evalF64Binary, Semantics.scalarEqual, Except.ok.injEq] at evaluated <;>
    subst evaluated <;>
    simp only [floatCompare, Expr.eval, FOp.apply, FCmp.holds, FloatTy.format, Word.holds, CmpOp.holdsU,
      IEEE.F32.eq, IEEE.F32.lt, IEEE.F32.le, IEEE.F64.eq, IEEE.F64.lt, IEEE.F64.le] <;>
    (first
      | simp only [bits_f32 bl, bits_f32 br, toNat_f32 bl, toNat_f32 br]
      | simp only [bits_f64, toNat_f64]) <;>
    (first | exact bool_ite _ | exact bool_ite_not _)

theorem neg32_key (n : Nat) (h : n < 2 ^ 32) : IEEE.binary32.neg n = (n + 2 ^ 31) % 2 ^ 32 := by
  simp only [IEEE.Format.neg, IEEE.Format.negative, IEEE.Format.signBit, IEEE.binary32, beq_iff_eq]
  split <;> omega

theorem neg64_key (n : Nat) (h : n < 2 ^ 64) : IEEE.binary64.neg n = (n + 2 ^ 63) % 2 ^ 64 := by
  simp only [IEEE.Format.neg, IEEE.Format.negative, IEEE.Format.signBit, IEEE.binary64, beq_iff_eq]
  split <;> omega

/-- The sign bits' numbers, without simp (which blows up on 64-bit literals). -/
theorem signBit32_toNat : FloatTy.f32.signBit.toNat = 2147483648 % 2 ^ 64 := BitVec.toNat_ofNat _ _

theorem signBit64_toNat : FloatTy.f64.signBit.toNat = 9223372036854775808 % 2 ^ 64 := BitVec.toNat_ofNat _ _

set_option simprocs false in
theorem neg32_word (x : Expr) (env : Env) :
    (Expr.eval env (.binary FloatTy.f32.signWord .add x (.lit FloatTy.f32.signBit))).toNat =
      ((x.eval env).toNat + 2 ^ 31) % 2 ^ 32 := by
  show ((low (x.eval env) + low FloatTy.f32.signBit).setWidth 64).toNat = _
  rw [BitVec.toNat_setWidth, BitVec.toNat_add, BitVec.toNat_setWidth, BitVec.toNat_setWidth, signBit32_toNat]
  omega

set_option simprocs false in
theorem neg64_word (x : Expr) (env : Env) :
    (Expr.eval env (.binary FloatTy.f64.signWord .add x (.lit FloatTy.f64.signBit))).toNat =
      ((x.eval env).toNat + 2 ^ 63) % 2 ^ 64 := by
  show ((x.eval env) + FloatTy.f64.signBit).toNat = _
  rw [BitVec.toNat_add, signBit64_toNat]

/-- A lowered float negation represents Core's: adding the sign bit, the
carry dropped, flips it. -/
theorem negateFloat_holds {operand t : Typed} {env : Env} {w : Value}
    (lowered : negateFloat operand operand.ty.floatTy = some t)
    (holds : operand.ty.Holds w (operand.expr.eval env)) :
    ∃ r, Semantics.evalUnaryValue .x86_64 .negate w = .ok r ∧ t.ty.Holds r (t.expr.eval env) := by
  simp only [negateFloat] at lowered
  split at lowered
  · simp at lowered
  rename_i ft hft
  have hty := SrcType.eq_of_floatTy hft
  simp only [Option.some.injEq] at lowered
  subst lowered
  rw [hty] at holds ⊢
  obtain ⟨rfl, bound⟩ := holds
  cases ft
  · refine ⟨_, rfl, ?_⟩
    have word := neg32_word operand.expr env
    show _ ∧ _
    refine ⟨?_, ?_⟩
    · simp only [FloatTy.value, IEEE.F32.neg, toNat_f32 bound, neg32_key _ bound, word]
    · simp only [FloatTy.width]
      rw [word]
      omega
  · refine ⟨_, rfl, ?_⟩
    have word := neg64_word operand.expr env
    show _ ∧ _
    refine ⟨?_, ?_⟩
    · simp only [FloatTy.value, IEEE.F64.neg, toNat_f64, neg64_key _ (operand.expr.eval env).isLt, word]
    · simp only [FloatTy.width]
      rw [word]
      omega

/-- A conversion's word represents Core's rounding of the integer. -/
theorem fromInt_holds (ft : FloatTy) (i : Int) :
    (SrcType.float ft).Holds (match ft with
      | .f32 => .f32Bits (IEEE.F32.ofInt i)
      | .f64 => .f64Bits (IEEE.F64.ofInt i)) (ft.word (ft.format.ofInt i)) := by
  cases ft
  · exact FloatTy.holds_word .f32 _
  · exact FloatTy.holds_word .f64 _

/-- A lowered cast to a float holds Core's cast of the operand's value. -/
theorem castToFloat_sound {ft : FloatTy} {inner t : Typed} {env : Env} {w result : Value}
    (base : inner.ty.sintKind = none) (notChar : inner.ty ≠ .char) (holds : inner.ty.Holds w (inner.expr.eval env))
    (lowered : castToFloat ft inner = some t)
    (casted : Semantics.evalScalarCast .x86_64 (SrcType.float ft).toScalar w = .ok result) :
    t.ty.Holds result (t.expr.eval env) := by
  simp only [castToFloat] at lowered
  split at lowered
  · -- i32
    rename_i hty
    simp only [intToFloat, Option.some.injEq] at lowered
    subst lowered
    rw [hty] at holds
    obtain ⟨rfl, -⟩ := holds
    cases ft <;> simp only [SrcType.toScalar, FloatTy.toCore, Semantics.evalScalarCast, Except.ok.injEq] at casted <;>
      subst casted <;> exact fromInt_holds _ _
  · simp at lowered
  · -- a narrow uint
    rename_i kind hty
    simp only [ifNarrow] at lowered
    split at lowered
    · simp at lowered
    rename_i narrow
    simp only [intToFloat, Option.some.injEq] at lowered
    subst lowered
    rw [hty] at holds
    obtain ⟨rfl, bound⟩ := holds
    have small : (inner.expr.eval env).toNat < 2 ^ 32 := by
      cases kind <;> simp [UintTy.isWide, UintTy.width] at narrow bound ⊢ <;> omega
    cases ft <;> simp only [SrcType.toScalar, FloatTy.toCore, Semantics.evalScalarCast, Except.ok.injEq] at casted <;>
      subst casted <;>
      simp only [Expr.eval, FOp.apply] <;> rw [toInt_small small] <;> exact fromInt_holds _ _
  · simp at lowered
  · simp at lowered
  · simp at lowered
  · simp at lowered
  · simp at lowered
  · simp at lowered
  · -- isize
    rename_i hty
    simp only [intToFloat, Option.some.injEq] at lowered
    subst lowered
    rw [hty] at holds
    subst holds
    cases ft <;> simp only [SrcType.toScalar, FloatTy.toCore, Semantics.evalScalarCast, Except.ok.injEq] at casted <;>
      subst casted <;> exact fromInt_holds _ _
  · rename_i hty
    exact absurd hty notChar
  · -- another float
    rename_i source hty
    rw [hty] at holds
    obtain ⟨rfl, bound⟩ := holds
    cases source <;> cases ft <;> simp only [floatToFloat, Option.some.injEq, reduceCtorEq] at lowered <;>
      subst lowered <;>
      simp only [SrcType.toScalar, FloatTy.toCore, FloatTy.value, Semantics.evalScalarCast, Except.ok.injEq,
        reduceCtorEq] at casted
    · subst casted
      simp only [Expr.eval, FOp.apply]
      refine holds_f64 ?_
      simp only [IEEE.F32.toF64, bits_f32 bound, toNat_f32 bound]
    · subst casted
      simp only [Expr.eval, FOp.apply]
      refine holds_f32 ?_
      simp only [IEEE.F64.toF32, bits_f64, toNat_f64]
  · rename_i _ hty
    simp [hty, SrcType.sintKind] at base

/-- Core's float operations have a result on the operands a float operation lowers for. -/
theorem floatArith_defined {op : BinOp} {cop : Core.BinaryOp}
    (h : (cop = .add ∧ op = .add) ∨ (cop = .subtract ∧ op = .sub) ∨ (cop = .multiply ∧ op = .mul) ∨
      (cop = .bitAnd ∧ op = .and) ∨ (cop = .bitOr ∧ op = .or) ∨ (cop = .bitXor ∧ op = .xor))
    {tl tr t : Typed} (lowered : floatArith op tl tr tl.ty.floatTy = some t) {env : Env} {vl vr : Value}
    (holdsl : tl.ty.Holds vl (tl.expr.eval env)) (holdsr : tr.ty.Holds vr (tr.expr.eval env)) :
    ∃ v, Semantics.evalBinaryValue .x86_64 cop vl vr = .ok v := by
  simp only [floatArith] at lowered
  split at lowered
  · simp at lowered
  rename_i ft hft
  rw [SrcType.eq_of_floatTy hft] at holdsl
  split at lowered
  rotate_left
  · simp at lowered
  rename_i same
  rw [SrcType.eq_of_isFloat same] at holdsr
  obtain ⟨rfl, -⟩ := holdsl
  obtain ⟨rfl, -⟩ := holdsr
  rcases h with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ <;>
    simp only [floatApply, floatOp, reduceCtorEq] at lowered <;>
    cases ft <;> exact ⟨_, rfl⟩

/-- Core's float comparisons have a result on the operands a comparison lowers for. -/
theorem floatOrder_defined {op : CmpOp} {tl tr t : Typed} (lowered : floatOrder op tl tr tl.ty.floatTy = some t)
    {env : Env} {vl vr : Value}
    (holdsl : tl.ty.Holds vl (tl.expr.eval env)) (holdsr : tr.ty.Holds vr (tr.expr.eval env)) :
    ∃ v, Semantics.evalBinaryValue .x86_64 op.floatCore vl vr = .ok v := by
  simp only [floatOrder] at lowered
  split at lowered
  · simp at lowered
  rename_i ft hft
  rw [SrcType.eq_of_floatTy hft] at holdsl
  split at lowered
  rotate_left
  · simp at lowered
  rename_i same
  rw [SrcType.eq_of_isFloat same] at holdsr
  obtain ⟨rfl, -⟩ := holdsl
  obtain ⟨rfl, -⟩ := holdsr
  cases ft <;> cases op <;> exact ⟨_, rfl⟩

theorem floatArith_some {op : BinOp} {tl tr t : Typed} {k : Option FloatTy} (h : floatArith op tl tr k = some t) :
    ∃ ft o, t = { expr := .fp (.basic ft o) tl.expr tr.expr, ty := .float ft } := by
  cases k with
  | none => simp [floatArith] at h
  | some ft =>
    simp only [floatArith] at h
    split at h
    · simp only [floatApply] at h
      cases hop : floatOp op with
      | none => simp [hop] at h
      | some o =>
        simp only [hop, Option.some.injEq] at h
        exact ⟨ft, o, h.symm⟩
    · simp at h

theorem floatOrder_some {op : CmpOp} {tl tr t : Typed} {k : Option FloatTy} (h : floatOrder op tl tr k = some t) :
    ∃ ft, t = { expr := floatCompare ft op tl.expr tr.expr, ty := .bool } := by
  cases k with
  | none => simp [floatOrder] at h
  | some ft =>
    simp only [floatOrder] at h
    split at h
    · simp only [Option.some.injEq] at h
      exact ⟨ft, h.symm⟩
    · simp at h

theorem floatArith_types {op : BinOp} {tl tr t : Typed} (h : floatArith op tl tr tl.ty.floatTy = some t) :
    ∃ ft o, tl.ty = .float ft ∧ tr.ty = .float ft ∧ floatOp op = some o ∧
      t = { expr := .fp (.basic ft o) tl.expr tr.expr, ty := .float ft } := by
  simp only [floatArith] at h
  split at h
  · simp at h
  rename_i ft hft
  split at h
  · rename_i same
    simp only [floatApply] at h
    cases hop : floatOp op with
    | none => simp [hop] at h
    | some o =>
      simp only [hop, Option.some.injEq] at h
      exact ⟨ft, o, SrcType.eq_of_floatTy hft, SrcType.eq_of_isFloat same, rfl, h.symm⟩
  · simp at h

theorem floatOrder_types {op : CmpOp} {tl tr t : Typed} (h : floatOrder op tl tr tl.ty.floatTy = some t) :
    ∃ ft, tl.ty = .float ft ∧ tr.ty = .float ft ∧
      t = { expr := floatCompare ft op tl.expr tr.expr, ty := .bool } := by
  simp only [floatOrder] at h
  split at h
  · simp at h
  rename_i ft hft
  split at h
  · rename_i same
    simp only [Option.some.injEq] at h
    exact ⟨ft, SrcType.eq_of_floatTy hft, SrcType.eq_of_isFloat same, h.symm⟩
  · simp at h

theorem SrcType.isFloatAny_of_isInteger {ty : SrcType} (h : ty.isInteger = true) : ty.isFloatAny = false := by
  cases ty <;> simp_all [SrcType.isInteger, SrcType.isFloatAny]

end Lanius.Mini
