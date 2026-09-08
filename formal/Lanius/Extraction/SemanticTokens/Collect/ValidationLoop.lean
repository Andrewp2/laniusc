import Lanius.Extraction.SemanticTokens.Collect.Validation
import Lanius.Semantics.Sequence

namespace Lanius.Extraction.SemanticTokens.Collect

open Lanius Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.Compiler.Parser

structure ValidationMemory where
  data : TraversalData
  cursorCell : CellId
  separate : ∀ cell ∈ [data.grammarCell, data.kindsCell, data.outputCell], cell ≠ cursorCell

def validationStableIds : List VarId := [0, 2, 3, 8, 11]

structure ValidationOwned (memory : ValidationMemory) (index : Nat) (state : State) : Prop where
  wellFormed : StateWellFormed state
  grammar : memory.data.grammar.Owns memory.data.grammarCell state
  kinds : I32PrefixLocal state 2 memory.data.kindsCell (memory.data.tokens.map (Int.ofNat ∘ Token.kind))
  assignments : I32PrefixLocal state 8 memory.data.outputCell (memory.data.collection.assignments.flatMap Assignment.words)
  cursor : (Assertion.localPointsTo 12 memory.cursorCell (some (.signed .i32 index))).holds state
  count : state.local? 3 = some (.signed .i32 memory.data.tokens.length)
  offset : state.local? 11 = some (.signed .i32 memory.data.grammar.layout.canonicalKindsOffset)
  stable : ∀ id ∈ validationStableIds, ∀ cell, state.cellId? id = some cell → cell ≠ memory.cursorCell

theorem ValidationOwned.bindLocal {memory : ValidationMemory}
    (held : ValidationOwned memory index before) (id : VarId) (value : Value) (high : 24 ≤ id) :
    ValidationOwned memory index (before.bindLocal id value) := by
  have different (localId : VarId) (low : localId < 24) : id ≠ localId := by
    dsimp only [VarId] at high low ⊢
    omega
  have keep {localId : VarId} {current : Value} (low : localId < 24)
      (found : before.local? localId = some current) : (before.bindLocal id value).local? localId = some current :=
    (bindLocal_preserves_other_local held.wellFormed (different localId low)).trans found
  refine ⟨bindLocal_preserves_well_formed _ _ _ held.wellFormed,
    held.grammar.bindLocal held.wellFormed id value (different _ (by decide)),
    held.kinds.bindLocal held.wellFormed id value (different _ (by decide)),
    held.assignments.bindLocal held.wellFormed id value (different _ (by decide)),
    bindLocal_preserves_localPointsTo_of_ne before id 12 value memory.cursorCell _ held.wellFormed
      (different _ (by decide)) held.cursor,
    keep (by decide) held.count, keep (by decide) held.offset, ?_⟩
  intro localId member cell binding
  have low : localId < 24 := by
    simp only [validationStableIds, List.mem_cons, List.not_mem_nil, or_false] at member
    dsimp only [VarId] at member ⊢
    omega
  exact held.stable localId member cell
    (by simpa only [bindLocal_preserves_other_cellId before id localId value (different localId low)] using binding)

theorem ValidationOwned.advance {memory : ValidationMemory} {nextIndex : Nat}
    (held : ValidationOwned memory index before)
    (effect : CellEffect (CellSet.singleton memory.cursorCell) before after)
    (cursor : (Assertion.localPointsTo 12 memory.cursorCell (some (.signed .i32 nextIndex))).holds after) :
    ValidationOwned memory nextIndex after := by
  have keep {id : VarId} {value : Value} (member : id ∈ validationStableIds)
      (found : before.local? id = some value) : after.local? id = some value :=
    effect.preserves_local held.wellFormed found (held.stable id member)
  refine ⟨effect.wellFormed,
    held.grammar.preserved (fun _ found => keep (by decide) found) held.wellFormed effect (memory.separate _ (by simp)),
    held.kinds.preserved (fun _ found => keep (by decide) found) held.wellFormed effect (memory.separate _ (by simp)),
    held.assignments.preserved (fun _ found => keep (by decide) found) held.wellFormed effect (memory.separate _ (by simp)),
    cursor, keep (by decide) held.count, keep (by decide) held.offset, ?_⟩
  intro id member cell found
  apply held.stable id member cell
  simpa only [State.cellId?, effect.locals] using found

/-- One complete source iteration, including both word reads, local scopes,
all semantic guards, and the index increment. The output is read-only. -/
theorem validation_step {memory : ValidationMemory} (program : Program)
    (held : ValidationOwned memory index before) (active : index < memory.data.tokens.length) :
    ∃ after, Executes program before validateBody .next after ∧
      ValidationOwned memory (index + 1) after ∧ CellEffect (CellSet.singleton memory.cursorCell) before after := by
  have rawFound := List.getElem?_eq_getElem active
  obtain ⟨assignment, found, valid⟩ := memory.data.collection.validAssignments index _ rawFound
  obtain ⟨firstFound, secondFound⟩ := assignment_words_fields found
  have firstIndex := evaluatesNatI32Multiply
    (local_evaluates program (Assertion.localPointsTo_local _ _ _ _ held.cursor))
    (show Evaluates program before (number 2) (.signed .i32 2) before from ⟨1, rfl⟩)
    (by have := memory.data.tokensFit; omega : index * 2 ≤ 2147483647)
  have firstResult := read_word program held.assignments _ _ firstFound firstIndex
  let first := before.bindLocal 24 (.signed .i32 assignment.first)
  have firstHeld : ValidationOwned memory index first := held.bindLocal 24 _ (by decide)
  have firstRead : first.local? 24 = some (.signed .i32 assignment.first) :=
    bindLocal_finds_local _ _ _ held.wellFormed
  have twice := evaluatesNatI32Multiply
    (local_evaluates program (Assertion.localPointsTo_local _ _ _ _ firstHeld.cursor))
    (show Evaluates program first (number 2) (.signed .i32 2) first from ⟨1, rfl⟩)
    (by have := memory.data.tokensFit; omega : index * 2 ≤ 2147483647)
  have secondIndex := evaluatesNatI32Add (leftValue := index * 2) (rightValue := 1) twice
    (show Evaluates program first (number 1) (.signed .i32 1) first from ⟨1, rfl⟩)
    (by have := memory.data.tokensFit; omega)
  have secondResult := read_word program firstHeld.assignments _ _ secondFound secondIndex
  let secondValue := (assignment.second.map Int.ofNat).getD (-1)
  let second := first.bindLocal 25 (.signed .i32 secondValue)
  have secondHeld : ValidationOwned memory index second := firstHeld.bindLocal 25 _ (by decide)
  have secondRead : second.local? 25 = some (.signed .i32 secondValue) := bindLocal_finds_local _ _ _ firstHeld.wellFormed
  have firstStill : second.local? 24 = some (.signed .i32 assignment.first) :=
    (bindLocal_preserves_other_local firstHeld.wellFormed (by decide : (25 : VarId) ≠ 24)).trans firstRead
  have checks := validation_checks memory.data.grammar program valid rawFound secondHeld.grammar secondHeld.kinds
    (Assertion.localPointsTo_local _ _ _ _ secondHeld.cursor) secondHeld.offset firstStill secondRead
  obtain ⟨completed, incremented, wellFormed, cursorAfter, incrementEffect⟩ := executesIncrementOwnedI32Local
    program second 12 memory.cursorCell index secondHeld.wellFormed secondHeld.cursor
    (by have := memory.data.tokensFit; omega)
  have checked := executesSequence_continue checks incremented
  have secondScope := executesLetLocal (id := 25) (type := i32) secondResult checked
  have firstScope := executesLetLocal (id := 24) (type := i32) firstResult secondScope
  have secondEffect := CellEffect.ofModifiesOnly incrementEffect wellFormed
  have firstEffect := CellEffect.closeLocal first 25 (.signed .i32 secondValue) firstHeld.wellFormed secondEffect
  have effect := CellEffect.closeLocal before 24 (.signed .i32 assignment.first) held.wellFormed firstEffect
  have restored : (Assertion.localPointsTo 12 memory.cursorCell (some (.signed .i32 (Int.ofNat (index + 1))))).holds
      (restoreLocals before completed) := ⟨held.cursor.1, cursorAfter.2⟩
  exact ⟨restoreLocals before completed, firstScope, held.advance effect restored, effect⟩

def validationLoop : Stmt := .whileLoop (binary .notEqual (read 12) (read 3)) validateBody

/-- The complete final-validation loop terminates without changing any
assignment, grammar, token, or other old cell except its own index. -/
theorem validation_loop {memory : ValidationMemory} (program : Program)
    (held : ValidationOwned memory index before) (bound : index ≤ memory.data.tokens.length) :
    ∃ after, Executes program before validationLoop .next after ∧
      ValidationOwned memory memory.data.tokens.length after ∧
      CellEffect (CellSet.singleton memory.cursorCell) before after := by
  have condition : Evaluates program before (binary .notEqual (read 12) (read 3))
      (.boolean (!(Int.ofNat index == Int.ofNat memory.data.tokens.length))) before := by
    apply evaluatesEagerBinary (by decide) (by decide)
      (local_evaluates program (Assertion.localPointsTo_local _ _ _ _ held.cursor)) (local_evaluates program held.count)
    simp [evalBinaryValue, scalarEqual]
  by_cases done : index = memory.data.tokens.length
  · subst index
    exact ⟨before, executesWhileFalse (by simpa using condition), held, CellEffect.refl held.wellFormed⟩
  · have trueCondition : Evaluates program before (binary .notEqual (read 12) (read 3)) (.boolean true) before := by
      simpa only [Bool.not_false, show (Int.ofNat index == Int.ofNat memory.data.tokens.length) = false from
        beq_eq_false_iff_ne.mpr (by intro same; exact done (Int.ofNat.inj same))] using condition
    obtain ⟨middle, stepped, next, firstEffect⟩ := validation_step program held (by omega)
    obtain ⟨after, finished, final, restEffect⟩ := validation_loop program next (by omega)
    exact ⟨after, executesWhileTrue trueCondition stepped finished, final, firstEffect.trans restEffect⟩
termination_by memory.data.tokens.length - index

end Lanius.Extraction.SemanticTokens.Collect
