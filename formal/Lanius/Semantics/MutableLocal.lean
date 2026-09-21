import Lanius.Semantics.CallerFrame
import Lanius.Semantics.Loop
import Lanius.Semantics.ReadOnlySlice

namespace Lanius.Semantics

open Lanius
open Lanius.Core

/-! Facts for the fresh cell introduced by `bindLocal`. -/

theorem State.bindLocal_cellId
    (state : State) (id : VarId) (value : Value) :
    (state.bindLocal id value).cellId? id = some state.nextCell := by
  simp [State.bindLocal, State.bindCell, State.cellId?]

theorem State.bindLocal_local?
    (state : State) (formed : state.CellsWellFormed)
    (id : VarId) (value : Value) :
    (state.bindLocal id value).local? id = some value :=
  formed.bindLocal_local id value

theorem State.bindLocal_cellId_of_ne
    (state : State) (oldId newId : VarId) (different : newId ≠ oldId)
    (newValue : Value) :
    (state.bindLocal newId newValue).cellId? oldId = state.cellId? oldId := by
  simp [State.bindLocal, State.bindCell, State.cellId?, different]

private theorem State.bindLocal_cellEntry_of_lt
    (state : State) (newId : VarId) (newValue : Value)
    {cell : CellId} (bound : cell < state.nextCell) :
    (state.bindLocal newId newValue).cellEntry? cell = state.cellEntry? cell := by
  simp [State.bindLocal, State.bindCell, State.cellEntry?, Nat.ne_of_gt bound]

theorem State.bindLocal_local?_of_ne
    (state : State) (_formed : state.CellsWellFormed)
    (oldId newId : VarId) (oldValue newValue : Value)
    (different : newId ≠ oldId)
    (found : state.local? oldId = some oldValue) :
    (state.bindLocal newId newValue).local? oldId = some oldValue := by
  have idEq := State.bindLocal_cellId_of_ne state oldId newId different newValue
  unfold State.local? at found ⊢
  rw [idEq]
  cases h : state.cellId? oldId with
  | none => simp [h] at found
  | some cell =>
    simp only [h, Option.bind_some] at found ⊢
    cases entryFound : state.cellEntry? cell with
    | none =>
      unfold State.cell? at found
      simp [entryFound] at found
    | some foundEntry =>
      have entryMember : foundEntry ∈ state.cells :=
        List.mem_of_find?_eq_some entryFound
      have entryId : foundEntry.id = cell := by
        simpa using List.find?_some entryFound
      have cellLt : cell < state.nextCell := by
        simpa [entryId] using _formed foundEntry entryMember
      unfold State.cell? at found ⊢
      rw [State.bindLocal_cellEntry_of_lt state newId newValue cellLt]
      simpa [entryFound] using found

def boundLocalAssigned
    (state : State) (id : VarId) (initial replacement : Value) : State :=
  { state.bindLocal id initial with
    cells := replaceCell (state.bindLocal id initial).cells state.nextCell replacement }

theorem State.bindLocal_assignLocal
    (state : State) (id : VarId)
    (initial replacement : Value) :
    (state.bindLocal id initial).assignLocal id replacement =
      some (boundLocalAssigned state id initial replacement) := by
  unfold State.assignLocal
  rw [State.bindLocal_cellId]
  simp only [Option.bind_some]
  unfold State.assignCell boundLocalAssigned
  simp [State.cellEntry?, State.bindLocal, State.bindCell]

theorem evalExpr_boundLocal_assign_add_i32
    (fuel : Nat) (program : Program) (state : State)
    (formed : state.CellsWellFormed) (id : VarId)
    (initial increment : Int) :
    evalExpr fuel.succ.succ program (state.bindLocal id
        (.signed .i32 initial))
      (.assign .add (.local id) (.value (.signed .i32 increment))) =
      .done .unit
        (boundLocalAssigned state id (.signed .i32 initial)
          (.signed .i32 (wrapSigned program.target .i32 (initial + increment)))) := by
  apply evalExpr_assign_add_i32_local fuel program
    (state.bindLocal id (.signed .i32 initial)) id state.nextCell initial increment
    (boundLocalAssigned state id (.signed .i32 initial)
      (.signed .i32 (wrapSigned program.target .i32 (initial + increment))))
  · exact State.bindLocal_cellId state id _
  · exact formed.bindLocal_local id (.signed .i32 initial)
  · exact State.bindLocal_assignLocal state id _ _

theorem CallerFrame.assign_boundLocal
    {caller current : State} (frame : CallerFrame caller current)
    (id : VarId) (initial replacement : Value) :
    CallerFrame caller (boundLocalAssigned current id initial replacement) := by
  have boundFrame := frame.bindLocal id initial
  apply boundFrame.assignLocalFresh id current.nextCell replacement
  · exact State.bindLocal_cellId current id initial
  · rcases frame.cells with ⟨extra, cells, frontier, fresh⟩
    exact frontier
  · exact State.bindLocal_assignLocal current id initial replacement

end Lanius.Semantics
