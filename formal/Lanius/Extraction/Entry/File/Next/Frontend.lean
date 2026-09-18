import Lanius.Extraction.Entry.File.Next

namespace Lanius.Extraction.Entry.File.Next
open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Extraction.Frontend Lanius.Extraction.RawLexer.LexInto
open Lanius.Compiler.Lexer Lanius.Compiler.Parser

variable {program : CoreSynthesis.Program.CheckedProgram artifacts}
variable {pipeline : Load.Pipeline program} {before after : State}
variable {input : Load.Input pipeline before} {data : SyntaxData}

/-- A registered buffer retains its capacity even when a preceding file has
overwritten every word. Recover its actual new contents; do not reset it. -/
theorem refreshedBuffer (buffers : Load.FrontendBuffers input data)
    (registry : Allocation.Registry after)
    (retained : ∀ view ∈ before.i32ArrayViews, view ∈ after.i32ArrayViews)
    (buffer : CellId × List Int) (member : buffer ∈ (data.buffers []).tail) :
    ∃ words : List Int, words.length = buffer.2.length ∧
      after.cellEntry? buffer.1 = some { id := buffer.1, value := some (.array (signedI32Values words)) } := by
  obtain ⟨view, present, root, _, _, _, _, original⟩ := buffers.other buffer member
  obtain ⟨elements, read, length, _⟩ := input.registry.arrays view present
  have exactValues : elements = signedI32Values buffer.2 := by
    simpa only [readCellProjection, input.registry.roots view present, root, original, projectedValue,
      Except.ok.injEq, Value.array.injEq] using read.symm
  have oldLength : buffer.2.length = view.length := by
    simpa only [exactValues, signedI32Values, List.length_map] using length
  obtain ⟨words, size, stored⟩ := registry.storage (retained view present)
  exact ⟨words, size.trans oldLength.symm, by simpa only [root] using stored⟩

/-- Rebuild the public frontend's data and ownership for a different file,
using the six dirty working arrays left by the previous iteration. The
workspace layout is derived from the next source's bounded token count.
No successful parse, zeroed storage, or internal parser invariant is assumed. -/
theorem frontend (nextInput : Load.Input pipeline after)
    (buffers : Load.FrontendBuffers input data) (valid : data.Valid) (capacities : Syntax.Capacities data)
    (sameSource : nextInput.source = input.source)
    (samePackedPath : nextInput.packedPath = input.packedPath)
    (samePath : nextInput.pathOutput = input.pathOutput)
    (sameScratch : nextInput.scratch = input.scratch)
    (retained : ∀ view ∈ before.i32ArrayViews, view ∈ after.i32ArrayViews)
    (grammar : after.cellEntry? data.grammarCell = some {
      id := data.grammarCell, value := some (.array (signedI32Values data.grammarWords)) }) :
    ∃ nextData : SyntaxData, nextData.Valid ∧ Syntax.Capacities nextData ∧
      Nonempty (Load.FrontendBuffers nextInput nextData) ∧
      nextData.grammar = data.grammar ∧ nextData.grammarWords = data.grammarWords ∧
      nextData.bufferRoots = data.bufferRoots ∧
      (∀ stage : Syntax.Stage, stage.bufferBindings nextData nextInput.source.length =
        stage.bufferBindings data input.source.length) := by
  obtain ⟨raw, rawLength, rawStored⟩ := refreshedBuffer buffers nextInput.registry retained
    (data.rawCell, data.records) (by simp [SyntaxData.buffers])
  obtain ⟨canonical, canonicalLength, canonicalStored⟩ := refreshedBuffer buffers nextInput.registry retained
    (data.canonicalCell, data.canonical) (by simp [SyntaxData.buffers])
  obtain ⟨kinds, kindsLength, kindsStored⟩ := refreshedBuffer buffers nextInput.registry retained
    (data.kindsCell, data.kinds) (by simp [SyntaxData.buffers])
  obtain ⟨workspace, workspaceLength, workspaceStored⟩ := refreshedBuffer buffers nextInput.registry retained
    (data.workspaceCell, data.workspaceValues) (by simp [SyntaxData.buffers])
  obtain ⟨records, recordsLength, recordsStored⟩ := refreshedBuffer buffers nextInput.registry retained
    (data.recordsCell, data.treeRecords) (by simp [SyntaxData.buffers])
  obtain ⟨offsets, offsetsLength, offsetsStored⟩ := refreshedBuffer buffers nextInput.registry retained
    (data.offsetsCell, data.treeOffsets) (by simp [SyntaxData.buffers])
  let request : Model.Request := {
    source := nextInput.file.bytes.map UInt8.toFin
    capacity := 65536 / 3
    sourceFitsI32 := by have fits := nextInput.fileFits; simp only [List.length_map]; omega
    recordsFitI32 := by decide }
  let tokens := canonicalizeTokens request.source (Model.emittedTokens request.outcome)
  have tokenBound : tokens.length ≤ 65536 / 3 := by
    have filtered := Lanius.Extraction.CanonicalTokens.Compaction.filtered_length
      request.source (Model.emittedTokens request.outcome)
    have rawBound := Model.emittedTokens_length_le_capacity request.source request.capacity
    simpa only [tokens, canonicalizeTokens,
      Lanius.Extraction.CanonicalTokens.Compaction.Range.retag_length] using Nat.le_trans filtered rawBound
  let layout : WorkspaceLayout := {
    tokenCount := tokens.length
    workspaceLength := 4194304
    tokenBound := by unfold maxTokenCount; omega
    baseFits := by rw [stateBase_eq]; omega
    workspaceI32 := by decide }
  let nextData : SyntaxData := {
    data with
    request := request
    records := raw
    canonical := canonical
    kinds := kinds
    workspaceValues := workspace
    treeRecords := records
    treeOffsets := offsets
    workspaceLayout := layout }
  have nextValid : nextData.Valid := {
    wordCapacity := by simp only [nextData, request, rawLength, capacities.raw]
    recordsFit := rawLength ▸ valid.recordsFit
    canonicalFit := canonicalLength ▸ valid.canonicalFit
    kindsFit := kindsLength ▸ valid.kindsFit
    grammarEncoded := valid.grammarEncoded
    grammarWellFormed := valid.grammarWellFormed
    wordsFit := valid.wordsFit
    workspaceLength := workspaceLength.trans capacities.workspace
    workspaceTokenCount := rfl
    sourceRaw := valid.sourceRaw
    sourceCanonical := valid.sourceCanonical
    sourceKinds := valid.sourceKinds
    sourceWorkspace := valid.sourceWorkspace
    rawCanonical := valid.rawCanonical
    rawKinds := valid.rawKinds
    rawWorkspace := valid.rawWorkspace
    canonicalKinds := valid.canonicalKinds
    canonicalWorkspace := valid.canonicalWorkspace
    grammarRaw := valid.grammarRaw
    grammarCanonical := valid.grammarCanonical
    grammarKinds := valid.grammarKinds
    grammarWorkspace := valid.grammarWorkspace
    kindsWorkspace := valid.kindsWorkspace
    outputSeparation := valid.outputSeparation
    outputsDistinct := valid.outputsDistinct
    treeRecordsFit := recordsLength ▸ valid.treeRecordsFit
    treeOffsetsFit := offsetsLength ▸ valid.treeOffsetsFit
    depthFit := valid.depthFit }
  have nextCapacities : Syntax.Capacities nextData :=
    ⟨capacities.grammar, rawLength.trans capacities.raw, canonicalLength.trans capacities.canonical,
      kindsLength.trans capacities.kinds, workspaceLength.trans capacities.workspace,
      recordsLength.trans capacities.records, offsetsLength.trans capacities.offsets, capacities.depth⟩
  have backing {cell : CellId} {oldWords words : List Int}
      (member : (cell, oldWords) ∈ (data.buffers []).tail)
      (stored : after.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values words)) }) :
      ∃ view : I32ArrayView, view ∈ after.i32ArrayViews ∧ view.root = cell ∧
        view.root ≠ nextInput.packedPath.root ∧ view.root ≠ nextInput.pathOutput.root ∧
        view.root ≠ nextInput.source.root ∧ view.root ≠ nextInput.scratch.root ∧
        after.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values words)) } := by
    obtain ⟨view, member, root, packed, path, source, scratch, _⟩ := buffers.other (cell, oldWords) member
    exact ⟨view, retained view member, root, samePackedPath.symm ▸ packed, samePath.symm ▸ path,
      sameSource.symm ▸ source, sameScratch.symm ▸ scratch, stored⟩
  refine ⟨nextData, nextValid, nextCapacities, ⟨?_, rfl, ?_⟩, rfl, rfl, rfl, ?_⟩
  · exact buffers.sourceCell.trans (congrArg I32ArrayView.root sameSource.symm)
  · intro buffer member
    simp only [SyntaxData.buffers, nextData, List.tail_cons, List.mem_cons, List.not_mem_nil, or_false] at member
    rcases member with rfl | rfl | rfl | rfl | rfl | rfl | rfl
    · exact backing (oldWords := data.records) (by simp [SyntaxData.buffers]) rawStored
    · exact backing (oldWords := data.canonical) (by simp [SyntaxData.buffers]) canonicalStored
    · exact backing (oldWords := data.kinds) (by simp [SyntaxData.buffers]) kindsStored
    · exact backing (oldWords := data.grammarWords) (by simp [SyntaxData.buffers]) grammar
    · exact backing (oldWords := data.workspaceValues) (by simp [SyntaxData.buffers]) workspaceStored
    · exact backing (oldWords := data.treeRecords) (by simp [SyntaxData.buffers]) recordsStored
    · exact backing (oldWords := data.treeOffsets) (by simp [SyntaxData.buffers]) offsetsStored
  · intro stage
    simp only [Syntax.Stage.bufferBindings, nextData, sameSource, rawLength, canonicalLength,
      kindsLength, workspaceLength, recordsLength, offsetsLength]

/-- Every frontend slice argument still names the original registered
storage after the file body closes its temporary bindings. -/
theorem syntaxReads {argument positionId : VarId} {position : Int} {nextData : SyntaxData}
    (frame : Handoff input data syntaxStage resultsStage argument positionId after)
    (sameLocals : after.locals = before.locals) (selected : argument = pipeline.path.argument)
    (relation : Relation pipeline syntaxStage resultsStage)
    (positionRead : before.local? positionId = some (.signed .i32 position))
    (reads : syntaxStage.Reads data input.source.length before)
    (sameBindings : syntaxStage.bufferBindings nextData capacity = syntaxStage.bufferBindings data input.source.length) :
    syntaxStage.Reads nextData capacity after := by
  intro binding member
  rw [sameBindings] at member
  have localMember : binding.1 ∈ syntaxStage.bufferLocals := by
    simpa only [Syntax.Stage.bufferBindings, Syntax.Stage.bufferLocals, List.map_cons, List.map_nil] using
      List.mem_map_of_mem (f := Prod.fst) member
  apply stableLocal frame sameLocals selected positionRead
    (relation binding.1 (List.mem_append_right _ localMember)) (reads _ member)
  · simp only [Syntax.Stage.bufferBindings, List.mem_cons, List.not_mem_nil, or_false] at member
    rcases member with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl <;> intro elements same <;> cases same
  · simp only [Syntax.Stage.bufferBindings, List.mem_cons, List.not_mem_nil, or_false] at member
    rcases member with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl <;> intro scalar same <;> cases same

end Lanius.Extraction.Entry.File.Next
