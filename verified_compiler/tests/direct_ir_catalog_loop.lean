import verified_compiler.tests.direct_ir_catalog_copy
import verified_compiler.tests.direct_ir_catalog_slots
import verified_compiler.tests.direct_ir_catalog_prefix
import Lanius.Semantics.LoopRun

namespace IRCatalogCopyProof
open Lanius Lanius.Core Lanius.Memory Lanius.Semantics IREventStoreProof

theorem actualEvent (input : Input original) (slot : Context before)
    (inside : slot.position < input.count) (reads : HeapReads original.heap before.heap)
    (destination : before.local? (source.bindingId 8) =
      some (.rawSlice eventType slot.events slot.capacity))
    (sourceEvents : before.local? (source.bindingId 2) =
      some (.rawSlice eventType input.eventsAddress input.eventsLength))
    (counter : before.local? (source.bindingId 11) = some (.signed .i32 slot.position))
    (unique : HeapBlockBasesUnique before.heap) (noViews : before.i32ArrayViews = []) :
    ∃ heap, RunsExpr extractedProgram before (source.effectExpression 1) .unit { before with heap } ∧
      NativeSnapshot 64 extractedProgram heap eventType slot.eventBase (input.events slot.position) 40 ∧
      HeapRegionWrite before.heap heap slot.eventBase 40 := by
  exact RunsExpr.assignRawNative (before := before) (indexed := before) (ready := before)
    destination (.ofStable (.local counter) rfl) slot.bound
    slot.eventLocation (input.codec inside) slot.eventRoom unique noViews
    (.ofStable (.rawSliceIndex sourceEvents counter (reads.rawSlice (input.reads _ inside))) rfl)

def annotationStep : Stmt := match (source.whileLoop 1).2 with
  | .sequence _ (.sequence branch _) => branch
  | _ => .skip
private def annotationRight (enabled : Bool) : Expr :=
  match source.effectExpression (if enabled then 2 else 3) with
  | .assign _ _ right => right | _ => .value .unit
theorem actualBodyShape : (source.whileLoop 1).2 = .sequence (.expression (source.effectExpression 1))
    (.sequence annotationStep (.sequence (.expression (source.effectExpression 4)) .skip)) := by rfl

theorem actualAnnotation (input : Input original) (slot : IRResultTypeProof.Slot before)
    (enabled : slot.enabled = true) (inside : slot.position < input.count) (reads : HeapReads original.heap before.heap)
    (sourceRegion : before.local? (source.argumentId 2) = some input.value)
    (destination : before.local? (source.bindingId 9) = some (.rawSlice referenceType slot.types slot.typesLength))
    (sourceTypes : before.local? (source.bindingId 10) =
      some (.rawSlice referenceType input.resultAddress input.resultLength))
    (counter : before.local? (source.bindingId 11) = some (.signed .i32 slot.position))
    (unique : HeapBlockBasesUnique before.heap) (noViews : before.i32ArrayViews = []) :
    ∃ heap, RunsStmt extractedProgram before annotationStep .next { before with heap } ∧
      NativeSnapshot 64 extractedProgram heap referenceType slot.address (input.annotation slot.position) 16 ∧
      HeapRegionWrite before.heap heap slot.address 16 := by
  have codec : NativeStoreSpec 64 extractedProgram referenceType (input.annotation slot.position) 16 := by
    cases flag : input.hasResultTypes <;> simp only [Input.annotation, flag, ↓reduceIte]
    · exact invalidCodec
    · exact IRResultTypeProof.referenceCodec _
  have right : RunsExpr extractedProgram before (annotationRight input.hasResultTypes)
      (input.annotation slot.position) before := by
    cases flag : input.hasResultTypes <;> simp only [annotationRight, Input.annotation, flag, ↓reduceIte]
    · core_run
    · exact .ofStable (.rawSliceIndex sourceTypes counter
        (reads.rawSlice (input.annotationReads flag _ inside))) rfl
  have guard : RunsExpr extractedProgram before (.field (.local (source.argumentId 2)) 2)
      (.boolean input.hasResultTypes) before := by core_run
  obtain ⟨heap, store, snapshot, effect⟩ := RunsExpr.assignRawNative
    (before := before) (indexed := before) (ready := before) destination
    (.ofStable (.local counter) rfl) (slot.typeBound enabled) (slot.location enabled)
    codec (slot.room enabled) unique noViews right
  refine ⟨heap, ?_, snapshot, effect⟩
  cases flag : input.hasResultTypes <;> simp only [flag] at guard store <;> core_stmt

/-- The fresh counter, copied prefix and untouched source evolve together. -/
structure Frame (input : Input original) (budget : Option Nat) (base current : State) (copied : Nat) : Prop where
  counter : CountedLocal base current (source.bindingId 11) copied
  buffer : Buffer input current.heap copied
  reads : HeapReads original.heap current.heap
  writes : HeapRegionWrite (input.freshHeap budget) current.heap input.memory (input.count * 56)
  world : current.world = base.world
  views : current.i32ArrayViews = base.i32ArrayViews

theorem Frame.start (seed : Seed input budget base) :
    Frame input budget base (base.bindLocal (source.bindingId 11) (.signed .i32 0)) 0 := by
  refine ⟨CountedLocal.start seed.formed _ _, ?_, seed.reads, ?_, rfl, rfl⟩
  · change Buffer input base.heap 0
    rw [seed.heap]
    exact Buffer.seed input budget input.below
  · change HeapRegionWrite (input.freshHeap budget) base.heap _ _
    rw [← seed.heap]
    exact HeapRegionWrite.refl _ seed.unique

theorem actualIteration {original : State} {input : Input original}
    (seed : Seed input budget base) (frame : Frame input budget base before position)
    (inside : position < input.count) (fits : input.count * 56 < 2 ^ 31) :
    ∃ after, RunsStmt extractedProgram before (source.whileLoop 1).2 .next after ∧
      Frame input budget base after (position + 1) := by
  let slot := frame.buffer.slot inside fits
  have events := frame.counter.read _ _ (by decide) seed.events
  have sourceEvents := frame.counter.read _ _ (by decide) seed.sourceEvents
  have counter := frame.counter.counter
  have noViews := frame.views.trans seed.noViews
  obtain ⟨eventHeap, eventRun, eventSnapshot, eventWrite⟩ := actualEvent input slot inside frame.reads
    events sourceEvents counter frame.writes.unique noViews
  change HeapRegionWrite before.heap eventHeap (input.eventBase position) 40 at eventWrite
  let written := { before with heap := eventHeap }
  let typeSlot : IRResultTypeProof.Slot written := {
    position, capacity := input.count, enabled := true, typesLength := input.count
    types := input.typePointer, address := input.typeBase position
    bound := inside, typeBound := fun _ => inside, location := fun _ => input.typeLocation inside
    room := fun _ => eventWrite.readable _ _ (slot.typeRoom rfl) }
  have sourceRegion : written.local? (source.argumentId 2) = some input.value :=
    frame.counter.read _ _ (by decide) seed.sourceFound
  have types : written.local? (source.bindingId 9) = some (.rawSlice referenceType slot.types slot.capacity) :=
    frame.counter.read _ _ (by decide) seed.types
  have sourceTypes : written.local? (source.bindingId 10) =
      some (.rawSlice referenceType input.resultAddress input.resultLength) :=
    frame.counter.read _ _ (by decide) seed.sourceTypes
  have fresh : original.heap.nextAddress ≤ input.memory := original.heap.allocationAddress_ge (by decide : 0 < 8)
  have writtenReads : HeapReads original.heap written.heap := frame.reads.writeRegionFresh input.below
    (Nat.le_trans fresh (Nat.le_add_right _ _)) eventWrite
  obtain ⟨typeHeap, typeRun, typeSnapshot, typeWrite⟩ := actualAnnotation input typeSlot rfl inside writtenReads
    sourceRegion types sourceTypes counter eventWrite.unique noViews
  change HeapRegionWrite eventHeap typeHeap (input.typeBase position) 16 at typeWrite
  let annotated := { before with heap := typeHeap }
  have retained : FreshCellFrame before annotated := ⟨[], by simp [annotated], Nat.le_refl _, by simp⟩
  have counted := frame.counter.transCells retained rfl
  obtain ⟨after, increment, counterNext, sameHeap, sameWorld, sameViews⟩ := counted.increment
    (program := extractedProgram) seed.formed (by have := input.fits; omega)
  have pair := frame.buffer.afterPair inside eventSnapshot eventWrite typeSnapshot typeWrite
  have pairWrite : HeapRegionWrite before.heap typeHeap input.memory (input.count * 56) :=
    (eventWrite.enlarge (by dsimp only [Input.eventBase]; omega)
      (by dsimp only [Input.eventBase]; omega)).trans
    (typeWrite.enlarge (by dsimp only [Input.typeBase]; omega) (by dsimp only [Input.typeBase]; omega))
  refine ⟨after, ?_, counterNext, ?_, ?_, ?_, sameWorld.trans frame.world, sameViews.trans frame.views⟩
  · rw [actualBodyShape]
    core_stmt
  · rw [sameHeap]; exact pair
  · rw [sameHeap]
    exact writtenReads.writeRegionFresh input.below
      (Nat.le_trans fresh (Nat.le_trans (Nat.le_add_right _ _) (Nat.le_add_right _ _))) typeWrite
  · rw [sameHeap]
    exact frame.writes.trans pairWrite

theorem actualLoop (seed : Seed input budget base) (fits : input.count * 56 < 2 ^ 31) :
    ∃ after, RunsStmt extractedProgram (base.bindLocal (source.bindingId 11) (.signed .i32 0))
      (.whileLoop (source.whileLoop 1).1 (source.whileLoop 1).2) .next after ∧
      Frame input budget base after input.count := by
  let invariant := fun remaining current => ∃ position, position + remaining = input.count ∧
    Frame input budget base current position
  apply RunsStmt.whileCount (remaining := input.count) invariant
  · intro current initial
    obtain ⟨position, progress, frame⟩ := initial
    have equal : position = input.count := by omega
    subst position
    have countFound := frame.counter.read _ _ (by decide) seed.countFound
    have indexFound := frame.counter.counter
    exact ⟨current, by core_run, frame⟩
  · intro remaining current initial
    obtain ⟨position, progress, frame⟩ := initial
    have inside : position < input.count := by omega
    have countFound := frame.counter.read _ _ (by decide) seed.countFound
    have indexFound := frame.counter.counter
    obtain ⟨after, iteration, next⟩ := actualIteration seed frame inside fits
    exact ⟨current, after, .next, by core_run, iteration, Or.inl rfl, position + 1, by omega, next⟩
  · exact ⟨0, by omega, Frame.start seed⟩

/-- At count, both tables become the original events and enabled annotations.
    This constructs the builder's Region and caller locals at the open cut. -/
theorem Frame.cutState (seed : Seed input budget base) (frame : Frame input budget base state input.count) :
    CutState input budget state := by
  exact {
    cells := seed.cells.trans frame.counter.cells
    callerCells := by
      intro id member
      have excluded : source.bindingId 11 ∉ callerIds := by decide +kernel
      have different : source.bindingId 11 ≠ id := fun same => excluded (same.symm ▸ member)
      simpa [State.cellId?, frame.counter.locals, different] using seed.callerCells id member
    reads := frame.reads, writes := frame.writes
    world := frame.world.trans seed.world, views := frame.views.trans seed.views
    below := frame.writes.below (by rw [← seed.heap]; exact seed.below)
    eventSnapshots := by
      intro index inside
      exact frame.buffer.events index inside
    typeSnapshots := by
      intro index inside
      exact frame.buffer.types index inside
    owned := frame.counter.read _ _ (by decide) seed.owned
    countFound := frame.counter.read _ _ (by decide) seed.countFound }

/-- Total allocation and copying, composed with a separately proved tail. The
    tail receives the derived live cut-state, never assumed prefix success. -/
theorem actualAllocationCopy (input : Input original) (budget : Option Nat) (suffix : Stmt)
    (positive : 0 < input.count) (fits : input.count * 56 < 2 ^ 31)
    (pointerFits : input.memory + input.count * 56 < 2 ^ 64)
    (sourceFound : original.local? (source.argumentId 2) = some input.value)
    (sourceEvents : original.local? (source.bindingId 2) =
      some (.rawSlice eventType input.eventsAddress input.eventsLength))
    (countFound : original.local? (source.argumentId 3) = some (.signed .i32 input.count))
    (available : consumeBudget original.heap.remaining (input.count * 56) = some budget)
    (formed : original.CellsWellFormed) (unique : HeapBlockBasesUnique original.heap)
    (noViews : original.i32ArrayViews = []) (Q : Completion → State → Prop)
    (tailContract : ∀ state, CutState input budget state → ∃ completion after,
      RunsStmt extractedProgram state suffix completion after ∧ Q completion (restoreLocals original after)) :
    ∃ completion after, RunsStmt extractedProgram original («prefix» suffix) completion after ∧ Q completion after := by
  apply allocatedContinue input budget suffix positive fits pointerFits sourceFound sourceEvents countFound
    available formed unique noViews Q
  intro base seed
  obtain ⟨reached, loopRun, frame⟩ := actualLoop seed fits
  obtain ⟨completion, after, tailRun, post⟩ := tailContract reached (frame.cutState seed)
  exact ⟨completion, after, RunsStmt.sequenceNext loopRun tailRun, post⟩

#print axioms actualLoop
#print axioms Frame.cutState
#print axioms actualAllocationCopy
end IRCatalogCopyProof
