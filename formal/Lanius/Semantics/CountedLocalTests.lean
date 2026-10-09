import Lanius.Semantics.CountedLocal
import Lanius.Semantics.CallRun

namespace Lanius.Semantics.CountedLocalTests

open Lanius.Core

private def program : Program := { functions := [{
  id := 7, parameters := [(72, .scalar (.signed .i32))], returnType := .scalar (.signed .i32),
  body := some (.returnValue (some (.local 72))) }] }

private def base : State := ({} : State).bindLocal 72 (.boolean false)

-- The counter shadows a caller local. The action then shadows the counter
-- in a function's parameters and appends cells, but must restore its scope.
example (index : Nat) (fits : index + 1 < 2 ^ 31) :
    ∃ after, RunsStmt program (base.bindLocal 72 (.signed .i32 index))
        (.letLocal 9 .unit (.value .unit) (.sequence
          (.expression (.call 7 [.value (.signed .i32 (-99))]))
          (.sequence (.expression (.assign .add (.local 72) (.value (.signed .i32 1)))) .skip)))
        .next after ∧
      after.local? 72 = some (.signed .i32 (index + 1 : Nat)) ∧
      (restoreLocals base after).local? 72 = some (.boolean false) := by
  have formed : base.CellsWellFormed := by
    simp [State.CellsWellFormed, base, State.bindLocal, State.bindCell]
  let before := base.bindLocal 72 (.signed .i32 index)
  let ready := before.bindLocal 9 .unit
  let callee := ({ ready with locals := [] }).bindLocals [(72, .signed .i32 (-99))]
  have readyFormed : ready.CellsWellFormed := (formed.bindLocal 72 _).bindLocal 9 _
  have calleeFormed : callee.CellsWellFormed := readyFormed.bindLocals [(72, .signed .i32 (-99))]
  have bodyRun : RunsStmt program callee (.returnValue (some (.local 72)))
      (.returned (some (.signed .i32 (-99)))) callee := by core_stmt
  obtain ⟨middle, actionRun, actionFrame⟩ := RunsExpr.callUnchanged
    (program := program) (caller := ready) (functionId := 7) (value := .signed .i32 (-99))
    (bindings := [(72, .signed .i32 (-99))]) (values := [.signed .i32 (-99)]) (by core_lookup) rfl rfl
    readyFormed bodyRun
  obtain ⟨after, run, counter, _, _, _⟩ := CountedLocal.step
    (type := .unit) (temporary := 9) (CountedLocal.start formed 72 index) formed (by decide) fits
    (RunsExpr.ofStable StableExpr.value rfl) actionRun actionFrame.cells
  exact ⟨after, run, counter.counter, counter.cells.restoreLocals.localFound rfl 72 _ rfl⟩

#print axioms CountedLocal.step

-- Zero decrements to -1, while a shadowed caller binding remains untouched.
example : ∃ after,
    RunsExpr program ((base.bindLocal 72 (.signed .i32 0)).bindLocal 9 .unit)
      (.assign .subtract (.local 72) (.value (.signed .i32 1))) .unit after ∧
    (restoreLocals (base.bindLocal 72 (.signed .i32 0)) after).local? 72 = some (.signed .i32 (-1)) ∧
    (restoreLocals base after).local? 72 = some (.boolean false) := by
  have formed : base.CellsWellFormed := by simp [State.CellsWellFormed, base, State.bindLocal, State.bindCell]
  let before := base.bindLocal 72 (.signed .i32 0)
  let ready := before.bindLocal 9 .unit
  have frame := CountedLocal.start formed 72 0
  have cell : ready.cellId? 72 = some base.nextCell := by rfl
  have found : ready.local? 72 = some (.signed .i32 0) := by core_local
  obtain ⟨after, run, counter, _, _, _⟩ := CountedLocal.decrementScoped (index := 0)
    frame formed (frame.cells.trans (FreshCellFrame.bindLocal before 9 .unit)) cell found (by decide)
  exact ⟨after, run, counter.counter, counter.cells.restoreLocals.localFound rfl 72 _ rfl⟩

#print axioms CountedLocal.decrementScoped

-- Computed RHS, a fresh temporary and a shadowed caller counter. The RHS
-- proof comes from evaluation rules, not an assumed successful assignment.
theorem computedCounter (index count : Nat) (fits : index + count < 2 ^ 31) :
    ∃ after, RunsExpr program ((base.bindLocal 72 (.signed .i32 index)).bindLocal 9 (.signed .i32 count))
      (.assign .add (.local 72) (.binary .add (.local 9) (.value (.signed .i32 0)))) .unit after ∧
      (restoreLocals (base.bindLocal 72 (.signed .i32 index)) after).local? 72 =
        some (.signed .i32 (index + count : Nat)) ∧
      (restoreLocals base after).local? 72 = some (.boolean false) := by
  have formed : base.CellsWellFormed := by simp [State.CellsWellFormed, base, State.bindLocal, State.bindCell]
  let before := base.bindLocal 72 (.signed .i32 index)
  let ready := before.bindLocal 9 (.signed .i32 count)
  have frame := CountedLocal.start formed 72 index
  have found : ready.local? 72 = some (.signed .i32 index) := by core_local
  have countFound : ready.local? 9 = some (.signed .i32 count) := by core_local
  obtain ⟨after, run, counter, _, _, _⟩ := frame.assignScoped (program := program) (op := .add)
    (replacement := (index + count : Nat)) formed
    (frame.cells.trans (FreshCellFrame.bindLocal before 9 (.signed .i32 count))) (by rfl) found
    (show RunsExpr program ready (.binary .add (.local 9) (.value (.signed .i32 0)))
      (.signed .i32 count) ready from by core_run)
    (by simpa only [evalAssignValue, assignOpBinary?] using eval_i32_addNat program.target index count fits)
  exact ⟨after, run, counter.counter, counter.cells.restoreLocals.localFound rfl 72 _ rfl⟩

#print axioms computedCounter

end Lanius.Semantics.CountedLocalTests
