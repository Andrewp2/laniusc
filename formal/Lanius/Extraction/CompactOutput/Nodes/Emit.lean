import Lanius.Extraction.CompactOutput.Nodes.ChildPhase

namespace Lanius.Extraction.CompactOutput.Nodes

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Extraction.SemanticTokens

def encodeRecord (record : RecordVisit) : List Nat :=
  encodeHeader record ++ encodeChildren record.children

def emitRecord (wordId : FunctionId) (tokenTag stateTag : Lanius.ConstantId) : Stmt :=
  headerThen wordId (childPhase wordId tokenTag stateTag)

/-- Execute all emission for one stored node, including its final index
advance. No header or child execution is an input to this theorem. -/
theorem emit_record {memory : HeaderMemory} {refs : References memory}
    (owned : HeaderOwned memory position contents before)
    (refsOwned : ReferencesOwned refs before) (word : Word.Checked program byte digit)
    (tokenConstant : ParserTreeSource.constantValue program.core tokenTag 1)
    (stateConstant : ParserTreeSource.constantValue program.core stateTag 2)
    (nodeOwned : (Assertion.localPointsTo 9 nodeCell (some (.signed .i32 refs.node))).holds before)
    (distinct : memory.cursorCell ≠ nodeCell) (nextFit : refs.node + 1 ≤ 2147483647) :
    ∃ after, Executes program.core before (emitRecord word.source.function.id tokenTag stateTag)
        (appendAll memory.capacity (encodeRecord memory.record) position contents).completion after ∧
      after.cellEntry? memory.outputCell = some {
        id := memory.outputCell, value := some (.array (signedI32Values
          (appendAll memory.capacity (encodeRecord memory.record) position contents).contents)) } ∧
      (∀ result updated, appendAll memory.capacity (encodeRecord memory.record) position contents = .done result updated →
        (Assertion.localPointsTo 8 memory.cursorCell (some (.signed .i32 result))).holds after ∧
        (Assertion.localPointsTo 9 nodeCell (some (.signed .i32 (refs.node + 1 : Nat)))).holds after) ∧
      CellEffect (CellSet.union memory.writes (CellSet.singleton nodeCell)) before after := by
  have encoded : appendAll memory.capacity (encodeRecord memory.record) position contents =
      (appendAll memory.capacity (encodeHeader memory.record) position contents).resume memory.capacity
        (encodeChildren memory.record.children) := appendAll_append _ _ _ _ _
  cases outcome : appendAll memory.capacity (encodeHeader memory.record) position contents with
  | full retained =>
    obtain ⟨after, run, backing, effect⟩ := header_failure owned word outcome
      (childPhase word.source.function.id tokenTag stateTag)
    refine ⟨after, ?_, ?_, ?_, effect.weaken CellSet.subset_union_left⟩
    · simpa only [encoded, outcome, AppendOutcome.resume, AppendOutcome.completion, emitRecord] using run
    · simpa only [encoded, outcome, AppendOutcome.resume, AppendOutcome.contents] using backing
    · intro result updated impossible
      rw [encoded, outcome] at impossible
      cases impossible
  | done nextCursor updated =>
    obtain ⟨written, headerOwned, writtenRefs, headerEffect, continueRun⟩ := header_success owned refsOwned word outcome
    have outputNode : memory.outputCell ≠ nodeCell := by
      intro same
      have original := owned.backing
      rw [same, nodeOwned.2] at original
      cases original
    have nodeWritten := headerEffect.preserves_localPointsTo owned.wellFormed nodeOwned (by
      intro changed
      rcases changed with output | cursor
      · exact outputNode output.symm
      · exact distinct cursor.symm)
    obtain ⟨after, childRun, backing, advanced, childEffect⟩ := execute_child_phase headerOwned writtenRefs word
      tokenConstant stateConstant nodeWritten distinct nextFit
    refine ⟨after, ?_, ?_, ?_, (headerEffect.weaken CellSet.subset_union_left).trans childEffect⟩
    · simpa only [encoded, outcome, AppendOutcome.resume, emitRecord] using continueRun _ _ _ childRun
    · simpa only [encoded, outcome, AppendOutcome.resume] using backing
    · intro result finalContents done
      apply advanced result finalContents
      simpa only [encoded, outcome, AppendOutcome.resume] using done

end Lanius.Extraction.CompactOutput.Nodes
