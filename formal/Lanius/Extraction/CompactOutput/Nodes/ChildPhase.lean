import Lanius.Extraction.CompactOutput.Nodes.HeaderControl

namespace Lanius.Extraction.CompactOutput.Nodes

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation

def childPhase (wordId : FunctionId) (tokenTag stateTag : Lanius.ConstantId) : Stmt :=
  .letLocal 13 i32 (number 0) (.sequence (childLoop wordId tokenTag stateTag)
    (.sequence (.expression increment) .skip))

theorem execute_child_phase {memory : HeaderMemory} {refs : References memory}
    (owned : HeaderOwned memory position contents before)
    (refsOwned : ReferencesOwned refs before) (word : Word.Checked program byte digit)
    (tokenConstant : ParserTreeSource.constantValue program.core tokenTag 1)
    (stateConstant : ParserTreeSource.constantValue program.core stateTag 2)
    (nodeOwned : (Assertion.localPointsTo 9 nodeCell (some (.signed .i32 refs.node))).holds before)
    (distinct : memory.cursorCell ≠ nodeCell) (nextFit : refs.node + 1 ≤ 2147483647) :
    ∃ after, Executes program.core before (childPhase word.source.function.id tokenTag stateTag)
        (appendAll memory.capacity (encodeChildren memory.record.children) position contents).completion after ∧
      after.cellEntry? memory.outputCell = some {
        id := memory.outputCell, value := some (.array (signedI32Values
          (appendAll memory.capacity (encodeChildren memory.record.children) position contents).contents)) } ∧
      (∀ result updated, appendAll memory.capacity (encodeChildren memory.record.children) position contents = .done result updated →
        (Assertion.localPointsTo 8 memory.cursorCell (some (.signed .i32 result))).holds after ∧
        (Assertion.localPointsTo 9 nodeCell (some (.signed .i32 (refs.node + 1 : Nat)))).holds after) ∧
      CellEffect (CellSet.union memory.writes (CellSet.singleton nodeCell)) before after := by
  let entered := before.bindLocal 13 (.signed .i32 0)
  let childMemory := owned.childMemory refs
  have childOwned := owned.start_children refsOwned
  obtain ⟨written, loopRun, backing, completed, effect⟩ := execute_child_loop word tokenConstant stateConstant
    memory.record.children childOwned (by simp [HeaderOwned.childMemory])
  dsimp only [HeaderOwned.childMemory] at loopRun backing
  have nodeEntered := bindLocal_preserves_localPointsTo_of_ne before 13 9 (.signed .i32 0)
    nodeCell _ owned.wellFormed (by decide) nodeOwned
  have nodeOld := StateWellFormed.cell_lt_next_of_entry owned.wellFormed nodeOwned.2
  have outputNode : memory.outputCell ≠ nodeCell := by
    intro same
    have original := owned.backing
    rw [same, nodeOwned.2] at original
    cases original
  have nodeWritten := effect.preserves_localPointsTo childOwned.wellFormed nodeEntered (by
    intro changed
    rcases changed with (output | cursor) | child
    · exact outputNode output.symm
    · exact distinct cursor.symm
    · change nodeCell = before.nextCell at child
      exact (Nat.ne_of_lt nodeOld) child)
  cases outcome : appendAll memory.capacity (encodeChildren memory.record.children) position contents with
  | full retained =>
    have run := executesLetLocal (id := 13) (type := i32)
      (show Evaluates program.core before (number 0) (.signed .i32 0) before from ⟨1, rfl⟩)
      (executesSequenceReturned (second := .sequence (.expression increment) .skip)
        (by simpa only [outcome, AppendOutcome.completion] using loopRun))
    have closed := CellEffect.closeLocal before 13 (.signed .i32 0) owned.wellFormed effect
    refine ⟨restoreLocals before written, ?_, ?_, ?_, closed.narrow ?_⟩
    · simpa only [outcome, AppendOutcome.completion, childPhase] using run
    · rw [outcome] at backing
      exact backing
    · intro result updated impossible
      cases impossible
    · intro cell old changed
      rcases changed with original | fresh
      · exact Or.inl original
      · change cell = before.nextCell at fresh
        exact False.elim ((Nat.ne_of_lt old) fresh)
  | done result updated =>
    have finalOwned : ChildOwned childMemory memory.record.children.length result updated written := by
      simpa only [childMemory, HeaderOwned.childMemory, outcome, ChildCompleted] using completed
    obtain ⟨advanced, incremented, advancedWF, nodeAdvanced, modifies⟩ := evaluatesIncrementOwnedI32Local
      program.core written 9 nodeCell refs.node effect.wellFormed nodeWritten nextFit
    have incrementEffect := CellEffect.ofModifiesOnly modifies advancedWF
    have cursorAdvanced := incrementEffect.preserves_localPointsTo effect.wellFormed finalOwned.cursor
      (by simpa only [CellSet.singleton, childMemory, HeaderOwned.childMemory] using distinct)
    have outputAdvanced := incrementEffect.preserves_entry effect.wellFormed finalOwned.backing
      (by simpa only [CellSet.singleton, childMemory, HeaderOwned.childMemory] using outputNode)
    have combined := (effect.weaken CellSet.subset_union_left).trans
      (incrementEffect.weaken CellSet.subset_union_right)
    have run := executesLetLocal (id := 13) (type := i32)
      (show Evaluates program.core before (number 0) (.signed .i32 0) before from ⟨1, rfl⟩)
      (executesSequence (by simpa only [outcome, AppendOutcome.completion] using loopRun)
        (executesSequence (executesExpression incremented) (executesSkip _ _)))
    have closed := CellEffect.closeLocal before 13 (.signed .i32 0) owned.wellFormed combined
    refine ⟨restoreLocals before advanced, ?_, ?_, ?_, closed.narrow ?_⟩
    · exact run
    · exact outputAdvanced
    · intro next nextContents same
      cases same
      exact ⟨⟨owned.cursor.1, cursorAdvanced.2⟩, ⟨nodeOwned.1, nodeAdvanced.2⟩⟩
    · intro cell old changed
      rcases changed with (original | fresh) | node
      · exact Or.inl original
      · change cell = before.nextCell at fresh
        exact False.elim ((Nat.ne_of_lt old) fresh)
      · exact Or.inr node

end Lanius.Extraction.CompactOutput.Nodes
