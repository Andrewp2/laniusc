import verified_compiler.tests.direct_ir_owned_queries_allocation
import Lanius.Core.Bindings

namespace IRBodyOwnedInputs

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics IRBodyProductionInputs

private def exactRows := Extracted.«lowering::allocation».Functions.«table_has_exact_rows».core
private def headerQuery := Extracted.«lowering::allocation».Functions.«table_header».core
private def rowView := Extracted.«lowering::allocation».Functions.«table_row_view».core
private def rowQuery := Extracted.«lowering::allocation».Functions.«table_row».core

/-- Negative counts reject before constructing any native header view. -/
@[core_pure_rule] theorem actualExactRowsNegative (table : AllocationTable)
    (negative : table.count.toInt ≤ -1) (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before (.call exactRows.id [.value table.value])
      (.boolean false) after ∧ PureFrame before after := by
  core_call_pure exactRows as callee
  core_pure

/-- A reached count comparison retains the actual header ownership transfer. -/
theorem actualExactRows (geometry : HeaderGeometry table before.heap)
    (native : NativeHeader table before.heap) (nonnegative : 0 ≤ table.count.toInt)
    (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before (.call exactRows.id [.value table.value])
      (.boolean (decide (native.header.rows.toInt = table.count.toInt))) after ∧
      MemoryEffect (fun heap result => result = heap.borrowBlock geometry.block.base) before after := by
  core_call_framed (RunsExpr.callEffect (MemoryEffect.scopeStable _)) exactRows as callee
  apply RunsStmt.guardEffectFalse (MemoryEffect.scopeStable _)
  · core_pure_guard
  · intro ready frame
    have same : ready.heap = before.heap := frame.heap.trans (show callee.heap = before.heap from rfl)
    have tableFound : ready.local? (exactRows.argumentId 0) = some table.value := by core_local
    let currentGeometry : HeaderGeometry table ready.heap := {
      geometry with
      found := by rw [same]; exact geometry.found
      unique := by rw [same]; exact geometry.unique }
    let currentHeader : NativeHeader table ready.heap := {
      native with snapshot := by rw [same]; exact native.snapshot }
    obtain ⟨read, header, effect⟩ := actualHeader currentGeometry currentHeader frame.afterFormed
    have queried : RunsExpr extractedProgram ready
        (.call headerQuery.id [.local (exactRows.argumentId 0)]) native.header.value read :=
      RunsExpr.callArguments (.cons (by core_run) .nil) header
    have tableKept := effect.1.localFound queried.choose_spec.2 _ _ tableFound
    refine ⟨read, RunsStmt.returnValue ?_, ?_⟩
    · have rows : RunsExpr extractedProgram ready
          (.field (.call headerQuery.id [.local (exactRows.argumentId 0)]) 1)
          (.signed .i32 native.header.rows.toInt) read := RunsExpr.field queried (by rfl)
      have count : RunsExpr extractedProgram read (.field (.local (exactRows.argumentId 0)) 1)
          (.signed .i32 table.count.toInt) read := by core_run
      exact RunsExpr.binary (operation := .equal) rows count ⟨by decide, by decide⟩ rfl
    · simpa only [MemoryEffect, currentGeometry] using effect

/-- Every queried row starts in the same original table block. This is a
    native geometry fact, not a successful row-query premise. -/
abbrev RowLocations (native : NormalTable table heap) : Prop :=
  ∀ index, index < native.count → heap.containingBlock? (table.rowBase index) = some native.geometry.block

private theorem actualRowView (native : BorrowedTable table before.heap)
    (locations : RowLocations native.toNormalTable) (inside : index < native.count)
    (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before (.call rowView.id
      [.value table.value, .value (.signed .i32 index)])
      (.rawSlice rowType (table.rowBase index + 80 - 8) 1) after ∧ PureFrame before after := by
  obtain ⟨room, pointer, product⟩ := native.toNormalTable.rowBounds inside
  have layout : NativeLayout.valueWords? extractedProgram rowType = some 10 := by decide +kernel
  have multiply := eval_i32_mulNat extractedProgram.target index 80 product
  have header := eval_pointer_addNat extractedProgram.target table.memory 72 native.geometry.pointerFits
  have offset := eval_pointer_addNat extractedProgram.target (table.memory + 72) (index * 80)
    (by change table.memory + 72 + index * 80 < 2 ^ 64
        dsimp only [AllocationTable.rowBase] at pointer
        omega)
  have ending := eval_pointer_addNat extractedProgram.target (table.rowBase index) 80 pointer
  have subtract := eval_pointer_subNat extractedProgram.target (table.rowBase index + 80) 8 (by omega) pointer
  have aligned : table.rowBase index % 8 = 0 := by
    have headerAligned : 72 % 8 = 0 := by decide
    simp only [AllocationTable.rowBase, Nat.add_mod, Nat.mul_mod, native.geometry.aligned,
      headerAligned, Nat.mul_zero, Nat.add_zero]
  have mapped (state : State) (same : state.heap = before.heap) :
      mapRawNominalSlice extractedProgram state rowType (table.rowBase index + 80 - 8) 1 =
        .done (.rawSlice rowType (table.rowBase index + 80 - 8) 1) state := by
    have start : table.rowBase index + 80 - 8 + 8 - 1 * 10 * 8 = table.rowBase index := by omega
    have result := mapRawNominalSlice_of_block (state := state)
      (address := table.rowBase index + 80 - 8) (block := native.geometry.block) 1
      (by decide) rfl layout (by decide)
      (by change 1 * 10 * 8 ≤ table.rowBase index + 80 - 8 + 8; omega)
      (by simpa only [NativeLayout.wordBytes, start, same] using locations index inside)
      (by simpa only [NativeLayout.wordBytes, start] using aligned)
      native.geometry.alignment
      (by change table.rowBase index + 80 - 8 + 8 ≤ native.geometry.block.base + native.geometry.block.size
          omega)
      (by rw [same]; exact native.geometry.unique)
    have borrowed : state.heap.borrowBlock native.geometry.block.base = state.heap := by
      rw [same]; exact native.borrowed
    have one : ((1 : Nat) : Int) = 1 := rfl
    change mapRawNominalSlice extractedProgram state rowType (table.rowBase index + 80 - 8) 1 =
      .done (.rawSlice rowType (table.rowBase index + 80 - 8) 1)
        { state with heap := state.heap.borrowBlock native.geometry.block.base } at result
    rw [borrowed] at result
    simpa only [one] using result
  core_call_pure rowView as callee
  apply RunsStmt.letPure
  · core_run
  · core_formed
  · let current := callee.bindLocal (rowView.bindingId 0) (.pointer (table.rowBase index + 80 - 8))
    have currentHeap : current.heap = before.heap := rfl
    apply RunsStmt.returnPure
    exact ⟨current, RunsExpr.nominalSliceFromParts
      (before := current) (middle := current) (afterLength := current) (after := current)
      (by core_run) (by core_run) (mapped current currentHeap) rfl, PureFrame.refl (by core_formed)⟩

/-- The real1158 accessor is pure only after the actual shared header borrow. -/
@[core_pure_rule] theorem actualRow (native : BorrowedTable table before.heap)
    (locations : RowLocations native.toNormalTable) (inside : index < native.count)
    (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before (.call rowQuery.id
      [.value table.value, .value (.signed .i32 index)])
      (native.rows index inside).row.value after ∧ PureFrame before after := by
  have view {state : State} (same : state.heap = before.heap) (cells : state.CellsWellFormed) :
      ∃ after, RunsExpr extractedProgram state (.call rowView.id
        [.value table.value, .value (.signed .i32 index)])
        (.rawSlice rowType (table.rowBase index + 80 - 8) 1) after ∧ PureFrame state after := by
    let current : BorrowedTable table state.heap := {
      native with
      geometry := { native.geometry with
        found := by rw [same]; exact native.geometry.found
        unique := by rw [same]; exact native.geometry.unique }
      header := { native.header with snapshot := by rw [same]; exact native.header.snapshot }
      rows := fun row bounded => { native.rows row bounded with
        snapshot := by rw [same]; exact (native.rows row bounded).snapshot }
      borrowed := by
        change state.heap.borrowBlock native.geometry.block.base = state.heap
        rw [same]
        exact native.borrowed }
    have currentLocations : RowLocations current.toNormalTable := by
      intro row bounded
      change state.heap.containingBlock? (table.rowBase row) = some native.geometry.block
      rw [same]
      exact locations row bounded
    exact actualRowView current currentLocations inside cells
  have location : rawSliceElementAddress? extractedProgram rowType (table.rowBase index + 80 - 8) 0 =
      .ok (table.rowBase index) := rawSliceElementAddress_of_layout (words := 10) rfl
        (by decide +kernel) (by decide) (by omega) (by omega)
  have read {state : State} (same : state.heap = before.heap) :
      readRawSliceIndex extractedProgram state rowType (table.rowBase index + 80 - 8) 1 0 =
        .ok (native.rows index inside).row.value := by
    simp only [readRawSliceIndex, Nat.not_le_of_lt (by decide : 0 < 1), ↓reduceIte, location]
    rw [same]
    exact (native.rows index inside).snapshot.read
  core_call_pure rowQuery as callee
  apply RunsStmt.letFramedPure
  · apply RunsExpr.callPureArguments (values := [table.value, .signed .i32 index])
    · core_arguments
    · have viewId : rowView.id = 1154 := rfl
      simpa only [List.map_cons, List.map_nil, viewId] using view (state := callee) rfl (by core_formed)
  · intro middle frame
    have selected : readRawSliceIndex extractedProgram
        (middle.bindLocal (rowQuery.bindingId 0) (.rawSlice rowType (table.rowBase index + 80 - 8) 1))
        rowType (table.rowBase index + 80 - 8) 1 0 = .ok (native.rows index inside).row.value :=
      read (frame.heap.trans (show callee.heap = before.heap from rfl))
    core_pure

#print axioms actualExactRowsNegative
#print axioms actualExactRows
#print axioms actualRow

end IRBodyOwnedInputs
