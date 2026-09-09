import Lanius.Extraction.CompactOutput.Assignments.Source

namespace Lanius.Extraction.CompactOutput.Assignments

open Lanius.Core Lanius.Semantics Lanius.Properties

/-- Evaluate the actual signed division and guard. A spare trailing input
word does not increase the number of complete two-word assignments. -/
theorem entry_guard (program : Program) (count length : Nat)
    (lengthFit : length ≤ 2147483647)
    (countRead : before.local? 2 = some (.signed .i32 count))
    (lengthRead : before.local? 1 = some (.signed .i32 length)) :
    Evaluates program before entryGuard (.boolean (decide (length / 2 < count))) before := by
  have negative : Evaluates program before (binary .lessEqual (read 2) negativeOne) (.boolean false) before := by
    apply evaluatesEagerBinary (by decide) (by decide) (local_evaluates program countRead)
      (negativeOne_evaluates program before)
    simp [evalBinaryValue, evalSignedBinary]
    omega
  have quotient := evaluatesNatI32Divide (leftValue := length) (rightValue := 2)
    (local_evaluates program lengthRead)
    (show Evaluates program before (number 2) (.signed .i32 2) before from ⟨1, rfl⟩)
    (by decide) (by omega)
  have comparison : Evaluates program before
      (binary .lessEqual (read 2) (binary .divide (read 1) (number 2)))
      (.boolean (decide (count ≤ length / 2))) before := by
    apply evaluatesEagerBinary (by decide) (by decide) (local_evaluates program countRead) quotient
    simp only [evalBinaryValue, evalSignedBinary, beq_self_eq_true, if_true,
      Except.ok.injEq, Value.boolean.injEq, decide_eq_decide, Int.ofNat_eq_natCast]
    omega
  have negated : Evaluates program before
      (.unary .logicalNot (binary .lessEqual (read 2) (binary .divide (read 1) (number 2))))
      (.boolean (decide (length / 2 < count))) before := by
    apply evaluatesUnary comparison
    by_cases enough : count ≤ length / 2
    · simp [evalUnaryValue, enough, show ¬ length / 2 < count by omega]
    · simp [evalUnaryValue, enough, show length / 2 < count by omega]
  exact evaluatesPureLogicalOr negative negated

theorem entry_guard_passes (program : Program) (count length : Nat)
    (room : 2 * count ≤ length) (lengthFit : length ≤ 2147483647)
    (countRead : before.local? 2 = some (.signed .i32 count))
    (lengthRead : before.local? 1 = some (.signed .i32 length)) :
    Evaluates program before entryGuard (.boolean false) before := by
  have noError : ¬ length / 2 < count := by omega
  simpa only [noError, decide_false] using entry_guard program count length lengthFit countRead lengthRead

theorem entry_guard_rejects (program : Program) (count length : Nat)
    (short : length < 2 * count) (lengthFit : length ≤ 2147483647)
    (countRead : before.local? 2 = some (.signed .i32 count))
    (lengthRead : before.local? 1 = some (.signed .i32 length)) :
    Evaluates program before entryGuard (.boolean true) before := by
  have error : length / 2 < count := by omega
  simpa only [error, decide_true] using entry_guard program count length lengthFit countRead lengthRead

end Lanius.Extraction.CompactOutput.Assignments
