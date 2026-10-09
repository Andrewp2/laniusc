import verified_compiler.tests.direct_ir_catalog_append_scan

namespace IRCatalogAppendProof

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics IRTypeRefProof
open IRCatalogBuildProof IRBuilderCallProof IRBuilderNavigationProof

/-- Only the original locals actually consumed by the remaining source. -/
structure StageBindings (input : Arguments) (state : State) : Prop where
  signature : state.local? (source.argumentId 1) = some input.signature
  region : state.local? (source.argumentId 2) = some input.region
  eventCount : state.local? (source.argumentId 3) = some (.signed .i32 input.eventCount.toInt)
  count : state.local? (source.bindingId 0) = some input.count
  rows : state.local? (source.bindingId 1) = some input.rows
  events : state.local? (source.bindingId 2) = some (.rawSlice eventType input.eventsAddress input.eventsLength)
  next : state.local? (source.bindingId 3) = some (.signed .i32 input.next.toInt)

theorem StageBindings.afterScan (bindings : StageBindings input base) (frame : CallerFrame base after)
    (locals : after.locals = (base.bindLocal priorId (.signed .i32 0)).locals) : StageBindings input after := by
  have retained : ∀ id value, id ≠ priorId → base.local? id = some value → after.local? id = some value := by
    intro id value different found
    apply frame.cells.localFoundAt ?_ value found
    simpa only [State.cellId?, locals] using
      State.bindLocal_cellId_of_ne base id priorId (Ne.symm different) (.signed .i32 0)
  exact ⟨retained _ _ (by decide +kernel) bindings.signature,
    retained _ _ (by decide +kernel) bindings.region, retained _ _ (by decide +kernel) bindings.eventCount,
    retained _ _ (by decide +kernel) bindings.count, retained _ _ (by decide +kernel) bindings.rows,
    retained _ _ (by decide +kernel) bindings.events, retained _ _ (by decide +kernel) bindings.next⟩

theorem Arguments.requested (input : Arguments) (guarded : input.Guarded) :
    input.eventCount.toInt = (input.request : Int) := by
  have positive := guarded.2.2.2.2.2.1
  dsimp only [Arguments.request]
  omega

theorem Arguments.occupiedValue (input : Arguments) (guarded : input.Guarded) :
    input.next.toInt = (input.occupied : Int) := by
  have nonnegative := guarded.2.2.2.1
  dsimp only [Arguments.occupied]
  omega

def Input.buildEntry (input : Input caller) (active : input.CopyNeeded caller.heap)
    (frame : CallerFrame caller state) (bindings : StageBindings input.toArguments state)
    (available : consumeBudget caller.heap.remaining (input.request * 56) = some budget) :
    IRCatalogBuildProof.Entry (input.copyInput active state frame.heap) budget := {
  positive := active.2.2.1.1
  fits := by change input.request * 56 < 2 ^ 31; have upper := active.2.2.1.2; omega
  pointerFits := by change state.heap.allocationAddress 8 + input.request * 56 < 2 ^ 64; rw [frame.heap]; exact input.freshFits active
  sourceFound := by change state.local? (source.argumentId 2) = some input.region; exact bindings.region
  sourceEvents := bindings.events
  countFound := by
    change state.local? (source.argumentId 3) = some (.signed .i32 input.request)
    simpa only [input.toArguments.requested active.1] using bindings.eventCount
  available := by
    change consumeBudget state.heap.remaining (input.request * 56) = some budget
    simpa only [frame.heap] using available
  formed := frame.currentFormed
  unique := by rw [frame.heap]; exact input.unique
  noViews := frame.views.trans input.noViews }

/-- A derived live tree proves independent shape and resources before any
    success-only catalog storage is requested. -/
theorem Input.liveSuccess (input : Input caller) (active : input.CopyNeeded caller.heap)
    (frame : CallerFrame caller state) (bindings : StageBindings input.toArguments state)
    (available : consumeBudget caller.heap.remaining (input.request * 56) = some budget)
    (live : Live (input.copyInput active state frame.heap) budget current) : input.Success caller.heap := by
  let entry := input.buildEntry active frame bindings available
  obtain ⟨copied, cut, post⟩ := live.memory.allocation
  rcases post.2.2.2.2.2 with failed | ⟨_, second, remaining, _⟩
  · exact False.elim (IRCatalogStoreProof.nonempty entry live failed.1)
  · refine ⟨active.1, active.2.1, active.2.2.1, ⟨budget, second, available, ?_⟩,
      live.tree.ends, ?_, live.tree.root⟩
    · simpa only [IRCatalogCopyProof.CutState.region, Input.copyInput, cut.writes.budget,
        IRCatalogCopyProof.Input.freshHeap, Heap.borrowBlock, Heap.allocatedBytes] using remaining
    · intro index inside
      exact live.tree.suffix index (Nat.zero_le _) inside

/-- Original independent success excludes either endpoint exhaustion or
    structural rejection, using the existing builder exclusion proof once. -/
theorem Input.rejectionNotSuccess (input : Input caller) (active : input.CopyNeeded caller.heap)
    (frame : CallerFrame caller state) (bindings : StageBindings input.toArguments state)
    (available : consumeBudget caller.heap.remaining (input.request * 56) = some budget)
    (memory : Memory (input.copyInput active state frame.heap) budget IRBuilderProof.emptyTree current) :
    ¬input.Success caller.heap := by
  rintro ⟨_, _, _, ⟨first, second, firstBudget, secondBudget⟩, ends, shape, root⟩
  have same : first = budget := Option.some.inj (firstBudget.symm.trans available)
  subst first
  exact IRCatalogStoreProof.rejectImpossible (input.buildEntry active frame bindings available)
    ((input.copySuffix active frame.heap).mpr shape) root
    (by change consumeBudget budget (input.request * 4) ≠ none; rw [secondBudget]; intro empty; cases empty) memory

/-- The full store entry is derived only after live success establishes the
    original-data success predicate and activates its write geometry. -/
def Input.storeEntry (input : Input caller) (active : input.CopyNeeded caller.heap)
    (frame : CallerFrame caller state) (bindings : StageBindings input.toArguments state)
    (available : consumeBudget caller.heap.remaining (input.request * 56) = some budget)
    (successful : input.Success caller.heap) :
    IRCatalogStoreProof.Entry (input.copyInput active state frame.heap) budget := by
  let geometry := input.geometry successful
  have nextNonnegative := active.1.2.2.2.1
  have nextCapacity := active.1.2.2.2.2.1
  have capacityBound := input.capacity.toInt_lt
  have nextNat := input.toArguments.occupiedValue active.1
  have countBound : 0 < input.countLength := by
    have read := input.countRead
    by_cases bound : 0 < input.countLength
    · exact bound
    have outside : input.countLength ≤ 0 := by omega
    simp only [Arguments.CountRead, readRawSliceIndex, if_pos outside] at read
    cases read
  exact {
    build := input.buildEntry active frame bindings available
    id := input.id, parameters := input.parameters, result := input.result
    next := input.occupied, rowsAddress := input.rowsAddress, rowsLength := input.rowsLength
    countAddress := input.countAddress, countLength := input.countLength
    incrementFits := by omega
    rowBound := geometry.rowBound, rowFloor := geometry.rowFloor, countBound
    rowRoom := by rw [frame.heap]; exact geometry.rowRoom
    countRoom := by rw [frame.heap]; exact geometry.countRoom
    separate := geometry.separate
    signatureFound := bindings.signature
    rowsFound := bindings.rows
    countFound := bindings.count
    nextFound := by
      change state.local? (source.bindingId 3) = some (.signed .i32 input.occupied)
      simpa only [nextNat] using bindings.next }

#print axioms Input.liveSuccess
#print axioms Input.rejectionNotSuccess

end IRCatalogAppendProof
