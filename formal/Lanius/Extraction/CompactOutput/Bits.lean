import Lanius.Extraction.CompactOutput.Byte
import Init.Data.Nat.Bitwise.Lemmas

namespace Lanius.Extraction.CompactOutput

open Lanius.Core Lanius.Semantics

/-- Signed shifting agrees with division on the nonnegative values accepted
by hex_u32; the shift count must be in the machine's defined domain. -/
theorem shift_right (target : Target) (value shift : Nat)
    (bounded : value ≤ 2147483647) (shiftBound : shift < 32) :
    evalSignedBinary target .shiftRight .i32 value shift =
      .ok (.signed .i32 (value / 2 ^ shift : Nat)) := by
  have valid : (decide ((shift : Int) < 0) ||
      decide ((shift : Int) ≥ Int.ofNat (SignedIntTy.i32.bits target))) = false := by
    simp [SignedIntTy.bits]
    omega
  unfold evalSignedBinary
  rw [valid]
  simp only [Bool.false_eq_true, if_false, Int.toNat_natCast]
  change (Except.ok (Value.signed .i32 (wrapSigned target .i32
    (if (value : Int) ≥ 0 then (value : Int) / (2 ^ shift : Nat)
      else -((-(value : Int) + (2 ^ shift : Nat) - 1) / (2 ^ shift : Nat))))) : Except Trap Value) = _
  rw [if_pos (by omega), ← Int.natCast_ediv]
  have wrapped := wrapSigned_i32_ofNat target (value / 2 ^ shift)
    (Nat.le_trans (Nat.div_le_self _ _) bounded)
  simpa only [Int.ofNat_eq_natCast] using congrArg (fun n => Except.ok (Value.signed .i32 n) :
    Int → Except Trap Value) wrapped

theorem mask_nibble (target : Target) (value : Nat) (bounded : value ≤ 2147483647) :
    evalSignedBinary target .bitAnd .i32 value 15 = .ok (.signed .i32 (value % 16 : Nat)) := by
  have bits : ((value : Int) % 4294967296).toNat = value := by omega
  have masked : Nat.land value 15 = value % 16 := by
    simpa using Nat.and_two_pow_sub_one_eq_mod value 4
  change (Except.ok (Value.signed .i32 (wrapSigned target .i32
    (Nat.land (((value : Int) % 4294967296).toNat) 15 : Nat))) : Except Trap Value) = _
  rw [bits, masked]
  have wrapped := wrapSigned_i32_ofNat target (value % 16) (by omega)
  simpa only [Int.ofNat_eq_natCast] using congrArg (fun n => Except.ok (Value.signed .i32 n) :
    Int → Except Trap Value) wrapped

/-- The source expression emits the high-to-low four-bit digit, with no
assumption about an already computed nibble or native bit-operation result. -/
theorem nibble_evaluates (value shift : Nat) (bounded : value ≤ 2147483647) (shiftBound : shift < 32)
    (valueResult : Evaluates program before expression (.signed .i32 value) before)
    (shiftResult : Evaluates program before amount (.signed .i32 shift) before) :
    Evaluates program before (binary .bitAnd (binary .shiftRight expression amount) (number 15))
      (.signed .i32 (value / 2 ^ shift % 16 : Nat)) before := by
  have shifted := evaluatesEagerBinary (by decide) (by decide) valueResult shiftResult
    (show evalBinaryValue program.target .shiftRight (.signed .i32 value) (.signed .i32 shift) =
      .ok (.signed .i32 (value / 2 ^ shift : Nat)) from shift_right program.target value shift bounded shiftBound)
  exact evaluatesEagerBinary (by decide) (by decide) shifted
    (show Evaluates program before (number 15) (.signed .i32 15) before from ⟨1, rfl⟩)
    (mask_nibble program.target _ (Nat.le_trans (Nat.div_le_self _ _) bounded))

end Lanius.Extraction.CompactOutput
