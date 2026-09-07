import Lanius.Extraction.CanonicalTokens.Ascii.Source
import Lanius.Separation

namespace Lanius.Extraction.CanonicalTokens.Ascii

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation

/-- One comparison iteration of the actual source loop. Introducing the
temporary byte may allocate a fresh semantic cell, but only the existing
cursor cell can change; the caller's lexical bindings are restored. -/
theorem executes_body (program : Program) (before : State) (locals : Locals)
    (sourceCell cursorCell : CellId) (source : List Int) (start index : Nat) (byte : UInt8)
    (wellFormed : StateWellFormed before)
    (inBounds : start + index < source.length) (bounded : source.length ≤ 2147483647)
    (expected_source : locals.expected ≠ locals.source)
    (expected_start : locals.expected ≠ locals.start)
    (expected_cursor : locals.expected ≠ locals.cursor)
    (sourceLocal : before.local? locals.source = some
      (.slice (.scalar (.signed .i32)) sourceCell [] 0 source.length))
    (sourceContents : before.cellEntry? sourceCell = some {
      id := sourceCell
      value := some (.array (signedI32Values source)) })
    (startLocal : before.local? locals.start = some (.signed .i32 start))
    (cursor : (Assertion.localPointsTo locals.cursor cursorCell
      (some (.signed .i32 index))).holds before)
    (expectedByte : Evaluates program before locals.byte (.signed .i32 byte.toNat) before) :
    let same := source.get ⟨start + index, inBounds⟩ = (byte.toNat : Int)
    ∃ after,
      Executes program before locals.body
        (if same then .next else .returned (some (.boolean false))) after ∧
      StateWellFormed after ∧
      (Assertion.localPointsTo locals.cursor cursorCell
        (some (.signed .i32 (if same then index + 1 else index)))).holds after ∧
      ModifiesOnly (CellSet.singleton cursorCell) before after := by
  let entered := before.bindLocal locals.expected (.signed .i32 byte.toNat)
  have enteredWF : StateWellFormed entered :=
    bindLocal_preserves_well_formed before locals.expected _ wellFormed
  have sourceStill : entered.local? locals.source = some
      (.slice (.scalar (.signed .i32)) sourceCell [] 0 source.length) :=
    (bindLocal_preserves_other_local wellFormed expected_source).trans sourceLocal
  have startStill : entered.local? locals.start = some (.signed .i32 start) :=
    (bindLocal_preserves_other_local wellFormed expected_start).trans startLocal
  have cursorStill := bindLocal_preserves_localPointsTo_of_ne before locals.expected locals.cursor
    (.signed .i32 byte.toNat) cursorCell (some (.signed .i32 index)) wellFormed expected_cursor cursor
  have contentsStill : entered.cellEntry? sourceCell = some {
      id := sourceCell
      value := some (.array (signedI32Values source)) } := by
    have old := StateWellFormed.cell_lt_next_of_entry wellFormed sourceContents
    exact (bindCell_preserves_old_cell before locals.expected (some (.signed .i32 byte.toNat)) sourceCell old).trans
      sourceContents
  have sourceResult : Evaluates program entered (.local locals.source)
      (.slice (.scalar (.signed .i32)) sourceCell [] 0 source.length) entered :=
    ⟨1, evalLocal_of_local 0 program entered _ _ sourceStill⟩
  have startResult : Evaluates program entered (.local locals.start) (.signed .i32 start) entered :=
    ⟨1, evalLocal_of_local 0 program entered _ _ startStill⟩
  have cursorResult : Evaluates program entered (.local locals.cursor) (.signed .i32 index) entered :=
    ⟨1, evalLocal_of_local 0 program entered _ _ (Assertion.localPointsTo_local _ _ _ _ cursorStill)⟩
  have indexResult := evaluatesNatI32Add startResult cursorResult (by omega)
  have actualResult := evaluatesSignedI32SliceIndex program entered entered entered source
    (.local locals.source) _ sourceCell (start + index) inBounds sourceResult indexResult contentsStill
  have expectedLocal : entered.local? locals.expected = some (.signed .i32 byte.toNat) :=
    bindLocal_finds_local before locals.expected _ wellFormed
  have expectedResult : Evaluates program entered (.local locals.expected) (.signed .i32 byte.toNat) entered :=
    ⟨1, evalLocal_of_local 0 program entered _ _ expectedLocal⟩
  have different : Evaluates program entered locals.different
      (.boolean (source.get ⟨start + index, inBounds⟩ != (byte.toNat : Int))) entered :=
    evaluatesEagerBinary (by decide) (by decide) actualResult expectedResult (by rfl)
  have entryEffect : StoreEffect (CellSet.singleton cursorCell) before entered :=
    (bindLocal_effect before locals.expected (.signed .i32 byte.toNat)).weaken CellSet.empty_subset
  dsimp only
  by_cases same : source.get ⟨start + index, inBounds⟩ = (byte.toNat : Int)
  · simp only [if_pos same]
    have comparison : Evaluates program entered locals.different (.boolean false) entered := by
      rw [same] at different
      simpa using different
    obtain ⟨completed, increment, completedWF, incremented, effect⟩ :=
      executesIncrementOwnedI32Local program entered locals.cursor cursorCell index enteredWF cursorStill (by omega)
    have sequence : Executes program entered locals.continuation .next completed :=
      executesSequence (executesIfFalse comparison (executesSkip program entered)) increment
    have complete := entryEffect.trans_same effect.toStoreEffect
    refine ⟨restoreLocals before completed, executesLetLocal expectedByte sequence,
      complete.restoreLocals_wellFormed wellFormed completedWF, ?_, complete.restoreLocals⟩
    exact ⟨cursor.1, incremented.2⟩
  · simp only [if_neg same]
    have comparison : Evaluates program entered locals.different (.boolean true) entered := by
      have unequal : (source.get ⟨start + index, inBounds⟩ == (byte.toNat : Int)) = false :=
        beq_eq_false_iff_ne.mpr same
      change Evaluates program entered locals.different
        (.boolean (!(source.get ⟨start + index, inBounds⟩ == (byte.toNat : Int)))) entered at different
      rw [unequal] at different
      exact different
    have returned := executesReturnValue (program := program) (state := entered)
      (expression := Expr.value (.boolean false)) (by exact ⟨1, rfl⟩)
    have sequence : Executes program entered locals.continuation (.returned (some (.boolean false))) entered :=
      executesSequenceReturned (executesIfTrue comparison (executesSequenceReturned returned))
    refine ⟨restoreLocals before entered, executesLetLocal expectedByte sequence,
      entryEffect.restoreLocals_wellFormed wellFormed enteredWF, ?_, entryEffect.restoreLocals⟩
    exact ⟨cursor.1, cursorStill.2⟩

end Lanius.Extraction.CanonicalTokens.Ascii
