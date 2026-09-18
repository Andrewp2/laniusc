import Lanius.Extraction.Entry.GrammarStep
import Lanius.Extraction.BufferCopy.Loop
import Lanius.Extraction.Allocation.Transport

namespace Lanius.Extraction.Entry.Grammar

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Extraction.CompactOutput

structure Memory (locals : Locals) where
  sourceCell : Lanius.CellId
  destinationCell : Lanius.CellId
  cursorCell : Lanius.CellId
  values : List Nat
  untouched : List Int
  bounded : ∀ value ∈ values, value < 65536
  capacity : values.length ≤ untouched.length
  fits : untouched.length ≤ 2147483647
  count : locals.count = values.length
  sourceDestination : sourceCell ≠ destinationCell
  sourceCursor : sourceCell ≠ cursorCell
  destinationCursor : destinationCell ≠ cursorCell
  wordDestination : locals.word ≠ locals.destination
  wordCursor : locals.word ≠ locals.cursor

def Memory.source (memory : Memory locals) : List Int :=
  memory.values.map (fun value => (Hex.packedWord value : Int))

def Memory.buffer (memory : Memory locals) (processed : List Nat) : List Int :=
  BufferCopy.buffer memory.untouched (processed.map Int.ofNat)

def Memory.writes (memory : Memory locals) : CellSet :=
  CellSet.union (CellSet.singleton memory.destinationCell) (CellSet.singleton memory.cursorCell)

structure Invariant (memory : Memory locals) (processed : List Nat) (state : State) : Prop where
  wellFormed : StateWellFormed state
  sourceLocal : state.local? locals.source = some (.slice i32 memory.sourceCell [] 0 memory.source.length)
  destinationLocal : state.local? locals.destination = some (.slice i32 memory.destinationCell [] 0 memory.untouched.length)
  sourceContents : state.cellEntry? memory.sourceCell = some {
    id := memory.sourceCell, value := some (.array (signedI32Values memory.source)) }
  destinationContents : state.cellEntry? memory.destinationCell = some {
    id := memory.destinationCell, value := some (.array (signedI32Values (memory.buffer processed))) }
  cursor : (Assertion.localPointsTo locals.cursor memory.cursorCell (some (.signed .i32 processed.length))).holds state
  stable : ∀ id, id ∈ [locals.source, locals.destination] → ∀ cell,
    state.cellId? id = some cell → ¬ memory.writes cell

theorem step (checked : Hex.Checked program) (locals : Locals) (memory : Memory locals)
    (processed remaining : List Nat) (value : Nat) (before : State)
    (selected : memory.values = processed ++ value :: remaining)
    (invariant : Invariant memory processed before) :
    ∃ after, Executes program.core before (locals.body checked.source.function.id) .next after ∧
      Invariant memory (processed ++ [value]) after ∧ CellEffect memory.writes before after ∧ HeapFrame before after := by
  have lengths : memory.values.length = processed.length + 1 + remaining.length := by simp [selected]; omega
  have room : processed.length < memory.untouched.length := by have := memory.capacity; omega
  have bufferLength : (memory.buffer processed).length = memory.untouched.length := by
    apply BufferCopy.buffer_length
    simpa using Nat.le_of_lt room
  have sourceBound : processed.length < memory.source.length := by simp [Memory.source]; omega
  have encoded : memory.source.get ⟨processed.length, sourceBound⟩ = Hex.packedWord value := by
    simp [Memory.source, selected, List.get_eq_getElem]
  have valueBound := memory.bounded value (by simp [selected])
  obtain ⟨after, ran, contents, cursor, effect, heapFrame⟩ := bodyStep checked locals memory.source
    (memory.buffer processed) memory.sourceCell memory.destinationCell memory.cursorCell processed.length value
    before invariant.wellFormed valueBound sourceBound (by omega)
    (by have := memory.fits; omega) encoded invariant.sourceLocal
    (by simpa only [bufferLength] using invariant.destinationLocal)
    invariant.sourceContents invariant.destinationContents invariant.cursor
    memory.wordDestination memory.wordCursor memory.destinationCursor
  have updated : (memory.buffer processed).set processed.length value = memory.buffer (processed ++ [value]) := by
    simpa [Memory.buffer, List.map_append] using BufferCopy.buffer_step memory.untouched
      (processed.map Int.ofNat) value (by simpa using room)
  rw [updated] at contents
  refine ⟨after, ran, ⟨effect.wellFormed, ?_, ?_, ?_, contents, ?_, ?_⟩, effect, heapFrame⟩
  · exact effect.preserves_local invariant.wellFormed invariant.sourceLocal (invariant.stable _ (by simp))
  · exact effect.preserves_local invariant.wellFormed invariant.destinationLocal (invariant.stable _ (by simp))
  · exact effect.preserves_entry invariant.wellFormed invariant.sourceContents
      (by simp [CellSet.union, CellSet.singleton, memory.sourceDestination, memory.sourceCursor])
  · simpa using cursor
  · intro id member cell found
    apply invariant.stable id member cell
    simpa only [State.cellId?, effect.locals] using found

theorem executesLoop (checked : Hex.Checked program) (locals : Locals) (memory : Memory locals)
    (processed remaining : List Nat) (before : State)
    (selected : memory.values = processed ++ remaining)
    (invariant : Invariant memory processed before) :
    ∃ after, Executes program.core before (locals.loop checked.source.function.id) .next after ∧
      Invariant memory memory.values after ∧ CellEffect memory.writes before after ∧ HeapFrame before after := by
  have cursorResult := local_evaluates program.core (Assertion.localPointsTo_local _ _ _ _ invariant.cursor)
  have condition : Evaluates program.core before
      (.binary .notEqual (.local locals.cursor) (.value (.signed .i32 locals.count)))
      (.boolean (!(Int.ofNat processed.length == Int.ofNat memory.values.length))) before := by
    apply evaluatesEagerBinary (by decide) (by decide) cursorResult
      (show Evaluates program.core before (.value (.signed .i32 locals.count)) (.signed .i32 locals.count) before from ⟨1, rfl⟩)
    simp [evalBinaryValue, scalarEqual, memory.count]
  cases remaining with
  | nil =>
      have complete : memory.values = processed := by simpa using selected
      exact ⟨before, executesWhileFalse (by simpa [complete] using condition),
        complete.symm ▸ invariant, CellEffect.refl invariant.wellFormed, HeapFrame.refl _⟩
  | cons value rest =>
      have different : Int.ofNat processed.length ≠ Int.ofNat memory.values.length := by
        intro equal
        have equalNat := Int.ofNat.inj equal
        simp only [selected, List.length_append, List.length_cons] at equalNat
        omega
      have trueCondition : Evaluates program.core before
          (.binary .notEqual (.local locals.cursor) (.value (.signed .i32 locals.count)))
          (.boolean true) before := by
        rw [beq_eq_false_iff_ne.mpr different] at condition
        exact condition
      obtain ⟨middle, body, nextInvariant, bodyEffect, bodyHeap⟩ := step checked locals memory
        processed rest value before selected invariant
      obtain ⟨after, loop, complete, loopEffect, loopHeap⟩ := executesLoop checked locals memory
        (processed ++ [value]) rest middle (by simpa [List.append_assoc] using selected) nextInvariant
      exact ⟨after, executesWhileTrue trueCondition body loop, complete, bodyEffect.trans loopEffect,
        bodyHeap.trans loopHeap⟩
termination_by remaining.length

theorem loopSound (checked : Hex.Checked program) (locals : Locals) (memory : Memory locals)
    (processed remaining : List Nat) (before after : State)
    (selected : memory.values = processed ++ remaining)
    (invariant : Invariant memory processed before)
    (actual : Executes program.core before (locals.loop checked.source.function.id) completion after) :
    completion = .next ∧ Invariant memory memory.values after ∧ CellEffect memory.writes before after ∧ HeapFrame before after := by
  obtain ⟨expected, executed, complete, effect, heapFrame⟩ :=
    executesLoop checked locals memory processed remaining before selected invariant
  obtain ⟨sameCompletion, sameState⟩ := Lanius.Fuel.executes_deterministic actual executed
  subst after
  exact ⟨sameCompletion, complete, effect, heapFrame⟩

/-- The typed destination update and scalar cursor cannot invalidate any
registered view. This connects loop ownership to the next host-call phase. -/
theorem preservesRegistry (memory : Memory locals) (processed : List Nat)
    (prefixLength : processed.length ≤ memory.values.length)
    (initial : Allocation.Registry before)
    (beforeInvariant : Invariant memory processed before)
    (afterInvariant : Invariant memory memory.values after)
    (effect : CellEffect memory.writes before after) (heapFrame : HeapFrame before after) :
    Allocation.Registry after := by
  apply initial.updateArrayAndScalar effect heapFrame beforeInvariant.destinationContents
    afterInvariant.destinationContents _ beforeInvariant.cursor.2
  have beforeLength : (memory.buffer processed).length = memory.untouched.length :=
    BufferCopy.buffer_length memory.untouched (processed.map Int.ofNat)
      (by simpa only [List.length_map] using Nat.le_trans prefixLength memory.capacity)
  have afterLength : (memory.buffer memory.values).length = memory.untouched.length :=
    BufferCopy.buffer_length memory.untouched (memory.values.map Int.ofNat)
      (by simpa only [List.length_map] using memory.capacity)
  exact afterLength.trans beforeLength.symm

end Lanius.Extraction.Entry.Grammar
