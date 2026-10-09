import Lanius.Semantics.ExpressionProof

namespace Lanius.Semantics.WellFormedAutomationTests

open Lanius.Core

-- The program and expressions remain symbolic: propagation must not run them.
example (formed : before.CellsWellFormed)
    (run : RunsExpr program before expression value after) : after.CellsWellFormed := by
  core_formed

example (formed : before.CellsWellFormed)
    (run : RunsStmt program before statement flow after) : after.CellsWellFormed := by
  core_formed

example (formed : before.CellsWellFormed)
    (run : RunsExprs program before arguments values after) : after.CellsWellFormed := by
  core_formed

example (formed : before.CellsWellFormed)
    (run : Evaluates program before expression value after) : after.CellsWellFormed := by
  core_formed

example (formed : before.CellsWellFormed)
    (run : Executes program before statement flow after) : after.CellsWellFormed := by
  core_formed

-- Reverse hypothesis order and binding/scope/heap changes between calls.
theorem chained {before : State} {localId other : VarId} (formed : before.CellsWellFormed)
    (last : RunsStmt program (middle.bindLocal localId value) statement flow after)
    (first : RunsExprs program ({ before with locals := [] }.bindLocals bindings)
      arguments values middle) :
    ({ after with locals := [], heap := heap, world := world }.bindCell other none).CellsWellFormed := by
  core_formed

-- An execution edge is not a seed, even in a cycle. Unrelated output states
-- and a changed allocation frontier cannot be substituted for proved states.
example (_first : RunsExpr program before expression value after)
    (_last : RunsExpr program after expression value before) : True := by
  fail_if_success have wrong : after.CellsWellFormed := by core_formed
  trivial

example (_formed : before.CellsWellFormed)
    (_run : RunsExpr program before expression value after) (_unrelated : State) : True := by
  fail_if_success have wrong : _unrelated.CellsWellFormed := by core_formed
  fail_if_success have wrong : { after with nextCell := 0 }.CellsWellFormed := by core_formed
  trivial

-- Allocation laws say nothing about retaining values of mutable cells.
example {localId : VarId} (_formed : before.CellsWellFormed)
    (_run : RunsExpr program before expression value after)
    (_found : before.local? localId = some value) : True := by
  fail_if_success have wrong : after.local? localId = some value := by core_local
  trivial

#print axioms chained

end Lanius.Semantics.WellFormedAutomationTests
