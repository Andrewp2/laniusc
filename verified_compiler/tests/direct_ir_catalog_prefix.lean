import verified_compiler.tests.direct_ir_catalog_copy
namespace IRCatalogCopyProof
open Lanius Lanius.Core Lanius.Memory Lanius.Semantics IRRegionAllocationProof

def rejection (index : Nat) : Stmt := match source.bindingStatement index with
  | .letLocal _ _ _ (.sequence guard _) => guard
  | _ => .skip

theorem actualMemoryGuard (heap : Heap)
    (memory : before.local? (source.bindingId 6) = some (.pointer (heap.allocationAddress 8))) :
    RunsStmt extractedProgram before (rejection 6) .next before := by
  have positive := heap.allocationAddress_pos (by decide : 0 < 8)
  core_stmt

theorem actualBytesGuard (count : Nat) (positive : 0 < count)
    (bytes : before.local? (source.bindingId 5) = some (.signed .i32 (count * 56 : Nat))) :
    RunsStmt extractedProgram before (rejection 5) .next before := by
  core_stmt

private theorem callerCell {id : VarId} (run : InitializersRun before after count memory)
    (notBytes : source.bindingId 5 ≠ id) (notMemory : source.bindingId 6 ≠ id) :
    after.cellId? id = before.cellId? id := by
  obtain ⟨sized, allocated, sizing, allocation, construction⟩ := run
  have builtLocals : after.locals = (allocated.bindLocal (source.bindingId 6) (.pointer memory)).locals :=
    construction.choose_spec.2
  have allocatedLocals : allocated.locals =
      (sized.bindLocal (source.bindingId 5) (.signed .i32 (count * 56 : Nat))).locals := allocation.choose_spec.2
  simp [State.cellId?, builtLocals, State.bindLocal, State.bindCell,
    allocatedLocals, sizing.choose_spec.2, notBytes, notMemory]

private theorem callerLocal {id : VarId} (run : InitializersRun before after count memory)
    (cells : FreshCellFrame before after)
    (notBytes : source.bindingId 5 ≠ id) (notMemory : source.bindingId 6 ≠ id)
    (found : before.local? id = some value) : after.local? id = some value :=
  cells.localFoundAt (callerCell run notBytes notMemory) value found

/-- The remaining executable statement is precisely the actual copy loop followed
    by the supplied tail. The live descriptor/index scopes are not closed here. -/
def loopSuffix (suffix : Stmt) : Stmt :=
  .sequence (.whileLoop (source.whileLoop 1).1 (source.whileLoop 1).2) suffix

/-- Execute every allocation/guard/descriptor initializer from caller facts.
    Only the loop and tail are delegated; all seven actual lexical scopes close
    around their completion. In particular the callback does not assume CutState. -/
theorem allocatedContinue (input : Input original) (budget : Option Nat) (suffix : Stmt)
    (positive : 0 < input.count) (fits : input.count * 56 < 2 ^ 31)
    (pointerFits : input.memory + input.count * 56 < 2 ^ 64)
    (sourceFound : original.local? (source.argumentId 2) = some input.value)
    (sourceEvents : original.local? (source.bindingId 2) =
      some (.rawSlice IREventStoreProof.eventType input.eventsAddress input.eventsLength))
    (countFound : original.local? (source.argumentId 3) = some (.signed .i32 input.count))
    (available : consumeBudget original.heap.remaining (input.count * 56) = some budget)
    (formed : original.CellsWellFormed) (unique : HeapBlockBasesUnique original.heap)
    (noViews : original.i32ArrayViews = []) (Q : Completion → State → Prop)
    (continuation : ∀ base, Seed input budget base → ∃ completion after,
      RunsStmt extractedProgram (base.bindLocal (source.bindingId 11) (.signed .i32 0))
        (loopSuffix suffix) completion after ∧ Q completion (restoreLocals original after)) :
    ∃ completion after, RunsStmt extractedProgram original («prefix» suffix)
      completion after ∧ Q completion after := by
  obtain ⟨constructed, initializers, cells, world, views, heap, reads, newUnique, below, initialized⟩ :=
    actualOwned input.count positive fits pointerFits countFound available formed input.below unique noViews
  have inheritedSource := callerLocal initializers cells (by decide) (by decide) sourceFound
  have inheritedEvents := callerLocal initializers cells (by decide) (by decide) sourceEvents
  have inheritedCount := callerLocal initializers cells (by decide) (by decide) countFound
  have separate : ∀ id ∈ callerIds, ∀ index ∈ [5, 6, 7, 8, 9, 10], source.bindingId index ≠ id := by
    decide +kernel
  have inheritedCells : ∀ id ∈ callerIds, constructed.cellId? id = original.cellId? id := by
    intro id member
    exact callerCell initializers (separate id member 5 (by simp)) (separate id member 6 (by simp))
  obtain ⟨sized, allocated, sizing, allocation, construction⟩ := initializers
  let prepared := sized.bindLocal (source.bindingId 5) (.signed .i32 (input.count * 56 : Nat))
  let memoryBound := allocated.bindLocal (source.bindingId 6) (.pointer input.memory)
  let owned := constructed.bindLocal (source.bindingId 7) (regionValue input.memory input.count)
  let events := owned.bindLocal (source.bindingId 8)
    (.rawSlice IREventStoreProof.eventType input.eventPointer input.count)
  let types := events.bindLocal (source.bindingId 9)
    (.rawSlice IREventStoreProof.referenceType input.typePointer input.count)
  let base := types.bindLocal (source.bindingId 10)
    (.rawSlice IREventStoreProof.referenceType input.resultAddress input.resultLength)
  have sizedFormed := sizing.cellsWellFormed formed
  have allocatedFormed := allocation.cellsWellFormed (by core_formed)
  have constructedFormed := cells.after_cellsWellFormed formed
  have ownedFormed : owned.CellsWellFormed := by core_formed
  have eventsFormed : events.CellsWellFormed := by core_formed
  have typesFormed : types.CellsWellFormed := by core_formed
  have baseFormed : base.CellsWellFormed := by core_formed
  have bytes : prepared.local? (source.bindingId 5) =
      some (.signed .i32 (input.count * 56 : Nat)) := by core_local
  have memory : memoryBound.local? (source.bindingId 6) = some (.pointer input.memory) := by core_local
  have bytesGuard := actualBytesGuard input.count positive bytes
  have memoryGuard := actualMemoryGuard original.heap memory
  have ownedFound : owned.local? (source.bindingId 7) = some (regionValue input.memory input.count) := by core_local
  have sourceInTypes : types.local? (source.argumentId 2) = some input.value := by core_local
  have eventsRead : RunsExpr extractedProgram owned (source.bindingInitializer 8)
      (.rawSlice IREventStoreProof.eventType input.eventPointer input.count) owned := by core_run
  have typesRead : RunsExpr extractedProgram events (source.bindingInitializer 9)
      (.rawSlice IREventStoreProof.referenceType input.typePointer input.count) events := by core_run
  have sourceTypesRead : RunsExpr extractedProgram types (source.bindingInitializer 10)
      (.rawSlice IREventStoreProof.referenceType input.resultAddress input.resultLength) types := by core_run
  have indexRead : RunsExpr extractedProgram base (source.bindingInitializer 11) (.signed .i32 0) base := by core_run
  have seed : Seed input budget base := {
    formed := baseFormed
    cells := (((cells.trans (FreshCellFrame.bindLocal constructed _ _)).trans
      (FreshCellFrame.bindLocal owned _ _)).trans (FreshCellFrame.bindLocal events _ _)).trans
      (FreshCellFrame.bindLocal types _ _)
    callerCells := by
      intro id member
      dsimp only [base, types, events, owned]
      rw [State.bindLocal_cellId_of_ne _ _ _ (separate id member 10 (by simp)),
        State.bindLocal_cellId_of_ne _ _ _ (separate id member 9 (by simp)),
        State.bindLocal_cellId_of_ne _ _ _ (separate id member 8 (by simp)),
        State.bindLocal_cellId_of_ne _ _ _ (separate id member 7 (by simp))]
      exact inheritedCells id member
    reads := reads, heap := heap, unique := newUnique, below := below
    world := world, views := views, noViews := views.trans noViews
    sourceFound := by core_local
    sourceEvents := by core_local
    countFound := by core_local
    owned := by core_local
    events := by core_local
    types := by core_local
    sourceTypes := by core_local }
  obtain ⟨completion, after, loopRun, post⟩ := continuation base seed
  have run : RunsStmt extractedProgram original («prefix» suffix) completion
      (restoreLocals sized (restoreLocals allocated (restoreLocals constructed
        (restoreLocals owned (restoreLocals events (restoreLocals types (restoreLocals base after))))))) := by
    exact RunsStmt.letLocal sizing (RunsStmt.sequenceNext bytesGuard
      (RunsStmt.letLocal allocation (RunsStmt.sequenceNext memoryGuard
        (RunsStmt.letLocal construction (RunsStmt.letLocal eventsRead
          (RunsStmt.letLocal typesRead (RunsStmt.letLocal sourceTypesRead
            (RunsStmt.letLocal indexRead loopRun))))))))
  exact ⟨completion, restoreLocals original after,
    by simpa only [restoreLocals, sizing.choose_spec.2] using run, post⟩

#print axioms allocatedContinue
end IRCatalogCopyProof
