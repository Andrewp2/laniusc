import verified_compiler.tests.direct_ir_recursive_inference

namespace IRBinaryInferenceTests

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics
open IRTypeRefProof IRExpressionKindProof IRBinaryKindProof
open IRTypeCacheFillProof (Literal Environment nodeType)

private def ordinal : Value → Nat | .enumeration _ tag _ => tag | _ => 0
private def nodeBytes (tag operator : Value) (left right : Int) : List UInt8 :=
  encodeNatLE 8 (ordinal tag) ++ encodeNatLE 8 (ordinal operator) ++
    ([left, right, -1, -1] : List Int).flatMap (fun n => i32Bytes n ++ List.replicate 4 0)

-- The right subtree runs after the left has changed the cache. Boolean trees
-- consume integer comparisons; a shared comparison is revisited with a smaller
-- budget and must retain valid cache facts while overwriting its old budget.
#eval (do
  let binary := source_value Extracted.«verified::surface_expr».Types.«SurfaceExprKind».«Binary» []
  let unary := source_value Extracted.«verified::surface_expr».Types.«SurfaceExprKind».«Unary» []
  let literal := source_value Extracted.«verified::surface_expr».Types.«SurfaceExprKind».«Literal» []
  let env : Environment := {
    header := fun _ => .unit, countCell := .unit, middle := fun _ => .unit,
    table := .unit, allocationTail := [], tail := [] }
  let mut checked := 0
  let integers := [Surface.BinaryOp.bitOr, .bitXor, .bitAnd, .equal, .notEqual, .less, .greater,
    .lessEqual, .greaterEqual, .shiftLeft, .shiftRight, .add, .subtract, .multiply, .divide, .remainder]
  let booleans := [Surface.BinaryOp.logicalAnd, .logicalOr, .equal, .notEqual]
  let comparisons := [Surface.BinaryOp.equal, .notEqual, .less, .greater, .lessEqual, .greaterEqual]
  let scenarios := integers.map (fun op => (op, Surface.BinaryOp.add, false)) ++
    booleans.flatMap (fun op => comparisons.map (fun child => (op, child, true)))
  for (op, childOp, boolean) in scenarios do
    for shared in [false, true] do
      let count := if shared then 5 else 6
      let childKind : Reference := if boolean then .Bool else .I32
      let kind : Reference := if boolean then .Bool else integerResult op
      let rightLiteral := if boolean then Literal.boolean false else Literal.integer
      let rightOp := if boolean then IRUnaryInferenceProof.Operation.not else .positive
      let rightChild := if boolean && shared then 1 else if shared then 4 else 5
      let nodes := (if shared then [] else nodeBytes literal rightLiteral.operator (-1) (-1)) ++
        (List.replicate 2 (nodeBytes literal Literal.integer.operator (-1) (-1))).flatten ++
        nodeBytes unary rightOp.sourceValue rightChild (-1) ++
        nodeBytes binary (sourceValue childOp) 3 4 ++ nodeBytes binary (sourceValue op) 1 2
      let leftSource : Surface.Expr := .binary childOp (.literal (.integer "7")) (.literal (.integer "7"))
      let rightSource : Surface.Expr := if boolean && shared then leftSource
        else .literal (IRSourceCacheProof.surfaceLiteral rightLiteral "7")
      let source : Surface.Expr := .binary op leftSource (.unary (IRSourceCacheProof.surfaceOperation rightOp) rightSource)
      let some (sourceKind, needed) := IRRecursiveInferenceProof.classify source
        | throw (IO.userError "mixed scalar fixture has no independent classification")
      unless known sourceKind == known kind && needed ≤ 4 do
        throw (IO.userError "mixed scalar source result or required depth is wrong")
      for prime in ([none, some 1, some 2] : List (Option Nat)) do
        let before := ({ heap := { blocks := [
          { base := 16, size := count * 4, alignment := 4, bytes := (List.replicate count (-1 : Int)).flatMap i32Bytes },
          { base := 1024, size := count * 4, alignment := 4, bytes := (List.replicate count (-77 : Int)).flatMap i32Bytes },
          { base := 4096, size := count * 48, alignment := 8, bytes := nodes }], nextAddress := 4096 + count * 48 } } : State)
          |>.bindLocal 99 (.signed .i32 321)
        let context := IRExpressionValidationProof.context (.rawSlice nodeType (4096 + count * 48 - 8) count) env.countCell
          (.signed .i32 count) env.header
          ([.rawSlice (.scalar (.signed .i32)) 16 count, .rawSlice (.scalar (.signed .i32)) 1024 count] ++ env.suffix)
        let call := fun node depth => Expr.call Extracted.«lowering::body_expression».Functions.«expression_kind».core.id
          ([context,
            .signed .i32 count, .signed .i32 node, .signed .i32 depth].map Expr.value)
        let mut ready := before
        if let some node := prime then
          let .done value after := evalExpr 30000 extractedProgram ready (call node 3)
            | throw (IO.userError "binary subtree priming trapped")
          unless value == known childKind do throw (IO.userError "primed subtree inferred wrong type")
          ready := after
        let .done value after := evalExpr 30000 extractedProgram ready (call 0 4)
          | throw (IO.userError "recursive binary query trapped")
        unless value == known kind do throw (IO.userError "binary decision differs from source rule")
        let codes := ([kind, childKind, childKind, .I32, .I32] ++
          (if shared then [] else [childKind])).map typeCode |>.flatMap i32Bytes
        let depths := (([4, if boolean && shared then 2 else 3, 3] : List Int) ++
          List.replicate 2 (if boolean && shared then 1 else 2) ++
          (if shared then [] else [2])).flatMap i32Bytes
        unless (after.heap.loadBytes 16 (count * 4)).toOption == some codes &&
            (after.heap.loadBytes 1024 (count * 4)).toOption == some depths &&
            (after.heap.loadBytes 4096 nodes.length).toOption == some nodes &&
            after.locals == before.locals && after.local? 99 == before.local? 99 &&
            after.world.calls.isEmpty && after.world.standardOutput.isEmpty &&
            after.world.standardError.isEmpty && after.i32ArrayViews.isEmpty do
          throw (IO.userError "binary traversal lost a cache write, source byte or caller binding")
        let stripped := { after with heap := { after.heap with blocks := after.heap.blocks.filter (fun block => block.base != 4096) } }
        let .done reused final := evalExpr 30000 extractedProgram stripped (call 0 5)
          | throw (IO.userError "binary root reuse inspected missing source")
        unless reused == value && final.heap.nextAddress == stripped.heap.nextAddress &&
            final.heap.blocks.length == stripped.heap.blocks.length &&
            (final.heap.loadBytes 16 (count * 4)).toOption == some codes &&
            (final.heap.loadBytes 1024 (count * 4)).toOption == some depths do
          throw (IO.userError "binary root hit recomputed or mutated cache")
        checked := checked + 1
  IO.println s!"{checked} integer/Boolean binary queries and source-free reuses passed" : IO Unit)

-- Primitive mismatches are rejected, not silently coerced. This checks native
-- decisions as well as the source model; recursive rejection is not yet proved.
#eval (do
  let operators := [Surface.BinaryOp.logicalAnd, .logicalOr, .equal, .notEqual, .less, .greater,
    .lessEqual, .greaterEqual, .shiftLeft, .shiftRight, .add, .subtract, .multiply, .divide, .remainder,
    .bitOr, .bitXor, .bitAnd]
  let site : Site := ⟨.unit, 0, 0, 0⟩
  let primitives : List Reference := [.I32, .Bool]
  let before := ({} : State).bindLocal 99 (.signed .i32 321)
  let mut checked := 0
  for op in operators do
    for left in primitives do
      for right in primitives do
        let expected := match scalarResult op left right with
          | some kind => known kind | none => unsupported
        let .done value after := evalExpr 2000 extractedProgram before (site.call op (known left) (known right))
          | throw (IO.userError "primitive binary decision trapped")
        unless value == expected && after.locals == before.locals &&
            after.heap.blocks.isEmpty && after.heap.nextAddress == before.heap.nextAddress &&
            after.world.calls.isEmpty && after.world.standardOutput.isEmpty &&
            after.world.standardError.isEmpty && after.i32ArrayViews.isEmpty do
          throw (IO.userError "primitive binary typing/rejection or frame differs from the source model")
        checked := checked + 1
  IO.println s!"{checked} primitive binary acceptance/rejection decisions passed" : IO Unit)

end IRBinaryInferenceTests
