import verified_compiler.tests.direct_ir_catalog_construction_call
import verified_compiler.tests.direct_ir_catalog_construction_stage
import Lanius.Semantics.HostCall

namespace IRCatalogConstructionProof

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics IRTypeRefProof
open IRCatalogAppendProof

def Catalog.allocated (capacity : Int32) (heap : Heap) : Catalog :=
  { memory := heap.allocationAddress 8, capacity := capacity }

private theorem supportedBytes (catalog : Catalog) (supported : Supported catalog.capacity) :
    allocationBytes catalog.capacity = (catalog.bytes : Int) ∧ catalog.bytes < 2 ^ 31 := by
  have represented : (catalog.capacity.toInt.toNat : Int) = catalog.capacity.toInt :=
    Int.toNat_of_nonneg (by have := supported.1; omega)
  constructor
  · simp only [allocationBytes, if_pos supported, Catalog.bytes, Catalog.length,
      Int.natCast_add, Int.natCast_mul, Int.cast_ofNat_Int, represented]
  · have := supported.2
    dsimp only [Catalog.bytes, Catalog.length]
    omega

/-- One source-selected allocator initializer serves both budget outcomes. -/
private theorem allocatorInitializer (size : Nat) (fits : size < 2 ^ 31)
    (found : before.local? (lowerSource.bindingId 15) = some (.signed .i32 size))
    (noViews : before.i32ArrayViews = [])
    (called : World.call before.heap before.world .alloc [.unsigned .usize size, .unsigned .usize 8] =
      .returned (.pointer address) heap world) :
    RunsExpr extractedProgram before (lowerSource.bindingInitializer 16) (.pointer address)
      { before with heap, world } := by
  have cast := eval_unsigned_castNat extractedProgram.target .usize .i32 size
    (by change size < 2 ^ 64; omega)
  have alignment := eval_unsigned_castNat extractedProgram.target .usize .i32 8 (by decide)
  apply RunsExpr.callArguments (by core_arguments)
  let allocator := Extracted.«verified::host».Functions.«alloc».core
  exact RunsExpr.hostCall (functionId := allocator.id) (function := allocator)
    (values := [.unsigned .usize size, .unsigned .usize 8])
    (bindings := [(allocator.argumentId 0, .unsigned .usize size), (allocator.argumentId 1, .unsigned .usize 8)])
    (by dsimp only [allocator]; core_lookup) rfl rfl rfl noViews called

/-- The actual three initializers and intervening guards, ending before the
    unknown body-production continuation. No replacement caller is constructed. -/
def InitializersRun (before constructed : State) (catalog : Catalog) : Prop :=
  ∃ sized allocated,
    RunsExpr extractedProgram before (lowerSource.bindingInitializer 15) (.signed .i32 catalog.bytes) sized ∧
    RunsStmt extractedProgram (sized.bindLocal (lowerSource.bindingId 15) (.signed .i32 catalog.bytes))
      (.ifThenElse sizeGuard failureReturn .skip) .next
      (sized.bindLocal (lowerSource.bindingId 15) (.signed .i32 catalog.bytes)) ∧
    RunsExpr extractedProgram (sized.bindLocal (lowerSource.bindingId 15) (.signed .i32 catalog.bytes))
      (lowerSource.bindingInitializer 16) (.pointer catalog.memory) allocated ∧
    RunsStmt extractedProgram (allocated.bindLocal (lowerSource.bindingId 16) (.pointer catalog.memory))
      (.ifThenElse nullGuard failureReturn .skip) .next
      (allocated.bindLocal (lowerSource.bindingId 16) (.pointer catalog.memory)) ∧
    RunsExpr extractedProgram (allocated.bindLocal (lowerSource.bindingId 16) (.pointer catalog.memory))
      (lowerSource.bindingInitializer 17) catalog.value constructed

/-- A real continuation completes the exact source binding15 suffix. This
    rule does not assume or claim that body production has been proved. -/
theorem InitializersRun.continue (initializers : InitializersRun before constructed catalog)
    (Q : Completion → State → Prop)
    (tail : ∃ completion after, RunsStmt extractedProgram
      (constructed.bindLocal (lowerSource.bindingId 17) catalog.value) catalogSuccessTail completion after ∧
      Q completion (restoreLocals before after)) : ∃ completion after,
    RunsStmt extractedProgram before (lowerSource.bindingStatement 15) completion after ∧ Q completion after := by
  obtain ⟨sized, allocated, sizing, sizeGuardRun, allocation, nullGuardRun, construction⟩ := initializers
  obtain ⟨completion, after, tailRun, post⟩ := tail
  refine ⟨completion, restoreLocals before after, ?_, post⟩
  have run := RunsStmt.letLocal (id := lowerSource.bindingId 15) (type := .scalar (.signed .i32)) sizing
    (RunsStmt.sequenceNext sizeGuardRun (RunsStmt.letLocal (id := lowerSource.bindingId 16) (type := .scalar .rawPtr) allocation
      (RunsStmt.sequenceNext nullGuardRun (RunsStmt.letLocal (id := lowerSource.bindingId 17) (type := .structure 7) construction tailRun))))
  rw [actualStageShape.1, actualStageShape.2.1, actualStageShape.2.2]
  obtain ⟨_, _, sizedLocals⟩ := sizing
  simpa only [restoreLocals, sizedLocals] using run

def InitializedAppend (before : State) (capacity : Int32) (previous : Nat → PreviousRow)
    (request : Model) (budget : Option Nat) : Prop :=
  let catalog := Catalog.allocated capacity before.heap
  ∃ constructed after,
    InitializersRun before constructed catalog ∧ Invariant catalog 0 previous constructed ∧
    RunsExpr extractedProgram constructed (catalog.model 0 previous request).call
      (.signed .i32 ((catalog.model 0 previous request).answer constructed.heap)) after ∧
    FreshCellFrame before after ∧
    Post (catalog.model 0 previous request) constructed ((catalog.model 0 previous request).answer constructed.heap)
      after.heap after.world after.i32ArrayViews ∧ after.locals = constructed.locals ∧
    Invariant catalog (catalog.afterCount 0 previous request constructed.heap)
      (catalog.afterRows 0 previous request constructed.heap) after ∧
    constructed.heap = (before.heap.allocatedBytes catalog.bytes 8 budget).borrowBlock catalog.memory ∧
    constructed.world = World.record before.world .alloc ∧ constructed.i32ArrayViews = before.i32ArrayViews ∧
    HeapReads before.heap after.heap

/-- Supported allocation/constructor initializers feed one actual public
    append. The budget and source reads are independently specified inputs. -/
theorem actualInitializedAppend (capacity : Int32) (supported : Supported capacity)
    (required : before.local? (lowerSource.bindingId 7) = some
      (source_value Extracted.«lowering::signature_index».Types.«Requirements».mk
        [.signed .i32 capacity.toInt, members, variants, fields, constants, bytes, .boolean valid]))
    (available : consumeBudget before.heap.remaining (Catalog.allocated capacity before.heap).bytes = some budget)
    (fits : (Catalog.allocated capacity before.heap).memory +
      (Catalog.allocated capacity before.heap).bytes < 2 ^ 64)
    (formed : before.CellsWellFormed) (below : HeapBlocksBelowNext before.heap)
    (unique : HeapBlockBasesUnique before.heap) (noViews : before.i32ArrayViews = [])
    (request : Model) (source : RequestEvidence ((Catalog.allocated capacity before.heap).model 0 previous request) before
      ((before.heap.allocatedBytes (Catalog.allocated capacity before.heap).bytes 8 budget).borrowBlock
        (Catalog.allocated capacity before.heap).memory)) :
    InitializedAppend before capacity previous request budget := by
  let catalog := Catalog.allocated capacity before.heap
  obtain ⟨sizeIs, sizeFits⟩ := supportedBytes catalog supported
  change allocationBytes capacity = (catalog.bytes : Int) at sizeIs
  obtain ⟨sized, sizing, pure⟩ := actualSizeInitializer capacity required formed
  have sizeRun : RunsExpr extractedProgram before (lowerSource.bindingInitializer 15) (.signed .i32 catalog.bytes) sized :=
    by simpa only [sizeIs] using sizing
  let prepared := sized.bindLocal (lowerSource.bindingId 15) (.signed .i32 catalog.bytes)
  let allocated : State := { prepared with
    heap := prepared.heap.allocatedBytes catalog.bytes 8 budget
    world := World.record prepared.world .alloc }
  let ready := allocated.bindLocal (lowerSource.bindingId 16) (.pointer catalog.memory)
  have sizedFormed := pure.afterFormed
  have preparedFormed : prepared.CellsWellFormed := by core_formed
  have readyFormed : ready.CellsWellFormed := by core_formed
  have sameHeap : prepared.heap = before.heap := pure.heap
  have inheritedRequired := pure.localFound required
  have sizeFound : prepared.local? (lowerSource.bindingId 15) = some (.signed .i32 catalog.bytes) := by core_local
  have preparedViews : prepared.i32ArrayViews = [] := pure.views.trans noViews
  have memoryFound : ready.local? (lowerSource.bindingId 16) = some (.pointer catalog.memory) := by core_local
  have readyRequired : ready.local? (lowerSource.bindingId 7) = some
      (source_value Extracted.«lowering::signature_index».Types.«Requirements».mk
        [.signed .i32 capacity.toInt, members, variants, fields, constants, bytes, .boolean valid]) := by core_local
  have allocationRun : RunsExpr extractedProgram prepared (lowerSource.bindingInitializer 16)
      (.pointer catalog.memory) allocated := by
    apply allocatorInitializer catalog.bytes sizeFits sizeFound preparedViews
    have allocated := Heap.allocate_of_budget (alignment := 8) (by decide)
      (show consumeBudget prepared.heap.remaining catalog.bytes = some budget by rw [sameHeap]; exact available)
    simp only [World.call, World.callSimple]
    rw [allocated]
    simp only [sameHeap, catalog, Catalog.allocated]
  obtain ⟨constructed, after, constructorRun, effect, invariant, appendRun, cells, post, locals, retained⟩ :=
    actualConstructorAppend (original := before) (before := ready) catalog supported rfl
      (by change prepared.heap.allocatedBytes catalog.bytes 8 budget = _; rw [sameHeap])
      below unique fits readyFormed preparedViews request source
  have constructionRun : RunsExpr extractedProgram ready (lowerSource.bindingInitializer 17) catalog.value constructed :=
    RunsExpr.callArguments (by core_arguments) constructorRun
  have oldCells : FreshCellFrame before ready :=
    (pure.cells.trans (FreshCellFrame.bindLocal sized (lowerSource.bindingId 15) (.signed .i32 catalog.bytes))).trans
      (FreshCellFrame.bindLocal allocated (lowerSource.bindingId 16) (.pointer catalog.memory))
  refine ⟨constructed, after, ⟨sized, allocated, sizeRun, ?_, allocationRun, ?_, constructionRun⟩,
    invariant, appendRun, oldCells.trans cells, post, locals, retained, ?_, ?_, ?_, ?_⟩
  · have positive : 0 < catalog.bytes := by dsimp only [Catalog.bytes]; omega
    exact RunsStmt.ifThenElseFalse (by core_run) (RunsStmt.skip _ _)
  · have memoryPositive : 0 < catalog.memory := before.heap.allocationAddress_pos (by decide : 0 < 8)
    exact RunsStmt.ifThenElseFalse (by core_run) (RunsStmt.skip _ _)
  · have heap := effect.2.2.2
    change constructed.heap = (prepared.heap.allocatedBytes catalog.bytes 8 budget).borrowBlock catalog.memory at heap
    simpa only [sameHeap] using heap
  · have world := effect.2.1
    change constructed.world = World.record sized.world .alloc at world
    rwa [pure.world] at world
  · exact effect.2.2.1.trans pure.views
  · have originalReads : HeapReads before.heap constructed.heap := by
      intro pointer offset byte read
      rw [effect.2.2.2, Heap.loadByte_borrowBlock]
      change (prepared.heap.allocatedBytes catalog.bytes 8 budget).loadByte pointer offset = .ok byte
      apply Heap.allocatedBytes_oldRead
      rw [sameHeap]
      exact read
    have minimum : ∀ address, (catalog.model 0 previous request).footprint address → catalog.memory ≤ address := by
      intro address allowed
      change ((catalog.model 0 previous request).rowBase 0 ≤ address ∧ _) ∨ (catalog.memory ≤ address ∧ _) at allowed
      rcases allowed with ⟨lower, _⟩ | ⟨lower, _⟩
      · have positive : 0 < catalog.length := by
          have := supported.1
          dsimp only [catalog, Catalog.allocated, Catalog.length]
          omega
        dsimp only [Catalog.model, Arguments.rowBase] at lower
        rw [catalog.rowAddress positive] at lower
        dsimp only [Catalog.rowBase] at lower
        omega
      · exact lower
    intro pointer offset byte read
    have aliasRead := Heap.loadByte_alias read (show (pointer + offset) + 0 = pointer + offset by omega)
    have upper := (Heap.Readable.of_loadBytes
      (show before.heap.loadBytes (pointer + offset) 1 = .ok [byte] by
        simp [Heap.loadBytes, loadBytesFrom, aliasRead])).belowNext (by decide) below
    have fresh := before.heap.allocationAddress_ge (by decide : 0 < 8)
    exact post.outside pointer offset byte (originalReads _ _ _ read) (by
      rintro ⟨_, allowed⟩
      have := minimum _ allowed
      change before.heap.nextAddress ≤ catalog.memory at fresh
      dsimp only [Lanius.Address] at *
      omega)

/-- Both real early-return branches retain the original heap and caller
    scope; only exhausted allocation adds its actual world observation. -/
def RejectedStage (before : State) (world : World.State) : Prop :=
  ∃ after, RunsStmt extractedProgram before (lowerSource.bindingStatement 15)
    (.returned (some failureValue)) after ∧ FreshCellFrame before after ∧
    after.heap = before.heap ∧ after.world = world ∧
    after.i32ArrayViews = before.i32ArrayViews ∧ after.locals = before.locals

theorem actualCatalogExhausted (capacity : Int32) (supported : Supported capacity)
    (required : before.local? (lowerSource.bindingId 7) = some
      (source_value Extracted.«lowering::signature_index».Types.«Requirements».mk
        [.signed .i32 capacity.toInt, members, variants, fields, constants, bytes, .boolean valid]))
    (exhausted : consumeBudget before.heap.remaining (Catalog.allocated capacity before.heap).bytes = none)
    (formed : before.CellsWellFormed) (noViews : before.i32ArrayViews = []) :
    RejectedStage before (World.record before.world .alloc) := by
  let catalog := Catalog.allocated capacity before.heap
  obtain ⟨sizeIs, sizeFits⟩ := supportedBytes catalog supported
  change allocationBytes capacity = (catalog.bytes : Int) at sizeIs
  obtain ⟨sized, sizing, pure⟩ := actualSizeInitializer capacity required formed
  have sizeRun : RunsExpr extractedProgram before (lowerSource.bindingInitializer 15) (.signed .i32 catalog.bytes) sized :=
    by simpa only [sizeIs] using sizing
  let prepared := sized.bindLocal (lowerSource.bindingId 15) (.signed .i32 catalog.bytes)
  let allocated : State := { prepared with world := World.record prepared.world .alloc }
  let ready := allocated.bindLocal (lowerSource.bindingId 16) (.pointer 0)
  have sizedFormed := pure.afterFormed
  have preparedFormed : prepared.CellsWellFormed := by core_formed
  have readyFormed : ready.CellsWellFormed := by core_formed
  have sameHeap : prepared.heap = before.heap := pure.heap
  have sizeFound : prepared.local? (lowerSource.bindingId 15) = some (.signed .i32 catalog.bytes) := by core_local
  have preparedViews : prepared.i32ArrayViews = [] := pure.views.trans noViews
  have pointerFound : ready.local? (lowerSource.bindingId 16) = some (.pointer 0) := by core_local
  have allocationRun : RunsExpr extractedProgram prepared (lowerSource.bindingInitializer 16) (.pointer 0) allocated := by
    apply allocatorInitializer catalog.bytes sizeFits sizeFound preparedViews
    have unavailable : consumeBudget prepared.heap.remaining catalog.bytes = none := by rw [sameHeap]; exact exhausted
    simp only [World.call, World.callSimple, Heap.allocate,
      show validAlignment 8 = true from rfl, Bool.not_true, Bool.false_eq_true,
      ↓reduceIte, unavailable, null]
  obtain ⟨failed, failureRun, failurePure⟩ : ∃ failed,
      RunsStmt extractedProgram ready failureReturn (.returned (some failureValue)) failed ∧
        PureFrame ready failed := by core_pure
  have positive : 0 < catalog.bytes := by dsimp only [Catalog.bytes]; omega
  have sizeGuardRun : RunsStmt extractedProgram prepared (.ifThenElse sizeGuard failureReturn .skip) .next prepared :=
    RunsStmt.ifThenElseFalse (by core_run) (RunsStmt.skip _ _)
  have nullGuardRun : RunsStmt extractedProgram ready (.ifThenElse nullGuard failureReturn .skip)
      (.returned (some failureValue)) failed := RunsStmt.ifThenElseTrue (by core_run) failureRun
  have run := RunsStmt.letLocal (id := lowerSource.bindingId 15) (type := .scalar (.signed .i32)) sizeRun
    (RunsStmt.sequenceNext sizeGuardRun
      (RunsStmt.letLocal (id := lowerSource.bindingId 16) (type := .scalar .rawPtr) allocationRun
        (RunsStmt.sequenceCompleted nullGuardRun
          (by simp) (lowerSource.bindingStatement 17))))
  refine ⟨restoreLocals before failed, ?_, ?_, failurePure.heap.trans pure.heap, ?_,
    failurePure.views.trans pure.views, rfl⟩
  · rw [actualStageShape.1, actualStageShape.2.1]
    simpa only [restoreLocals, pure.locals] using run
  · exact ((pure.cells.trans (FreshCellFrame.bindLocal sized (lowerSource.bindingId 15)
      (.signed .i32 catalog.bytes))).trans (FreshCellFrame.bindLocal allocated (lowerSource.bindingId 16)
        (.pointer 0))).trans failurePure.cells
  · have world := failurePure.world
    change failed.world = World.record sized.world .alloc at world
    rwa [pure.world] at world

/-- Branches are selected from original capacity and budget, not execution.
    The positive case ends at the real constructor stage and discharges one
    public append; the unproved body-production tail is not asserted here. -/
def ConstructionAppend (before : State) (capacity : Int32) (previous : Nat → PreviousRow)
    (request : Model) : Prop :=
  if Supported capacity then
    match consumeBudget before.heap.remaining (Catalog.allocated capacity before.heap).bytes with
    | none => RejectedStage before (World.record before.world .alloc)
    | some budget => InitializedAppend before capacity previous request budget
  else RejectedStage before before.world

theorem actualConstructionAppend (capacity : Int32)
    (required : before.local? (lowerSource.bindingId 7) = some
      (source_value Extracted.«lowering::signature_index».Types.«Requirements».mk
        [.signed .i32 capacity.toInt, members, variants, fields, constants, bytes, .boolean valid]))
    (formed : before.CellsWellFormed) (below : HeapBlocksBelowNext before.heap)
    (unique : HeapBlockBasesUnique before.heap) (noViews : before.i32ArrayViews = [])
    (request : Model) (storage : ∀ budget, Supported capacity →
      consumeBudget before.heap.remaining (Catalog.allocated capacity before.heap).bytes = some budget →
      (Catalog.allocated capacity before.heap).memory + (Catalog.allocated capacity before.heap).bytes < 2 ^ 64 ∧
      RequestEvidence ((Catalog.allocated capacity before.heap).model 0 previous request) before
        ((before.heap.allocatedBytes (Catalog.allocated capacity before.heap).bytes 8 budget).borrowBlock
          (Catalog.allocated capacity before.heap).memory)) :
    ConstructionAppend before capacity previous request := by
  by_cases supported : Supported capacity
  · rw [ConstructionAppend, if_pos supported]
    cases available : consumeBudget before.heap.remaining (Catalog.allocated capacity before.heap).bytes with
    | none => exact actualCatalogExhausted capacity supported required available formed noViews
    | some budget =>
        obtain ⟨fits, source⟩ := storage budget supported available
        exact actualInitializedAppend capacity supported required available fits formed below unique noViews request source
  · rw [ConstructionAppend, if_neg supported]
    obtain ⟨after, run, pure⟩ := actualInvalidCapacity capacity supported required formed
    exact ⟨after, run, pure.cells, pure.heap, pure.world, pure.views, pure.locals⟩

#print axioms InitializersRun.continue
#print axioms actualInitializedAppend
#print axioms actualCatalogExhausted
#print axioms actualConstructionAppend

end IRCatalogConstructionProof
