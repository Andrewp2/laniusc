import Lanius.Extraction.Entry.Grammar

namespace Lanius.Extraction.Entry.Grammar

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Extraction.CompactOutput

theorem bodyStep (checked : Hex.Checked program) (locals : Locals)
    (source destination : List Int) (sourceCell destinationCell cursorCell : Lanius.CellId)
    (index value : Nat) (before : State)
    (wellFormed : StateWellFormed before) (bounded : value < 65536)
    (sourceBound : index < source.length) (destinationBound : index < destination.length)
    (indexFits : index + 1 ≤ 2147483647)
    (encoded : source.get ⟨index, sourceBound⟩ = Hex.packedWord value)
    (sourceLocal : before.local? locals.source = some (.slice i32 sourceCell [] 0 source.length))
    (destinationLocal : before.local? locals.destination = some (.slice i32 destinationCell [] 0 destination.length))
    (sourceContents : before.cellEntry? sourceCell = some {
      id := sourceCell, value := some (.array (signedI32Values source)) })
    (destinationContents : before.cellEntry? destinationCell = some {
      id := destinationCell, value := some (.array (signedI32Values destination)) })
    (cursor : (Assertion.localPointsTo locals.cursor cursorCell (some (.signed .i32 index))).holds before)
    (wordDestination : locals.word ≠ locals.destination) (wordCursor : locals.word ≠ locals.cursor)
    (destinationCursor : destinationCell ≠ cursorCell) :
    ∃ after, Executes program.core before (locals.body checked.source.function.id) .next after ∧
      after.cellEntry? destinationCell = some {
        id := destinationCell, value := some (.array (signedI32Values (destination.set index value))) } ∧
      (Assertion.localPointsTo locals.cursor cursorCell (some (.signed .i32 (index + 1 : Nat)))).holds after ∧
      CellEffect (CellSet.union (CellSet.singleton destinationCell) (CellSet.singleton cursorCell)) before after ∧
      HeapFrame before after := by
  have cursorRead := Assertion.localPointsTo_local _ _ _ _ cursor
  have loaded := evaluatesSignedI32SliceIndex program.core before before before source
    (.local locals.source) (.local locals.cursor) sourceCell index sourceBound
    (local_evaluates program.core sourceLocal) (local_evaluates program.core cursorRead) sourceContents
  rw [encoded] at loaded
  let scope := before.bindLocal locals.word (.signed .i32 (Hex.packedWord value))
  have scopeWF : StateWellFormed scope := bindLocal_preserves_well_formed before _ _ wellFormed
  have wordRead : scope.local? locals.word = some (.signed .i32 (Hex.packedWord value)) :=
    bindLocal_finds_local before _ _ wellFormed
  have destinationRead : scope.local? locals.destination = some
      (.slice i32 destinationCell [] 0 destination.length) :=
    (bindLocal_preserves_other_local wellFormed wordDestination).trans destinationLocal
  have indexRead : scope.local? locals.cursor = some (.signed .i32 index) :=
    (bindLocal_preserves_other_local wellFormed wordCursor).trans cursorRead
  have contents : scope.cellEntry? destinationCell = some {
      id := destinationCell, value := some (.array (signedI32Values destination)) } :=
    ((bindLocal_effect before locals.word (.signed .i32 (Hex.packedWord value))).oldCells destinationCell
      (StateWellFormed.cell_lt_next_of_entry wellFormed destinationContents) (by simp [CellSet.empty])).trans destinationContents
  obtain ⟨stored, assigned, storedContents, storeEffect, storeHeap⟩ := checked.storeValue locals.word locals.destination
    destination destinationCell index value (.local locals.cursor) bounded scopeWF wordRead destinationBound
    destinationRead (local_evaluates program.core indexRead) contents
  have cursorScope : (Assertion.localPointsTo locals.cursor cursorCell (some (.signed .i32 index))).holds scope :=
    bindLocal_preserves_localPointsTo_of_ne before locals.word locals.cursor
      (.signed .i32 (Hex.packedWord value)) cursorCell _ wellFormed wordCursor cursor
  have cursorStored := storeEffect.preserves_localPointsTo scopeWF cursorScope
    (by simpa [CellSet.singleton, eq_comm] using destinationCursor)
  obtain ⟨after, incremented, afterWF, cursorAfter, incrementEffect⟩ :=
    executesIncrementOwnedI32Local program.core stored locals.cursor cursorCell index
      storeEffect.wellFormed cursorStored indexFits
  have effect := (storeEffect.weaken CellSet.subset_union_left).trans
    ((CellEffect.ofModifiesOnly incrementEffect afterWF).weaken CellSet.subset_union_right)
  refine ⟨restoreLocals before after, executesLetLocal loaded
    (executesSequence (executesExpression assigned) incremented), ?_, ?_,
    CellEffect.closeLocal before locals.word (.signed .i32 (Hex.packedWord value)) wellFormed effect,
    HeapFrame.closeLocal before locals.word (.signed .i32 (Hex.packedWord value))
      (storeHeap.trans (HeapFrame.ofStoreEffect incrementEffect.toStoreEffect))⟩
  · exact incrementEffect.preserves_entry storeEffect.wellFormed storedContents destinationCursor
  · exact ⟨cursor.1, cursorAfter.2⟩

end Lanius.Extraction.Entry.Grammar
