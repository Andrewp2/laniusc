import Lanius.Extraction.Entry.Files.Output.Source

namespace Lanius.Extraction.Entry.Files
open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Extraction.Frontend Lanius.Extraction.CompactOutput

variable {program : CoreSynthesis.Program.CheckedProgram artifacts}
variable {pipeline : File.Load.Pipeline program}

/-- Complete the first file body's resources from its constructed frontend
input and the actual startup header. Both cursors and every buffer-separation
fact are derived; the initial certificate history contains no assumed unit. -/
theorem OutputSource.resources
    (checked : OutputSource pipeline syntaxStage collectStage emitStage header buffers aliases literal framing)
    (frontend : FrontendSource pipeline syntaxStage buffers aliases literal framing)
    (loading : LoadingSource pipeline buffers aliases literal framing)
    (input : File.Load.Input pipeline (ready.bindLocal pipeline.path.argument (.signed .i32 1)))
    (inputStorage : InputStorage original input.toAvailable)
    (data : SyntaxData) (valid : data.Valid) (capacities : File.Syntax.Capacities data)
    (frontBuffers : File.Load.FrontendBuffers input data)
    (reads : syntaxStage.Reads data input.source.length (ready.bindLocal pipeline.path.argument (.signed .i32 1)))
    (grammar : data.grammar = Grammar.indexedLanius)
    (history : Allocation.HostReady buffers initial allocated)
    (frame : Pointers.AliasFrame aliases allocated original)
    (registry : Allocation.Registry original) (readyRegistry : Allocation.Registry ready)
    (names : (buffers.map Allocation.Buffer.binding).Nodup)
    (retained : Retained literal framing original ready)
    (untouched : List Int) (count : Nat)
    (originalOutput : original.local? framing.output = some
      (.slice (.scalar (.signed .i32)) outputCell [] 0 untouched.length))
    (outputStored : ready.cellEntry? outputCell = some {
      id := outputCell, value := some (.array (signedI32Values
        (Header.contents (Input.copiedBuffer [] untouched Framing.bytes) Framing.bytes.length count))) })
    (position : (Assertion.localPointsTo header.position positionCell
      (some (.signed .i32 (Framing.bytes.length + 16 : Nat)))).holds ready)
    (index : input.index = 1)
    (olderHandles : ∀ handle ∈ ready.world.fileHandles, handle.id < (ready.world.nextFileHandle : Int)) :
    ∃ resources : File.Resources pipeline syntaxStage collectStage emitStage pipeline.path.argument
        (ready.bindLocal pipeline.path.argument (.signed .i32 1)),
      resources.input = input ∧ resources.data = data ∧ resources.output.view.root = outputCell ∧
      History count [] [] resources.position resources.output.contents := by
  obtain ⟨semantic⟩ := checked.semantic.storage history frame registry readyRegistry names retained
  obtain ⟨output⟩ := checked.output.storage history frame registry readyRegistry names retained
  obtain ⟨semanticPacked, semanticPath, semanticSource, semanticScratch⟩ :=
    inputStorage.apart loading semantic checked.semantic history frame names checked.semanticLoading
  obtain ⟨outputPacked, outputPath, outputSource, outputScratch⟩ :=
    inputStorage.apart loading output checked.output history frame names checked.outputLoading
  let savedSemantic : File.SavedBuffer input :=
    ⟨semantic.view, semantic.values, semantic.member, semanticPacked, semanticPath, semanticSource, semanticScratch, semantic.stored⟩
  let savedOutput : File.SavedBuffer input :=
    ⟨output.view, output.values, output.member, outputPacked, outputPath, outputSource, outputScratch, output.stored⟩
  have positionBinding : ready.cellId? emitStage.position = some positionCell := by
    simpa only [checked.positionBinding] using position.1
  have positionRead : ready.local? emitStage.position = some (.signed .i32 (Framing.bytes.length + 16 : Nat)) := by
    simpa only [checked.positionBinding] using Assertion.localPointsTo_local _ _ _ _ position
  have currentPosition := (bindLocal_preserves_other_local
    (value := Value.signed .i32 1) readyRegistry.wellFormed checked.argumentPosition).trans positionRead
  have currentPositionBinding := (bindLocal_preserves_other_cellId ready pipeline.path.argument emitStage.position
    (.signed .i32 1) checked.argumentPosition).trans positionBinding
  have differentCursors : (ready.bindLocal pipeline.path.argument (.signed .i32 1)).cellId? pipeline.path.argument ≠
      (ready.bindLocal pipeline.path.argument (.signed .i32 1)).cellId? emitStage.position := by
    rw [currentPositionBinding]
    have old := StateWellFormed.cell_lt_next_of_entry readyRegistry.wellFormed position.2
    simp only [State.cellId?, State.bindLocal, State.bindCell, List.find?_cons, beq_self_eq_true, Option.map_some]
    exact fun same => (Nat.ne_of_lt old) (Option.some.inj same).symm
  let resources : File.Resources pipeline syntaxStage collectStage emitStage pipeline.path.argument
      (ready.bindLocal pipeline.path.argument (.signed .i32 1)) := {
    input, data, buffers := frontBuffers, valid, capacities, reads
    kindsFit := by rw [grammar]; decide
    grammarIdentity := congrArg Lanius.Compiler.Parser.IndexedGrammar.grammar grammar
    semantic := savedSemantic, output := savedOutput
    semanticCapacity := semantic.capacity, outputCapacity := output.capacity
    semanticRead := by simpa only [savedSemantic, semantic.capacity] using semantic.read
    outputRead := by simpa only [savedOutput, output.capacity] using output.read
    position := (Framing.bytes.length + 16 : Nat), positionRead := currentPosition
    semanticSeparate := frontend.apart data reads semantic checked.semantic history frame registry readyRegistry names retained checked.semanticFrontend
    outputSeparate := frontend.apart data reads output checked.output history frame registry readyRegistry names retained checked.outputFrontend
    outputSemantic := (semantic.apart output checked.semantic checked.output history frame names checked.semanticOutput).symm
    differentCursors
    indexBound := by rw [index]; decide
    olderHandles := olderHandles }
  have outputRoot : output.view.root = outputCell := by
    have originalRead : original.local? emitStage.output = some
        (.slice (.scalar (.signed .i32)) outputCell [] 0 untouched.length) := by
      simpa only [checked.outputBinding] using originalOutput
    have same := output.originalRead.symm.trans originalRead
    injection same with same
    injection same
  have currentStored := ((bindLocal_effect ready pipeline.path.argument (.signed .i32 1)).oldCells outputCell
    (StateWellFormed.cell_lt_next_of_entry readyRegistry.wellFormed outputStored) (by simp [CellSet.empty])).trans outputStored
  rw [← outputRoot, output.stored] at currentStored
  have outputWords : output.values =
      Header.contents (Input.copiedBuffer [] untouched Framing.bytes) Framing.bytes.length count :=
    signedI32Values_injective (Value.array.inj (Option.some.inj (congrArg Cell.value (Option.some.inj currentStored))))
  refine ⟨resources, rfl, rfl, outputRoot, ?_⟩
  change History count [] [] (Framing.bytes.length + 16 : Nat) output.values
  rw [outputWords]
  exact History.start count untouched

end Lanius.Extraction.Entry.Files
