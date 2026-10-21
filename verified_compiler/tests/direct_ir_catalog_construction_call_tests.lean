import verified_compiler.tests.direct_ir_catalog_construction_tests
import verified_compiler.tests.direct_ir_catalog_construction_call

namespace IRCatalogConstructionCallTests

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics
open IRTypeRefProof IRCatalogAppendProof IRCatalogConstructionProof
open IRCatalogConstructionTests

/-- The real stage's incoming Requirements value is represented independently. -/
def stageCaller (capacity : Int32) (budget : Nat) : State :=
  (original budget).bindLocal (lowerSource.bindingId 7)
    (source_value Extracted.«lowering::signature_index».Types.«Requirements».mk
      [.signed .i32 capacity.toInt, .signed .i32 0, .signed .i32 0, .signed .i32 0,
        .signed .i32 0, .signed .i32 0, .boolean true])

private theorem stageFormed (capacity : Int32) (budget : Nat) :
    (stageCaller capacity budget).CellsWellFormed := by
  apply State.CellsWellFormed.bindLocal
  apply State.CellsWellFormed.bindLocal
  simp [State.CellsWellFormed]

def previous : Nat → PreviousRow :=
  fun _ => { id := 40, parameters := 0, result := .I32, tree := IRBuilderProof.emptyTree }

/-- Request representation and source data are fixed before construction.
    Catalog.model supplies the actual constructor's descriptors and count. -/
def request : Model := {
  toArguments := {
    rowsAddress := 160, rowsLength := 1, countAddress := 64, countLength := 1
    capacity := 1, id := 7, parameters := 0, result := .I32
    eventsAddress := 48, eventsLength := 1, resultAddress := 9999, resultLength := 1
    hasResultTypes := false, sourceCapacity := 1, eventCount := 1, next := 0 }
  previous := previous
  events := fun _ => IREventStoreProof.integer 0
  annotations := fun _ => .Invalid
  kinds := fun _ => .ExpressionNode, arities := fun _ => 0, rules := fun _ => .NoChildren }

theorem originalEvent (budget : Nat) :
    NativeSnapshot 64 extractedProgram (original budget).heap eventType 16
      (IREventStoreProof.integer 0) 12 :=
  NativeSnapshot.enumSingle (by core_lookup) rfl (by decide) (by rfl)
    (NativeSnapshot.i32 (0 : BitVec 32) (by rfl))

def originalBudget (funded : Bool) : Nat := if funded then 164 else 104
def constructedInput (funded : Bool) : State :=
  let initial := original (originalBudget funded)
  let storage := initial.heap.allocatedBytes catalog.bytes 8 (some (if funded then 60 else 0))
  { initial with heap := storage }
def phaseHeap (funded : Bool) : Heap := (constructedInput funded).heap.borrowBlock catalog.memory
def model : Model := catalog.model 0 previous request

example (funded : Bool) : (original (originalBudget funded)).heap.allocate catalog.bytes 8 =
    .allocated catalog.memory (constructedInput funded).heap := by cases funded <;> rfl

/-- Reads and classification come from original bytes. The only later heap
    mentioned here is independently computed allocator metadata, not a run. -/
def sourceEvidence (funded : Bool) : RequestEvidence model (original (originalBudget funded)) (phaseHeap funded) := {
  eventReads := by
    intro _ index inside
    have zero : index = 0 := by change index < 1 at inside; omega
    subst index
    have width : NativeLayout.valueWords? extractedProgram eventType = some 5 := by decide +kernel
    have location : rawSliceElementAddress? extractedProgram eventType 48 0 = .ok 16 := by
      simp only [rawSliceElementAddress?, width]
      rfl
    change readRawSliceIndex extractedProgram (original (originalBudget funded)) eventType 48 1 0 =
      .ok (IREventStoreProof.integer 0)
    rw [readRawSliceIndex, if_neg (by decide), location]
    exact (originalEvent (originalBudget funded)).read
  classified := by intro _ index inside; exact IRCatalogCopyDomain.input.classified index inside
  represented := by intro _ index inside; exact IRCatalogCopyDomain.input.represented index inside
  annotationReads := by intro _ enabled; cases enabled
  freshFits := by intro _; cases funded <;> decide }

private theorem initialFormed (funded : Bool) : (constructedInput funded).CellsWellFormed := by
  change (original (originalBudget funded)).CellsWellFormed
  apply State.CellsWellFormed.bindLocal
  simp [State.CellsWellFormed]

private theorem originalBelow (funded : Bool) : HeapBlocksBelowNext (original (originalBudget funded)).heap := by
  intro block member
  simp [original, State.bindLocal, State.bindCell] at member
  subst block
  change 16 + max 40 1 ≤ 64
  decide

private theorem originalUnique (funded : Bool) : HeapBlockBasesUnique (original (originalBudget funded)).heap := by
  intro left leftMember right rightMember _
  simp [original, State.bindLocal, State.bindCell] at leftMember rightMember
  exact leftMember.trans rightMember.symm

private theorem guarded : model.Guarded :=
  ⟨by decide, by rfl, by decide, by decide, by decide, by decide, by decide⟩
private theorem noDuplicate : ¬model.Duplicate := by
  rintro ⟨index, inside, _⟩
  change index < 0 at inside
  omega
private theorem sized : model.Sized := ⟨by decide, by decide⟩
private theorem canonical : model.Canonical := by
  refine ⟨fun _ => 1, ?_, rfl⟩
  intro index inside
  have zero : index = 0 := by change index < 1 at inside; omega
  subst index
  exact ⟨by decide, by decide, by decide, 1, rfl, .nil⟩

theorem fundedSuccess : model.Success (phaseHeap true) :=
  ⟨guarded, noDuplicate, sized, ⟨some 4, some 0, rfl, rfl⟩, canonical⟩
theorem exhaustedReject : ¬model.Success (phaseHeap false) := by
  intro successful
  rcases successful.2.2.2.1 with ⟨first, _, available, _⟩
  change none = some first at available
  contradiction

/-- The actual constructor feeds the actual public append, whose retained
    invariant includes count one and the newly represented occupied row. -/
theorem firstAppendSuccess : ∃ constructed after,
    RunsExpr extractedProgram (constructedInput true) catalog.call catalog.value constructed ∧
    RunsExpr extractedProgram constructed model.call (.signed .i32 0) after ∧
    Invariant catalog 1 (catalog.afterRows 0 previous request (phaseHeap true)) after := by
  obtain ⟨constructed, after, constructorRun, effect, _, appendRun, _, _, _, retained⟩ :=
    actualConstructorAppend (original := original 164) (before := constructedInput true)
      (budget := some 60) (previous := previous) catalog (by decide) (by rfl) (by rfl)
      (originalBelow true) (originalUnique true) (by decide) (initialFormed true) (by rfl)
      request (sourceEvidence true)
  have heap : constructed.heap = phaseHeap true := effect.2.2.2
  have successful : model.Success constructed.heap := by rw [heap]; exact fundedSuccess
  change RunsExpr extractedProgram constructed model.call (.signed .i32 (model.answer constructed.heap)) after at appendRun
  refine ⟨constructed, after, constructorRun, ?_, ?_⟩
  · have answer : model.answer constructed.heap = 0 := by
      simp only [Model.answer, if_pos successful]
      rfl
    simpa only [answer] using appendRun
  · dsimp only [model] at successful
    have one : Int32.ofInt ((0 : Int32).toInt + 1) = (1 : Int32) := by decide
    simpa only [Catalog.afterCount, if_pos successful, one, heap] using retained

/-- Catalog allocation and construction succeed; the first append allocation
    exhausts, so the public call rejects and retains the empty invariant. -/
theorem firstAppendRejected : ∃ constructed after,
    RunsExpr extractedProgram (constructedInput false) catalog.call catalog.value constructed ∧
    RunsExpr extractedProgram constructed model.call (.signed .i32 (-1)) after ∧
    Invariant catalog 0 previous after := by
  obtain ⟨constructed, after, constructorRun, effect, _, appendRun, _, _, _, retained⟩ :=
    actualConstructorAppend (original := original 104) (before := constructedInput false)
      (budget := some 0) (previous := previous) catalog (by decide) (by rfl) (by rfl)
      (originalBelow false) (originalUnique false) (by decide) (initialFormed false) (by rfl)
      request (sourceEvidence false)
  have heap : constructed.heap = phaseHeap false := effect.2.2.2
  have rejected : ¬model.Success constructed.heap := by rw [heap]; exact exhaustedReject
  change RunsExpr extractedProgram constructed model.call (.signed .i32 (model.answer constructed.heap)) after at appendRun
  refine ⟨constructed, after, constructorRun, ?_, ?_⟩
  · simpa only [Model.answer, if_neg rejected] using appendRun
  · dsimp only [model] at rejected
    simpa only [Catalog.afterCount, Catalog.afterRows, if_neg rejected] using retained

#print axioms originalEvent
#print axioms sourceEvidence
#print axioms fundedSuccess
#print axioms exhaustedReject
#print axioms firstAppendSuccess
#print axioms firstAppendRejected

#eval (do
  for (capacity, expected) in [(1, 104), (0, -1), (22369622, -1)] do
    let .done (.signed .i32 result) after := evalExpr 1000 extractedProgram (original 164)
        (.call sizeSource.id [.value (.signed .i32 capacity)])
      | throw (IO.userError "actual catalog size helper failed")
    unless result == expected && after.local? 100 == some (.signed .i32 91) &&
        after.heap.nextAddress == 64 && after.heap.remaining == some 164 &&
        after.world.calls.isEmpty do
      throw (IO.userError "catalog size result or pure caller frame changed")
  let .done value ready := evalExpr 1000 extractedProgram allocated catalog.call
    | throw (IO.userError "actual catalog constructor failed")
  unless value == catalog.value &&
      (readRawSliceIndex extractedProgram ready (.structure countId) 64 1 0).toOption ==
        some (.structure countId [.signed .i32 0]) &&
      (ready.heap.block? 64).map (·.owned) == some false &&
      (ready.heap.block? 64).map (·.size) == some 104 &&
      (ready.heap.loadBytes 16 40).toOption == some (List.replicate 40 0) &&
      ready.local? 100 == some (.signed .i32 91) && ready.locals == allocated.locals &&
      ready.i32ArrayViews.isEmpty && ready.world.standardOutput == [88] &&
      ready.world.standardError == [89] && ready.world.calls.isEmpty do
    throw (IO.userError "catalog descriptors/count or caller/source retention changed")
  IO.println "actual catalog constructor fixtures: size guards, zero count and caller/source retention passed"
  for funded in [true, false] do
    let .done value constructed := evalExpr 1000 extractedProgram (constructedInput funded) catalog.call
      | throw (IO.userError "catalog constructor-to-append setup failed")
    unless value == catalog.value do
      throw (IO.userError "constructor returned different catalog descriptors")
    let .done (.signed .i32 answer) after := evalExpr 1000 extractedProgram constructed model.call
      | throw (IO.userError "actual first public append failed")
    unless answer == (if funded then 0 else -1) &&
        (readRawSliceIndex extractedProgram after (.structure countId) 64 1 0).toOption ==
          some (.structure countId [.signed .i32 (if funded then 1 else 0)]) &&
        (after.heap.block? 64).map (·.size) == some 104 &&
        (after.heap.block? 64).map (·.owned) == some false &&
        after.heap.nextAddress == (if funded then 228 else 168) && after.heap.remaining == some 0 &&
        (after.heap.loadBytes 16 40).toOption == some (List.replicate 40 0) &&
        after.local? 100 == some (.signed .i32 91) && after.locals == constructed.locals &&
        after.i32ArrayViews.isEmpty && after.world.standardOutput == [88] && after.world.standardError == [89] &&
        after.world.calls.all (· == .alloc) do
      throw (IO.userError "first append result/invariant or caller/source retention changed")
    if funded then
      unless (readNativeValue 64 extractedProgram after.heap bodyType 72).toOption ==
          some (IRCatalogStoreProof.body model.signature (model.copiedTree (phaseHeap true))) &&
          (readRawSliceIndex extractedProgram after eventType 200 1 0).toOption ==
            some (IREventStoreProof.integer 0) &&
          (readRawSliceIndex extractedProgram after referenceType 216 1 0).toOption ==
            some (referenceValue .Invalid) &&
          (readRawSliceIndex extractedProgram after (.scalar (.signed .i32)) 224 1 0).toOption ==
            some (.signed .i32 1) do
        throw (IO.userError "first appended row or copied payload changed")
  IO.println "actual catalog construction public fixtures: first append success and post-construction exhaustion passed"
  : IO Unit)

end IRCatalogConstructionCallTests
