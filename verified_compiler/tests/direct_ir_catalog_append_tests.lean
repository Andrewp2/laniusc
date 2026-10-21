import verified_compiler.tests.direct_ir_catalog_append
import verified_compiler.tests.direct_ir_catalog_copy_domain

namespace IRCatalogAppendTests

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics
open IRTypeRefProof IRShapeProof IRChildrenProof IRCatalogAppendProof

private def spareBytes : List UInt8 :=
  List.replicate 64 0 ++ encodeNatLE 4 2 ++ List.replicate 28 0

/-- Original bytes, not an allocator/copy/store execution. The exhausted
    caller has no row backing; the funded caller's spare row cannot decode. -/
def original (funded : Bool) : State :=
  let state : State := {
    heap := {
      blocks := [{ base := 16, size := 40, alignment := 8, bytes := List.replicate 40 0 },
        { base := 256, size := 4, alignment := 8, bytes := i32Bytes 0 }] ++
        if funded then [{ base := 704, size := 96, alignment := 8, bytes := spareBytes }] else []
      nextAddress := if funded then 800 else 260
      remaining := some (if funded then 60 else 56) }
    world := {
      arguments := ["catalog"]
      environment := [("mode", "fixture")]
      standardInput := [90]
      standardOutput := [88]
      standardError := [89]
      unixTimeSeconds := 37
      secureU32Stream := [13]
      calls := [.unixSeconds] } }
  state.bindLocal 100 (.signed .i32 91)

def arguments : Arguments := {
  rowsAddress := 792, rowsLength := 1, countAddress := 256, countLength := 1
  capacity := 1, id := 7, parameters := 0, result := .I32
  eventsAddress := 48, eventsLength := 1, resultAddress := 9999, resultLength := 1
  hasResultTypes := false, sourceCapacity := 1, eventCount := 1, next := 0 }

def model : Model := {
  toArguments := arguments
  previous := fun _ => { id := 40, parameters := 0, result := .I32, tree := IRBuilderProof.emptyTree }
  events := fun _ => IREventStoreProof.integer 0
  annotations := fun _ => .Invalid
  kinds := fun _ => .ExpressionNode, arities := fun _ => 0, rules := fun _ => .NoChildren }

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

private theorem secondExhausted : ¬model.BothAvailable (original false).heap := by
  rintro ⟨first, second, available, again⟩
  change some (some 0) = some first at available
  cases available
  change none = some second at again
  contradiction

/-- Both inputs establish only original storage, shape and resource facts.
    In particular, row geometry is not required on second-allocation failure. -/
def input (funded : Bool) : IRCatalogAppendProof.Input (original funded) := {
  toModel := model
  formed := by
    apply State.CellsWellFormed.bindLocal
    simp [State.CellsWellFormed]
  unique := by
    cases funded
    · intro left leftFound right rightFound same
      simp [original, State.bindLocal, State.bindCell] at leftFound rightFound
      rcases leftFound with rfl | rfl <;>
        rcases rightFound with rfl | rfl <;> first | rfl | cases same
    · intro left leftFound right rightFound same
      simp [original, State.bindLocal, State.bindCell] at leftFound rightFound
      rcases leftFound with rfl | rfl | rfl <;>
        rcases rightFound with rfl | rfl | rfl <;> first | rfl | cases same
  below := by
    cases funded
    · intro block found
      simp [original, State.bindLocal, State.bindCell] at found
      rcases found with rfl | rfl <;> change _ ≤ 260 <;> decide
    · intro block found
      simp [original, State.bindLocal, State.bindCell] at found
      rcases found with rfl | rfl | rfl <;> change _ ≤ 800 <;> decide
  noViews := rfl
  countRead := by rfl
  rowBound := by intro _; change 0 ≤ 1; decide
  rowFloor := by intro _; change 0 * 96 ≤ 792 + 8; decide
  rowSnapshots := by
    intro _ index inside
    change index < 0 at inside
    omega
  eventReads := by
    intro _ index inside
    have zero : index = 0 := by change index < 1 at inside; omega
    subst index
    have snapshot : NativeSnapshot 64 extractedProgram (original funded).heap
        IREventStoreProof.eventType 16 (IREventStoreProof.integer 0) 12 :=
      NativeSnapshot.enumSingle (by core_lookup) rfl (by decide) (by rfl)
        (NativeSnapshot.i32 0 (by rfl))
    have width : NativeLayout.valueWords? extractedProgram IREventStoreProof.eventType = some 5 :=
      by decide +kernel
    have location : rawSliceElementAddress? extractedProgram IREventStoreProof.eventType 48 0 = .ok 16 := by
      dsimp only [IREventStoreProof.eventType] at width ⊢
      simp only [rawSliceElementAddress?, width]
      rfl
    change readRawSliceIndex extractedProgram (original funded)
      IREventStoreProof.eventType 48 1 0 = .ok (IREventStoreProof.integer 0)
    rw [readRawSliceIndex, if_neg (by decide), location]
    exact snapshot.read
  classified := by intro _; exact IRCatalogCopyDomain.input.classified
  represented := by intro _; exact IRCatalogCopyDomain.input.represented
  annotationReads := by intro _ enabled; cases enabled
  freshFits := by intro _; cases funded <;> decide
  geometry := by
    cases funded
    · intro successful
      exact False.elim (secondExhausted successful.2.2.2.1)
    · intro _
      exact {
        rowBound := by decide, rowFloor := by decide
        rowRoom := Heap.Readable.of_loadBytes (bytes := spareBytes) (by rfl)
        countRoom := Heap.Readable.of_loadBytes (bytes := i32Bytes 0) (by rfl)
        separate := Or.inr (by decide)
        countApart := by intro index inside; change index < 0 at inside; omega } }

def successInput : IRCatalogAppendProof.Input (original true) := input true
def exhaustedInput : IRCatalogAppendProof.Input (original false) := input false

theorem copyNeeded (funded : Bool) : (input funded).CopyNeeded (original funded).heap := by
  refine ⟨guarded, noDuplicate, sized, ?_⟩
  cases funded
  · exact ⟨some 0, rfl⟩
  · exact ⟨some 4, rfl⟩

theorem successInitial : successInput.Success (original true).heap :=
  ⟨guarded, noDuplicate, sized, ⟨some 4, some 0, rfl, rfl⟩, canonical⟩

theorem exhaustedInitial : ¬exhaustedInput.Success (original false).heap :=
  fun successful => secondExhausted successful.2.2.2.1

-- Independent facts distinguishing these initial heaps from decodable,
-- fully backed catalog records or an assumed successful build.
example (funded : Bool) : (original funded).heap.loadBytes 256 8 = .error .rawMemoryBounds := by
  cases funded <;> rfl
example : (original true).heap.loadBytes 768 4 = .ok (encodeNatLE 4 2) := rfl
example : (original false).heap.containingBlock? 704 = none := rfl

/-- A full public call, with row/count/endpoint and copied-content conclusions
    obtained from the assembled Post, not the binding-5 store theorem. -/
theorem publicSuccess : ∃ after,
    RunsExpr extractedProgram (original true) successInput.call (.signed .i32 0) after ∧
    model.SuccessStorage (original true).heap after.heap ∧
    model.CopiedStorage (original true).heap after.heap ∧
    after.world = model.expectedWorld (original true).heap (original true).world := by
  obtain ⟨after, run, _, post, _⟩ := actualAppend successInput
  have answer : successInput.answer (original true).heap = 0 := by
    simp only [Model.answer, if_pos successInitial]
    rfl
  refine ⟨after, ?_, post.stored successInitial, post.copied (copyNeeded true), post.worldFrame⟩
  simpa only [answer] using run

/-- The second allocation rejects, but the completed event/annotation copy
    and its allocation metadata survive. -/
theorem publicSecondExhaustion : ∃ after,
    RunsExpr extractedProgram (original false) exhaustedInput.call (.signed .i32 (-1)) after ∧
    model.CopiedStorage (original false).heap after.heap ∧
    Metadata (arguments.firstHeap (original false).heap (some 0)) after.heap ∧
    after.world = model.expectedWorld (original false).heap (original false).world := by
  obtain ⟨after, run, _, post, _⟩ := actualAppend exhaustedInput
  have expected : exhaustedInput.expectedHeap (original false).heap =
      arguments.firstHeap (original false).heap (some 0) := by
    change model.expectedHeap (original false).heap = _
    simp only [Model.expectedHeap, if_pos (And.intro guarded (And.intro noDuplicate sized))]
    rfl
  refine ⟨after, ?_, post.copied (copyNeeded false), ?_, post.worldFrame⟩
  · simpa only [Model.answer, if_neg exhaustedInitial] using run
  · simpa only [expected] using post.metadata


/-- First exhaustion has readable original count/source bytes but activates
    neither copying nor spare-row geometry. -/
def firstCaller : State :=
  { original false with heap := { (original false).heap with remaining := some 55 } }

private theorem noFirstCopy : ¬model.CopyNeeded firstCaller.heap := by
  rintro ⟨_, _, _, budget, available⟩
  change none = some budget at available
  contradiction

private theorem noFirstSuccess : ¬model.Success firstCaller.heap := by
  rintro ⟨_, _, _, ⟨first, _, available, _⟩, _⟩
  change none = some first at available
  contradiction

def firstInput : IRCatalogAppendProof.Input firstCaller := {
  toModel := model
  formed := (input false).formed
  unique := (input false).unique
  below := (input false).below
  noViews := rfl
  countRead := rfl
  rowBound := by intro _; change 0 ≤ 1; decide
  rowFloor := by intro _; change 0 * 96 ≤ 792 + 8; decide
  rowSnapshots := by intro _ index inside; change index < 0 at inside; omega
  eventReads := by intro active; exact False.elim (noFirstCopy active)
  classified := by intro active; exact False.elim (noFirstCopy active)
  represented := by intro active; exact False.elim (noFirstCopy active)
  annotationReads := by intro _ enabled; cases enabled
  freshFits := by intro active; exact False.elim (noFirstCopy active)
  geometry := by intro successful; exact False.elim (noFirstSuccess successful) }

theorem publicFirstExhaustion : ∃ after,
    RunsExpr extractedProgram firstCaller firstInput.call (.signed .i32 (-1)) after ∧
    after.world = World.record firstCaller.world .alloc ∧
    Metadata firstCaller.heap after.heap := by
  obtain ⟨after, run, _, post, _⟩ := actualAppend firstInput
  have rejected : ¬firstInput.Success firstCaller.heap := noFirstSuccess
  have active : firstInput.Guarded ∧ ¬firstInput.Duplicate ∧ firstInput.Sized :=
    ⟨guarded, noDuplicate, sized⟩
  have expected : firstInput.expectedHeap firstCaller.heap = firstCaller.heap := by
    simp only [Model.expectedHeap, if_pos active]
    rfl
  have world : firstInput.expectedWorld firstCaller.heap firstCaller.world =
      World.record firstCaller.world .alloc := by
    simp only [Model.expectedWorld, if_pos active]
    rfl
  refine ⟨after, ?_, ?_, ?_⟩
  · simpa only [Model.answer, if_neg rejected] using run
  · simpa only [world] using post.worldFrame
  · simpa only [expected] using post.metadata

private def layout (heap : Heap) := heap.blocks.map fun block =>
  (block.base, block.size, block.alignment, block.live, block.owned)

private def observed (funded : Bool) : Bool :=
  let before := original funded
  match evalExpr 1000 extractedProgram before arguments.call with
  | .done (.signed .i32 result) after =>
      let memory := before.heap.allocationAddress 8
      let first := arguments.firstHeap before.heap (some (if funded then 4 else 0))
      let expected := if funded then first.appendI32 (List.replicate 4 0) false (some 0) else first
      result == (if funded then 0 else -1) &&
      (readNativeValue 64 extractedProgram after.heap (.scalar (.signed .i32)) 256).toOption ==
        some (.signed .i32 (if funded then 1 else 0)) &&
      (readRawSliceIndex extractedProgram after IREventStoreProof.eventType (memory + 32) 1 0).toOption ==
        some (IREventStoreProof.integer 0) &&
      (readRawSliceIndex extractedProgram after IREventStoreProof.referenceType (memory + 48) 1 0).toOption ==
        some (referenceValue .Invalid) &&
      (if funded then
        (readNativeValue 64 extractedProgram after.heap IRCatalogStoreProof.bodyType 704).toOption ==
          some (IRCatalogStoreProof.body arguments.signature (arguments.copiedTree before.heap)) &&
        (readRawSliceIndex extractedProgram after (.scalar (.signed .i32)) (memory + 56) 1 0).toOption ==
          some (.signed .i32 1)
       else (after.heap.containingBlock? 704).isNone) &&
      (after.heap.loadBytes 16 40).toOption == (before.heap.loadBytes 16 40).toOption &&
      after.heap.nextAddress == expected.nextAddress && after.heap.remaining == expected.remaining &&
      layout after.heap == layout expected && after.locals == before.locals &&
      (before.cells.all fun cell => after.cell? cell.id == cell.value) && after.i32ArrayViews.isEmpty &&
      after.world.standardOutput == before.world.standardOutput &&
      after.world.standardError == before.world.standardError &&
      after.world.calls == before.world.calls ++ [.alloc, .alloc] &&
      after.world.arguments == before.world.arguments && after.world.environment == before.world.environment &&
      after.world.standardInput == before.world.standardInput &&
      after.world.unixTimeSeconds == before.world.unixTimeSeconds &&
      after.world.secureU32Stream == before.world.secureU32Stream
  | _ => false


/-- Pure rejection and first exhaustion preserve the original two native
    blocks. The existing calls and non-call world fields must survive. -/
private def observedRejected (before : State) (args : Arguments) (attempts : Nat) : Bool :=
  match evalExpr 1000 extractedProgram before args.call with
  | .done (.signed .i32 result) after =>
      result == -1 && after.heap.nextAddress == before.heap.nextAddress &&
      after.heap.remaining == before.heap.remaining && layout after.heap == layout before.heap &&
      (after.heap.loadBytes 16 40).toOption == (before.heap.loadBytes 16 40).toOption &&
      (after.heap.loadBytes 256 4).toOption == (before.heap.loadBytes 256 4).toOption &&
      after.locals == before.locals &&
      (before.cells.all fun cell => after.cell? cell.id == cell.value) && after.i32ArrayViews.isEmpty &&
      after.world.calls == before.world.calls ++ List.replicate attempts .alloc &&
      after.world.arguments == before.world.arguments && after.world.environment == before.world.environment &&
      after.world.standardInput == before.world.standardInput &&
      after.world.standardOutput == before.world.standardOutput &&
      after.world.standardError == before.world.standardError &&
      after.world.unixTimeSeconds == before.world.unixTimeSeconds &&
      after.world.secureU32Stream == before.world.secureU32Stream
  | _ => false

#eval (do
  let .error .typeMismatch := readNativeValue 64 extractedProgram (original true).heap
      IRCatalogStoreProof.bodyType 704
    | throw (IO.userError "independent spare-row Bool2 corruption unexpectedly decoded")
  unless observed true do
    throw (IO.userError "public append corrupt-row/four-byte-count success contract failed")
  unless observed false do
    throw (IO.userError "public append second-allocation exhaustion lost completed copy or caller frame")
  unless observedRejected (original false) { arguments with id := -1 } 0 do
    throw (IO.userError "public append early guard rejection changed heap or caller world")
  unless observedRejected (original false)
      { arguments with eventCount := 38347923, sourceCapacity := 38347923 } 0 do
    throw (IO.userError "public append size rejection attempted allocation or changed caller world")
  unless observedRejected firstCaller arguments 1 do
    throw (IO.userError "public append first exhaustion lost exact one allocation observation")
  IO.println "actual catalog append observations: zero, one and two allocation attempts preserve caller world"
  IO.println "actual catalog append public fixtures: success and second-exhaustion retained copy passed" : IO Unit)

#print axioms input
#print axioms copyNeeded
#print axioms successInitial
#print axioms exhaustedInitial
#print axioms publicSuccess
#print axioms publicSecondExhaustion
#print axioms firstInput
#print axioms publicFirstExhaustion

end IRCatalogAppendTests
