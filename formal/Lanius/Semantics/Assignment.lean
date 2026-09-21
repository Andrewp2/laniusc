import Lanius.Semantics
import Lanius.Semantics.Loop
import Lanius.Semantics.Stable

namespace Lanius.Semantics

open Lanius
open Lanius.Core

theorem replaceCell_find_same
    (cells : List Cell) (id : CellId) (value : Value) (entry : Cell)
    (found : cells.find? (fun cell => cell.id == id) = some entry) :
    (replaceCell cells id value).find? (fun cell => cell.id == id) =
      some { entry with value := some value } := by
  induction cells with
  | nil => simp at found
  | cons head tail inductionHypothesis =>
      by_cases same : head.id = id
      · simp [replaceCell, same] at found ⊢
        subst entry
        exact same.symm
      · simp [replaceCell, same] at found ⊢
        exact inductionHypothesis found

theorem replaceCell_find_other
    (cells : List Cell) (assigned queried : CellId) (value : Value)
    (different : queried ≠ assigned) :
    (replaceCell cells assigned value).find?
        (fun cell => cell.id == queried) =
      cells.find? (fun cell => cell.id == queried) := by
  induction cells with
  | nil => rfl
  | cons head tail inductionHypothesis =>
      by_cases assignedHead : head.id = assigned
      · subst assigned
        have notQueried : head.id ≠ queried := Ne.symm different
        simp [replaceCell, notQueried, inductionHypothesis]
      · by_cases queriedHead : head.id = queried
        · simp [replaceCell, queriedHead, different]
        · simp [replaceCell, assignedHead, queriedHead, inductionHypothesis]

theorem assignCell_state
    {state next : State} {cell : CellId} {value : Value}
    (assigned : state.assignCell cell value = some next) :
    next = { state with cells := replaceCell state.cells cell value } := by
  simp only [State.assignCell] at assigned
  split at assigned <;> simp_all

theorem assignCell_finds_assigned
    {state next : State} {cell : CellId} {value : Value}
    (assigned : state.assignCell cell value = some next) :
    next.cellEntry? cell = some { id := cell, value := some value } := by
  have presentWitness : ∃ entry, state.cellEntry? cell = some entry := by
    simp only [State.assignCell] at assigned
    split at assigned <;> rename_i present
    · cases found : state.cellEntry? cell with
      | none => simp [found] at present
      | some entry => exact ⟨entry, rfl⟩
    · cases assigned
  obtain ⟨entry, found⟩ := presentWitness
  have entryId : entry.id = cell := by
    simpa using List.find?_some found
  rw [assignCell_state assigned]
  change (replaceCell state.cells cell value).find?
      (fun candidate => candidate.id == cell) = _
  rw [replaceCell_find_same state.cells cell value entry found]
  subst entryId
  rfl

theorem cellEntry_of_local
    (state : State) (id cell : CellId) (value : Value)
    (cellFound : state.cellId? id = some cell)
    (localFound : state.local? id = some value) :
    state.cellEntry? cell = some { id := cell, value := some value } := by
  unfold State.local? at localFound
  rw [cellFound] at localFound
  cases h : state.cellEntry? cell with
  | none => simp [State.cell?, h] at localFound
  | some entry =>
    have valueFound : entry.value = some value := by
      simpa [State.cell?, h] using localFound
    have entryId : entry.id = cell := by
      simpa using List.find?_some h
    cases entry
    simp_all

private theorem assignCell_local_after
    {state after : State} (id : VarId) (assignedCell : CellId)
    (replacement : Value) {cell : CellId}
    (assigned : state.assignCell assignedCell replacement = some after)
    (cellFound : state.cellId? id = some cell) :
    after.local? id =
      if cell = assignedCell then some replacement else state.local? id := by
  have afterCell : after.cellId? id = some cell := by
    rw [assignCell_state assigned]
    change state.cellId? id = some cell
    exact cellFound
  unfold State.local?
  rw [afterCell, cellFound]
  simp only [Option.bind_some]
  by_cases same : cell = assignedCell
  · subst cell
    simp [State.cell?, assignCell_finds_assigned assigned]
  · rw [if_neg same]
    unfold State.cell? State.cellEntry?
    rw [assignCell_state assigned]
    simpa using congrArg (fun found => found.bind Cell.value)
      (replaceCell_find_other state.cells assignedCell cell replacement same)

theorem assignLocal_assignCell
    {state after : State} (id : VarId) (cell : CellId) (value : Value)
    (cellFound : state.cellId? id = some cell)
    (assigned : state.assignLocal id value = some after) : state.assignCell cell value = some after := by
  simpa [State.assignLocal, cellFound] using assigned

theorem assignLocal_exists
    (state : State) (id : VarId) (initial replacement : Value) (cell : CellId)
    (cellFound : state.cellId? id = some cell)
    (localFound : state.local? id = some initial) :
    ∃ after, state.assignLocal id replacement = some after := by
  have entry := cellEntry_of_local state id cell initial cellFound localFound
  refine ⟨{state with cells := replaceCell state.cells cell replacement}, ?_⟩
  simp [State.assignLocal, cellFound, State.assignCell, entry]

theorem assignCell_preserves_frame
    {state after : State} {cell : CellId} {value : Value} (protectedId : VarId)
    (assigned : state.assignCell cell value = some after) :
    after.locals = state.locals ∧ after.cellId? protectedId = state.cellId? protectedId := by
  rw [assignCell_state assigned]
  exact ⟨rfl, rfl⟩

theorem assignLocal_preserves_frame
    {state after : State} {id protectedId : VarId} {value : Value}
    (assigned : state.assignLocal id value = some after) :
    after.locals = state.locals ∧ after.cellId? protectedId = state.cellId? protectedId := by
  cases cell : state.cellId? id with
  | none => simp [State.assignLocal, cell] at assigned
  | some cell => exact assignCell_preserves_frame protectedId (by
      simpa [State.assignLocal, cell] using assigned)

theorem assignLocal_finds_assigned
    {state after : State} (id : VarId) (cell : CellId) (value : Value)
    (cellFound : state.cellId? id = some cell)
    (assigned : state.assignLocal id value = some after) : after.local? id = some value := by
  have assignedCell := assignLocal_assignCell id cell value cellFound assigned
  simpa using assignCell_local_after id cell value assignedCell cellFound

theorem assignCell_preserves_other_local_of_cellId
    {state after : State} (id : VarId) (assignedCell : CellId) (value : Value)
    {oldValue : Value} (assigned : state.assignCell assignedCell value = some after)
    (localFound : state.local? id = some oldValue)
    (different : state.cellId? id ≠ some assignedCell) : after.local? id = some oldValue := by
  cases h : state.cellId? id with
  | none => simp [State.local?, h] at localFound
  | some cell =>
      have differentCell : cell ≠ assignedCell := by
        intro equal
        apply different
        simp [h, equal]
      simpa [differentCell, localFound] using
        assignCell_local_after id assignedCell value assigned h

theorem evalExpr_assign_set_local
    (fuel : Nat) (program : Program) (state : State)
    (id : VarId) (cell : CellId) (current replacement : Value) (after : State)
    (cellFound : state.cellId? id = some cell)
    (localFound : state.local? id = some current)
    (assigned : state.assignLocal id replacement = some after) :
    evalExpr fuel.succ.succ program state
      (.assign .set (.local id) (.value replacement)) =
      .done .unit after := by
  have place := evalPlace_local_of_local? fuel program state id cell current
    cellFound localFound
  have right := evalExpr_value fuel program state replacement
  have assignedCell := assignLocal_assignCell id cell replacement cellFound assigned
  have write :
      writeResolvedPlace state
          { root := cell, projections := [], value := some current }
          replacement = .ok after := by
    simp [writeResolvedPlace, assignedCell]
  rw [evalExpr.eq_def]
  simp only [place, right]
  rw [show evalAssignValue program.target .set (some current) replacement =
      .ok replacement by rfl]
  simp only [write]

private theorem stableExpr_two
    {program : Program} {state after : State} {expression : Expr} {value : Value}
    (run : ∀ fuel : Nat, evalExpr fuel.succ.succ program state expression =
      .done value after) : StableExpr 2 program state expression value after := by
  intro fuel enough
  simpa only [show (fuel - 2).succ.succ = fuel by omega] using run (fuel - 2)

theorem StableExpr.assignSetBool
    (program : Program) (state : State) (id : VarId) (cell : CellId)
    (current : Value) (value : Bool) (after : State)
    (cellFound : state.cellId? id = some cell)
    (localFound : state.local? id = some current)
    (assigned : state.assignLocal id (.boolean value) = some after) :
    StableExpr 2 program state
      (.assign .set (.local id) (.value (.boolean value))) .unit after := by
  apply stableExpr_two
  intro fuel
  exact evalExpr_assign_set_local fuel program state id cell current
    (.boolean value) after cellFound localFound assigned

theorem StableExpr.assignAddI32
    (program : Program) (state : State) (id : VarId) (cell : CellId)
    (current increment : Int) (after : State)
    (cellFound : state.cellId? id = some cell)
    (localFound : state.local? id = some (.signed .i32 current))
    (assigned : state.assignLocal id
      (.signed .i32 (wrapSigned program.target .i32 (current + increment))) =
      some after) :
    StableExpr 2 program state
      (.assign .add (.local id) (.value (.signed .i32 increment))) .unit after := by
  apply stableExpr_two
  intro fuel
  exact evalExpr_assign_add_i32_local fuel program state id cell current increment
    after cellFound localFound assigned

theorem StableStmt.expression
    {fuel : Nat} {program : Program} {state after : State}
    {expression : Expr} {value : Value}
    (run : StableExpr fuel program state expression value after) :
    StableStmt (fuel + 1) program state (.expression expression) .next after := by
  intro enough bound
  have evaluated := run (enough - 1) (by omega)
  simpa [show enough - 1 + 1 = enough by omega] using
    execStmt_expression (fuel := enough - 1) program state expression value after evaluated

/-! A state-level contract for writes through caller-owned aggregate storage.
    CellEffect records the exact root-cell replacement and the fields which
    an assignment cannot touch.  It is deliberately independent of any
    particular slice or lexer shape. -/

structure CellEffect (before after : State) (root : CellId) (value : Value) : Prop where
  cells : after.cells = replaceCell before.cells root value
  locals : after.locals = before.locals
  nextCell : after.nextCell = before.nextCell
  heap : after.heap = before.heap
  world : after.world = before.world
  views : after.i32ArrayViews = before.i32ArrayViews

theorem assignCell_effect
    {state after : State} {cell : CellId} {value : Value}
    (assigned : state.assignCell cell value = some after) :
    CellEffect state after cell value := by
  rw [assignCell_state assigned]
  exact ⟨rfl, rfl, rfl, rfl, rfl, rfl⟩

private theorem replaceCell_same
    (cells : List Cell) (root : CellId) (old new : Value) :
    replaceCell (replaceCell cells root old) root new =
      replaceCell cells root new := by
  induction cells with
  | nil => rfl
  | cons head tail induction =>
      by_cases same : head.id = root
      · simpa [replaceCell, same] using induction
      · simp [replaceCell, same, induction]

theorem CellEffect.trans
    {before middle after : State} {root : CellId}
    {firstValue secondValue : Value}
    (first : CellEffect before middle root firstValue)
    (second : CellEffect middle after root secondValue) :
    CellEffect before after root secondValue := by
  refine ⟨?_, second.locals.trans first.locals, second.nextCell.trans first.nextCell,
    second.heap.trans first.heap, second.world.trans first.world,
    second.views.trans first.views⟩
  rw [second.cells, first.cells, replaceCell_same]

theorem CellEffect.otherCell
    {before after : State} {root queried : CellId} {value : Value}
    (effect : CellEffect before after root value) (different : queried ≠ root)
    {entry : Cell} (found : before.cellEntry? queried = some entry) :
    after.cellEntry? queried = some entry := by
  unfold State.cellEntry? at found ⊢
  rw [effect.cells, replaceCell_find_other before.cells root queried value different]
  exact found

private theorem setValue_length_of_lt :
    ∀ (values : List Value) (index : Nat) (value : Value),
      index < values.length →
      (setValue values index value).length = values.length := by
  intro values
  induction values with
  | nil => simp
  | cons head tail induction =>
      intro index value bound
      cases index with
      | zero => rfl
      | succ index =>
          simp only [List.length_cons] at bound ⊢
          simp [setValue, induction index value (by omega)]

def i32RowUpdate (elements : List Value) (row : Nat)
    (kind start finish : Int) : List Value :=
  setValue (setValue (setValue elements row (.signed .i32 kind)) (row + 1)
    (.signed .i32 start)) (row + 2) (.signed .i32 finish)

theorem i32RowUpdate_spec
    (elements : List Value) (row : Nat) (kind start finish : Int)
    (bounds : row + 3 ≤ elements.length) :
    (i32RowUpdate elements row kind start finish).length = elements.length ∧
      row + 3 ≤ (i32RowUpdate elements row kind start finish).length := by
  have rowLt : row < elements.length := by omega
  have row1Lt : row + 1 < elements.length := by omega
  have row2Lt : row + 2 < elements.length := by omega
  have first := setValue_length_of_lt elements row (.signed .i32 kind) rowLt
  have second := setValue_length_of_lt
    (setValue elements row (.signed .i32 kind)) (row + 1)
    (.signed .i32 start) (by simpa [first] using row1Lt)
  have third := setValue_length_of_lt
    (setValue (setValue elements row (.signed .i32 kind)) (row + 1)
      (.signed .i32 start)) (row + 2) (.signed .i32 finish)
      (by simpa [first, second] using row2Lt)
  have finalLength := third.trans (second.trans first)
  have finalLength' : (i32RowUpdate elements row kind start finish).length =
      elements.length := by
    simpa [i32RowUpdate] using finalLength
  exact ⟨finalLength', by omega⟩

/-! Three adjacent stores are exposed as one reusable effect contract.  The
    caller supplies the backing-cell lookup and row bound; the result names
    every intermediate state so expression-level assignment rules can consume
    it without reopening the cell/frame bookkeeping. -/
theorem assignI32Row
    (state : State) (root : CellId) (elements : List Value) (row : Nat)
    (kind start finish : Int)
    (backing : state.cellEntry? root = some
      { id := root, value := some (.array elements) })
    (bounds : row + 3 ≤ elements.length) :
    ∃ after₁ after₂ after₃,
      state.assignCell root (.array (setValue elements row (.signed .i32 kind))) = some after₁ ∧
      after₁.assignCell root (.array (setValue (setValue elements row
        (.signed .i32 kind)) (row + 1) (.signed .i32 start))) = some after₂ ∧
      after₂.assignCell root (.array (i32RowUpdate elements row kind start finish)) = some after₃ ∧
      CellEffect state after₃ root (.array (i32RowUpdate elements row kind start finish)) ∧
      after₃.cellEntry? root = some
        { id := root, value := some (.array (i32RowUpdate elements row kind start finish)) } ∧
      (i32RowUpdate elements row kind start finish).length = elements.length ∧
      row + 3 ≤ (i32RowUpdate elements row kind start finish).length := by
  let first : State := { state with cells := (replaceCell state.cells root
    (.array (setValue elements row (.signed .i32 kind)))) }
  let second : State := { first with cells := (replaceCell first.cells root
    (.array (setValue (setValue elements row (.signed .i32 kind)) (row + 1)
      (.signed .i32 start)))) }
  let third : State := { second with cells := (replaceCell second.cells root
    (.array (i32RowUpdate elements row kind start finish))) }
  have firstAssigned : state.assignCell root
      (.array (setValue elements row (.signed .i32 kind))) = some first := by
    simp [first, State.assignCell, backing]
  have firstEntry := assignCell_finds_assigned firstAssigned
  have secondAssigned : first.assignCell root
      (.array (setValue (setValue elements row (.signed .i32 kind)) (row + 1)
        (.signed .i32 start))) = some second := by
    simp [second, State.assignCell, firstEntry]
  have secondEntry := assignCell_finds_assigned secondAssigned
  have thirdAssigned : second.assignCell root
      (.array (i32RowUpdate elements row kind start finish)) = some third := by
    simp [third, State.assignCell, secondEntry, i32RowUpdate]
  refine ⟨first, second, third, firstAssigned, secondAssigned, thirdAssigned, ?_, ?_, ?_, ?_⟩
  · exact (assignCell_effect firstAssigned).trans
      ((assignCell_effect secondAssigned).trans (assignCell_effect thirdAssigned))
  · exact assignCell_finds_assigned thirdAssigned
  · exact (i32RowUpdate_spec elements row kind start finish bounds).1
  · exact (i32RowUpdate_spec elements row kind start finish bounds).2

end Lanius.Semantics
