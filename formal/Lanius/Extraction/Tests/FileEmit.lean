import Lanius.Extraction.Entry.File.Step
import Lean.Util.CollectAxioms

namespace Lanius.Extraction.Tests.FileEmit
open Lanius.Core Lanius.Semantics Lanius.Extraction.CompactOutput Lanius.Extraction.Frontend
open Lanius.Extraction.Entry.File

/-- Argument order, nested raw-count call, cursor mutation, and return guard.
Only the emitter body is replaced by an observation in these call-site tests. -/
def checkStage (program : Program) (typeId : TypeId) (function rawCount : FunctionId) (stage : Emit.Stage) : IO Unit := do
  unless (Emit.check? function rawCount (stage.statement function rawCount)).isSome do
    throw (IO.userError "exact emitter assignment and guard rejected")
  for index in [5, 8, 11, 13, 17, 18] do
    let changed := .sequence (.expression (.assign .set (.local stage.position)
      (.call function ((stage.arguments rawCount).set index (number 17)))))
      (.sequence (.ifThenElse (.binary .lessEqual (read stage.position) negativeOne)
        (returned (number 21)) .skip) stage.continuation)
    if (Emit.check? function rawCount changed).isSome then
      throw (IO.userError "emitter call accepted a changed capacity or disconnected input cursor")
  if (Emit.check? (function + 1) rawCount (stage.statement function rawCount)).isSome ||
      (Emit.check? function (rawCount + 1) (stage.statement function rawCount)).isSome then
    throw (IO.userError "emitter call accepted a different emitter or raw-count accessor")
  for (tokens, nodes, raw) in ([(0, 1, 0), (7, 3, 11), (65536, 65536, 65536)] : List (Nat × Nat × Nat)) do
    let bindings : List (VarId × Value) :=
      [(stage.path, .slice i32 101 [] 0 1024), (stage.pathLength, .signed .i32 9),
        (stage.source, .slice i32 102 [] 0 65536), (stage.sourceLength, .signed .i32 17),
        (stage.raw, .slice i32 103 [] 0 65536), (stage.canonical, .slice i32 104 [] 0 65536),
        (stage.tokens, .signed .i32 tokens), (stage.semantic, .slice i32 105 [] 0 131072),
        (stage.records, .slice i32 106 [] 0 1048576), (stage.offsets, .slice i32 107 [] 0 65536),
        (stage.nodes, .signed .i32 nodes), (stage.output, .slice i32 108 [] 0 16777216),
        (stage.position, .signed .i32 31),
        (stage.result, syntaxResult typeId 0 23 raw tokens nodes 41 43)]
    let before := ({} : State).bindLocals bindings
    let expected := [.slice i32 101 [] 0 1024, .signed .i32 9, .slice i32 102 [] 0 65536, .signed .i32 17,
      .slice i32 103 [] 0 65536, .signed .i32 65536, .signed .i32 raw,
      .slice i32 104 [] 0 65536, .signed .i32 65536, .signed .i32 tokens,
      .slice i32 105 [] 0 131072, .signed .i32 131072, .slice i32 106 [] 0 1048576,
      .signed .i32 1048576, .slice i32 107 [] 0 65536, .signed .i32 nodes,
      .slice i32 108 [] 0 16777216, .signed .i32 16777216, .signed .i32 31]
    let .done actual ready := evalExprs 100 program before (stage.arguments rawCount)
      | throw (IO.userError "emitter argument evaluation or embedded raw-count accessor failed")
    unless actual == expected && ready.locals == before.locals && ready.world.calls == before.world.calls do
      throw (IO.userError "emitter arguments mix source lengths, raw/canonical counts, capacities, or cursor")
    for outcome in ([-3, -1, 0, 11, 16777216] : List Int) do
      let some oldFunction := program.function? function
        | throw (IO.userError "emitter fixture refers to a missing function")
      let observer := { oldFunction with body := some (returned (.value (.signed .i32 outcome))) }
      let testProgram := { program with functions := observer :: program.functions.filter (fun found => found.id != function) }
      let probe := { stage with continuation := returned (read stage.position) }
      let .done (.returned (some actual)) after := execStmt 150 testProgram before (probe.statement function rawCount)
        | throw (IO.userError "emitter cursor assignment or guard did not complete")
      unless actual == .signed .i32 (if outcome <= -1 then 21 else outcome) &&
          after.local? stage.position == some (.signed .i32 outcome) && after.locals == before.locals do
        throw (IO.userError "emitter failed to assign its result before choosing the error/success branch")
      for (id, value) in bindings do
        unless id == stage.position || after.local? id == some value do
          throw (IO.userError "emitter call administration changed an unrelated caller local")

def checkPipeline (pipeline : Load.Pipeline program) (syntaxStage : Syntax.Stage)
    (resultsStage : Results.Stage) (collectStage : Collect.Stage) (stage : Emit.Stage) : IO Unit := do
  unless (Emit.checkRelation? pipeline syntaxStage resultsStage collectStage stage).isSome do
    throw (IO.userError "emitter inputs are disconnected from preceding file/frontend/collector bindings")
  for changed in [{ stage with path := stage.source }, { stage with source := stage.path },
      { stage with pathLength := stage.sourceLength }, { stage with sourceLength := stage.pathLength },
      { stage with raw := stage.canonical }, { stage with canonical := stage.raw },
      { stage with tokens := stage.nodes }, { stage with nodes := stage.tokens },
      { stage with records := stage.offsets }, { stage with offsets := stage.records },
      { stage with result := stage.tokens }, { stage with semantic := stage.output }] do
    if (Emit.checkRelation? pipeline syntaxStage resultsStage collectStage changed).isSome then
      throw (IO.userError "emitter accepted a swapped or disconnected loaded/frontend/collector input")
  for id in pipeline.boundLocals ++ [syntaxStage.result, resultsStage.nodes, resultsStage.tokens] do
    for changed in [{ stage with output := id }, { stage with position := id }] do
      if (Emit.checkRelation? pipeline syntaxStage resultsStage collectStage changed).isSome then
        throw (IO.userError "emitter accepted an output/cursor binding shadowed by the file prefix")

private def fixture : Program := { functions := [
  ⟨19, Unit.parameters, i32, some (returned (number 0)), none⟩,
  ⟨20, [(0, .structure 7)], i32, some (Lanius.Extraction.Source.projectionBody 2), none⟩] }
#eval checkStage fixture 7 19 20 ⟨0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, .skip⟩

run_elab do
  let standard : Array Lean.Name := #[``propext, ``Classical.choice, ``Quot.sound]
  for name in #[``Emit.Stage.arguments_evaluate, ``Emit.Stage.call_evaluates, ``Emit.Stage.executes,
      ``Emit.Stage.ready_reads, ``Emit.Stage.result_ready, ``Emit.storage,
      ``Load.FrontendBuffers.path_separate, ``FrontendReturn.path_ready, ``Unit.Storage.preserved,
      ``Lanius.Extraction.BufferCopy.copy_then_canonicalize, ``Lanius.Extraction.BufferCopy.copy_kinds,
      ``Host.MemoryFrame.ofRuntime, ``Host.MemoryPath.ofMetadata, ``Host.checked_evaluation,
      ``Host.MemoryTail.thenHeap, ``Host.MemoryTail.ready, ``Host.NativeReady.finish, ``Host.checked_statement_type,
      ``Host.ViewLayout.borrowed, ``Lanius.Semantics.CellOnly.execution,
      ``Lanius.Semantics.CellOnly.checked, ``Lanius.Semantics.CellOnly.Region.executes,
      ``Lanius.Semantics.CellOnly.Region.evaluates] do
    for assumption in ← Lean.collectAxioms name do
      unless standard.contains assumption do
        throwError "emitter continuation {name} adds unexpected axiom {assumption}"
  let baseline ← Lean.collectAxioms ``CheckedSyntax.call_evaluates
  let inherited := baseline.filter fun assumption => !standard.contains assumption
  for name in #[``Entry.File.step, ``Frontend.lex_then_count, ``Frontend.lex_to_canonical,
      ``Frontend.canonical_to_recognize, ``Frontend.lex_to_recognize,
      ``CheckedSyntax.call_native, ``CheckedSyntax.padded_call_native] do
    for assumption in ← Lean.collectAxioms name do
      unless standard.contains assumption || baseline.contains assumption do
        throwError "composed file/frontend theorem {name} adds unexpected axiom {assumption}"
  Lean.logInfo m!"File load/frontend/collector/emitter/cursor/guard composition adds no assumptions beyond the frontend baseline ({inherited.size} inherited nonstandard assumptions)."

end Lanius.Extraction.Tests.FileEmit
