import Lanius.Extraction.Entry.File.Certificate
import Lanius.Extraction.Entry.File.Progress
import Lanius.Extraction.Diagnostics.Frontend

namespace Lanius.Extraction.Entry.File
open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Extraction.Frontend Lanius.Extraction.SemanticTokens Lanius.Extraction.CompactOutput
open Emit

variable {program : CoreSynthesis.Program.CheckedProgram artifacts} {before : State}

/-- On the supported loading domain, one complete file body either advances
or returns the frontend/output error code. External inputs and old handles
are preserved on every branch, not just on successful extraction. -/
structure Result (before : State) (outcome : Completion) (after : State) : Prop where
  completion : outcome = .next ∨ outcome = .returned (some (.signed .i32 21)) ∨
    outcome = .returned (some (.signed .i32 28))
  arguments : after.world.arguments = before.world.arguments
  files : after.world.files = before.world.files
  handles : after.world.fileHandles = before.world.fileHandles
  stdout : after.world.standardOutput = before.world.standardOutput
  stderr : outcome = .next → after.world.standardError = before.world.standardError

theorem Result.restore {before after : State} {completion : Completion}
    (result : Result before completion after) (caller : State) : Result before completion (restoreLocals caller after) :=
  ⟨result.completion, result.arguments, result.files, result.handles, result.stdout, result.stderr⟩

private theorem loaded_result {pipeline : Load.Pipeline program} {before after : State}
    (input : Load.Input pipeline before) {reads : Nat}
    (world : after.world = input.loadedWorld reads)
    (classified : completion = .next ∨ completion = .returned (some (.signed .i32 21)) ∨
      completion = .returned (some (.signed .i32 28))) : Result before completion after := by
  refine ⟨classified, ?_, ?_, ?_, ?_, ?_⟩ <;> simp only [world, Load.Available.loadedWorld, implies_true]

/-- One source-linked file iteration, including loading, frontend, collection,
emission, cursor assignment, and the final argument increment. Both success
and frontend diagnostics construct every component execution on the stated
input domain. No component-execution or logical-postcondition callback is
required from callers of this complete file-body theorem.
The checked statement and ordinary typed entry derive final runtime typing;
on success the next iteration receives a complete native registry and word
ranges, including any views borrowed inside frontend helpers, plus the
logical handoff used to reconstruct the next invocation's resources. -/
theorem step {store : StoreTyping} (pipeline : Load.Pipeline program) (syntaxStage : Syntax.Stage)
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
    (rawCount : Source.CheckedProjection program ["verified", "extraction"] "raw_count" checked.tail.finish.constructor.typeId 2)
    (word : Word.Checked program byte digit) (bytes : Bytes.Checked program byte digit hex)
    (tokens : Tokens.Checked program byte digit word) (assignmentWriter : Assignments.Checked program byte digit word)
    (nodes : Nodes.Checked program byte digit word tokenTag stateTag)
    (unitWriter : Unit.Checked program ⟨word.source.function.id, bytes.source.function.id,
      tokens.source.function.id, assignmentWriter.source.function.id, nodes.source.function.id⟩)
    (tokenConstant : ParserTreeSource.constantValue program.core tokenTag 1)
    (stateConstant : ParserTreeSource.constantValue program.core stateTag 2)
    (emitStage : Stage)
    (emitMemory : CellOnly.Region program.core (emitStage.assignment unitWriter.source.function.id rawCount.source.function.id))
    (emitSource : collectStage.continuation = emitStage.statement unitWriter.source.function.id rawCount.source.function.id)
    (emitRelation : Relation pipeline syntaxStage resultsStage collectStage emitStage)
    (argument : VarId) (advanceSource : emitStage.continuation = Advance.statement argument)
    (advanceRelation : Advance.Relation pipeline syntaxStage resultsStage argument)
    (diagnostics : Diagnostics.CheckedFrontend program checked.tail.finish.constructor.typeId
      argument syntaxStage.result resultsStage.failure)
    (resources : Resources pipeline syntaxStage collectStage emitStage argument before)
    (typed : RuntimeStateHasType program.core context before store)
    (statementTyped : Typing.StmtHasType program.core returnType context true
      (pipeline.path.statement pipeline.length.function.id)) :
    ∃ completion after, Executes program.core before (pipeline.path.statement pipeline.length.function.id) completion after ∧
      Result before completion after ∧ Progress resources.input emitStage.position resources.position completion after ∧
      (completion = .next → Allocation.Registry after ∧ Host.RepresentableViews after ∧
        (∃ fresh, after.i32ArrayViews = before.i32ArrayViews ++ fresh) ∧
        Handoff resources.input resources.data syntaxStage resultsStage argument emitStage.position after ∧
        Emitted resources.input resources.output resources.position emitStage.position after) ∧
      after.locals = before.locals ∧
      ∃ afterStore, RuntimeStateHasType program.core context after afterStore := by
  let originalResources := resources
  rcases resources with ⟨input, data, buffers, valid, capacities, reads, kindsFit, grammarIdentity,
    semantic, output, semanticCapacity, outputCapacity, semanticRead, outputRead, position, positionRead,
    semanticSeparate, outputSeparate, outputSemantic, differentCursors, indexBound, _olderHandles⟩
  let nativePost : Scope.Post := {
    holds := fun completion after => Result before completion after ∧
      Progress input emitStage.position position completion after ∧
      (completion = .next → Host.NativeReady program.core before.i32ArrayViews after ∧
        Handoff input data syntaxStage resultsStage argument emitStage.position after ∧
        Emitted input output position emitStage.position after)
    restore := fun completion caller after proved =>
      ⟨proved.1.restore caller, proved.2.1.restore caller, fun next =>
        ⟨(proved.2.2 next).1.thenHeap ⟨rfl, rfl⟩, (proved.2.2 next).2.1.restore caller,
          (proved.2.2 next).2.2.restore caller⟩⟩ }
  obtain ⟨completion, after, run, satisfied, locals⟩ : ∃ completion after,
      Executes program.core before (pipeline.path.statement pipeline.length.function.id) completion after ∧
      nativePost completion after ∧ after.locals = before.locals := by
    apply process_collect pipeline syntaxStage checked linked source relation fragment included accessors resultsStage resultsSupported
      resultsSource resultsBinding collector collectStage collectMemory collectSource collectRelation input data buffers valid capacities reads
      kindsFit semantic semanticCapacity semanticRead semanticSeparate nativePost
    · intro observed failure guarded effect memory reached
      obtain ⟨guardContext, guardStore, _failureTyped, guardTyped⟩ := Host.checked_prefix_type program statementTyped typed reached
      have frame := memory.finish guardTyped
      have boundWF := observed.bound_wellFormed syntaxStage.result checked.tail.finish.constructor.typeId
      have argumentRead := observed.original_local buffers (advanceRelation.selected.symm ▸ input.indexRead)
        (by intro elements same; cases same) advanceRelation.loaded advanceRelation.result
        (effect.empty_preserves_local boundWF)
      have resultRead := effect.empty_preserves_local boundWF
        (show (observed.bound syntaxStage.result checked.tail.finish.constructor.typeId).local? syntaxStage.result =
          some (observed.value checked.tail.finish.constructor.typeId) from
          bindLocal_finds_local _ _ _ observed.effect.wellFormed)
      obtain ⟨after, run, registered, representable, diagnosticEffect, diagnosticWorld⟩ := diagnostics.executes guardTyped
        (frame.registry observed.loaded.registry) (frame.representable observed.loaded.registry observed.loaded.representable)
        argumentRead resultRead
      obtain ⟨readCount, _, world⟩ := observed.loaded.world
      have guardedWorld : guarded.world = input.loadedWorld readCount :=
        effect.world.trans (observed.effect.world.trans world)
      obtain ⟨diagnosticBytes, stderrWorld⟩ := diagnosticWorld
      have progress : Progress input emitStage.position position (.returned (some (.signed .i32 28))) after := by
        intro bound supported _ _
        exact False.elim (failure (originalResources.supported_frontend supported observed))
      refine ⟨.returned (some (.signed .i32 28)), after, run,
        ⟨Or.inr (Or.inr rfl), ?_, ?_, ?_, ?_, fun impossible => Completion.noConfusion impossible⟩,
        progress, fun impossible => Completion.noConfusion impossible⟩ <;>
        simp only [stderrWorld, guardedWorld, Load.Available.loadedWorld]
    · intro observed success ready wellFormed scopeEffect nodeRead tokenRead bindings kept result collection collected assignments effect memory
      have unitStorage := storage (position := position) observed success buffers valid capacities kindsFit semantic output
        semanticCapacity outputCapacity semanticSeparate outputSeparate outputSemantic wellFormed scopeEffect result collection assignments effect
      have untouched : ¬ data.writes semantic.view.root := fun written => semanticSeparate _ (SyntaxData.writes_in_roots written) rfl
      have semanticReady := observed.saved_ready semantic untouched scopeEffect
      have unitReads := (emitStage.ready_reads emitRelation observed buffers semantic output reads semanticRead outputRead positionRead
        nodeRead tokenRead kept).preserved wellFormed semanticReady effect
      have resultReady := emitStage.result_ready emitRelation resultsSupported resultsBinding observed kept
      have resultCollected := effect.preserves_local_of_distinct_value wellFormed resultReady semanticReady (by intro same; cases same)
      obtain ⟨completion, after, run, satisfied⟩ := emitStage.executes rawCount unitStorage word bytes tokens assignmentWriter nodes unitWriter
        emitMemory tokenConstant stateConstant capacities semanticCapacity rfl effect.wellFormed unitReads resultCollected nativePost
        (by
          intro positionCell middle
          dsimp only
          intro negative _owned _contents emittedEffect _
          obtain ⟨readCount, _, loadedWorld⟩ := observed.loaded.world
          have world : middle.world = input.loadedWorld readCount :=
            emittedEffect.world.trans (effect.world.trans ((observed.scopes scopeEffect).world.trans
              (observed.effect.world.trans loadedWorld)))
          refine ⟨loaded_result input world (Or.inr (Or.inl rfl)), ?_,
            fun impossible => Completion.noConfusion impossible⟩
          intro bound supported nonnegative room
          have fits : ((emission observed semantic output position).encoding
              collection.assignments collection.records).length ≤ bound :=
            originalResources.supported_output supported observed result collection
          have cursor := append_position_bounds _ output.contents nonnegative fits room (by omega)
          have positive := cursor.1
          change (appendAll 16777216 ((emission observed semantic output position).encoding
            collection.assignments collection.records) position output.contents).position ≤ -1 at negative
          omega)
        (by
          intro positionCell middle
          dsimp only
          intro nonnegative owned contents emittedEffect emittedHeap
          obtain ⟨indexCell, after, advanced, indexBinding, positionBinding, indexOwned, positionOwned, outputAfter, advancedEffect, heapFrame⟩ :=
            Advance.finishes argument advanceRelation emitStage emitRelation observed buffers semantic output semanticSeparate outputSeparate
              outputSemantic differentCursors indexBound wellFormed scopeEffect bindings kept effect owned contents emittedEffect
          have native : Host.NativeReady program.core before.i32ArrayViews after := by
            simpa only [observed.loaded.views] using
              ((memory.thenHeap emittedHeap).thenHeap heapFrame).ready observed.loaded.registry observed.loaded.representable
          have frame := handoff argument advanceRelation emitStage emitRelation observed buffers valid semantic output
            semanticSeparate outputSeparate outputSemantic positionRead wellFormed scopeEffect bindings kept effect emittedEffect
            indexBinding positionBinding indexOwned nonnegative positionOwned advancedEffect
          have certificate := certified_output observed success buffers grammarIdentity scopeEffect semantic output
            result collection unitStorage effect.wellFormed nonnegative positionBinding positionOwned outputAfter
          obtain ⟨readCount, _, world⟩ := frame.world
          refine ⟨.next, after, advanceSource.symm ▸ advanced,
            loaded_result input world (Or.inl rfl), ?_,
            fun _ => ⟨native, frame, certificate⟩⟩
          intro bound supported nonnegativePosition room
          have fits : ((emission observed semantic output position).encoding
              collection.assignments collection.records).length ≤ bound :=
            originalResources.supported_output supported observed result collection
          have cursor := append_position_bounds _ output.contents nonnegativePosition fits room (by omega)
          let finalPosition := (appendAll 16777216 ((emission observed semantic output position).encoding
            collection.assignments collection.records) position output.contents).position
          have read : (restoreLocals before after).local? emitStage.position = some (.signed .i32 finalPosition) :=
            Assertion.localPointsTo_local _ _ _ _ ⟨positionBinding, positionOwned.2⟩
          have cast : (finalPosition.toNat : Int) = finalPosition := Int.toNat_of_nonneg cursor.1
          exact ⟨rfl, finalPosition.toNat, by simpa only [cast] using read, Int.toNat_le_toNat cursor.2⟩)
      exact ⟨completion, after, emitSource.symm ▸ run, satisfied⟩
  obtain ⟨afterStore, afterTyped⟩ := Host.checked_statement_type program statementTyped typed run
  refine ⟨completion, after, run, satisfied.1, satisfied.2.1, ?_, locals, afterStore, afterTyped⟩
  intro next
  obtain ⟨registry, representable, views⟩ := (satisfied.2.2 next).1.finish afterTyped
  exact ⟨registry, representable, views, (satisfied.2.2 next).2.1, (satisfied.2.2 next).2.2⟩

end Lanius.Extraction.Entry.File
