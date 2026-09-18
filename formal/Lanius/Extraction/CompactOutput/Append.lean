import Lanius.Extraction.CompactOutput.Digit

namespace Lanius.Extraction.CompactOutput

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts

def nextPosition (capacity : Nat) (position : Int) : Int :=
  if 0 ≤ position ∧ position < capacity then position + 1 else -1

def appended (original : List Int) (capacity : Nat) (position value : Int) : List Int :=
  if 0 ≤ position ∧ position < capacity then original.set position.toNat value else original

theorem appended_length : (appended original capacity position value).length = original.length := by
  unfold appended
  split <;> simp

/-- A single contract for success and sticky errors, suitable for sequential
writers that must retain partial output on capacity exhaustion. -/
theorem CheckedByte.write (checked : CheckedByte program) (position : Int) (capacity value : Nat)
    (wellFormed : StateWellFormed before)
    (capacityBound : capacity ≤ original.length) (capacityFit : capacity ≤ 2147483647)
    (byteBound : value < 256)
    (backing : before.cellEntry? outputCell = some {
      id := outputCell, value := some (.array (signedI32Values original)) })
    (argumentsResult : ArgumentsEvaluateTo program.core caller arguments
      (byteValues (.slice i32 outputCell [] 0 original.length) capacity position value) before) :
    ∃ after, Evaluates program.core caller (.call checked.source.function.id arguments)
        (.signed .i32 (nextPosition capacity position)) after ∧
      after.cellEntry? outputCell = some {
        id := outputCell, value := some (.array (signedI32Values (appended original capacity position value))) } ∧
      CellEffect (CellSet.singleton outputCell) before after ∧ HeapFrame before after := by
  by_cases valid : 0 ≤ position ∧ position < capacity
  · have cast : (position.toNat : Int) = position := Int.toNat_of_nonneg valid.1
    obtain ⟨after, call, contents, effect, heapFrame⟩ :=
      (checked.append position.toNat capacity value (by omega) capacityBound capacityFit byteBound).call
        wellFormed (by simpa only [cast] using argumentsResult) backing
    exact ⟨after, by simpa only [nextPosition, if_pos valid, Int.natCast_add, Int.natCast_one, cast] using call,
      by simpa only [appended, if_pos valid] using contents, effect, heapFrame⟩
  · have bad : byteBad capacity position value = true := by
      by_cases negative : position ≤ -1
      · simp [byteBad, negative]
      · have beyond : (capacity : Int) ≤ position := by omega
        simp [byteBad, beyond]
    obtain ⟨after, call, _, effect, heapFrame⟩ :=
      (checked.reject _ capacity position value bad).call wellFormed argumentsResult
    exact ⟨after, by simpa only [nextPosition, if_neg valid] using call,
      by simpa only [appended, if_neg valid] using effect.empty_preserves_entry wellFormed backing,
      effect.weaken CellSet.empty_subset, heapFrame⟩

/-- Compose the actual nested hex_digit and output.byte calls, including
their left-to-right argument evaluation and fresh parameter allocations. -/
theorem append_digit (byte : CheckedByte program) (digit : CheckedDigit program)
    (position : Int) (capacity value : Nat) (bounded : value < 16)
    (wellFormed : StateWellFormed before)
    (capacityBound : capacity ≤ original.length) (capacityFit : capacity ≤ 2147483647)
    (backing : before.cellEntry? outputCell = some {
      id := outputCell, value := some (.array (signedI32Values original)) })
    (outputResult : Evaluates program.core before outputExpression (.slice i32 outputCell [] 0 original.length) before)
    (capacityResult : Evaluates program.core before capacityExpression (.signed .i32 capacity) before)
    (positionResult : Evaluates program.core before positionExpression (.signed .i32 position) before)
    (digitResult : Evaluates program.core before valueExpression (.signed .i32 value) before) :
    ∃ after, Evaluates program.core before
        (digitCall byte.source.function.id digit.source.function.id outputExpression capacityExpression positionExpression valueExpression)
        (.signed .i32 (nextPosition capacity position)) after ∧
      after.cellEntry? outputCell = some {
        id := outputCell, value := some (.array (signedI32Values (appended original capacity position (hexDigit value)))) } ∧
      CellEffect (CellSet.singleton outputCell) before after ∧ HeapFrame before after := by
  obtain ⟨afterDigit, digitCallResult, _, digitEffect, digitHeap⟩ :=
    (digit.call_digit value bounded).call wellFormed (.cons digitResult (.nil _ _))
  have argumentsResult := ArgumentsEvaluateTo.cons outputResult (.cons capacityResult
    (.cons positionResult (.cons digitCallResult (.nil _ _))))
  obtain ⟨after, call, contents, effect, heapFrame⟩ := byte.write position capacity (hexDigit value)
    digitEffect.wellFormed capacityBound capacityFit (hexDigit_bound bounded)
    (digitEffect.empty_preserves_entry wellFormed backing) argumentsResult
  exact ⟨after, call, contents, (digitEffect.weaken CellSet.empty_subset).trans effect, digitHeap.trans heapFrame⟩

end Lanius.Extraction.CompactOutput
