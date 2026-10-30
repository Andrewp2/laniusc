import Lanius.Mini.Fails

/-! Progress for pure expressions: a lowered expression whose guard passes
evaluates in Core, with enough fuel, to a value and leaves the state as it
was. Its operators have results on the values its operands represent (a
shift's amount is below the width, which is what the guard tests), its
locals are initialized (`Corr`), and Core's `&&` and `||` evaluate the right
side only when the left does not decide. So a pure expression neither
diverges nor traps once its guard passes, and when the guard fails the
compiled code stops at the check. -/

namespace Lanius.Mini

open Lanius.Core (Value)
open Lanius.Semantics (State evalExpr evalBinaryValue evalUnaryValue evalScalarCast)

/-! ## Guards that pass -/

theorem guardAnd_ne {a b : Expr} {env : Env} (h : (guardAnd a b).eval env ≠ 0) :
    a.eval env ≠ 0 ∧ b.eval env ≠ 0 := by
  unfold guardAnd at h
  split at h
  · rename_i one
    exact ⟨by rw [isOne_eval one]; decide, h⟩
  split at h
  · rename_i one
    exact ⟨h, by rw [isOne_eval one]; decide⟩
  simp only [Expr.eval, Word.apply, BinOp.apply] at h
  constructor <;> intro z <;> simp [z] at h

theorem guardOr_ne {a b : Expr} {env : Env} (h : (guardOr a b).eval env ≠ 0) :
    a.eval env ≠ 0 ∨ b.eval env ≠ 0 := by
  unfold guardOr at h
  split at h
  · rename_i one
    simp only [Bool.or_eq_true] at one
    rcases one with one | one
    · exact .inl (by rw [isOne_eval one]; decide)
    · exact .inr (by rw [isOne_eval one]; decide)
  simp only [Expr.eval, Word.holds, CmpOp.holdsU, Word.apply, BinOp.apply] at h
  by_cases ha : a.eval env = 0
  · by_cases hb : b.eval env = 0
    · simp [ha, hb] at h
    · exact .inr hb
  · exact .inl ha

theorem amountGuard_ne {width : BitVec 64} {amount : Expr} {env : Env}
    (h : (amountGuard width amount).eval env ≠ 0) : (amount.eval env).toNat < width.toNat := by
  unfold amountGuard at h
  split at h
  · rename_i below
    cases amount <;> simp [literalBelow] at below
    simpa [Expr.eval, BitVec.lt_def] using below
  · simp only [Expr.eval, Word.holds, CmpOp.holdsU, BitVec.ult] at h
    by_cases lt : (amount.eval env).toNat < width.toNat
    · exact lt
    · simp [lt] at h

/-! ## Operators with results -/

section Values

open Semantics

theorem toInt_of_small {w : Nat} (b : BitVec w) (small : 2 * b.toNat < 2 ^ w) : b.toInt = b.toNat := by
  rw [BitVec.toInt_eq_toNat_cond]
  simp [small]

theorem shift_i32_ok (a b : BitVec 32) (small : b.toNat < 32) {cop : Core.BinaryOp}
    (shift : cop = .shiftLeft ∨ cop = .shiftRight) :
    ∃ v, evalBinaryValue .x86_64 cop (.signed .i32 a.toInt) (.signed .i32 b.toInt) = .ok v := by
  have nonneg := toInt_of_small b (by omega)
  rcases shift with rfl | rfl <;>
  · simp only [evalBinaryValue, beq_self_eq_true, ↓reduceIte, evalSignedBinary, evalSignedBinary_shiftRight]
    split
    · rename_i bad
      simp [Core.SignedIntTy.bits, Core.Target.x86_64, Core.PointerWidth.bits] at bad
      omega
    · exact ⟨_, rfl⟩

theorem shift_isize_ok (x y : BitVec 64) (small : y.toNat < 64) {cop : Core.BinaryOp}
    (shift : cop = .shiftLeft ∨ cop = .shiftRight) :
    ∃ v, evalBinaryValue .x86_64 cop (.signed .isize x.toInt) (.signed .isize y.toInt) = .ok v := by
  have nonneg := toInt_of_small y (by omega)
  rcases shift with rfl | rfl <;>
  · simp only [evalBinaryValue, beq_self_eq_true, ↓reduceIte, evalSignedBinary, evalSignedBinary_shiftRight]
    split
    · rename_i bad
      simp [Core.SignedIntTy.bits, Core.Target.x86_64, Core.PointerWidth.bits] at bad
      omega
    · exact ⟨_, rfl⟩

theorem UintTy.bits_toNat (k : UintTy) : (UintTy.bits k).toNat = k.width := by
  cases k <;> rfl

theorem shift_uint_ok (k : UintTy) (x y : BitVec 64) (small : y.toNat < k.width) {cop : Core.BinaryOp}
    (shift : cop = .shiftLeft ∨ cop = .shiftRight) :
    ∃ v, evalBinaryValue .x86_64 cop (.unsigned k.toCore x.toNat) (.unsigned k.toCore y.toNat) = .ok v := by
  rcases shift with rfl | rfl <;>
  · simp only [evalBinaryValue, beq_self_eq_true, ↓reduceIte, evalUnsignedBinary, UintTy.bits_toCore]
    split
    · rename_i bad
      simp only [ge_iff_le, decide_eq_true_eq] at bad
      omega
    · exact ⟨_, rfl⟩

end Values

/-- A signed value is Core's of the signed type as wide. -/
theorem sint_value {k : UintTy} {v : Value} {a : BitVec 64} (h : k.SintHolds v a) :
    ∃ n, v = .signed k.toSigned n := by
  cases k <;> simp only [UintTy.SintHolds, NarrowHolds] at h <;> first | exact ⟨_, h.1⟩ | exact ⟨_, h⟩

/-- Core's arithmetic, comparisons and equality on two values of one signed type have results. -/
theorem sint_defined {k : UintTy} {cop : Core.BinaryOp}
    (h : cop = .add ∨ cop = .subtract ∨ cop = .multiply ∨ cop = .bitAnd ∨ cop = .bitOr ∨ cop = .bitXor ∨
      cop = .less ∨ cop = .lessEqual ∨ cop = .greater ∨ cop = .greaterEqual ∨ cop = .equal ∨ cop = .notEqual)
    {vl vr : Value} {a b : BitVec 64} (hl : k.SintHolds vl a) (hr : k.SintHolds vr b) :
    ∃ v, evalBinaryValue .x86_64 cop vl vr = .ok v := by
  obtain ⟨x, rfl⟩ := sint_value hl
  obtain ⟨y, rfl⟩ := sint_value hr
  rcases h with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl <;>
    simp [evalBinaryValue, Semantics.evalSignedBinary, Semantics.scalarEqual]

/-- A signed shift whose amount is below the width has a result. -/
theorem sint_shift_defined {k : UintTy} {cop : Core.BinaryOp} (shift : cop = .shiftLeft ∨ cop = .shiftRight)
    {vl vr : Value} {a b : BitVec 64} (hl : k.SintHolds vl a) (hr : k.SintHolds vr b) (amount : b.toNat < k.width) :
    ∃ v, evalBinaryValue .x86_64 cop vl vr = .ok v := by
  obtain ⟨x, rfl⟩ := sint_value hl
  have val : vr = .signed k.toSigned (b.toNat : Int) := by
    have le : k.width ≤ 64 := by cases k <;> decide
    by_cases wide : k.isWide = true
    · rw [sintHolds_wide wide] at hr
      rw [hr, BitVec.toInt_eq_toNat_cond, if_pos (by omega)]
    · rw [sintHolds_narrow (by simpa using wide)] at hr
      obtain ⟨rfl, hb, -, -⟩ := hr
      have w32 := UintTy.width_le (k := k) (by simpa using wide)
      have eq : b.toNat = (low b).toNat := by
        have := congrArg BitVec.toNat hb
        rwa [widen_toNat] at this
      rw [BitVec.toInt_eq_toNat_cond, if_pos (by omega), eq]
  subst val
  rcases shift with rfl | rfl <;>
    simp only [evalBinaryValue, beq_self_eq_true, ↓reduceIte, Semantics.evalSignedBinary, UintTy.bits_toSigned] <;>
    rw [if_neg (by simp; omega)] <;> exact ⟨_, rfl⟩

/-- Arithmetic other than shifts has a result on the values it lowers for. -/
theorem arith_defined {op : BinOp} {cop : Core.BinaryOp}
    (h : (cop = .add ∧ op = .add) ∨ (cop = .subtract ∧ op = .sub) ∨ (cop = .multiply ∧ op = .mul) ∨
      (cop = .bitAnd ∧ op = .and) ∨ (cop = .bitOr ∧ op = .or) ∨ (cop = .bitXor ∧ op = .xor))
    {tl tr t : Typed} (lowered : arith op tl tr = some t) {env : Env} {vl vr : Value}
    (holdsl : tl.ty.Holds vl (tl.expr.eval env)) (holdsr : tr.ty.Holds vr (tr.expr.eval env)) :
    ∃ v, evalBinaryValue .x86_64 cop vl vr = .ok v := by
  simp only [arith] at lowered
  split at lowered
  · rename_i types
    cases htl : tl.ty <;> cases htr : tr.ty <;> simp [htl, htr, SrcType.isI32] at types
    rw [htl] at holdsl
    rw [htr] at holdsr
    obtain ⟨rfl, _⟩ := holdsl
    obtain ⟨rfl, _⟩ := holdsr
    rcases h with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩
    · exact ⟨_, eval_add _ _⟩
    · exact ⟨_, eval_sub _ _⟩
    · exact ⟨_, eval_mul _ _⟩
    · exact ⟨_, eval_bitAnd _ _⟩
    · exact ⟨_, eval_bitOr _ _⟩
    · exact ⟨_, eval_bitXor _ _⟩
  split at lowered
  · rename_i types
    cases htl : tl.ty <;> cases htr : tr.ty <;> simp [htl, htr, SrcType.isIsize] at types
    rw [htl] at holdsl
    rw [htr] at holdsr
    subst holdsl
    subst holdsr
    exact ⟨_, eval_isize_binop _ _ h⟩
  split at lowered
  · obtain ⟨k, htl, htr, -⟩ := arithSint_types lowered
    rw [htl] at holdsl
    rw [htr] at holdsr
    exact sint_defined (by rcases h with ⟨rfl, -⟩ | ⟨rfl, -⟩ | ⟨rfl, -⟩ | ⟨rfl, -⟩ | ⟨rfl, -⟩ | ⟨rfl, -⟩ <;> simp)
      holdsl holdsr
  · obtain ⟨k, hk, htr, rfl⟩ := arithUint_some lowered
    rw [SrcType.eq_of_uintKind hk] at holdsl
    rw [htr] at holdsr
    obtain ⟨rfl, _⟩ := holdsl
    obtain ⟨rfl, boundr⟩ := holdsr
    exact ⟨_, eval_uint_binop k boundr h⟩

/-- A shift has a result when its amount is below the left operand's width. -/
theorem shift_defined {op : BinOp} {cop : Core.BinaryOp} (shift : cop = .shiftLeft ∨ cop = .shiftRight)
    {tl tr t : Typed} (lowered : arith op tl tr = some t) {env : Env} {vl vr : Value}
    (holdsl : tl.ty.Holds vl (tl.expr.eval env)) (holdsr : tr.ty.Holds vr (tr.expr.eval env))
    (amount : (tr.expr.eval env).toNat < (shiftWidth tl.ty).toNat) :
    ∃ v, evalBinaryValue .x86_64 cop vl vr = .ok v := by
  simp only [arith] at lowered
  split at lowered
  · rename_i types
    cases htl : tl.ty <;> cases htr : tr.ty <;> simp [htl, htr, SrcType.isI32] at types
    rw [htl] at holdsl amount
    rw [htr] at holdsr
    obtain ⟨rfl, _⟩ := holdsl
    obtain ⟨rfl, bits⟩ := holdsr
    rw [bits, widen_toNat] at amount
    exact shift_i32_ok _ _ (Nat.lt_of_lt_of_eq amount rfl) shift
  split at lowered
  · rename_i types
    cases htl : tl.ty <;> cases htr : tr.ty <;> simp [htl, htr, SrcType.isIsize] at types
    rw [htl] at holdsl amount
    rw [htr] at holdsr
    subst holdsl
    subst holdsr
    exact shift_isize_ok _ _ (by simpa [shiftWidth] using amount) shift
  split at lowered
  · obtain ⟨k, htl, htr, -⟩ := arithSint_types lowered
    rw [htl] at holdsl amount
    rw [htr] at holdsr
    have width : (UintTy.bits k).toNat = k.width := by cases k <;> rfl
    simp only [shiftWidth, width] at amount
    exact sint_shift_defined shift holdsl holdsr amount
  · obtain ⟨k, hk, htr, rfl⟩ := arithUint_some lowered
    rw [SrcType.eq_of_uintKind hk] at holdsl amount
    rw [htr] at holdsr
    obtain ⟨rfl, _⟩ := holdsl
    obtain ⟨rfl, _⟩ := holdsr
    exact shift_uint_ok k _ _ (by simpa [shiftWidth, UintTy.bits_toNat] using amount) shift

theorem order_defined {op : CmpOp} {cop : Core.BinaryOp}
    (h : (cop = .less ∧ op = .lt) ∨ (cop = .lessEqual ∧ op = .le) ∨
      (cop = .greater ∧ op = .gt) ∨ (cop = .greaterEqual ∧ op = .ge))
    {tl tr t : Typed} (lowered : order op tl tr = some t) {env : Env} {vl vr : Value}
    (holdsl : tl.ty.Holds vl (tl.expr.eval env)) (holdsr : tr.ty.Holds vr (tr.expr.eval env)) :
    ∃ v, evalBinaryValue .x86_64 cop vl vr = .ok v := by
  simp only [order] at lowered
  split at lowered
  · rename_i types
    cases htl : tl.ty <;> cases htr : tr.ty <;> simp [htl, htr, SrcType.isI32] at types
    rw [htl] at holdsl
    rw [htr] at holdsr
    obtain ⟨rfl, _⟩ := holdsl
    obtain ⟨rfl, _⟩ := holdsr
    exact ⟨_, eval_order _ _ cop op h⟩
  split at lowered
  · rename_i types
    cases htl : tl.ty <;> cases htr : tr.ty <;> simp [htl, htr, SrcType.isIsize] at types
    rw [htl] at holdsl
    rw [htr] at holdsr
    subst holdsl
    subst holdsr
    exact ⟨_, eval_isize_order _ _ h⟩
  split at lowered
  · obtain ⟨k, htl, htr, -⟩ := orderSint_types lowered
    rw [htl] at holdsl
    rw [htr] at holdsr
    exact sint_defined (by rcases h with ⟨rfl, -⟩ | ⟨rfl, -⟩ | ⟨rfl, -⟩ | ⟨rfl, -⟩ <;> simp) holdsl holdsr
  · obtain ⟨k, hk, htr, rfl⟩ := orderUint_some lowered
    rw [SrcType.eq_of_uintKind hk] at holdsl
    rw [htr] at holdsr
    obtain ⟨rfl, _⟩ := holdsl
    obtain ⟨rfl, _⟩ := holdsr
    exact ⟨_, eval_uint_order k _ _ h⟩

theorem equality_defined {op : CmpOp} {cop : Core.BinaryOp}
    (h : (cop = .equal ∧ op = .eq) ∨ (cop = .notEqual ∧ op = .ne))
    {tl tr t : Typed} (lowered : equality op tl tr = some t) {env : Env} {vl vr : Value}
    (holdsl : tl.ty.Holds vl (tl.expr.eval env)) (holdsr : tr.ty.Holds vr (tr.expr.eval env)) :
    ∃ v, evalBinaryValue .x86_64 cop vl vr = .ok v := by
  simp only [equality] at lowered
  split at lowered
  · rename_i same
    rw [← SrcType.same_eq same] at holdsr
    cases hty : tl.ty <;> rw [hty] at holdsl holdsr <;> simp only [SrcType.Holds] at holdsl holdsr
    · obtain ⟨rfl, _⟩ := holdsl
      obtain ⟨rfl, _⟩ := holdsr
      rcases h with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩
      · exact ⟨_, eval_eq_int _ _⟩
      · exact ⟨_, eval_ne_int _ _⟩
    · obtain ⟨x, rfl, _⟩ := holdsl
      obtain ⟨y, rfl, _⟩ := holdsr
      rcases h with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩
      · exact ⟨_, eval_eq_bool x y⟩
      · exact ⟨_, eval_ne_bool x y⟩
    · obtain ⟨rfl, _⟩ := holdsl
      obtain ⟨rfl, _⟩ := holdsr
      rcases h with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩
      · exact ⟨_, eval_uint_eq _ _ _⟩
      · exact ⟨_, eval_uint_ne _ _ _⟩
    · subst holdsl
      subst holdsr
      rcases h with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩
      · exact ⟨_, eval_ptr_eq _ _⟩
      · exact ⟨_, eval_ptr_ne _ _⟩
    · subst holdsl
      subst holdsr
      rcases h with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩
      · exact ⟨_, eval_isize_eq _ _⟩
      · exact ⟨_, eval_isize_ne _ _⟩
    · rcases h with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩
      · exact sint_defined (by simp) holdsl holdsr
      · exact sint_defined (by simp) holdsl holdsr
  · simp at lowered

/-- An operator other than `&&` and `||` has a result on the values its
operands represent, a shift when its amount guard passes. -/
theorem SrcOp.lower_defined {op : SrcOp} {tl tr t : Typed} (lowered : op.lower tl tr = some t)
    (strict : op ≠ .logicalAnd ∧ op ≠ .logicalOr) {env : Env} {vl vr : Value}
    (holdsl : tl.ty.Holds vl (tl.expr.eval env)) (holdsr : tr.ty.Holds vr (tr.expr.eval env))
    (amount : op = .shiftLeft ∨ op = .shiftRight → (tr.expr.eval env).toNat < (shiftWidth tl.ty).toNat) :
    ∃ v, evalBinaryValue .x86_64 op.toCore vl vr = .ok v := by
  cases op
  case plus | minus =>
    simp only [SrcOp.lower] at lowered
    rcases offsetOrArith_some lowered with ⟨htl, htr, rfl⟩ | lowered
    · rw [htl] at holdsl
      rw [htr] at holdsr
      simp only [SrcType.Holds, UintTy.toCore] at holdsl holdsr
      obtain ⟨rfl, -⟩ := holdsr
      subst holdsl
      exact ⟨_, rfl⟩
    · first
        | exact arith_defined (.inl ⟨rfl, rfl⟩) lowered holdsl holdsr
        | exact arith_defined (.inr (.inl ⟨rfl, rfl⟩)) lowered holdsl holdsr
  case times => exact arith_defined (.inr (.inr (.inl ⟨rfl, rfl⟩))) lowered holdsl holdsr
  case bitAnd => exact arith_defined (.inr (.inr (.inr (.inl ⟨rfl, rfl⟩)))) lowered holdsl holdsr
  case bitOr => exact arith_defined (.inr (.inr (.inr (.inr (.inl ⟨rfl, rfl⟩))))) lowered holdsl holdsr
  case bitXor => exact arith_defined (.inr (.inr (.inr (.inr (.inr ⟨rfl, rfl⟩))))) lowered holdsl holdsr
  case shiftLeft => exact shift_defined (.inl rfl) lowered holdsl holdsr (amount (.inl rfl))
  case shiftRight =>
    simp only [SrcOp.lower, arithShiftRight] at lowered
    split at lowered
    · exact shift_defined (.inr rfl) lowered holdsl holdsr (amount (.inr rfl))
    · exact shift_defined (.inr rfl) lowered holdsl holdsr (amount (.inr rfl))
  case less => exact order_defined (.inl ⟨rfl, rfl⟩) lowered holdsl holdsr
  case lessEq => exact order_defined (.inr (.inl ⟨rfl, rfl⟩)) lowered holdsl holdsr
  case greater => exact order_defined (.inr (.inr (.inl ⟨rfl, rfl⟩))) lowered holdsl holdsr
  case greaterEq => exact order_defined (.inr (.inr (.inr ⟨rfl, rfl⟩))) lowered holdsl holdsr
  case equal => exact equality_defined (.inl ⟨rfl, rfl⟩) lowered holdsl holdsr
  case notEqual => exact equality_defined (.inr ⟨rfl, rfl⟩) lowered holdsl holdsr
  case logicalAnd => exact absurd rfl strict.1
  case logicalOr => exact absurd rfl strict.2

/-- A cast the lowering accepts has a result. -/
theorem castTo_defined {ty : SrcType} {inner t : Typed} (lowered : castTo ty inner = some t) {w : Value}
    {bits : BitVec 64} (holds : inner.ty.Holds w bits) :
    ∃ r, evalScalarCast .x86_64 ty.toScalar w = .ok r := by
  cases ty <;> simp only [castTo, reduceCtorEq] at lowered
  case i32 =>
    simp only [castToI32] at lowered
    cases hty : inner.ty <;> simp [hty] at lowered <;> rw [hty] at holds <;> simp only [SrcType.Holds] at holds
    all_goals first
      | (obtain ⟨rfl, _⟩ := holds; exact ⟨_, rfl⟩)
      | (subst holds; exact ⟨_, rfl⟩)
      | (obtain ⟨n, rfl⟩ := sint_value holds; exact ⟨_, rfl⟩)
  case uint k =>
    simp only [castToUint] at lowered
    cases hty : inner.ty <;> simp [hty] at lowered <;> rw [hty] at holds <;> simp only [SrcType.Holds] at holds
    all_goals first
      | (obtain ⟨rfl, _⟩ := holds; exact ⟨_, rfl⟩)
      | (subst holds; exact ⟨_, rfl⟩)
      | (obtain ⟨n, rfl⟩ := sint_value holds; exact ⟨_, rfl⟩)
  case isize =>
    simp only [castToIsize] at lowered
    cases hty : inner.ty <;> simp [hty] at lowered <;> rw [hty] at holds <;> simp only [SrcType.Holds] at holds
    all_goals first
      | (obtain ⟨rfl, _⟩ := holds; exact ⟨_, rfl⟩)
      | (subst holds; exact ⟨_, rfl⟩)
      | (obtain ⟨n, rfl⟩ := sint_value holds; exact ⟨_, rfl⟩)
  case sint k =>
    simp only [castToSint] at lowered
    split at lowered
    · cases hty : inner.ty <;> simp [hty, castToIsize] at lowered <;> rw [hty] at holds <;>
        simp only [SrcType.Holds] at holds
      all_goals first
        | (obtain ⟨rfl, _⟩ := holds; exact ⟨_, rfl⟩)
        | (subst holds; exact ⟨_, rfl⟩)
        | (obtain ⟨n, rfl⟩ := sint_value holds; exact ⟨_, rfl⟩)
    · split at lowered
      · rename_i scalar
        cases hty : inner.ty <;> simp [hty, SrcType.isScalar, SrcType.isBool, SrcType.isPtr] at scalar <;>
          rw [hty] at holds <;> simp only [SrcType.Holds] at holds
        all_goals first
          | (obtain ⟨rfl, _⟩ := holds; exact ⟨_, rfl⟩)
          | (subst holds; exact ⟨_, rfl⟩)
          | (obtain ⟨n, rfl⟩ := sint_value holds; exact ⟨_, rfl⟩)
      · simp at lowered

/-! ## Evaluation steps -/

section Steps

variable {P : Core.Program} {st : State}

theorem unary_progress {op : Core.UnaryOp} {e : Core.Expr} {f : Nat} {w r : Value}
    (run : evalExpr f P st e = .done w st) (ok : evalUnaryValue P.target op w = .ok r) :
    evalExpr (f + 1) P st (.unary op e) = .done r st := by
  simp only [evalExpr, run, ok]

theorem cast_progress {ty : Core.ScalarTy} {e : Core.Expr} {f : Nat} {w r : Value}
    (run : evalExpr f P st e = .done w st) (ok : evalScalarCast P.target ty w = .ok r) :
    evalExpr (f + 1) P st (.cast ty e) = .done r st := by
  simp only [evalExpr, run, ok]

theorem binary_progress {op : Core.BinaryOp} (general : op ≠ .logicalAnd ∧ op ≠ .logicalOr) {l r : Core.Expr}
    {fl fr : Nat} {vl vr v : Value} (runl : evalExpr fl P st l = .done vl st)
    (runr : evalExpr fr P st r = .done vr st) (ok : evalBinaryValue P.target op vl vr = .ok v) :
    evalExpr (max fl fr + 1) P st (.binary op l r) = .done v st := by
  have l' := Semantics.evalExpr_of_le runl (by intro h; cases h) (Nat.le_max_left fl fr)
  have r' := Semantics.evalExpr_of_le runr (by intro h; cases h) (Nat.le_max_right fl fr)
  cases op <;> simp only [ne_eq, not_true_eq_false, false_and, and_false, reduceCtorEq, not_false_eq_true,
    and_self] at general <;> simp only [evalExpr, l', r', ok]

end Steps

/-- A lowered pure expression whose guard passes evaluates, with enough fuel,
to a value, leaving the state as it was. -/
theorem SrcExpr.progress (e : SrcExpr) {scope : List Binding} {frame : Nat → Nat} {st : State}
    {env : Env} {prog : Core.Program} (corr : Corr scope frame st env) (target : prog.target = .x86_64) :
    ∀ {t : Typed}, e.lower scope = some t → (e.guard scope).eval env ≠ 0 →
      ∃ fuel v, evalExpr fuel prog st e.toCore = .done v st := by
  induction e with
  | int x => intro _ _ _; exact ⟨1, _, by simp only [SrcExpr.toCore, evalExpr] <;> rfl⟩
  | boolean x => intro _ _ _; exact ⟨1, _, by simp only [SrcExpr.toCore, evalExpr] <;> rfl⟩
  | null => intro _ _ _; exact ⟨1, _, by simp only [SrcExpr.toCore, evalExpr] <;> rfl⟩
  | unsigned kind value => intro _ _ _; exact ⟨1, _, by simp only [SrcExpr.toCore, evalExpr] <;> rfl⟩
  | «local» id =>
    intro t lowered _
    simp only [SrcExpr.lower, lowerLocal] at lowered
    split at lowered
    · simp at lowered
    · rename_i b found
      obtain ⟨w, eval, _⟩ := corr.local found 0 prog
      exact ⟨1, w, eval⟩
  | field id index =>
    intro t lowered _
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
    obtain ⟨w, eval, holds⟩ := corr.local found 0 prog
    rw [hty] at holds
    cases holds with
    | struct fieldsHold =>
      obtain ⟨fv, got, _⟩ := fieldsHold.get fieldFound
      refine ⟨2, fv, ?_⟩
      simp only [SrcExpr.toCore, evalExpr]
      simp only [evalExpr] at eval
      rw [eval]
      simp only [got]
    all_goals simp at lowered
  | negate operand ih =>
    intro t lowered g
    simp only [SrcExpr.lower, lowerNegate] at lowered
    split at lowered
    · simp at lowered
    rename_i inner innerLowered
    obtain ⟨f, w, run⟩ := ih innerLowered g
    obtain ⟨-, holds⟩ := operand.lower_sound corr target innerLowered run
    simp only [lowerNegateTyped] at lowered
    split at lowered
    · rename_i isI32
      cases hty : inner.ty <;> simp [hty, SrcType.isI32] at isI32
      rw [hty] at holds
      obtain ⟨rfl, _⟩ := holds
      exact ⟨f + 1, _, unary_progress run (by rw [target]; rfl)⟩
    split at lowered
    · rename_i isIsize
      cases hty : inner.ty <;> simp [hty, SrcType.isIsize] at isIsize
      rw [hty] at holds
      subst holds
      exact ⟨f + 1, _, unary_progress run (by rw [target]; rfl)⟩
    split at lowered
    · simp at lowered
    · rename_i k hk
      rw [SrcType.eq_of_sintKind hk] at holds
      obtain ⟨n, rfl⟩ := sint_value holds
      exact ⟨f + 1, _, unary_progress run (by rw [target]; rfl)⟩
  | not operand ih =>
    intro t lowered g
    simp only [SrcExpr.lower, lowerNot] at lowered
    split at lowered
    · simp at lowered
    rename_i inner innerLowered
    obtain ⟨f, w, run⟩ := ih innerLowered g
    obtain ⟨-, holds⟩ := operand.lower_sound corr target innerLowered run
    simp only [lowerNotTyped] at lowered
    split at lowered
    · rename_i isBool
      cases hty : inner.ty <;> simp [hty, SrcType.isBool] at isBool
      rw [hty] at holds
      obtain ⟨x, rfl, _⟩ := holds
      exact ⟨f + 1, _, unary_progress run rfl⟩
    · simp at lowered
  | cast ty operand ih =>
    intro t lowered g
    simp only [SrcExpr.lower, lowerCast] at lowered
    split at lowered
    · simp at lowered
    rename_i inner innerLowered
    obtain ⟨f, w, run⟩ := ih innerLowered g
    obtain ⟨-, holds⟩ := operand.lower_sound corr target innerLowered run
    obtain ⟨r, ok⟩ := castTo_defined lowered holds
    exact ⟨f + 1, r, cast_progress run (by rw [target]; exact ok)⟩
  | apply op left right ihl ihr =>
    intro t lowered g
    simp only [SrcExpr.lower, lowerApply] at lowered
    split at lowered
    · simp at lowered
    rename_i tl leftLowered
    split at lowered
    · simp at lowered
    rename_i tr rightLowered
    simp only [SrcExpr.guard, leftLowered, rightLowered] at g
    simp only [SrcExpr.toCore]
    cases op
    case logicalAnd =>
      simp only [applyGuard] at g
      obtain ⟨gl, gr⟩ := guardAnd_ne g
      obtain ⟨fl, vl, runl⟩ := ihl leftLowered gl
      obtain ⟨-, holdsl⟩ := left.lower_sound corr target leftLowered runl
      simp only [SrcOp.lower, conjunction] at lowered
      split at lowered
      · rename_i types
        cases htl : tl.ty <;> cases htr : tr.ty <;> simp [htl, htr, SrcType.isBool] at types
        rw [htl] at holdsl
        obtain ⟨x, rfl, bitsl⟩ := holdsl
        cases x with
        | false => exact ⟨fl + 1, _, by simp only [SrcOp.toCore, evalExpr, runl] <;> rfl⟩
        | true =>
          have right : (right.guard scope).eval env ≠ 0 := by
            rcases guardOr_ne gr with h | h
            · simp [leftFalse, Expr.eval, Word.holds, CmpOp.holdsU, bitsl, boolBits] at h
            · exact h
          obtain ⟨fr, vr, runr⟩ := ihr rightLowered right
          have l' := Semantics.evalExpr_of_le runl (by intro h; cases h) (Nat.le_max_left fl fr)
          have r' := Semantics.evalExpr_of_le runr (by intro h; cases h) (Nat.le_max_right fl fr)
          exact ⟨max fl fr + 1, vr, by simp only [SrcOp.toCore, evalExpr, l', r']⟩
      · simp at lowered
    case logicalOr =>
      simp only [applyGuard] at g
      obtain ⟨gl, gr⟩ := guardAnd_ne g
      obtain ⟨fl, vl, runl⟩ := ihl leftLowered gl
      obtain ⟨-, holdsl⟩ := left.lower_sound corr target leftLowered runl
      simp only [SrcOp.lower, disjunction] at lowered
      split at lowered
      · rename_i types
        cases htl : tl.ty <;> cases htr : tr.ty <;> simp [htl, htr, SrcType.isBool] at types
        rw [htl] at holdsl
        obtain ⟨x, rfl, bitsl⟩ := holdsl
        cases x with
        | true => exact ⟨fl + 1, _, by simp only [SrcOp.toCore, evalExpr, runl] <;> rfl⟩
        | false =>
          have right : (right.guard scope).eval env ≠ 0 := by
            rcases guardOr_ne gr with h | h
            · simp [leftTrue, bitsl, boolBits] at h
            · exact h
          obtain ⟨fr, vr, runr⟩ := ihr rightLowered right
          have l' := Semantics.evalExpr_of_le runl (by intro h; cases h) (Nat.le_max_left fl fr)
          have r' := Semantics.evalExpr_of_le runr (by intro h; cases h) (Nat.le_max_right fl fr)
          exact ⟨max fl fr + 1, vr, by simp only [SrcOp.toCore, evalExpr, l', r']⟩
      · simp at lowered
    all_goals
      simp only [applyGuard] at g
      first
        | (obtain ⟨⟨gl, gr⟩, amount⟩ := (guardAnd_ne g).imp_left guardAnd_ne
           obtain ⟨fl, vl, runl⟩ := ihl leftLowered gl
           obtain ⟨fr, vr, runr⟩ := ihr rightLowered gr
           obtain ⟨-, holdsl⟩ := left.lower_sound corr target leftLowered runl
           obtain ⟨-, holdsr⟩ := right.lower_sound corr target rightLowered runr
           obtain ⟨v, ok⟩ := SrcOp.lower_defined lowered (by simp) holdsl holdsr
             (fun _ => amountGuard_ne (by simpa [shiftGuard] using amount))
           exact ⟨_, v, binary_progress (by simp [SrcOp.toCore]) runl runr (by rw [target]; exact ok)⟩)
        | (obtain ⟨gl, gr⟩ := guardAnd_ne g
           obtain ⟨fl, vl, runl⟩ := ihl leftLowered gl
           obtain ⟨fr, vr, runr⟩ := ihr rightLowered gr
           obtain ⟨-, holdsl⟩ := left.lower_sound corr target leftLowered runl
           obtain ⟨-, holdsr⟩ := right.lower_sound corr target rightLowered runr
           obtain ⟨v, ok⟩ := SrcOp.lower_defined lowered (by simp) holdsl holdsr (by simp)
           exact ⟨_, v, binary_progress (by simp [SrcOp.toCore]) runl runr (by rw [target]; exact ok)⟩)

theorem lowerAs_progress {scope : List Binding} {frame : Nat → Nat} {st : State} {env : Env}
    {prog : Core.Program} (corr : Corr scope frame st env) (target : prog.target = .x86_64) {e : SrcExpr}
    {ty : SrcType} {x : Expr} (ok : lowerAs scope e ty = some x) (g : (e.guard scope).eval env ≠ 0) :
    ∃ fuel v, evalExpr fuel prog st e.toCore = .done v st := by
  obtain ⟨t, lowered, -, -⟩ := lowerAs_some ok
  exact e.progress corr target lowered g

theorem lowerValue_progress {scope : List Binding} {frame : Nat → Nat} {st : State} {env : Env}
    {prog : Core.Program} (corr : Corr scope frame st env) (target : prog.target = .x86_64) {e : SrcExpr}
    {ty : SrcType} {xs : List Expr} (ok : lowerValue scope e ty = some xs) (g : (e.guard scope).eval env ≠ 0) :
    ∃ fuel v, evalExpr fuel prog st e.toCore = .done v st := by
  simp only [lowerValue] at ok
  split at ok
  · simp only [lowerSingle] at ok
    split at ok
    · simp at ok
    rename_i x valueOk
    exact lowerAs_progress corr target valueOk g
  · cases e with
    | «local» id =>
      simp only [lowerCopy, copyBinding] at ok
      split at ok
      · simp at ok
      rename_i b found
      obtain ⟨w, eval, -⟩ := corr.local found 0 prog
      exact ⟨1, w, eval⟩
    | field id index =>
      simp only [lowerCopy, copyField] at ok
      split at ok
      · simp at ok
      rename_i b found
      simp only [copyFieldOf] at ok
      split at ok
      · simp at ok
      · simp at ok
      · simp at ok
      rename_i sid fields hty
      simp only [copyFieldAt] at ok
      split at ok
      · simp at ok
      rename_i f fieldFound
      obtain ⟨w, eval, holds⟩ := corr.local found 0 prog
      rw [hty] at holds
      cases holds with
      | struct fieldsHold =>
        obtain ⟨fv, got, _⟩ := fieldsHold.get fieldFound
        refine ⟨2, fv, ?_⟩
        simp only [SrcExpr.toCore, evalExpr]
        simp only [evalExpr] at eval
        rw [eval]
        simp only [got]
      all_goals simp at ok
    | _ => simp [lowerCopy] at ok

/-- Expressions that each evaluate in place evaluate one after another. -/
theorem exprs_progress {P : Core.Program} {st : State} :
    ∀ {es : List Core.Expr}, (∀ e ∈ es, ∃ f v, evalExpr f P st e = .done v st) →
      ∃ f vs, Semantics.evalExprs f P st es = .done vs st
  | [], _ => ⟨1, [], by simp only [Semantics.evalExprs]⟩
  | e :: es, each => by
    obtain ⟨f1, v, head⟩ := each e List.mem_cons_self
    obtain ⟨f2, vs, rest⟩ := exprs_progress fun e' mem => each e' (List.mem_cons_of_mem _ mem)
    have head' := Semantics.evalExpr_of_le head (by intro h; cases h) (Nat.le_max_left f1 f2)
    have rest' := (rest ▸ Semantics.evalExprs_refines (program := P) (state := st) (expressions := es)
      (Nat.le_max_right f1 f2)).completed (by intro h; cases h)
    exact ⟨max f1 f2 + 1, v :: vs, by simp only [Semantics.evalExprs, head', rest']⟩

theorem lowerArgs_progress {scope : List Binding} {frame : Nat → Nat} {st : State} {env : Env}
    {prog : Core.Program} (corr : Corr scope frame st env) (target : prog.target = .x86_64) :
    ∀ {args : List SrcExpr} {types : List SrcType} {es : List Expr}, lowerArgs scope args types = some es →
      (guardAll scope args).eval env ≠ 0 →
      ∃ f vs, Semantics.evalExprs f prog st (args.map SrcExpr.toCore) = .done vs st := by
  intro args
  induction args with
  | nil => intro _ _ _ _; exact exprs_progress (by simp)
  | cons arg rest ih =>
    intro types es ok g
    cases types with
    | nil => simp [lowerArgs] at ok
    | cons ty more =>
      simp only [lowerArgs, lowerAppend] at ok
      split at ok
      · simp at ok
      rename_i xs argOk
      split at ok
      · simp at ok
      rename_i ys restOk
      simp only [guardAll] at g
      obtain ⟨g1, g2⟩ := guardAnd_ne g
      obtain ⟨f1, v, head⟩ := lowerValue_progress corr target argOk g1
      obtain ⟨f2, vs, restRun⟩ := ih restOk g2
      have head' := Semantics.evalExpr_of_le head (by intro h; cases h) (Nat.le_max_left f1 f2)
      have rest' := (restRun ▸ Semantics.evalExprs_refines (program := prog) (state := st)
        (expressions := rest.map SrcExpr.toCore) (Nat.le_max_right f1 f2)).completed (by intro h; cases h)
      exact ⟨max f1 f2 + 1, v :: vs, by simp only [List.map_cons, Semantics.evalExprs, head', rest']⟩

end Lanius.Mini
