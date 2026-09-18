import Lanius.Extraction.Entry.File.Emit.Arguments
import Lanius.Separation.LocalCall

namespace Lanius.Extraction.Entry.File.Emit
open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.Extraction.Frontend Lanius.Extraction.CompactOutput

variable {status detail position : Int}
variable {emission : Unit.Emission} {extracted : State}
variable {result : SemanticTokens.FrontendResult emission.data emission.count emission.nodes emission.words extracted}

/-- The actual emitter RHS, including argument-side `raw_count`. -/
theorem Stage.call_evaluates (stage : Stage)
    (rawCount : Source.CheckedProjection program ["verified", "extraction"] "raw_count" typeId 2)
    (storage : Unit.Storage emission result collection before)
    (word : Word.Checked program byte digit) (bytes : Bytes.Checked program byte digit hex)
    (tokens : Tokens.Checked program byte digit word) (semantic : Assignments.Checked program byte digit word)
    (nodes : Nodes.Checked program byte digit word tokenTag stateTag)
    (checked : Unit.Checked program ⟨word.source.function.id, bytes.source.function.id,
      tokens.source.function.id, semantic.source.function.id, nodes.source.function.id⟩)
    (tokenConstant : ParserTreeSource.constantValue program.core tokenTag 1)
    (stateConstant : ParserTreeSource.constantValue program.core stateTag 2)
    (capacities : Syntax.Capacities emission.data)
    (semanticCapacity : emission.semanticOriginal.length = 131072) (outputCapacity : emission.capacity = 16777216)
    (wellFormed : StateWellFormed before) (reads : stage.Reads emission before)
    (resultRead : before.local? stage.result = some
      (syntaxResult typeId status detail emission.data.raw.length emission.count emission.nodes emission.words position)) :
    ∃ after, Evaluates program.core before (.call checked.source.function.id (stage.arguments rawCount.source.function.id))
        (.signed .i32 (appendAll emission.capacity (emission.encoding collection.assignments collection.records)
          emission.position emission.original).position) after ∧
      after.cellEntry? emission.outputCell = some { id := emission.outputCell, value := some (.array
        (signedI32Values (appendAll emission.capacity (emission.encoding collection.assignments collection.records)
          emission.position emission.original).contents)) } ∧
      CellEffect (CellSet.singleton emission.outputCell) before after := by
  obtain ⟨ready, arguments, effect⟩ := stage.arguments_evaluate rawCount emission capacities semanticCapacity outputCapacity
    wellFormed reads resultRead
  obtain ⟨after, call, contents, emitted⟩ := (storage.preserved wellFormed effect).write
    word bytes tokens semantic nodes checked tokenConstant stateConstant effect.wellFormed arguments
  exact ⟨after, call, contents, (effect.weaken CellSet.empty_subset).trans emitted⟩

/-- Assign the emitter's actual result, then execute its negative-result
guard. Partial-output failures return 21 without executing the continuation. -/
theorem Stage.executes (stage : Stage)
    (rawCount : Source.CheckedProjection program ["verified", "extraction"] "raw_count" typeId 2)
    (storage : Unit.Storage emission result collection before)
    (word : Word.Checked program byte digit) (bytes : Bytes.Checked program byte digit hex)
    (tokens : Tokens.Checked program byte digit word) (semantic : Assignments.Checked program byte digit word)
    (nodes : Nodes.Checked program byte digit word tokenTag stateTag)
    (checked : Unit.Checked program ⟨word.source.function.id, bytes.source.function.id,
      tokens.source.function.id, semantic.source.function.id, nodes.source.function.id⟩)
    (memory : CellOnly.Region program.core (stage.assignment checked.source.function.id rawCount.source.function.id))
    (tokenConstant : ParserTreeSource.constantValue program.core tokenTag 1)
    (stateConstant : ParserTreeSource.constantValue program.core stateTag 2)
    (capacities : Syntax.Capacities emission.data)
    (semanticCapacity : emission.semanticOriginal.length = 131072) (outputCapacity : emission.capacity = 16777216)
    (wellFormed : StateWellFormed before) (reads : stage.Reads emission before)
    (resultRead : before.local? stage.result = some
      (syntaxResult typeId status detail emission.data.raw.length emission.count emission.nodes emission.words position))
    (post : Scope.Post)
    (failure : ∀ positionCell middle,
      let outcome := appendAll emission.capacity (emission.encoding collection.assignments collection.records)
        emission.position emission.original
      outcome.position ≤ -1 →
      (Assertion.localPointsTo stage.position positionCell (some (.signed .i32 outcome.position))).holds middle →
      middle.cellEntry? emission.outputCell = some { id := emission.outputCell, value := some (.array (signedI32Values outcome.contents)) } →
      CellEffect (CellSet.union (CellSet.singleton emission.outputCell) (CellSet.singleton positionCell)) before middle →
      HeapFrame before middle →
      post (.returned (some (.signed .i32 21))) middle)
    (continuationRun : ∀ positionCell middle,
      let outcome := appendAll emission.capacity (emission.encoding collection.assignments collection.records)
        emission.position emission.original
      0 ≤ outcome.position →
      (Assertion.localPointsTo stage.position positionCell (some (.signed .i32 outcome.position))).holds middle →
      middle.cellEntry? emission.outputCell = some { id := emission.outputCell, value := some (.array (signedI32Values outcome.contents)) } →
      CellEffect (CellSet.union (CellSet.singleton emission.outputCell) (CellSet.singleton positionCell)) before middle →
      HeapFrame before middle →
      ∃ completion after, Executes program.core middle stage.continuation completion after ∧ post completion after) :
    ∃ completion after, Executes program.core before (stage.statement checked.source.function.id rawCount.source.function.id)
      completion after ∧ post completion after := by
  have positionRead := reads (stage.position, .signed .i32 emission.position) (by simp [Stage.bindings])
  obtain ⟨positionCell, positionOwned⟩ := Assertion.exists_localPointsTo_of_local _ _ _ positionRead
  have separate : emission.outputCell ≠ positionCell := by
    intro same
    have backing := storage.output
    rw [same, positionOwned.2] at backing
    cases backing
  obtain ⟨written, call, output, effect⟩ := stage.call_evaluates rawCount storage word bytes tokens semantic nodes checked
    tokenConstant stateConstant capacities semanticCapacity outputCapacity wellFormed reads resultRead
  have stillOwned := effect.preserves_localPointsTo wellFormed positionOwned
    (by simpa [CellSet.singleton, eq_comm] using separate)
  obtain ⟨middle, assigned, owned, combined, assignmentEffect, _⟩ := evaluatesOwnedLocalSet positionOwned call effect stillOwned
  have heap := memory.executes (executesExpression assigned)
  have outputMiddle := assignmentEffect.preserves_entry effect.wellFormed output separate
  let outcome := appendAll emission.capacity (emission.encoding collection.assignments collection.records)
    emission.position emission.original
  have guard : Evaluates program.core middle (binary .lessEqual (read stage.position) negativeOne)
      (.boolean (outcome.position ≤ -1)) middle := by
    apply evaluatesEagerBinary (by decide) (by decide)
      (local_evaluates program.core (Assertion.localPointsTo_local _ _ _ _ owned))
      (negativeOne_evaluates program.core middle)
    rfl
  by_cases failed : outcome.position ≤ -1
  · have satisfied := failure positionCell middle failed owned outputMiddle combined heap
    have returnedRun : Executes program.core middle (returned (number 21)) (.returned (some (.signed .i32 21))) middle :=
      executesSequenceReturned (executesReturnValue (show Evaluates program.core middle (number 21) (.signed .i32 21) middle from ⟨1, rfl⟩))
    refine ⟨.returned (some (.signed .i32 21)), middle, ?_, satisfied⟩
    exact executesSequence (executesExpression assigned)
      (executesSequenceNonNext (executesIfTrue (by simpa only [failed, decide_true] using guard) returnedRun) (by simp))
  · obtain ⟨completion, after, continued, satisfied⟩ := continuationRun positionCell middle (by change 0 ≤ outcome.position; omega) owned outputMiddle combined heap
    exact ⟨completion, after, executesSequence (executesExpression assigned)
      (executesSequence (executesIfFalse (by simpa only [failed, decide_false] using guard) (executesSkip _ _)) continued), satisfied⟩

end Lanius.Extraction.Entry.File.Emit
