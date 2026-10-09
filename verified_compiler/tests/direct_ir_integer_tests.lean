import verified_compiler.tests.direct_ir_literal_lowering
import verified_compiler.tests.direct_ir_event_store_tests
import Lanius.Semantics.RawSlice

namespace IRIntegerTests

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics IREventStoreProof IRLiteralLoweringProof

private def tokenKind : Value := source_value Extracted.«verified::token».Types.«TokenKind».«Integer» []
private def tokenOrdinal : Nat := match tokenKind with | .enumeration _ ordinal _ => ordinal | _ => 0
private def tokenType : Ty := match source_value Extracted.«verified::token».Types.«TokenRow».mk [] with
  | .structure id _ => .structure id | _ => .unit
private def rowId : Nat := match tokenType with | .structure id => id | _ => 0
private def kindId : Nat := match tokenKind with | .enumeration id _ _ => id | _ => 0
private theorem tokenWidth : NativeLayout.valueWords? extractedProgram tokenType = some 3 := by decide +kernel
private def tokenBytes : List UInt8 := encodeNatLE 4 tokenOrdinal ++ List.replicate 4 0 ++ i32Bytes 0 ++
  List.replicate 4 0 ++ i32Bytes 1 ++ List.replicate 4 0
private def sourceBytes := i32Bytes 55 ++ i32Bytes 999
private def tokenBufferBytes := List.replicate 24 165 ++ tokenBytes
def sample : State := {
  locals := [(10, 0)]
  cells := [{ id := 0, value := some (.boolean true) }]
  nextCell := 1
  world := { standardInput := [17], standardOutput := [18], standardError := [19] }
  heap := { blocks := [
  { base := 16, size := 112, alignment := 8,
    bytes := IREventStoreTests.eventBytes ++ IREventStoreTests.eventBytes ++
      IREventStoreTests.typeBytes ++ IREventStoreTests.typeBytes },
  { base := 128, size := 8, alignment := 4, bytes := sourceBytes, owned := false },
  { base := 136, size := 48, alignment := 8, bytes := tokenBufferBytes, owned := false }], nextAddress := 184 } }

def input : IRIntegerLoweringProof.Input sample := {
  address := 128, capacity := 2, count := 1, capacityBound := by decide
  start := 0, length := 1, bytes := fun _ => 55
  fits := by decide, inside := by decide, nonempty := by decide
  reads := by
    intro index inside
    have equal : index = 0 := by omega
    subst index
    rfl
  tokenAddress := 176, tokenCapacity := 2, tokenCount := 1, tokenBound := by decide
  tokenStorage := 200, tokenIndex := 0
  tokenFits := by decide, tokenInside := by decide
  tokenRead := by
    have address : rawSliceElementAddress? extractedProgram tokenType 176 0 = .ok 160 :=
      rawSliceElementAddress_of_layout rfl tokenWidth (by decide) (by decide) rfl
    change readRawSliceIndex extractedProgram sample tokenType 176 2 0 = _
    simp only [readRawSliceIndex, show ¬0 ≥ 2 by decide, ↓reduceIte, address]
    dsimp only [Bind.bind, Except.bind]
    have declaration : extractedProgram.structure? rowId = some
        { id := rowId, fields := [.enumeration kindId, .scalar (.signed .i32), .scalar (.signed .i32)] } := by core_lookup
    have first : NativeLayout.structureFieldOffset? extractedProgram rowId 0 = some 0 := by decide +kernel
    have second : NativeLayout.structureFieldOffset? extractedProgram rowId 1 = some 8 := by decide +kernel
    have third : NativeLayout.structureFieldOffset? extractedProgram rowId 2 = some 16 := by decide +kernel
    have kind : readNativeValue 63 extractedProgram sample.heap (.enumeration kindId) 160 = .ok tokenKind :=
      (NativeSnapshot.enumEmpty (by core_lookup) rfl (by decide)
        (show sample.heap.loadBytes 160 4 = .ok (encodeNatLE 4 tokenOrdinal) from rfl)).read
    change readNativeValue 64 extractedProgram sample.heap (.structure rowId) 160 =
      .ok (.structure rowId [tokenKind, .signed .i32 0, .signed .i32 1])
    rw [readNativeValue, declaration]
    simp only [List.length_cons, List.length_nil, List.range_succ, List.range_zero,
      List.cons_append, List.nil_append, List.mapM_cons, List.mapM_nil,
      List.getElem?_cons_zero, List.getElem?_cons_succ, first, second, third,
      Nat.add_zero, kind]
    rfl }

def storage : Context sample := {
  position := 0, capacity := 2, events := 88, types := 120, typesLength := 2, enabled := true
  eventBase := 56, typeBase := 112
  bound := by decide, fits := by decide, typeBound := fun _ => by decide
  eventLocation := IREventStoreTests.input.eventLocation
  typeLocation := IREventStoreTests.input.typeLocation
  eventRoom := Heap.Readable.of_loadBytes (show sample.heap.loadBytes 56 40 = .ok IREventStoreTests.eventBytes from rfl)
  typeRoom := fun _ => Heap.Readable.of_loadBytes (show sample.heap.loadBytes 112 16 = .ok IREventStoreTests.typeBytes from rfl)
  separate := fun _ => Or.inl (by decide) }

/-- Real source and token buffers are connected to the real frontend writer;
    the stored 7 is decoded from ASCII 55, not supplied to the writer. -/
theorem sourceToIR : ∃ after, RunsExpr extractedProgram sample (integerCall input [] storage.value 0)
    (.signed .i32 1) after ∧ readNativeValue 64 extractedProgram after.heap eventType 56 = .ok (integer 7) ∧
    readNativeValue 64 extractedProgram after.heap referenceType 112 = .ok invalid ∧
    after.heap.loadBytes 128 8 = .ok sourceBytes ∧ after.heap.loadBytes 136 48 = .ok tokenBufferBytes := by
  have formed : sample.CellsWellFormed := by simp [State.CellsWellFormed, sample]
  have unique : HeapBlockBasesUnique sample.heap := by
    intro left hl right hr same
    simp only [sample, List.mem_cons, List.not_mem_nil, or_false] at hl hr
    rcases hl with rfl | rfl | rfl <;> rcases hr with rfl | rfl | rfl <;> first | rfl | contradiction
  obtain ⟨after, run, _, _, _, event, middle, first, last⟩ :=
    actualInteger input [] 7 rfl storage formed unique rfl
  obtain ⟨annotation, second⟩ := last
  exact ⟨after, run, event.read, annotation.read,
    second.loadBytes (first.loadBytes (show sample.heap.loadBytes 128 8 = .ok sourceBytes from rfl)
      (Or.inr (by decide))) (Or.inr (by decide)),
    second.loadBytes (first.loadBytes (show sample.heap.loadBytes 136 48 = .ok tokenBufferBytes from rfl)
      (Or.inr (by decide))) (Or.inr (by decide))⟩

#print axioms sourceToIR

-- Malformed decimal contents must reject even when the output descriptor is
-- unusable. Valid digits must be read from memory, not from the token's tag.
#eval (do
  for word in ([48, 55, 57, 95, 58, -1, 2147483647] : List Int) do
    let before := { sample with heap := { sample.heap with blocks := sample.heap.blocks.map fun block =>
      if block.base == 128 then { block with bytes := i32Bytes word ++ i32Bytes 999 } else block } }
    let accepted := 48 ≤ word && word ≤ 57
    let output := if accepted then storage.value else .unit
    let .done result after := evalExpr 500 extractedProgram before (integerCall input [] output 0)
      | throw (IO.userError "source-to-IR literal path trapped")
    if accepted then
      unless result == .signed .i32 1 do throw (IO.userError "literal cursor did not advance")
      unless (readNativeValue 64 extractedProgram after.heap eventType 56).toOption == some (integer (BitVec.ofInt 32 (word - 48))) do
        throw (IO.userError "literal IR payload differs from source digit")
    else
      unless result == .signed .i32 (-1) do throw (IO.userError "malformed literal was accepted")
      let .ok previous := before.heap.loadBytes 16 112 | throw (IO.userError "unreadable fixture storage")
      unless (after.heap.loadBytes 16 112).toOption == some previous do
        throw (IO.userError "rejected literal wrote to IR storage")
    unless (after.heap.loadBytes 128 8).toOption == some (i32Bytes word ++ i32Bytes 999) &&
        (after.heap.loadBytes 136 48).toOption == some tokenBufferBytes do
      throw (IO.userError "literal lowering changed source or token memory")
    unless after.locals == before.locals && after.local? 10 == some (Value.boolean true) &&
        after.cell? 0 == before.cell? 0 && after.i32ArrayViews.isEmpty && after.world.calls.isEmpty &&
        after.world.standardInput == before.world.standardInput &&
        after.world.standardOutput == before.world.standardOutput &&
        after.world.standardError == before.world.standardError do
      throw (IO.userError "literal lowering lost the original caller frame")
  IO.println "7 source-to-IR success/rejection cases passed"
  IO.println "actual decoder spare source/token capacity and nonzero storage preserve meaning and caller" : IO Unit)

end IRIntegerTests
