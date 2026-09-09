import Lanius.Extraction.CompactOutput.Word.Assign

namespace Lanius.Extraction.CompactOutput.Assignments

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation

/-- Assignment payloads use -1 for absence. Adding one maps absence to zero
and nonnegative indices to positive wire values without signed overflow. -/
theorem encode_second (program : Program) (second : Int)
    (lower : -1 ≤ second) (upper : second < 2147483647)
    (readSecond : Evaluates program before expression (.signed .i32 second) before) :
    Evaluates program before (binary .add expression (number 1))
      (.signed .i32 (second + 1).toNat) before := by
  have nonnegative : 0 ≤ second + 1 := by omega
  have cast : ((second + 1).toNat : Int) = second + 1 := Int.toNat_of_nonneg nonnegative
  apply evaluatesEagerBinary (by decide) (by decide) readSecond
    (show Evaluates program before (number 1) (.signed .i32 1) before from ⟨1, rfl⟩)
  simp only [evalBinaryValue, evalSignedBinary, beq_self_eq_true, if_true]
  have wrapped : wrapSigned program.target .i32 (second + 1) = second + 1 := by
    simpa only [Int.ofNat_eq_natCast, cast] using
      wrapSigned_i32_ofNat program.target (second + 1).toNat (by omega)
  rw [wrapped, cast]

def fieldGuard : Expr :=
  binary .logicalOr (binary .lessEqual (read 8) negativeOne)
    (binary .lessEqual (read 9) (.unary .negate (number 2)))

theorem fields_valid (program : Program) (first : Nat) (second : Int)
    (lower : -1 ≤ second)
    (firstRead : before.local? 8 = some (.signed .i32 first))
    (secondRead : before.local? 9 = some (.signed .i32 second)) :
    Evaluates program before fieldGuard (.boolean false) before := by
  have firstGuard : Evaluates program before (binary .lessEqual (read 8) negativeOne) (.boolean false) before := by
    apply evaluatesEagerBinary (by decide) (by decide) (local_evaluates program firstRead)
      (negativeOne_evaluates program before)
    simp [evalBinaryValue, evalSignedBinary]
    omega
  have secondGuard : Evaluates program before
      (binary .lessEqual (read 9) (.unary .negate (number 2))) (.boolean false) before := by
    have negativeTwo : Evaluates program before (.unary .negate (number 2)) (.signed .i32 (-2)) before := by
      apply evaluatesUnary (show Evaluates program before (number 2) (.signed .i32 2) before from ⟨1, rfl⟩)
      simp [evalUnaryValue, wrapSigned, signedModulus, signedSignBit, SignedIntTy.bits]
    apply evaluatesEagerBinary (by decide) (by decide) (local_evaluates program secondRead)
      negativeTwo
    simp [evalBinaryValue, evalSignedBinary]
    omega
  exact evaluatesPureLogicalOr firstGuard secondGuard

end Lanius.Extraction.CompactOutput.Assignments
