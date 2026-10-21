import Lanius.Semantics.StmtList

namespace Lanius.Semantics

open Lanius.Core

variable {guard : Expr}

theorem RunsStmt.whileReturn
    (condition : RunsExpr program state guard (.boolean true) middle)
    (iteration : RunsStmt program middle body (.returned result) after) :
    RunsStmt program state (.whileLoop guard body) (.returned result) after := by
  obtain ⟨guardFuel, guardRun, guardLocals⟩ := condition
  obtain ⟨bodyFuel, bodyRun, bodyLocals⟩ := iteration
  refine ⟨max guardFuel bodyFuel + 1, ?_, bodyLocals.trans guardLocals⟩
  intro fuel enough
  have first := guardRun (fuel - 1) (by omega)
  have second := bodyRun (fuel - 1) (by omega)
  rw [show fuel = (fuel - 1).succ by omega, execStmt.eq_def]
  simp only [first, second]

/-- The final guard may have effects; the body is not executed. -/
theorem RunsStmt.whileFalse
    (condition : RunsExpr program state guard (.boolean false) after) :
    RunsStmt program state (.whileLoop guard body) .next after := by
  obtain ⟨threshold, run, locals⟩ := condition
  refine ⟨threshold + 1, ?_, locals⟩
  intro fuel enough
  simpa only [show (fuel - 1).succ = fuel by omega] using
    execStmt_while_false (fuel - 1) program state guard body after
      (run (fuel - 1) (by omega))

/-- One continuing iteration composes guard, body, and the rest of the loop.
    Both ordinary fallthrough and an explicit `continue` recur. -/
theorem RunsStmt.whileStep
    (condition : RunsExpr program state guard (.boolean true) afterCondition)
    (iteration : RunsStmt program afterCondition body completion afterBody)
    (continues : completion = .next ∨ completion = .continueLoop)
    (rest : RunsStmt program afterBody (.whileLoop guard body) result after) :
    RunsStmt program state (.whileLoop guard body) result after := by
  obtain ⟨guardFuel, guardRun, guardLocals⟩ := condition
  obtain ⟨bodyFuel, bodyRun, bodyLocals⟩ := iteration
  obtain ⟨restFuel, restRun, restLocals⟩ := rest
  refine ⟨max guardFuel (max bodyFuel restFuel) + 1, ?_,
    restLocals.trans (bodyLocals.trans guardLocals)⟩
  intro fuel enough
  simpa only [show (fuel - 1).succ = fuel by omega] using
    execStmt_while_true_step (fuel - 1) program state guard body
      afterCondition afterBody after completion result
      (guardRun (fuel - 1) (by omega)) (bodyRun (fuel - 1) (by omega))
      continues (restRun (fuel - 1) (by omega))

/-- Total correctness for a loop consuming one item per iteration. The
    invariant can include an output prefix, memory frame, and remaining input.
    Clients prove one step for every invariant state, not an execution trace
    or an assumed successful run of the loop. Fuel is hidden by composition. -/
theorem RunsStmt.whileCount (invariant : Nat → State → Prop) (post : State → Prop)
    (finished : ∀ state, invariant 0 state → ∃ after,
      RunsExpr program state guard (.boolean false) after ∧ post after)
    (step : ∀ remaining state, invariant (remaining + 1) state →
      ∃ afterCondition afterBody completion,
        RunsExpr program state guard (.boolean true) afterCondition ∧
        RunsStmt program afterCondition body completion afterBody ∧
        (completion = .next ∨ completion = .continueLoop) ∧ invariant remaining afterBody)
    (initial : invariant remaining state) :
    ∃ after, RunsStmt program state (.whileLoop guard body) .next after ∧ post after := by
  induction remaining generalizing state with
  | zero =>
      obtain ⟨after, condition, result⟩ := finished state initial
      exact ⟨after, .whileFalse condition, result⟩
  | succ remaining ih =>
      obtain ⟨middle, next, completion, condition, iteration, continues, invariantNext⟩ :=
        step remaining state initial
      obtain ⟨after, rest, result⟩ := ih invariantNext
      exact ⟨after, .whileStep condition iteration continues rest, result⟩

/-- Total correctness for a bounded traversal that may reject during an
    iteration. A client proves the decreasing invariant or the returned result
    at each step; rejection is not an assumed successful run of the loop. -/
theorem RunsStmt.whileCountOrReturn
    (invariant : Nat → State → Prop) (post : Completion → State → Prop)
    (finished : ∀ state, invariant 0 state → ∃ after,
      RunsExpr program state guard (.boolean false) after ∧ post .next after)
    (step : ∀ remaining state, invariant (remaining + 1) state → ∃ middle,
      RunsExpr program state guard (.boolean true) middle ∧
        ((∃ after completion, RunsStmt program middle body completion after ∧
          (completion = .next ∨ completion = .continueLoop) ∧ invariant remaining after) ∨
        (∃ after value, RunsStmt program middle body (.returned value) after ∧
          post (.returned value) after)))
    (initial : invariant remaining state) :
    ∃ completion after, RunsStmt program state (.whileLoop guard body) completion after ∧
      post completion after := by
  induction remaining generalizing state with
  | zero =>
      obtain ⟨after, condition, result⟩ := finished state initial
      exact ⟨.next, after, .whileFalse condition, result⟩
  | succ remaining ih =>
      obtain ⟨middle, condition, iteration⟩ := step remaining state initial
      rcases iteration with ⟨next, _, bodyRun, continues, invariantNext⟩ | ⟨after, value, bodyRun, result⟩
      · obtain ⟨completion, after, rest, result⟩ := ih invariantNext
        exact ⟨completion, after, .whileStep condition bodyRun continues rest, result⟩
      · exact ⟨.returned value, after, .whileReturn condition bodyRun, result⟩

/-- A bounded continuing prefix may end either at the false guard or in a
    proved terminating iteration, such as an output-capacity error. -/
theorem RunsStmt.whilePrefix (invariant : Nat → State → Prop) (post : State → Prop)
    (finished : ∀ state, invariant 0 state → ∃ after,
      RunsStmt program state (.whileLoop guard body) result after ∧ post after)
    (step : ∀ remaining state, invariant (remaining + 1) state →
      ∃ middle after,
        RunsExpr program state guard (.boolean true) middle ∧
        RunsStmt program middle body .next after ∧ invariant remaining after)
    (initial : invariant remaining state) :
    ∃ after, RunsStmt program state (.whileLoop guard body) result after ∧ post after := by
  induction remaining generalizing state with
  | zero => exact finished state initial
  | succ remaining ih =>
      obtain ⟨middle, next, condition, iteration, invariantNext⟩ := step remaining state initial
      obtain ⟨after, rest, result⟩ := ih invariantNext
      exact ⟨after, .whileStep condition iteration (Or.inl rfl) rest, result⟩

end Lanius.Semantics
