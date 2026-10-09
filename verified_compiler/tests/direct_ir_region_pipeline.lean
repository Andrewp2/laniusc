import verified_compiler.tests.direct_ir_region_allocation
import verified_compiler.tests.direct_ir_result_type

namespace IRRegionPipelineProof

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics IRRegionProof IREventStoreProof
  IRRegionAllocationProof IRTypeRefProof

/-- Derive a writer's slot from the actual fresh allocation, not a successful
    previous write or a prebuilt descriptor. All padding is readable as well. -/
def allocatedContext (original : Heap) (count position : Nat) (budget : Option Nat)
    (inside : position < count) (fits : count * 56 < 2 ^ 31) (below : HeapBlocksBelowNext original)
    (heapIs : state.heap = (original.allocatedBytes (count * 56) 8 budget).borrowBlock
      (original.allocationAddress 8)) : Context state := by
  let base := original.allocationAddress 8
  let eventBase := base + (count - position - 1) * 40
  let typeBase := base + count * 40 + (count - position - 1) * 16
  have zeros : ∀ offset width, offset + width ≤ count * 56 →
      state.heap.loadBytes (base + offset) width = .ok (List.replicate width 0) := by
    intro offset width room
    rw [heapIs, Heap.loadBytes_borrowBlock]
    exact original.allocatedBytes_zeroRange below (by decide) room
  exact {
    position, capacity := count, events := base + count * 40 - 8, types := base + count * 56 - 8
    eventBase, typeBase, bound := inside, fits := by omega
    eventLocation := by
      apply rawSliceElementAddress_of_layout (words := 5) rfl (by decide +kernel) (by decide)
      · dsimp only [eventBase, base]; omega
      · dsimp only [eventBase, base]; omega
    typeLocation := by
      apply rawSliceElementAddress_of_layout (words := 2) rfl (by decide +kernel) (by decide)
      · dsimp only [typeBase, base]; omega
      · dsimp only [typeBase, base]; omega
    eventRoom := Heap.Readable.of_loadBytes (zeros _ 40 (by omega))
    typeRoom := Heap.Readable.of_loadBytes (by
      simpa only [typeBase, Nat.add_assoc] using zeros (count * 40 + (count - position - 1) * 16) 16 (by omega))
    separate := Or.inl (by dsimp only [eventBase, typeBase]; omega) }

def appendCall (memory count position : Nat) (event : Value) : Expr :=
  appendProducer event (regionValue memory count) position
def recordCall (memory count position : Nat) (kind : Reference) : Expr :=
  IRResultTypeProof.call (.rawSlice eventType (memory + count * 40 - 8) count)
    (.rawSlice referenceType (memory + count * 56 - 8) count) true count position kind

/-- Allocate, construct, run a proved producer and record its result type.
    Internal storage facts are derived, not passed in by the frontend. -/
theorem actualAllocateProduceRecord (count position : Nat) (inside : position < count)
    (fits : count * 56 < 2 ^ 31) (pointerFits : before.heap.allocationAddress 8 + count * 56 < 2 ^ 64)
    (capacity : before.local? (Extracted.«ir::body_catalog».Functions.«append».core.argumentId 3) =
      some (.signed .i32 count))
    (available : consumeBudget before.heap.remaining (count * 56) = some budget)
    (formed : before.CellsWellFormed) (below : HeapBlocksBelowNext before.heap)
    (unique : HeapBlockBasesUnique before.heap) (noViews : before.i32ArrayViews = [])
    (event : Value) (producer : Value → Int → Expr) (produces : Produces producer event)
    (kind : Reference) (valid : 0 ≤ typeCode kind) :
    ∃ ready written after,
      InitializersRun before ready count (before.heap.allocationAddress 8) ∧
      RunsExpr extractedProgram ready (producer (regionValue (before.heap.allocationAddress 8) count) position)
        (.signed .i32 (position + 1 : Nat)) written ∧
      RunsExpr extractedProgram written (recordCall (before.heap.allocationAddress 8) count position kind)
        (.boolean true) after ∧ FreshCellFrame before after ∧
      after.world = World.record before.world .alloc ∧ after.i32ArrayViews = before.i32ArrayViews ∧
      HeapReads before.heap after.heap ∧
      NativeSnapshot 64 extractedProgram after.heap eventType
        (before.heap.allocationAddress 8 + (count - position - 1) * 40) event 40 ∧
      NativeSnapshot 64 extractedProgram after.heap referenceType
        (before.heap.allocationAddress 8 + count * 40 + (count - position - 1) * 16) (referenceValue kind) 16 := by
  obtain ⟨ready, allocation, cells, world, views, heap, reads, readyUnique, _, _⟩ :=
    actualOwned count (by omega) fits pointerFits capacity available formed below unique noViews
  let context := allocatedContext before.heap count position budget inside fits below heap
  have readyFormed := cells.after_cellsWellFormed formed
  obtain ⟨written, append, writtenCells, writtenWorld, writtenViews, event, annotation, middle, first, second⟩ :=
    produces context readyFormed readyUnique (views.trans noViews)
  let slot : IRResultTypeProof.Slot written := {
    position, capacity := count, types := context.types, address := context.typeBase, bound := inside
    location := context.typeLocation
    room := second.readable _ _ (first.readable _ _ context.typeRoom) }
  obtain ⟨after, record, finalCells, finalWorld, finalViews, result, effect⟩ :=
    IRResultTypeProof.actualRecord (events := .rawSlice eventType context.events count) slot kind valid
      (writtenCells.after_cellsWellFormed readyFormed) second.unique (writtenViews.trans (views.trans noViews))
  have fresh := before.heap.allocationAddress_ge (alignment := 8) (by decide)
  have eventFresh : before.heap.nextAddress ≤ context.eventBase := by
    change before.heap.nextAddress ≤ before.heap.allocationAddress 8 + (count - position - 1) * 40
    dsimp only [Lanius.Address] at fresh ⊢
    omega
  have typeFresh : before.heap.nextAddress ≤ context.typeBase := by
    change before.heap.nextAddress ≤ before.heap.allocationAddress 8 + count * 40 + (count - position - 1) * 16
    dsimp only [Lanius.Address] at fresh ⊢
    omega
  exact ⟨ready, written, after, allocation, append, record, cells.trans (writtenCells.trans finalCells),
    finalWorld.trans (writtenWorld.trans world), finalViews.trans (writtenViews.trans views),
    ((reads.writeRegionFresh below eventFresh first).writeRegionFresh below typeFresh second).writeRegionFresh
      below typeFresh effect,
    event.afterWrite effect context.separate, result⟩

#print axioms actualAllocateProduceRecord

end IRRegionPipelineProof
