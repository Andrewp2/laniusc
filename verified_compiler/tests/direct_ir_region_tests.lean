import verified_compiler.tests.direct_ir_region
import verified_compiler.tests.direct_ir_result_type

namespace IRRegionTests

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics IRRegionProof IREventStoreProof IRTypeRefProof

-- Owned storage with live integer events, zero annotation tags, and nonzero
-- padding. Construction must preserve actual bytes, not just decoded values.
private def eventBytes := encodeNatLE 4 0 ++ List.replicate 4 165 ++ i32Bytes 0 ++ List.replicate 28 165
private def typeBytes := encodeNatLE 4 0 ++ List.replicate 12 165
private def block : Block := {
  base := 16, size := 112, alignment := 8, owned := true
  bytes := eventBytes ++ eventBytes ++ typeBytes ++ typeBytes }
private def sample : State := { heap := { blocks := [block], nextAddress := 128 } }
private def input : FreshRegion sample := {
  memory := 16, count := 2, block := block, positive := by decide
  bytesFit := by decide, pointerFit := by decide, aligned := by decide
  eventBlock := rfl, typeBlock := rfl, alignment := by decide, bounds := by decide
  readable := Heap.Readable.of_loadBytes (show sample.heap.loadBytes 16 112 = .ok block.bytes from rfl)
  zero := by
    intro position inside
    have small : position = 0 ∨ position = 1 := by omega
    rcases small with rfl | rfl <;> rfl }
private theorem formed : sample.CellsWellFormed := by simp [State.CellsWellFormed, sample]
private theorem unique : HeapBlockBasesUnique sample.heap := by
  intro left hl right hr _
  simp only [sample, List.mem_singleton] at hl hr
  exact hl.trans hr.symm
private theorem eventWidth : NativeLayout.valueWords? extractedProgram eventType = some 5 := by decide +kernel
private theorem typeWidth : NativeLayout.valueWords? extractedProgram referenceType = some 2 := by decide +kernel
private def appendCall (word : BitVec 32) : Expr :=
  .call Extracted.«ir::body_events».Functions.«append».core.id
    [.value input.value, .value (.signed .i32 0), .value (integer word)]
private def recordCall (kind : Reference) := IRResultTypeProof.call
  (.rawSlice eventType 88 2) (.rawSlice referenceType 120 2) true 2 0 kind

-- The preconditions of both writers come from the actual constructor and
-- preceding writes. All signed payloads and valid result types are covered.
theorem constructAppendRecord (word : BitVec 32) (kind : Reference) (valid : 0 ≤ typeCode kind) :
    ∃ ready written after,
      RunsExpr extractedProgram sample input.call input.value ready ∧
      RunsExpr extractedProgram ready (appendCall word) (.signed .i32 1) written ∧
      RunsExpr extractedProgram written (recordCall kind) (.boolean true) after ∧
      readNativeValue 64 extractedProgram after.heap eventType 56 = .ok (integer word) ∧
      readNativeValue 64 extractedProgram after.heap referenceType 112 = .ok (referenceValue kind) ∧
      after.heap.loadBytes 16 40 = .ok eventBytes ∧ after.heap.loadBytes 96 16 = .ok typeBytes := by
  obtain ⟨ready, construct, readyCells, _, readyViews, readyHeap, _⟩ :=
    actualRegion input formed unique rfl
  have reads : ∀ pointer count, ready.heap.loadBytes pointer count = sample.heap.loadBytes pointer count := by
    intro pointer count
    rw [readyHeap]
    exact Heap.loadBytes_borrowBlock _ _ _ _
  have readyUnique : HeapBlockBasesUnique ready.heap := by rw [readyHeap]; exact unique.borrowBlock
  let context : Context ready := {
    position := 0, capacity := 2, events := 88, types := 120, eventBase := 56, typeBase := 112
    bound := by decide, fits := by decide
    eventLocation := by
      have layout := eventWidth
      dsimp only [eventType] at layout ⊢
      simp only [rawSliceElementAddress?, layout]; rfl
    typeLocation := by
      have layout := typeWidth
      dsimp only [referenceType] at layout ⊢
      simp only [rawSliceElementAddress?, layout]; rfl
    eventRoom := Heap.Readable.of_loadBytes (show ready.heap.loadBytes 56 40 = .ok eventBytes from by rw [reads]; rfl)
    typeRoom := Heap.Readable.of_loadBytes (show ready.heap.loadBytes 112 16 = .ok typeBytes from by rw [reads]; rfl)
    separate := Or.inl (by decide) }
  obtain ⟨written, append, writtenCells, _, writtenViews, event, _, middle, first, second⟩ :=
    actualAppend context (integerCodec word) (readyCells.after_cellsWellFormed formed) readyUnique readyViews
  let slot : IRResultTypeProof.Slot written := {
    position := 0, capacity := 2, types := 120, address := 112, bound := by decide
    location := context.typeLocation
    room := second.readable _ _ (first.readable _ _ context.typeRoom) }
  obtain ⟨after, record, _, _, _, resultType, effect⟩ :=
    IRResultTypeProof.actualRecord (events := .rawSlice eventType 88 2) slot kind valid
      (writtenCells.after_cellsWellFormed (readyCells.after_cellsWellFormed formed)) second.unique
      (writtenViews.trans readyViews)
  refine ⟨ready, written, after, construct, append, record,
    (event.afterWrite effect (Or.inl (by change 56 + 40 ≤ 112; decide))).read, resultType.read, ?_, ?_⟩
  · exact effect.loadBytes (second.loadBytes (first.loadBytes
      (show ready.heap.loadBytes 16 40 = .ok eventBytes from by rw [reads]; rfl)
      (Or.inl (by change 16 + 40 ≤ 56; decide))) (Or.inl (by change 16 + 40 ≤ 112; decide)))
      (Or.inl (by change 16 + 40 ≤ 112; decide))
  · exact effect.loadBytes (second.loadBytes (first.loadBytes
      (show ready.heap.loadBytes 96 16 = .ok typeBytes from by rw [reads]; rfl)
      (Or.inr (by change 56 + 40 ≤ 96; decide))) (Or.inl (by change 96 + 16 ≤ 112; decide)))
      (Or.inl (by change 96 + 16 ≤ 112; decide))

#print axioms constructAppendRecord

#eval (do
  let constructor := Extracted.«ir::body_events».Functions.«from_raw_parts».core
  for count in [1, 2, 3, 8] do
    let bytes := List.replicate (count * 56) (0 : UInt8)
    let before : State := { heap := { blocks := [{ base := 16, size := bytes.length, alignment := 8, bytes := bytes }] } }
    let .done region after := evalExpr 500 extractedProgram before
      (.call constructor.id [.value (.pointer 16), .value (.signed .i32 count)])
      | throw (IO.userError "fresh region construction trapped")
    let expected := source_value Extracted.«ir::body_events».Types.«Region».mk
      [.rawSlice eventType (16 + count * 40 - 8) count,
        .rawSlice referenceType (16 + count * 56 - 8) count, .boolean true, .signed .i32 count]
    unless region == expected do throw (IO.userError "constructor returned incorrect descriptors")
    let .ok actualBytes := after.heap.loadBytes 16 bytes.length
      | throw (IO.userError "fresh region became unreadable")
    unless actualBytes == bytes do
      throw (IO.userError "constructor changed fresh allocation bytes")
    unless (after.heap.block? 16).map (·.owned) == some false do
      throw (IO.userError "constructor did not transfer ownership")
    for position in List.range count do
      let .ok annotation := readRawSliceIndex extractedProgram after referenceType (16 + count * 56 - 8) count position
        | throw (IO.userError "annotation became unreadable")
      unless annotation == IREventStoreProof.invalid do
        throw (IO.userError "constructor left an invalid annotation slot") : IO Unit)

end IRRegionTests
