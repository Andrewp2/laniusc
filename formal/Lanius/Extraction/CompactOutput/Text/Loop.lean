import Lanius.Extraction.CompactOutput.Text.Step
import Lanius.Extraction.Allocation.Transport

namespace Lanius.Extraction.CompactOutput.Text

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts

structure Memory where
  inputCell : CellId
  outputCell : CellId
  positionCell : CellId
  indexCell : CellId
  words : List Int
  storage : List UInt8
  bytes : List UInt8
  earlier : List Int
  untouched : List Int
  capacity : Nat
  encoded : encodeI32Array (signedI32Values words) = .ok storage
  sourceBytes : storage.take bytes.length = bytes
  capacityBound : capacity ≤ earlier.length + untouched.length
  capacityFit : capacity ≤ 2147483647
  distinctLocals : positionCell ≠ indexCell
  inputOutput : inputCell ≠ outputCell
  inputPosition : inputCell ≠ positionCell
  inputIndex : inputCell ≠ indexCell

def Memory.writes (memory : Memory) := Text.writes memory.outputCell memory.positionCell memory.indexCell
def Memory.output (memory : Memory) (processed : List UInt8) :=
  Input.copiedBuffer memory.earlier memory.untouched processed

structure Invariant (memory : Memory) (processed : List UInt8) (state : State) : Prop where
  wellFormed : StateWellFormed state
  inputLocal : state.local? 5 = some (.slice i32 memory.inputCell [] 0 memory.words.length)
  inputContents : state.cellEntry? memory.inputCell = some {
    id := memory.inputCell, value := some (.array (signedI32Values memory.words)) }
  outputLocal : state.local? 0 = some
    (.slice i32 memory.outputCell [] 0 (memory.earlier.length + memory.untouched.length))
  outputContents : state.cellEntry? memory.outputCell = some {
    id := memory.outputCell, value := some (.array (signedI32Values (memory.output processed))) }
  capacity : state.local? 1 = some (.signed .i32 memory.capacity)
  length : state.local? 4 = some (.signed .i32 memory.bytes.length)
  position : (Assertion.localPointsTo 6 memory.positionCell
    (some (.signed .i32 (memory.earlier.length + processed.length : Nat)))).holds state
  index : (Assertion.localPointsTo 7 memory.indexCell
    (some (.signed .i32 processed.length))).holds state
  stable : ∀ id, id ∈ [0, 1, 4, 5] →
    ∀ cell, state.cellId? id = some cell → ¬ memory.writes cell
  writtenFit : memory.earlier.length + processed.length ≤ memory.capacity

theorem advance (byte : CheckedByte program) (memory : Memory)
    (processed remaining : List UInt8) (value : UInt8) (before : State)
    (source : memory.bytes = processed ++ value :: remaining)
    (invariant : Invariant memory processed before)
    (available : memory.earlier.length + processed.length < memory.capacity) :
    ∃ after, Executes program.core before (step byte.source.function.id) .next after ∧
      Invariant memory (processed ++ [value]) after ∧
      CellEffect memory.writes before after ∧ HeapFrame before after := by
  have sourceLength : memory.bytes.length = processed.length + 1 + remaining.length := by
    simp [source]; omega
  have room : processed.length < memory.untouched.length := by
    have := memory.capacityBound; omega
  have length := Input.copiedBuffer_length memory.earlier memory.untouched processed (by omega)
  have selected : memory.storage[processed.length]? = some value := by
    have selected := congrArg (fun bytes : List UInt8 => bytes[processed.length]?) memory.sourceBytes
    have bound : processed.length < memory.bytes.length := by omega
    simpa [List.getElem?_take, bound, source] using selected
  obtain ⟨after, run, output, position, index, effect, heapFrame⟩ := stepSuccess byte memory.words memory.storage
    processed.length (memory.earlier.length + processed.length) memory.capacity value
    invariant.wellFormed available
    (by simpa only [Memory.output, length] using memory.capacityBound) memory.capacityFit
    (by have := memory.capacityFit; omega) invariant.inputLocal
    invariant.inputContents memory.encoded selected
    (by simpa only [Memory.output, length] using invariant.outputLocal)
    invariant.capacity invariant.position invariant.index memory.distinctLocals invariant.outputContents
  have updated := Input.copiedBuffer_step memory.earlier memory.untouched processed value room
  change (memory.output processed).set (memory.earlier.length + processed.length) value.toNat =
    memory.output (processed ++ [value]) at updated
  rw [updated] at output
  refine ⟨after, run, ?_, effect, heapFrame⟩
  refine ⟨effect.wellFormed, ?_, ?_, ?_, output, ?_, ?_, ?_, ?_, ?_, ?_⟩
  · exact effect.preserves_local invariant.wellFormed invariant.inputLocal
      (invariant.stable 5 (by simp))
  · exact effect.preserves_entry invariant.wellFormed invariant.inputContents (by
      simp [Memory.writes, writes, CellSet.union, CellSet.singleton,
        memory.inputOutput, memory.inputPosition, memory.inputIndex])
  · exact effect.preserves_local invariant.wellFormed invariant.outputLocal
      (invariant.stable 0 (by simp))
  · exact effect.preserves_local invariant.wellFormed invariant.capacity
      (invariant.stable 1 (by simp))
  · exact effect.preserves_local invariant.wellFormed invariant.length
      (invariant.stable 4 (by simp))
  · simpa [List.length_append, Nat.add_assoc] using position
  · simpa using index
  · intro id member cell found
    apply invariant.stable id member cell
    simpa [State.cellId?, effect.locals] using found
  · simp only [List.length_append, List.length_singleton]; omega

theorem conditionValue (program : Program) (memory : Memory) (processed : List UInt8)
    (invariant : Invariant memory processed before) :
    Evaluates program before condition
      (.boolean (!(Int.ofNat processed.length == Int.ofNat memory.bytes.length))) before := by
  apply evaluatesEagerBinary (by decide) (by decide)
    (local_evaluates program (Assertion.localPointsTo_local _ _ _ _ invariant.index))
    (local_evaluates program invariant.length)
  simp [evalBinaryValue, scalarEqual]

/-- Total correctness of the actual text-output loop on its supported
capacity domain. The remaining input bytes are a decreasing termination
measure; no per-iteration execution is assumed. -/
theorem executesLoop (byte : CheckedByte program) (memory : Memory)
    (processed remaining : List UInt8) (before : State)
    (source : memory.bytes = processed ++ remaining)
    (invariant : Invariant memory processed before)
    (room : memory.earlier.length + memory.bytes.length ≤ memory.capacity) :
    ∃ after, Executes program.core before (loop byte.source.function.id) .next after ∧
      Invariant memory memory.bytes after ∧ CellEffect memory.writes before after ∧ HeapFrame before after := by
  have condition := conditionValue program.core memory processed invariant
  cases remaining with
  | nil =>
      have complete : memory.bytes = processed := by simpa using source
      exact ⟨before, executesWhileFalse (by simpa [complete] using condition),
        by simpa [complete] using invariant, CellEffect.refl invariant.wellFormed, HeapFrame.refl _⟩
  | cons value rest =>
      have different : (Int.ofNat processed.length) ≠ Int.ofNat memory.bytes.length := by
        intro equal
        have equalLength := Int.ofNat.inj equal
        simp only [source, List.length_append, List.length_cons] at equalLength
        omega
      rw [beq_eq_false_iff_ne.mpr different] at condition
      obtain ⟨middle, body, nextInvariant, bodyEffect, bodyHeap⟩ :=
        advance byte memory processed rest value before source invariant
          (by simp only [source, List.length_append, List.length_cons] at room; omega)
      obtain ⟨after, restRun, completed, restEffect, restHeap⟩ :=
        executesLoop byte memory (processed ++ [value]) rest middle
          (by simpa [List.append_assoc] using source) nextInvariant room
      exact ⟨after, executesWhileTrue condition body restRun, completed, bodyEffect.trans restEffect,
        bodyHeap.trans restHeap⟩
termination_by remaining.length

/-- Execute the same loop on insufficient capacity, preserving exactly the
fitting prefix and stopping at its first rejected byte. -/
theorem executesOverflowLoop (byte : CheckedByte program) (memory : Memory)
    (processed remaining : List UInt8) (before : State)
    (source : memory.bytes = processed ++ remaining)
    (invariant : Invariant memory processed before)
    (overflow : memory.capacity < memory.earlier.length + memory.bytes.length) :
    ∃ after, Executes program.core before (loop byte.source.function.id)
        (.returned (some (.signed .i32 (-1)))) after ∧
      after.cellEntry? memory.outputCell = some {
        id := memory.outputCell, value := some (.array (signedI32Values
          (memory.output (emitted memory.bytes memory.earlier.length memory.capacity)))) } ∧
      CellEffect memory.writes before after ∧ HeapFrame before after := by
  have writtenFit := invariant.writtenFit
  cases remaining with
  | nil =>
      have length : memory.bytes.length = processed.length := by simp [source]
      omega
  | cons value rest =>
      have sourceLength : memory.bytes.length = processed.length + 1 + rest.length := by
        simp [source]; omega
      have condition := conditionValue program.core memory processed invariant
      have different : (Int.ofNat processed.length) ≠ Int.ofNat memory.bytes.length := by
        intro equal
        have := Int.ofNat.inj equal
        omega
      rw [beq_eq_false_iff_ne.mpr different] at condition
      by_cases available : memory.earlier.length + processed.length < memory.capacity
      · obtain ⟨middle, body, nextInvariant, bodyEffect, bodyHeap⟩ :=
          advance byte memory processed rest value before source invariant available
        obtain ⟨after, restRun, output, restEffect, restHeap⟩ :=
          executesOverflowLoop byte memory (processed ++ [value]) rest middle
            (by simpa [List.append_assoc] using source) nextInvariant overflow
        exact ⟨after, executesWhileTrueThen condition body restRun, output,
          bodyEffect.trans restEffect, bodyHeap.trans restHeap⟩
      · have full : memory.earlier.length + processed.length = memory.capacity := by omega
        have length := Input.copiedBuffer_length memory.earlier memory.untouched processed
          (by have := memory.capacityBound; omega)
        have selected : memory.storage[processed.length]? = some value := by
          have selected := congrArg (fun bytes : List UInt8 => bytes[processed.length]?) memory.sourceBytes
          have bound : processed.length < memory.bytes.length := by omega
          simpa [List.getElem?_take, bound, source] using selected
        obtain ⟨after, body, output, effect, heap⟩ := stepFull byte memory.words memory.storage
          processed.length memory.capacity value invariant.wellFormed
          (by have := memory.capacityFit; omega) invariant.inputLocal invariant.inputContents
          memory.encoded selected
          (by simpa only [Memory.output, length] using invariant.outputLocal)
          invariant.capacity (by simpa only [full] using invariant.position)
          invariant.index invariant.outputContents
        have emittedPrefix : emitted memory.bytes memory.earlier.length memory.capacity = processed := by
          have consumed : memory.capacity - memory.earlier.length = processed.length := by omega
          simp [emitted, consumed, source]
        exact ⟨after, executesWhileReturned condition body,
          by simpa only [emittedPrefix] using output,
          effect.weaken (by intro cell changed; exact Or.inl (Or.inr changed)), heap⟩
termination_by remaining.length

/-- The common loop-and-return boundary covers full success, an empty write,
and partial-output exhaustion. Neither outcome needs another initialization. -/
theorem executesLoopAndReturn (byte : CheckedByte program) (memory : Memory)
    (before : State) (invariant : Invariant memory [] before) :
    ∃ after, Executes program.core before
        (.sequence (loop byte.source.function.id) (returned (read 6)))
        (.returned (some (.signed .i32
          (finalPosition memory.bytes.length memory.earlier.length memory.capacity)))) after ∧
      after.cellEntry? memory.outputCell = some {
        id := memory.outputCell, value := some (.array (signedI32Values
          (memory.output (emitted memory.bytes memory.earlier.length memory.capacity)))) } ∧
      CellEffect memory.writes before after ∧ HeapFrame before after := by
  by_cases room : memory.earlier.length + memory.bytes.length ≤ memory.capacity
  · obtain ⟨after, run, completed, effect, heap⟩ := executesLoop byte memory [] memory.bytes before rfl invariant room
    refine ⟨after, ?_, ?_, effect, heap⟩
    · rw [finalPosition_of_fits room]
      exact executesSequence run (executesSequenceReturned
        (executesReturnValue (local_evaluates program.core
          (Assertion.localPointsTo_local _ _ _ _ completed.position))))
    · simpa only [emitted_of_fits room] using completed.outputContents
  · obtain ⟨after, run, output, effect, heap⟩ :=
      executesOverflowLoop byte memory [] memory.bytes before rfl invariant (by omega)
    exact ⟨after, by simpa only [finalPosition, if_neg room] using
      (executesSequenceReturned (second := returned (read 6)) run), output, effect, heap⟩

theorem preservesRegistry (memory : Memory) (processed emitted : List UInt8)
    (initial : Allocation.Registry before) (beforeInvariant : Invariant memory processed before)
    (emittedFit : memory.earlier.length + emitted.length ≤ memory.capacity)
    (outputContents : after.cellEntry? memory.outputCell = some {
      id := memory.outputCell, value := some (.array (signedI32Values (memory.output emitted))) })
    (effect : CellEffect memory.writes before after) (heapFrame : HeapFrame before after) :
    Allocation.Registry after := by
  apply initial.transport effect heapFrame
  intro view member changed
  rcases changed with changed | atIndex
  · rcases changed with atOutput | atPosition
    · change view.root = memory.outputCell at atOutput
      have original : before.cellEntry? view.root = some {
          id := view.root, value := some (.array (signedI32Values (memory.output processed))) } :=
        atOutput.symm ▸ beforeInvariant.outputContents
      have beforeLength := Input.copiedBuffer_length memory.earlier memory.untouched processed
        (by have := beforeInvariant.writtenFit; have := memory.capacityBound; omega)
      have afterLength := Input.copiedBuffer_length memory.earlier memory.untouched emitted
        (by have := memory.capacityBound; omega)
      refine ⟨signedI32Values (memory.output emitted), ?_, ?_, ?_⟩
      · simp [readCellProjection, initial.roots view member, atOutput,
          outputContents, projectedValue]
      · simpa only [signedI32Values, List.length_map, Memory.output, beforeLength, afterLength] using
          initial.arrayLength member original
      · intro element present
        obtain ⟨value, _, rfl⟩ := List.mem_map.mp present
        exact ⟨value, rfl⟩
    · change view.root = memory.positionCell at atPosition
      exact False.elim (initial.notScalar member (atPosition.symm ▸ beforeInvariant.position.2))
  · change view.root = memory.indexCell at atIndex
    exact False.elim (initial.notScalar member (atIndex.symm ▸ beforeInvariant.index.2))

end Lanius.Extraction.CompactOutput.Text
