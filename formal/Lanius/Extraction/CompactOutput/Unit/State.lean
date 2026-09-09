import Lanius.Extraction.CompactOutput.Unit.Chunks
import Lanius.Extraction.CompactOutput.Unit.Source
import Lanius.Extraction.CompactOutput.Byte
import Lanius.Separation.LocalCall
import Lanius.Separation.I32Prefix

namespace Lanius.Extraction.CompactOutput.Unit

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation

/-- Fixed state immediately after the unit emitter's cursor declaration.
Later calls retain a frame back to this state instead of duplicating every
input-buffer invariant at each call site. -/
structure Memory where
  base : State
  outputCell : CellId
  cursorCell : CellId
  initialPosition : Int
  initialContents : List Int
  wellFormed : StateWellFormed base
  cursor : (Assertion.localPointsTo 19 cursorCell (some (.signed .i32 initialPosition))).holds base
  backing : base.cellEntry? outputCell = some {
    id := outputCell, value := some (.array (signedI32Values initialContents)) }
  stable : ∀ id, id ≠ 19 → ∀ cell, base.cellId? id = some cell → cell ≠ cursorCell

def Memory.writes (memory : Memory) : CellSet :=
  CellSet.union (CellSet.singleton memory.outputCell) (CellSet.singleton memory.cursorCell)

structure Owned (memory : Memory) (position : Int) (contents : List Int) (state : State) : Prop where
  frame : CellEffect memory.writes memory.base state
  cursor : (Assertion.localPointsTo 19 memory.cursorCell (some (.signed .i32 position))).holds state
  backing : state.cellEntry? memory.outputCell = some {
    id := memory.outputCell, value := some (.array (signedI32Values contents)) }
  length : contents.length = memory.initialContents.length

theorem Memory.owned (memory : Memory) : Owned memory memory.initialPosition memory.initialContents memory.base :=
  ⟨CellEffect.refl memory.wellFormed, memory.cursor, memory.backing, rfl⟩

theorem Owned.local (owned : Owned memory position contents state) {id : VarId} {value : Value}
    (notCursor : id ≠ 19) (found : memory.base.local? id = some value)
    (notArray : value ≠ .array (signedI32Values memory.initialContents)) : state.local? id = some value := by
  apply owned.frame.preserves_local memory.wellFormed found
  intro cell binding changed
  rcases changed with output | cursor
  · exact local_cell_ne_of_distinct_value found memory.backing notArray binding output
  · exact memory.stable id notCursor cell binding cursor

theorem Owned.input (owned : Owned memory position contents state)
    (input : I32Prefix memory.base cell physicalCapacity values)
    (separate : memory.outputCell ≠ cell) : I32Prefix state cell physicalCapacity values := by
  obtain ⟨unused, size, backing⟩ := input
  refine ⟨unused, size, owned.frame.preserves_entry memory.wellFormed backing ?_⟩
  intro changed
  rcases changed with output | cursor
  · exact separate output.symm
  · rw [cursor, memory.cursor.2] at backing
    cases backing

/-- Compose a proved serializer call with the actual `next = call(...)`.
The RHS execution is supplied by that serializer's public-call theorem. -/
theorem Owned.assign {result : Int} (owned : Owned memory position contents before)
    (callRun : Evaluates program before call (.signed .i32 result) written)
    (callEffect : CellEffect (CellSet.singleton memory.outputCell) before written)
    (output : written.cellEntry? memory.outputCell = some {
      id := memory.outputCell, value := some (.array (signedI32Values updated)) })
    (size : updated.length = contents.length) :
    ∃ after, Evaluates program before (.assign .set (.local 19) call) .unit after ∧
      Owned memory result updated after ∧ CellEffect memory.writes before after := by
  have distinct : memory.outputCell ≠ memory.cursorCell := by
    intro same
    have backing := owned.backing
    rw [same, owned.cursor.2] at backing
    cases backing
  have cursorWritten := callEffect.preserves_localPointsTo owned.frame.wellFormed owned.cursor
    (by simpa only [CellSet.singleton] using Ne.symm distinct)
  obtain ⟨after, run, cursor, effect, assignmentEffect⟩ := evaluatesOwnedLocalSet owned.cursor callRun callEffect cursorWritten
  have backing := assignmentEffect.preserves_entry callEffect.wellFormed output
    (by simpa only [CellSet.singleton] using distinct)
  exact ⟨after, run, ⟨owned.frame.trans effect, cursor, backing, size.trans owned.length⟩, effect⟩

end Lanius.Extraction.CompactOutput.Unit
