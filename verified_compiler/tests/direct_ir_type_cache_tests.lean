import verified_compiler.tests.direct_ir_type_cache_fill

namespace IRTypeCacheTests

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics IRTypeRefProof IRExpressionKindProof IRTypeCacheProof

-- Source-node storage is deliberately unusable: these are actual cache hits,
-- not a recomputation which happens to return the same answer.
#eval (do
  let kinds : List Reference := [.Void, .I32, .Bool, .Usize, .Pointer, .String, .Slice,
    .Nominal 0, .Nominal 1, .Nominal 1073741807,
    .NominalSlice 0, .NominalSlice 1, .NominalSlice 1073741807]
  let mut checked := 0
  for kind in kinds do
    for depth in ([1, 7, 2147483647] : List Int) do
      let codes := [-77, typeCode kind, -88].flatMap i32Bytes
      let depths := [-77, 1, -88].flatMap i32Bytes
      let before : State := ({ heap := { blocks := [
        { base := 16, size := 12, alignment := 4, bytes := codes },
        { base := 32, size := 12, alignment := 4, bytes := depths }], nextAddress := 44 } } : State)
        |>.bindLocal 99 (.signed .i32 321)
      let context := IRExpressionValidationProof.context .unit .unit (.signed .i32 3) (fun _ => .unit)
        [.rawSlice (.scalar (.signed .i32)) 16 3, .rawSlice (.scalar (.signed .i32)) 32 3]
      let call := Expr.call Extracted.«lowering::body_expression».Functions.«expression_kind».core.id
        ([context, .signed .i32 2, .signed .i32 1, .signed .i32 depth].map Expr.value)
      let .done result after := evalExpr 1000 extractedProgram before call
        | throw (IO.userError s!"cache hit trapped for code {typeCode kind} at depth {depth}")
      unless result == known kind do throw (IO.userError s!"cache changed type {typeCode kind}")
      unless (after.heap.loadBytes 16 12).toOption == some codes &&
          (after.heap.loadBytes 32 12).toOption == some depths && after.locals == before.locals &&
          after.heap.nextAddress == before.heap.nextAddress do
        throw (IO.userError "cache lookup changed memory or caller locals")
      checked := checked + 1
  IO.println s!"{checked} primitive/nominal cache-hit cases passed" : IO Unit)

private def ordinal : Value → Nat | .enumeration _ tag _ => tag | _ => 0

-- Start from native AST storage and either an empty cache or an entry whose
-- required depth is too large. The second query has no readable source nodes.
#eval (do
  let literals : List IRTypeCacheFillProof.Literal := [.integer, .boolean false, .boolean true, .string]
  let tag := source_value Extracted.«verified::surface_expr».Types.«SurfaceExprKind».«Literal» []
  let env : IRTypeCacheFillProof.Environment := {
    header := fun _ => .unit, countCell := .unit, middle := fun _ => .unit,
    table := .unit, allocationTail := [], tail := [] }
  let mut checked := 0
  for literal in literals do
    for depth in ([1, 7, 2147483647] : List Int) do
      for stale in [false, true] do
        if stale && depth == 2147483647 then continue
        let oldCode := if stale then 6 else -1
        let oldDepth := min (depth + 1) 2147483647
        let node := encodeNatLE 8 (ordinal tag) ++ encodeNatLE 8 (ordinal literal.operator) ++
          ([-1, -1, -1, -1] : List Int).flatMap (fun n => i32Bytes n ++ List.replicate 4 0)
        let nodes := List.replicate 48 0 ++ node ++ List.replicate 48 0
        let before : State := ({ heap := { blocks := [
          { base := 16, size := 12, alignment := 4, bytes := [-77, oldCode, -88].flatMap i32Bytes },
          { base := 32, size := 12, alignment := 4, bytes := [-55, oldDepth, -66].flatMap i32Bytes },
          { base := 256, size := 144, alignment := 8, bytes := nodes }], nextAddress := 400 } } : State)
          |>.bindLocal 99 (.signed .i32 321)
        let context := fun data => IRExpressionValidationProof.context data .unit (.signed .i32 3) env.header
          ([.rawSlice (.scalar (.signed .i32)) 16 3, .rawSlice (.scalar (.signed .i32)) 32 3] ++ env.suffix)
        let call := fun data => Expr.call Extracted.«lowering::body_expression».Functions.«expression_kind».core.id
          ([context data, .signed .i32 2, .signed .i32 1, .signed .i32 depth].map Expr.value)
        let .done result cached := evalExpr 1000 extractedProgram before
            (call (.rawSlice IRTypeCacheFillProof.nodeType 392 3))
          | throw (IO.userError s!"literal inference trapped at depth {depth}, stale={stale}")
        let .done reused after := evalExpr 1000 extractedProgram cached (call .unit)
          | throw (IO.userError "populated cache recomputed source instead of reusing the type")
        unless result == known literal.kind && reused == result do
          throw (IO.userError "inference or reuse returned the wrong literal type")
        for state in [cached, after] do
          unless (state.heap.loadBytes 16 12).toOption == some ([-77, typeCode literal.kind, -88].flatMap i32Bytes) &&
              (state.heap.loadBytes 32 12).toOption == some ([-55, depth, -66].flatMap i32Bytes) &&
              (state.heap.loadBytes 256 144).toOption == some nodes && state.locals == before.locals &&
              state.heap.nextAddress == before.heap.nextAddress do
            throw (IO.userError "cache writes changed the wrong slot, source memory or caller locals")
        checked := checked + 1
  IO.println s!"{checked} empty/insufficient-depth cache fill-and-reuse cases passed" : IO Unit)

-- Updating any slot preserves every other cached type and budget. Exercise
-- both physical table orders, then query all entries with no readable AST.
#eval (do
  let kinds : List Reference := [.I32, .Bool, .String, .Nominal 0, .NominalSlice 0]
  let tag := source_value Extracted.«verified::surface_expr».Types.«SurfaceExprKind».«Literal» []
  let literal := IRTypeCacheFillProof.Literal.boolean true
  let node := encodeNatLE 8 (ordinal tag) ++ encodeNatLE 8 (ordinal literal.operator) ++
    ([-1, -1, -1, -1] : List Int).flatMap (fun n => i32Bytes n ++ List.replicate 4 0)
  let env : IRTypeCacheFillProof.Environment := {
    header := fun _ => .unit, countCell := .unit, middle := fun _ => .unit,
    table := .unit, allocationTail := [], tail := [] }
  let mut checked := 0
  for (codes, depths) in [(16, 64), (64, 16)] do
    for root in List.range kinds.length do
      let oldCodes := (kinds.map typeCode).set root (-1)
      let oldDepths := ([1, 2, 3, 4, 5] : List Int)
      let before := ({ heap := { blocks := [
        { base := codes, size := 20, alignment := 4, bytes := oldCodes.flatMap i32Bytes },
        { base := depths, size := 20, alignment := 4, bytes := oldDepths.flatMap i32Bytes },
        { base := 256, size := 48, alignment := 8, bytes := node }], nextAddress := 304 } } : State)
        |>.bindLocal 99 (.signed .i32 321)
      let context := fun data => IRExpressionValidationProof.context data .unit (.signed .i32 5) env.header
        ([.rawSlice (.scalar (.signed .i32)) codes 5, .rawSlice (.scalar (.signed .i32)) depths 5] ++ env.suffix)
      let call := fun data index => Expr.call Extracted.«lowering::body_expression».Functions.«expression_kind».core.id
        ([context data, .signed .i32 5, .signed .i32 index, .signed .i32 8].map Expr.value)
      let .done value after := evalExpr 1000 extractedProgram before
          (call (.rawSlice IRTypeCacheFillProof.nodeType (296 + root * 48) 5) root)
        | throw (IO.userError "cache slot update trapped")
      unless value == known .Bool && after.locals == before.locals &&
          (after.heap.loadBytes codes 20).toOption == some ((oldCodes.set root 2).flatMap i32Bytes) &&
          (after.heap.loadBytes depths 20).toOption == some ((oldDepths.set root 8).flatMap i32Bytes) &&
          (after.heap.loadBytes 256 48).toOption == some node do
        throw (IO.userError "cache slot update changed another entry or source bytes")
      for (kind, index) in kinds.zipIdx do
        let expected : Reference := if index == root then .Bool else kind
        let .done found final := evalExpr 200 extractedProgram after (call .unit index)
          | throw (IO.userError "neighboring cached entry was lost")
        unless found == known expected && final.locals == before.locals do
          throw (IO.userError "neighboring cached entry changed meaning")
      checked := checked + 1
  IO.println s!"{checked} whole-table store/reuse cases passed" : IO Unit)

end IRTypeCacheTests
