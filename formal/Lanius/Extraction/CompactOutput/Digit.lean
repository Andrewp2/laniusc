import Lanius.Extraction.CompactOutput.Byte

namespace Lanius.Extraction.CompactOutput

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView.Core

/-- Lowercase ASCII, as required by the compact decoder. -/
def hexDigit (value : Nat) : Nat := if value < 10 then 48 + value else 87 + value

theorem hexDigit_bound (bounded : value < 16) : hexDigit value < 256 := by
  unfold hexDigit
  split <;> omega

theorem digit_body (program : Program) (value : Nat) (bounded : value < 16)
    (found : before.local? 0 = some (.signed .i32 value)) :
    Executes program before digitBody (.returned (some (.signed .i32 (hexDigit value)))) before := by
  have condition : Evaluates program before (binary .less (read 0) (number 10))
      (.boolean (decide (value < 10))) before := by
    apply evaluatesEagerBinary (by decide) (by decide) (local_evaluates program found)
      (show Evaluates program before (number 10) (.signed .i32 10) before from ⟨1, rfl⟩)
    simp only [evalBinaryValue, evalSignedBinary, BEq.rfl, if_true, Except.ok.injEq, Value.boolean.injEq,
      decide_eq_decide]
    omega
  by_cases small : value < 10
  · simp only [hexDigit, if_pos small]
    have sum := evaluatesNatI32Add (leftValue := 48) (rightValue := value)
      (show Evaluates program before (number 48) (.signed .i32 48) before from ⟨1, rfl⟩)
      (local_evaluates program found) (by omega)
    exact executesSequenceReturned (executesIfTrue
      (by simpa only [small, decide_true] using condition)
      (executesSequenceReturned (executesReturnValue sum)))
  · simp only [hexDigit, if_neg small]
    have sum := evaluatesNatI32Add (leftValue := 87) (rightValue := value)
      (show Evaluates program before (number 87) (.signed .i32 87) before from ⟨1, rfl⟩)
      (local_evaluates program found) (by omega)
    exact executesSequence (executesIfFalse (by simpa only [small, decide_false] using condition)
      (executesSkip program before)) (executesSequenceReturned (executesReturnValue sum))

/-- A call to the checked source has no caller-visible writes. Fresh parameter
allocation is retained in the runtime but hidden from its caller's frame. -/
theorem CheckedDigit.call_digit (checked : CheckedDigit program) (value : Nat) (bounded : value < 16)
    (wellFormed : StateWellFormed before)
    (argumentsResult : ArgumentsEvaluateTo program.core caller arguments [.signed .i32 value] before) :
    ∃ after, Evaluates program.core caller (.call checked.source.function.id arguments)
        (.signed .i32 (hexDigit value)) after ∧ CellEffect CellSet.empty before after := by
  let bindings : List (VarId × Value) := [(0, .signed .i32 value)]
  have localValue : (enterCall before bindings).local? 0 = some (.signed .i32 value) :=
    enterCall_local_of_binding before [] [] 0 (.signed .i32 value) wellFormed (by simp)
  have run := digit_body program.core value bounded localValue
  exact ⟨restoreLocals before (enterCall before bindings),
    checked.call wellFormed argumentsResult (bindings := bindings) rfl run
      (CellEffect.refl (enterCall_preserves_wellFormed wellFormed))⟩

end Lanius.Extraction.CompactOutput
