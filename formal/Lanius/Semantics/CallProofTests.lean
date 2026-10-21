import Lanius.Semantics.CallProof

namespace Lanius.Semantics.CallProofTests

open Lanius.Core

private def pick : Function := {
  id := 7, parameters := [(301, .unit), (907, .scalar .bool)], returnType := .scalar .bool,
  body := some (.returnValue (some (.local 907))) }
private def scopedPick : Function := {
  id := 8, parameters := [(907, .scalar .bool)], returnType := .scalar .bool,
  body := some (.letLocal 17 (.scalar .bool) (.local 907)
    (.returnValue (some (.local 17)))) }
private def program : Program := { functions := [pick, scopedPick] }

-- Parameter identities come from the declaration, not a hand-written binding
-- list. Caller locals may shadow either parameter without being overwritten.
theorem selects (formed : state.CellsWellFormed) (value : Bool) :
    ∃ after, RunsExpr program state
      (.call 7 [.value .unit, .value (.boolean value)]) (.boolean value) after ∧
      PureFrame state after := by
  core_call pick
  core_stmt

-- Reuse existing lookup evidence without reducing an opaque program table.
theorem selectsKnown (data : Program) (found : data.function? 7 = some pick)
    (formed : state.CellsWellFormed) (value : Bool) :
    ∃ after, RunsExpr data state (.call 7 [.value .unit, .value (.boolean value)]) (.boolean value) after ∧
      PureFrame state after := by
  core_call pick
  core_stmt

example (data : Program) (state : State) (unrelated : data.function? 8 = some scopedPick)
    (formed : state.CellsWellFormed) : True := by
  fail_if_success
    have wrong : ∃ after, RunsExpr data state (.call 7 [.value .unit, .value (.boolean true)]) (.boolean true) after ∧
        PureFrame state after := by
      core_call pick
      core_stmt
  trivial

-- A scoped local is allowed to allocate, but must restore the caller's scope
-- and preserve its existing cells, heap, world, and views.
theorem selectsWithLocal (formed : state.CellsWellFormed) (value : Bool) :
    ∃ after, RunsExpr program state (.call 8 [.value (.boolean value)]) (.boolean value) after ∧
      PureFrame state after := by
  core_call_pure scopedPick as callee
  have parameterRetained : callee.local? 907 = some (.boolean value) := by core_contract
  refine ⟨restoreLocals callee (callee.bindLocal 17 (.boolean value)), ?_, ?_⟩
  · core_stmt
  · exact ((CallerFrame.refl (by core_formed)).bindLocal 17 _).restoreLocals

-- Finding a declaration cannot prove an invented return value.
example {state : State} (formed : state.CellsWellFormed) : True := by
  fail_if_success
    have wrong : ∃ after, RunsExpr program state
        (.call 7 [.value .unit, .value (.boolean true)]) (.boolean false) after ∧
        PureFrame state after := by
      core_call pick
      core_stmt
  fail_if_success
    have wrong : ∃ after, RunsExpr program state
        (.call 8 [.value (.boolean true)]) (.boolean false) after ∧ PureFrame state after := by
      core_call_pure scopedPick as callee
      refine ⟨restoreLocals callee (callee.bindLocal 17 (.boolean true)), ?_, ?_⟩
      · core_stmt
      · exact ((CallerFrame.refl (by core_formed)).bindLocal 17 _).restoreLocals
  trivial

-- An actual declaration is not permission to ignore arity or lookup failure.
example {state : State} (formed : state.CellsWellFormed) : True := by
  fail_if_success
    have wrong : ∃ after, RunsExpr program state
        (.call 7 [.value (.boolean true)]) (.boolean true) after ∧ PureFrame state after := by
      core_call pick
      core_stmt
  fail_if_success
    have wrong : ∃ after, RunsExpr program state
        (.call 8 [.value .unit, .value (.boolean true)]) (.boolean true) after ∧
        PureFrame state after := by
      core_call pick
      core_stmt
  trivial

-- The pure-call helper must not silently drop effects from an argument.
example {state : State} (formed : state.CellsWellFormed) : True := by
  fail_if_success
    have wrong : ∃ after, RunsExpr program state
        (.call 7 [.assign .set (.local 301) (.value .unit), .value (.boolean true)])
        (.boolean true) after ∧ PureFrame state after := by
      core_call pick
      core_stmt
  trivial

-- Duplicate parameter IDs retain last-binding semantics, rather than an
-- unsound indexed lookup for the first parameter.
private def duplicatePick : Function := {
  id := 9, parameters := [(17, .scalar .bool), (17, .scalar .bool)],
  returnType := .scalar .bool, body := some (.returnValue (some (.local 17))) }
theorem selectsLast (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr { functions := [duplicatePick] } state
      (.call 9 [.value (.boolean false), .value (.boolean true)]) (.boolean true) after ∧
      PureFrame state after := by
  core_call duplicatePick
  core_stmt

#print axioms selectsLast
#print axioms selects
#print axioms selectsKnown
#print axioms selectsWithLocal

end Lanius.Semantics.CallProofTests
