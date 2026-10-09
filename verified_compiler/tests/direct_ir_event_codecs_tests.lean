import verified_compiler.tests.direct_ir_event_codecs
import verified_compiler.tests.direct_ir_event_store_tests

namespace IREventCodecTests

open Lanius Lanius.Core Lanius.Semantics IREventStoreProof IREventCodecProof
open IRTypeRefProof (Reference)

-- Every actual Event ordinal appears exactly once. This fails if a new
-- source variant is added without extending native payload coverage.
example : let tags := (representedEvents 0 0 0 false .I32 .I32Slice 0 0).map fun
    | .enumeration _ ordinal _ => ordinal
    | _ => 256 ^ 4
  tags.length = eventVariantCount ∧ (List.range eventVariantCount).all (tags.contains ·) = true := by decide +kernel

theorem representedAppend (first second third : Int32) (flag : Bool) (kind : Reference)
    (sliceKind : SliceKind) (pointer length : Nat) (pointerFits : pointer < 2 ^ 64) (lengthFits : length < 2 ^ 64)
    (member : event ∈ representedEvents first second third flag kind sliceKind pointer length) :
    ∃ after, RunsExpr extractedProgram IREventStoreTests.sample (IREventStoreTests.input.call event) (.signed .i32 1) after ∧
      readNativeValue 64 extractedProgram after.heap eventType 56 = .ok event ∧
      readNativeValue 64 extractedProgram after.heap IREventStoreProof.referenceType 112 = .ok invalid ∧
      after.heap.loadBytes 16 40 = .ok IREventStoreTests.eventBytes ∧
      after.heap.loadBytes 96 16 = .ok IREventStoreTests.typeBytes :=
  IREventStoreTests.appendReadback
    (representedCodecs first second third flag kind sliceKind pointer length pointerFits lengthFits event member)

#print axioms representedAppend

#eval (do
  let cases : List (Int32 × Int32 × Int32 × Bool × Reference × SliceKind × Nat × Nat) := [
    (0, 1, 7, false, .I32, .I32Slice, 0, 0),
    (-2147483648, 2147483647, -1, true, .Nominal 7, .StructureSlice, 16, 1),
    (2147483647, -1, -2147483648, false, .Invalid, .EnumerationSlice, 2 ^ 64 - 1, 2 ^ 64 - 1),
    (-1, -2147483648, 2147483647, true, .NominalSlice 2147483647, .I32Slice, 16, 4)]
  let source := Extracted.«ir::body_events».Functions.«append».core
  for (first, second, third, flag, kind, sliceKind, pointer, length) in cases do
    for event in representedEvents first second third flag kind sliceKind pointer length do
      for position in [0, 1] do
        let region := IREventStoreTests.input.value
        let .done cursor after := evalExpr 100 extractedProgram IREventStoreTests.sample
          (.call source.id [.value region, .value (.signed .i32 position), .value event])
          | throw (IO.userError "aggregate append trapped")
        unless cursor == .signed .i32 (position + 1) do throw (IO.userError "aggregate append advanced incorrectly")
        let .ok decoded := readRawSliceIndex extractedProgram after eventType 88 2 position.toNat
          | throw (IO.userError "aggregate event became unreadable")
        unless decoded == event do throw (IO.userError "aggregate payload changed")
        let .ok annotation := readRawSliceIndex extractedProgram after IREventStoreProof.referenceType 120 2 position.toNat
          | throw (IO.userError "aggregate annotation became unreadable")
        unless annotation == invalid do throw (IO.userError "aggregate append did not reset its annotation")
        let other := 1 - position.toNat
        let .ok neighborEvent := after.heap.loadBytes (16 + (1 - other) * 40) 40
          | throw (IO.userError "neighboring event became unreadable")
        unless neighborEvent == IREventStoreTests.eventBytes do
          throw (IO.userError "aggregate append changed neighboring event bytes")
        let .ok neighborType := after.heap.loadBytes (96 + (1 - other) * 16) 16
          | throw (IO.userError "neighboring annotation became unreadable")
        unless neighborType == IREventStoreTests.typeBytes do
          throw (IO.userError "aggregate append changed neighboring annotation bytes")
  IO.println s!"native event append cases: {cases.length * eventVariantCount * 2}; variants: {eventVariantCount}" : IO Unit)

end IREventCodecTests
