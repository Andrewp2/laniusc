import SelfCore
import Lanius.Core.Bindings
import Lanius.Semantics.PureProof
import Lanius.Semantics.ScalarAssignment

namespace MatchArmStepTests

open Lanius Lanius.Core Lanius.Semantics

private def source := Extracted.«verified::lean_typed_body».Functions.«surface_match_output».core
private def right : Expr := match source.effectExpression 18 with
  | .assign _ _ expression => expression | _ => .value .unit

/-- The actual outer counter advances by one. This independently checks the
    final effect used by the connected arm theorem, against fresh admitted data. -/
theorem increments {state : State} (formed : state.CellsWellFormed) :
    let before := state.bindLocal (source.bindingId 5) (.signed .i32 0)
    ∃ after, RunsExpr extractedProgram before (source.effectExpression 18) .unit after ∧
      after.local? (source.bindingId 5) = some (.signed .i32 1) := by
  intro before
  have slot : before.cellId? (source.bindingId 5) = some state.nextCell := State.bindLocal_cellId _ _ _
  have found : before.local? (source.bindingId 5) = some (.signed .i32 0) := by core_local
  have read : RunsExpr extractedProgram before right (.signed .i32 1) before := by core_run
  obtain ⟨after, run, assigned, _⟩ := RunsExpr.assignI32 (op := .add) (replacement := 1)
    slot found read (by rfl)
  exact ⟨after, run, assignLocal_finds_assigned _ _ _ slot assigned⟩

#print axioms increments

end MatchArmStepTests
