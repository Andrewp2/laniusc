import verified_compiler.tests.direct_ir_catalog_construction
import verified_compiler.tests.direct_ir_catalog_append

namespace IRCatalogConstructionProof

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics IRTypeRefProof
open IRCatalogAppendProof

/-- Derive the initial invariant from the constructor's already-exact heap effect. -/
private theorem initialized (catalog : Catalog) (supported : Supported catalog.capacity)
    (base : catalog.memory = origin.allocationAddress 8)
    (allocated : before.heap = origin.allocatedBytes catalog.bytes 8 budget)
    (below : HeapBlocksBelowNext origin) (unique : HeapBlockBasesUnique origin)
    (formed : before.CellsWellFormed) (noViews : before.i32ArrayViews = [])
    (effect : MemoryEffect (fun _ heap => heap = before.heap.borrowBlock catalog.memory) before after) :
    Invariant catalog (0 : Int32) previous after := by
  have heap : after.heap = (origin.allocatedBytes catalog.bytes 8 budget).borrowBlock catalog.memory :=
    effect.2.2.2.trans (congrArg (fun heap => heap.borrowBlock catalog.memory) allocated)
  have zero : after.heap.loadBytes catalog.memory 4 = .ok (i32Bytes 0) := by
    rw [heap, Heap.loadBytes_borrowBlock, base]
    simpa only [Nat.add_zero, show i32Bytes 0 = List.replicate 4 0 by rfl] using
      origin.allocatedBytes_zeroRange (size := catalog.bytes) (budget := budget) (offset := 0)
        below (by decide : 0 < 8) (by dsimp only [Catalog.bytes]; omega)
  refine ⟨supported, ?_, (NativeSnapshot.i32 (program := extractedProgram) (fuel := 63)
    (0 : BitVec 32) zero).read, ?_, ?_, effect.1.after_cellsWellFormed formed, ?_, ?_,
    effect.2.2.1.trans noViews⟩
  · change 0 ≤ (0 : Int) ∧ 0 ≤ catalog.capacity.toInt
    have := supported.1
    omega
  · rw [heap]
    apply Heap.Readable.of_loadBytes
    rw [Heap.loadBytes_borrowBlock, base]
    simpa only [Nat.add_zero] using origin.allocatedBytes_zeroRange
      (size := catalog.bytes) (budget := budget) (offset := 0) (count := catalog.bytes)
      below (by decide : 0 < 8) (by omega)
  · intro index inside
    exact False.elim (Nat.not_lt_zero index inside)
  · rw [heap]
    exact (origin.allocatedBytes_unique below unique (by decide : 0 < 8)).borrowBlock
  · rw [heap]
    exact (origin.allocatedBytes_below below (by decide : 0 < 8)).borrowBlock

/-- Only request/source obligations remain: construction supplies catalog storage. -/
structure RequestEvidence (input : Model) (storage : State) (phase : Heap) : Prop where
  eventReads : input.CopyNeeded phase → ∀ index, index < input.request →
    readRawSliceIndex extractedProgram storage eventType input.eventsAddress input.eventsLength index =
      .ok (input.events index)
  classified : input.CopyNeeded phase → ∀ index, index < input.request →
    IRShapeProof.Classifies (input.events index)
      (IRShapeProof.shapeValue (IRShapeProof.kindValue (input.kinds index))
        (input.arities index) (IRShapeProof.ruleValue (input.rules index)))
  represented : input.CopyNeeded phase → ∀ index, index < input.request →
    ∃ first second third flag kind sliceKind pointer length,
      pointer < 2 ^ 64 ∧ length < 2 ^ 64 ∧ input.events index ∈
        IREventCodecProof.representedEvents first second third flag kind sliceKind pointer length
  annotationReads : input.CopyNeeded phase → input.hasResultTypes = true →
    ∀ index, index < input.request → readRawSliceIndex extractedProgram storage referenceType
      input.resultAddress input.resultLength index = .ok (referenceValue (input.annotations index))
  freshFits : input.CopyNeeded phase → phase.allocationAddress 8 + input.request * 56 < 2 ^ 64

theorem RequestEvidence.afterReads (source : RequestEvidence input before phase)
    (reads : HeapReads before.heap after.heap) : RequestEvidence input after phase :=
  ⟨fun active index bound => reads.rawSlice (source.eventReads active index bound),
    source.classified, source.represented,
    fun active enabled index bound => reads.rawSlice (source.annotationReads active enabled index bound),
    source.freshFits⟩

theorem Catalog.rowAddress (catalog : Catalog) (inside : index < catalog.length) :
    catalog.memory + catalog.length * 96 + 8 - (index + 1) * 96 = catalog.rowBase index := by
  dsimp only [Catalog.rowBase]
  omega

/-- Occupied snapshots and writable backing discharge all catalog-side premises. -/
def Invariant.input (invariant : Invariant catalog next previous caller) (request : Model)
    (source : RequestEvidence (catalog.model next previous request) caller caller.heap) : Input caller := by
  have countBound : next.toInt.toNat ≤ catalog.length := by
    have := invariant.bounds
    dsimp only [Catalog.length]
    omega
  refine {
    toModel := catalog.model next previous request
    formed := invariant.formed
    unique := invariant.unique
    below := invariant.below
    noViews := invariant.noViews
    countRead := invariant.countRead request
    rowBound := fun _ => countBound
    rowFloor := ?_
    rowSnapshots := ?_
    eventReads := source.eventReads
    classified := source.classified
    represented := source.represented
    annotationReads := source.annotationReads
    freshFits := source.freshFits
    geometry := ?_ }
  all_goals dsimp only [Catalog.model, Arguments.occupied, Arguments.rowBase] at *
  · intro _
    change next.toInt.toNat * 96 ≤ catalog.memory + catalog.length * 96 + 8
    omega
  · intro _ index inside
    rw [catalog.rowAddress (by omega)]
    exact invariant.occupied index inside
  · intro successful
    have strict : next.toInt.toNat < catalog.length := by
      have room : next.toInt < catalog.capacity.toInt := successful.1.2.2.2.2.1
      have := invariant.bounds.1
      dsimp only [Catalog.length]
      omega
    refine ⟨strict, ?_, ?_, ?_, ?_, ?_⟩
    all_goals dsimp only [Arguments.rowBase, Arguments.occupied] at *
    · change (next.toInt.toNat + 1) * 96 ≤ catalog.memory + catalog.length * 96 + 8
      omega
    · rw [catalog.rowAddress strict]
      simpa only [Catalog.rowBase, Nat.add_assoc] using
        invariant.backing.subrange (start := 8 + (catalog.length - next.toInt.toNat - 1) * 96)
        (by dsimp only [Catalog.bytes]; omega)
    · change caller.heap.Readable catalog.memory 4
      simpa only [Nat.add_zero] using invariant.backing.subrange (start := 0) (length := 4)
        (by dsimp only [Catalog.bytes]; omega)
    · right
      rw [catalog.rowAddress strict]
      dsimp only [Catalog.rowBase]
      omega
    · intro index inside
      right
      rw [catalog.rowAddress (by omega)]
      dsimp only [Catalog.rowBase]
      omega

noncomputable def Catalog.afterCount (catalog : Catalog) (next : Int32)
    (previous : Nat → PreviousRow) (request : Model) (heap : Heap) : Int32 := by
  classical
  exact if (catalog.model next previous request).Success heap then Int32.ofInt (next.toInt + 1) else next

noncomputable def Catalog.afterRows (catalog : Catalog) (next : Int32)
    (previous : Nat → PreviousRow) (request : Model) (heap : Heap) : Nat → PreviousRow := by
  classical
  exact if (catalog.model next previous request).Success heap then
    fun index => if index = next.toInt.toNat then
      { id := request.id, parameters := request.parameters, result := request.result,
        tree := (catalog.model next previous request).copiedTree heap }
      else previous index
    else previous

private theorem expectedBelow (input : Model) (below : HeapBlocksBelowNext heap) :
    HeapBlocksBelowNext (input.expectedHeap heap) := by
  classical
  unfold Model.expectedHeap
  split
  · cases first : consumeBudget heap.remaining (input.request * 56) with
    | none => exact below
    | some budget =>
      have allocated : HeapBlocksBelowNext (input.firstHeap heap budget) :=
        (heap.allocatedBytes_below below (by decide : 0 < 8)).borrowBlock
      cases second : consumeBudget budget (input.request * 4) with
      | none => simpa only [second] using allocated
      | some _ => simpa only [second] using Heap.appendI32_below allocated
  · exact below

/-- Public metadata retains the frontier/layout needed for the next allocation. -/
private theorem retainedBelow (post : Post input caller result heap world views)
    (below : HeapBlocksBelowNext caller.heap) : HeapBlocksBelowNext heap := by
  have expected := expectedBelow input below
  intro block member
  have masked : { block with bytes := [] } ∈ heap.blocks.map (fun item => { item with bytes := [] }) :=
    List.mem_map.mpr ⟨block, member, rfl⟩
  rw [post.metadata.2.2] at masked
  obtain ⟨old, oldMember, same⟩ := List.mem_map.mp masked
  have shape := congrArg (fun item : Block => item.base + max item.size 1) same
  simpa only [post.metadata.1, shape] using expected old oldMember

/-- The real append call preserves the producer invariant on every branch. -/
theorem actualMaintainedAppend (invariant : Invariant catalog next previous caller) (request : Model)
    (source : RequestEvidence (catalog.model next previous request) caller caller.heap) : ∃ after,
    RunsExpr extractedProgram caller (catalog.model next previous request).call
      (.signed .i32 ((catalog.model next previous request).answer caller.heap)) after ∧
    FreshCellFrame caller after ∧
    Post (catalog.model next previous request) caller ((catalog.model next previous request).answer caller.heap)
      after.heap after.world after.i32ArrayViews ∧ after.locals = caller.locals ∧
    Invariant catalog (catalog.afterCount next previous request caller.heap)
      (catalog.afterRows next previous request caller.heap) after := by
  classical
  let input := invariant.input request source
  obtain ⟨after, run, cells, post, locals⟩ := actualAppend input
  change Post (catalog.model next previous request) caller
    ((catalog.model next previous request).answer caller.heap) after.heap after.world after.i32ArrayViews at post
  refine ⟨after, run, cells, post, locals, ?_⟩
  have commonBelow := retainedBelow post invariant.below
  have backing := post.readable _ _ invariant.backing
  have formed := cells.after_cellsWellFormed invariant.formed
  have noViews := post.viewsFrame.trans invariant.noViews
  by_cases successful : (catalog.model next previous request).Success caller.heap
  · have guarded := successful.1
    have room : next.toInt < catalog.capacity.toInt := guarded.2.2.2.2.1
    have strict : next.toInt.toNat < catalog.length := by
      have := invariant.bounds.1
      dsimp only [Catalog.length]
      omega
    have oldBounds := invariant.bounds
    have supported := invariant.supported
    have increment : (Int32.ofInt (next.toInt + 1)).toInt = next.toInt + 1 :=
      Int32.toInt_ofInt_of_le (by omega)
        (by have := supported.2; omega)
    have stored := post.stored successful
    simp only [Catalog.afterCount, Catalog.afterRows, if_pos successful]
    refine ⟨supported, ?_, ?_, backing, ?_, formed, post.unique, commonBelow, noViews⟩
    · simp only [increment]
      omega
    · simpa only [Catalog.model, increment] using stored.2.1
    · intro index inside
      have position : index ≤ next.toInt.toNat := by rw [increment] at inside; omega
      by_cases last : index = next.toInt.toNat
      · subst index
        rw [if_pos rfl]
        rw [← catalog.rowAddress strict]
        exact stored.1
      · rw [if_neg last]
        rw [← catalog.rowAddress (by omega)]
        have oldInside : index < next.toInt.toNat := by omega
        exact post.occupied guarded index oldInside
  · have reads : HeapReads caller.heap after.heap :=
      fun _ _ _ read => post.outside _ _ _ read (fun permitted => successful permitted.1)
    simp only [Catalog.afterCount, Catalog.afterRows, if_neg successful]
    exact ⟨invariant.supported, invariant.bounds, reads.nativeValue invariant.count,
      backing, fun index inside => (invariant.occupied index inside).afterHeapReads reads,
      formed, post.unique, commonBelow, noViews⟩

/-- A genuine constructor call produces the catalog evidence consumed by one
    actual public append. Request reads refer to original storage, not a future state. -/
theorem actualConstructorAppend (catalog : Catalog) (supported : Supported catalog.capacity)
    (base : catalog.memory = original.heap.allocationAddress 8)
    (allocated : before.heap = original.heap.allocatedBytes catalog.bytes 8 budget)
    (below : HeapBlocksBelowNext original.heap) (unique : HeapBlockBasesUnique original.heap)
    (fits : catalog.memory + catalog.bytes < 2 ^ 64)
    (formed : before.CellsWellFormed) (noViews : before.i32ArrayViews = [])
    (request : Model) (source : RequestEvidence (catalog.model 0 previous request) original
      ((original.heap.allocatedBytes catalog.bytes 8 budget).borrowBlock catalog.memory)) :
    ∃ constructed after,
      RunsExpr extractedProgram before catalog.call catalog.value constructed ∧
      MemoryEffect (fun _ heap => heap = before.heap.borrowBlock catalog.memory) before constructed ∧
      Invariant catalog 0 previous constructed ∧
      RunsExpr extractedProgram constructed (catalog.model 0 previous request).call
        (.signed .i32 ((catalog.model 0 previous request).answer constructed.heap)) after ∧
      FreshCellFrame before after ∧
      Post (catalog.model 0 previous request) constructed
        ((catalog.model 0 previous request).answer constructed.heap)
        after.heap after.world after.i32ArrayViews ∧ after.locals = constructed.locals ∧
      Invariant catalog (catalog.afterCount 0 previous request constructed.heap)
        (catalog.afterRows 0 previous request constructed.heap) after := by
  obtain ⟨constructed, constructorRun, effect⟩ := actualConstructor catalog supported base allocated
    below unique fits formed noViews
  have invariant : Invariant catalog 0 previous constructed :=
    initialized catalog supported base allocated below unique formed noViews effect
  have heap : constructed.heap =
      (original.heap.allocatedBytes catalog.bytes 8 budget).borrowBlock catalog.memory := by
    rw [effect.2.2.2, allocated]
  have reads : HeapReads original.heap constructed.heap := by
    intro pointer offset byte read
    rw [heap, Heap.loadByte_borrowBlock]
    exact Heap.allocatedBytes_oldRead read
  have inherited : RequestEvidence (catalog.model 0 previous request) constructed constructed.heap := by
    rw [heap]
    exact source.afterReads reads
  obtain ⟨after, appendRun, cells, post, locals, retained⟩ :=
    actualMaintainedAppend invariant request inherited
  exact ⟨constructed, after, constructorRun, effect, invariant, appendRun,
    effect.1.trans cells, post, locals, retained⟩


#print axioms Invariant.input
#print axioms actualMaintainedAppend
#print axioms actualConstructorAppend

end IRCatalogConstructionProof
