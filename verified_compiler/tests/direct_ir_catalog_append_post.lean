import verified_compiler.tests.direct_ir_catalog_append_stage

namespace IRCatalogAppendProof

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics IRTypeRefProof
open IRCatalogBuildProof IRBuilderCallProof IRBuilderNavigationProof

/-- Bytes may change in the proved slots; allocation identity does not. -/
def Metadata (expected actual : Heap) : Prop :=
  actual.nextAddress = expected.nextAddress ∧ actual.remaining = expected.remaining ∧
    actual.blocks.map (fun block => { block with bytes := [] }) =
      expected.blocks.map (fun block => { block with bytes := [] })

private theorem Metadata.trans (first : Metadata before middle) (second : Metadata middle after) :
    Metadata before after := ⟨second.1.trans first.1, second.2.1.trans first.2.1, second.2.2.trans first.2.2⟩

private theorem Metadata.append (same : Metadata before after) (bytes : List UInt8) (budget : Option Nat) :
    Metadata (before.appendI32 bytes false budget) (after.appendI32 bytes false budget) := by
  rcases same with ⟨frontier, remaining, layout⟩
  have address : after.borrowedAddress = before.borrowedAddress := by
    simp only [Heap.borrowedAddress, frontier]
  simp only [Metadata, Heap.appendI32, address, List.map_append, List.map_cons, List.map_nil, layout, true_and]

def Arguments.firstHeap (input : Arguments) (heap : Heap) (budget : Option Nat) : Heap :=
  (heap.allocatedBytes (input.request * 56) 8 budget).borrowBlock (heap.allocationAddress 8)

/-- Rejection after copying does not roll back either allocation. -/
noncomputable def Model.expectedHeap (input : Model) (heap : Heap) : Heap := by
  classical
  exact if input.Guarded ∧ ¬input.Duplicate ∧ input.Sized then
    match consumeBudget heap.remaining (input.request * 56) with
    | none => heap
    | some first => match consumeBudget first (input.request * 4) with
      | none => input.firstHeap heap first
      | some second => (input.firstHeap heap first).appendI32 (List.replicate (input.request * 4) 0) false second
  else heap

/-- Allocation attempts are observable even when allocation or validation
    rejects: pure rejection makes none, first exhaustion one, and copying two. -/
noncomputable def Model.expectedWorld (input : Model) (heap : Heap) (world : World.State) : World.State := by
  classical
  exact if input.Guarded ∧ ¬input.Duplicate ∧ input.Sized then
    match consumeBudget heap.remaining (input.request * 56) with
    | none => World.record world .alloc
    | some _ => World.record (World.record world .alloc) .alloc
  else world

noncomputable def Model.answer (input : Model) (heap : Heap) : Int := by
  classical
  exact if input.Success heap then input.next.toInt else -1

def Arguments.copiedTree (input : Arguments) (heap : Heap) : Value :=
  let memory := heap.allocationAddress 8
  IRValidatorProof.treeValue
    (.rawSlice eventType (memory + input.request * 40 - 8) input.request)
    (.rawSlice referenceType (memory + input.request * 56 - 8) input.request) true
    (.rawSlice (.scalar (.signed .i32)) (memory + input.request * 56) input.request) input.request

def Model.annotation (input : Model) (index : Nat) : Value :=
  if input.hasResultTypes then referenceValue (input.annotations index) else IREventStoreProof.invalid

def Model.CopiedStorage (input : Model) (original heap : Heap) : Prop :=
  (∀ index, index < input.request → readRawSliceIndex extractedProgram { heap := heap } eventType
    (original.allocationAddress 8 + input.request * 40 - 8) input.request index = .ok (input.events index)) ∧
  ∀ index, index < input.request → readRawSliceIndex extractedProgram { heap := heap } referenceType
    (original.allocationAddress 8 + input.request * 56 - 8) input.request index = .ok (input.annotation index)

def Model.SuccessStorage (input : Model) (original heap : Heap) : Prop :=
  NativeSnapshot 64 extractedProgram heap bodyType (input.rowBase input.occupied)
    (IRCatalogStoreProof.body input.signature (input.copiedTree original)) 96 ∧
  readNativeValue 64 extractedProgram heap (.scalar (.signed .i32)) input.countAddress =
    .ok (.signed .i32 (input.next.toInt + 1)) ∧
  ∃ ends, (∀ index, index < input.request → input.Node ends index) ∧ ends 0 = (input.request : Int) ∧
    ∀ index, index < input.request → readRawSliceIndex extractedProgram { heap := heap }
      (.scalar (.signed .i32)) (original.allocationAddress 8 + input.request * 56) input.request index =
        .ok (.signed .i32 (ends index))

/-- Observable postcondition, independent of temporary locals/cell IDs. -/
structure Post (input : Model) (caller : State) (result : Int) (heap : Heap)
    (world : World.State) (views : List I32ArrayView) : Prop where
  returned : result = input.answer caller.heap
  metadata : Metadata (input.expectedHeap caller.heap) heap
  unique : HeapBlockBasesUnique heap
  readable : ∀ pointer width, caller.heap.Readable pointer width → heap.Readable pointer width
  outside : ∀ pointer offset byte, caller.heap.loadByte pointer offset = .ok byte →
    ¬(input.Success caller.heap ∧ input.footprint (pointer + offset)) → heap.loadByte pointer offset = .ok byte
  occupied : input.Guarded → ∀ index, index < input.occupied →
    NativeSnapshot 64 extractedProgram heap bodyType (input.rowBase index) (input.previous index).value 96
  rejectedCount : ¬input.Success caller.heap → input.toArguments.CountRead { caller with heap }
  copied : input.CopyNeeded caller.heap → input.CopiedStorage caller.heap heap
  stored : input.Success caller.heap → input.SuccessStorage caller.heap heap
  worldFrame : world = input.expectedWorld caller.heap caller.world
  viewsFrame : views = caller.i32ArrayViews

/-- Pure argument preparation changes no observable input projection of Post. -/
theorem Post.reanchorPure (post : Post input after result heap world views)
    (frame : PureFrame before after) : Post input before result heap world views := by
  have sameHeap := frame.heap
  have sameWorld := frame.world
  have sameViews := frame.views
  cases before
  cases after
  cases sameHeap
  cases sameWorld
  cases sameViews
  exact ⟨post.returned, post.metadata, post.unique, post.readable, post.outside,
    post.occupied, post.rejectedCount, post.copied, post.stored, post.worldFrame, post.viewsFrame⟩

/-- A selected original native slot survives catalog writes and allocation.
    This uses the existing byte frame, not unchanged allocation metadata. -/
theorem Post.snapshot (post : Post input caller result heap world views)
    (snapshot : NativeSnapshot fuel program caller.heap type pointer value size)
    (apart : ∀ address, pointer ≤ address → address < pointer + size →
      ¬(input.Success caller.heap ∧ input.footprint address)) :
    NativeSnapshot fuel program heap type pointer value size := by
  intro other within
  apply snapshot other
  intro address width bytes lower upper loaded
  apply within address width bytes lower upper
  have length := (loadBytesFrom_spec loaded).1
  rw [← length]
  apply loadBytesFrom_of_reads
  intro index byte found
  rw [Nat.zero_add]
  apply post.outside address index byte (Heap.loadBytes_get loaded found)
  have inside := (List.getElem?_eq_some_iff.mp found).1
  exact apart (address + index) (by omega) (by omega)

/-- Fixed entry anchoring allows fresh loop counters to change. Existing
    scope rules transport this effect; no temporary cell is required immutable. -/
def Effect (anchor : State) (input : Model) (caller : State) (result : Int) (_before after : State) : Prop :=
  FreshCellFrame anchor after ∧ Post input caller result after.heap after.world after.i32ArrayViews

theorem Effect.scopes (anchor : State) (input : Model) (caller : State) (result : Int) :
    ScopeStable (Effect anchor input caller result) := by
  constructor
  · intro before middle after _ effect; exact effect
  · intro before after restored effect; exact ⟨effect.1.restoreLocals, effect.2⟩

theorem Input.unchangedPost (input : Input caller) {after : State} (rejected : ¬input.Success caller.heap)
    (noCopy : ¬input.CopyNeeded caller.heap)
    (heap : after.heap = caller.heap) (views : after.i32ArrayViews = caller.i32ArrayViews)
    (world : after.world = input.expectedWorld caller.heap caller.world) : Post input.toModel caller (-1)
      after.heap after.world after.i32ArrayViews := by
  classical
  have expected : input.expectedHeap caller.heap = caller.heap := by
    unfold Model.expectedHeap
    split
    · rename_i active
      cases resource : consumeBudget caller.heap.remaining (input.request * 56) with
      | none => rfl
      | some budget => exact False.elim (noCopy ⟨active.1, active.2.1, active.2.2, budget, resource⟩)
    · rfl
  refine ⟨by simp only [Model.answer, if_neg rejected], ?_, by simpa only [heap] using input.unique,
    fun _ _ readable => by simpa only [heap] using readable, ?_, ?_, ?_,
    fun active => False.elim (noCopy active), fun successful => False.elim (rejected successful), world, views⟩
  · rw [expected, heap]; exact ⟨rfl, rfl, rfl⟩
  · intro pointer offset byte read _; simpa only [heap] using read
  · intro guarded index inside
    change NativeSnapshot 64 extractedProgram after.heap IRCatalogStoreProof.bodyType
      (input.rowBase index) (input.previous index).value 96
    simpa only [heap] using input.rowSnapshots guarded index inside
  · intro _; simpa only [Arguments.CountRead, heap] using input.countRead

theorem Input.buildMetadata (input : Input caller) (active : input.CopyNeeded caller.heap)
    (frame : CallerFrame caller state)
    (available : consumeBudget caller.heap.remaining (input.request * 56) = some budget)
    (memory : Memory (input.copyInput active state frame.heap) budget value current) :
    Metadata (input.expectedHeap caller.heap) current.heap := by
  classical
  obtain ⟨copied, cut, post⟩ := memory.allocation
  have first : Metadata (input.firstHeap caller.heap budget) copied.heap := by
    simpa only [Arguments.firstHeap, Input.copyInput, IRCatalogCopyProof.Input.freshHeap,
      IRCatalogCopyProof.Input.memory, frame.heap] using
      (show Metadata ((input.copyInput active state frame.heap).freshHeap budget) copied.heap from
        ⟨cut.writes.frontier, cut.writes.budget, cut.writes.layout⟩)
  have budgetAtCut : copied.heap.remaining = budget := by
    simpa only [IRCatalogCopyProof.Input.freshHeap, Heap.borrowBlock, Heap.allocatedBytes] using cut.writes.budget
  have activeOnly : input.Guarded ∧ ¬input.Duplicate ∧ input.Sized := ⟨active.1, active.2.1, active.2.2.1⟩
  rcases post.2.2.2.2.2 with ⟨_, failed, unchanged⟩ | ⟨_, second, consumed, writes⟩
  · have exhausted : consumeBudget budget (input.request * 4) = none := by
      cases resource : consumeBudget budget (input.request * 4) with
      | none => rfl
      | some remaining =>
        have ready : consumeBudget copied.heap.remaining (input.request * 4) = some remaining := by
          rw [budgetAtCut]; exact resource
        simp only [IRCatalogCopyProof.CutState.region, Input.copyInput, IRAllocationProof.allocation, ready] at failed
        exact False.elim ((Nat.ne_of_gt copied.heap.borrowedAddress_pos) failed)
    simpa only [Model.expectedHeap, if_pos activeOnly, available, exhausted, unchanged] using first
  · have resource : consumeBudget budget (input.request * 4) = some second := by
      simpa only [IRCatalogCopyProof.CutState.region, Input.copyInput, budgetAtCut] using consumed
    have last : Metadata (copied.heap.appendI32 (List.replicate (input.request * 4) 0) false second) current.heap :=
      ⟨writes.frontier, writes.budget, writes.layout⟩
    simpa only [Model.expectedHeap, if_pos activeOnly, available, resource] using
      (first.append (List.replicate (input.request * 4) 0) second).trans last

theorem Input.rejectionPost (input : Input caller) (active : input.CopyNeeded caller.heap)
    (frame : CallerFrame caller state) (bindings : StageBindings input.toArguments state)
    (available : consumeBudget caller.heap.remaining (input.request * 56) = some budget)
    (memory : Memory (input.copyInput active state frame.heap) budget IRBuilderProof.emptyTree current) :
    Post input.toModel caller (-1) current.heap current.world current.i32ArrayViews := by
  classical
  have rejected := input.rejectionNotSuccess active frame bindings available memory
  have reads : HeapReads caller.heap current.heap := by rw [← frame.heap]; exact memory.reads
  have activeOnly : input.Guarded ∧ ¬input.Duplicate ∧ input.Sized := ⟨active.1, active.2.1, active.2.2.1⟩
  refine ⟨by simp only [Model.answer, if_neg rejected], input.buildMetadata active frame available memory,
    memory.unique, fun _ _ readable => reads.readable readable,
    fun _ _ _ read _ => reads _ _ _ read, ?_, ?_, ?_, fun successful => False.elim (rejected successful),
    ?_, memory.noViews.trans input.noViews.symm⟩
  · intro guarded index inside; exact (input.rowSnapshots guarded index inside).afterHeapReads reads
  · intro _; exact reads.rawSlice input.countRead
  · intro _
    constructor
    · intro index inside
      change readRawSliceIndex extractedProgram { heap := current.heap } IREventStoreProof.eventType
        (caller.heap.allocationAddress 8 + input.request * 40 - 8) input.request index = .ok (input.events index)
      simpa only [readRawSliceIndex, Input.copyInput, IRCatalogCopyProof.Input.eventPointer,
        IRCatalogCopyProof.Input.memory, frame.heap] using memory.eventReads index inside
    · intro index inside
      change readRawSliceIndex extractedProgram { heap := current.heap } IREventStoreProof.referenceType
        (caller.heap.allocationAddress 8 + input.request * 56 - 8) input.request index = .ok (input.annotation index)
      by_cases enabled : input.hasResultTypes = true <;>
        simpa only [readRawSliceIndex, Input.copyInput, Model.annotation, IRCatalogCopyProof.Input.annotation,
          IRCatalogCopyProof.Input.typePointer, IRCatalogCopyProof.Input.memory, frame.heap,
          enabled, ite_true, ite_false] using memory.typeReads index inside
  · simpa only [Model.expectedWorld, if_pos activeOnly, available, frame.world] using memory.world

theorem Input.successPost (input : Input caller) (active : input.CopyNeeded caller.heap)
    (frame : CallerFrame caller state) (bindings : StageBindings input.toArguments state)
    (available : consumeBudget caller.heap.remaining (input.request * 56) = some budget)
    (successful : input.Success caller.heap)
    (live : Live (input.copyInput active state frame.heap) budget current)
    (stored : IRCatalogStoreProof.Stored (input.storeEntry active frame bindings available successful) live after) :
    Post input.toModel caller input.next.toInt after.heap after.world after.i32ArrayViews := by
  classical
  let entry := input.storeEntry active frame bindings available successful
  have activeOnly : input.Guarded ∧ ¬input.Duplicate ∧ input.Sized := ⟨active.1, active.2.1, active.2.2.1⟩
  have nextNat := input.toArguments.occupiedValue active.1
  obtain ⟨copied, cut, address, _⟩ := IRCatalogStoreProof.endStorage entry live
  have endAddress : live.tree.address = caller.heap.allocationAddress 8 + input.request * 56 := by
    rw [address, IRCatalogStoreProof.endpoint entry cut]
    simp only [Input.copyInput, IRCatalogCopyProof.Input.memory, frame.heap]
  have treeValue : live.value = input.copiedTree caller.heap := by
    rw [live.represented]
    simp only [Ready.value, Region.tree, Memory.region, Input.copyInput, Arguments.copiedTree,
      IRCatalogCopyProof.Input.eventPointer, IRCatalogCopyProof.Input.typePointer,
      IRCatalogCopyProof.Input.memory, frame.heap, endAddress]
    rfl
  refine ⟨by simp only [Model.answer, if_pos successful],
    (input.buildMetadata active frame available live.memory).trans
      ⟨stored.writes.frontier, stored.writes.budget, stored.writes.layout⟩, stored.writes.unique,
    fun _ _ readable => stored.writes.readable _ _
      (live.memory.reads.readable (by simpa only [frame.heap] using readable)), ?_, ?_,
    fun rejected => False.elim (rejected successful), ?_, ?_, ?_,
    stored.views.trans (live.memory.noViews.trans input.noViews.symm)⟩
  · intro pointer offset byte read outside
    have permitted : ¬entry.footprint (pointer + offset) := fun inside => outside ⟨successful, inside⟩
    rw [stored.writes.outside _ _ permitted]
    apply live.memory.reads
    simpa only [frame.heap] using read
  · intro guarded index inside
    apply stored.otherRow (pointer := input.rowBase index)
    · simpa only [frame.heap] using input.rowSnapshots guarded index inside
    · right
      have floor := (input.geometry successful).rowFloor
      change input.rowBase input.occupied + 96 ≤ input.rowBase index
      dsimp only [Arguments.rowBase] at *
      omega
    · exact (input.geometry successful).countApart index inside
  · intro _
    constructor
    · obtain ⟨ready, _, _⟩ := stored.tree
      intro index inside
      have read := ready.eventReads index inside
      change readRawSliceIndex extractedProgram after IREventStoreProof.eventType
        (input.copyInput active state frame.heap).eventPointer input.request index = .ok (input.events index) at read
      change readRawSliceIndex extractedProgram { heap := after.heap } IREventStoreProof.eventType
        (caller.heap.allocationAddress 8 + input.request * 40 - 8) input.request index = .ok (input.events index)
      simpa only [readRawSliceIndex, Input.copyInput, IRCatalogCopyProof.Input.eventPointer,
        IRCatalogCopyProof.Input.memory, frame.heap] using read
    · intro index inside
      change readRawSliceIndex extractedProgram { heap := after.heap } IREventStoreProof.referenceType
        (caller.heap.allocationAddress 8 + input.request * 56 - 8) input.request index = .ok (input.annotation index)
      by_cases enabled : input.hasResultTypes = true <;>
        simpa only [readRawSliceIndex, Input.copyInput, Model.annotation, IRCatalogCopyProof.Input.annotation,
          IRCatalogCopyProof.Input.typePointer, IRCatalogCopyProof.Input.memory, frame.heap,
          enabled, ite_true, ite_false] using stored.types index inside
  · intro _
    refine ⟨?_, ?_, live.tree.ends, ?_, live.tree.root, ?_⟩
    · have snapshot := stored.row
      change NativeSnapshot 64 extractedProgram after.heap IRCatalogStoreProof.bodyType (input.rowBase input.occupied)
        (IRCatalogStoreProof.body input.signature live.value) 96 at snapshot
      change NativeSnapshot 64 extractedProgram after.heap IRCatalogStoreProof.bodyType (input.rowBase input.occupied) _ 96
      simpa only [treeValue] using snapshot
    · have read := stored.count.read
      change readNativeValue 64 extractedProgram after.heap (.scalar (.signed .i32)) input.countAddress =
        .ok (.signed .i32 ((input.occupied : Int) + 1)) at read
      simpa only [nextNat] using read
    · intro index inside; exact live.tree.suffix index (Nat.zero_le _) inside
    · obtain ⟨ready, sameAddress, sameEnds⟩ := stored.tree
      intro index inside
      simpa only [sameAddress, sameEnds, endAddress, readRawSliceIndex, Memory.region, Input.copyInput] using
        ready.contents index inside
  · rw [stored.world]
    simpa only [Model.expectedWorld, if_pos activeOnly, available, frame.world] using live.memory.world

#print axioms Effect.scopes
#print axioms Post.reanchorPure
#print axioms Post.snapshot
#print axioms Input.unchangedPost
#print axioms Input.buildMetadata
#print axioms Input.rejectionPost
#print axioms Input.successPost

end IRCatalogAppendProof
