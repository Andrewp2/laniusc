import Lanius.Extraction.Diagnostics.Natural.Source
import Lanius.Separation.LocalStore

namespace Lanius.Extraction.Diagnostics.Natural

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Extraction.CompactOutput

/-- The first loop grows a positive divisor only while its product by ten
fits below the input. Its decreasing measure is the remaining quotient. -/
theorem grow (program : Program) (value divisor : Nat)
    (bounded : value ≤ 2147483647) (positive : 0 < divisor) (divisorBound : divisor ≤ 2147483647)
    (wellFormed : StateWellFormed before)
    (input : (Assertion.localPointsTo 0 valueCell (some (.signed .i32 value))).holds before)
    (owned : (Assertion.localPointsTo 1 divisorCell (some (.signed .i32 divisor))).holds before)
    (different : valueCell ≠ divisorCell) :
    ∃ finalDivisor after, Executes program before growLoop .next after ∧
      0 < finalDivisor ∧ finalDivisor ≤ 2147483647 ∧ value / finalDivisor < 10 ∧
      (Assertion.localPointsTo 0 valueCell (some (.signed .i32 value))).holds after ∧
      (Assertion.localPointsTo 1 divisorCell (some (.signed .i32 finalDivisor))).holds after ∧
      CellEffect (CellSet.singleton divisorCell) before after ∧ HeapFrame before after := by
  generalize quotientEq : value / divisor = quotient
  induction quotient using Nat.strongRecOn generalizing divisor before with
  | ind quotient ih =>
    have divided := evaluatesNatI32Divide (local_evaluates program (Assertion.localPointsTo_local _ _ _ _ input))
      (local_evaluates program (Assertion.localPointsTo_local _ _ _ _ owned)) positive
      (Nat.le_trans (Nat.div_le_self _ _) bounded)
    have condition : Evaluates program before growCondition (.boolean (decide (10 ≤ value / divisor))) before := by
      apply evaluatesEagerBinary (by decide) (by decide) divided
        (show Evaluates program before (number 10) (.signed .i32 10) before from ⟨1, rfl⟩)
      simp only [evalBinaryValue, evalSignedBinary, BEq.rfl, if_true, Except.ok.injEq,
        Value.boolean.injEq, decide_eq_decide, Int.ofNat_eq_natCast]
      omega
    by_cases more : 10 ≤ value / divisor
    · have productBound : divisor * 10 ≤ value := by
        have found := (Nat.le_div_iff_mul_le positive).mp more
        simpa only [Nat.mul_comm] using found
      have productFit := Nat.le_trans productBound bounded
      obtain ⟨middle, updated, divisorOwned, effect, heap⟩ := evaluatesOwnedLocalUpdate wellFormed owned
        (show Evaluates program before (number 10) (.signed .i32 10) before from ⟨1, rfl⟩)
        (op := .multiply) (replacement := .signed .i32 (divisor * 10 : Nat)) (by
          simp only [evalAssignValue, assignOpBinary?, evalBinaryValue, BEq.rfl, if_true, evalSignedBinary]
          have wrapped := wrapSigned_i32_ofNat program.target _ productFit
          simp only [Int.ofNat_eq_natCast] at wrapped
          rw [show (divisor : Int) * 10 = (divisor * 10 : Nat) from by simp, wrapped])
      have inputKept := effect.preserves_localPointsTo wellFormed input different
      have decreasing : value / (divisor * 10) < quotient := by
        rw [← Nat.div_div_eq_div_mul, quotientEq]
        exact Nat.div_lt_self (by omega) (by decide)
      obtain ⟨last, after, rest, lastPositive, lastBound, finished, inputAfter, divisorAfter, remaining, remainingHeap⟩ :=
        ih _ decreasing (divisor * 10) (by omega) productFit effect.wellFormed inputKept divisorOwned rfl
      exact ⟨last, after, executesWhileTrueThen (by simpa only [more, decide_true] using condition)
        (executesSequence (executesExpression updated) (executesSkip _ _)) rest,
        lastPositive, lastBound, finished, inputAfter, divisorAfter, effect.trans remaining, heap.trans remainingHeap⟩
    · exact ⟨divisor, before, executesWhileFalse (by simpa only [more, decide_false] using condition),
        positive, divisorBound, by omega, input, owned, CellEffect.refl wellFormed, HeapFrame.refl before⟩

end Lanius.Extraction.Diagnostics.Natural
