import verified_compiler.tests.direct_ir_negative_lowering
import verified_compiler.tests.direct_ir_integer_tests

namespace IRNegativeTests

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics IREventStoreProof IREventWriteProof

private def tail : Context IRIntegerTests.sample := {
  position := 1, capacity := 2, events := 88, types := 120, typesLength := 2, enabled := true
  eventBase := 16, typeBase := 96
  bound := by decide, fits := by decide, typeBound := fun _ => by decide
  eventLocation := rawSliceElementAddress_of_layout (words := 5) rfl (by decide +kernel) (by decide) (by decide) rfl
  typeLocation := fun _ => rawSliceElementAddress_of_layout (words := 2) rfl (by decide +kernel) (by decide) (by decide) rfl
  eventRoom := Heap.Readable.of_loadBytes (show IRIntegerTests.sample.heap.loadBytes 16 40 = .ok IREventStoreTests.eventBytes from rfl)
  typeRoom := fun _ => Heap.Readable.of_loadBytes (show IRIntegerTests.sample.heap.loadBytes 96 16 = .ok IREventStoreTests.typeBytes from rfl)
  separate := fun _ => Or.inl (by decide) }

private def storage : IRNegativeLoweringProof.Storage IRIntegerTests.sample := {
  head := IRIntegerTests.storage, tail, same := rfl, next := rfl
  eventsApart := by decide, typesApart := fun _ => by decide, planesApart := fun _ => by decide }

-- The 7 is read from ASCII 55. This exercises two distinct slots and the
-- effectful annotation guard, not a supplied constant passed to a writer.
theorem sourceToNegativeIR : ∃ after, RunsExpr extractedProgram IRIntegerTests.sample
    (IRNegativeLoweringProof.call IRIntegerTests.input [] storage.head.value 0) (.signed .i32 2) after ∧
    readNativeValue 64 extractedProgram after.heap eventType 56 = .ok negateEvent ∧
    readNativeValue 64 extractedProgram after.heap eventType 16 = .ok (integer 7) ∧
    readNativeValue 64 extractedProgram after.heap referenceType 96 = .ok (IRTypeRefProof.referenceValue .I32) := by
  have formed : IRIntegerTests.sample.CellsWellFormed := by simp [State.CellsWellFormed, IRIntegerTests.sample]
  have unique : HeapBlockBasesUnique IRIntegerTests.sample.heap := by
    intro left hl right hr same
    simp only [IRIntegerTests.sample, List.mem_cons, List.not_mem_nil, or_false] at hl hr
    rcases hl with rfl | rfl | rfl <;> rcases hr with rfl | rfl | rfl <;> first | rfl | contradiction
  obtain ⟨after, run, _, _, _, first, second, _, _, recorded, header, child⟩ :=
    IRNegativeLoweringProof.actualNumber IRIntegerTests.input [] 7 rfl storage formed unique rfl
  obtain ⟨annotation, _⟩ := recorded
  exact ⟨after, run, header.read, child.read, annotation.read⟩

#print axioms sourceToNegativeIR

#eval (do
  let cases : List (String × Int × Int) := [
    ("0", 2, 0), ("7", 2, 7), ("2147483647", 2, 2147483647),
    ("2147483648", 1, -2147483648), ("2147483648_", 1, -2147483648),
    ("2147483649", -1, 0), ("21474836480", -1, 0), ("_", -1, 0), ("x", -1, 0)]
  let tokenKind := source_value Extracted.«verified::token».Types.«TokenKind».«Integer» []
  let ordinal := match tokenKind with | .enumeration _ ordinal _ => ordinal | _ => 0
  let tokenType := match source_value Extracted.«verified::token».Types.«TokenRow».mk [] with
    | .structure id _ => Ty.structure id | _ => .unit
  for (text, cursor, payload) in cases do
    let words := text.toList.map fun character => (character.toNat : Int)
    let bytes := words.flatMap i32Bytes
    let sourceBytes := bytes ++ i32Bytes 999 ++ i32Bytes (-8)
    let tokenBytes := encodeNatLE 4 ordinal ++ List.replicate 4 0 ++ i32Bytes 0 ++ List.replicate 4 0 ++
      i32Bytes words.length ++ List.replicate 4 0
    let tokenBufferBytes := List.replicate 24 165 ++ tokenBytes
    let before : State := { IRIntegerTests.sample with heap := { blocks := IRIntegerTests.sample.heap.blocks.take 1 ++ [
      { base := 256, size := sourceBytes.length, alignment := 4, bytes := sourceBytes, owned := false },
      { base := 512, size := 48, alignment := 8, bytes := tokenBufferBytes, owned := false }], nextAddress := 560 } }
    let context := source_value Extracted.«lowering::body_context».Types.«BodyContext».mk
      [.rawSlice (.scalar (.signed .i32)) 256 (words.length + 2), .signed .i32 words.length,
        source_value Extracted.«verified::token».Types.«TokenTable».mk
          [.rawSlice tokenType 552 2, .signed .i32 1, .pointer 600], .signed .i32 1]
    let output := if cursor < 0 then Value.unit else storage.head.value
    let expression := Expr.call Extracted.«lowering::body_literal».Functions.«negative».core.id
      [.value context, .value (.signed .i32 0), .value output, .value (.signed .i32 0)]
    let .done actual after := evalExpr 500 extractedProgram before expression
      | throw (IO.userError s!"negative literal {text} trapped")
    unless actual == .signed .i32 cursor do throw (IO.userError s!"negative literal {text} advanced incorrectly")
    if cursor > 0 then
      let expected := if cursor == 1 then integer (BitVec.ofInt 32 payload) else negateEvent
      unless (readNativeValue 64 extractedProgram after.heap eventType 56).toOption == some expected do
        throw (IO.userError s!"negative literal {text} has the wrong root")
      if cursor == 2 then
        unless (readNativeValue 64 extractedProgram after.heap eventType 16).toOption == some (integer (BitVec.ofInt 32 payload)) &&
            (readNativeValue 64 extractedProgram after.heap referenceType 96).toOption == some (IRTypeRefProof.referenceValue .I32) do
          throw (IO.userError s!"negative literal {text} has the wrong child or annotation")
    else
      unless (after.heap.loadBytes 16 112).toOption == (before.heap.loadBytes 16 112).toOption do
        throw (IO.userError "rejected magnitude changed output storage")
    unless (after.heap.loadBytes 256 sourceBytes.length).toOption == some sourceBytes &&
        (after.heap.loadBytes 512 48).toOption == some tokenBufferBytes do
      throw (IO.userError "negative literal changed source/token bytes")
    unless after.locals == before.locals && after.local? 10 == some (Value.boolean true) &&
        after.cell? 0 == before.cell? 0 && after.i32ArrayViews.isEmpty && after.world.calls.isEmpty &&
        after.world.standardInput == before.world.standardInput &&
        after.world.standardOutput == before.world.standardOutput &&
        after.world.standardError == before.world.standardError do
      throw (IO.userError "negative literal lost original caller frame")
  IO.println s!"{cases.length} negative literal cases passed"
  IO.println "actual signed minimum and ordinary negative with spare capacities and nonzero token storage passed" : IO Unit)

end IRNegativeTests
