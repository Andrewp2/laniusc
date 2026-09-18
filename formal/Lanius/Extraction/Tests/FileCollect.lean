import Lanius.Extraction.Entry.File.Collected
import Lean.Util.CollectAxioms

namespace Lanius.Extraction.Tests.FileCollect
open Lanius.Core Lanius.Semantics Lanius.Extraction.CompactOutput
open Lanius.Extraction.Entry.File

/-- Focused call-site checks. The collector's tree traversal has its own
execution fixtures; these exercise argument identity and the actual guard. -/
def checkStage (function : FunctionId) (stage : Collect.Stage) : IO Unit := do
  unless (Collect.check? function (stage.statement function)).isSome do
    throw (IO.userError "exact collector continuation rejected")
  for index in [1, 5, 9] do
    let changed := .sequence (.ifThenElse (.binary .notEqual
      (.call function (stage.arguments.set index (number 17))) (number 0))
      (returned (number 20)) .skip) stage.continuation
    if (Collect.check? function changed).isSome then
      throw (IO.userError "collector continuation accepted a changed production capacity")
  if (Collect.check? (function + 1) (stage.statement function)).isSome then
    throw (IO.userError "collector continuation accepted a different callee")
  for (tokens, nodes) in ([(0, 1), (7, 3), (65536, 65536)] : List (Nat × Nat)) do
    let buffers : List Value := [.slice i32 101 [] 0 2179, .slice i32 102 [] 0 65536,
      .slice i32 103 [] 0 1048576, .slice i32 104 [] 0 65536, .slice i32 105 [] 0 131072]
    let before := ({} : State).bindLocals ((stage.bufferLocals.zip buffers) ++
      [(stage.tokens, .signed .i32 tokens), (stage.nodes, .signed .i32 nodes)])
    let expected := [buffers[0], .signed .i32 2179, buffers[1], .signed .i32 tokens,
      buffers[2], .signed .i32 1048576, buffers[3], .signed .i32 nodes, buffers[4], .signed .i32 131072]
    let .done values after := evalExprs 30 {} before stage.arguments
      | throw (IO.userError "collector argument evaluation failed")
    unless values == expected && after.locals == before.locals && after.nextCell == before.nextCell do
      throw (IO.userError "collector arguments mix buffers, logical counts, or physical capacities")
    for status in ([-2, -1, 0, 1] : List Int) do
      let parameters := (List.range 10).map (fun id => (id, if [0, 2, 4, 6, 8].contains id then .slice i32 else i32))
      let program : Program := { functions := [⟨function, parameters, i32,
        some (returned (.value (.signed .i32 status))), none⟩] }
      let probe := { stage with continuation := returned (.array i32 [read stage.tokens, read stage.nodes]) }
      let .done (.returned (some actual)) after := execStmt 100 program before (probe.statement function)
        | throw (IO.userError "collector guard did not complete")
      let wanted := if status == 0 then Value.array [.signed .i32 tokens, .signed .i32 nodes] else .signed .i32 20
      unless actual == wanted && after.locals == before.locals && after.world.calls == before.world.calls do
        throw (IO.userError "collector guard executed the wrong continuation or changed caller scope")
      for cell in before.cells do
        unless (after.cellEntry? cell.id).map (fun entry => (entry.id, entry.value)) == some (cell.id, cell.value) do
          throw (IO.userError "collector call administration changed an old caller cell")

def checkPipeline (pipeline : Load.Pipeline program) (syntaxStage : Syntax.Stage)
    (resultsStage : Results.Stage) (stage : Collect.Stage) : IO Unit := do
  unless (Collect.checkRelation? pipeline syntaxStage resultsStage stage).isSome do
    throw (IO.userError "collector is disconnected from the preceding frontend/result bindings")
  for changed in [{ stage with grammar := stage.kinds }, { stage with kinds := stage.grammar },
      { stage with records := stage.offsets }, { stage with offsets := stage.records },
      { stage with tokens := stage.nodes }, { stage with nodes := stage.tokens }] do
    if (Collect.checkRelation? pipeline syntaxStage resultsStage changed).isSome then
      throw (IO.userError "collector accepted a swapped frontend buffer or count")
  for id in pipeline.boundLocals ++ [syntaxStage.result, resultsStage.nodes, resultsStage.tokens] do
    if (Collect.checkRelation? pipeline syntaxStage resultsStage { stage with semantic := id }).isSome then
      throw (IO.userError "collector accepted a semantic-buffer local shadowed by the preceding prefix")

#eval checkStage 17 ⟨0, 1, 2, 3, 4, 5, 6, .skip⟩

run_elab do
  let standard : Array Lean.Name := #[``propext, ``Classical.choice, ``Quot.sound]
  for name in #[``Collect.Stage.arguments_evaluate, ``Collect.Stage.initial_reads, ``Collect.Stage.ready_reads,
      ``Collect.Stage.executes, ``FrontendReturn.original_local, ``FrontendReturn.post_ready, ``FrontendReturn.saved_ready] do
    for assumption in ← Lean.collectAxioms name do
      unless standard.contains assumption do
        throwError "collector continuation {name} adds unexpected axiom {assumption}"
  let baseline ← Lean.collectAxioms ``Lanius.Extraction.Frontend.CheckedSyntax.call_evaluates
  for assumption in ← Lean.collectAxioms ``process_collect do
    unless standard.contains assumption || baseline.contains assumption do
      throwError "composed file collector adds unexpected axiom {assumption}"
  Lean.logInfo "Actual file-loading/frontend/count-binding/collector composition adds no assumptions beyond the existing frontend baseline."

end Lanius.Extraction.Tests.FileCollect
