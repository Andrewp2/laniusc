import Lanius.Semantics

namespace Lanius.Semantics

open Lanius Lanius.Core

theorem wrapSigned_bmod (value : Int) :
    wrapSigned Target.x86_64 .i32 value = value.bmod (2 ^ 32) := by
  unfold wrapSigned signedModulus signedSignBit
  have bits : SignedIntTy.bits Target.x86_64 .i32 = 32 := by decide
  rw [bits, Int.bmod_eq_emod]
  dsimp
  change (if value % (4294967296 : Int) ≥ 2147483648 then
      value % (4294967296 : Int) - 4294967296 else value % (4294967296 : Int)) =
    value % (4294967296 : Int) -
      ↑(if value % (4294967296 : Int) ≥ 2147483648 then
        (4294967296 : Nat) else 0)
  by_cases h : value % (4294967296 : Int) ≥ 2147483648
  · simp [h]
  · simp [h]

theorem evalSignedBinary_i32_and (left right : BitVec 32) :
    evalSignedBinary .x86_64 .bitAnd .i32 left.toInt right.toInt =
      .ok (.signed .i32 (left &&& right).toInt) := by
  simp [evalSignedBinary, signedBits_i32_bitvec_x86 _ _ rfl,
    wrapSigned_bmod, BitVec.toInt_and]

theorem evalSignedBinary_i32_or (left right : BitVec 32) :
    evalSignedBinary .x86_64 .bitOr .i32 left.toInt right.toInt =
      .ok (.signed .i32 (left ||| right).toInt) := by
  simp [evalSignedBinary, signedBits_i32_bitvec_x86 _ _ rfl,
    wrapSigned_bmod, BitVec.toInt_or]

theorem evalSignedBinary_i32_xor (left right : BitVec 32) :
    evalSignedBinary .x86_64 .bitXor .i32 left.toInt right.toInt =
      .ok (.signed .i32 (left ^^^ right).toInt) := by
  simp [evalSignedBinary, signedBits_i32_bitvec_x86 _ _ rfl,
    wrapSigned_bmod, BitVec.toInt_xor]

theorem evalSignedBinary_i32_shiftLeft (value : BitVec 32) (shift : Nat)
    (bound : shift < 32) :
    evalSignedBinary .x86_64 .shiftLeft .i32 value.toInt shift =
      .ok (.signed .i32 (value <<< shift).toInt) := by
  have guard : (decide ((shift : Int) < 0) ||
      decide ((shift : Int) ≥ Int.ofNat (SignedIntTy.i32.bits .x86_64))) = false := by
    simp [SignedIntTy.bits]; omega
  unfold evalSignedBinary
  rw [guard]
  simp only [Bool.false_eq_true, if_false, Int.toNat_natCast]
  rw [wrapSigned_bmod, ← BitVec.toInt_ofInt]
  rw [BitVec.ofInt_mul, BitVec.ofInt_toInt]
  have power : BitVec.ofInt 32 (Int.ofNat (2 ^ shift)) = BitVec.twoPow 32 shift := by
    rw [Int.ofNat_eq_natCast, BitVec.ofInt_natCast]
    apply BitVec.eq_of_toNat_eq
    simp
  rw [power, BitVec.mul_twoPow_eq_shiftLeft]

end Lanius.Semantics
