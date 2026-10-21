import verified_compiler.tests.direct_ir_owned_inputs
import Lanius.Semantics.EffectProof

namespace IRBodyOwnedInputs

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics IRBodyProductionInputs

private def headerView := Extracted.«lowering::allocation».Functions.«table_header_view».core
private def headerQuery := Extracted.«lowering::allocation».Functions.«table_header».core
private def exactRows := Extracted.«lowering::allocation».Functions.«table_has_exact_rows».core

private theorem actualHeaderView (geometry : HeaderGeometry table before.heap)
    (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before (.call headerView.id [.value table.value])
      (.rawSlice headerType (table.memory + 72 - 8) 1) after ∧
      MemoryEffect (fun heap result => result = heap.borrowBlock geometry.block.base) before after := by
  have layout : NativeLayout.valueWords? extractedProgram headerType = some 9 := by decide +kernel
  have add := eval_pointer_addNat extractedProgram.target table.memory 72 geometry.pointerFits
  have sub := eval_pointer_subNat extractedProgram.target (table.memory + 72) 8 (by omega) geometry.pointerFits
  have mapped (state : State) (same : state.heap = before.heap) :
      mapRawNominalSlice extractedProgram state headerType (table.memory + 72 - 8) 1 =
        .done (.rawSlice headerType (table.memory + 72 - 8) 1)
          { state with heap := before.heap.borrowBlock geometry.block.base } := by
    have start : table.memory + 72 - 8 + 8 - 1 * 9 * 8 = table.memory := by omega
    have result := mapRawNominalSlice_of_block (state := state) (address := table.memory + 72 - 8)
      (block := geometry.block) 1 (by decide) rfl layout (by decide)
      (by change 1 * 9 * 8 ≤ table.memory + 72 - 8 + 8; omega)
      (by simpa only [NativeLayout.wordBytes, start, same] using geometry.found)
      (by simpa only [NativeLayout.wordBytes, start] using geometry.aligned)
      geometry.alignment (by change table.memory + 72 - 8 + 8 ≤ geometry.block.base + geometry.block.size
                             have room := geometry.bounds; omega)
      (by rw [same]; exact geometry.unique)
    have one : ((1 : Nat) : Int) = 1 := rfl
    simpa only [same, one] using result
  core_call_framed (RunsExpr.callEffect (MemoryEffect.scopeStable _)) headerView as callee
  apply RunsStmt.returnEffect
  exact ⟨{ callee with heap := before.heap.borrowBlock geometry.block.base },
    RunsExpr.nominalSliceFromParts (by core_run) (by core_run) (mapped callee rfl) rfl,
    ⟨(CallerFrame.refl (state := callee) (by core_formed)).cells, rfl, rfl, rfl⟩⟩

/-- The actual header read transfers ownership even when its rows mismatch. -/
theorem actualHeader (geometry : HeaderGeometry table before.heap)
    (native : NativeHeader table before.heap) (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before (.call headerQuery.id [.value table.value])
      native.header.value after ∧
      MemoryEffect (fun heap result => result = heap.borrowBlock geometry.block.base) before after := by
  have view {state : State} (same : state.heap = before.heap) (cells : state.CellsWellFormed) :
      ∃ after, RunsExpr extractedProgram state (.call headerView.id [.value table.value])
        (.rawSlice headerType (table.memory + 72 - 8) 1) after ∧
        MemoryEffect (fun heap result => result = heap.borrowBlock geometry.block.base) state after := by
    let current : HeaderGeometry table state.heap := {
      geometry with
      found := by rw [same]; exact geometry.found
      unique := by rw [same]; exact geometry.unique }
    obtain ⟨after, run, effect⟩ := actualHeaderView current cells
    exact ⟨after, run, by simpa only [MemoryEffect, current] using effect⟩
  have location : rawSliceElementAddress? extractedProgram headerType (table.memory + 72 - 8) 0 =
      .ok table.memory := rawSliceElementAddress_of_layout (words := 9) rfl (by decide +kernel)
        (by decide) (by omega) (by omega)
  core_call_framed (RunsExpr.callEffect (MemoryEffect.scopeStable _)) headerQuery as callee
  have viewId : headerView.id = 1153 := rfl
  have calleeHeap : callee.heap = before.heap := rfl
  apply RunsStmt.letMemoryEffect
  · apply RunsExpr.argumentsEffect (values := [table.value])
    · core_arguments
    · simpa only [List.map_cons, List.map_nil, viewId] using
        view (state := callee) rfl (by core_formed)
  · intro middle run effect
    have formedMiddle := effect.1.after_cellsWellFormed (by core_formed)
    have read : readRawSliceIndex extractedProgram middle headerType (table.memory + 72 - 8) 1 0 =
        .ok native.header.value := by
      simp only [readRawSliceIndex, Nat.not_le_of_lt (by decide : 0 < 1), ↓reduceIte, location]
      exact (native.snapshot.afterHeapReads (by
        intro pointer offset byte loaded
        rw [effect.2.2.2, calleeHeap, Heap.loadByte_borrowBlock]
        exact loaded)).read
    core_pure

@[core_pure_rule] private theorem actualDeclarationUnit (row : DeclarationRow)
    (formed : before.CellsWellFormed) : ∃ after, RunsExpr extractedProgram before
      (.call Extracted.«lowering::declarations».Functions.«row_unit».core.id [.value row.value])
      (.signed .i32 row.unit.toInt) after ∧ PureFrame before after := by
  core_call_pure Extracted.«lowering::declarations».Functions.«row_unit».core as callee
  core_pure

@[core_pure_rule] private theorem actualDeclarationValue (row : DeclarationRow)
    (formed : before.CellsWellFormed) : ∃ after, RunsExpr extractedProgram before
      (.call Extracted.«lowering::declarations».Functions.«row_declaration».core.id [.value row.value])
      (.signed .i32 row.declaration.toInt) after ∧ PureFrame before after := by
  core_call_pure Extracted.«lowering::declarations».Functions.«row_declaration».core as callee
  core_pure

@[core_pure_rule] theorem actualRowUnit (row : AllocationRow) (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before
      (.call Extracted.«lowering::allocation».Functions.«row_unit».core.id [.value row.value])
      (.signed .i32 row.source.unit.toInt) after ∧ PureFrame before after := by
  core_call_pure Extracted.«lowering::allocation».Functions.«row_unit».core as callee
  core_pure

@[core_pure_rule] theorem actualRowDeclaration (row : AllocationRow) (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before
      (.call Extracted.«lowering::allocation».Functions.«row_declaration».core.id [.value row.value])
      (.signed .i32 row.source.declaration.toInt) after ∧ PureFrame before after := by
  core_call_pure Extracted.«lowering::allocation».Functions.«row_declaration».core as callee
  core_pure

@[core_pure_rule] theorem actualRowDeclarationId (row : AllocationRow) (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before
      (.call Extracted.«lowering::allocation».Functions.«row_declaration_id».core.id [.value row.value])
      (.signed .i32 row.declarationId.toInt) after ∧ PureFrame before after := by
  core_call_pure Extracted.«lowering::allocation».Functions.«row_declaration_id».core as callee
  core_pure

@[core_pure_rule] theorem actualRowCoreId (row : AllocationRow) (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before
      (.call Extracted.«lowering::allocation».Functions.«row_core_id».core.id [.value row.value])
      (.signed .i32 row.coreId.toInt) after ∧ PureFrame before after := by
  core_call_pure Extracted.«lowering::allocation».Functions.«row_core_id».core as callee
  core_pure

#print axioms actualHeader
#print axioms actualRowUnit
#print axioms actualRowDeclaration
#print axioms actualRowDeclarationId
#print axioms actualRowCoreId

end IRBodyOwnedInputs
