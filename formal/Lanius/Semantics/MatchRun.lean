import Lanius.Semantics.CallRun

namespace Lanius.Semantics

open Lanius.Core

/-- Select the first matching arm using the language's existing pattern
    matcher. This is a proof adapter, not another emitted syntax tree. -/
def selectedArm (value : Value) : List (Pattern × Expr) → Option (List (VarId × Value) × Expr)
  | [] => none
  | (pattern, body) :: rest =>
      match matchPattern pattern value with
      | some bindings => some (bindings, body)
      | none => selectedArm value rest

private theorem evalMatchArms_selected
    (selected : selectedArm value arms = some (bindings, body))
    (run : StableExpr threshold program (state.bindLocals bindings) body result after)
    (enough : arms.length + threshold + 1 ≤ fuel) :
    evalMatchArms fuel program state value arms = .done result (restoreLocals state after) := by
  induction arms generalizing fuel with
  | nil => simp [selectedArm] at selected
  | cons arm rest ih =>
    obtain ⟨pattern, expression⟩ := arm
    cases matched : matchPattern pattern value with
    | none =>
      have restSelected : selectedArm value rest = some (bindings, body) := by
        simpa only [selectedArm, matched] using selected
      have restRun := ih restSelected (fuel := fuel - 1) (by simp at enough; omega)
      rw [show fuel = (fuel - 1).succ by simp at enough; omega, evalMatchArms.eq_def]
      simp only [matched, restRun]
    | some found =>
      have same : (found, expression) = (bindings, body) := by
        simpa only [selectedArm, matched, Option.some.injEq] using selected
      cases same
      have bodyRun := run (fuel - 1) (by simp at enough; omega)
      rw [show fuel = (fuel - 1).succ by simp at enough; omega, evalMatchArms.eq_def]
      simp only [matched, bodyRun, restoreOutcomeLocals, restoreLocals]

/-- Scrutinee effects happen before arm selection. Payload bindings acquire
    fresh cells; the selected body runs once and its lexical scope is restored. -/
theorem RunsExpr.matchValue
    (source : RunsExpr program before scrutinee value middle)
    (selected : selectedArm value arms = some (bindings, body))
    (branch : RunsExpr program (middle.bindLocals bindings) body result after) :
    RunsExpr program before (.matchValue scrutinee arms) result (restoreLocals middle after) := by
  obtain ⟨sourceFuel, sourceRun, sourceLocals⟩ := source
  obtain ⟨branchFuel, branchRun, _⟩ := branch
  refine ⟨max sourceFuel (arms.length + branchFuel + 1) + 1, ?_, sourceLocals⟩
  intro fuel enough
  have first := sourceRun (fuel - 1) (by omega)
  have second := evalMatchArms_selected selected branchRun (fuel := fuel - 1) (by omega)
  rw [show fuel = (fuel - 1).succ by omega, evalExpr.eq_def]
  simp only [first, second]

/-- A read-only scrutinee and a proved pure branch suffice; the payload's
    temporary cells need not leave the state exactly unchanged. -/
theorem RunsExpr.matchPure
    (source : RunsExpr program before scrutinee value before)
    (selected : selectedArm value arms = some (bindings, body))
    (formed : before.CellsWellFormed)
    (branch : ∃ completed, RunsExpr program (before.bindLocals bindings) body result completed ∧
      PureFrame (before.bindLocals bindings) completed) :
    ∃ after, RunsExpr program before (.matchValue scrutinee arms) result after ∧ PureFrame before after := by
  obtain ⟨completed, run, frame⟩ := branch
  exact ⟨restoreLocals before completed, RunsExpr.matchValue source selected run,
    (((CallerFrame.refl formed).bindLocals bindings).transPure frame).restoreLocals⟩

/-- A scrutinee may allocate temporary cells. Compose its proved pure frame
    with arm bindings and the branch; do not require state-identical evaluation. -/
theorem RunsExpr.matchFramedPure
    (source : ∃ middle, RunsExpr program before scrutinee value middle ∧ PureFrame before middle)
    (selected : selectedArm value arms = some (bindings, body))
    (branch : ∀ middle, PureFrame before middle →
      ∃ completed, RunsExpr program (middle.bindLocals bindings) body result completed ∧
        PureFrame (middle.bindLocals bindings) completed) :
    ∃ after, RunsExpr program before (.matchValue scrutinee arms) result after ∧ PureFrame before after := by
  obtain ⟨middle, source, first⟩ := source
  obtain ⟨completed, branch, rest⟩ := branch middle first
  exact ⟨restoreLocals middle completed, RunsExpr.matchValue source selected branch,
    first.trans (((CallerFrame.refl first.afterFormed).bindLocals bindings).transPure rest).restoreLocals⟩

end Lanius.Semantics
