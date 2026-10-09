import verified_compiler.tests.direct_constructor_payload
import verified_compiler.tests.direct_declaration_name_tests
import verified_compiler.tests.direct_surface_expression_tree_tests

namespace ConstructorPayloadTests

open Lanius Lanius.Core Lanius.Semantics Lanius.Memory
open SurfaceBooleanProof SurfaceExpressionTreeProof SurfaceOperationsProof SymbolSpellingProof

private def variantType : Ty := match source_value Extracted.«ir::type_catalog».Types.«Variant».mk [] with
  | .structure id _ => .structure id | _ => .unit
private def fieldType : Ty := match source_value Extracted.«ir::type_catalog».Types.«Field».mk [] with
  | .structure id _ => .structure id | _ => .unit

/-- Build the real native event/annotation buffers, then invoke the actual
    builder and constructor printer. Expected text is supplied independently. -/
private def check (expressions : List Expression) (spelling : String) (short : Bool := false)
    (dispatch : Bool := false) : IO Unit := do
  let expected := World.utf8Bytes s!"(.«Choice»{spelling} : Extracted.«verified::syntax».Types.«Choice»)"
  let capacity := 3 + expected.length - (if short then 1 else 0)
  let .ok (sample, names) := DeclarationNameTests.fixture
    | throw (IO.userError "constructor naming fixture failed")
  let types : ConstructorNameProof.Table := {
    declarations := .rawSlice ConstructorNameProof.declarationType 2392 2, typeCount := 2,
    variants := .rawSlice variantType 0 0, variantCount := 4,
    fields := .rawSlice fieldType 0 0, fieldCount := 0 }
  let names := { names with variants := .rawSlice ConstructorNameProof.referenceType 2744 4, variantCount := 4 }
  let entries := (ConstructorPayloadProof.event 0 1 expressions.length, ScalarKind.i32) ::
    expressions.flatMap SurfaceExpressionTreeTests.nodes
  let count := entries.length
  let eventBase := 3456
  let annotationBase := eventBase + count * 40
  let events := eventBase + count * 40 - 8
  let annotations := annotationBase + count * 16 - 8
  let referenceType := SurfaceDispatchProof.referenceType
  let backed : State := { sample with heap := { sample.heap with
    blocks := sample.heap.blocks ++ [
      { base := 2304, size := 96, alignment := 8, bytes := List.replicate 96 0 },
      { base := 2688, size := 64, alignment := 8, bytes := List.replicate 64 0 },
      { base := 2944, size := 448, alignment := 8, bytes := List.replicate 448 0 },
      { base := eventBase, size := count * 40, alignment := 8, bytes := List.replicate (count * 40) 0 },
      { base := annotationBase, size := count * 16, alignment := 8, bytes := List.replicate (count * 16) 0 }]
    nextAddress := annotationBase + count * 16 } }
  let .ok heap := writeNativeValue 64 extractedProgram backed backed.heap ConstructorNameProof.declarationType 2352
    (ConstructorNameProof.enumeration 0 2 2) | throw (IO.userError "type declaration encoding failed")
  let mut before := { backed with heap }
  for slot in List.range 4 do
    let .ok heap := writeNativeValue 64 extractedProgram before before.heap ConstructorNameProof.referenceType
      (2688 + (3 - slot) * 16) (referenceValue (if slot == 3 then 1 else 0) 2)
      | throw (IO.userError "variant reference encoding failed")
    before := { before with heap }
  for ((value, kind), index) in entries.zipIdx do
    let .ok address := rawSliceElementAddress? extractedProgram eventType events index
      | throw (IO.userError "event addressing failed")
    let .ok heap := writeNativeValue 64 extractedProgram before before.heap eventType address value
      | throw (IO.userError "event encoding failed")
    before := { before with heap }
    let .ok address := rawSliceElementAddress? extractedProgram referenceType annotations index
      | throw (IO.userError "annotation addressing failed")
    let annotation := if index == 0 then TypeNameProof.nominalValue 0 else IRTypeRefProof.referenceValue kind.reference
    let .ok heap := writeNativeValue 64 extractedProgram before before.heap referenceType address
      annotation | throw (IO.userError "annotation encoding failed")
    before := { before with heap }
  let region := source_value Extracted.«ir::body_events».Types.«Region».mk
    [.rawSlice eventType events count, .rawSlice referenceType annotations count, .boolean true, .signed .i32 count]
  let .done tree built := evalExpr 1000 extractedProgram before
    (.call Extracted.«ir::body_tree».Functions.«build».core.id [.value region, .value (.signed .i32 count)])
    | throw (IO.userError "constructor tree builder trapped")
  let .structure _ [_, _, _, _, .signed .i32 builtCount] := tree
    | throw (IO.userError "constructor tree builder rejected")
  unless builtCount == (count : Int) do throw (IO.userError "constructor tree builder rejected nodes")
  let .ok (.structure _ fields) := readNativeValue 64 extractedProgram built.heap viewType 2944
    | throw (IO.userError "constructor View layout failed")
  let view := viewValue tree types.value names.value (fields[3]?.getD .unit) 0 1
    (.rawSlice (.scalar (.signed .i32)) 16 32) capacity
  let .ok heap := writeNativeValue 64 extractedProgram built built.heap viewType 2944 view
    | throw (IO.userError "constructor View encoding failed")
  let printing := { built with heap }
  let function := if dispatch then Extracted.«verified::lean_typed_body».Functions.«surface_expression_output».core
    else Extracted.«verified::lean_typed_body».Functions.«surface_constructor_output».core
  let .done result after := evalExpr 2000 extractedProgram printing
    (.call function.id ([.rawSlice viewType 3384 1, .signed .i32 0, .signed .i32 3].map Expr.value))
    | throw (IO.userError "constructor printing trapped")
  unless result == .signed .i32 (if short then -1 else (3 + expected.length : Nat)) do
    throw (IO.userError s!"wrong constructor result: {spelling}, short={short}, dispatch={dispatch}")
  let .ok output := after.heap.loadBytes 16 128 | throw (IO.userError "constructor output unreadable")
  if !short then
    unless output == List.replicate 3 90 ++ expected ++ List.replicate (128 - 3 - expected.length) 90 do
      throw (IO.userError s!"wrong constructor payload order/text: {spelling}")
  for index in List.range 128 do
    if index < 3 || capacity ≤ index then
      unless output[index]?.getD 0 == 90 do throw (IO.userError "constructor wrote outside its buffer")
  unless after.locals == printing.locals && after.i32ArrayViews.isEmpty &&
      after.world.standardOutput == printing.world.standardOutput &&
      after.world.standardError == printing.world.standardError && after.world.calls == printing.world.calls &&
      after.world.opaqueCalls.isEmpty &&
      (after.cells.take printing.cells.length).map (fun cell => (cell.id, cell.value)) ==
        printing.cells.map (fun cell => (cell.id, cell.value)) do
    throw (IO.userError "constructor changed caller state")
  for block in printing.heap.blocks.drop 1 do
    let .ok retained := after.heap.loadBytes block.base block.size
      | throw (IO.userError "constructor input storage unreadable")
    unless retained == block.bytes do throw (IO.userError "constructor changed native input storage")

#eval (do
  for (expressions, spelling) in [
      ([], ""), ([Expression.integer 7], " (7)"),
      ([.integer 7, .integer 3], " (7) (3)"),
      ([.unary .negate (.integer 7), .literal true, .integer 3], " ((-(7))) (true) (3)"),
      ([.binary .add (.integer 2) (.integer 3), .integer 9], " ((2 + 3)) (9)"),
      ([.localName 2 (World.utf8Bytes "Choice"), .integer 7], " («Choice») (7)")] do
    for dispatch in [false, true] do
      check expressions spelling false dispatch
      check expressions spelling true dispatch
  : IO Unit)

end ConstructorPayloadTests
