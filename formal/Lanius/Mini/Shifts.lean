import Lanius.Mini.Semantics
import Lanius.Mini.Unsigned

/-! Core's `<<` and `>>` as the mini IR's shifts. Core traps on an amount
outside the type's bits, so a shift that returns has an amount below the
word's width, which is the amount x86's masked count keeps. `>>` is
arithmetic on `i32` and `isize` and logical on the unsigned types. -/

namespace Lanius.Mini

open Lanius.Core (Value)
open Semantics

/-- A non-negative `toInt` below `2 ^ (w - 1)` is the number. -/
theorem toNat_of_toInt {w : Nat} (b : BitVec w) (nonneg : 0 ≤ b.toInt) : (b.toNat : Int) = b.toInt := by
  rw [BitVec.toInt_eq_toNat_cond] at nonneg ⊢
  have := b.isLt
  split at nonneg <;> split <;> omega

theorem ofInt_twoPow (w k : Nat) : BitVec.ofInt w (Int.ofNat (2 ^ k)) = BitVec.twoPow w k := by
  rw [show Int.ofNat (2 ^ k) = ((2 ^ k : Nat) : Int) from rfl, BitVec.ofInt_natCast]
  apply BitVec.eq_of_toNat_eq
  rw [BitVec.toNat_twoPow, BitVec.toNat_ofNat]

theorem shl_toInt (w : Nat) (a : BitVec w) (k : Nat) :
    BitVec.ofInt w (a.toInt * Int.ofNat (2 ^ k)) = a <<< k := by
  rw [BitVec.ofInt_mul, BitVec.ofInt_toInt, ofInt_twoPow, BitVec.shiftLeft_eq_mul_twoPow]

/-- The amount of a signed shift that returns: below the width, so the count
x86 keeps. -/
theorem signed_amount {w : Nat} (b : BitVec w) (bits : Nat) (le : bits ≤ w)
    (inRange : ¬(b.toInt < 0 || b.toInt >= Int.ofNat bits) = true) :
    Int.toNat b.toInt = b.toNat ∧ b.toNat < bits := by
  simp only [Bool.or_eq_true, decide_eq_true_eq, not_or, Int.not_lt, ge_iff_le, Int.not_le,
    Int.ofNat_eq_coe] at inRange
  have same := toNat_of_toInt b inRange.1
  have := inRange.2
  constructor <;> omega

variable (a b : BitVec 32)

theorem eval_shl_i32 {v : Value}
    (ev : evalBinaryValue .x86_64 .shiftLeft (.signed .i32 a.toInt) (.signed .i32 b.toInt) = .ok v) :
    v = .signed .i32 (a <<< (b.toNat % 32)).toInt := by
  simp only [evalBinaryValue, beq_self_eq_true, ↓reduceIte, evalSignedBinary] at ev
  split at ev
  · simp at ev
  · rename_i inRange
    obtain ⟨amount, below⟩ := signed_amount b 32 (by decide) inRange
    simp only [Except.ok.injEq] at ev
    rw [← ev, amount, Nat.mod_eq_of_lt below, wrapSigned_i32, shl_toInt]

theorem eval_sar_i32 {v : Value}
    (ev : evalBinaryValue .x86_64 .shiftRight (.signed .i32 a.toInt) (.signed .i32 b.toInt) = .ok v) :
    v = .signed .i32 (a.sshiftRight (b.toNat % 32)).toInt := by
  simp only [evalBinaryValue, beq_self_eq_true, ↓reduceIte, evalSignedBinary_shiftRight] at ev
  split at ev
  · simp at ev
  · rename_i inRange
    obtain ⟨amount, below⟩ := signed_amount b 32 (by decide) inRange
    simp only [Except.ok.injEq] at ev
    rw [← ev, amount, Nat.mod_eq_of_lt below, ← BitVec.toInt_sshiftRight, wrapSigned_i32, BitVec.ofInt_toInt]

variable (x y : BitVec 64)

theorem eval_shl_isize {v : Value}
    (ev : evalBinaryValue .x86_64 .shiftLeft (.signed .isize x.toInt) (.signed .isize y.toInt) = .ok v) :
    v = .signed .isize (x <<< (y.toNat % 64)).toInt := by
  simp only [evalBinaryValue, beq_self_eq_true, ↓reduceIte, evalSignedBinary] at ev
  split at ev
  · simp at ev
  · rename_i inRange
    obtain ⟨amount, below⟩ := signed_amount y 64 (by decide) inRange
    simp only [Except.ok.injEq] at ev
    rw [← ev, amount, Nat.mod_eq_of_lt below, wrapSigned_isize, shl_toInt]

theorem eval_sar_isize {v : Value}
    (ev : evalBinaryValue .x86_64 .shiftRight (.signed .isize x.toInt) (.signed .isize y.toInt) = .ok v) :
    v = .signed .isize (x.sshiftRight (y.toNat % 64)).toInt := by
  simp only [evalBinaryValue, beq_self_eq_true, ↓reduceIte, evalSignedBinary_shiftRight] at ev
  split at ev
  · simp at ev
  · rename_i inRange
    obtain ⟨amount, below⟩ := signed_amount y 64 (by decide) inRange
    simp only [Except.ok.injEq] at ev
    rw [← ev, amount, Nat.mod_eq_of_lt below, ← BitVec.toInt_sshiftRight, wrap_isize]

/-- An unsigned `<<` or `>>` that returns is the 64-bit shift, reduced to the
type's width. -/
theorem eval_uint_shift (k : UintTy) {op : BinOp} {cop : Core.BinaryOp}
    (h : (cop = .shiftLeft ∧ op = .shl) ∨ (cop = .shiftRight ∧ op = .shr)) {v : Value}
    (ev : evalBinaryValue .x86_64 cop (.unsigned k.toCore x.toNat) (.unsigned k.toCore y.toNat) = .ok v) :
    v = .unsigned k.toCore ((op.apply x y).toNat % 2 ^ k.width) := by
  have le : k.width ≤ 64 := by cases k <;> decide
  rcases h with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ <;>
    simp only [evalBinaryValue, beq_self_eq_true, ↓reduceIte, evalUnsignedBinary, wrapUnsigned,
      unsignedModulus, UintTy.bits_toCore] at ev
  all_goals
    split at ev
    · simp at ev
    rename_i below
    have small : y.toNat % 64 = y.toNat := Nat.mod_eq_of_lt (by omega)
    simp only [Except.ok.injEq] at ev
    rw [← ev]
    simp only [BinOp.apply, small]
  · rw [BitVec.toNat_shiftLeft, Nat.shiftLeft_eq, Nat.mod_mod_of_dvd _ (Nat.pow_dvd_pow 2 le)]
  · rw [BitVec.toNat_ushiftRight, Nat.shiftRight_eq_div_pow]

end Lanius.Mini
