import Lanius.Extraction.CompactOutput.Nodes.Entry

namespace Lanius.Extraction.CompactOutput.Nodes

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Compiler.Parser ParserTreeLayout Lanius.Extraction.SemanticTokens

theorem ChildEntry.failure (entry : ChildEntry before) (word : Word.Checked program byte digit)
    (tokenConstant : ParserTreeSource.constantValue program.core tokenTag 1)
    (stateConstant : ParserTreeSource.constantValue program.core stateTag 2)
    (full : entry.outcome = .full retained) :
    ∃ after, Executes program.core before (childStep word.source.function.id tokenTag stateTag)
        (.returned (some (.signed .i32 (-1)))) after ∧
      after.cellEntry? entry.outputCell = some {
        id := entry.outputCell, value := some (.array (signedI32Values retained)) } ∧
      CellEffect (CellSet.union (CellSet.singleton entry.outputCell) (CellSet.singleton entry.cursorCell)) before after := by
  obtain ⟨slotRead, tagRead, payloadRead, _, _, _, _⟩ := initialize_child program.core entry.record entry.child entry.index
    entry.wellFormed entry.input entry.stored entry.found entry.recordRead entry.indexRead entry.sizeFit
  obtain ⟨middle, written, firstRun, secondRun, cursor, backing, effect⟩ := entry.write word
  have nextRead := local_evaluates program.core (Assertion.localPointsTo_local _ _ _ _ cursor)
  rw [full] at nextRead backing
  have failed : Evaluates program.core written failureGuard (.boolean true) written := by
    apply evaluatesEagerBinary (by decide) (by decide) nextRead (negativeOne_evaluates program.core written)
    simp [evalBinaryValue, evalSignedBinary, AppendOutcome.position]
  have writesRun : Executes program.core entry.scope
      (.sequence (.expression (tagWrite word.source.function.id))
        (.sequence (.expression (payloadWrite word.source.function.id))
          (.sequence (.ifThenElse failureGuard (returned negativeOne) .skip)
            (.sequence (.expression childIncrement) .skip))))
      (.returned (some (.signed .i32 (-1)))) written :=
    executesSequence (executesExpression firstRun)
      (executesSequence (executesExpression secondRun)
        (executesSequenceReturned (executesIfTrue failed
          (executesSequenceReturned (executesReturnValue (negativeOne_evaluates program.core written))))))
  have tailRun := entry.validate program.core tokenConstant stateConstant writesRun
  have slotWF : StateWellFormed (slotState before entry.record entry.index) := bindLocal_preserves_well_formed _ _ _ entry.wellFormed
  have tagWF : StateWellFormed (tagState before entry.record entry.index entry.child) := bindLocal_preserves_well_formed _ _ _ slotWF
  have run := executesLetLocal (id := 14) (type := i32) slotRead
    (executesLetLocal (id := 15) (type := i32) tagRead
      (executesLetLocal (id := 16) (type := i32) payloadRead tailRun))
  have closed := CellEffect.closeLocal before 14 (.signed .i32 (entry.record.offset + 4 + entry.index * 3 : Nat)) entry.wellFormed
    (CellEffect.closeLocal (slotState before entry.record entry.index) 15 (.signed .i32 (childTag entry.child.reference)) slotWF
      (CellEffect.closeLocal (tagState before entry.record entry.index entry.child) 16 (.signed .i32 (childPayload entry.child.reference)) tagWF effect))
  exact ⟨restoreLocals before written, run, backing, closed⟩

end Lanius.Extraction.CompactOutput.Nodes
