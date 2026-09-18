import Lanius.Extraction.Entry.Files.Resources

namespace Lanius.Extraction.Entry.Files
open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation

variable {program : CoreSynthesis.Program.CheckedProgram artifacts}

/-- Enter and run the complete ordered-file phase from the actual startup
evidence. All first-file resources and the empty output history are constructed
here, then every iteration follows from the existing loop theorem. The result
still awaits the checked main's final suffix/packing/stdout continuation. -/
theorem CheckedSource.runFromStartup {countId : VarId} {continuation : Stmt}
    (checked : File.Checked program)
    (source : CheckedSource checked.argument countId checked.body continuation)
    (loading : LoadingSource checked.pipeline buffers aliases literal framing)
    (frontend : FrontendSource checked.pipeline checked.syntaxStage buffers aliases literal framing)
    (output : OutputSource checked.pipeline checked.syntaxStage checked.collectStage checked.emitStage header
      buffers aliases literal framing)
    (carried : File.Carried checked.pipeline checked.syntaxStage checked.resultsStage countId)
    (history : Allocation.HostReady buffers initial allocated)
    (frame : Pointers.AliasFrame aliases allocated original)
    (registry : Allocation.Registry original) (readyRegistry : Allocation.Registry ready)
    (names : (buffers.map Allocation.Buffer.binding).Nodup)
    (retained : Retained literal framing original ready)
    (evidence : Grammar.LiteralEvidence Grammar.indexedLanius literal.text)
    (memory : Grammar.Memory literal.setup.cursor.locals) (selected : memory.values = evidence.values)
    (originalGrammar : original.local? literal.setup.cursor.locals.destination = some
      (.slice (.scalar (.signed .i32)) memory.destinationCell [] 0 memory.untouched.length))
    (initialized : ready.cellEntry? memory.destinationCell = some {
      id := memory.destinationCell, value := some (.array (signedI32Values (memory.buffer memory.values))) })
    (untouched : List Int) (count : Nat) (countFit : count + 1 ≤ 2147483647)
    (originalOutput : original.local? framing.output = some
      (.slice (.scalar (.signed .i32)) outputCell [] 0 untouched.length))
    (outputStored : ready.cellEntry? outputCell = some {
      id := outputCell, value := some (.array (signedI32Values
        (Header.contents (Input.copiedBuffer [] untouched Framing.bytes) Framing.bytes.length count))) })
    (position : (Assertion.localPointsTo header.position positionCell
      (some (.signed .i32 (Framing.bytes.length + 16 : Nat)))).holds ready)
    (countRead : ready.local? countId = some (.signed .i32 (count + 1 : Nat)))
    (countApart : ready.cellId? countId ≠ ready.cellId? header.position)
    (mainTyped : Typing.StmtHasType program.core returnType context inLoop main)
    (beforeTyped : RuntimeStateHasType program.core context before store)
    (startup : Prefix.Reaches program.core before main ready continuation)
    (world : ready.world = { initialWorld with calls := calls })
    (pending : Pending initialWorld 1 (request :: rest))
    (endpoint : 1 + (request :: rest).length = count + 1)
    (handles : initialWorld.nextFileHandle + rest.length ≤ 2147483647)
    (olderHandles : ∀ handle ∈ initialWorld.fileHandles, handle.id < (initialWorld.nextFileHandle : Int))
    (sizeFit : 65536 < unsignedModulus program.core.target .usize) :
    ∃ loopContext completion after,
      Prefix.Reaches program.core before main (ready.bindLocal checked.pipeline.path.argument (.signed .i32 1))
        (statement checked countId) ∧
      Executes program.core (ready.bindLocal checked.pipeline.path.argument (.signed .i32 1))
        (statement checked countId) completion after ∧
      Result checked loopContext countId count ((request :: rest).map Request.source) outputCell
        (ready.bindLocal checked.pipeline.path.argument (.signed .i32 1)) completion after ∧
      Progress ((request :: rest).map Request.source) checked.emitStage.position
        (Framing.bytes.length + 16 : Nat) completion after := by
  let pipelineSource : CheckedSource checked.pipeline.path.argument countId checked.body continuation := by
    simpa only [checked.advanceRelation.selected] using source
  obtain ⟨loopContext, loopStore, resources, reached, typed, bodyTyped, index, _path, _file,
      packedPath, pathLength, _sourceLength, _scratch, outputRoot, certificateHistory⟩ :=
    pipelineSource.resources loading frontend output history frame registry readyRegistry names retained
      evidence memory selected originalGrammar initialized untouched count originalOutput outputStored position
      mainTyped beforeTyped startup world pending (by omega) olderHandles sizeFit
  let first : File.Resources checked.pipeline checked.syntaxStage checked.collectStage checked.emitStage checked.argument
      (ready.bindLocal checked.pipeline.path.argument (.signed .i32 1)) := {
    resources with differentCursors := by simpa only [checked.advanceRelation.selected] using resources.differentCursors }
  have currentCount := (bindLocal_preserves_other_local
    (value := Value.signed .i32 1) readyRegistry.wellFormed pipelineSource.distinct).trans countRead
  have currentApart : (ready.bindLocal checked.pipeline.path.argument (.signed .i32 1)).cellId? countId ≠
      (ready.bindLocal checked.pipeline.path.argument (.signed .i32 1)).cellId? checked.emitStage.position := by
    rw [bindLocal_preserves_other_cellId ready checked.pipeline.path.argument countId (.signed .i32 1) pipelineSource.distinct,
      bindLocal_preserves_other_cellId ready checked.pipeline.path.argument checked.emitStage.position
        (.signed .i32 1) output.argumentPosition, output.positionBinding]
    exact countApart
  have currentPending : Pending (ready.bindLocal checked.pipeline.path.argument (.signed .i32 1)).world 1 (request :: rest) := by
    change Pending ready.world 1 (request :: rest)
    rw [world]
    exact ⟨pending.selected, pending.files, pending.nonempty, pending.pathFits, pending.fileFits⟩
  have firstInput : first.input = resources.input := rfl
  obtain ⟨completion, after, run, result, progress⟩ := executes checked countId carried bodyTyped count countFit first typed
    [] [] request rest
    (by simpa only [first] using certificateHistory)
    (by simpa only [firstInput, List.length_nil] using index)
    (by simpa only [firstInput, index] using endpoint)
    (by simpa only [firstInput, index] using currentPending)
    (by simpa only [State.bindLocal, State.bindCell, world] using handles)
    (by rw [firstInput, packedPath]; decide)
    (by rw [firstInput, pathLength]; decide) currentCount currentApart
  refine ⟨loopContext, completion, after, ?_, run, ?_, ?_⟩
  · simpa only [statement, checked.advanceRelation.selected] using reached
  · simpa only [List.nil_append, first, outputRoot] using result
  · have initialPosition : first.position = (Framing.bytes.length + 16 : Nat) := by
      simpa only [first, bytes, List.flatMap_nil, List.append_nil, List.length_append,
        List.length_map, Header.encoding_length] using certificateHistory.cursor
    simpa only [initialPosition] using progress

end Lanius.Extraction.Entry.Files
