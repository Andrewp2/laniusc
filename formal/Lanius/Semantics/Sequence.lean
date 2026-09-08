import Lanius.ExecutionRules

namespace Lanius.Semantics

/-- Normal completion of a sequence exposes the intermediate runtime state. -/
theorem executesSequenceNext_inv
    (execution : Executes program before (.sequence first second) .next after) :
    ∃ middle, Executes program before first .next middle ∧
      Executes program middle second .next after := by
  obtain ⟨fuel, executed⟩ := execution
  cases fuel with
  | zero => simp [execStmt] at executed
  | succ fuel =>
    rw [execStmt.eq_def] at executed
    simp only at executed
    cases firstRun : execStmt fuel program before first with
    | outOfFuel => simp [firstRun] at executed
    | trapped reason runtime => simp [firstRun] at executed
    | exited code runtime => simp [firstRun] at executed
    | done completion middle =>
      cases completion with
      | next => exact ⟨middle, ⟨fuel, firstRun⟩, ⟨fuel, by simpa [firstRun] using executed⟩⟩
      | returned result => simp [firstRun] at executed
      | breakLoop => simp [firstRun] at executed
      | continueLoop => simp [firstRun] at executed

/-- Append a continuation without changing the grouping used by the source. -/
theorem executesSequence_continue
    (execution : Executes program before (.sequence first second) .next middle)
    (continuation : Executes program middle rest completion after) :
    Executes program before (.sequence first (.sequence second rest)) completion after := by
  obtain ⟨between, firstRun, secondRun⟩ := executesSequenceNext_inv execution
  exact executesSequence firstRun (executesSequence secondRun continuation)

end Lanius.Semantics
