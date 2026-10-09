import verified_compiler.tests.direct_surface_name

namespace IdentifierTests

open Lanius Lanius.Core Lanius.Semantics Lanius.Memory
open SymbolSpellingProof

private def refType : Ty := match referenceValue 0 0 with
  | .structure id _ => .structure id | _ => .unit
private def emptyRefs : Value := .rawSlice refType 0 0
private def constantType : Ty := match source_value Extracted.«ir::symbol_catalog».Types.«ConstantName».mk [] with
  | .structure id _ => .structure id | _ => .unit
private def path : Value := source_value Extracted.«ir::symbol_catalog».Types.«ModulePath».mk [emptyRefs, .signed .i32 0]

-- Distinct source units and spare token rows catch accidental global/local
-- token confusion. Native nominal slices descend from their high-word handle.
def fixture (spelling : String) (bad : Nat := 0) (outputSize : Nat := 64) : Except Trap (State × Catalog) := do
  let payload := World.utf8Bytes spelling
  let sourceBytes := World.utf8Bytes ("unused!@" ++ spelling ++ "#")
  let sourceCount := sourceBytes.length
  let unit : UnitSpan := {
    sourceOffset := if bad == 4 then sourceCount + 1 else 7
    sourceLength := payload.length + 2
    tokenOffset := if bad == 5 then 4 else 1
    tokenCount := 2
    modulePath := path }
  let catalog : Catalog := {
    bytes := .rawSlice (.scalar (.signed .i32)) 256 sourceCount, sourceCount,
    tokens := .rawSlice tokenType 600 4, tokenCount := 4, tokenStorage := 512,
    units := .rawSlice unitType 872 2, unitCount := 2,
    types := emptyRefs, variants := emptyRefs, fields := emptyRefs,
    functions := emptyRefs, constants := .rawSlice constantType 0 0,
    typeCount := 0, variantCount := 0, fieldCount := 0, functionCount := 0, constantCount := 0 }
  let state : State := { heap := {
    blocks := [
      { base := 16, size := outputSize, alignment := 4, bytes := List.replicate outputSize 90 },
      { base := 256, size := sourceCount * 4, alignment := 4,
        bytes := sourceBytes.flatMap (fun byte => i32Bytes byte.toNat) },
      { base := 512, size := 96, alignment := 8, bytes := List.replicate 96 0 },
      { base := 768, size := 112, alignment := 8, bytes := List.replicate 112 0 }],
    nextAddress := 1024 } }
  let unitZero : UnitSpan := { sourceOffset := 0, sourceLength := 7, tokenOffset := 0, tokenCount := 1, modulePath := path }
  let heap ← writeNativeValue 64 extractedProgram state state.heap unitType 824 unitZero.value
  let heap ← writeNativeValue 64 extractedProgram state heap unitType 768 unit.value
  let heap ← writeNativeValue 64 extractedProgram state heap tokenType 584 (identifierRow 0 6)
  let heap ← writeNativeValue 64 extractedProgram state heap tokenType 560 (identifierRow 0 1)
  let selected := if bad == 1 then
      source_value Extracted.«verified::token».Types.«TokenRow».mk
        [source_value Extracted.«verified::token».Types.«TokenKind».«Integer» [], .signed .i32 1, .signed .i32 2]
    else identifierRow 1 (if bad == 2 then 1 else if bad == 3 then payload.length + 4 else payload.length + 1)
  let heap ← writeNativeValue 64 extractedProgram state heap tokenType 536 selected
  let heap ← writeNativeValue 64 extractedProgram state heap tokenType 512 (identifierRow 0 1)
  return ({ state with heap } |>.bindLocal 902 (.signed .i32 91), catalog)

private def check (spelling : String) (escaped : Bool) (position : Nat) (short : Bool := false)
    (bad : Nat := 0) (unit : Int := 1) (token : Int := 1) : IO Unit := do
  let .ok (before, catalog) := fixture spelling bad | throw (IO.userError "identifier fixture is not representable")
  let expected := World.utf8Bytes (if escaped then "«" ++ spelling ++ "»" else spelling)
  let capacity := position + expected.length - (if short then 1 else 0)
  let function := if escaped then Extracted.«verified::lean_syntax».Functions.«escaped_identifier».core
    else SourceIdentifierProof.source
  let .done result after := evalExpr 400 extractedProgram before
      (.call function.id ([.rawSlice (.scalar (.signed .i32)) 16 16, .signed .i32 capacity,
        .signed .i32 position, catalog.value, referenceValue unit token].map Expr.value))
    | throw (IO.userError "identifier printing trapped")
  let valid := bad == 0 && unit == 1 && token == 1
  let accepted := valid && !short
  unless result == .signed .i32 (if accepted then (position + expected.length : Nat) else -1) do
    throw (IO.userError s!"wrong identifier result for {spelling}, escaped={escaped}, short={short}, bad={bad}")
  let .ok output := after.heap.loadBytes 16 64 | throw (IO.userError "identifier output became unreadable")
  if accepted then
    unless (output.drop position).take expected.length == expected do throw (IO.userError "wrong identifier bytes")
  for index in List.range 64 do
    if index < position || capacity ≤ index || (!valid && !escaped) then
      unless output[index]?.getD 0 == 90 do throw (IO.userError "identifier wrote outside its permitted prefix")
  unless after.locals == before.locals do throw (IO.userError "identifier changed caller scope")
  unless (after.cells.take before.cells.length).map (fun cell => (cell.id, cell.value)) ==
      before.cells.map (fun cell => (cell.id, cell.value)) do throw (IO.userError "identifier changed caller cells")
  for block in before.heap.blocks.drop 1 do
    let .ok retained := after.heap.loadBytes block.base block.size
      | throw (IO.userError "identifier made source/catalog storage unreadable")
    unless retained == block.bytes do throw (IO.userError "identifier changed source/catalog storage")
  unless after.world.standardOutput == before.world.standardOutput &&
      after.world.standardError == before.world.standardError && after.world.calls.isEmpty &&
      after.world.opaqueCalls.isEmpty && after.i32ArrayViews.isEmpty do
    throw (IO.userError "identifier changed runtime state")
  if !escaped then
    unless after.heap.nextAddress == before.heap.nextAddress do throw (IO.userError "source copy allocated storage")

private def checkBodyName (spelling : String) (localName : Bool) (unit : Int := 1) : IO Unit := do
  let .ok (sample, catalog) := fixture spelling | throw (IO.userError "body-name fixture failed")
  let before := { sample with heap := { sample.heap with
    blocks := sample.heap.blocks ++ [{ base := 1088, size := 448, alignment := 8, bytes := List.replicate 448 0 }]
    nextAddress := 1664 } }
  let .ok (.structure _ fields) := readRawSliceIndex extractedProgram before SurfaceBooleanProof.viewType 1528 1 0
    | throw (IO.userError "zero native View did not decode")
  let view := SurfaceBooleanProof.viewValue (fields[0]?.getD .unit) (fields[1]?.getD .unit) catalog.value
    (fields[3]?.getD .unit) 0 unit (.rawSlice (.scalar (.signed .i32)) 16 16) 64
  let .ok heap := writeNativeValue 64 extractedProgram before before.heap SurfaceBooleanProof.viewType 1088 view
    | throw (IO.userError "body-name View could not be stored")
  let printing := { before with heap }
  let function := if localName then Extracted.«verified::lean_typed_body».Functions.«surface_name».core
    else Extracted.«verified::lean_typed_body».Functions.«surface_reference».core
  let argument := if localName then Value.signed .i32 1 else referenceValue 1 1
  let .done cursor printed := evalExpr 400 extractedProgram printing
      (.call function.id [.value (.rawSlice SurfaceBooleanProof.viewType 1528 1), .value argument, .value (.signed .i32 3)])
    | throw (IO.userError "body name printing trapped")
  let rejected := localName && unit < 0
  let expected := World.utf8Bytes ("«" ++ spelling ++ "»")
  unless cursor == .signed .i32 (if rejected then -1 else (3 + expected.length : Nat)) do
    throw (IO.userError "body name returned the wrong cursor")
  let .ok bytes := printed.heap.loadBytes 16 64 | throw (IO.userError "body name lost output storage")
  unless bytes == (if rejected then List.replicate 64 90 else
      List.replicate 3 90 ++ expected ++ List.replicate (61 - expected.length) 90) do
    throw (IO.userError "body name changed the wrong bytes")
  let .ok retainedView := readRawSliceIndex extractedProgram printed SurfaceBooleanProof.viewType 1528 1 0
    | throw (IO.userError "body name destroyed the native View")
  unless retainedView == view && printed.locals == printing.locals do throw (IO.userError "body name changed input or caller scope")

#eval (do
  for spelling in ["Some", "selected", "value", "match", "if", "do", "_name9", "identifier_crossing_many_output_words"] do
    for escaped in [false, true] do
      for position in [0, 3] do check spelling escaped position
      check spelling escaped 3 true
  for escaped in [false, true] do
    for bad in [1, 2, 3, 4, 5] do check "Some" escaped 3 false bad
    for (unit, token) in [((-1 : Int), 1), (2, 1), (1, -1), (1, 2)] do
      check "Some" escaped 3 false 0 unit token
  -- Unit bounds reject even when both output and backing descriptors are invalid.
  let .ok (_, catalog) := fixture "Some" | throw (IO.userError "invalid-reference fixture failed")
  for unit in [(-1 : Int), 2] do
    let .done result after := evalExpr 100 extractedProgram {}
        (.call SourceIdentifierProof.source.id
          ([.unit, .signed .i32 (-1), .signed .i32 2147483647, catalog.value, referenceValue unit 1].map Expr.value))
      | throw (IO.userError "out-of-range identifier reference accessed storage")
    unless result == .signed .i32 (-1) && after.heap.blocks.isEmpty &&
        after.heap.nextAddress == ({} : Heap).nextAddress do
      throw (IO.userError "out-of-range identifier rejection had heap effects")
  for spelling in ["Some", "selected", "match"] do
    for localName in [false, true] do checkBodyName spelling localName
  checkBodyName "Some" false (-1)
  checkBodyName "Some" true (-1) : IO Unit)

end IdentifierTests
