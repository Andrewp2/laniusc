import verified_compiler.tests.direct_type_name

namespace DeclarationNameTests

open Lanius Lanius.Core Lanius.Semantics Lanius.Memory SymbolSpellingProof DeclarationNameProof

-- Both units contain Choice, but their existing native module paths differ.
-- All nominal arrays use their actual high-word native slice handles.
def fixture (bad : Nat := 0) : Except Trap (State × Catalog) := do
  let spelling := World.utf8Bytes "otherxChoiceverifiedsyntaxChoice"
  let path (address count : Nat) : Value := source_value Extracted.«ir::symbol_catalog».Types.«ModulePath».mk
    [.rawSlice referenceType address count, .signed .i32 (if bad == 1 then 0 else if bad == 2 then 4 else if bad == 4 then -1 else count)]
  let first : UnitSpan := { sourceOffset := 0, sourceLength := 12, tokenOffset := 0, tokenCount := 3, modulePath := path 1768 1 }
  let second : UnitSpan := { sourceOffset := 12, sourceLength := 20, tokenOffset := 3, tokenCount := 3, modulePath := path 1688 2 }
  let references := Value.rawSlice referenceType 1880 2
  let constantType : Ty := match source_value Extracted.«ir::symbol_catalog».Types.«ConstantName».mk [] with
    | .structure id _ => .structure id | _ => .unit
  let catalog : Catalog := {
    bytes := .rawSlice (.scalar (.signed .i32)) 256 spelling.length, sourceCount := spelling.length,
    tokens := .rawSlice tokenType 648 6, tokenCount := 6, tokenStorage := 512,
    units := .rawSlice unitType 872 2, unitCount := 2,
    types := references, variants := .rawSlice referenceType 0 0, fields := .rawSlice referenceType 0 0,
    functions := references, constants := .rawSlice constantType 0 0,
    typeCount := 2, variantCount := 0, fieldCount := 0, functionCount := 2, constantCount := 0 }
  let before : State := { heap := {
    blocks := [
      { base := 16, size := 128, alignment := 4, bytes := List.replicate 128 90 },
      { base := 256, size := spelling.length * 4, alignment := 4, bytes := spelling.flatMap (fun byte => i32Bytes byte.toNat) },
      { base := 512, size := 144, alignment := 8, bytes := List.replicate 144 0 },
      { base := 768, size := 112, alignment := 8, bytes := List.replicate 112 0 },
      { base := 1664, size := 32, alignment := 8, bytes := List.replicate 32 0 },
      { base := 1760, size := 16, alignment := 8, bytes := List.replicate 16 0 },
      { base := 1856, size := 32, alignment := 8, bytes := List.replicate 32 0 }], nextAddress := 2048 } }
  let heap ← writeNativeValue 64 extractedProgram before before.heap unitType 824 first.value
  let heap ← writeNativeValue 64 extractedProgram before heap unitType 768 second.value
  let mut heap := heap
  for (address, start, finish) in [(632, 0, 5), (608, 5, 6), (584, 6, 12), (560, 0, 8), (536, 8, 14), (512, 14, 20)] do
    heap ← writeNativeValue 64 extractedProgram before heap tokenType address (identifierRow start finish)
  heap ← writeNativeValue 64 extractedProgram before heap referenceType 1680 (referenceValue (if bad == 3 then -1 else 1) 0)
  heap ← writeNativeValue 64 extractedProgram before heap referenceType 1664 (referenceValue 1 1)
  heap ← writeNativeValue 64 extractedProgram before heap referenceType 1760 (referenceValue 0 0)
  heap ← writeNativeValue 64 extractedProgram before heap referenceType 1872 (referenceValue 1 2)
  heap ← writeNativeValue 64 extractedProgram before heap referenceType 1856 (referenceValue 0 2)
  return ({ before with heap } |>.bindLocal 902 (.signed .i32 91), catalog)

private def check (unit : Nat) (space : Space) (position : Nat) (short : Bool := false) (bad : Nat := 0)
    (route : Nat := 0) : IO Unit := do
  let .ok (sample, catalog) := fixture bad | throw (IO.userError "qualified name fixture failed")
  let expected := World.utf8Bytes ("Extracted.«" ++ (if unit == 1 then "verified::syntax" else "other") ++
    "»" ++ namespaceText space ++ "«Choice»")
  let capacity := position + expected.length - (if short then 1 else 0)
  -- Decode a zero-initialized native View, then install the real name catalog.
  -- Its other metadata is unused here, but still uses the declared layouts.
  let backed := { sample with heap := { sample.heap with
    blocks := sample.heap.blocks ++ [{ base := 2304, size := 448, alignment := 8, bytes := List.replicate 448 0 }]
    nextAddress := 2816 } }
  let .ok (.structure _ fields) := readNativeValue 64 extractedProgram backed.heap SurfaceBooleanProof.viewType 2304
    | throw (IO.userError "native type-name View did not decode")
  let view := SurfaceBooleanProof.viewValue (fields[0]?.getD .unit) (fields[1]?.getD .unit) catalog.value
    (fields[3]?.getD .unit) 0 (-1) (.rawSlice (.scalar (.signed .i32)) 16 32) capacity
  let .ok heap := writeNativeValue 64 extractedProgram backed backed.heap SurfaceBooleanProof.viewType 2304 view
    | throw (IO.userError "native type-name View could not be stored")
  let before : State := { backed with heap }
  let typeIndex : Nat := if unit == 1 then 0 else 1
  let (function, arguments) : Lanius.Core.Function × List Value := match route with
    | 1 => (Extracted.«verified::lean_syntax».Functions.«type_identifier».core,
      [.rawSlice (.scalar (.signed .i32)) 16 32, .signed .i32 capacity,
        .signed .i32 position, catalog.value, .signed .i32 typeIndex])
    | 2 => (Extracted.«verified::lean_syntax».Functions.«named_type_ref».core,
      [.rawSlice (.scalar (.signed .i32)) 16 32, .signed .i32 capacity,
        .signed .i32 position, fields[1]?.getD .unit, catalog.value, TypeNameProof.nominalValue typeIndex])
    | 3 => (Extracted.«verified::lean_typed_body».Functions.«type_name».core,
      [.rawSlice SurfaceBooleanProof.viewType 2744 1, TypeNameProof.nominalValue typeIndex, .signed .i32 position])
    | _ => (DeclarationNameProof.source,
      [.rawSlice (.scalar (.signed .i32)) 16 32, .signed .i32 capacity,
        .signed .i32 position, catalog.value, referenceValue unit 2, spaceValue space])
  let .done result after := evalExpr 800 extractedProgram before
      (.call function.id (arguments.map Expr.value))
    | throw (IO.userError s!"qualified name trapped: route={route}, unit={unit}, bad={bad}")
  let accepted := bad == 0 && !short
  unless result == .signed .i32 (if accepted then (position + expected.length : Nat) else -1) do
    throw (IO.userError s!"wrong qualified name cursor: unit={unit}, bad={bad}")
  let .ok output := after.heap.loadBytes 16 128 | throw (IO.userError "qualified name destroyed output")
  if accepted then
    unless output == List.replicate position 90 ++ expected ++ List.replicate (128 - position - expected.length) 90 do
      throw (IO.userError "qualified name changed the wrong bytes or namespace")
  for index in List.range 128 do
    if index < position || capacity ≤ index || bad == 1 || bad == 2 || bad == 4 then
      unless output[index]?.getD 0 == 90 do throw (IO.userError "qualified name wrote outside its allowed prefix")
  unless after.locals == before.locals && after.i32ArrayViews.isEmpty &&
      after.world.standardOutput == before.world.standardOutput &&
      after.world.standardError == before.world.standardError && after.world.calls.isEmpty &&
      after.world.opaqueCalls.isEmpty do
    throw (IO.userError "qualified name changed caller/runtime state")
  unless (after.cells.take before.cells.length).map (fun cell => (cell.id, cell.value)) ==
      before.cells.map (fun cell => (cell.id, cell.value)) do throw (IO.userError "qualified name changed caller cells")
  for block in before.heap.blocks.drop 1 do
    let .ok retained := after.heap.loadBytes block.base block.size
      | throw (IO.userError "qualified name destroyed native input storage")
    unless retained == block.bytes do
      throw (IO.userError "qualified name changed native input storage")

#eval (do
  for unit in [0, 1] do
    for space in ([.TypeSpace, .FunctionSpace, .ConstantSpace] : List Space) do
      for position in [0, 3] do
        check unit space position
        check unit space position true
  for bad in [1, 2, 3, 4] do
    for space in ([.TypeSpace, .FunctionSpace, .ConstantSpace] : List Space) do check 1 space 3 false bad
  for route in [1, 2, 3] do
    for unit in [0, 1] do
      for position in [0, 3] do
        check unit .TypeSpace position false 0 route
        check unit .TypeSpace position true 0 route
    for bad in [1, 2, 3, 4] do check 1 .TypeSpace 3 false bad route
  let .ok (_, catalog) := fixture | throw (IO.userError "qualified rejection fixture failed")
  for unit in [(-1 : Int), 2] do
    for space in ([.TypeSpace, .FunctionSpace, .ConstantSpace] : List Space) do
      let .done result after := evalExpr 100 extractedProgram {}
          (.call DeclarationNameProof.source.id ([.unit, .signed .i32 (-1), .signed .i32 2147483647, catalog.value,
            referenceValue unit 2, spaceValue space].map Expr.value))
        | throw (IO.userError "bad qualified unit accessed storage")
      unless result == .signed .i32 (-1) && after.heap.blocks.isEmpty && after.world.calls.isEmpty &&
          after.world.standardOutput.isEmpty && after.world.standardError.isEmpty && after.world.opaqueCalls.isEmpty do
        throw (IO.userError "bad qualified unit had output effects")
  -- Named IDs reject without touching invalid output or catalog backing;
  -- zero-unit synthetic names are intentionally a different branch.
  for units in [0, 2] do
    let names := { catalog with units := .unit, unitCount := units, types := .unit }
    for index in (if units == 0 then [(-1 : Int)] else [-1, 2]) do
      for nominal in [false, true] do
        let function := if nominal then Extracted.«verified::lean_syntax».Functions.«named_type_ref».core
          else Extracted.«verified::lean_syntax».Functions.«type_identifier».core
        let arguments := if nominal then
            [.unit, .signed .i32 (-1), .signed .i32 2147483647, .unit, names.value,
              source_value Extracted.«ir::type_ref».Types.«TypeRef».«Nominal» [.signed .i32 index]]
          else [.unit, .signed .i32 (-1), .signed .i32 2147483647, names.value, .signed .i32 index]
        let .done result after := evalExpr 100 extractedProgram {} (.call function.id (arguments.map Expr.value))
          | throw (IO.userError "bad named type accessed storage")
        unless result == .signed .i32 (-1) && after.heap.blocks.isEmpty && after.world.calls.isEmpty &&
            after.world.standardOutput.isEmpty && after.world.standardError.isEmpty && after.world.opaqueCalls.isEmpty do
          throw (IO.userError "bad named type had output effects")
  IO.println "qualified name fixtures: 42 declaration, 42 type routes" : IO Unit)

end DeclarationNameTests
