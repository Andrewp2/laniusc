import Lanius.Extraction.Entry.File.Process
import Lean.Util.CollectAxioms

namespace Lanius.Extraction.Tests.FileResults
open Lanius.Core Lanius.Semantics Lanius.Extraction.CompactOutput Lanius.Extraction.Frontend
open Lanius.Extraction.Entry.File

/-- Exercise the actual accessor calls and surrounding control flow, replacing
only diagnostics and the downstream collector continuation with observations. -/
def check (program : Program) (typeId : TypeId) (statusId nodesId tokensId : FunctionId)
    (sourceStage : Results.Stage) : IO Unit := do
  unless (Results.check? statusId nodesId tokensId (sourceStage.statement statusId nodesId tokensId)).isSome &&
      sourceStage.checkSupported?.isSome do
    throw (IO.userError "valid frontend-result continuation rejected")
  if (Results.check? statusId nodesId tokensId (sourceStage.statement statusId tokensId nodesId)).isSome then
    throw (IO.userError "frontend-result continuation accepted swapped node/token accessors")
  for changed in [{ sourceStage with nodes := sourceStage.result }, { sourceStage with tokens := sourceStage.result },
      { sourceStage with tokens := sourceStage.nodes }] do
    if changed.checkSupported?.isSome then
      throw (IO.userError "frontend-result continuation accepted a shadowed result or count")
  for failure in [.skip, .expression (number 28),
      .ifThenElse (.value (.boolean true)) (returned (number 28)) .skip,
      .whileLoop (.value (.boolean false)) (returned (number 28))] do
    if ({ sourceStage with failure }).checkSupported?.isSome then
      throw (IO.userError "frontend diagnostic branch can fall through into the success path")
  let stage := { sourceStage with
    failure := returned (number 28)
    continuation := returned (.array i32 [read sourceStage.nodes, read sourceStage.tokens]) }
  for status in ([-1, 0, 1, 6] : List Int) do
    for (nodes, tokens) in ([(0, 0), (1, 7), (1048576, 65536)] : List (Int × Int)) do
      let before := ({ cells := [⟨0, some (.array (signedI32Values [51, 93]))⟩], nextCell := 1 } : State).bindLocals
        [(stage.nodes, .signed .i32 (-71)), (stage.tokens, .signed .i32 (-73)),
          (stage.result, syntaxResult typeId status 23 31 tokens nodes 41 43)]
      let wanted := if status == 0 then Value.array [.signed .i32 nodes, .signed .i32 tokens] else .signed .i32 28
      let .done (.returned (some actual)) after := execStmt 100 program before (stage.statement statusId nodesId tokensId)
        | throw (IO.userError "frontend-result guard or accessor execution trapped/exhausted")
      unless actual == wanted && after.locals == before.locals && after.world.calls == before.world.calls do
        throw (IO.userError "frontend-result guard, count projection, or caller scope changed")
      for cell in before.cells do
        unless (after.cellEntry? cell.id).map (fun entry => (entry.id, entry.value)) == some (cell.id, cell.value) do
          throw (IO.userError "frontend-result accessors or bindings changed an old buffer/local cell")

private def projection (id : FunctionId) (field : FieldId) : Function :=
  ⟨id, [(0, .structure 7)], i32, some (Source.projectionBody field), none⟩

#eval check { functions := [projection 11 0, projection 12 4, projection 13 3] } 7 11 12 13
  ⟨0, 1, 2, returned (number 28), .skip⟩

run_elab do
  for name in #[``Results.Stage.success, ``Results.Stage.dispatch, ``Results.check?, ``Results.checkAccessors?,
      ``Source.CheckedStop.not_next,
      ``Prefix.Reaches.typed, ``Host.checked_prefix_type,
      ``Entry.Scope.called, ``Entry.Scope.bound] do
    for assumption in ← Lean.collectAxioms name do
      unless assumption == ``propext || assumption == ``Classical.choice || assumption == ``Quot.sound do
        throwError "frontend-result continuation {name} adds unexpected axiom {assumption}"
  let baseline ← Lean.collectAxioms ``Frontend.CheckedSyntax.call_evaluates
  for assumption in ← Lean.collectAxioms ``Entry.File.process do
    unless assumption == ``propext || assumption == ``Classical.choice || assumption == ``Quot.sound || baseline.contains assumption do
      throwError "composed file prefix adds unexpected axiom {assumption}"
  Lean.logInfo "File prefix retains actual diagnostic reachability and derives entry typing without executing diagnostics; composition adds no assumptions beyond the existing frontend baseline."

end Lanius.Extraction.Tests.FileResults
