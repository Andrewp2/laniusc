import Lanius.Extraction.Entry.File.Collect

namespace Lanius.Extraction.Entry.File
open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Extraction.Frontend Lanius.Extraction.SemanticTokens

variable {program : CoreSynthesis.Program.CheckedProgram artifacts}
variable {pipeline : Load.Pipeline program} {before : State}

/-- Extend `process` through the actual collector call and its guard. The
semantic buffer is an ordinary initial resource; its preservation, arguments,
capacity, collection, and successful guard are all derived inside this proof.
Only diagnostics and the emitter continuation remain execution premises. -/
theorem process_collect (pipeline : Load.Pipeline program) (syntaxStage : Syntax.Stage)
    {visit : ParserTreeSource.CheckedVisit program} {materializer : ParserTreeSource.CheckedMaterialize visit}
    (checked : CheckedSyntax materializer) (linked : LinkedSyntax checked)
    (source : pipeline.read.continuation = syntaxStage.statement checked.source.function.id)
    (relation : Syntax.Relation pipeline syntaxStage)
    (fragment : Semantics.Capacity.Fragment.Checked program.core allowed)
    (included : allowed checked.source.function.id = true)
    (accessors : Results.Accessors program checked.tail.finish.constructor.typeId)
    (resultsStage : Results.Stage) (resultsSupported : resultsStage.Supported)
    (resultsSource : syntaxStage.continuation = resultsStage.statement accessors.status.source.function.id
      accessors.nodes.source.function.id accessors.tokens.source.function.id)
    (resultsBinding : resultsStage.result = syntaxStage.result)
    (collector : SemanticTokens.Collect.CheckedCollect program) (collectStage : Collect.Stage)
    (collectMemory : CellOnly.Region program.core (.expression (.call collector.source.function.id collectStage.arguments)))
    (collectSource : resultsStage.continuation = collectStage.statement collector.source.function.id)
    (collectRelation : Collect.Relation pipeline syntaxStage resultsStage collectStage)
    (input : Load.Input pipeline before) (data : SyntaxData) (buffers : Load.FrontendBuffers input data)
    (valid : data.Valid) (capacities : Syntax.Capacities data) (reads : syntaxStage.Reads data input.source.length before)
    (kindsFit : data.grammar.grammar.n_kinds ≤ 32768)
    (semantic : SavedBuffer input) (semanticCapacity : semantic.contents.length = 131072)
    (semanticRead : before.local? collectStage.semantic = some
      (.slice CompactOutput.i32 semantic.view.root [] 0 semantic.contents.length))
    (separate : ∀ cell ∈ data.bufferRoots, cell ≠ semantic.view.root)
    (post : Scope.Post)
    (failureRun : ∀ observed : FrontendReturn input data, observed.status ≠ 0 → ∀ guarded,
      CellEffect CellSet.empty (observed.bound syntaxStage.result checked.tail.finish.constructor.typeId) guarded →
      Host.MemoryTail program.core observed.loadedState guarded →
      Prefix.Reaches program.core before (pipeline.path.statement pipeline.length.function.id) guarded resultsStage.failure →
      ∃ completion after, Executes program.core guarded resultsStage.failure completion after ∧ post completion after)
    (continuationRun : ∀ observed : FrontendReturn input data, observed.status = 0 → ∀ ready,
      StateWellFormed ready →
      CellEffect CellSet.empty (observed.bound syntaxStage.result checked.tail.finish.constructor.typeId)
        (restoreLocals (observed.bound syntaxStage.result checked.tail.finish.constructor.typeId) ready) →
      ready.local? resultsStage.nodes = some (.signed .i32 observed.nodes) →
      ready.local? resultsStage.tokens = some (.signed .i32 observed.count) →
      (∀ id, id ≠ resultsStage.nodes → id ≠ resultsStage.tokens → ready.cellId? id =
        (observed.bound syntaxStage.result checked.tail.finish.constructor.typeId).cellId? id) →
      (∀ id, id ≠ resultsStage.nodes → id ≠ resultsStage.tokens → ∀ value,
        (observed.bound syntaxStage.result checked.tail.finish.constructor.typeId).local? id = some value →
        ready.local? id = some value) →
      ∀ result : FrontendResult data observed.count observed.nodes observed.words ready,
      ∀ collection : CollectionRecords data.grammar (artifactTokens data.tokens) result.parse.tree 0 0,
      ∀ collected, collected.cellEntry? semantic.view.root = some { id := semantic.view.root, value := some (.array
        (signedI32Values (collection.assignments.flatMap Assignment.words ++ semantic.contents.drop (observed.count * 2)))) } →
      CellEffect (CellSet.singleton semantic.view.root) ready collected →
      Host.MemoryTail program.core observed.loadedState collected →
      ∃ completion after, Executes program.core collected collectStage.continuation completion after ∧ post completion after) :
    ∃ completion after, Executes program.core before (pipeline.path.statement pipeline.length.function.id) completion after ∧
      post completion after ∧ after.locals = before.locals := by
  apply process pipeline syntaxStage checked linked source relation fragment included accessors resultsStage resultsSupported
    resultsSource resultsBinding input data buffers valid capacities reads post failureRun
  intro observed success ready wellFormed effect memory nodeRead tokenRead bindings kept
  obtain ⟨result⟩ := frontend_result valid (observed.post_ready success effect) success
  have untouched : ¬ data.writes semantic.view.root := fun written => separate _ (SyntaxData.writes_in_roots written) rfl
  have collectorSeparate : ∀ cell ∈ [data.grammarCell, data.kindsCell, data.recordsCell, data.offsetsCell], cell ≠ semantic.view.root := by
    intro cell member
    apply separate cell
    simp only [List.mem_cons, List.not_mem_nil, or_false] at member
    rcases member with rfl | rfl | rfl | rfl <;> simp [SyntaxData.bufferRoots, SyntaxData.buffers]
  obtain ⟨completion, after, run, done⟩ := collectStage.executes collector collectMemory result valid capacities kindsFit wellFormed
    (observed.grammar_ready buffers valid effect) (observed.saved_ready semantic untouched effect)
    semanticCapacity collectorSeparate
    (collectStage.ready_reads collectRelation observed buffers (collectStage.initial_reads collectRelation reads semanticRead) kept)
    (collectRelation.tokens.symm ▸ tokenRead) (collectRelation.nodes.symm ▸ nodeRead) post
    (by
      intro collection collected contents collectedEffect heap
      exact continuationRun observed success ready wellFormed effect nodeRead tokenRead bindings kept result
        collection collected contents collectedEffect (memory.thenHeap heap))
  exact ⟨completion, after, collectSource.symm ▸ run, done⟩

end Lanius.Extraction.Entry.File
