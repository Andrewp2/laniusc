import Lanius.Semantics.Stable

namespace Lanius.Semantics

open Lanius.Core

/-! An internal frame for calls that may mutate cells allocated after entry.
The caller's cells remain an exact prefix; heap-backed data and effects are
read-only.  Restoring locals turns this into the public `PureFrame`. -/

private theorem replaceCell_append_of_fresh
    (prefixCells suffix : List Cell) (frontier id : CellId) (value : Value)
    (formed : ∀ cell ∈ prefixCells, cell.id < frontier) (fresh : frontier ≤ id) :
    replaceCell (prefixCells ++ suffix) id value =
      prefixCells ++ replaceCell suffix id value := by
  induction prefixCells with
  | nil => rfl
  | cons cell rest induction =>
      have cellNe : cell.id ≠ id :=
        Nat.ne_of_lt (Nat.lt_of_lt_of_le (formed cell (by simp)) fresh)
      simp only [List.cons_append, replaceCell]
      simp [cellNe, induction (fun item member => formed item (by simp [member]))]

private theorem replaceCell_preserves_bounds
    (cells : List Cell) (id : CellId) (value : Value) (lower upper : CellId)
    (bounded : ∀ cell ∈ cells, lower ≤ cell.id ∧ cell.id < upper) :
    ∀ cell ∈ replaceCell cells id value,
      lower ≤ cell.id ∧ cell.id < upper := by
  induction cells with
  | nil => simp [replaceCell]
  | cons head tail induction =>
      intro cell member
      simp only [replaceCell] at member
      have recurse : ∀ item ∈ replaceCell tail id value,
          lower ≤ item.id ∧ item.id < upper :=
        induction (fun item inside => bounded item (by simp [inside]))
      split at member
      · rcases List.mem_cons.mp member with rfl | member
        · exact bounded head (by simp)
        · exact recurse cell member
      · rcases List.mem_cons.mp member with rfl | member
        · exact bounded cell (by simp)
        · exact recurse cell member

/-- State internal to a pure call. Locals and fresh cells may change, but the
caller's cell prefix and all externally observable stores are preserved. -/
structure CallerFrame (caller current : State) : Prop where
  callerFormed : caller.CellsWellFormed
  cells : FreshCellFrame caller current
  heap : current.heap = caller.heap
  world : current.world = caller.world
  views : current.i32ArrayViews = caller.i32ArrayViews

theorem CallerFrame.refl (formed : state.CellsWellFormed) :
    CallerFrame state state :=
  ⟨formed, ⟨[], by simp, Nat.le_refl _, by simp⟩, rfl, rfl, rfl⟩

theorem CallerFrame.currentFormed
    (frame : CallerFrame caller current) : current.CellsWellFormed :=
  frame.cells.after_cellsWellFormed frame.callerFormed

theorem CallerFrame.transPure
    (frame : CallerFrame caller current) (pure : PureFrame current after) :
    CallerFrame caller after :=
  ⟨frame.callerFormed, frame.cells.trans pure.cells, pure.heap.trans frame.heap,
    pure.world.trans frame.world, pure.views.trans frame.views⟩

theorem CallerFrame.trans
    (left : CallerFrame before middle) (right : CallerFrame middle after) :
    CallerFrame before after :=
  ⟨left.callerFormed, left.cells.trans right.cells, right.heap.trans left.heap,
    right.world.trans left.world, right.views.trans left.views⟩

theorem CallerFrame.bindLocal (frame : CallerFrame caller current)
    (id : VarId) (value : Value) :
    CallerFrame caller (current.bindLocal id value) :=
  ⟨frame.callerFormed, frame.cells.trans (FreshCellFrame.bindLocal current id value),
    frame.heap, frame.world, frame.views⟩

theorem CallerFrame.bindLocals (frame : CallerFrame caller current)
    (bindings : List (VarId × Value)) :
    CallerFrame caller (current.bindLocals bindings) := by
  induction bindings generalizing current with
  | nil => simpa [State.bindLocals] using frame
  | cons binding rest induction =>
      simp only [State.bindLocals, List.foldl_cons]
      exact induction (frame.bindLocal binding.1 binding.2)

theorem CallerFrame.assignCellFresh
    (frame : CallerFrame caller current) (cell : CellId) (value : Value)
    (fresh : caller.nextCell ≤ cell)
    (assigned : current.assignCell cell value = some after) :
    CallerFrame caller after := by
  rcases frame.cells with ⟨extra, cells, frontier, bounded⟩
  unfold State.assignCell at assigned
  split at assigned
  · simp only [Option.some.injEq] at assigned
    subst after
    refine
      { callerFormed := frame.callerFormed
        cells := ⟨replaceCell extra cell value, ?_, frontier, ?_⟩
        heap := frame.heap
        world := frame.world
        views := frame.views }
    · change replaceCell current.cells cell value =
        caller.cells ++ replaceCell extra cell value
      rw [cells]
      exact replaceCell_append_of_fresh caller.cells extra caller.nextCell cell value
        frame.callerFormed fresh
    · exact replaceCell_preserves_bounds extra cell value caller.nextCell
        current.nextCell bounded
  · contradiction

theorem CallerFrame.assignLocalFresh
    (frame : CallerFrame caller current) (id : VarId) (cell : CellId)
    (value : Value) (localCell : current.cellId? id = some cell)
    (fresh : caller.nextCell ≤ cell)
    (assigned : current.assignLocal id value = some after) :
    CallerFrame caller after := by
  unfold State.assignLocal at assigned
  simp only [localCell, Option.bind_some] at assigned
  exact frame.assignCellFresh cell value fresh assigned

theorem CallerFrame.restoreLocals
    (frame : CallerFrame caller current) :
    PureFrame caller (restoreLocals caller current) :=
  ⟨frame.callerFormed, frame.cells.restoreLocals, rfl, frame.heap, frame.world,
    frame.views⟩

end Lanius.Semantics
