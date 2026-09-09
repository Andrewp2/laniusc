import Lanius.Extraction.CompactOutput.Bytes.Step
import Lanius.Extraction.CompactOutput.Chunks

namespace Lanius.Extraction.CompactOutput.Bytes

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation

structure Memory where
  inputCell : CellId
  outputCell : CellId
  cursorCell : CellId
  indexCell : CellId
  values : List Nat
  capacity : Nat
  capacityFit : capacity ≤ 2147483647
  lengthFit : values.length ≤ 2147483647
  byteBound : ∀ value ∈ values, value < 256
  distinctLocals : cursorCell ≠ indexCell
  distinctBuffers : outputCell ≠ inputCell

def Memory.writes (memory : Memory) : CellSet :=
  CellSet.union (CellSet.union (CellSet.singleton memory.outputCell) (CellSet.singleton memory.cursorCell))
    (CellSet.singleton memory.indexCell)

structure Owned (memory : Memory) (index : Nat) (position : Int) (contents : List Int) (state : State) : Prop where
  wellFormed : StateWellFormed state
  bound : index ≤ memory.values.length
  room : memory.capacity ≤ contents.length
  input : I32PrefixLocal state 0 memory.inputCell (memory.values.map Int.ofNat)
  length : state.local? 1 = some (.signed .i32 memory.values.length)
  output : state.local? 2 = some (.slice i32 memory.outputCell [] 0 contents.length)
  capacity : state.local? 3 = some (.signed .i32 memory.capacity)
  backing : state.cellEntry? memory.outputCell = some {
    id := memory.outputCell, value := some (.array (signedI32Values contents)) }
  cursor : (Assertion.localPointsTo 5 memory.cursorCell (some (.signed .i32 position))).holds state
  indexOwned : (Assertion.localPointsTo 6 memory.indexCell (some (.signed .i32 index))).holds state
  stable : ∀ id ∈ [0, 1, 2, 3], ∀ cell, state.cellId? id = some cell →
    cell ≠ memory.cursorCell ∧ cell ≠ memory.indexCell

theorem Owned.output_index (owned : Owned memory index position contents state) : memory.outputCell ≠ memory.indexCell := by
  intro same
  have backing := owned.backing
  rw [same, owned.indexOwned.2] at backing
  cases backing

theorem Owned.input_index (owned : Owned memory index position contents state) : memory.inputCell ≠ memory.indexCell := by
  intro same
  obtain ⟨unused, _, backing⟩ := owned.input.exists_unused
  rw [same, owned.indexOwned.2] at backing
  cases backing

theorem Owned.transition {nextIndex : Nat} {nextCursor : Int}
    (owned : Owned memory index position contents before)
    (effect : CellEffect memory.writes before after)
    (bound : nextIndex ≤ memory.values.length) (size : updated.length = contents.length)
    (input : I32PrefixLocal after 0 memory.inputCell (memory.values.map Int.ofNat))
    (backing : after.cellEntry? memory.outputCell = some {
      id := memory.outputCell, value := some (.array (signedI32Values updated)) })
    (cursor : (Assertion.localPointsTo 5 memory.cursorCell (some (.signed .i32 nextCursor))).holds after)
    (indexOwned : (Assertion.localPointsTo 6 memory.indexCell (some (.signed .i32 nextIndex))).holds after) :
    Owned memory nextIndex nextCursor updated after := by
  have keep {id : VarId} {value : Value} (member : id ∈ [0, 1, 2, 3])
      (found : before.local? id = some value) (different : value ≠ .array (signedI32Values contents)) :
      after.local? id = some value := by
    apply effect.preserves_local owned.wellFormed found
    intro cell binding changed
    rcases changed with (output | cursor) | index
    · exact local_cell_ne_of_distinct_value found owned.backing different binding output
    · exact (owned.stable id member cell binding).1 cursor
    · exact (owned.stable id member cell binding).2 index
  refine ⟨effect.wellFormed, bound, by rw [size]; exact owned.room, input,
    keep (by simp) owned.length (by intro same; cases same), ?_,
    keep (by simp) owned.capacity (by intro same; cases same), backing, cursor, indexOwned, ?_⟩
  · simpa only [size] using keep (by simp) owned.output (by intro same; cases same)
  · intro id member cell binding
    exact owned.stable id member cell (by simpa only [State.cellId?, effect.locals] using binding)

theorem Owned.append (owned : Owned memory index position contents before)
    (hex : CheckedHexByte program byte digit) (bound : index < memory.values.length) :
    ∃ after, Evaluates program.core before (assignment hex.source.function.id) .unit after ∧
      Owned memory index (hexBytePosition memory.capacity position)
        (hexByteOutput contents memory.capacity position memory.values[index]) after ∧
      CellEffect memory.writes before after := by
  obtain ⟨after, run, cursor, indexOwned, input, backing, effect⟩ := assign_byte hex memory.values index
    memory.capacity position owned.wellFormed owned.input bound
    (memory.byteBound _ (List.getElem_mem bound)) owned.indexOwned owned.cursor memory.distinctLocals
    memory.distinctBuffers (fun cell binding => (owned.stable 0 (by simp) cell binding).1)
    owned.output owned.capacity owned.room memory.capacityFit owned.backing
  have combined : CellEffect memory.writes before after := effect.weaken CellSet.subset_union_left
  exact ⟨after, run, owned.transition combined owned.bound hexByteOutput_length input backing cursor indexOwned, combined⟩

theorem Owned.increment (owned : Owned memory index position contents before)
    (program : Program) (bound : index < memory.values.length) :
    ∃ after, Evaluates program before increment .unit after ∧
      Owned memory (index + 1) position contents after ∧ CellEffect memory.writes before after := by
  obtain ⟨after, run, wellFormed, indexOwned, modifies⟩ := evaluatesIncrementOwnedI32Local
    program before 6 memory.indexCell index owned.wellFormed owned.indexOwned (by have := memory.lengthFit; omega)
  have effect := CellEffect.ofModifiesOnly modifies wellFormed
  have cursor := effect.preserves_localPointsTo owned.wellFormed owned.cursor
    (by simpa only [CellSet.singleton] using memory.distinctLocals)
  have backing := effect.preserves_entry owned.wellFormed owned.backing
    (by simpa only [CellSet.singleton] using owned.output_index)
  have input := owned.input.preserved (fun value found => effect.preserves_local owned.wellFormed found
    (fun cell binding changed => (owned.stable 0 (by simp) cell binding).2 changed))
    owned.wellFormed effect (by simpa only [CellSet.singleton] using owned.input_index)
  have combined : CellEffect memory.writes before after := effect.weaken CellSet.subset_union_right
  exact ⟨after, run, owned.transition combined (by omega) rfl input backing cursor indexOwned, combined⟩

theorem Owned.condition (owned : Owned memory index position contents state) (program : Program) :
    Evaluates program state condition (.boolean (decide (index ≠ memory.values.length))) state := by
  apply evaluatesEagerBinary (by decide) (by decide)
    (local_evaluates program (Assertion.localPointsTo_local _ _ _ _ owned.indexOwned))
    (local_evaluates program owned.length)
  simp only [evalBinaryValue, scalarEqual, beq_self_eq_true, if_true,
    Except.ok.injEq, Value.boolean.injEq, decide_not]
  apply Bool.eq_iff_iff.mpr
  simp [Int.ofNat_inj]

theorem Owned.failureGuard (owned : Owned memory index position contents state) (program : Program) :
    Evaluates program state failureGuard (.boolean (decide (position < 0))) state := by
  apply evaluatesEagerBinary (by decide) (by decide)
    (local_evaluates program (Assertion.localPointsTo_local _ _ _ _ owned.cursor)) (negativeOne_evaluates program state)
  simp only [evalBinaryValue, evalSignedBinary, beq_self_eq_true, if_true, Except.ok.injEq,
    Value.boolean.injEq, decide_eq_decide]
  omega

end Lanius.Extraction.CompactOutput.Bytes
