import SelfCore
import Lanius.Semantics.SourceValue
import Lanius.Semantics

namespace IRValidatorTests
open Lanius Lanius.Core Lanius.Memory Lanius.Semantics
private def source := Extracted.«ir::body_tree».Functions.«valid».core
private def leaf := source_value Extracted.«ir::body_events».Types.«Event».«ExpressionPointerNull» []
private def parent := source_value Extracted.«ir::body_events».Types.«Event».«ExpressionUnaryPositive» []
private def statement := source_value Extracted.«ir::body_events».Types.«Event».«StatementSkip» []
private def eventType : Ty := match leaf with | .enumeration id _ _ => .enumeration id | _ => .unit
private def referenceType : Ty := match source_value Extracted.«ir::type_ref».Types.«TypeRef».«I32» [] with | .enumeration id _ _ => .enumeration id | _ => .unit
private def eventBytes : Value → List UInt8
  | .enumeration _ tag _ => encodeNatLE 4 tag ++ List.replicate 36 0
  | _ => []

#eval (do
  let cases : List (String × List Value × List Int × Int × Nat × Nat × Bool) := [
    ("unary", [parent, leaf], [2, 2], 2, 2, 2, true),
    ("parent arity", [parent], [1], 1, 1, 1, false),
    ("child category", [parent, statement], [2, 2], 2, 2, 2, false),
    ("negative endpoint", [parent, leaf], [2, -1], 2, 2, 2, false),
    ("nonadvancing endpoint", [parent, leaf], [2, 1], 2, 2, 2, false),
    ("out-of-range endpoint", [parent, leaf], [2, 3], 2, 2, 2, false),
    ("parent mismatch", [parent, leaf], [1, 2], 2, 2, 2, false),
    ("forest", [leaf, leaf], [1, 2], 2, 2, 2, false),
    ("independent spare lengths", [parent, leaf], [2, 2], 2, 5, 3, true)] ++
    ([0, -1, -2147483648] : List Int).map (fun count => (s!"unreadable count {count}", [], [], count, 7, 9, false))
  for (label, nodes, endpoints, count, eventsLength, endsLength, expected) in cases do
    let eventData := nodes.reverse.flatMap eventBytes
    let endData := endpoints.flatMap i32Bytes
    let address := if nodes.isEmpty then 4096 else 16 + nodes.length * 40 - 8
    let before : State := ({
      heap := { blocks := (if nodes.isEmpty then [] else [
      { base := 16, size := eventData.length, alignment := 8, bytes := eventData },
      { base := 256, size := endData.length, alignment := 4, bytes := endData }]), nextAddress := 1, remaining := some 0 },
      world := { standardOutput := [17] } } : State).bindLocal ((source.parameters[0]?.getD (0, .unit)).1) (.signed .i32 91)
    let tree := source_value Extracted.«ir::body_tree».Types.«Tree».mk
      [.rawSlice eventType address eventsLength, .rawSlice referenceType 8192 37, .boolean true, .rawSlice (.scalar (.signed .i32)) 256 endsLength, .signed .i32 count]
    for (node, index) in nodes.zipIdx do
      unless (readRawSliceIndex extractedProgram before eventType address eventsLength index).toOption == some node && (readRawSliceIndex extractedProgram before (.scalar (.signed .i32)) 256 endsLength index).toOption == some (.signed .i32 endpoints[index]!) do throw (IO.userError s!"{label}: fixture decoding")
    let .done actual after := evalExpr 200 extractedProgram before (.call source.id [.value tree])
      | throw (IO.userError s!"{label}: validator did not finish")
    unless actual == .boolean expected && after.locals == before.locals && (after.cells.take before.cells.length).map (fun cell => (cell.id, cell.value)) == before.cells.map (fun cell => (cell.id, cell.value)) &&
        reprStr after.heap == reprStr before.heap && reprStr after.world == reprStr before.world && reprStr after.i32ArrayViews == reprStr before.i32ArrayViews do throw (IO.userError s!"{label}: result or caller frame")
  IO.println s!"{cases.length} actual Core validator cases passed" : IO Unit)
end IRValidatorTests
