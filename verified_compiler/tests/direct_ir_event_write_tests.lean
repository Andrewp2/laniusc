import verified_compiler.tests.direct_ir_event_write
import verified_compiler.tests.direct_ir_event_store_tests
import verified_compiler.tests.direct_ir_literal_lowering

namespace IREventWriteTests

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics IREventStoreProof IREventCodecProof IREventWriteProof
open IRTypeRefProof (Reference isValid)
open IREventStoreTests (sample input eventBytes typeBytes)

-- Rejection needs no storage premise. These actual calls have unit output
-- descriptors and an empty heap, so reaching append would trap.
example : ∃ after, RunsExpr extractedProgram {} (headerCall .unit 0 (-1) 7)
    (.signed .i32 (-1)) after ∧ PureFrame {} after :=
  actualCallReject _ _ (Or.inl (by decide)) (by simp [State.CellsWellFormed])
example : ∃ after, RunsExpr extractedProgram {} (matchingCall .unit 0 .Void 0 1)
    (.signed .i32 (-1)) after ∧ PureFrame {} after :=
  actualMatchReject _ _ _ (Or.inl rfl) (by simp [State.CellsWellFormed])

#eval (do
  let mut checked := 0
  for position in [-1, 0, 1, 2] do
    let mut cases : List (Expr × Option Value) := []
    for (functionId, arguments) in ([(0, 0), (7, 2), (2147483647, 2147483647),
        (-1, 0), (0, -1), (-2147483648, 7)] : List (Int32 × Int32)) do
      cases := cases ++ [(headerCall input.value position functionId arguments,
        if 0 ≤ functionId.toInt ∧ 0 ≤ arguments.toInt then some (callEvent functionId arguments) else none)]
    for (kind, scrutinee, arms) in ([(.I32, 0, 1), (.Bool, 7, 3), (.Nominal 1073741807, 1, 2),
        (.I32, -1, 1), (.I32, 0, 2147483647), (.Void, 0, 1), (.Invalid, 0, 1),
        (.Nominal (-1), 0, 1), (.I32, 0, 0), (.I32, 0, -1)] : List (Reference × Int32 × Int32)) do
      cases := cases ++ [(matchingCall input.value position kind scrutinee arms,
        if isValid kind && decide (0 < arms.toInt) then some (matchingEvent kind scrutinee arms) else none)]
    for literal in ([.IntegerValue 0, .IntegerValue (-1), .IntegerValue (-2147483648),
        .IntegerValue 2147483647, .BooleanValue false, .BooleanValue true] : List Literal) do
      cases := cases ++ [(literalCall input.value position literal, some (literalEvent literal))]
    -- A unit context has no source or token buffers to read. Boolean lowering
    -- must use the semantic node operator, irrespective of its token number.
    for flag in [false, true] do
      for token in ([-2147483648, -1, 0, 2147483647] : List Int32) do
        cases := cases ++ [(IRLiteralLoweringProof.booleanCall .unit flag token input.value position, some (boolean flag))]
    for (expression, event) in cases do
      let .done answer after := evalExpr 300 extractedProgram sample expression
        | throw (IO.userError "frontend writer trapped")
      if let some event := event.filter (fun _ => decide (0 ≤ position ∧ position < 2)) then
        unless answer == .signed .i32 (position + 1) do throw (IO.userError "frontend cursor is incorrect")
        let .ok stored := readRawSliceIndex extractedProgram after eventType 88 2 position.toNat
          | throw (IO.userError "frontend event became unreadable")
        unless stored == event do throw (IO.userError "frontend selected the wrong event or payload")
        let .ok annotation := readRawSliceIndex extractedProgram after referenceType 120 2 position.toNat
          | throw (IO.userError "frontend annotation became unreadable")
        unless annotation == invalid do throw (IO.userError "frontend failed to reset the annotation")
        let other := 1 - position
        let .ok neighboringEvent := after.heap.loadBytes (if other == 0 then 56 else 16) 40
          | throw (IO.userError "neighboring event became unreadable")
        let .ok neighboringType := after.heap.loadBytes (if other == 0 then 112 else 96) 16
          | throw (IO.userError "neighboring annotation became unreadable")
        unless neighboringEvent == eventBytes && neighboringType == typeBytes do
          throw (IO.userError "frontend changed neighboring bytes")
      else
        unless answer == .signed .i32 (-1) do throw (IO.userError "frontend accepted invalid input")
        let .ok bytes := after.heap.loadBytes 16 112
          | throw (IO.userError "rejection damaged storage")
        unless bytes == eventBytes ++ eventBytes ++ typeBytes ++ typeBytes do
          throw (IO.userError "rejection wrote to storage")
      checked := checked + 1
  IO.println s!"frontend writer cases: {checked}" : IO Unit)

end IREventWriteTests
