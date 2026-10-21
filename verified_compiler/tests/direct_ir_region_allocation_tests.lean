import verified_compiler.tests.direct_ir_region_pipeline
import verified_compiler.tests.direct_ir_event_codecs
import verified_compiler.tests.direct_ir_event_write
import verified_compiler.tests.direct_ir_literal_lowering

namespace IRRegionAllocationTests

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics IRRegionProof IREventStoreProof IRRegionAllocationProof
  IRRegionPipelineProof
open IRTypeRefProof (Reference typeCode referenceValue)

private def catalog := Extracted.«ir::body_catalog».Functions.«append».core
private def canary : List UInt8 := [165, 166, 167, 168]
private def initial (count : Int) (budget : Nat) : State := ({ heap := {
  blocks := [{ base := 16, size := 4, alignment := 4, bytes := canary }]
  nextAddress := 21, remaining := some budget } } : State).bindLocal (catalog.argumentId 3) (.signed .i32 count)
private theorem formed : (initial count budget).CellsWellFormed := by
  apply State.CellsWellFormed.bindLocal
  simp [State.CellsWellFormed]
private theorem below : HeapBlocksBelowNext (initial count budget).heap := by
  intro block member
  simp only [initial, State.bindLocal, State.bindCell, List.mem_singleton] at member
  subst block
  change 16 + max 4 1 ≤ 21
  decide
private theorem unique : HeapBlockBasesUnique (initial count budget).heap := by
  intro left hl right hr _
  simp only [initial, State.bindLocal, State.bindCell, List.mem_singleton] at hl hr
  exact hl.trans hr.symm
private theorem rounded : (initial count budget).heap.allocationAddress 8 = 24 := by
  simp only [initial, State.bindLocal, State.bindCell, Heap.allocationAddress, alignUp]
  rfl
private theorem space (count : Nat) (fits : count * 56 < 2 ^ 31) :
    (initial count (count * 56)).heap.allocationAddress 8 + count * 56 < 2 ^ 64 := by
  rw [rounded]
  dsimp only [Lanius.Address]
  omega
private theorem capacity : (initial count budget).local? (catalog.argumentId 3) = some (.signed .i32 count) := by
  dsimp only [initial]
  apply State.bindLocal_local?
  simp [State.CellsWellFormed]

-- Any representable positive count, not just two prebuilt slots. The proof
-- starts with no bytes local and no fresh storage; all three real initializers
-- run, consume an exact budget, and retain the original canary.
theorem initializersAllocate (count : Nat) (positive : 0 < count) (fits : count * 56 < 2 ^ 31) :
    ∃ after, InitializersRun (initial count (count * 56)) after count 24 ∧
      after.heap.loadBytes 16 4 = .ok canary ∧
      ∀ position, position < count → readNativeValue 64 extractedProgram after.heap referenceType
        (24 + count * 40 + (count - position - 1) * 16) = .ok invalid := by
  obtain ⟨after, run, _, _, _, _, reads, _, _, initialized⟩ := actualOwned (before := initial count (count * 56))
      (budget := some 0) count positive fits
      (space count fits) capacity
      (by simp [consumeBudget, initial, State.bindLocal, State.bindCell]) formed below unique rfl
  rw [rounded] at run initialized
  exact ⟨after, run,
    reads.loadBytes (show (initial count (count * 56)).heap.loadBytes 16 4 = .ok canary from rfl),
    fun position inside => (initialized position inside).read⟩

#print axioms initializersAllocate

-- The closed pipeline covers any represented count, any slot, every signed
-- payload and every valid result type; the old canary survives every write.
theorem allocateProduceRecord (count position : Nat) (inside : position < count)
    (fits : count * 56 < 2 ^ 31) (event : Value) (producer : Value → Int → Expr) (produces : Produces producer event)
    (kind : Reference) (valid : 0 ≤ typeCode kind) :
    ∃ ready written after, InitializersRun (initial count (count * 56)) ready count 24 ∧
      RunsExpr extractedProgram ready (producer (regionValue 24 count) position) (.signed .i32 (position + 1 : Nat)) written ∧
      RunsExpr extractedProgram written (recordCall 24 count position kind) (.boolean true) after ∧
      readNativeValue 64 extractedProgram after.heap eventType (24 + (count - position - 1) * 40) = .ok event ∧
      readNativeValue 64 extractedProgram after.heap referenceType
        (24 + count * 40 + (count - position - 1) * 16) = .ok (referenceValue kind) ∧
      after.heap.loadBytes 16 4 = .ok canary := by
  obtain ⟨ready, written, after, allocation, append, record, _, _, _, reads, event, annotation⟩ :=
    actualAllocateProduceRecord (before := initial count (count * 56)) (budget := some 0) count position inside fits
      (space count fits) capacity (by simp [consumeBudget, initial, State.bindLocal, State.bindCell]) formed below unique rfl
      event producer produces kind valid
  rw [rounded] at allocation append record event annotation
  exact ⟨ready, written, after, allocation, append, record, event.read, annotation.read,
    reads.loadBytes (show (initial count (count * 56)).heap.loadBytes 16 4 = .ok canary from rfl)⟩

#print axioms allocateProduceRecord

-- The codec obligation is discharged for every source Event schema, not
-- left as an assumed successful write. Counts, positions and fields vary.
theorem allocateAppendRepresented (count position : Nat) (inside : position < count) (fits : count * 56 < 2 ^ 31)
    (first second third : Int32) (flag : Bool) (kind : Reference) (sliceKind : IREventCodecProof.SliceKind)
    (pointer length : Nat) (pointerFits : pointer < 2 ^ 64) (lengthFits : length < 2 ^ 64)
    (member : event ∈ IREventCodecProof.representedEvents first second third flag kind sliceKind pointer length)
    (result : Reference) (valid : 0 ≤ typeCode result) :
    ∃ ready written after, InitializersRun (initial count (count * 56)) ready count 24 ∧
      RunsExpr extractedProgram ready (appendCall 24 count position event) (.signed .i32 (position + 1 : Nat)) written ∧
      RunsExpr extractedProgram written (recordCall 24 count position result) (.boolean true) after ∧
      readNativeValue 64 extractedProgram after.heap eventType (24 + (count - position - 1) * 40) = .ok event ∧
      readNativeValue 64 extractedProgram after.heap referenceType
        (24 + count * 40 + (count - position - 1) * 16) = .ok (referenceValue result) ∧
      after.heap.loadBytes 16 4 = .ok canary :=
  allocateProduceRecord count position inside fits event (appendProducer event)
    (fun input formed unique views => actualAppend input
      (IREventCodecProof.representedCodecs first second third flag kind sliceKind pointer length pointerFits lengthFits event member)
      formed unique views)
    result valid

#print axioms allocateAppendRepresented

-- A closed frontend instance: the actual literal writer supplies its proved
-- dispatch/store contract. Allocation derives its storage, and recording
-- installs the literal's scalar type, retaining the original canary.
theorem allocateLiteralRecord (count position : Nat) (inside : position < count) (fits : count * 56 < 2 ^ 31)
    (literal : IREventWriteProof.Literal) :
    ∃ ready written after, InitializersRun (initial count (count * 56)) ready count 24 ∧
      RunsExpr extractedProgram ready (IREventWriteProof.literalCall (regionValue 24 count) position literal)
        (.signed .i32 (position + 1 : Nat)) written ∧
      RunsExpr extractedProgram written (recordCall 24 count position (IREventWriteProof.literalKind literal))
        (.boolean true) after ∧
      readNativeValue 64 extractedProgram after.heap eventType (24 + (count - position - 1) * 40) =
        .ok (IREventWriteProof.literalEvent literal) ∧
      readNativeValue 64 extractedProgram after.heap referenceType
        (24 + count * 40 + (count - position - 1) * 16) =
        .ok (referenceValue (IREventWriteProof.literalKind literal)) ∧ after.heap.loadBytes 16 4 = .ok canary :=
  allocateProduceRecord count position inside fits (IREventWriteProof.literalEvent literal)
    (fun output position => IREventWriteProof.literalCall output position literal)
    (IREventWriteProof.actualLiteral literal) (IREventWriteProof.literalKind literal)
    (by cases literal <;> simp only [IREventWriteProof.literalKind, typeCode] <;> decide)

#print axioms allocateLiteralRecord

-- One level above the writer: a parsed Boolean node enters the real frontend
-- emitter. Source/token context is unused, and its annotation is Bool.
theorem allocateBooleanLoweringRecord (count position : Nat) (inside : position < count)
    (fits : count * 56 < 2 ^ 31) (context : Value) (flag : Bool) (token : Int32) :
    ∃ ready written after, InitializersRun (initial count (count * 56)) ready count 24 ∧
      RunsExpr extractedProgram ready (IRLiteralLoweringProof.booleanCall context flag token (regionValue 24 count) position)
        (.signed .i32 (position + 1 : Nat)) written ∧
      RunsExpr extractedProgram written (recordCall 24 count position .Bool) (.boolean true) after ∧
      readNativeValue 64 extractedProgram after.heap eventType (24 + (count - position - 1) * 40) = .ok (boolean flag) ∧
      readNativeValue 64 extractedProgram after.heap referenceType
        (24 + count * 40 + (count - position - 1) * 16) = .ok (referenceValue .Bool) ∧
      after.heap.loadBytes 16 4 = .ok canary :=
  allocateProduceRecord count position inside fits (boolean flag) (IRLiteralLoweringProof.booleanCall context flag token)
    (IRLiteralLoweringProof.actualBoolean context flag token) .Bool (by decide)

#print axioms allocateBooleanLoweringRecord

#eval (do
  for count in [-2147483648, -1, 0, 1, 38347922, 38347923, 2147483647] do
    let .done size _ := evalExpr 100 extractedProgram (initial count 0) (catalog.bindingInitializer 5)
      | throw (IO.userError "size calculation trapped")
    let expected := if 0 < count && count <= 38347922 then count * 56 else -1
    unless size == .signed .i32 expected do throw (IO.userError "size calculation accepted or rejected incorrectly")
  for count in ([1, 2, 3, 8] : List Nat) do
    for budget in [0, count * 56 - 1, count * 56] do
      let before := initial count budget
      let .done size sized := evalExpr 100 extractedProgram before (catalog.bindingInitializer 5)
        | throw (IO.userError "valid size calculation trapped")
      let prepared := sized.bindLocal (catalog.bindingId 5) size
      let .done (.pointer pointer) allocated := evalExpr 100 extractedProgram prepared (catalog.bindingInitializer 6)
        | throw (IO.userError "allocation initializer trapped")
      if budget < count * 56 then
        unless pointer == 0 do throw (IO.userError "exhausted allocation returned a nonnull pointer")
        unless allocated.heap.remaining == some budget do throw (IO.userError "exhaustion consumed the budget")
        unless allocated.heap.blocks.length == 1 do throw (IO.userError "exhaustion added a block")
      else
        unless pointer == 24 do throw (IO.userError "allocation used an incorrect aligned base")
        let ready := allocated.bindLocal (catalog.bindingId 6) (.pointer pointer)
        let .done region after := evalExpr 500 extractedProgram ready (catalog.bindingInitializer 7)
          | throw (IO.userError "allocated region construction trapped")
        let expected := source_value Extracted.«ir::body_events».Types.«Region».mk
          [.rawSlice eventType (pointer + count * 40 - 8) count,
            .rawSlice referenceType (pointer + count * 56 - 8) count, .boolean true, .signed .i32 count]
        unless region == expected do throw (IO.userError "owned initializer returned incorrect descriptors")
        unless after.heap.remaining == some 0 do throw (IO.userError "exact allocation budget was not consumed")
        unless (after.heap.block? pointer).map (·.owned) == some false do
          throw (IO.userError "owned region did not protect allocation ownership")
        for position in List.range count do
          let .ok annotation := readRawSliceIndex extractedProgram after referenceType
            (pointer + count * 56 - 8) count position
            | throw (IO.userError "fresh annotation became unreadable")
          unless annotation == invalid do throw (IO.userError "fresh annotation was not initialized")
        for position in List.range count do
          for number in [-2147483648, -1, 0, 1, 2147483647] do
            let word := BitVec.ofInt 32 number
            for kind in ([.I32, .Void, .Nominal 7] : List Reference) do
              let .done (.signed .i32 cursor) written := evalExpr 500 extractedProgram after (appendCall pointer count position (integer word))
                | throw (IO.userError "append after allocation trapped")
              unless cursor == position + 1 do throw (IO.userError "append advanced incorrectly")
              let .done (.boolean true) recorded := evalExpr 500 extractedProgram written (recordCall pointer count position kind)
                | throw (IO.userError "annotation after append failed")
              for index in List.range count do
                let .ok event := readRawSliceIndex extractedProgram recorded eventType (pointer + count * 40 - 8) count index
                  | throw (IO.userError "pipeline left an unreadable event")
                let .ok annotation := readRawSliceIndex extractedProgram recorded referenceType (pointer + count * 56 - 8) count index
                  | throw (IO.userError "pipeline left an unreadable annotation")
                unless event == integer (if index == position then word else 0) do
                  throw (IO.userError "pipeline changed the wrong event slot")
                unless annotation == (if index == position then referenceValue kind else invalid) do
                  throw (IO.userError "pipeline changed the wrong annotation slot")
              let .ok retained := recorded.heap.loadBytes 16 4
                | throw (IO.userError "pipeline destroyed old storage")
              unless retained == canary do throw (IO.userError "pipeline changed old storage")
      let .ok retained := allocated.heap.loadBytes 16 4
        | throw (IO.userError "allocation destroyed old storage")
      unless retained == canary do throw (IO.userError "allocation changed old storage") : IO Unit)

end IRRegionAllocationTests
