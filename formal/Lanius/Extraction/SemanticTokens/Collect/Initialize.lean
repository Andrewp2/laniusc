import Lanius.Extraction.SemanticTokens.Collect.Source
import Lanius.Extraction.BufferCopy.Loop
import Lanius.Separation.SliceStore

namespace Lanius.Extraction.SemanticTokens.Collect

open Lanius Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation

def initialized (original : List Int) (position : Nat) : List Int :=
  BufferCopy.buffer original (List.replicate position (-1))

theorem initialized_length (bound : position ≤ original.length) :
    (initialized original position).length = original.length := by
  apply BufferCopy.buffer_length
  simpa only [List.length_replicate] using bound

theorem initialized_step (bound : position < original.length) :
    (initialized original position).set position (-1) = initialized original (position + 1) := by
  have step := BufferCopy.buffer_step original (List.replicate position (-1)) (-1)
    (by simpa only [List.length_replicate] using bound)
  simpa only [initialized, List.length_replicate, List.replicate_succ'] using step

structure InitializeMemory where
  outputCell : CellId
  cursorCell : CellId
  original : List Int
  count : Nat
  capacity : count * 2 ≤ original.length
  bounded : count * 2 ≤ 2147483647
  distinct : outputCell ≠ cursorCell

def InitializeMemory.writes (memory : InitializeMemory) : CellSet :=
  CellSet.union (CellSet.singleton memory.outputCell) (CellSet.singleton memory.cursorCell)

structure InitializeInvariant (memory : InitializeMemory) (position : Nat) (state : State) : Prop where
  wellFormed : StateWellFormed state
  outputLocal : state.local? 8 = some (.slice i32 memory.outputCell [] 0 memory.original.length)
  contents : state.cellEntry? memory.outputCell = some {
    id := memory.outputCell, value := some (.array (signedI32Values (initialized memory.original position))) }
  cursor : (Assertion.localPointsTo 12 memory.cursorCell (some (.signed .i32 position))).holds state
  count : state.local? 3 = some (.signed .i32 memory.count)
  stable : ∀ localId, localId ∈ [8, 3] → ∀ cell, state.cellId? localId = some cell → ¬ memory.writes cell

theorem negativeOne_evaluates (program : Program) (before : State) :
    Evaluates program before (negative 1) (.signed .i32 (-1)) before := by
  apply evaluatesUnary (show Evaluates program before (number 1) (.signed .i32 1) before from ⟨1, rfl⟩)
  simp [evalUnaryValue, wrapSigned, signedModulus, signedSignBit, SignedIntTy.bits]

theorem initialize_step (program : Program) (memory : InitializeMemory)
    (invariant : InitializeInvariant memory position before) (active : position < memory.count * 2) :
    ∃ after, Executes program before initializeBody .next after ∧
      InitializeInvariant memory (position + 1) after ∧ CellEffect memory.writes before after := by
  have room : position < memory.original.length := Nat.lt_of_lt_of_le active memory.capacity
  have lengthEq := initialized_length (Nat.le_of_lt room)
  have indexResult : Evaluates program before (read 12) (.signed .i32 position) before :=
    ⟨1, evalLocal_of_local 0 program before 12 _ (Assertion.localPointsTo_local _ _ _ _ invariant.cursor)⟩
  obtain ⟨written, assigned, contents, writeEffect⟩ := evaluatesSliceStore program before before
    (initialized memory.original position) 8 (read 12) (negative 1) memory.outputCell position (-1)
    invariant.wellFormed (by simpa only [lengthEq] using room)
    (by simpa only [lengthEq] using invariant.outputLocal) indexResult
    (negativeOne_evaluates program before) (CellEffect.refl invariant.wellFormed) invariant.contents
  rw [initialized_step room] at contents
  have cursorStill := writeEffect.preserves_localPointsTo invariant.wellFormed invariant.cursor
    (by simpa only [CellSet.singleton, eq_comm] using memory.distinct)
  obtain ⟨after, incremented, afterWF, cursorAfter, incrementEffect⟩ := executesIncrementOwnedI32Local
    program written 12 memory.cursorCell position writeEffect.wellFormed cursorStill
    (by have := memory.bounded; omega)
  have effect : CellEffect memory.writes before after :=
    (writeEffect.weaken CellSet.subset_union_left).trans
      ((CellEffect.ofModifiesOnly incrementEffect afterWF).weaken CellSet.subset_union_right)
  refine ⟨after, executesSequence (executesExpression assigned) incremented, ?_, effect⟩
  refine ⟨afterWF, ?_, ?_, cursorAfter, ?_, ?_⟩
  · exact effect.preserves_local invariant.wellFormed invariant.outputLocal (invariant.stable _ (by simp))
  · exact incrementEffect.preserves_entry writeEffect.wellFormed contents memory.distinct
  · exact effect.preserves_local invariant.wellFormed invariant.count (invariant.stable _ (by simp))
  · intro localId member cell found
    apply invariant.stable localId member cell
    simpa only [State.cellId?, effect.locals] using found

/-- Terminate the actual initialization loop, retaining its exact write
footprint. A sufficient output capacity is derived before entering this loop;
the theorem does not assume that any iteration has already executed. -/
theorem initialize_loop (program : Program) (memory : InitializeMemory)
    (invariant : InitializeInvariant memory position before) (bound : position ≤ memory.count * 2) :
    ∃ after, Executes program before initializeLoop .next after ∧
      InitializeInvariant memory (memory.count * 2) after ∧ CellEffect memory.writes before after := by
  have cursorResult : Evaluates program before (read 12) (.signed .i32 position) before :=
    ⟨1, evalLocal_of_local 0 program before 12 _ (Assertion.localPointsTo_local _ _ _ _ invariant.cursor)⟩
  have countResult : Evaluates program before (read 3) (.signed .i32 memory.count) before :=
    ⟨1, evalLocal_of_local 0 program before 3 _ invariant.count⟩
  have limitResult := evaluatesNatI32Multiply countResult
    (show Evaluates program before (number 2) (.signed .i32 2) before from ⟨1, rfl⟩) memory.bounded
  have condition : Evaluates program before initializeCondition
      (.boolean (!(Int.ofNat position == Int.ofNat (memory.count * 2)))) before := by
    apply evaluatesEagerBinary (by decide) (by decide) cursorResult limitResult
    simp [evalBinaryValue, scalarEqual]
  by_cases complete : position = memory.count * 2
  · subst position
    exact ⟨before, executesWhileFalse (by simpa using condition), invariant, CellEffect.refl invariant.wellFormed⟩
  · have active : position < memory.count * 2 := by omega
    have conditionTrue : Evaluates program before initializeCondition (.boolean true) before := by
      simpa only [Bool.not_false, show (Int.ofNat position == Int.ofNat (memory.count * 2)) = false from
        beq_eq_false_iff_ne.mpr (by intro same; exact complete (Int.ofNat.inj same))] using condition
    obtain ⟨middle, stepped, next, stepEffect⟩ := initialize_step program memory invariant active
    obtain ⟨after, finished, final, restEffect⟩ := initialize_loop program memory next (by omega)
    exact ⟨after, executesWhileTrue conditionTrue stepped finished, final, stepEffect.trans restEffect⟩
termination_by memory.count * 2 - position

theorem InitializeInvariant.finished {memory : InitializeMemory}
    (invariant : InitializeInvariant memory (memory.count * 2) state) :
    state.cellEntry? memory.outputCell = some {
      id := memory.outputCell,
      value := some (.array (signedI32Values (List.replicate (memory.count * 2) (-1) ++
        memory.original.drop (memory.count * 2)))) } := by
  simpa only [initialized, BufferCopy.buffer, List.length_replicate] using invariant.contents

end Lanius.Extraction.SemanticTokens.Collect
