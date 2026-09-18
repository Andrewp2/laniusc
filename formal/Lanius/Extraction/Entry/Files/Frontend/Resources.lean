import Lanius.Extraction.Entry.Files.Frontend.Grammar

namespace Lanius.Extraction.Entry.Files
open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Extraction.Frontend Lanius.Extraction.RawLexer.LexInto
open Lanius.Compiler.Lexer Lanius.Compiler.Parser

variable {program : CoreSynthesis.Program.CheckedProgram artifacts}
variable {pipeline : File.Load.Pipeline program}

/-- Build the first public frontend invocation from startup's allocations and
decoded grammar. The logical request comes from the selected file. No parse
success, accepted output, or internal parser invariant is assumed. -/
theorem FrontendSource.prepare
    (checked : FrontendSource pipeline stage buffers aliases literal framing)
    (loading : LoadingSource pipeline buffers aliases literal framing)
    (input : File.Load.Input pipeline (ready.bindLocal pipeline.path.argument (.signed .i32 1)))
    (inputStorage : InputStorage original input.toAvailable)
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
      id := memory.destinationCell, value := some (.array (signedI32Values (memory.buffer memory.values))) }) :
    ∃ data : SyntaxData, data.Valid ∧ File.Syntax.Capacities data ∧
      Nonempty (File.Load.FrontendBuffers input data) ∧
      stage.Reads data input.source.length (ready.bindLocal pipeline.path.argument (.signed .i32 1)) ∧
      data.grammar = Grammar.indexedLanius := by
  obtain ⟨source⟩ := checked.source.storage history frame registry readyRegistry names retained
  obtain ⟨grammar⟩ := checked.grammar.storage history frame registry readyRegistry names retained
  obtain ⟨raw⟩ := checked.raw.storage history frame registry readyRegistry names retained
  obtain ⟨canonical⟩ := checked.canonical.storage history frame registry readyRegistry names retained
  obtain ⟨kinds⟩ := checked.kinds.storage history frame registry readyRegistry names retained
  obtain ⟨workspace⟩ := checked.workspace.storage history frame registry readyRegistry names retained
  obtain ⟨records⟩ := checked.records.storage history frame registry readyRegistry names retained
  obtain ⟨offsets⟩ := checked.offsets.storage history frame registry readyRegistry names retained
  have grammarWords := checked.grammarWords evidence memory selected originalGrammar readyRegistry initialized grammar
  have sourceRead : (ready.bindLocal pipeline.path.argument (.signed .i32 1)).local? stage.source =
      some (.slice (.scalar (.signed .i32)) input.source.root [] 0 input.source.length) := by
    simpa only [checked.sourceBinding] using input.sourceRead
  have sourceRoot : source.view.root = input.source.root := by
    have same := source.read.symm.trans sourceRead
    injection same with same
    injection same
  have sourceLength : input.source.length = 65536 := by
    have same := source.read.symm.trans sourceRead
    injection same with same
    injection same
    omega
  let request : Model.Request := {
    source := input.file.bytes.map UInt8.toFin
    capacity := 65536 / 3
    sourceFitsI32 := by have bound := input.fileFits; simp only [List.length_map]; omega
    recordsFitI32 := by decide }
  let tokens := canonicalizeTokens request.source (Model.emittedTokens request.outcome)
  have tokenBound : tokens.length ≤ 65536 / 3 := by
    have filtered := Lanius.Extraction.CanonicalTokens.Compaction.filtered_length
      request.source (Model.emittedTokens request.outcome)
    have rawBound := Model.emittedTokens_length_le_capacity request.source request.capacity
    simpa only [tokens, canonicalizeTokens,
      Lanius.Extraction.CanonicalTokens.Compaction.Range.retag_length] using Nat.le_trans filtered rawBound
  let layout : WorkspaceLayout := {
    tokenCount := tokens.length, workspaceLength := 4194304
    tokenBound := by unfold maxTokenCount; omega
    baseFits := by rw [stateBase_eq]; omega
    workspaceI32 := by decide }
  let data : SyntaxData := {
    request, records := raw.values, canonical := canonical.values, kinds := kinds.values,
    workspaceValues := workspace.values, treeRecords := records.values, treeOffsets := offsets.values,
    grammarLayout := evidence.layout, grammar := Grammar.indexedLanius, grammarWords := grammar.values,
    workspaceLayout := layout, sourceCell := source.view.root, rawCell := raw.view.root,
    canonicalCell := canonical.view.root, kindsCell := kinds.view.root, grammarCell := grammar.view.root,
    workspaceCell := workspace.view.root, recordsCell := records.view.root, offsetsCell := offsets.view.root, depth := 1024 }
  have apart {leftId rightId : VarId} {leftCount rightCount : Nat}
      (left : BufferStorage leftId leftCount original (ready.bindLocal pipeline.path.argument (.signed .i32 1)))
      (right : BufferStorage rightId rightCount original (ready.bindLocal pipeline.path.argument (.signed .i32 1)))
      (leftSource : BufferSource buffers aliases literal framing pipeline.path.argument leftId leftCount)
      (rightSource : BufferSource buffers aliases literal framing pipeline.path.argument rightId rightCount)
      (different : leftId ≠ rightId) : left.view.root ≠ right.view.root :=
    left.apart right leftSource rightSource history frame names different
  have ids := checked.distinct
  simp only [File.Syntax.Stage.bufferLocals, List.nodup_cons, List.mem_cons, List.not_mem_nil,
    or_false, not_or, List.nodup_nil, not_false_eq_true, and_true] at ids
  rcases ids with ⟨⟨_sg, sr, sc, sk, sw, srec, soff⟩, ⟨gr, gc, gk, gw, grec, goff⟩,
    ⟨rc, rk, rw, rrec, roff⟩, ⟨ck, cw, crec, coff⟩, ⟨kw, krec, koff⟩, ⟨wrec, woff⟩, recoff⟩
  have valid : data.Valid := {
    wordCapacity := by simp only [data, request, raw.capacity]
    recordsFit := by simp only [data, raw.capacity]; decide
    canonicalFit := by simp only [data, canonical.capacity]; decide
    kindsFit := by simp only [data, kinds.capacity]; decide
    grammarEncoded := by simpa only [data, grammarWords] using evidence.encoding
    grammarWellFormed := Grammar.indexedLanius_wellFormed
    wordsFit := by simp only [data, grammar.capacity]; decide
    workspaceLength := workspace.capacity
    workspaceTokenCount := rfl
    sourceRaw := apart source raw checked.source checked.raw sr
    sourceCanonical := apart source canonical checked.source checked.canonical sc
    sourceKinds := apart source kinds checked.source checked.kinds sk
    sourceWorkspace := apart source workspace checked.source checked.workspace sw
    rawCanonical := apart raw canonical checked.raw checked.canonical rc
    rawKinds := apart raw kinds checked.raw checked.kinds rk
    rawWorkspace := apart raw workspace checked.raw checked.workspace rw
    canonicalKinds := apart canonical kinds checked.canonical checked.kinds ck
    canonicalWorkspace := apart canonical workspace checked.canonical checked.workspace cw
    grammarRaw := apart grammar raw checked.grammar checked.raw gr
    grammarCanonical := apart grammar canonical checked.grammar checked.canonical gc
    grammarKinds := apart grammar kinds checked.grammar checked.kinds gk
    grammarWorkspace := apart grammar workspace checked.grammar checked.workspace gw
    kindsWorkspace := apart kinds workspace checked.kinds checked.workspace kw
    outputSeparation := by
      intro cell member
      simp only [data, List.mem_cons, List.not_mem_nil, or_false] at member
      rcases member with rfl | rfl | rfl | rfl | rfl | rfl
      · exact ⟨apart source records checked.source checked.records srec, apart source offsets checked.source checked.offsets soff⟩
      · exact ⟨apart raw records checked.raw checked.records rrec, apart raw offsets checked.raw checked.offsets roff⟩
      · exact ⟨apart canonical records checked.canonical checked.records crec, apart canonical offsets checked.canonical checked.offsets coff⟩
      · exact ⟨apart kinds records checked.kinds checked.records krec, apart kinds offsets checked.kinds checked.offsets koff⟩
      · exact ⟨apart grammar records checked.grammar checked.records grec, apart grammar offsets checked.grammar checked.offsets goff⟩
      · exact ⟨apart workspace records checked.workspace checked.records wrec, apart workspace offsets checked.workspace checked.offsets woff⟩
    outputsDistinct := apart records offsets checked.records checked.offsets recoff
    treeRecordsFit := by simp only [data, records.capacity]; decide
    treeOffsetsFit := by simp only [data, offsets.capacity]; decide
    depthFit := by change (1024 : Nat) ≤ 2147483647; decide }
  have capacities : File.Syntax.Capacities data :=
    ⟨grammar.capacity, raw.capacity, canonical.capacity, kinds.capacity, workspace.capacity, records.capacity, offsets.capacity, rfl⟩
  have saved {binding : VarId} {count : Nat}
      (storage : BufferStorage binding count original (ready.bindLocal pipeline.path.argument (.signed .i32 1)))
      (source : BufferSource buffers aliases literal framing pipeline.path.argument binding count)
      (member : binding ∈ stage.bufferLocals.tail) :
      ∃ view : I32ArrayView, view ∈ (ready.bindLocal pipeline.path.argument (.signed .i32 1)).i32ArrayViews ∧
        view.root = storage.view.root ∧ view.root ≠ input.packedPath.root ∧ view.root ≠ input.pathOutput.root ∧
        view.root ≠ input.source.root ∧ view.root ≠ input.scratch.root ∧
        (ready.bindLocal pipeline.path.argument (.signed .i32 1)).cellEntry? storage.view.root =
          some { id := storage.view.root, value := some (.array (signedI32Values storage.values)) } := by
    obtain ⟨packedPath, path, source, scratch⟩ := inputStorage.apart loading storage source history frame names
      (checked.loadingApart binding member)
    exact ⟨storage.view, storage.member, rfl, packedPath, path, source, scratch, storage.stored⟩
  refine ⟨data, valid, capacities, ⟨sourceRoot, rfl, ?_⟩, ?_, rfl⟩
  · intro buffer member
    simp only [SyntaxData.buffers, data, List.tail_cons, List.mem_cons, List.not_mem_nil, or_false] at member
    rcases member with rfl | rfl | rfl | rfl | rfl | rfl | rfl
    · exact saved raw checked.raw (by simp [File.Syntax.Stage.bufferLocals])
    · exact saved canonical checked.canonical (by simp [File.Syntax.Stage.bufferLocals])
    · exact saved kinds checked.kinds (by simp [File.Syntax.Stage.bufferLocals])
    · exact saved grammar checked.grammar (by simp [File.Syntax.Stage.bufferLocals])
    · exact saved workspace checked.workspace (by simp [File.Syntax.Stage.bufferLocals])
    · exact saved records checked.records (by simp [File.Syntax.Stage.bufferLocals])
    · exact saved offsets checked.offsets (by simp [File.Syntax.Stage.bufferLocals])
  · intro binding member
    simp only [File.Syntax.Stage.bufferBindings, data, sourceLength, grammar.capacity, raw.capacity,
      canonical.capacity, kinds.capacity, workspace.capacity, records.capacity, offsets.capacity,
      List.mem_cons, List.not_mem_nil, or_false] at member
    rcases member with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl
    · exact source.read
    · exact grammar.read
    · exact raw.read
    · exact canonical.read
    · exact kinds.read
    · exact workspace.read
    · exact records.read
    · exact offsets.read

end Lanius.Extraction.Entry.Files
