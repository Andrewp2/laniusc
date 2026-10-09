import verified_compiler.tests.direct_match_metadata

namespace MatchMetadataTests

open Lanius Lanius.Core Lanius.Semantics MatchMetadataProof IRShapeProof

private def check (function : Lanius.Core.Function) (event expected : Value) : IO Unit := do
  let before := ({} : State).bindLocal 900 (.signed .i32 91)
  let .done actual after := evalExpr 100 extractedProgram before (.call function.id [.value event])
    | throw (IO.userError s!"match metadata reader {function.id} trapped")
  unless actual == expected do throw (IO.userError s!"match metadata reader {function.id} returned the wrong payload")
  unless after.locals == before.locals && after.heap.blocks.isEmpty &&
      after.heap.nextAddress == before.heap.nextAddress && after.i32ArrayViews.isEmpty &&
      after.world.standardOutput.isEmpty && after.world.standardError.isEmpty &&
      after.world.calls.isEmpty && after.world.opaqueCalls.isEmpty &&
      (after.cells.take before.cells.length).map (fun cell => (cell.id, cell.value)) ==
        before.cells.map (fun cell => (cell.id, cell.value)) do
    throw (IO.userError "match metadata reader changed caller/runtime state")

#eval (do
  for token in [-2147483648, -1, 0, 7, 2147483647] do
    check Extracted.«ir::body_events».Functions.«matching_binding_fields».core
      (bindingEvent token) (bindingValue token)
    check Extracted.«verified::lean_body_shape».Functions.«match_binding_id».core
      (bindingEvent token) (.signed .i32 token)
    check Extracted.«verified::lean_body_shape».Functions.«match_binding_id».core
      (source_value Extracted.«ir::body_events».Types.«Event».«ExpressionLocal» [bindingValue token])
      (.signed .i32 (-1))
  for (ordinal, count) in [(-1, 0), (-1, 1), (0, 0), (2, 3)] do
    check Extracted.«ir::body_events».Functions.«matching_arm_fields».core
      (armEvent ordinal count) (armValue ordinal count)
  for (typeId, count) in [(-1, -1), (0, 0), (0, 2), (2147483647, 2147483647)] do
    check Extracted.«ir::body_events».Functions.«matching_fields».core
      (matchEvent .I32 typeId count) (matchHeaderValue .I32 typeId count)
  : IO Unit)

end MatchMetadataTests
