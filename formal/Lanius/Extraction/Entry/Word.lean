import Lanius.Extraction.Entry.Hex
import Lanius.Extraction.Input.Unpacking

namespace Lanius.Extraction.Entry.Hex

open Lanius.Core Lanius.Semantics

theorem shiftLeft (target : Target) (value shift : Nat) (valid : shift < 32)
    (bounded : value * 2 ^ shift ≤ 2147483647) :
    evalSignedBinary target .shiftLeft .i32 value shift =
      .ok (.signed .i32 (value * 2 ^ shift : Nat)) := by
  have allowed : (decide ((shift : Int) < 0) ||
      decide ((shift : Int) ≥ Int.ofNat (SignedIntTy.i32.bits target))) = false := by
    simp [SignedIntTy.bits]; omega
  unfold evalSignedBinary
  rw [allowed]
  simp only [Bool.false_eq_true, if_false, Int.toNat_natCast]
  simp only [Int.ofNat_eq_natCast, ← Int.natCast_mul]
  have wrapped := wrapSigned_i32_ofNat target _ bounded
  simpa only [Int.ofNat_eq_natCast] using congrArg
    (fun value => (Except.ok (.signed .i32 value) : Except Lanius.Trap Value)) wrapped

/-- Disjoint high and low bit fields combine arithmetically. This is the
invariant needed by the source's hexadecimal-word OR expression. -/
theorem join (target : Target) (high low shift : Nat)
    (lowBound : low < 2 ^ shift) (bounded : high * 2 ^ shift + low ≤ 2147483647) :
    evalSignedBinary target .bitOr .i32 (high * 2 ^ shift : Nat) low =
      .ok (.signed .i32 (high * 2 ^ shift + low : Nat)) := by
  have highBits : (((high * 2 ^ shift : Nat) : Int) % 4294967296).toNat = high * 2 ^ shift := by omega
  have lowBits : ((low : Int) % 4294967296).toNat = low := by omega
  have combined : Nat.lor (high * 2 ^ shift) low = high * 2 ^ shift + low := by
    simpa [Nat.shiftLeft_eq] using (Nat.shiftLeft_add_eq_or_of_lt lowBound high).symm
  change (Except.ok (.signed .i32 (wrapSigned target .i32
    (Nat.lor (((high * 2 ^ shift : Nat) : Int) % 4294967296).toNat
      ((low : Int) % 4294967296).toNat : Nat))) : Except Lanius.Trap Value) = _
  rw [highBits, lowBits, combined]
  have wrapped := wrapSigned_i32_ofNat target _ bounded
  simpa only [Int.ofNat_eq_natCast] using congrArg
    (fun value => (Except.ok (.signed .i32 value) : Except Lanius.Trap Value)) wrapped

theorem evaluatesShiftLeft (value shift : Nat) (valid : shift < 32)
    (bounded : value * 2 ^ shift ≤ 2147483647)
    (evaluated : Evaluates program before expression (.signed .i32 value) after) :
    Evaluates program before (.binary .shiftLeft expression (.value (.signed .i32 shift)))
      (.signed .i32 (value * 2 ^ shift : Nat)) after := by
  apply evaluatesEagerBinary (by decide) (by decide) evaluated
    (show Evaluates program after (.value (.signed .i32 shift)) (.signed .i32 shift) after from ⟨1, rfl⟩)
  simpa only [evalBinaryValue, BEq.rfl, if_true] using shiftLeft program.target value shift valid bounded

theorem evaluatesJoin (high low shift : Nat) (lowBound : low < 2 ^ shift)
    (bounded : high * 2 ^ shift + low ≤ 2147483647)
    (left : Evaluates program before leftExpr (.signed .i32 (high * 2 ^ shift : Nat)) middle)
    (right : Evaluates program middle rightExpr (.signed .i32 low) after) :
    Evaluates program before (.binary .bitOr leftExpr rightExpr)
      (.signed .i32 (high * 2 ^ shift + low : Nat)) after := by
  apply evaluatesEagerBinary (by decide) (by decide) left right
  simpa only [evalBinaryValue, BEq.rfl, if_true] using join program.target high low shift lowBound bounded

theorem evaluatesWord (a b c d : Nat) (ha : a < 16) (hb : b < 16) (hc : c < 16) (hd : d < 16)
    (first : Evaluates program before firstExpr (.signed .i32 a) afterFirst)
    (second : Evaluates program afterFirst secondExpr (.signed .i32 b) afterSecond)
    (third : Evaluates program afterSecond thirdExpr (.signed .i32 c) afterThird)
    (fourth : Evaluates program afterThird fourthExpr (.signed .i32 d) after) :
    Evaluates program before
      (.binary .bitOr
        (.binary .bitOr
          (.binary .bitOr
            (.binary .shiftLeft firstExpr (.value (.signed .i32 12)))
            (.binary .shiftLeft secondExpr (.value (.signed .i32 8))))
          (.binary .shiftLeft thirdExpr (.value (.signed .i32 4)))) fourthExpr)
      (.signed .i32 (a * 4096 + b * 256 + c * 16 + d : Nat)) after := by
  have one := evaluatesShiftLeft a 12 (by decide) (by simp only [Nat.reducePow]; omega) first
  have two := evaluatesShiftLeft b 8 (by decide) (by simp only [Nat.reducePow]; omega) second
  have three := evaluatesShiftLeft c 4 (by decide) (by simp only [Nat.reducePow]; omega) third
  have pair := evaluatesJoin a (b * 256) 12 (by simp only [Nat.reducePow]; omega) (by simp only [Nat.reducePow]; omega) one two
  have pairValue : a * 2 ^ 12 + b * 256 = (a * 16 + b) * 256 := by simp [Nat.add_mul, Nat.mul_assoc]
  rw [pairValue] at pair
  have triple := evaluatesJoin (a * 16 + b) (c * 16) 8
    (by simp only [Nat.reducePow]; omega) (by simp only [Nat.reducePow]; omega) pair three
  have tripleValue : (a * 16 + b) * 2 ^ 8 + c * 16 = (a * 256 + b * 16 + c) * 16 := by
    simp [Nat.add_mul, Nat.mul_assoc]
  rw [tripleValue] at triple
  have whole := evaluatesJoin (a * 256 + b * 16 + c) d 4
    (by simp only [Nat.reducePow]; omega) (by simp only [Nat.reducePow]; omega) triple fourth
  have value : (a * 256 + b * 16 + c) * 2 ^ 4 + d = a * 4096 + b * 256 + c * 16 + d := by
    simp [Nat.add_mul, Nat.mul_assoc]
  rw [value] at whole
  exact whole

end Lanius.Extraction.Entry.Hex
