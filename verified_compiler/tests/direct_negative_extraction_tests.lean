import verified_compiler.tests.direct_negative_extraction
import verified_compiler.tests.direct_ir_integer_tests

namespace NegativeExtractionTests

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics
open IREventStoreProof SurfaceBooleanProof

-- The expected text is independent of the printer specification. Every case
-- starts with source bytes/token storage, never a prepopulated expression tree.
#eval (do
  let cases : List (String × String × Int) := [
    ("0", "(-(0))", 2), ("7", "(-(7))", 2), ("2_147_483_647", "(-(2147483647))", 2),
    ("2147483648", "-2147483648", 1), ("2147483649", "", -1), ("_", "", -1), ("x", "", -1)]
  let tokenKind := source_value Extracted.«verified::token».Types.«TokenKind».«Integer» []
  let ordinal := match tokenKind with | .enumeration _ ordinal _ => ordinal | _ => 0
  let tokenType := match source_value Extracted.«verified::token».Types.«TokenRow».mk [] with
    | .structure id _ => Ty.structure id | _ => .unit
  let outputRegion := source_value Extracted.«ir::body_events».Types.«Region».mk
    [.rawSlice IREventStoreProof.eventType 88 2, .rawSlice referenceType 120 2, .boolean true, .signed .i32 2]
  let mut checked := 0
  for (text, expectedText, count) in cases do
    let expected := World.utf8Bytes expectedText
    for capacity in (if count < 0 then [64] else [3 + expected.length, 2 + expected.length, 64]) do
      for budget in (if count < 0 then [none] else [none, some 0]) do
        let words := text.toList.map fun character => (character.toNat : Int)
        let bytes := words.flatMap i32Bytes
        let tokenBytes := encodeNatLE 4 ordinal ++ List.replicate 4 0 ++ i32Bytes 0 ++ List.replicate 4 0 ++
          i32Bytes words.length ++ List.replicate 4 0
        let before : State := ({ heap := { blocks := IRIntegerTests.sample.heap.blocks.take 1 ++ [
          { base := 256, size := bytes.length, alignment := 4, bytes, owned := false },
          { base := 512, size := 24, alignment := 8, bytes := tokenBytes, owned := false },
          { base := 768, size := 64, alignment := 4, bytes := List.replicate 64 90 },
          { base := 1024, size := 448, alignment := 8,
            bytes := List.replicate 424 0 ++ encodeNatLE 8 768 ++ encodeNatLE 8 16 ++
              i32Bytes capacity ++ List.replicate 4 0 }], nextAddress := 1472, remaining := budget } } : State)
          |>.bindLocal 77 (.signed .i32 321)
        let context := source_value Extracted.«lowering::body_context».Types.«BodyContext».mk
          [.rawSlice (.scalar (.signed .i32)) 256 words.length, .signed .i32 words.length,
            source_value Extracted.«verified::token».Types.«TokenTable».mk
              [.rawSlice tokenType 528 1, .signed .i32 1, .pointer 0], .signed .i32 1]
        let .done cursor lowered := evalExpr 500 extractedProgram before
          (.call Extracted.«lowering::body_literal».Functions.«negative».core.id
            [.value context, .value (.signed .i32 0), .value outputRegion, .value (.signed .i32 0)])
          | throw (IO.userError s!"source lowering trapped for {text}")
        unless cursor == .signed .i32 count do throw (IO.userError "source lowering returned wrong count")
        if count < 0 then
          unless (lowered.heap.loadBytes 16 112).toOption == (before.heap.loadBytes 16 112).toOption do
            throw (IO.userError "malformed source changed IR storage")
        else
          let .done tree built := evalExpr 500 extractedProgram lowered
            (.call Extracted.«ir::body_tree».Functions.«build».core.id [.value outputRegion, .value cursor])
            | throw (IO.userError "builder trapped after source lowering")
          if budget == some 0 then
            unless tree == IRBuilderProof.emptyTree do throw (IO.userError "exhausted builder did not reject")
            unless (built.heap.loadBytes 768 64).toOption == some (List.replicate 64 90) do
              throw (IO.userError "failed builder touched Lean output")
          else
            let .structure _ [_, _, _, _, .signed .i32 active] := tree
              | throw (IO.userError "builder did not produce a tree")
            unless active == count do throw (IO.userError "builder rejected the lowered tree")
            let .ok (.structure _ fields) := readRawSliceIndex extractedProgram built viewType 1464 1 0
              | throw (IO.userError "printer metadata unreadable")
            let view := viewValue tree (fields[1]?.getD .unit) (fields[2]?.getD .unit)
              (fields[3]?.getD .unit) 0 0 (.rawSlice (.scalar (.signed .i32)) 768 16) capacity
            let .ok heap := writeNativeValue 64 extractedProgram built built.heap viewType 1024 view
              | throw (IO.userError "printer View store failed")
            let printing := { built with heap }
            let .done finish after := evalExpr 1000 extractedProgram printing
              (.call Extracted.«verified::lean_typed_body».Functions.«surface_expression_output».core.id
                [.value (.rawSlice viewType 1464 1), .value (.signed .i32 0), .value (.signed .i32 3)])
              | throw (IO.userError "printer trapped after lowering and building")
            let enough := decide (3 + expected.length ≤ capacity)
            unless finish == .signed .i32 (if enough then (3 + expected.length : Nat) else -1) do
              throw (IO.userError "incorrect Lean output cursor/rejection")
            if enough && (after.heap.loadBytes 771 expected.length).toOption != some expected then
              throw (IO.userError s!"wrong Lean text for {text}")
            let untouched := max 3 (min capacity (3 + expected.length))
            unless (after.heap.loadBytes 768 3).toOption == some [90, 90, 90] &&
                (after.heap.loadBytes (768 + untouched) (64 - untouched)).toOption ==
                  some (List.replicate (64 - untouched) 90) do
              throw (IO.userError "printer escaped its output interval")
            unless (after.heap.loadBytes 16 112).toOption == (printing.heap.loadBytes 16 112).toOption &&
                (after.heap.loadBytes 1472 (count.toNat * 4)).toOption ==
                  (printing.heap.loadBytes 1472 (count.toNat * 4)).toOption do
              throw (IO.userError "printer changed the constructed IR tree")
            unless (after.heap.loadBytes 256 bytes.length).toOption == some bytes &&
                (after.heap.loadBytes 512 24).toOption == some tokenBytes && after.locals == before.locals do
              throw (IO.userError "extraction changed source/token storage or caller locals")
        checked := checked + 1
  IO.println s!"{checked} source-to-Lean pipeline cases passed" : IO Unit)

end NegativeExtractionTests
