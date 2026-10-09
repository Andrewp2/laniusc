import verified_compiler.tests.direct_ir_builder

namespace IRBuilderCallProof

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics IRShapeProof IRChildrenProof IRBuilderProof

private def source := Extracted.«ir::body_tree».Functions.«build».core
private def eventType := ((Extracted.«ir::body_tree».Functions.«shape».core.parameters[0]?).getD (0, .unit)).2
private def referenceType := ((Extracted.«ir::type_ref».Functions.«is_invalid».core.parameters[0]?).getD (0, .unit)).2
private def indexId := source.bindingId 3

/-- The represented region keeps its active count separate from its backing
    buffer length. Event reads and classification come from `Source`. -/
structure Region (original : State) extends Source original where
  capacity : Int
  resultAddress : Address
  resultLength : Nat
  hasResultTypes : Bool

def Region.value (region : Region original) : Value := source_value Extracted.«ir::body_events».Types.«Region».mk
  [.rawSlice eventType region.eventsAddress region.eventsLength,
    .rawSlice referenceType region.resultAddress region.resultLength,
    .boolean region.hasResultTypes, .signed .i32 region.capacity]

def Region.tree (region : Region original) (address : Address) : Value :=
  source_value Extracted.«ir::body_tree».Types.«Tree».mk
    [.rawSlice eventType region.eventsAddress region.eventsLength,
      .rawSlice referenceType region.resultAddress region.resultLength,
      .boolean region.hasResultTypes, .rawSlice (.scalar (.signed .i32)) address region.count,
      .signed .i32 region.count]

private def counterScope : Stmt := match source.body.getD .skip with
  | .sequence _ (.letLocal _ _ _ (.sequence _ (.letLocal _ _ _ (.letLocal _ _ _ scope)))) => scope
  | _ => .skip
private def counterBody : Stmt := match counterScope with | .letLocal _ _ _ body => body | _ => .skip
private def rootTail : Stmt := match counterBody with | .sequence _ tail => tail | _ => .skip
private def endsScope : Stmt := match source.body.getD .skip with
  | .sequence _ (.letLocal _ _ _ (.sequence _ scope)) => scope
  | _ => .skip
private def eventsScope : Stmt := match endsScope with | .letLocal _ _ _ body => body | _ => .skip
private def memoryScope : Stmt := match source.body.getD .skip with | .sequence _ scope => scope | _ => .skip
private def memoryBody : Stmt := match memoryScope with | .letLocal _ _ _ body => body | _ => .skip
private def allocationSource := Extracted.«verified::host».Functions.«alloc_i32».core

def StructuralResult (region : Region original) (address : Address) (ends : Nat → Int) (value : Value) : Prop :=
  (value = emptyTree ∧ ((∃ index, index < region.count ∧
    region.toSource.Suffix ends (index + 1) ∧ BadNode region.toSource ends index) ∨
    (region.toSource.Suffix ends 0 ∧ ends 0 ≠ (region.count : Int)))) ∨
  (value = region.tree address ∧ region.toSource.Suffix ends 0 ∧ ends 0 = (region.count : Int))

/-- The actual final root check distinguishes one complete tree from a forest.
    A completed suffix alone is not assumed to be a single-root tree. -/
theorem actualRoot (region : Region original) (context : Context original base)
    (same : context.toSource = region.toSource) (positive : 0 < region.count)
    (frame : Frame context before ends 0)
    (regionFound : base.local? (source.argumentId 0) = some region.value) :
    ∃ value after, RunsStmt extractedProgram before rootTail (.returned (some value)) after ∧
      PureFrame before after ∧ StructuralResult region context.endsAddress ends value := by
  core_facts [context, frame]
  have countSame : context.count = region.count := congrArg Source.count same
  have eventsSame : context.eventsAddress = region.eventsAddress := congrArg Source.eventsAddress same
  have lengthSame : context.eventsLength = region.eventsLength := congrArg Source.eventsLength same
  have formed := frame.cells.after_cellsWellFormed context.formed
  have rootRead := frame.table.endReads 0 (by omega)
  have endsFound : before.local? (source.bindingId 1) = some
      (.rawSlice (.scalar (.signed .i32)) context.endsAddress context.count) := by core_local
  have countFound : before.local? (source.argumentId 1) = some (.signed .i32 context.count) := by core_local
  have resultCount : before.local? (source.argumentId 1) = some (.signed .i32 region.count) := by
    rw [← countSame]; exact countFound
  have resultEnds : before.local? (source.bindingId 1) = some
      (.rawSlice (.scalar (.signed .i32)) context.endsAddress region.count) := by
    rw [← countSame]; exact endsFound
  have sourceFound : before.local? (source.argumentId 0) = some region.value := by core_local
  have eventsFound : before.local? (source.bindingId 2) = some
      (.rawSlice eventType region.eventsAddress region.eventsLength) := by
    rw [← eventsSame, ← lengthSame]; core_local
  have suffix : region.toSource.Suffix ends 0 := by rw [← same]; exact frame.suffix
  have rootValue : StableExpr 2 extractedProgram before
      (.index (.local (source.bindingId 1)) (.value (.signed .i32 0))) (.signed .i32 (ends 0)) before :=
    StableExpr.rawSliceRead (.local endsFound) .value rootRead
  have rootRun := RunsExpr.ofStable rootValue rfl
  by_cases single : ends 0 = (region.count : Int)
  · refine ⟨region.tree context.endsAddress, before, ?_, PureFrame.refl formed, Or.inr ⟨rfl, suffix, single⟩⟩
    core_stmt
  · obtain ⟨after, run, pure⟩ : ∃ after, RunsStmt extractedProgram before rootTail
        (.returned (some emptyTree)) after ∧ PureFrame before after := by core_pure
    exact ⟨emptyTree, after, run, pure, Or.inl ⟨rfl, Or.inr ⟨suffix, single⟩⟩⟩

/-- Compose counter initialization, the proved reverse loop, and the actual
    final return. No successful loop or single-root result is an input premise. -/
theorem actualCounterScope (region : Region original) (context : Context original base)
    (same : context.toSource = region.toSource) (positive : 0 < region.count)
    (table : Table context base (fun _ => 0))
    (regionFound : base.local? (source.argumentId 0) = some region.value) :
    ∃ value after ends, RunsStmt extractedProgram base counterScope (.returned (some value)) after ∧
      FreshCellFrame base after ∧ Table context after ends ∧ after.world = base.world ∧
      StructuralResult region context.endsAddress ends value := by
  have countSame : context.count = region.count := congrArg Source.count same
  core_facts [context]
  have initial : RunsExpr extractedProgram base
      (.binary .subtract (.local (source.argumentId 1)) (.value (.signed .i32 1)))
      (.signed .i32 ((context.count : Int) - 1)) base := by
    have subtraction := eval_i32_subNat extractedProgram.target context.count 1 (by omega) context.fits
    have predecessor : (context.count : Int) - 1 = (context.count - 1 : Nat) := by omega
    rw [predecessor]; core_run
  obtain ⟨completion, finished, ends, remaining, loopRun, frame, result⟩ :=
    actualLoop context (Frame.start context table) (Nat.le_refl _)
  rcases result with ⟨rfl, rfl⟩ | ⟨rfl, index, remaining, inside, bad⟩
  · obtain ⟨value, after, rootRun, pure, structural⟩ := actualRoot region context same positive frame regionFound
    have body : RunsStmt extractedProgram
        (base.bindLocal indexId (.signed .i32 ((context.count : Int) - 1))) counterBody
        (.returned (some value)) after := by core_stmt
    have run := RunsStmt.letLocal (type := .scalar (.signed .i32)) initial body
    refine ⟨value, restoreLocals base after, ends, ?_, (frame.cells.trans pure.cells).restoreLocals,
      (frame.table.transPure pure).restoreLocals base, pure.world.trans frame.world, structural⟩
    · exact run
  · have body : RunsStmt extractedProgram
        (base.bindLocal indexId (.signed .i32 ((context.count : Int) - 1))) counterBody
        (.returned (some emptyTree)) finished := by core_stmt
    refine ⟨emptyTree, restoreLocals base finished, ends,
      RunsStmt.letLocal (type := .scalar (.signed .i32)) initial body,
      frame.cells.restoreLocals, frame.table.restoreLocals base, frame.world,
      Or.inl ⟨rfl, Or.inl ⟨index, by omega, ?_, ?_⟩⟩⟩
    · rw [← same]; simpa only [remaining] using frame.suffix
    · rw [← same]; exact bad

/-- Logical endpoints are connected to the returned table's physical reads. -/
def Stored (region : Region original) (address : Address) (value : Value) (after : State) : Prop :=
  ∃ ends, StructuralResult region address ends value ∧ after.heap.Readable address (region.count * 4) ∧
    ∀ index, index < region.count →
      readRawSliceIndex extractedProgram after (.scalar (.signed .i32)) address region.count index = .ok (.signed .i32 (ends index))

private def PreparedPost (region : Region original) (budget : Option Nat)
    (world : World.State) (value : Value) (after : State) : Prop :=
  HeapReads original.heap after.heap ∧ after.world = world ∧ after.i32ArrayViews = [] ∧
    HeapBlockBasesUnique after.heap ∧ HeapBlocksBelowNext after.heap ∧
    Stored region original.heap.borrowedAddress value after ∧
    HeapRegionWrite (original.heap.appendI32 (List.replicate (region.count * 4) 0) false budget)
      after.heap original.heap.borrowedAddress (region.count * 4)

/-- Borrow fresh storage, bind the actual event slice, and run the builder's
    counter/loop/root scope. Fresh-cell and postcondition restoration is shared. -/
theorem actualEndsScope (region : Region original) (budget : Option Nat)
    (positive : 0 < region.count) (allocated : before.heap = original.heap.allocatedI32 region.count budget)
    (formed : before.CellsWellFormed) (unique : HeapBlockBasesUnique original.heap)
    (views : before.i32ArrayViews = [])
    (memoryFound : before.local? (source.bindingId 0) = some (.pointer original.heap.borrowedAddress))
    (countFound : before.local? (source.argumentId 1) = some (.signed .i32 region.count))
    (regionFound : before.local? (source.argumentId 0) = some region.value) :
    ∃ value after, RunsStmt extractedProgram before endsScope (.returned (some value)) after ∧
      FreshCellFrame before after ∧ PreparedPost region budget before.world value after := by
  let borrowed := { before with heap := original.heap.appendI32 (List.replicate (region.count * 4) 0) false budget }
  let endpoints : Value := .rawSlice (.scalar (.signed .i32)) original.heap.borrowedAddress region.count
  let events : Value := .rawSlice eventType region.eventsAddress region.eventsLength
  let ended := borrowed.bindLocal (source.bindingId 1) endpoints
  let ready := ended.bindLocal (source.bindingId 2) events
  have construct : mapRawI32Slice before original.heap.borrowedAddress region.count = .done endpoints borrowed := by
    simp only [mapRawI32Slice, Int.not_lt_of_ge (Int.natCast_nonneg region.count), ↓reduceIte,
      show (region.count : Int) ≠ 0 by omega, Int.toNat_natCast, allocated,
      Heap.allocatedI32_protect region.below]
    rfl
  have initial : RunsExpr extractedProgram before
      (.i32SliceFromRawParts (.local (source.bindingId 0)) (.local (source.argumentId 1))) endpoints borrowed :=
    RunsExpr.rawSliceFromParts (RunsExpr.ofStable (.local memoryFound) rfl)
      (RunsExpr.ofStable (.local countFound) rfl) construct rfl
  have borrowedFormed : borrowed.CellsWellFormed := formed
  have borrowedCells : FreshCellFrame before borrowed := ⟨[], by simp [borrowed], Nat.le_refl _, by simp⟩
  have endedFormed : ended.CellsWellFormed := by core_formed
  have endedSource : ended.local? (source.argumentId 0) = some region.value := by core_local
  have eventRead : RunsExpr extractedProgram ended (.field (.local (source.argumentId 0)) 0) events ended := by core_run
  let context : Context original ready := {
    toSource := region.toSource, formed := by core_formed
    endsAddress := original.heap.borrowedAddress, fresh := original.heap.borrowedAddress_ge
    eventsFound := by core_local, endsFound := by core_local, countFound := by core_local }
  have table : Table context ready (fun _ => 0) := Table.allocated context rfl rfl unique views
  obtain ⟨value, after, ends, run, cells, table, world, result⟩ :=
    actualCounterScope region context rfl positive table (by core_local)
  have finish : PreparedPost region budget before.world value after :=
    ⟨table.oldReads, world, table.views, table.unique, table.below,
      ⟨ends, result, table.readable, table.endReads⟩, table.writes⟩
  apply RunsStmt.letLocalPost (id := source.bindingId 1) (type := .slice (.scalar (.signed .i32))) initial borrowedCells
  · apply RunsStmt.letLocalPost (id := source.bindingId 2) (type := .slice eventType) eventRead
      (show FreshCellFrame ended ended from ⟨[], by simp, Nat.le_refl _, by simp⟩)
    · exact ⟨value, after, run, cells, finish⟩
    · intro value completed result; exact result
  · intro value completed result; exact result

/-- Allocation failure keeps the old heap. Every allocated branch, including
    structural rejection, retains the allocation metadata and endpoint frame. -/
def BuildPost (region : Region original) (world : World.State) (value : Value) (after : State) : Prop :=
  HeapReads original.heap after.heap ∧ after.world = World.record world .alloc ∧ after.i32ArrayViews = [] ∧
    HeapBlockBasesUnique after.heap ∧ HeapBlocksBelowNext after.heap ∧
    ((value = emptyTree ∧ (IRAllocationProof.allocation original.heap region.count).1 = 0 ∧
      after.heap = original.heap) ∨
      (Stored region original.heap.borrowedAddress value after ∧
        ∃ budget, consumeBudget original.heap.remaining (region.count * 4) = some budget ∧
          HeapRegionWrite (original.heap.appendI32 (List.replicate (region.count * 4) 0) false budget)
            after.heap original.heap.borrowedAddress (region.count * 4)))

theorem actualMemoryScope (region : Region original) (positive : 0 < region.count)
    (bounded : region.count ≤ 536870911) (heapSame : before.heap = original.heap)
    (formed : before.CellsWellFormed) (unique : HeapBlockBasesUnique original.heap)
    (views : before.i32ArrayViews = [])
    (countFound : before.local? (source.argumentId 1) = some (.signed .i32 region.count))
    (regionFound : before.local? (source.argumentId 0) = some region.value) :
    ∃ value after, RunsStmt extractedProgram before memoryScope (.returned (some value)) after ∧
      FreshCellFrame before after ∧ BuildPost region before.world value after := by
  obtain ⟨allocated, allocatedRun, cells, heap, world, noViews⟩ :=
    IRAllocationProof.actualAllocate (before := before) region.count bounded formed views
  have locals := allocatedRun.choose_spec.2
  have allocatedFormed := cells.after_cellsWellFormed formed
  have allocatedCount := cells.localFound locals _ _ countFound
  have allocatedRegion := cells.localFound locals _ _ regionFound
  have initial : RunsExpr extractedProgram before (.call allocationSource.id [.local (source.argumentId 1)])
      (.pointer (IRAllocationProof.allocation original.heap region.count).1) allocated := by
    have call := allocatedRun
    rw [heapSame] at call
    core_run
  apply RunsStmt.letLocalPost (id := source.bindingId 0) (type := .scalar .rawPtr) initial cells
  · cases consumed : consumeBudget original.heap.remaining (region.count * 4) with
    | none =>
        have zero : (IRAllocationProof.allocation original.heap region.count).1 = 0 := by
          simp [IRAllocationProof.allocation, consumed]
        have oldHeap : allocated.heap = original.heap := by
          simpa only [heapSame, IRAllocationProof.allocation, consumed] using heap
        let ready := allocated.bindLocal (source.bindingId 0) (.pointer 0)
        have readyFormed : ready.CellsWellFormed := by core_formed
        have memoryFound : ready.local? (source.bindingId 0) = some (.pointer 0) := by core_local
        have condition : RunsExpr extractedProgram ready
            (.binary .equal (.local (source.bindingId 0)) (.value (.pointer 0))) (.boolean true) ready := by core_run
        obtain ⟨after, emptyRun, pure⟩ := actualEmpty (state := ready) readyFormed
        have run : RunsStmt extractedProgram ready memoryBody (.returned (some emptyTree)) after :=
          RunsStmt.sequenceCompleted (RunsStmt.ifThenElseTrue condition (RunsStmt.returnValue emptyRun)) (by simp) endsScope
        rw [zero]
        refine ⟨emptyTree, after, run, pure.cells, ?_⟩
        exact ⟨by rw [pure.heap]; change HeapReads original.heap allocated.heap; rw [oldHeap]; exact HeapReads.refl _,
          pure.world.trans world, pure.views.trans noViews,
          by rw [pure.heap]; change HeapBlockBasesUnique allocated.heap; rw [oldHeap]; exact unique,
          by rw [pure.heap]; change HeapBlocksBelowNext allocated.heap; rw [oldHeap]; exact region.below,
          Or.inl ⟨rfl, zero, pure.heap.trans oldHeap⟩⟩
    | some budget =>
        have address : (IRAllocationProof.allocation original.heap region.count).1 = original.heap.borrowedAddress := by
          simp [IRAllocationProof.allocation, consumed]
        have allocatedHeap : allocated.heap = original.heap.allocatedI32 region.count budget := by
          simpa only [heapSame, IRAllocationProof.allocation, consumed] using heap
        let ready := allocated.bindLocal (source.bindingId 0) (.pointer original.heap.borrowedAddress)
        have readyFormed : ready.CellsWellFormed := by core_formed
        have memoryFound : ready.local? (source.bindingId 0) = some (.pointer original.heap.borrowedAddress) := by core_local
        have readyCount : ready.local? (source.argumentId 1) = some (.signed .i32 region.count) := by core_local
        have readyRegion : ready.local? (source.argumentId 0) = some region.value := by core_local
        have nonnull : original.heap.borrowedAddress ≠ 0 := Nat.ne_of_gt original.heap.borrowedAddress_pos
        have condition : RunsExpr extractedProgram ready
            (.binary .equal (.local (source.bindingId 0)) (.value (.pointer 0))) (.boolean false) ready := by core_run
        obtain ⟨value, after, run, frame, oldReads, unchangedWorld, unchangedViews, finalUnique, finalBelow, stored, writes⟩ :=
          actualEndsScope (before := ready) region budget positive allocatedHeap readyFormed unique noViews memoryFound readyCount readyRegion
        have body : RunsStmt extractedProgram ready memoryBody (.returned (some value)) after := by core_stmt
        rw [address]
        exact ⟨value, after, body, frame, oldReads, unchangedWorld.trans world,
          unchangedViews, finalUnique, finalBelow, Or.inr ⟨stored, budget, consumed, writes⟩⟩
  · intro value completed result; exact result

def Region.call (region : Region original) (count : Int := region.count) : Expr :=
  .call source.id [.value region.value, .value (.signed .i32 count)]

/-- The entry guard rejects without touching the backing buffers or allocator. -/
theorem actualEntryReject (region : Region original) (count : Int)
    (bad : count ≤ 0 ∨ region.capacity < count) (formed : original.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram original (region.call count) emptyTree after ∧ PureFrame original after := by
  core_call_pure source as callee
  core_pure

/-- The complete builder call, including allocation exhaustion and malformed
    structure, for a nonempty region within the allocator's representable size. -/
theorem actualBuild (region : Region original) (positive : 0 < region.count)
    (capacity : (region.count : Int) ≤ region.capacity) (bounded : region.count ≤ 536870911)
    (formed : original.CellsWellFormed) (unique : HeapBlockBasesUnique original.heap)
    (views : original.i32ArrayViews = []) :
    ∃ value after, RunsExpr extractedProgram original (region.call) value after ∧
      FreshCellFrame original after ∧ BuildPost region original.world value after := by
  apply RunsExpr.callPost (function := source) (values := [region.value, .signed .i32 region.count])
    (bindings := [(source.argumentId 0, region.value), (source.argumentId 1, .signed .i32 region.count)])
    (by core_lookup) rfl rfl
  · let callee := ({ original with locals := [] }).bindLocals
      [(source.argumentId 0, region.value), (source.argumentId 1, .signed .i32 region.count)]
    have calleeFormed : callee.CellsWellFormed := by core_formed
    have countFound : callee.local? (source.argumentId 1) = some (.signed .i32 region.count) := by core_local
    have regionFound : callee.local? (source.argumentId 0) = some region.value := by core_local
    obtain ⟨value, after, run, cells, post⟩ := actualMemoryScope (before := callee) region positive bounded rfl calleeFormed unique views countFound regionFound
    refine ⟨value, after, ?_, cells, post⟩
    core_stmt
  · intro value completed result; exact result

/-- An oversized count rejects through the real wrapper (or the earlier entry
    guard), without calling the allocator or accessing backing events. -/
theorem actualSizeReject (region : Region original) (oversized : 536870911 < region.count)
    (formed : original.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram original (region.call) emptyTree after ∧ PureFrame original after := by
  have badWords : (region.count : Int) < 0 ∨ 536870911 < (region.count : Int) := Or.inr (by omega)
  core_call_pure source as callee
  by_cases capacity : (region.count : Int) ≤ region.capacity
  · have positive : 0 < region.count := by omega
    core_pure
  · have badEntry : region.capacity < (region.count : Int) := by omega
    core_pure

def BoundsRejected (region : Region original) : Prop :=
  region.count = 0 ∨ region.capacity < (region.count : Int) ∨ 536870911 < region.count

/-- Total correctness of the complete call over every represented natural
    count: entry/size rejection is pure; allocation and structural results are
    explicit, and successful trees retain the table's physical interpretation. -/
theorem actualCall (region : Region original) (formed : original.CellsWellFormed)
    (unique : HeapBlockBasesUnique original.heap) (views : original.i32ArrayViews = []) :
    ∃ value after, RunsExpr extractedProgram original region.call value after ∧ FreshCellFrame original after ∧
      ((value = emptyTree ∧ BoundsRejected region ∧ PureFrame original after) ∨
        BuildPost region original.world value after) := by
  by_cases empty : region.count = 0
  · obtain ⟨after, run, pure⟩ := actualEntryReject region region.count (Or.inl (by omega)) formed
    exact ⟨emptyTree, after, run, pure.cells, Or.inl ⟨rfl, Or.inl empty, pure⟩⟩
  by_cases capacity : (region.count : Int) ≤ region.capacity
  · by_cases size : region.count ≤ 536870911
    · obtain ⟨value, after, run, cells, result⟩ := actualBuild region (by omega) capacity size formed unique views
      exact ⟨value, after, run, cells, Or.inr result⟩
    · obtain ⟨after, run, pure⟩ := actualSizeReject region (by omega) formed
      exact ⟨emptyTree, after, run, pure.cells, Or.inl ⟨rfl, Or.inr (Or.inr (by omega)), pure⟩⟩
  · obtain ⟨after, run, pure⟩ := actualEntryReject region region.count (Or.inr (by omega)) formed
    exact ⟨emptyTree, after, run, pure.cells, Or.inl ⟨rfl, Or.inr (Or.inl (by omega)), pure⟩⟩

#print axioms actualRoot
#print axioms actualCounterScope
#print axioms actualEndsScope
#print axioms actualMemoryScope
#print axioms actualEntryReject
#print axioms actualBuild
#print axioms actualSizeReject
#print axioms actualCall

end IRBuilderCallProof
