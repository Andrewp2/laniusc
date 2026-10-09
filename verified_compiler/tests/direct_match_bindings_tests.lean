import verified_compiler.tests.direct_surface_match
import verified_compiler.tests.direct_declaration_name_tests

namespace MatchBindingsTests

open Lanius Lanius.Core Lanius.Semantics Lanius.Memory
open SurfaceBooleanProof SymbolSpellingProof MatchMetadataProof

private def source := Extracted.«verified::lean_typed_body».Functions.«surface_match_output».core
private inductive Route where
  | bindings | continuation | arm | arms | matchCall | expression
  deriving BEq

/-- Execute binding traversal, its continuation, or the complete arm body over
    builder-produced native events. Expected text is independent of the proof. -/
private def check (tokens : List Nat) (expectedText : String) (short : Bool := false)
    (bad : Nat := 0) (wildcard : Bool := false) (route : Route := .bindings)
    (lastArm : Bool := false) (enclosed : Bool := false) (nonAtom : Bool := false) : IO Unit := do
  let wholeCall := route == .matchCall || route == .expression
  let enclosed := enclosed || route == .expression
  let wholeLoop := route == .arms || wholeCall
  let wholeArm := route == .arm || wholeLoop
  let withTail := route != .bindings
  let armText := (if wholeArm then
      "      | " ++ (if lastArm then "_" else ".«Choice»") else "") ++
    expectedText ++ (if withTail then (if lastArm then " => 9\n" else " => 7\n") else "") ++
    (if wholeLoop && !lastArm then "      | _ => 9\n" else "")
  let expected := World.utf8Bytes (if wholeCall then
    (if enclosed then "(" else "") ++ "match " ++ (if nonAtom then "((+(0)))" else "0") ++
      " with\n" ++ armText ++ (if enclosed then ")" else "") else armText)
  let capacity := 3 + expected.length - (if short then 1 else 0)
  let .ok (sample, names) := DeclarationNameTests.fixture
    | throw (IO.userError "match binding naming fixture failed")
  -- Type 1 / ordinal 1 selects global variant 3, whose name is unit 1 / token 2.
  -- Distinct indexes catch confusion between type, ordinal, slot, and token.
  let variantType : Ty := match source_value Extracted.«ir::type_catalog».Types.«Variant».mk [] with
    | .structure id _ => .structure id | _ => .unit
  let fieldType : Ty := match source_value Extracted.«ir::type_catalog».Types.«Field».mk [] with
    | .structure id _ => .structure id | _ => .unit
  let types : ConstructorNameProof.Table := {
    declarations := .rawSlice ConstructorNameProof.declarationType 2136 2, typeCount := 2,
    variants := .rawSlice variantType 0 0, variantCount := 4,
    fields := .rawSlice fieldType 0 0, fieldCount := 0 }
  let names := if wholeArm then { names with
    variants := .rawSlice ConstructorNameProof.referenceType 2216 4, variantCount := 4 } else names
  let variant : Int := if bad == 1 || wildcard then -1 else if bad == 2 then -2 else if wholeArm then 1 else 0
  let declared : Int := if bad == 3 then tokens.length + 1 else if bad == 4 then 2147483647
    else if bad == 6 then -1 else tokens.length
  let armEntries := [IRShapeProof.armEvent variant declared] ++ tokens.map (fun (token : Nat) =>
      if bad == 5 then source_value Extracted.«ir::body_events».Types.«Event».«ExpressionLocal» [bindingValue token]
      else bindingEvent token) ++
    [SurfaceIntegerProof.integerEvent 7]
  let scrutinee := (if nonAtom then [SurfaceUnaryProof.Unary.positive.event] else []) ++
    [SurfaceIntegerProof.integerEvent 0]
  let entries := if withTail then [IRShapeProof.matchEvent .I32 (if wholeArm then 1 else 0) 2] ++ scrutinee ++
      armEntries ++ [IRShapeProof.armEvent (-1) 0, SurfaceIntegerProof.integerEvent 9] else armEntries
  let parent := if withTail then (if lastArm then tokens.length + 4 else 2) + (if nonAtom then 1 else 0) else 0
  let armOrdinal : Nat := if withTail then (if lastArm then 1 else 0) else 17
  let count := entries.length
  let eventBase := 3456
  let events := eventBase + count * 40 - 8
  let backed : State := { sample with heap := { sample.heap with
    blocks := sample.heap.blocks ++ (if wholeArm then [
      { base := 2048, size := 96, alignment := 8, bytes := List.replicate 96 0 },
      { base := 2160, size := 64, alignment := 8, bytes := List.replicate 64 0 }] else []) ++ [
      { base := 2304, size := 448, alignment := 8, bytes := List.replicate 448 0 },
      { base := eventBase, size := count * 40, alignment := 8, bytes := List.replicate (count * 40) 0 }]
    nextAddress := eventBase + count * 40 } }
  let mut before := backed
  if wholeArm then
    let .ok heap := writeNativeValue 64 extractedProgram before before.heap
        ConstructorNameProof.declarationType 2096 (ConstructorNameProof.enumeration 0 0 2)
      | throw (IO.userError "match arm first type encoding failed")
    let .ok heap := writeNativeValue 64 extractedProgram before heap
        ConstructorNameProof.declarationType 2048 (ConstructorNameProof.enumeration 1 2 2)
      | throw (IO.userError "match arm selected type encoding failed")
    before := { before with heap }
    for slot in List.range 4 do
      let reference := if slot == 3 then referenceValue 1 2 else referenceValue 0 0
      let .ok heap := writeNativeValue 64 extractedProgram before before.heap
          ConstructorNameProof.referenceType (2160 + (3 - slot) * 16) reference
        | throw (IO.userError "match arm variant reference encoding failed")
      before := { before with heap }
  for (value, index) in entries.zipIdx do
    let .ok address := rawSliceElementAddress? extractedProgram eventType events index
      | throw (IO.userError "match binding event addressing failed")
    let .ok heap := writeNativeValue 64 extractedProgram before before.heap eventType address value
      | throw (IO.userError "match binding event encoding failed")
    before := { before with heap }
  let region := source_value Extracted.«ir::body_events».Types.«Region».mk
    [.rawSlice eventType events count, .rawSlice SurfaceDispatchProof.referenceType 0 0,
      .boolean false, .signed .i32 count]
  let .done tree built := evalExpr 1000 extractedProgram before
    (.call Extracted.«ir::body_tree».Functions.«build».core.id [.value region, .value (.signed .i32 count)])
    | throw (IO.userError "match binding builder trapped")
  let .structure _ [_, _, _, _, .signed .i32 builtCount] := tree
    | throw (IO.userError "match binding builder rejected")
  if bad != 0 then
    unless builtCount == 0 && built.locals == before.locals && built.i32ArrayViews.isEmpty &&
        built.world.standardOutput == before.world.standardOutput &&
        built.world.standardError == before.world.standardError && built.world.opaqueCalls.isEmpty do
      throw (IO.userError s!"malformed arm accepted or changed runtime state: {bad}")
    for block in before.heap.blocks do
      let .ok retained := built.heap.loadBytes block.base block.size
        | throw (IO.userError "rejected arm lost existing storage")
      unless retained == block.bytes do throw (IO.userError "rejected arm changed existing storage")
    for cell in before.cells do
      unless built.cell? cell.id == before.cell? cell.id do throw (IO.userError "rejected arm changed caller cell")
    return
  unless builtCount == (count : Int) do throw (IO.userError "match binding builder rejected nodes")
  let .ok (.structure _ fields) := readNativeValue 64 extractedProgram built.heap viewType 2304
    | throw (IO.userError "match binding View layout failed")
  let view := viewValue tree (if wholeArm then types.value else fields[1]?.getD .unit)
    names.value (fields[3]?.getD .unit) 0 1
    (.rawSlice (.scalar (.signed .i32)) 16 32) capacity
  let .ok heap := writeNativeValue 64 extractedProgram built built.heap viewType 2304 view
    | throw (IO.userError s!"match binding View encoding failed: tokens={tokens}, wholeArm={wholeArm}")
  let printing := { built with heap }
  let initial := printing.bindLocals ([
    (source.argumentId 0, .rawSlice viewType 2744 1),
    (source.argumentId 1, .signed .i32 0),
    (source.bindingId 0, view), (source.bindingId 1, .rawSlice eventType events count),
    (source.bindingId 2, IRShapeProof.matchHeaderValue .I32 (if wholeArm then 1 else 0) 2),
    (source.bindingId 3, .signed .i32 3), (source.bindingId 4, .signed .i32 parent),
    (source.bindingId 5, .signed .i32 armOrdinal)] ++ if wholeArm then [] else [
    (source.bindingId 6, IRShapeProof.armValue (if lastArm then -1 else variant) tokens.length),
    (source.bindingId 7, .signed .i32 (parent + 1 : Nat)), (source.bindingId 8, .signed .i32 0)])
  let after ← if wholeCall then do
      let values : List Value := [.rawSlice viewType 2744 1, .signed .i32 0, .signed .i32 3]
      let function := if route == .expression then SurfaceDispatchProof.expression.id else source.id
      let values := values ++ if route == .expression then [] else [.boolean enclosed]
      let .done (.signed .i32 cursor) after := evalExpr 6000 extractedProgram printing
          (.call function (values.map Expr.value))
        | throw (IO.userError "complete match call did not return normally")
      unless cursor == (if short then -1 else ((3 + expected.length : Nat) : Int)) do
        throw (IO.userError s!"wrong full match result: route={wholeCall}, short={short}")
      pure after
    else if wholeArm then
      match execStmt 3000 extractedProgram initial
          (if wholeLoop then MatchArmsProof.armLoop else MatchArmProof.armBody) with
      | .done .next after => pure after
      | _ => throw (IO.userError "complete match arm did not terminate normally")
    else do
      let parts := source.whileLoop 1
      let .done .next bound := execStmt 2000 extractedProgram initial (.whileLoop parts.1 parts.2)
        | throw (IO.userError "match binding traversal did not terminate normally")
      if withTail then
        match execStmt 3000 extractedProgram bound MatchArmTailProof.tail with
        | .done .next after => pure after
        | _ => throw (IO.userError "match arm continuation did not terminate normally")
      else pure bound
  unless wholeCall || (after.local? (source.bindingId 3) == some (.signed .i32
      (if short && !tokens.isEmpty then -1 else (3 + expected.length : Nat))) &&
      (wholeArm || (after.local? (source.bindingId 7) == some (.signed .i32 (parent + tokens.length + 1 : Nat)) &&
        after.local? (source.bindingId 8) == some (.signed .i32 tokens.length))) &&
      after.local? (source.bindingId 4) == some (.signed .i32
        (if wholeLoop || lastArm then -1 else if withTail then tokens.length + 4 else parent)) &&
      after.local? (source.bindingId 5) == some (.signed .i32
        (if wholeLoop then 2 else armOrdinal + if withTail then 1 else 0 : Nat))) do
    throw (IO.userError s!"wrong binding cursor, counter or final body: {tokens}, short={short}")
  let .ok output := after.heap.loadBytes 16 128 | throw (IO.userError "match binding output unreadable")
  if !short then
    unless output == List.replicate 3 90 ++ expected ++ List.replicate (128 - 3 - expected.length) 90 do
      throw (IO.userError s!"wrong binding order/text: {tokens}")
  for index in List.range 128 do
    if index < 3 || capacity ≤ index then
      unless output[index]?.getD 0 == 90 do throw (IO.userError "binding wrote outside output capacity")
  let caller := if wholeCall then printing else initial
  unless after.locals == caller.locals && after.i32ArrayViews.isEmpty &&
      after.world.standardOutput == printing.world.standardOutput &&
      after.world.standardError == printing.world.standardError && after.world.calls == printing.world.calls &&
      after.world.opaqueCalls.isEmpty do
    throw (IO.userError "binding traversal changed scope/runtime state")
  let changed := if wholeCall then [] else [initial.cellId? (source.bindingId 3), initial.cellId? (source.bindingId 7),
    initial.cellId? (source.bindingId 8)] ++ if withTail then
      [initial.cellId? (source.bindingId 4), initial.cellId? (source.bindingId 5)] else []
  for cell in caller.cells do
    if !(changed.contains (some cell.id)) then
      unless after.cell? cell.id == caller.cell? cell.id do
        throw (IO.userError "binding traversal changed a non-control cell")
  for block in printing.heap.blocks.drop 1 do
    let .ok retained := after.heap.loadBytes block.base block.size
      | throw (IO.userError "binding traversal lost input storage")
    unless retained == block.bytes do throw (IO.userError "binding traversal changed native input storage")

#eval (do
  for (tokens, expected) in [([], ""), ([2], " «Choice»"),
      ([0, 1, 2], " «verified» «syntax» «Choice»"), ([2, 0], " «Choice» «verified»")] do
    check tokens expected
    check tokens expected true
  check [] "" false 0 true
  for route in [Route.continuation, .arm, .arms] do
    check [] "" (route := route)
    check [2] " «Choice»" (route := route)
    check [0, 1, 2] " «verified» «syntax» «Choice»" (route := route)
    check [] "" (wildcard := true) (route := route) (lastArm := true)
  for bad in [1, 2, 3, 4, 5, 6] do check [2, 0] "" false bad
  for (tokens, expected) in [([], ""), ([2], " «Choice»"),
      ([0, 1, 2], " «verified» «syntax» «Choice»")] do
    for nonAtom in [false, true] do
      for enclosed in [false, true] do
        check tokens expected (route := .matchCall) (enclosed := enclosed) (nonAtom := nonAtom)
      check tokens expected (route := .expression) (nonAtom := nonAtom)
  for route in [Route.matchCall, .expression] do
    for nonAtom in [false, true] do
      check [2] " «Choice»" (short := true) (route := route) (enclosed := true) (nonAtom := nonAtom)
  for count in [0, 2] do
    let before := ({} : State).bindLocals [
      (source.bindingId 2, IRShapeProof.matchHeaderValue .I32 1 count),
      (source.bindingId 5, .signed .i32 count)]
    let .done .next after := execStmt 20 extractedProgram before MatchArmsProof.armLoop
      | throw (IO.userError "empty outer loop ran an arm body")
    unless after.locals == before.locals &&
        after.cells.map (fun cell => (cell.id, cell.value)) == before.cells.map (fun cell => (cell.id, cell.value)) &&
        after.nextCell == before.nextCell &&
        after.heap.blocks.isEmpty && after.world.calls.isEmpty && after.world.opaqueCalls.isEmpty &&
        after.i32ArrayViews.isEmpty do throw (IO.userError "empty outer loop changed state")
  IO.println "native match cases: 9 traversals, 4 continuations, 4 complete arms, 6 outer loops, 6 malformed rejections, 12 full helpers, 6 expression calls, 4 short buffers"
  : IO Unit)

end MatchBindingsTests
