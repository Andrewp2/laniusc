import Lanius.X86.Buffer.Bytes
import Lanius.X86.Source.Fixed

namespace Lanius.X86.Buffer

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView.Core Lanius.X86.Source

structure FixedResources (state : State) (cell : CellId) (position : Nat)
    (values : List Int) : Prop where
  wellFormed : StateWellFormed state
  sliceRead : state.local? 0 = some (.slice i32 cell [] 0 values.length)
  positionRead : state.local? 2 = some (.signed .i32 position)
  backing : state.cellEntry? cell = some {
    id := cell, value := some (.array (signedI32Values values)) }

theorem fixed_index (program : Program) (position offset : Nat)
    (bounded : position + offset ≤ 2147483647)
    (positionRead : before.local? 2 = some (.signed .i32 position)) :
    Evaluates program before (fixedIndex offset) (.signed .i32 (position + offset : Nat)) before := by
  by_cases zero : offset = 0
  · simpa only [fixedIndex, zero, ↓reduceIte, Nat.add_zero] using local_evaluates program positionRead
  · simpa only [fixedIndex, if_neg zero, Source.read, Source.number, Int.ofNat_eq_natCast] using
      evaluatesNatI32Add (local_evaluates program positionRead)
        (show Evaluates program before (number offset) (.signed .i32 (offset : Nat)) before from ⟨1, rfl⟩) bounded

theorem fixed_store (program : Program) (resources : FixedResources before cell position values)
    (offset byte : Nat) (room : position + offset < values.length)
    (bounded : position + offset ≤ 2147483647) :
    ∃ after, Evaluates program before (fixedStore offset byte) .unit after ∧
      FixedResources after cell position (values.set (position + offset) byte) ∧
      CellEffect (CellSet.singleton cell) before after ∧ HeapFrame before after := by
  obtain ⟨after, store, contents, effect, heapFrame, _⟩ := evaluatesSliceStore program before before
    values 0 (fixedIndex offset) (number byte) cell (position + offset) byte
    resources.wellFormed room resources.sliceRead
    (fixed_index program position offset bounded resources.positionRead) ⟨1, rfl⟩
    (CellEffect.refl resources.wellFormed) resources.backing
  refine ⟨after, store, ⟨effect.wellFormed, ?_, ?_, contents⟩, effect, heapFrame⟩
  · simpa only [List.length_set] using effect.preserves_local_of_distinct_value resources.wellFormed
      resources.sliceRead resources.backing (by intro same; cases same)
  · exact effect.preserves_local_of_distinct_value resources.wellFormed
      resources.positionRead resources.backing (by intro same; cases same)

/-- Execute the source's entire straight-line suffix, including its return.
One induction covers every fixed byte sequence, rather than a separate proof
for each opcode or each buffer length. -/
theorem fixed_stores (program : Program) (resources : FixedResources before cell position values)
    (count offset : Nat) (bytes : List Nat) (within : offset + bytes.length ≤ count)
    (room : position + count ≤ values.length) (bounded : position + count ≤ 2147483647) :
    ∃ after, Executes program before (fixedStatements count offset bytes)
        (.returned (some (.signed .i32 (position + count : Nat)))) after ∧
      FixedResources after cell position (writtenBytes values (position + offset) bytes) ∧
      CellEffect (CellSet.singleton cell) before after ∧ HeapFrame before after := by
  induction bytes generalizing offset before values with
  | nil =>
      have next := evaluatesNatI32Add (local_evaluates program resources.positionRead)
        (show Evaluates program before (number count) (.signed .i32 (count : Nat)) before from ⟨1, rfl⟩) bounded
      exact ⟨before, executesSequenceReturned (executesReturnValue next), resources,
        CellEffect.refl resources.wellFormed, HeapFrame.refl before⟩
  | cons byte bytes ih =>
      obtain ⟨middle, store, middleResources, storeEffect, storeHeap⟩ :=
        fixed_store program resources offset byte (by simp only [List.length_cons] at within; omega) (by omega)
      obtain ⟨after, rest, afterResources, restEffect, restHeap⟩ :=
        ih middleResources (offset + 1) (by simp only [List.length_cons] at within; omega)
          (by simpa only [List.length_set] using room)
      refine ⟨after, executesSequence (executesExpression store) rest, ?_,
        storeEffect.trans restEffect, storeHeap.trans restHeap⟩
      simpa only [writtenBytes, Nat.add_assoc] using afterResources

theorem fixed_guard (fits : CheckedFits program) (capacity cursor : Int) (count : Nat)
    (wellFormed : StateWellFormed before) (capacityBound : capacity ≤ 2147483647)
    (capacityRead : before.local? 1 = some (.signed .i32 capacity))
    (cursorRead : before.local? 2 = some (.signed .i32 cursor)) :
    ∃ after, Evaluates program.core before (fixedGuard fits.source.function.id count)
        (.boolean (!reserved capacity cursor count)) after ∧
      CellEffect CellSet.empty before after ∧ HeapFrame before after := by
  have arguments : ArgumentsEvaluateTo program.core before [read 1, read 2, number count]
      (fitsValues capacity cursor count) before :=
    .cons (local_evaluates program.core capacityRead) (.cons (local_evaluates program.core cursorRead)
      (.cons ⟨1, rfl⟩ (.nil _ _)))
  obtain ⟨after, fit, effect, heapFrame⟩ := fits_call fits capacity cursor count wellFormed capacityBound arguments
  exact ⟨after, evaluatesUnary fit rfl, effect, heapFrame⟩

def fixedValues (output : Value) (capacity cursor : Int) : List Value :=
  [output, .signed .i32 capacity, .signed .i32 cursor]

def fixedBindings (output : Value) (capacity cursor : Int) : List (VarId × Value) :=
  parameterBindings (fun index : Fin 3 => (fixedValues output capacity cursor).get index)

/-- Rejection occurs before any output access, even when the output value is
not a slice. Existing caller memory and host observations are preserved. -/
theorem fixed_reject (checked : CheckedFixed program fits modulePath name bytes) (output : Value)
    (capacity cursor : Int) (wellFormed : StateWellFormed before)
    (capacityBound : capacity ≤ 2147483647) (bad : reserved capacity cursor bytes.length = false)
    (argumentsResult : ArgumentsEvaluateTo program.core caller arguments
      (fixedValues output capacity cursor) before) :
    ∃ after, Evaluates program.core caller (.call checked.source.function.id arguments)
        (.signed .i32 (-1)) after ∧
      CellEffect CellSet.empty before after ∧ HeapFrame before after := by
  let bindings := fixedBindings output capacity cursor
  let callee := enterCall before bindings
  have locals (index : Fin 3) : callee.local? index.val =
      some ((fixedValues output capacity cursor).get index) :=
    enterCall_parameterBindings_matches wellFormed index
  obtain ⟨middle, guard, effect, heapFrame⟩ := fixed_guard fits capacity cursor bytes.length
    (enterCall_preserves_wellFormed wellFormed) capacityBound (locals ⟨1, by decide⟩) (locals ⟨2, by decide⟩)
  rw [bad] at guard
  have negative : Evaluates program.core middle negativeOne (.signed .i32 (-1)) middle := by
    apply evaluatesUnary (show Evaluates program.core middle (number 1) (.signed .i32 1) middle from ⟨1, rfl⟩)
    simp [evalUnaryValue, wrapSigned, signedModulus, signedSignBit, SignedIntTy.bits]
  have run : Executes program.core callee (fixedBody fits.source.function.id bytes)
      (.returned (some (.signed .i32 (-1)))) middle :=
    executesSequenceReturned (executesIfTrue guard
      (executesSequenceReturned (executesReturnValue negative)))
  have called := checked.call wellFormed argumentsResult (bindings := bindings) rfl run effect
  exact ⟨restoreLocals before middle, called.1, called.2, HeapFrame.closeCall before bindings heapFrame⟩

/-- Full actual-source contract for a fixed instruction emitter: reserve,
write the requested bytes, return the new cursor, and restore caller locals. -/
theorem fixed_success (checked : CheckedFixed program fits modulePath name bytes)
    (capacity cursor : Nat) (wellFormed : StateWellFormed before)
    (room : cursor + bytes.length ≤ capacity) (storage : capacity ≤ values.length)
    (capacityBound : capacity ≤ 2147483647)
    (backing : before.cellEntry? cell = some {
      id := cell, value := some (.array (signedI32Values values)) })
    (argumentsResult : ArgumentsEvaluateTo program.core caller arguments
      (fixedValues (.slice i32 cell [] 0 values.length) capacity cursor) before) :
    ∃ after, Evaluates program.core caller (.call checked.source.function.id arguments)
        (.signed .i32 (cursor + bytes.length : Nat)) after ∧
      after.cellEntry? cell = some {
        id := cell, value := some (.array (signedI32Values (writtenBytes values cursor bytes))) } ∧
      CellEffect (CellSet.singleton cell) before after ∧ HeapFrame before after := by
  let output : Value := .slice i32 cell [] 0 values.length
  let bindings := fixedBindings output capacity cursor
  let callee := enterCall before bindings
  have calleeWF := enterCall_preserves_wellFormed wellFormed (bindings := bindings)
  have locals (index : Fin 3) : callee.local? index.val =
      some ((fixedValues output capacity cursor).get index) :=
    enterCall_parameterBindings_matches wellFormed index
  have calleeBacking := ((enterCall_effect before bindings).oldCells cell
    (StateWellFormed.cell_lt_next_of_entry wellFormed backing) (by simp [CellSet.empty])).trans backing
  obtain ⟨middle, guard, guardEffect, guardHeap⟩ := fixed_guard fits capacity cursor bytes.length
    calleeWF (Int.ofNat_le.mpr capacityBound) (locals ⟨1, by decide⟩) (locals ⟨2, by decide⟩)
  have good : reserved capacity cursor bytes.length = true := by
    simp only [reserved, decide_eq_true_eq]
    omega
  rw [good] at guard
  have resources : FixedResources middle cell cursor values := ⟨guardEffect.wellFormed,
    guardEffect.empty_preserves_local calleeWF (locals ⟨0, by decide⟩),
    guardEffect.empty_preserves_local calleeWF (locals ⟨2, by decide⟩),
    guardEffect.empty_preserves_entry calleeWF calleeBacking⟩
  obtain ⟨completed, stores, completedResources, storeEffect, storeHeap⟩ :=
    fixed_stores program.core resources bytes.length 0 bytes (by omega) (by omega) (by omega)
  have run : Executes program.core callee (fixedBody fits.source.function.id bytes)
      (.returned (some (.signed .i32 (cursor + bytes.length : Nat)))) completed :=
    executesSequence (executesIfFalse guard (executesSkip _ _)) stores
  have effect := (guardEffect.weaken (larger := CellSet.singleton cell) CellSet.empty_subset).trans storeEffect
  have called := checked.call wellFormed argumentsResult (bindings := bindings) rfl run effect
  exact ⟨restoreLocals before completed, called.1, completedResources.backing, called.2,
    HeapFrame.closeCall before bindings (guardHeap.trans storeHeap)⟩

end Lanius.X86.Buffer
