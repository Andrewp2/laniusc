import verified_compiler.tests.direct_surface_expression_tree
import verified_compiler.tests.direct_identifier_tests

namespace SurfaceExpressionTreeTests

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics Lanius.Extraction
open SurfaceBooleanProof SurfaceExpressionTreeProof SurfaceOperationsProof

private def kind : Expression → ScalarKind
  | .literal _ | .unary .not _ => .boolean
  | .integer _ | .localName _ _ => .i32
  | .unary _ child => kind child
  | .binary operation leftChild _ => match operation with
    | .andThen | .orElse | .equal | .notEqual | .less | .lessEqual | .greater | .greaterEqual => .boolean
    | _ => kind leftChild
def nodes (expression : Expression) : List (Value × ScalarKind) := match expression with
  | .literal value => [(booleanEvent value, .boolean)]
  | .integer value => [(SurfaceIntegerProof.integerEvent value, .i32)]
  | .localName token _ => [(SurfaceLocalProof.localEvent token, .i32)]
  | .unary operation child => (operation.event, kind expression) :: nodes child
  | .binary operation leftChild rightChild => (operation.event, kind expression) :: (nodes leftChild ++ nodes rightChild)

private def read (state : State) (type : Ty) (address length index : Nat) : IO Value :=
  match readRawSliceIndex extractedProgram state type address length index with
  | .ok value => pure value
  | .error _ => throw (IO.userError "IR became unreadable")

private def run (expression : Expression) (spelling : String) (capacity : Nat := 192)
    (badAnnotation : Bool := false) (nameSpelling : String := "selected") : IO Unit := do
  let expected := World.utf8Bytes spelling
  unless expression.output == expected do throw (IO.userError "incorrect independently specified fixture text")
  let entries := nodes expression
  let values := entries.map Prod.fst
  let count := values.length
  let eventsAddress := 1568 + count * 40 - 8
  let annotationsBase := 1568 + count * 40 + 16
  let annotationsAddress := annotationsBase + count * 16 - 8
  let eventType := SurfaceBooleanProof.eventType
  let referenceType := SurfaceDispatchProof.referenceType
  let .ok (sample, catalog) := IdentifierTests.fixture nameSpelling 0 192
    | throw (IO.userError "expression naming fixture is not representable")
  let initial : State := { sample with heap := { sample.heap with
    blocks := sample.heap.blocks ++ [
      { base := 1088, size := 448, alignment := 8,
        bytes := List.replicate 424 0 ++ encodeNatLE 8 16 ++ encodeNatLE 8 48 ++
          i32Bytes capacity ++ List.replicate 4 0 },
      { base := 1568, size := count * 40, alignment := 8, bytes := List.replicate (count * 40) 0 },
      { base := annotationsBase, size := count * 16, alignment := 8, bytes := List.replicate (count * 16) 0 }]
    nextAddress := annotationsBase + count * 16 } }
  let mut before := initial.bindLocal 77 (.signed .i32 345)
  for ((value, annotationKind), index) in entries.zipIdx do
    let .ok address := rawSliceElementAddress? extractedProgram eventType eventsAddress index
      | throw (IO.userError "event addressing failed")
    let .ok heap := writeNativeValue 64 extractedProgram before before.heap eventType address value
      | throw (IO.userError "event encoding failed")
    before := { before with heap := heap }
    let .ok address := rawSliceElementAddress? extractedProgram referenceType annotationsAddress index
      | throw (IO.userError "annotation addressing failed")
    let .ok heap := writeNativeValue 64 extractedProgram before before.heap referenceType address
      (IRTypeRefProof.referenceValue (if badAnnotation then .I32 else annotationKind.reference))
      | throw (IO.userError "annotation encoding failed")
    before := { before with heap := heap }
  let region := source_value Extracted.«ir::body_events».Types.«Region».mk
    [.rawSlice eventType eventsAddress count, .rawSlice referenceType annotationsAddress count,
      .boolean true, .signed .i32 count]
  let .done tree built := evalExpr 1000 extractedProgram before
    (.call Extracted.«ir::body_tree».Functions.«build».core.id [.value region, .value (.signed .i32 count)])
    | throw (IO.userError "builder trapped")
  let .structure _ [_, _, _, ends, .signed .i32 builtCount] := tree
    | throw (IO.userError "builder rejected expression tree")
  unless builtCount == (count : Int) do throw (IO.userError "wrong builder count")
  let .ok (.structure _ fields) := readRawSliceIndex extractedProgram built viewType 1528 1 0
    | throw (IO.userError "View metadata unreadable")
  let view := viewValue tree (fields[1]?.getD .unit) catalog.value (fields[3]?.getD .unit) 0 1
    (.rawSlice (.scalar (.signed .i32)) 16 48) capacity
  let .ok heap := writeNativeValue 64 extractedProgram built built.heap viewType 1088 view
    | throw (IO.userError "View encoding failed")
  let printing := { built with heap := heap }
  let .done cursor printed := evalExpr 1000 extractedProgram printing
    (.call Extracted.«verified::lean_typed_body».Functions.«surface_expression_output».core.id
      [.value (.rawSlice viewType 1528 1), .value (.signed .i32 0), .value (.signed .i32 3)])
    | throw (IO.userError "expression tree printing trapped")
  if badAnnotation || capacity < 3 + expected.length then
    unless cursor == .signed .i32 (-1) do throw (IO.userError "invalid/short tree did not reject")
  else
    unless cursor == .signed .i32 (3 + expected.length : Nat) do throw (IO.userError "wrong expression-tree cursor")
    let .ok output := printed.heap.loadBytes 19 expected.length | throw (IO.userError "output unreadable")
    unless output == expected do throw (IO.userError s!"incorrect output for {spelling}")
  let .ok prefixBytes := printed.heap.loadBytes 16 3 | throw (IO.userError "output prefix unreadable")
  unless prefixBytes == [90, 90, 90] do throw (IO.userError "printer wrote before its cursor")
  let untouched := max 3 (min capacity (3 + expected.length))
  let .ok suffix := printed.heap.loadBytes (16 + untouched) (192 - untouched)
    | throw (IO.userError "output suffix unreadable")
  unless suffix == List.replicate (192 - untouched) 90 do throw (IO.userError "printer exceeded its output range")
  unless printed.locals == printing.locals do throw (IO.userError "caller locals changed")
  unless (printed.cells.take printing.cells.length).map (fun cell => (cell.id, cell.value)) ==
      printing.cells.map (fun cell => (cell.id, cell.value)) do throw (IO.userError "caller cells changed")
  for block in sample.heap.blocks.drop 1 do
    let .ok retained := printed.heap.loadBytes block.base block.size
      | throw (IO.userError "expression printer made the naming catalog unreadable")
    unless retained == block.bytes do throw (IO.userError "expression printer changed the naming catalog")
  for (value, index) in values.zipIdx do
    unless (← read printed eventType eventsAddress count index) == value do
      throw (IO.userError "printer changed IR events")
    unless (← read printed referenceType annotationsAddress count index) ==
        (← read printing referenceType annotationsAddress count index) do
      throw (IO.userError "printer changed IR annotations")
    let .rawSlice type address length := ends | throw (IO.userError "endpoints are not a native slice")
    unless (← read printed type address length index) == (← read printing type address length index) do
      throw (IO.userError "printer changed IR endpoints")

#eval (do
  let yes := Expression.literal true
  let no := Expression.literal false
  for left in [yes, no] do
    for right in [yes, no] do
      for operation in [Binary.andThen, Binary.orElse] do
        let .literal a := left | throw (IO.userError "not a literal")
        let .literal b := right | throw (IO.userError "not a literal")
        run (.binary operation left right) s!"({spelling a} {operation.spelling} {spelling b})"
  let asymmetric := Expression.binary .andThen (.unary .not yes) no
  run asymmetric "((!(true)) && false)"
  run (.unary .not (.binary .orElse yes no)) "(!((true || false)))"
  run (.binary .orElse asymmetric (.unary .not no)) "(((!(true)) && false) || (!(false)))"
  run asymmetric "((!(true)) && false)" (3 + (World.utf8Bytes "((!(true)) && false)").length)
  run asymmetric "((!(true)) && false)" (2 + (World.utf8Bytes "((!(true)) && false)").length)
  run asymmetric "((!(true)) && false)" 192 true
  -- Expected strings are independent of the operator specification table.
  for (operation, symbol) in [
      (Binary.equal, "=="), (.notEqual, "!="), (.less, "<"), (.lessEqual, "<="),
      (.greater, ">"), (.greaterEqual, ">="), (.add, "+"), (.subtract, "-"),
      (.multiply, "*"), (.divide, "/"), (.remainder, "%"), (.bitAnd, "&&&"),
      (.bitOr, "|||"), (.bitXor, "^^^"), (.shiftLeft, "<<<"), (.shiftRight, ">>>")] do
    run (.binary operation (.integer 7) (.integer 3)) s!"(7 {symbol} 3)"
  let sum := Expression.binary .add (.integer 2) (.integer 3)
  let difference := Expression.binary .subtract (.integer 7) (.integer 4)
  let product := Expression.binary .multiply sum difference
  run product "((2 + 3) * (7 - 4))"
  run (.binary .andThen (.binary .less sum (.integer 10)) (.binary .greater (.integer 8) (.integer 4)))
    "(((2 + 3) < 10) && (8 > 4))"
  run (.unary .not (.binary .equal (.binary .bitXor (.integer 7) (.integer 3)) (.integer 4))) "(!(((7 ^^^ 3) == 4)))"
  run (.binary .less (.integer (-2147483648)) (.integer 2147483647)) "(-2147483648 < 2147483647)"
  run product "((2 + 3) * (7 - 4))" (3 + (World.utf8Bytes "((2 + 3) * (7 - 4))").length)
  run product "((2 + 3) * (7 - 4))" (2 + (World.utf8Bytes "((2 + 3) * (7 - 4))").length)
  for (operation, symbol) in [(SurfaceUnaryProof.Unary.positive, "+"), (.negate, "-")] do
    for value in [0, 7, 2147483647] do
      run (.unary operation (.integer value)) s!"({symbol}({value}))"
  let negative := Expression.unary .negate (.integer 7)
  run (.unary .negate negative) "(-((-(7))))"
  run (.unary .positive negative) "(+((-(7))))"
  run (.unary .negate (.integer (-2147483648))) "(-(-2147483648))"
  run (.binary .add negative (.integer 3)) "((-(7)) + 3)"
  run (.unary .not (.binary .less negative (.unary .positive (.integer 3)))) "(!(((-(7)) < (+(3)))))"
  run negative "(-(7))" (3 + (World.utf8Bytes "(-(7))").length)
  run negative "(-(7))" (2 + (World.utf8Bytes "(-(7))").length)
  for name in ["selected", "value", "match"] do
    let leaf := Expression.localName 1 (World.utf8Bytes name)
    run leaf s!"«{name}»" (nameSpelling := name)
    run (.unary .negate leaf) s!"(-(«{name}»))" (nameSpelling := name)
    run (.binary .add leaf (.integer 7)) s!"(«{name}» + 7)" (nameSpelling := name)
  let selected := Expression.localName 1 (World.utf8Bytes "selected")
  run (.binary .add selected selected) "(«selected» + «selected»)"
  let namedTree := Expression.binary .multiply (.unary .negate selected)
    (.binary .add selected (.integer 7))
  run namedTree "((-(«selected»)) * («selected» + 7))"
  run (.unary .not (.binary .less selected (.integer 7))) "(!((«selected» < 7)))"
  run namedTree "((-(«selected»)) * («selected» + 7))"
    (3 + (World.utf8Bytes "((-(«selected»)) * («selected» + 7))").length)
  run namedTree "((-(«selected»)) * («selected» + 7))"
    (2 + (World.utf8Bytes "((-(«selected»)) * («selected» + 7))").length) : IO Unit)

end SurfaceExpressionTreeTests
