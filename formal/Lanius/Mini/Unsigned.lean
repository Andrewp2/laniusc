import Lanius.Mini.Source

/-! Core's unsigned arithmetic, comparisons and the casts between `i32` and
the unsigned types, as arithmetic on 64-bit slots. A value of an unsigned type
of width `w` sits in its slot as its number, below `2 ^ w`. -/

namespace Lanius.Mini

open Lanius.Core (Value)

theorem UintTy.bits_toCore (k : UintTy) : Core.UnsignedIntTy.bits .x86_64 k.toCore = k.width := by
  cases k <;> rfl

theorem UintTy.pow_le (k : UintTy) : 2 ^ k.width ≤ 2 ^ 64 := by
  cases k <;> decide

theorem UintTy.mask_toNat (k : UintTy) : k.mask.toNat = 2 ^ k.width - 1 := by
  cases k <;> rfl

theorem UintTy.width_of_wide {k : UintTy} (wide : k.isWide = true) : k.width = 64 := by
  cases k <;> simp_all [UintTy.isWide, UintTy.width]

theorem UintTy.width_of_narrow {k : UintTy} (narrow : ¬k.isWide = true) : k.width ≤ 32 := by
  cases k <;> simp_all [UintTy.isWide, UintTy.width]

/-- `wrap` reduces a slot to its type's width. -/
theorem wrap_eval (k : UintTy) (e : Expr) (env : Env) :
    (wrap k e).eval env = BitVec.ofNat 64 ((e.eval env).toNat % 2 ^ k.width) := by
  apply BitVec.eq_of_toNat_eq
  have bound := (e.eval env).isLt
  have le := k.pow_le
  by_cases wide : k.isWide = true
  · simp only [wrap, wide, ↓reduceIte, BitVec.toNat_ofNat, UintTy.width_of_wide wide]
    omega
  · simp only [wrap, wide, Bool.false_eq_true, ↓reduceIte, Expr.eval, Word.apply, BinOp.apply,
      BitVec.toNat_and, UintTy.mask_toNat, Nat.and_two_pow_sub_one_eq_mod, BitVec.toNat_ofNat]
    omega

theorem holds_uint (k : UintTy) {m : Nat} (bound : m < 2 ^ k.width) :
    (SrcType.uint k).Holds (.unsigned k.toCore m) (BitVec.ofNat 64 m) := by
  have le := k.pow_le
  have : m % 2 ^ 64 = m := Nat.mod_eq_of_lt (by omega)
  simp only [SrcType.Holds, BitVec.toNat_ofNat, this, true_and]
  exact bound

section Values

open Semantics

theorem eval_uint_binop (k : UintTy) {a b : BitVec 64} (hb : b.toNat < 2 ^ k.width)
    {op : BinOp} {cop : Core.BinaryOp}
    (h : (cop = .add ∧ op = .add) ∨ (cop = .subtract ∧ op = .sub) ∨ (cop = .multiply ∧ op = .mul) ∨
      (cop = .bitAnd ∧ op = .and) ∨ (cop = .bitOr ∧ op = .or) ∨ (cop = .bitXor ∧ op = .xor)) :
    evalBinaryValue .x86_64 cop (.unsigned k.toCore a.toNat) (.unsigned k.toCore b.toNat) =
      .ok (.unsigned k.toCore ((op.apply a b).toNat % 2 ^ k.width)) := by
  have le := k.pow_le
  rcases h with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ <;>
  simp only [evalBinaryValue, beq_self_eq_true, ↓reduceIte, evalUnsignedBinary, wrapUnsigned,
    unsignedModulus, UintTy.bits_toCore, BinOp.apply, BitVec.toNat_add, BitVec.toNat_sub,
    BitVec.toNat_mul, BitVec.toNat_and, BitVec.toNat_or, BitVec.toNat_xor, Except.ok.injEq,
    Value.unsigned.injEq, true_and]
  · cases k <;> simp only [UintTy.width] <;> omega
  · cases k <;> simp only [UintTy.width] at hb ⊢ <;> omega
  · cases k <;> simp only [UintTy.width] <;> omega
  · rfl
  · rfl
  · rfl

theorem eval_uint_order (k : UintTy) (a b : BitVec 64) {cop : Core.BinaryOp} {op : CmpOp}
    (h : (cop = .less ∧ op = .lt) ∨ (cop = .lessEqual ∧ op = .le) ∨
      (cop = .greater ∧ op = .gt) ∨ (cop = .greaterEqual ∧ op = .ge)) :
    evalBinaryValue .x86_64 cop (.unsigned k.toCore a.toNat) (.unsigned k.toCore b.toNat) =
      .ok (.boolean (op.holdsU a b)) := by
  rcases h with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ <;>
    simp [evalBinaryValue, evalUnsignedBinary, CmpOp.holdsU, BitVec.ult, BitVec.ule]

theorem toNat_beq (a b : BitVec 64) : (a.toNat == b.toNat) = (a == b) := by
  rw [Bool.eq_iff_iff]
  simp [BitVec.toNat_inj]

theorem eval_uint_eq (k : UintTy) (a b : BitVec 64) :
    evalBinaryValue .x86_64 .equal (.unsigned k.toCore a.toNat) (.unsigned k.toCore b.toNat) =
      .ok (.boolean (CmpOp.eq.holdsU a b)) := by
  simp [evalBinaryValue, scalarEqual, CmpOp.holdsU, toNat_beq]

theorem eval_uint_ne (k : UintTy) (a b : BitVec 64) :
    evalBinaryValue .x86_64 .notEqual (.unsigned k.toCore a.toNat) (.unsigned k.toCore b.toNat) =
      .ok (.boolean (CmpOp.ne.holdsU a b)) := by
  simp [evalBinaryValue, scalarEqual, CmpOp.holdsU, toNat_beq, bne]

theorem cast_i32_i32 (x : BitVec 32) :
    evalScalarCast .x86_64 (.signed .i32) (.signed .i32 x.toInt) = .ok (.signed .i32 x.toInt) := by
  simp [evalScalarCast, wrapSigned_i32]

theorem cast_i32_uint (k : UintTy) (n : Nat) :
    evalScalarCast .x86_64 (.signed .i32) (.unsigned k.toCore n) =
      .ok (.signed .i32 (BitVec.ofNat 32 n).toInt) := by
  simp only [evalScalarCast, wrap_nat]

theorem cast_uint_uint (k source : UintTy) (n : Nat) :
    evalScalarCast .x86_64 (.unsigned k.toCore) (.unsigned source.toCore n) =
      .ok (.unsigned k.toCore (n % 2 ^ k.width)) := by
  simp [evalScalarCast, wrapUnsigned, unsignedModulus, UintTy.bits_toCore]

theorem cast_uint_i32 (k : UintTy) (x : BitVec 32) :
    evalScalarCast .x86_64 (.unsigned k.toCore) (.signed .i32 x.toInt) =
      .ok (.unsigned k.toCore (x.toInt % 2 ^ k.width).toNat) := by
  simp [evalScalarCast, wrapUnsignedInt, unsignedModulus, UintTy.bits_toCore]

end Values

theorem toInt_cases (x : BitVec 32) :
    (x.toNat < 2147483648 ∧ x.toInt = x.toNat) ∨ (2147483648 ≤ x.toNat ∧ x.toInt = x.toNat - 4294967296) := by
  rw [BitVec.toInt_eq_toNat_cond]
  have := x.isLt
  by_cases h : 2 * x.toNat < 2 ^ 32
  · left; rw [if_pos h]; omega
  · right; rw [if_neg h]; omega

/-- Sign extension as `fromI32` computes it. -/
theorem sext_toNat (x : BitVec 32) :
    (widen x - (if (2147483648 : BitVec 64).ule (widen x) then 1 else 0) * 4294967296).toNat =
      (x.toInt % 2 ^ 64).toNat := by
  have xLt := x.isLt
  have xNat : (widen x).toNat = x.toNat := by simp [widen]; omega
  rw [BitVec.toInt_eq_toNat_cond]
  by_cases neg : 2147483648 ≤ x.toNat
  · have c : (2147483648 : BitVec 64).ule (widen x) = true := by
      simp only [BitVec.ule, xNat, decide_eq_true_eq]; exact neg
    have : ((1 : BitVec 64) * 4294967296).toNat = 4294967296 := by simp
    rw [if_pos c, if_neg (by omega), BitVec.toNat_sub, this, xNat]
    omega
  · have c : (2147483648 : BitVec 64).ule (widen x) = false := by
      simp only [BitVec.ule, xNat, decide_eq_false_iff_not]; exact neg
    have : widen x - (0 : BitVec 64) * 4294967296 = widen x := by simp
    rw [if_neg (by rw [c]; simp), if_pos (by omega), this, xNat]
    omega

/-- `fromI32` gives the number Core's cast from `i32` does. -/
theorem fromI32_eval (k : UintTy) (e : Expr) (env : Env) {x : BitVec 32} (bits : e.eval env = widen x) :
    (fromI32 k e).eval env = BitVec.ofNat 64 (x.toInt % 2 ^ k.width).toNat := by
  have xLt := x.isLt
  have xNat : (widen x).toNat = x.toNat := by simp [widen]; omega
  by_cases wide : k.isWide = true
  · rw [UintTy.width_of_wide wide]
    simp only [fromI32, wide, ↓reduceIte, Expr.eval, Word.apply, Word.holds, CmpOp.holdsU, BinOp.apply, bits]
    apply BitVec.eq_of_toNat_eq
    rw [sext_toNat, BitVec.toNat_ofNat]
    omega
  · have w := UintTy.width_of_narrow wide
    simp only [fromI32, wide, Bool.false_eq_true, ↓reduceIte, wrap_eval, bits, xNat]
    congr 1
    rcases toInt_cases x with ⟨_, eq⟩ | ⟨_, eq⟩ <;> rw [eq] <;>
      cases k <;> simp_all [UintTy.isWide, UintTy.width] <;> omega

end Lanius.Mini
