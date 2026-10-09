import verified_compiler.tests.direct_constructor_name
import verified_compiler.tests.direct_identifier_tests

namespace ConstructorNameTests

open Lanius Lanius.Core Lanius.Semantics Lanius.Memory
open ConstructorNameProof SymbolSpellingProof

private def variantType : Ty := match source_value Extracted.«ir::type_catalog».Types.«Variant».mk [] with
  | .structure id _ => .structure id | _ => .unit
private def fieldType : Ty := match source_value Extracted.«ir::type_catalog».Types.«Field».mk [] with
  | .structure id _ => .structure id | _ => .unit

-- The selected constructor is ordinal 1 of type 1, at global slot 3.
-- Its source name is unit 1/token 1; every other reference points at unit 0.
-- All these distinct indexes catch accidental ordinal/global-slot confusion.
private def fixture (spelling : String) (bad : Nat) : Except Trap (State × Table × Catalog) := do
  let (sample, names) ← IdentifierTests.fixture spelling
  let types : Table := {
    declarations := .rawSlice declarationType 1688 2, typeCount := 2,
    variants := .rawSlice variantType 1784 4, variantCount := 4,
    fields := .rawSlice fieldType 0 0, fieldCount := 0 }
  let names := { names with
    variants := .rawSlice referenceType 1944 4
    variantCount := if bad == 4 then 3 else 4 }
  let state := { sample with heap := { sample.heap with
    blocks := sample.heap.blocks ++ [
      { base := 1088, size := 448, alignment := 8, bytes := List.replicate 448 0 },
      { base := 1600, size := 96, alignment := 8, bytes := List.replicate 96 0 },
      { base := 1728, size := 64, alignment := 8, bytes := List.replicate 64 0 },
      { base := 1888, size := 64, alignment := 8, bytes := List.replicate 64 0 }],
    nextAddress := 2048 } }
  let first := enumeration 0 0 2
  let second := if bad == 1 then source_value Extracted.«ir::type_catalog».Types.«TypeDecl».mk
      [source_value Extracted.«ir::type_catalog».Types.«TypeKind».«Structure» [],
        .signed .i32 1, .signed .i32 0, .signed .i32 0, .signed .i32 2, .signed .i32 2]
    else enumeration 1 (if bad == 3 then 4 else 2) (if bad == 2 then 0 else 2)
  let heap ← writeNativeValue 64 extractedProgram state state.heap declarationType 1648 first
  let heap ← writeNativeValue 64 extractedProgram state heap declarationType 1600 second
  let mut heap := heap
  for slot in List.range 4 do
    let variant := source_value Extracted.«ir::type_catalog».Types.«Variant».mk [.signed .i32 0, .signed .i32 0]
    heap ← writeNativeValue 64 extractedProgram state heap variantType (1728 + (3 - slot) * 16) variant
    let reference := if slot == 3 then referenceValue (if bad == 5 then 2 else 1) 1 else referenceValue 0 0
    heap ← writeNativeValue 64 extractedProgram state heap referenceType (1888 + (3 - slot) * 16) reference
  return ({ state with heap }, types, names)

private def check (spelling : String) (body : Bool) (position : Nat := 3)
    (short : Bool := false) (bad : Nat := 0) (typeId : Int := 1) (ordinal : Int := 1) : IO Unit := do
  let .ok (sample, types, names) := fixture spelling bad | throw (IO.userError "constructor fixture failed")
  let expected := World.utf8Bytes (".«" ++ spelling ++ "»")
  let capacity := position + expected.length - (if short then 1 else 0)
  -- An explicit catalog Ref selects the name's source unit, not View.unit.
  let .ok (.structure _ fields) := readRawSliceIndex extractedProgram sample SurfaceBooleanProof.viewType 1528 1 0
    | throw (IO.userError "native constructor View did not decode")
  let view := SurfaceBooleanProof.viewValue (fields[0]?.getD .unit) types.value names.value
    (fields[3]?.getD .unit) 0 (-1) (.rawSlice (.scalar (.signed .i32)) 16 16) capacity
  let .ok heap := writeNativeValue 64 extractedProgram sample sample.heap SurfaceBooleanProof.viewType 1088 view
    | throw (IO.userError "native constructor View could not be stored")
  let before := { sample with heap }
  let function := if body then Extracted.«verified::lean_typed_body».Functions.«surface_variant».core
    else Extracted.«verified::lean_syntax».Functions.«constructor_surface».core
  let arguments := if body then
      [.rawSlice SurfaceBooleanProof.viewType 1528 1, .signed .i32 typeId, .signed .i32 ordinal, .signed .i32 position]
    else [.rawSlice (.scalar (.signed .i32)) 16 16, .signed .i32 capacity, .signed .i32 position,
      types.value, names.value, .signed .i32 typeId, .signed .i32 ordinal]
  let .done result after := evalExpr 500 extractedProgram before (.call function.id (arguments.map Expr.value))
    | throw (IO.userError "constructor name printing trapped")
  let accepted := !short && bad == 0 && typeId == 1 && ordinal == 1
  unless result == .signed .i32 (if accepted then (position + expected.length : Nat) else -1) do
    throw (IO.userError s!"wrong constructor result: body={body}, short={short}, bad={bad}, type={typeId}, ordinal={ordinal}")
  let .ok output := after.heap.loadBytes 16 64 | throw (IO.userError "constructor lost output storage")
  if accepted then
    unless output == List.replicate position 90 ++ expected ++ List.replicate (64 - position - expected.length) 90 do
      throw (IO.userError "constructor emitted the wrong name or changed surrounding bytes")
  else
    for index in List.range 64 do
      if index < position || capacity ≤ index || bad ≤ 3 && !short then
        unless output[index]?.getD 0 == 90 do throw (IO.userError "constructor rejection wrote outside its permitted prefix")
  unless after.locals == before.locals &&
      (after.cells.take before.cells.length).map (fun cell => (cell.id, cell.value)) ==
        before.cells.map (fun cell => (cell.id, cell.value)) do
    throw (IO.userError "constructor changed caller locals/cells")
  for block in before.heap.blocks.drop 1 do
    let .ok retained := after.heap.loadBytes block.base block.size
      | throw (IO.userError "constructor lost source/type/name/View storage")
    unless retained == block.bytes do throw (IO.userError "constructor changed input storage")
  unless after.world.standardOutput == before.world.standardOutput &&
      after.world.standardError == before.world.standardError && after.world.calls.isEmpty &&
      after.world.opaqueCalls.isEmpty && after.i32ArrayViews.isEmpty do
    throw (IO.userError "constructor changed runtime state")

#eval (do
  for body in [false, true] do
    for spelling in ["Some", "None", "match", "identifier_crossing_output_words"] do
      check spelling body 0
      check spelling body 3
      check spelling body 3 true
    for bad in [1, 2, 3, 4, 5] do check "Some" body 3 false bad
    for (typeId, ordinal) in [((-1 : Int), 1), (2, 1), (1, -1), (1, 2)] do
      check "Some" body 3 false 0 typeId ordinal
  -- Invalid type bounds reject before touching deliberately invalid backing
  -- slices, output, and names; exercise the universal rejection contract.
  let table : Table := {
    declarations := .unit, typeCount := 2, variants := .unit,
    variantCount := 4, fields := .unit, fieldCount := 0 }
  for typeId in [(-1 : Int), 2] do
    let .done result after := evalExpr 100 extractedProgram {}
        (.call Extracted.«verified::lean_syntax».Functions.«constructor_surface».core.id
          ([.unit, .signed .i32 (-1), .signed .i32 2147483647, table.value, .unit,
            .signed .i32 typeId, .signed .i32 1].map Expr.value))
      | throw (IO.userError "invalid constructor type accessed backing storage")
    unless result == .signed .i32 (-1) && after.heap.blocks.isEmpty &&
        after.heap.nextAddress == ({} : Heap).nextAddress do
      throw (IO.userError "invalid constructor type rejection changed the heap") : IO Unit)

end ConstructorNameTests
