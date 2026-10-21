import Lanius.Semantics.CallProof
import Lanius.Semantics.MutableLocal

namespace Lanius.Semantics

open Lanius.Core

private def program : Program := { functions := [{
  id := 7, parameters := [(1, .unit), (2, .scalar .bool)], returnType := .scalar .bool,
  body := some (.returnValue (some (.local 2))) }] }

private def before : State := ({} : State).bindLocal 2 (.boolean false)
private def middle : State := boundLocalAssigned {} 2 (.boolean false) (.boolean true)
private def bindings : List (Lanius.VarId × Value) := [(1, .unit), (2, .boolean true)]
private def completed : State := ({ middle with locals := [] }).bindLocals bindings
private def arguments : List Expr :=
  [.assign .set (.local 2) (.value (.boolean true)), .local 2]

-- The second argument observes the first argument's mutation. Parameters
-- shadow the caller's local, but returning restores its original cell binding.
example : RunsExpr program before (.call 7 arguments) (.boolean true)
      (restoreLocals before completed) ∧
    (restoreLocals before completed).local? 2 = some (.boolean true) ∧
    (restoreLocals before completed).cellId? 2 = before.cellId? 2 := by
  have assigned : RunsExpr program before
      (.assign .set (.local 2) (.value (.boolean true))) .unit middle :=
    .ofStable (StableExpr.assignSetBool program before 2 0 (.boolean false) true middle
      rfl rfl rfl rfl) rfl
  have secondArgument : middle.local? 2 = some (.boolean true) := rfl
  have values : RunsExprs program before arguments [.unit, .boolean true] middle := by core_arguments
  have body : RunsStmt program completed (.returnValue (some (.local 2)))
      (.returned (some (.boolean true))) completed :=
    .returnValue (.ofStable (.local rfl) rfl)
  have literalCall : RunsExpr program middle
      (.call 7 ([.unit, .boolean true].map Expr.value)) (.boolean true)
      (restoreLocals middle completed) :=
    RunsExpr.call rfl rfl (RunsExprs.values _) rfl body
  have actualCall : RunsExpr program before (.call 7 arguments) (.boolean true)
      (restoreLocals before completed) := by core_run
  fail_if_success
    have wrong : RunsExpr program before (.call 7 arguments) (.boolean false)
        (restoreLocals before completed) := by core_run
  exact ⟨actualCall, rfl, rfl⟩

-- Pure calls may append parameters, but do not change a shadowed caller local.
example : ∃ after, RunsExpr program before
      (.call 7 ([.unit, .boolean true].map Expr.value)) (.boolean true) after ∧
    PureFrame before after ∧ after.local? 2 = some (.boolean false) := by
  have formed : before.CellsWellFormed := by
    simp [State.CellsWellFormed, before, State.bindLocal, State.bindCell]
  obtain ⟨after, run, frame⟩ := RunsExpr.callUnchanged (program := program) (functionId := 7)
    (bindings := bindings)
    (values := [.unit, .boolean true]) rfl rfl rfl formed
    (RunsStmt.returnValue (RunsExpr.ofStable (StableExpr.local (by rfl)) rfl))
  exact ⟨after, run, frame, frame.cells.localFound frame.locals 2 _ rfl⟩

private def unitFunction : Function := {
  id := 8, parameters := [(1, .unit), (2, .scalar .bool)], returnType := .unit, body := some .skip }
private def unitProgram : Program := { functions := [unitFunction] }

-- Unit fallthrough retains argument side effects and restores shadowed locals.
example : RunsExpr unitProgram before (.call 8 arguments) .unit (restoreLocals before completed) ∧
    (restoreLocals before completed).local? 2 = some (.boolean true) ∧
    (restoreLocals before completed).cellId? 2 = before.cellId? 2 := by
  have assigned : RunsExpr unitProgram before
      (.assign .set (.local 2) (.value (.boolean true))) .unit middle :=
    .ofStable (StableExpr.assignSetBool unitProgram before 2 0 (.boolean false) true middle
      rfl rfl rfl rfl) rfl
  have secondArgument : middle.local? 2 = some (.boolean true) := rfl
  have values : RunsExprs unitProgram before arguments [.unit, .boolean true] middle := by core_arguments
  exact ⟨RunsExpr.callUnit (function := unitFunction) (bindings := bindings)
    rfl rfl rfl values rfl (RunsStmt.skip _ _), rfl, rfl⟩

#print axioms RunsExpr.callUnit

end Lanius.Semantics
