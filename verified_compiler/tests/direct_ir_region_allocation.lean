import verified_compiler.tests.direct_ir_region
import Lanius.Memory.Allocated
import Lanius.Semantics.HostCall
import Lanius.Semantics.NativeReadFrame

namespace IRRegionAllocationProof

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics IRRegionProof IREventStoreProof

private def catalog := Extracted.«ir::body_catalog».Functions.«append».core
private def allocator := Extracted.«verified::host».Functions.«alloc».core
private def sizeSource := Extracted.«ir::body_events».Functions.«allocation_bytes».core

def regionValue (memory count : Nat) : Value :=
  source_value Extracted.«ir::body_events».Types.«Region».mk
    [.rawSlice eventType (memory + count * 40 - 8) count,
      .rawSlice referenceType (memory + count * 56 - 8) count, .boolean true, .signed .i32 count]

/-- Execution of the three real initializers and their local bindings.
    This is a proof contract, not another emitted program representation. -/
def InitializersRun (before after : State) (count memory : Nat) : Prop :=
  ∃ sized allocated,
    RunsExpr extractedProgram before (catalog.bindingInitializer 5) (.signed .i32 (count * 56 : Nat)) sized ∧
    RunsExpr extractedProgram (sized.bindLocal (catalog.bindingId 5) (.signed .i32 (count * 56 : Nat)))
      (catalog.bindingInitializer 6) (.pointer memory) allocated ∧
    RunsExpr extractedProgram (allocated.bindLocal (catalog.bindingId 6) (.pointer memory))
      (catalog.bindingInitializer 7) (regionValue memory count) after

/-- Actual size calculation, with an explicit representable positive domain. -/
theorem actualSize (count : Nat) (positive : 0 < count) (fits : count * 56 < 2 ^ 31)
    (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before (.call sizeSource.id [.value (.signed .i32 count)])
      (.signed .i32 (count * 56 : Nat)) after ∧ PureFrame before after := by
  core_call_pure sizeSource as callee
  core_pure

theorem actualSizeReject (count : Int) (bad : count ≤ 0 ∨ 38347922 < count)
    (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before (.call sizeSource.id [.value (.signed .i32 count)])
      (.signed .i32 (-1)) after ∧ PureFrame before after := by
  core_call_pure sizeSource as callee
  core_pure

/-- The caller's real size initializer uses the proved helper, not an
    independently computed byte count assumed by the allocation contract. -/
theorem actualBytes (count : Nat) (positive : 0 < count) (fits : count * 56 < 2 ^ 31)
    (capacity : before.local? (catalog.argumentId 3) = some (.signed .i32 count))
    (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before (catalog.bindingInitializer 5)
      (.signed .i32 (count * 56 : Nat)) after ∧ PureFrame before after := by
  apply RunsExpr.callPureArguments (values := [.signed .i32 count]) (before := before)
  · core_arguments
  · exact actualSize count positive fits formed

/-- All constructor input facts follow from the allocator's actual fresh
    block. No descriptor construction or successful store is assumed. -/
def freshRegion (count : Nat) (budget : Option Nat)
    (allocated : state.heap = heap.allocatedBytes (count * 56) 8 budget)
    (positive : 0 < count) (fits : count * 56 < 2 ^ 31)
    (pointerFits : heap.allocationAddress 8 + count * 56 < 2 ^ 64)
    (below : HeapBlocksBelowNext heap) : FreshRegion state := {
  memory := heap.allocationAddress 8, count, block := heap.allocationBlock (count * 56) 8
  positive, bytesFit := fits, pointerFit := pointerFits
  aligned := heap.allocationAddress_aligned
  eventBlock := by
    rw [allocated]
    simpa only [Nat.add_zero] using heap.allocatedBytes_containing (budget := budget) below (by decide)
      (by omega : 0 < count * 56)
  typeBlock := by
    rw [allocated]
    exact heap.allocatedBytes_containing below (by decide) (by omega : count * 40 < count * 56)
  alignment := by change 8 ≤ 8; decide
  bounds := Nat.le_refl _
  readable := by
    rw [allocated]
    apply Heap.Readable.of_loadBytes
    simpa only [Nat.add_zero] using heap.allocatedBytes_zeroRange (budget := budget) below (by decide)
      (by omega : 0 + count * 56 ≤ count * 56)
  zero := by
    intro position inside
    rw [allocated]
    simpa only [Nat.add_assoc, show encodeNatLE 4 0 = List.replicate 4 (0 : UInt8) from rfl] using
      heap.allocatedBytes_zeroRange (budget := budget) below (by decide)
        (by omega : count * 40 + (count - position - 1) * 16 + 4 ≤ count * 56) }

private theorem hostAllocate (size : Nat) (available : consumeBudget before.heap.remaining size = some budget)
    (noViews : before.i32ArrayViews = []) :
    RunsExpr extractedProgram before (.call allocator.id
      [.value (.unsigned .usize size), .value (.unsigned .usize 8)])
      (.pointer (before.heap.allocationAddress 8))
      { before with heap := before.heap.allocatedBytes size 8 budget, world := World.record before.world .alloc } := by
  apply RunsExpr.hostCall (function := allocator) (values := [.unsigned .usize size, .unsigned .usize 8])
    (bindings := [(allocator.argumentId 0, .unsigned .usize size), (allocator.argumentId 1, .unsigned .usize 8)])
    (by core_lookup) rfl rfl rfl noViews
  have allocated := Heap.allocate_of_budget (alignment := 8) (by decide) available
  simp only [World.call, World.callSimple, allocated]

private theorem hostExhausted (size : Nat) (exhausted : consumeBudget before.heap.remaining size = none)
    (noViews : before.i32ArrayViews = []) :
    RunsExpr extractedProgram before (.call allocator.id
      [.value (.unsigned .usize size), .value (.unsigned .usize 8)]) (.pointer 0)
      { before with world := World.record before.world .alloc } := by
  apply RunsExpr.hostCall (function := allocator) (values := [.unsigned .usize size, .unsigned .usize 8])
    (bindings := [(allocator.argumentId 0, .unsigned .usize size), (allocator.argumentId 1, .unsigned .usize 8)])
    (by core_lookup) rfl rfl rfl noViews
  simp only [World.call, World.callSimple, Heap.allocate, show validAlignment 8 = true from rfl,
    Bool.not_true, Bool.false_eq_true, ↓reduceIte, exhausted, null]

/-- The real catalog initializer, including its signed-to-usize arguments. -/
theorem actualMemory (count : Nat) (fits : count * 56 < 2 ^ 31)
    (bytes : before.local? (catalog.bindingId 5) = some (.signed .i32 (count * 56 : Nat)))
    (available : consumeBudget before.heap.remaining (count * 56) = some budget)
    (noViews : before.i32ArrayViews = []) :
    RunsExpr extractedProgram before (catalog.bindingInitializer 6) (.pointer (before.heap.allocationAddress 8))
      { before with heap := before.heap.allocatedBytes (count * 56) 8 budget, world := World.record before.world .alloc } := by
  have cast := eval_unsigned_castNat extractedProgram.target .usize .i32 (count * 56) (by
    change count * 56 < 2 ^ 64; omega)
  have alignment := eval_unsigned_castNat extractedProgram.target .usize .i32 8 (by decide)
  exact RunsExpr.callArguments (by core_arguments) (hostAllocate (count * 56) available noViews)

theorem actualMemoryExhausted (count : Nat) (fits : count * 56 < 2 ^ 31)
    (bytes : before.local? (catalog.bindingId 5) = some (.signed .i32 (count * 56 : Nat)))
    (exhausted : consumeBudget before.heap.remaining (count * 56) = none)
    (noViews : before.i32ArrayViews = []) :
    RunsExpr extractedProgram before (catalog.bindingInitializer 6) (.pointer 0)
      { before with world := World.record before.world .alloc } := by
  have cast := eval_unsigned_castNat extractedProgram.target .usize .i32 (count * 56) (by
    change count * 56 < 2 ^ 64; omega)
  have alignment := eval_unsigned_castNat extractedProgram.target .usize .i32 8 (by decide)
  exact RunsExpr.callArguments (by core_arguments) (hostExhausted (count * 56) exhausted noViews)

/-- Connect all three actual catalog initializers: compute the byte count,
    allocate, then construct a region with no assumed internal memory facts. -/
theorem actualOwned (count : Nat) (positive : 0 < count) (fits : count * 56 < 2 ^ 31)
    (pointerFits : before.heap.allocationAddress 8 + count * 56 < 2 ^ 64)
    (capacity : before.local? (catalog.argumentId 3) = some (.signed .i32 count))
    (available : consumeBudget before.heap.remaining (count * 56) = some budget)
    (formed : before.CellsWellFormed) (below : HeapBlocksBelowNext before.heap)
    (unique : HeapBlockBasesUnique before.heap) (noViews : before.i32ArrayViews = []) :
    ∃ after, InitializersRun before after count (before.heap.allocationAddress 8) ∧ FreshCellFrame before after ∧
      after.world = World.record before.world .alloc ∧ after.i32ArrayViews = before.i32ArrayViews ∧
      after.heap = (before.heap.allocatedBytes (count * 56) 8 budget).borrowBlock (before.heap.allocationAddress 8) ∧
      HeapReads before.heap after.heap ∧ HeapBlockBasesUnique after.heap ∧ HeapBlocksBelowNext after.heap ∧
      ∀ position, position < count → NativeSnapshot 64 extractedProgram after.heap referenceType
        (before.heap.allocationAddress 8 + count * 40 + (count - position - 1) * 16) invalid 16 := by
  obtain ⟨sized, sizing, frame⟩ := actualBytes count positive fits capacity formed
  let prepared := sized.bindLocal (catalog.bindingId 5) (.signed .i32 (count * 56 : Nat))
  let allocated := { prepared with
    heap := prepared.heap.allocatedBytes (count * 56) 8 budget
    world := World.record prepared.world .alloc }
  let ready := allocated.bindLocal (catalog.bindingId 6) (.pointer (prepared.heap.allocationAddress 8))
  have sizedFormed := frame.afterFormed
  have preparedFormed : prepared.CellsWellFormed := by core_formed
  have sameHeap : prepared.heap = before.heap := frame.heap
  have preparedBelow : HeapBlocksBelowNext prepared.heap := by rw [sameHeap]; exact below
  have preparedUnique : HeapBlockBasesUnique prepared.heap := by rw [sameHeap]; exact unique
  have preparedViews : prepared.i32ArrayViews = [] := frame.views.trans noViews
  have budgetReady : consumeBudget prepared.heap.remaining (count * 56) = some budget := by rw [sameHeap]; exact available
  have space : prepared.heap.allocationAddress 8 + count * 56 < 2 ^ 64 := by rw [sameHeap]; exact pointerFits
  let input := freshRegion count budget (state := ready) (heap := prepared.heap) rfl positive fits space preparedBelow
  have sizedCapacity := frame.localFound capacity
  have readyFormed : ready.CellsWellFormed := by core_formed
  have capacityFound : ready.local? (catalog.argumentId 3) = some (.signed .i32 count) := by core_local
  have readyUnique : HeapBlockBasesUnique ready.heap := prepared.heap.allocatedBytes_unique preparedBelow preparedUnique (by decide)
  obtain ⟨after, constructed, cells, world, views, heap, initialized⟩ := actualRegion input readyFormed readyUnique preparedViews
  have owned : RunsExpr extractedProgram ready (catalog.bindingInitializer 7) input.value after :=
    RunsExpr.callArguments (by core_arguments) constructed
  have bytes : prepared.local? (catalog.bindingId 5) = some (.signed .i32 (count * 56 : Nat)) := by core_local
  have oldCells := frame.cells.trans (FreshCellFrame.bindLocal sized (catalog.bindingId 5) (.signed .i32 (count * 56 : Nat)))
  have finalWorld : after.world = World.record before.world .alloc := by
    change after.world = World.record sized.world .alloc at world
    rw [frame.world] at world
    exact world
  have memoryIs : input.memory = before.heap.allocationAddress 8 := by
    change prepared.heap.allocationAddress 8 = before.heap.allocationAddress 8
    rw [sameHeap]
  have valueIs : input.value = regionValue (before.heap.allocationAddress 8) count := by
    dsimp only [FreshRegion.value, FreshRegion.eventPointer, FreshRegion.typePointer, FreshRegion.typeBase,
      regionValue]
    rw [memoryIs, show input.count = count from rfl,
      show count * 56 = count * 40 + count * 16 by omega]
    simp only [Nat.add_assoc]
  have finalHeap : after.heap = (before.heap.allocatedBytes (count * 56) 8 budget).borrowBlock
      (before.heap.allocationAddress 8) := by
    change after.heap = (prepared.heap.allocatedBytes (count * 56) 8 budget).borrowBlock
      (prepared.heap.allocationAddress 8) at heap
    rwa [sameHeap] at heap
  have memoryRun := actualMemory count fits bytes budgetReady preparedViews
  refine ⟨after, ⟨sized, allocated, sizing, ?_, ?_⟩,
    oldCells.trans ((FreshCellFrame.bindLocal allocated (catalog.bindingId 6) (.pointer input.memory)).trans cells),
    finalWorld, views.trans frame.views, finalHeap, ?_, ?_, ?_, ?_⟩
  · change RunsExpr _ prepared _ _ allocated
    rw [← memoryIs]
    exact memoryRun
  · change RunsExpr _ (allocated.bindLocal (catalog.bindingId 6) (.pointer input.memory)) _ input.value after at owned
    simpa only [memoryIs, valueIs] using owned
  · intro pointer offset byte read
    rw [heap, Heap.loadByte_borrowBlock]
    apply Heap.allocatedBytes_oldRead
    rw [sameHeap]; exact read
  · rw [heap]; exact readyUnique.borrowBlock
  · rw [heap]; exact (prepared.heap.allocatedBytes_below preparedBelow (by decide)).borrowBlock
  · intro position inside
    simpa only [FreshRegion.typeBase, show input.count = count from rfl, memoryIs] using initialized position inside

#print axioms actualSize
#print axioms actualSizeReject
#print axioms actualBytes
#print axioms actualMemory
#print axioms actualMemoryExhausted
#print axioms actualOwned

end IRRegionAllocationProof
