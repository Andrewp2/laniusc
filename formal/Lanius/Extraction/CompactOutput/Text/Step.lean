import Lanius.Extraction.CompactOutput.Text.Read
import Lanius.Separation.LocalCall

namespace Lanius.Extraction.CompactOutput.Text

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts

def writes (outputCell positionCell indexCell : CellId) : CellSet :=
  CellSet.union (CellSet.union (CellSet.singleton outputCell) (CellSet.singleton positionCell))
    (CellSet.singleton indexCell)

/-- A successful iteration derives the packed read, helper call, sticky-error
test, and both cursor updates from owned storage. -/
theorem stepSuccess (byte : CheckedByte program)
    (values : List Int) (storage : List UInt8) (index position capacity : Nat) (value : UInt8)
    (wellFormed : StateWellFormed before) (room : position < capacity)
    (capacityBound : capacity ≤ original.length) (capacityFit : capacity ≤ 2147483647)
    (indexFit : index + 1 ≤ 2147483647)
    (inputRead : before.local? 5 = some (.slice i32 inputCell [] 0 values.length))
    (inputContents : before.cellEntry? inputCell = some {
      id := inputCell, value := some (.array (signedI32Values values)) })
    (encoded : encodeI32Array (signedI32Values values) = .ok storage)
    (selected : storage[index]? = some value)
    (outputRead : before.local? 0 = some (.slice i32 outputCell [] 0 original.length))
    (capacityRead : before.local? 1 = some (.signed .i32 capacity))
    (positionOwned : (Assertion.localPointsTo 6 positionCell (some (.signed .i32 position))).holds before)
    (indexOwned : (Assertion.localPointsTo 7 indexCell (some (.signed .i32 index))).holds before)
    (distinct : positionCell ≠ indexCell)
    (contents : before.cellEntry? outputCell = some {
      id := outputCell, value := some (.array (signedI32Values original)) }) :
    ∃ after, Executes program.core before (step byte.source.function.id) .next after ∧
      after.cellEntry? outputCell = some {
        id := outputCell, value := some (.array (signedI32Values (original.set position value.toNat))) } ∧
      (Assertion.localPointsTo 6 positionCell (some (.signed .i32 (position + 1 : Nat)))).holds after ∧
      (Assertion.localPointsTo 7 indexCell (some (.signed .i32 (index + 1 : Nat)))).holds after ∧
      CellEffect (writes outputCell positionCell indexCell) before after ∧ HeapFrame before after := by
  have outputPosition : outputCell ≠ positionCell := by
    intro same; rw [same, positionOwned.2] at contents; cases contents
  have outputIndex : outputCell ≠ indexCell := by
    intro same; rw [same, indexOwned.2] at contents; cases contents
  have loaded := readValue program.core before values storage index value (by omega)
    inputRead (Assertion.localPointsTo_local _ _ _ _ indexOwned) inputContents encoded selected
  let scope := before.bindLocal 8 (.signed .i32 value.toNat)
  have scopeWF : StateWellFormed scope := bindLocal_preserves_well_formed before _ _ wellFormed
  have scopeOutput := (bindLocal_preserves_other_local (boundId := 8) (queriedId := 0)
    (value := .signed .i32 value.toNat) wellFormed (by decide)).trans outputRead
  have scopeCapacity := (bindLocal_preserves_other_local (boundId := 8) (queriedId := 1)
    (value := .signed .i32 value.toNat) wellFormed (by decide)).trans capacityRead
  have scopePosition := bindLocal_preserves_localPointsTo_of_ne before 8 6
    (.signed .i32 value.toNat) positionCell _ wellFormed (by decide) positionOwned
  have scopeIndex := bindLocal_preserves_localPointsTo_of_ne before 8 7
    (.signed .i32 value.toNat) indexCell _ wellFormed (by decide) indexOwned
  have scopeContents := ((bindLocal_effect before 8 (.signed .i32 value.toNat)).oldCells outputCell
    (StateWellFormed.cell_lt_next_of_entry wellFormed contents) (by simp [CellSet.empty])).trans contents
  obtain ⟨written, called, writtenContents, callEffect, callHeap⟩ := appendValue byte position capacity value
    scopeWF room capacityBound capacityFit scopeOutput scopeCapacity
    (Assertion.localPointsTo_local _ _ _ _ scopePosition)
    (bindLocal_finds_local before 8 (.signed .i32 value.toNat) wellFormed) scopeContents
  have positionStill := callEffect.preserves_localPointsTo scopeWF scopePosition
    (by simpa [CellSet.singleton, eq_comm] using outputPosition)
  obtain ⟨assigned, assignment, newPosition, assignmentEffect, setEffect, setHeap, _⟩ :=
    evaluatesOwnedLocalSet scopePosition called callEffect positionStill
  have indexStill := assignmentEffect.preserves_localPointsTo scopeWF scopeIndex (by
    intro changed; rcases changed with changed | changed
    · exact outputIndex changed.symm
    · exact distinct changed.symm)
  have assignedContents := setEffect.preserves_entry callEffect.wellFormed writtenContents
    (by simpa [CellSet.singleton] using outputPosition)
  have guard : Evaluates program.core assigned (binary .equal (read 6) negativeOne)
      (.boolean false) assigned := by
    apply evaluatesEagerBinary (by decide) (by decide)
      (local_evaluates program.core (Assertion.localPointsTo_local _ _ _ _ newPosition))
      (negativeOne_evaluates program.core assigned)
    simp [evalBinaryValue, scalarEqual]
    omega
  obtain ⟨after, incremented, afterWF, newIndex, incrementEffect⟩ :=
    executesIncrementOwnedI32Local program.core assigned 7 indexCell index
      assignmentEffect.wellFormed indexStill indexFit
  have finalPosition := incrementEffect.preserves_localPointsTo assignmentEffect.wellFormed
    newPosition distinct
  have effect := (assignmentEffect.weaken CellSet.subset_union_left).trans
    ((CellEffect.ofModifiesOnly incrementEffect afterWF).weaken CellSet.subset_union_right)
  refine ⟨restoreLocals before after, executesLetLocal loaded
    (executesSequence (executesExpression assignment)
      (executesSequence (executesIfFalse guard (executesSkip _ _)) incremented)),
    incrementEffect.preserves_entry assignmentEffect.wellFormed assignedContents outputIndex,
    ⟨positionOwned.1, finalPosition.2⟩, ⟨indexOwned.1, newIndex.2⟩,
    CellEffect.closeLocal before 8 (.signed .i32 value.toNat) wellFormed effect,
    HeapFrame.closeLocal before 8 (.signed .i32 value.toNat)
      ((callHeap.trans setHeap).trans (HeapFrame.ofStoreEffect incrementEffect.toStoreEffect))⟩

/-- Exhaustion still reads the selected packed byte, then returns before
writing output or incrementing the input index. Only the error cursor changes. -/
theorem stepFull (byte : CheckedByte program)
    (values : List Int) (storage : List UInt8) (index capacity : Nat) (value : UInt8)
    (wellFormed : StateWellFormed before) (indexFit : index ≤ 2147483647)
    (inputRead : before.local? 5 = some (.slice i32 inputCell [] 0 values.length))
    (inputContents : before.cellEntry? inputCell = some {
      id := inputCell, value := some (.array (signedI32Values values)) })
    (encoded : encodeI32Array (signedI32Values values) = .ok storage)
    (selected : storage[index]? = some value)
    (outputRead : before.local? 0 = some (.slice i32 outputCell [] 0 original.length))
    (capacityRead : before.local? 1 = some (.signed .i32 capacity))
    (positionOwned : (Assertion.localPointsTo 6 positionCell (some (.signed .i32 capacity))).holds before)
    (indexOwned : (Assertion.localPointsTo 7 indexCell (some (.signed .i32 index))).holds before)
    (contents : before.cellEntry? outputCell = some {
      id := outputCell, value := some (.array (signedI32Values original)) }) :
    ∃ after, Executes program.core before (step byte.source.function.id)
        (.returned (some (.signed .i32 (-1)))) after ∧
      after.cellEntry? outputCell = some {
        id := outputCell, value := some (.array (signedI32Values original)) } ∧
      CellEffect (CellSet.singleton positionCell) before after ∧ HeapFrame before after := by
  have outputPosition : outputCell ≠ positionCell := by
    intro same; rw [same, positionOwned.2] at contents; cases contents
  have loaded := readValue program.core before values storage index value indexFit
    inputRead (Assertion.localPointsTo_local _ _ _ _ indexOwned) inputContents encoded selected
  let scope := before.bindLocal 8 (.signed .i32 value.toNat)
  have scopeWF : StateWellFormed scope := bindLocal_preserves_well_formed before _ _ wellFormed
  have scopeOutput := (bindLocal_preserves_other_local (boundId := 8) (queriedId := 0)
    (value := .signed .i32 value.toNat) wellFormed (by decide)).trans outputRead
  have scopeCapacity := (bindLocal_preserves_other_local (boundId := 8) (queriedId := 1)
    (value := .signed .i32 value.toNat) wellFormed (by decide)).trans capacityRead
  have scopePosition := bindLocal_preserves_localPointsTo_of_ne before 8 6
    (.signed .i32 value.toNat) positionCell _ wellFormed (by decide) positionOwned
  have scopeContents := ((bindLocal_effect before 8 (.signed .i32 value.toNat)).oldCells outputCell
    (StateWellFormed.cell_lt_next_of_entry wellFormed contents) (by simp [CellSet.empty])).trans contents
  obtain ⟨written, called, _, callEffect, callHeap⟩ := (byte.reject
    (.slice i32 outputCell [] 0 original.length) capacity capacity value.toNat
    (by simp [byteBad])).call scopeWF
    (.cons (local_evaluates program.core scopeOutput)
      (.cons (local_evaluates program.core scopeCapacity)
        (.cons (local_evaluates program.core (Assertion.localPointsTo_local _ _ _ _ scopePosition))
          (.cons (local_evaluates program.core (bindLocal_finds_local before 8 (.signed .i32 value.toNat) wellFormed))
            (.nil _ _)))))
  have positionStill := callEffect.preserves_localPointsTo scopeWF scopePosition
    (by simp [CellSet.empty])
  obtain ⟨assigned, assignment, newPosition, assignmentEffect, setEffect, setHeap, _⟩ :=
    evaluatesOwnedLocalSet scopePosition called callEffect positionStill
  have effect : CellEffect (CellSet.singleton positionCell) scope assigned :=
    assignmentEffect.weaken (by intro cell changed; exact changed.elim False.elim id)
  have assignedContents := effect.preserves_entry scopeWF scopeContents outputPosition
  have guard : Evaluates program.core assigned (binary .equal (read 6) negativeOne)
      (.boolean true) assigned := by
    apply evaluatesEagerBinary (by decide) (by decide)
      (local_evaluates program.core (Assertion.localPointsTo_local _ _ _ _ newPosition))
      (negativeOne_evaluates program.core assigned)
    simp [evalBinaryValue, scalarEqual]
  exact ⟨restoreLocals before assigned,
    executesLetLocal loaded (executesSequence (executesExpression assignment)
      (executesSequenceReturned (executesIfTrue guard
        (executesSequenceReturned (executesReturnValue (negativeOne_evaluates program.core assigned)))))),
    assignedContents, CellEffect.closeLocal before 8 (.signed .i32 value.toNat) wellFormed effect,
    HeapFrame.closeLocal before 8 (.signed .i32 value.toNat) (callHeap.trans setHeap)⟩

end Lanius.Extraction.CompactOutput.Text
