import Lanius.Extraction.SemanticTokens.Collect.ChildLoop

namespace Lanius.Extraction.SemanticTokens.Collect

open Lanius Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.Compiler.Parser

def recordChildren (symbols : Symbols) : Stmt :=
  .sequence (childLoop symbols)
    (.sequence (reject (binary .notEqual (read 16) (atIndex 4 (binary .add (read 14) (number 2)))))
      (.sequence (increment 13 1) .skip))

/-- Complete the current record's children, check its stored endpoint, and
advance the outer node index. Path and uniqueness come from CollectionRecords;
the final buffer is the exact next prefix of that same postorder traversal. -/
theorem record_children_execute {memory : ChildMemory} {record : RecordVisit}
    (program : Program) (symbols : Symbols)
    (tokenTag : ParserTreeSource.constantValue program symbols.childToken 1)
    (stateTag : ParserTreeSource.constantValue program symbols.childState 2)
    (found : memory.data.collection.records[nodeIndex]? = some record)
    (held : ChildOwned memory record nodeIndex 0 record.start
      (priorUses memory.data.collection.records nodeIndex) before)
    (nodeOwned : (Assertion.localPointsTo 13 nodeCell (some (.signed .i32 nodeIndex))).holds before)
    (nodeFits : nodeIndex + 1 ≤ 2147483647) :
    ∃ after, Executes program before (recordChildren symbols) .next after ∧
      (Assertion.localPointsTo 13 nodeCell (some (.signed .i32 (Int.ofNat (nodeIndex + 1))))).holds after ∧
      after.cellEntry? memory.data.outputCell = some {
        id := memory.data.outputCell,
        value := some (.array (signedI32Values (written memory.data.original memory.data.tokens.length
          (priorUses memory.data.collection.records (nodeIndex + 1))))) } ∧
      CellEffect (CellSet.union memory.writes (CellSet.singleton nodeCell)) before after := by
  have member := List.mem_of_getElem? found
  have path := memory.data.collection.valid record member
  have unique := memory.data.collection.unique
  rw [record_uses_split found] at unique
  obtain ⟨middle, loopRun, final, loopEffect⟩ := child_loop program symbols tokenTag stateTag found held (by omega)
    (by simpa only [List.drop_zero, RecordVisit.Valid] using path)
    (by simpa only [List.drop_zero, RecordVisit.uses] using unique)
  have stored := memory.data.collection.stored record member
  obtain ⟨_, endpoint, _⟩ := record_header_read program final.records stored
    (read 14) (local_evaluates program final.offset) memory.data.wordsFit
  have cursorRead := local_evaluates program (Assertion.localPointsTo_local _ _ _ _ final.cursor)
  have guard : Evaluates program middle
      (binary .notEqual (read 16) (atIndex 4 (binary .add (read 14) (number 2)))) (.boolean false) middle :=
    evaluatesEagerBinary (by decide) (by decide) cursorRead endpoint (by simp [evalBinaryValue, scalarEqual])
  have nodeSeparate := held.stable 13 (by decide) nodeCell nodeOwned.1
  have nodeStill := loopEffect.preserves_localPointsTo held.wellFormed nodeOwned nodeSeparate
  obtain ⟨after, incremented, afterWF, nodeAfter, incrementEffect⟩ := executesIncrementOwnedI32Local
    program middle 13 nodeCell nodeIndex loopEffect.wellFormed nodeStill nodeFits
  have outputSeparate : memory.data.outputCell ≠ nodeCell := by
    intro same
    exact nodeSeparate (Or.inl (Or.inl same.symm))
  have contents := incrementEffect.preserves_entry loopEffect.wellFormed final.backing outputSeparate
  refine ⟨after, executesSequence loopRun (executesSequence (executesIfFalse guard (executesSkip _ _)) incremented),
    nodeAfter, ?_, (loopEffect.weaken CellSet.subset_union_left).trans
      ((CellEffect.ofModifiesOnly incrementEffect afterWF).weaken CellSet.subset_union_right)⟩
  simpa only [List.drop_zero, priorUses_step found, RecordVisit.uses] using contents

end Lanius.Extraction.SemanticTokens.Collect
