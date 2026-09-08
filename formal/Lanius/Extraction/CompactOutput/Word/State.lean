import Lanius.Extraction.CompactOutput.Word.Source
import Lanius.Extraction.CompactOutput.Sequence
import Lanius.Extraction.CompactOutput.Bits
import Lanius.Separation.LocalStore
import Lanius.Separation.LocalCall

namespace Lanius.Extraction.CompactOutput.Word

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation

def bitPosition (remaining : Nat) : Int := (remaining : Int) * 4 - 4

theorem bitPosition_succ (remaining : Nat) : bitPosition (remaining + 1) = (remaining * 4 : Nat) := by
  simp only [bitPosition, Int.natCast_add, Int.natCast_mul, Int.natCast_one]
  omega

structure Memory where
  outputCell : CellId
  cursorCell : CellId
  shiftCell : CellId
  capacity : Nat
  value : Nat
  capacityFit : capacity ≤ 2147483647
  valueFit : value ≤ 2147483647
  distinct : cursorCell ≠ shiftCell

def Memory.writes (memory : Memory) : CellSet :=
  CellSet.union (CellSet.union (CellSet.singleton memory.outputCell) (CellSet.singleton memory.cursorCell))
    (CellSet.singleton memory.shiftCell)

structure Owned (memory : Memory) (remaining : Nat) (position : Int) (contents : List Int) (state : State) : Prop where
  wellFormed : StateWellFormed state
  room : memory.capacity ≤ contents.length
  output : state.local? 0 = some (.slice i32 memory.outputCell [] 0 contents.length)
  backing : state.cellEntry? memory.outputCell = some {
    id := memory.outputCell, value := some (.array (signedI32Values contents)) }
  capacity : state.local? 1 = some (.signed .i32 memory.capacity)
  value : state.local? 3 = some (.signed .i32 memory.value)
  cursor : (Assertion.localPointsTo 4 memory.cursorCell (some (.signed .i32 position))).holds state
  shift : (Assertion.localPointsTo 5 memory.shiftCell (some (.signed .i32 (bitPosition remaining)))).holds state
  stable : ∀ id ∈ [0, 1, 3], ∀ cell, state.cellId? id = some cell → cell ≠ memory.cursorCell ∧ cell ≠ memory.shiftCell

theorem Owned.output_cursor (owned : Owned memory remaining position contents state) : memory.outputCell ≠ memory.cursorCell := by
  intro same
  have backing := owned.backing
  rw [same, owned.cursor.2] at backing
  cases backing

theorem Owned.output_shift (owned : Owned memory remaining position contents state) : memory.outputCell ≠ memory.shiftCell := by
  intro same
  have backing := owned.backing
  rw [same, owned.shift.2] at backing
  cases backing

/-- Reuse the invariant after an update, supplying only the changed storage
and loop locals. Stable argument cells are derived from the original frame. -/
theorem Owned.transition {nextPosition : Int} {nextRemaining : Nat}
    (owned : Owned memory remaining position contents before)
    (effect : CellEffect memory.writes before after)
    (length : updated.length = contents.length)
    (backing : after.cellEntry? memory.outputCell = some {
      id := memory.outputCell, value := some (.array (signedI32Values updated)) })
    (cursor : (Assertion.localPointsTo 4 memory.cursorCell (some (.signed .i32 nextPosition))).holds after)
    (shift : (Assertion.localPointsTo 5 memory.shiftCell (some (.signed .i32 (bitPosition nextRemaining)))).holds after) :
    Owned memory nextRemaining nextPosition updated after := by
  have keep {id : VarId} {value : Value} (member : id ∈ [0, 1, 3]) (found : before.local? id = some value)
      (different : value ≠ .array (signedI32Values contents)) : after.local? id = some value := by
    apply effect.preserves_local owned.wellFormed found
    intro cell binding changed
    rcases changed with (output | next) | shift
    · exact local_cell_ne_of_distinct_value found owned.backing different binding output
    · exact (owned.stable id member cell binding).1 next
    · exact (owned.stable id member cell binding).2 shift
  refine ⟨effect.wellFormed, by rw [length]; exact owned.room, ?_, backing,
    keep (by simp) owned.capacity (by intro same; cases same),
    keep (by simp) owned.value (by intro same; cases same), cursor, shift, ?_⟩
  · simpa only [length] using keep (by simp) owned.output (by intro same; cases same)
  · intro id member cell binding
    exact owned.stable id member cell (by simpa only [State.cellId?, effect.locals] using binding)

theorem decrement_value (target : Target) (remaining : Nat) (bounded : remaining ≤ 8) :
    evalAssignValue target .subtract (some (.signed .i32 (bitPosition (remaining + 1)))) (.signed .i32 4) =
      .ok (.signed .i32 (bitPosition remaining)) := by
  have subtraction : bitPosition (remaining + 1) - 4 = bitPosition remaining := by
    simp only [bitPosition, Int.natCast_add, Int.natCast_one]
    omega
  have wrapped : wrapSigned target .i32 (bitPosition remaining) = bitPosition remaining := by
    cases remaining with
    | zero => simp [bitPosition, wrapSigned, signedModulus, signedSignBit, SignedIntTy.bits]
    | succ remaining =>
      rw [bitPosition_succ]
      exact wrapSigned_i32_ofNat target (remaining * 4) (by omega)
  simp only [evalAssignValue, assignOpBinary?, evalBinaryValue, beq_self_eq_true, if_true, evalSignedBinary]
  rw [subtraction, wrapped]

end Lanius.Extraction.CompactOutput.Word
