import Lanius.Extraction.WriterCursor
import Lanius.Semantics.LocalPair

namespace Lanius.Extraction

open Lanius.Core Lanius.Semantics

/-- A bounded printer loop's fresh cursor/counter cells and accumulated output.
    The counter is retained through writer calls; neither cell belongs to the caller. -/
structure WriterCounter (base current : State) (cursor counter : VarId) (address position : Nat)
    (bytes : List UInt8) (index : Nat) : Prop extends
    LocalPair base current cursor counter (.signed .i32 (position + bytes.length : Nat)) (.signed .i32 index) where
  frame : WriterFrame base current address bytes

namespace WriterCounter

variable {base before ready : State} {cursor counter : VarId} {address position index : Nat}
  {front suffix : List UInt8}

theorem toCursor (current : WriterCounter base before cursor counter address position front index) :
    WriterCursor base before cursor base.nextCell address position front
      (scope := [(counter, base.nextCell + 1)]) :=
  ⟨current.frame, Nat.le_refl _, current.firstCell, current.first, current.locals⟩

theorem start (formed : base.CellsWellFormed) (unique : Memory.HeapBlockBasesUnique base.heap)
    (different : cursor ≠ counter) :
    WriterCounter base ((base.bindLocal cursor (.signed .i32 position)).bindLocal counter (.signed .i32 0))
      cursor counter address position [] 0 := by
  let pair := LocalPair.start (first := .signed .i32 position) (second := .signed .i32 0) formed different
  exact ⟨pair, ⟨.write (Memory.BytesWrite.refl unique), pair.cells, rfl, rfl⟩⟩

/-- A checked writer and its cursor store retain the counter and input frame. -/
theorem advance (current : WriterCounter base before cursor counter address position front index)
    (formed : base.CellsWellFormed)
    (run : RunsExpr program before expression (.signed .i32 (position + (front ++ suffix).length : Nat)) ready)
    (written : WriterFrame before ready (address + front.length) suffix) :
    ∃ after, RunsExpr program before (.assign .set (.local cursor) expression) .unit after ∧
      WriterCounter base after cursor counter address position (front ++ suffix) index := by
  obtain ⟨after, run, next, kept⟩ := current.toCursor.advanceKeeping formed run written
  refine ⟨after, run, ⟨⟨next.frame.cells, current.different, next.locals, next.value, ?_⟩, next.frame⟩⟩
  exact kept counter _ current.second (by rw [current.secondCell]; simp)

/-- Increment only the fresh loop counter, retaining cursor, output and caller. -/
theorem increment (current : WriterCounter base before cursor counter address position front index)
    (formed : base.CellsWellFormed) (fits : index + 1 < 2 ^ 31) :
    ∃ after, RunsExpr program before (.assign .add (.local counter) (.value (.signed .i32 1))) .unit after ∧
      WriterCounter base after cursor counter address position front (index + 1) := by
  obtain ⟨after, run, assigned, effect⟩ := RunsExpr.assignI32
    (op := .add) (replacement := (index + 1 : Nat)) current.secondCell current.second (.ofStable .value rfl) (by
      simpa only [evalAssignValue, assignOpBinary?, Int.natCast_add, Int.natCast_one] using
        eval_i32_addNat program.target index 1 fits)
  let pair := current.toLocalPair.assignSecond formed assigned
  exact ⟨after, run, ⟨pair, ⟨by simpa only [effect.heap] using current.frame.output, pair.cells,
    effect.world.trans current.frame.world, effect.views.trans current.frame.views⟩⟩⟩

end WriterCounter
end Lanius.Extraction
