import SelfCore
import Lanius.Core.Bindings
import Lanius.Memory.Allocation
import Lanius.Semantics.HostCall
import Lanius.Semantics.CallProof
import Lanius.Semantics.PureProof
import Lanius.Semantics.RawSlice
import Lanius.Semantics.RawStore
import Lanius.Semantics.ScopedEffect
import Lanius.Extraction.OutputPacking.Byte

namespace IRAllocationProof

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics

private def source := Extracted.«verified::host».Functions.«alloc_i32».core
private def host := Extracted.«verified::host».Functions.«alloc».core
private def sizeId := source.bindingId 0
private def alignId := source.bindingId 1
private def sliceSource := Extracted.«verified::host».Functions.«i32_slice_from_raw_parts».core
private def builder := Extracted.«ir::body_tree».Functions.«build».core

/-- Budget exhaustion is part of the result, not excluded from the input domain. -/
def allocation (heap : Heap) (words : Nat) : Address × Heap :=
  match consumeBudget heap.remaining (words * 4) with
  | none => (0, heap)
  | some budget => (heap.borrowedAddress, heap.allocatedI32 words budget)

private theorem hostValues (words : Nat) (noViews : before.i32ArrayViews = []) :
    RunsExpr extractedProgram before (.call host.id
      [.value (.unsigned .usize (words * 4)), .value (.unsigned .usize 4)])
      (.pointer (allocation before.heap words).1)
      { before with heap := (allocation before.heap words).2, world := World.record before.world .alloc } := by
  apply RunsExpr.hostCall (function := host)
    (values := [.unsigned .usize (words * 4), .unsigned .usize 4])
    (bindings := [(host.argumentId 0, .unsigned .usize (words * 4)), (host.argumentId 1, .unsigned .usize 4)])
    (by core_lookup) rfl rfl rfl noViews
  cases budget : consumeBudget before.heap.remaining (words * 4) <;>
    simp only [World.call, World.callSimple, Heap.allocate_i32, allocation, budget, null]

/-- Actual self-extracted allocation wrapper, including overflow rejection's
    complementary safe domain and the real host-call effects. -/
theorem actualAllocate (words : Nat) (bounded : words ≤ 536870911)
    (formed : before.CellsWellFormed) (noViews : before.i32ArrayViews = []) :
    ∃ after, RunsExpr extractedProgram before (.call source.id [.value (.signed .i32 words)])
      (.pointer (allocation before.heap words).1) after ∧
      FreshCellFrame before after ∧
      after.heap = (allocation before.heap words).2 ∧
      after.world = World.record before.world .alloc ∧ after.i32ArrayViews = [] := by
  core_call_framed (RunsExpr.callStores (fun heap world views =>
    heap = (allocation before.heap words).2 ∧
    world = World.record before.world .alloc ∧ views = [])) source as callee
  let sized := callee.bindLocal sizeId (.unsigned .usize (words * 4))
  let ready := sized.bindLocal alignId (.unsigned .usize 4)
  have cast := eval_unsigned_castNat extractedProgram.target .usize .i32 words
    (by change words < 18446744073709551616; omega)
  have castFour := eval_unsigned_castNat extractedProgram.target .usize .i32 4 (by decide)
  have multiply := eval_unsigned_mulNat extractedProgram.target .usize words 4
    (by change words * 4 < 18446744073709551616; omega)
  have readyFormed : ready.CellsWellFormed := by core_formed
  have sizeFound : ready.local? sizeId = some (.unsigned .usize (words * 4)) := by core_local
  have alignFound : ready.local? alignId = some (.unsigned .usize 4) := by core_local
  have called := hostValues (before := ready) words (by exact noViews)
  let completed := { ready with
    locals := callee.locals
    heap := (allocation before.heap words).2
    world := World.record before.world .alloc }
  exact ⟨completed, by core_stmt,
    (FreshCellFrame.bindLocal callee sizeId (.unsigned .usize (words * 4))).trans
      (FreshCellFrame.bindLocal sized alignId (.unsigned .usize 4)), rfl, rfl, noViews⟩

@[core_pure_rule] theorem actualReject (words : Int) (bad : words < 0 ∨ 536870911 < words)
    (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before (.call source.id [.value (.signed .i32 words)])
      (.pointer 0) after ∧ PureFrame before after := by
  core_call_pure source as callee
  core_pure

/-- The source constructor protects the fresh allocation without copying it.
    Readability and old reads then follow from the shared append-storage rules. -/
theorem actualSlice (heap : Heap) (words : Nat) (budget : Option Nat) (positive : 0 < words)
    (allocated : before.heap = heap.allocatedI32 words budget)
    (below : HeapBlocksBelowNext heap) (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before (.call sliceSource.id
        [.value (.pointer heap.borrowedAddress), .value (.signed .i32 words)])
      (.rawSlice (.scalar (.signed .i32)) heap.borrowedAddress words) after ∧
      MemoryEffect (fun _ result => result = heap.appendI32 (List.replicate (words * 4) 0) false budget) before after := by
  core_call_framed (RunsExpr.callEffect (MemoryEffect.scopeStable _)) sliceSource as callee
  refine ⟨{ callee with heap := heap.appendI32 (List.replicate (words * 4) 0) false budget },
    RunsStmt.returnValue (RunsExpr.allocatedI32Slice (by core_run) (by core_run) allocated positive below),
    (CallerFrame.refl (by core_formed)).cells, rfl, rfl, rfl⟩

theorem actualEmptySlice (address : Nat) (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before (.call sliceSource.id
      [.value (.pointer address), .value (.signed .i32 0)])
      (.rawSlice (.scalar (.signed .i32)) address 0) after ∧ PureFrame before after := by
  core_call_pure sliceSource as callee
  core_pure

/-- The extractor's two real scratch setup calls establish a usable descriptor.
    Available budget is a numeric resource bound, not allocator success.
    This route uses raw buffers, so it has no cell-backed registrations. -/
theorem actualScratch (words : Nat) (positive : 0 < words) (bounded : words ≤ 536870911)
    (formed : before.CellsWellFormed) (ready : before.I32ViewsReady extractedProgram types)
    (noViews : before.i32ArrayViews = [])
    (capacity : ∀ available, before.heap.remaining = some available → words * 4 ≤ available) :
    ∃ allocated after,
      RunsExpr extractedProgram before (.call source.id [.value (.signed .i32 words)])
        (.pointer before.heap.borrowedAddress) allocated ∧
      RunsExpr extractedProgram allocated (.call sliceSource.id
        [.value (.pointer before.heap.borrowedAddress), .value (.signed .i32 words)])
        (.rawSlice (.scalar (.signed .i32)) before.heap.borrowedAddress words) after ∧
      FreshCellFrame before after ∧ after.locals = before.locals ∧
      after.I32ViewsReady extractedProgram types ∧
      I32SliceValid extractedProgram types after
        (.rawSlice (.scalar (.signed .i32)) before.heap.borrowedAddress words) words ∧
      HeapReads before.heap after.heap ∧ after.world = World.record before.world .alloc ∧
      after.i32ArrayViews = [] := by
  let budget := before.heap.remaining.map (fun available => available - words * 4)
  have available := consumeBudget_of_capacity capacity
  obtain ⟨allocated, allocate, cells, heap, world, views⟩ := actualAllocate words bounded formed noViews
  have allocatedHeap : allocated.heap = before.heap.allocatedI32 words budget := by
    simpa only [allocation, available] using heap
  obtain ⟨after, construct, borrowedCells, borrowedWorld, borrowedViews, borrowedHeap⟩ :=
    actualSlice before.heap words budget positive allocatedHeap ready.below (cells.after_cellsWellFormed formed)
  have framed := cells.trans borrowedCells
  have reads : HeapReads before.heap after.heap := by rw [borrowedHeap]; exact .appendI32
  have finalReady := ready.retained framed reads
    (by rw [borrowedHeap]; exact Heap.appendI32_unique ready.below ready.unique)
    (by rw [borrowedHeap]; exact Heap.appendI32_below ready.below)
    (borrowedViews.trans (views.trans noViews.symm))
  refine ⟨allocated, after, ?_, construct, framed, construct.choose_spec.2.trans allocate.choose_spec.2,
    finalReady, .raw ?_, reads,
    borrowedWorld.trans world, borrowedViews.trans views⟩
  · simpa only [allocation, available] using allocate
  · rw [borrowedHeap]
    simpa only [List.length_replicate] using Heap.appendI32_readable (bytes := List.replicate (words * 4) 0)
      (owned := false) (budget := budget) ready.below

/-- The builder's real `ends[index] = cursor` expression writes one endpoint.
    Every different entry (in particular the completed suffix) is preserved. -/
theorem actualEndpointStore (count index cursor address : Nat)
    (inside : index < count) (fits : cursor < 2 ^ 31)
    (endsFound : before.local? (builder.bindingId 1) = some (.rawSlice (.scalar (.signed .i32)) address count))
    (indexFound : before.local? (builder.bindingId 3) = some (.signed .i32 index))
    (cursorFound : before.local? (builder.bindingId 5) = some (.signed .i32 cursor))
    (readable : before.heap.Readable address (count * 4))
    (unique : HeapBlockBasesUnique before.heap) (noViews : before.i32ArrayViews = []) :
    ∃ heap, RunsExpr extractedProgram before (builder.effectExpression 0) .unit { before with heap } ∧
      BytesWrite before.heap heap (address + index * 4) (i32Bytes cursor) ∧
      heap.Readable address (count * 4) ∧
      readRawSliceIndex extractedProgram { before with heap } (.scalar (.signed .i32)) address count index =
        .ok (.signed .i32 cursor) ∧
      ∀ position, position < count → position ≠ index → ∀ bytes,
        before.heap.loadBytes (address + position * 4) 4 = .ok bytes →
        heap.loadBytes (address + position * 4) 4 = .ok bytes := by
  obtain ⟨heap, run, written⟩ := RunsExpr.assignRawI32 (program := extractedProgram)
    (expression := .local (builder.bindingId 5))
    endsFound (.ofStable (.local indexFound) rfl) inside (readable.subrange (by omega)) unique noViews (by core_run)
  have length : (i32Bytes (cursor : Int)).length = 4 := by simp [i32Bytes]
  refine ⟨heap, run, written, written.readable readable,
    Extraction.OutputPacking.readRawSliceIndex_i32Nat _ _ cursor fits inside ?_, ?_⟩
  · simpa only [length] using written.loadBytes
  · intro position bounded different bytes loaded
    apply written.loadBytes_disjoint loaded
    rw [length]
    dsimp only [Address]
    omega

#print axioms actualAllocate
#print axioms actualReject
#print axioms actualSlice
#print axioms actualEmptySlice
#print axioms actualScratch
#print axioms actualEndpointStore

end IRAllocationProof
