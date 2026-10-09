import verified_compiler.tests.direct_ir_catalog_construction_call_tests
import verified_compiler.tests.direct_ir_catalog_construction_initialized

namespace IRCatalogConstructionInitializedTests

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics
open IRTypeRefProof IRCatalogAppendProof IRCatalogConstructionProof
open IRCatalogConstructionTests IRCatalogConstructionCallTests

private theorem required (capacity : Int32) (budget : Nat) :
    (stageCaller capacity budget).local? (lowerSource.bindingId 7) = some
      (source_value Extracted.«lowering::signature_index».Types.«Requirements».mk
        [.signed .i32 capacity.toInt, .signed .i32 0, .signed .i32 0, .signed .i32 0,
          .signed .i32 0, .signed .i32 0, .boolean true]) := by
  apply State.bindLocal_local?
  apply State.CellsWellFormed.bindLocal
  simp [State.CellsWellFormed]

private theorem formed (capacity : Int32) (budget : Nat) :
    (stageCaller capacity budget).CellsWellFormed := by
  apply State.CellsWellFormed.bindLocal
  apply State.CellsWellFormed.bindLocal
  simp [State.CellsWellFormed]

private theorem below (capacity : Int32) (budget : Nat) :
    HeapBlocksBelowNext (stageCaller capacity budget).heap := by
  intro block member
  change block ∈ (original budget).heap.blocks at member
  simp [original, State.bindLocal, State.bindCell] at member
  subst block
  change 16 + max 40 1 ≤ 64
  decide

private theorem unique (capacity : Int32) (budget : Nat) :
    HeapBlockBasesUnique (stageCaller capacity budget).heap := by
  intro left leftMember right rightMember _
  change left ∈ (original budget).heap.blocks at leftMember
  change right ∈ (original budget).heap.blocks at rightMember
  simp [original, State.bindLocal, State.bindCell] at leftMember rightMember
  exact leftMember.trans rightMember.symm

private theorem allocatedCatalog (budget : Nat) :
    Catalog.allocated 1 (stageCaller 1 budget).heap = IRCatalogConstructionTests.catalog := by
  simp only [Catalog.allocated, stageCaller, State.bindLocal, State.bindCell, original,
    IRCatalogConstructionTests.catalog, Heap.allocationAddress, alignUp] <;> rfl

/-- Adding the original Requirements local does not supply any future reads. -/
theorem sourceEvidence (funded : Bool) :
    RequestEvidence ((Catalog.allocated 1 (stageCaller 1 (originalBudget funded)).heap).model 0 previous request)
      (stageCaller 1 (originalBudget funded))
      (((stageCaller 1 (originalBudget funded)).heap.allocatedBytes
        (Catalog.allocated 1 (stageCaller 1 (originalBudget funded)).heap).bytes 8
        (some (if funded then 60 else 0))).borrowBlock
          (Catalog.allocated 1 (stageCaller 1 (originalBudget funded)).heap).memory) := by
  rw [allocatedCatalog]
  exact ⟨(IRCatalogConstructionCallTests.sourceEvidence funded).eventReads,
    (IRCatalogConstructionCallTests.sourceEvidence funded).classified,
    (IRCatalogConstructionCallTests.sourceEvidence funded).represented,
    (IRCatalogConstructionCallTests.sourceEvidence funded).annotationReads,
    (IRCatalogConstructionCallTests.sourceEvidence funded).freshFits⟩

theorem invalidCapacity : RejectedStage (stageCaller 0 164) (stageCaller 0 164).world := by
  have result := actualConstructionAppend (before := stageCaller 0 164) (previous := previous)
    0 (required 0 164) (formed 0 164) (below 0 164) (unique 0 164) (by rfl) request
    (by intro budget supported _; exact False.elim ((show ¬Supported (0 : Int32) by decide) supported))
  simpa only [ConstructionAppend, if_neg (show ¬Supported (0 : Int32) by decide)] using result

theorem catalogExhausted : RejectedStage (stageCaller 1 103)
    (World.record (stageCaller 1 103).world .alloc) :=
  actualCatalogExhausted 1 (by decide) (required 1 103) (by rfl) (formed 1 103) (by rfl)

private theorem initialized (funded : Bool) :
    InitializedAppend (stageCaller 1 (originalBudget funded)) 1 previous request
      (some (if funded then 60 else 0)) := by
  refine actualInitializedAppend 1 (by decide) (required 1 (originalBudget funded))
    (by cases funded <;> rfl) ?_ (formed 1 (originalBudget funded))
    (below 1 (originalBudget funded)) (unique 1 (originalBudget funded)) (by rfl)
    request (sourceEvidence funded)
  rw [allocatedCatalog]
  decide

/-- Real normal initializers, not an allocated-state premise, feed append. -/
theorem normalSuccess : ∃ constructed after,
    InitializersRun (stageCaller 1 164) constructed catalog ∧
    RunsExpr extractedProgram constructed model.call (.signed .i32 0) after ∧
    Invariant catalog 1 (catalog.afterRows 0 previous request (phaseHeap true)) after ∧
    HeapReads (stageCaller 1 164).heap after.heap := by
  have completed := initialized true
  simp only [InitializedAppend, allocatedCatalog] at completed
  obtain ⟨constructed, after, initializers, _, run, _, _, _, retained, heap, _, _, reads⟩ := completed
  change constructed.heap = phaseHeap true at heap
  have successful : model.Success constructed.heap := by rw [heap]; exact fundedSuccess
  change RunsExpr extractedProgram constructed model.call (.signed .i32 (model.answer constructed.heap)) after at run
  refine ⟨constructed, after, initializers, ?_, ?_, reads⟩
  · have answer : model.answer constructed.heap = 0 := by
      simp only [Model.answer, if_pos successful]
      rfl
    simpa only [answer] using run
  · dsimp only [model] at successful
    have one : Int32.ofInt ((0 : Int32).toInt + 1) = (1 : Int32) := by decide
    simpa only [Catalog.afterCount, if_pos successful, one, heap] using retained

/-- Catalog construction succeeds, but no append-copy allocation is available. -/
theorem normalRejected : ∃ constructed after,
    InitializersRun (stageCaller 1 104) constructed catalog ∧
    RunsExpr extractedProgram constructed model.call (.signed .i32 (-1)) after ∧
    Invariant catalog 0 previous after ∧ HeapReads (stageCaller 1 104).heap after.heap := by
  have completed := initialized false
  simp only [InitializedAppend, allocatedCatalog] at completed
  obtain ⟨constructed, after, initializers, _, run, _, _, _, retained, heap, _, _, reads⟩ := completed
  change constructed.heap = phaseHeap false at heap
  have rejected : ¬model.Success constructed.heap := by rw [heap]; exact exhaustedReject
  change RunsExpr extractedProgram constructed model.call (.signed .i32 (model.answer constructed.heap)) after at run
  refine ⟨constructed, after, initializers, ?_, ?_, reads⟩
  · simpa only [Model.answer, if_neg rejected] using run
  · dsimp only [model] at rejected
    simpa only [Catalog.afterCount, Catalog.afterRows, if_neg rejected] using retained

#print axioms sourceEvidence
#print axioms invalidCapacity
#print axioms catalogExhausted
#print axioms normalSuccess
#print axioms normalRejected

#eval (do
  for (capacity, budget) in [((0 : Int32), 164), ((1 : Int32), 103)] do
    let before := stageCaller capacity budget
    let .done (.returned (some result)) after :=
        execStmt 1000 extractedProgram before (lowerSource.bindingStatement 15)
      | throw (IO.userError "actual normal catalog rejection did not return")
    let expectedWorld := if capacity.toInt == 0 then before.world else World.record before.world .alloc
    unless result == failureValue && reprStr after.heap == reprStr before.heap &&
        reprStr after.world == reprStr expectedWorld && after.locals == before.locals &&
        after.local? 100 == some (.signed .i32 91) &&
        after.local? (lowerSource.bindingId 7) == before.local? (lowerSource.bindingId 7) &&
        after.i32ArrayViews.isEmpty do
      throw (IO.userError "normal catalog rejection changed original storage or caller")
  IO.println "actual normal catalog fixtures: invalid capacity and allocation exhaustion preserve caller heap"
  for funded in [true, false] do
    let before := stageCaller 1 (originalBudget funded)
    let .done (.signed .i32 size) sized :=
        evalExpr 1000 extractedProgram before (lowerSource.bindingInitializer 15)
      | throw (IO.userError "actual normal size initializer failed")
    unless size == 104 do throw (IO.userError "normal catalog size changed")
    let prepared := sized.bindLocal (lowerSource.bindingId 15) (.signed .i32 size)
    let .done (.boolean false) _ := evalExpr 1000 extractedProgram prepared sizeGuard
      | throw (IO.userError "normal positive size guard rejected")
    let .done (.pointer memory) allocated :=
        evalExpr 1000 extractedProgram prepared (lowerSource.bindingInitializer 16)
      | throw (IO.userError "actual normal host allocation initializer failed")
    unless memory == 64 do throw (IO.userError "normal catalog fresh address changed")
    let ready := allocated.bindLocal (lowerSource.bindingId 16) (.pointer memory)
    let .done (.boolean false) _ := evalExpr 1000 extractedProgram ready nullGuard
      | throw (IO.userError "normal positive allocation guard rejected")
    let .done value constructed :=
        evalExpr 1000 extractedProgram ready (lowerSource.bindingInitializer 17)
      | throw (IO.userError "actual normal constructor initializer failed")
    unless value == catalog.value &&
        (readRawSliceIndex extractedProgram constructed (.structure countId) 64 1 0).toOption ==
          some (.structure countId [.signed .i32 0]) do
      throw (IO.userError "normal constructor descriptors or zero count changed")
    let .done (.signed .i32 answer) after := evalExpr 1000 extractedProgram constructed model.call
      | throw (IO.userError "normal constructor-fed public append failed")
    unless answer == (if funded then 0 else -1) &&
        (readRawSliceIndex extractedProgram after (.structure countId) 64 1 0).toOption ==
          some (.structure countId [.signed .i32 (if funded then 1 else 0)]) &&
        (after.heap.loadBytes 16 40).toOption == some (List.replicate 40 0) &&
        after.local? 100 == some (.signed .i32 91) &&
        after.local? (lowerSource.bindingId 7) == before.local? (lowerSource.bindingId 7) &&
        after.locals == constructed.locals && after.i32ArrayViews.isEmpty &&
        after.world.standardOutput == [88] && after.world.standardError == [89] &&
        after.world.calls.all (· == .alloc) do
      throw (IO.userError "normal initializer-fed append lost count, original storage or caller")
    if funded then
      unless (readNativeValue 64 extractedProgram after.heap bodyType 72).toOption ==
          some (IRCatalogStoreProof.body model.signature (model.copiedTree (phaseHeap true))) do
        throw (IO.userError "normal initializer-fed success lost represented catalog row")
  IO.println "actual normal catalog fixtures: initializers feed public append and retain catalog/source"
  : IO Unit)

end IRCatalogConstructionInitializedTests
