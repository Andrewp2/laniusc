import Lanius.Extraction.SemanticTokens.Collect.RecordSetup

namespace Lanius.Extraction.SemanticTokens.Collect

open Lanius Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.Compiler.Parser ParserTreeLayout

/-- One complete outer iteration of the current collector: fetch the record,
check its storage/span, derive the child resources, execute every child, and
close all four record scopes. Only output and the outer cursor remain writable. -/
theorem node_step {memory : NodeMemory} {record : RecordVisit}
    (program : Program) (symbols : Symbols)
    (tokenTag : ParserTreeSource.constantValue program symbols.childToken 1)
    (stateTag : ParserTreeSource.constantValue program symbols.childState 2)
    (held : NodeOwned memory index before)
    (found : memory.data.collection.records[index]? = some record) :
    ∃ after, Executes program before (nodeBody symbols) .next after ∧
      NodeOwned memory (index + 1) after ∧ CellEffect memory.writes before after := by
  have member := List.mem_of_getElem? found
  have active := (List.getElem?_eq_some_iff.mp found).1
  have stored := memory.data.collection.stored record member
  have room := stored.bounds
  have offsetFound : ((treeFrom 0 0 memory.data.tree).offsets.map Int.ofNat)[index]? = some (Int.ofNat record.offset) := by
    rw [← memory.data.collection.offsets]
    simp [List.getElem?_map, found]
  have offsetResult := read_word program held.offsets (read 13) index offsetFound
    (local_evaluates program (Assertion.localPointsTo_local _ _ _ _ held.node))
  let first := before.bindLocal 14 (.signed .i32 record.offset)
  have firstHeld : NodeOwned memory index first := held.bindLocal 14 _ (by decide)
  have offsetFirst : first.local? 14 = some (.signed .i32 record.offset) := bindLocal_finds_local _ _ _ held.wellFormed
  have headerGuard := recordGuard_pass program 14 record.offset (treeFrom 0 0 memory.data.tree).words.length
    offsetFirst firstHeld.wordLength (by omega) memory.data.wordsFit
  obtain ⟨_, _, countResult⟩ := record_header_read program firstHeld.records stored
    (read 14) (local_evaluates program offsetFirst) memory.data.wordsFit
  let second := first.bindLocal 15 (.signed .i32 record.children.length)
  have secondHeld : NodeOwned memory index second := firstHeld.bindLocal 15 _ (by decide)
  have countSecond : second.local? 15 = some (.signed .i32 record.children.length) := bindLocal_finds_local _ _ _ firstHeld.wellFormed
  have offsetSecond : second.local? 14 = some (.signed .i32 record.offset) :=
    (bindLocal_preserves_other_local firstHeld.wellFormed (by decide : (15 : VarId) ≠ 14)).trans offsetFirst
  obtain ⟨startResult, _, _⟩ := record_header_read program secondHeld.records stored
    (read 14) (local_evaluates program offsetSecond) memory.data.wordsFit
  let third := second.bindLocal 16 (.signed .i32 record.start)
  have thirdHeld : NodeOwned memory index third := secondHeld.bindLocal 16 _ (by decide)
  have startThird : third.local? 16 = some (.signed .i32 record.start) := bindLocal_finds_local _ _ _ secondHeld.wellFormed
  have offsetThird : third.local? 14 = some (.signed .i32 record.offset) :=
    (bindLocal_preserves_other_local secondHeld.wellFormed (by decide : (16 : VarId) ≠ 14)).trans offsetSecond
  have countThird : third.local? 15 = some (.signed .i32 record.children.length) :=
    (bindLocal_preserves_other_local secondHeld.wellFormed (by decide : (16 : VarId) ≠ 15)).trans countSecond
  have ordered := VisitPath.monotone (memory.data.collection.valid record member)
  have finishBound := memory.data.collection.bounded record member
  have startBound : record.start ≤ memory.data.tokens.length * 2 := by
    simp only [finalPosition] at finishBound
    omega
  have countGuard := record_count_guard_pass program stored memory.data.wordsFit memory.data.tokensFit startBound
    thirdHeld.wordLength offsetThird countThird startThird thirdHeld.count
  have children := held.children record
  have fourthHeld : NodeOwned memory index (recordEntered before record) := thirdHeld.bindLocal 17 _ (by decide)
  obtain ⟨completed, childrenRun, nodeAfter, contents, childrenEffect⟩ := record_children_execute program symbols tokenTag stateTag
    found children fourthHeld.node (by have := memory.nodesFit; omega)
  have childScope := executesLetLocal (id := 17) (type := i32)
    (show Evaluates program third (number 0) (.signed .i32 0) third from ⟨1, rfl⟩) childrenRun
  have guardedChildren := executesSequence (executesIfFalse (thenBranch := returned (negative 1)) countGuard (executesSkip _ _)) childScope
  have startScope := executesLetLocal (id := 16) (type := i32) startResult guardedChildren
  have countScope := executesLetLocal (id := 15) (type := i32) countResult startScope
  have guardedRecord := executesSequence (executesIfFalse (thenBranch := returned (negative 1)) headerGuard (executesSkip _ _)) countScope
  have wholeRun := executesLetLocal (id := 14) (type := i32) offsetResult guardedRecord
  have thirdEffect := CellEffect.closeLocal third 17 (.signed .i32 0) thirdHeld.wellFormed childrenEffect
  have secondEffect := CellEffect.closeLocal second 16 (.signed .i32 record.start) secondHeld.wellFormed thirdEffect
  have firstEffect := CellEffect.closeLocal first 15 (.signed .i32 record.children.length) firstHeld.wellFormed secondEffect
  have closedEffect := CellEffect.closeLocal before 14 (.signed .i32 record.offset) held.wellFormed firstEffect
  have effect : CellEffect memory.writes before (restoreLocals before completed) := by
    apply closedEffect.narrow
    intro cell old changed
    rcases changed with ((output | position) | child) | node
    · exact Or.inl output
    · dsimp only [NodeOwned.childMemory, CellSet.singleton, CellId] at position old
      omega
    · dsimp only [NodeOwned.childMemory, CellSet.singleton, CellId] at child old
      omega
    · exact Or.inr node
  have restoredNode : (Assertion.localPointsTo 13 memory.nodeCell (some (.signed .i32 (Int.ofNat (index + 1))))).holds
      (restoreLocals before completed) := ⟨held.node.1, nodeAfter.2⟩
  exact ⟨restoreLocals before completed, wholeRun, held.advance effect contents restoredNode, effect⟩

end Lanius.Extraction.SemanticTokens.Collect
