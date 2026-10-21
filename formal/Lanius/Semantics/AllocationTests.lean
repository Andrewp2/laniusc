import Lanius.Semantics.StmtList

namespace Lanius.Semantics.AllocationTests

open Lanius.Core

private def program : Program := {}
private def caller : State := ({} : State).bindLocal 7 (.signed .i32 3)
private theorem callerFormed : caller.CellsWellFormed := by
  simp [State.CellsWellFormed, caller, State.bindLocal, State.bindCell]
private theorem callerUnique : (caller.cells.map Cell.id).Nodup := by
  simp [caller, State.bindLocal, State.bindCell]

-- Mutation changes a value, not its identity or the allocation frontier.
private def changed : State := { caller with cells := replaceCell caller.cells 0 (.signed .i32 9) }
private theorem write : RunsExpr program caller
    (.assign .set (.local 7) (.value (.signed .i32 9))) .unit changed :=
  .ofEval (fuel := 2) rfl
example : changed.cell? 0 = some (.signed .i32 9) := rfl
example : caller.cellInventory.Extends changed.cellInventory := write.inventory
example : changed.CellsWellFormed := write.cellsWellFormed callerFormed
example : (changed.cellEntry? 0).isSome := write.inventory.retainsCell rfl
example : (changed.cells.map Cell.id).Nodup := write.inventory.unique callerFormed callerUnique

-- The last iteration restores bindings, not the cell inventory.
private def loopAfter : State := restoreLocals caller
  ((caller.bindLocal 7 .unit).bindLocal 7 (.boolean true))
private theorem valuesLoop : execForValues 3 program caller 7 [.unit, .boolean true] .continueLoop =
    .done .next loopAfter := rfl
example : loopAfter.cellInventory.ids = [0, 1, 2] := rfl
example : loopAfter.nextCell = 3 := rfl
example : caller.cellInventory.Extends loopAfter.cellInventory := by
  simpa only [valuesLoop, Outcome.PreservesInventory] using
    (execForValues_preservesInventory (fuel := 3) (program := program) (state := caller)
      (id := 7) (values := [.unit, .boolean true]) (body := .continueLoop))

private def rangeAfter : State := restoreLocals caller
  ((caller.bindLocal 7 (.signed .i32 0)).bindLocal 7 (.signed .i32 1))
private theorem rangeLoop : execForRange 3 program caller 7 0 (some 2) false .skip =
    .done .next rangeAfter := rfl
example : caller.cellInventory.Extends rangeAfter.cellInventory := by
  simpa only [rangeLoop, Outcome.PreservesInventory] using
    (execForRange_preservesInventory (fuel := 3) (program := program) (state := caller)
      (id := 7) (current := 0) (stop := some 2) (inclusive := false) (body := .skip))

-- Array-to-slice conversion retains an unnamed backing cell.
private def backing : State := (caller.allocateTemporary (.array [.signed .i32 5])).2
private theorem temporary : RunsExpr program caller
    (.arrayToSlice (.scalar (.signed .i32)) (.value (.array [.signed .i32 5])))
    (.slice (.scalar (.signed .i32)) 1 [] 0 1) backing := .ofEval (fuel := 2) rfl
example : backing.cellInventory.ids = [0, 1] := rfl
example : backing.CellsWellFormed := temporary.cellsWellFormed callerFormed
example : backing.cellEntry? backing.nextCell = none :=
  (temporary.cellsWellFormed callerFormed).cellEntry_nextCell

private def doneInventory : Outcome α → Option CellInventory
  | .done _ after => some after.cellInventory
  | _ => none
-- Native view registration does not allocate a second language backing cell.
example : doneInventory (evalExpr 2 program caller
    (.i32ArrayDataPtr (.value (.array [.signed .i32 5])))) = some ⟨[0, 1], 2⟩ := rfl

-- A trap after binding keeps the fresh, uninitialized cell.
private def uninitialized : State := restoreLocals caller (caller.bindUninitialized 8)
private theorem trapped : execStmt 3 program caller
    (.letUninitialized 8 .unit (.expression (.local 8))) =
    .trapped .uninitializedLocal uninitialized := rfl
example : caller.cellInventory.Extends uninitialized.cellInventory := by
  simpa only [trapped, Outcome.PreservesInventory] using
    (execStmt_preservesInventory (fuel := 3) (program := program) (state := caller)
      (statement := .letUninitialized 8 .unit (.expression (.local 8))))
example : uninitialized.cellEntry? 1 = some ⟨1, none⟩ := rfl
example : (execStmt 2 program caller (.letUninitialized 8 .unit (.expression (.local 8)))) =
    .outOfFuel := rfl

-- Recursive calls append parameter cells in actual call order.
private def recursive : Program := { functions := [{
  id := 7, parameters := [(1, .scalar .bool)], returnType := .unit,
  body := some (.ifThenElse (.local 1)
    (.returnValue (some (.call 7 [.value (.boolean false)]))) (.returnValue (some (.value .unit)))) }] }
private def completed : State := {
  caller with cells := caller.cells ++ [⟨1, some (.boolean true)⟩, ⟨2, some (.boolean false)⟩], nextCell := 3 }
private theorem recursiveRun : RunsExpr recursive caller (.call 7 [.value (.boolean true)]) .unit completed :=
  .ofEval (fuel := 7) rfl
example : completed.CellsWellFormed := recursiveRun.cellsWellFormed callerFormed
example : (completed.cells.map Cell.id).Nodup := recursiveRun.inventory.unique callerFormed callerUnique

-- A nested host exit retains the surrounding local's cell.
private def exitProgram : Program := { functions := [
  { id := 9, parameters := [(1, .scalar (.signed .i32))], returnType := .unit,
    body := none, external := some (.host .exit) },
  { id := 10, parameters := [], returnType := .unit,
    body := some (.letLocal 7 (.scalar .bool) (.value (.boolean false))
      (.expression (.call 9 [.value (.signed .i32 17)]))) }] }
private def exited : State := {
  restoreLocals caller (({ caller with locals := [] }).bindLocal 7 (.boolean false)) with
  world := Lanius.World.record caller.world .exit }
private theorem exitRun : evalExpr 6 exitProgram caller (.call 10 []) = .exited 17 exited := rfl
example : caller.cellInventory.Extends exited.cellInventory := by
  simpa only [exitRun, Outcome.PreservesInventory] using
    (evalExpr_preservesInventory (fuel := 6) (program := exitProgram) (state := caller) (expression := .call 10 []))

-- The law neither assumes validity nor claims to repair invalid input.
private def invalid : State := { cells := [⟨4, some .unit⟩], nextCell := 2 }
example : ¬ invalid.CellsWellFormed := by simp [State.CellsWellFormed, invalid]
example : invalid.cellInventory.Extends invalid.cellInventory :=
  evalExpr_inventory (fuel := 1) (program := program) (expression := .value .unit) rfl

-- A valid state need not begin at zero or have a contiguous initial inventory.
private def gapped : State := { cells := [⟨2, some .unit⟩], nextCell := 7 }
private theorem gapRun : RunsStmt program gapped (.letUninitialized 8 .unit .skip)
    .next (restoreLocals gapped (gapped.bindUninitialized 8)) := .ofExec (fuel := 2) rfl
example : (restoreLocals gapped (gapped.bindUninitialized 8)).cellInventory.ids = [2, 7] := rfl
example : (restoreLocals gapped (gapped.bindUninitialized 8)).CellsWellFormed :=
  gapRun.cellsWellFormed (by simp [State.CellsWellFormed, gapped])

private def duplicate : State := { cells := [⟨0, some .unit⟩, ⟨0, none⟩], nextCell := 1 }
private theorem duplicateRun : RunsStmt program duplicate (.letUninitialized 8 .unit .skip)
    .next (restoreLocals duplicate (duplicate.bindUninitialized 8)) := .ofExec (fuel := 2) rfl
example : (restoreLocals duplicate (duplicate.bindUninitialized 8)).CellsWellFormed :=
  duplicateRun.cellsWellFormed (by simp [State.CellsWellFormed, duplicate])
example : ¬ ((restoreLocals duplicate (duplicate.bindUninitialized 8)).cells.map Cell.id).Nodup := by
  simp [duplicate, restoreLocals, State.bindUninitialized, State.bindCell]

#print axioms evalExpr_preservesInventory
#print axioms execStmt_preservesInventory
#print axioms RunsExpr.cellsWellFormed
#print axioms CellInventory.Extends.unique

end Lanius.Semantics.AllocationTests
