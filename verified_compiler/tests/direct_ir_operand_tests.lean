import verified_compiler.tests.direct_ir_unary_inference
import Lanius.Semantics
import Lanius.Semantics.SourceValue

namespace IROperandTests

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics

private def ordinal : Value → Nat | .enumeration _ tag _ => tag | _ => 0
private def nodeType : Ty := match source_value Extracted.«verified::surface_expr».Types.«ExpressionNode».mk [] with
  | .structure id _ => .structure id | _ => .unit
private def context (codes depths : Value) : Value :=
  .structure (match source_value Extracted.«lowering::body_context».Types.«BodyContext».mk [] with
    | .structure id _ => id | _ => 0)
    ([.unit, .unit, .unit, .unit, .unit,
      source_value Extracted.«verified::surface_expr».Types.«ExpressionArena».mk
        [.rawSlice nodeType 392 3, .unit, .signed .i32 3], codes, depths] ++
      List.replicate 6 .unit ++ [source_value Extracted.«lowering::allocation».Types.«Index».mk [.unit]])

-- A cached Void is a legitimate result of calling a void function, but never
-- a legitimate operand. Child AST storage is absent, so it must use the cache.
#eval (do
  let unary := source_value Extracted.«verified::surface_expr».Types.«SurfaceExprKind».«Unary» []
  let binary := source_value Extracted.«verified::surface_expr».Types.«SurfaceExprKind».«Binary» []
  let cases : List (Value × Value × List (Int × Int)) := [
    (unary, source_value Extracted.«verified::surface_expr».Types.«ExpressionOperator».«UnaryNot» [], [(0, 0)]),
    (unary, source_value Extracted.«verified::surface_expr».Types.«ExpressionOperator».«UnaryPositive» [], [(0, 0)]),
    (unary, source_value Extracted.«verified::surface_expr».Types.«ExpressionOperator».«UnaryNegate» [], [(0, 0)]),
    (binary, source_value Extracted.«verified::surface_expr».Types.«ExpressionOperator».«BinaryAdd» [], [(0, 0), (0, 1), (1, 0)]),
    (binary, source_value Extracted.«verified::surface_expr».Types.«ExpressionOperator».«BinaryAndThen» [], [(0, 0), (0, 2), (2, 0)]),
    (binary, source_value Extracted.«verified::surface_expr».Types.«ExpressionOperator».«BinaryEqual» [], [(0, 0), (0, 1), (1, 0)])]
  let unsupported := source_value Extracted.«lowering::body_expression».Types.«ExpressionKind».mk
    [source_value Extracted.«lowering::body_expression».Types.«ExpressionStatus».«UnsupportedExpression» [],
      source_value Extracted.«ir::type_ref».Types.«TypeRef».«Invalid» []]
  let mut checked := 0
  let invalid := source_value Extracted.«lowering::body_expression».Types.«ExpressionKind».mk
    [source_value Extracted.«lowering::body_expression».Types.«ExpressionStatus».«InvalidExpression» [],
      source_value Extracted.«ir::type_ref».Types.«TypeRef».«Invalid» []]
  for (kind, operator, operands) in cases do
    for (left, right) in operands do
      for depth in [1, 3] do
        let node := encodeNatLE 8 (ordinal kind) ++ encodeNatLE 8 (ordinal operator) ++
          ([0, 1, -1, -1] : List Int).flatMap (fun n => i32Bytes n ++ List.replicate 4 0)
        let codes := ([left, right, -1] : List Int).flatMap i32Bytes
        let depths := ([1, 1, -77] : List Int).flatMap i32Bytes
        let before : State := ({ heap := { blocks := [
          { base := 16, size := 12, alignment := 4, bytes := codes },
          { base := 32, size := 12, alignment := 4, bytes := depths },
          { base := 256, size := 48, alignment := 8, bytes := node }], nextAddress := 304 } } : State)
          |>.bindLocal 99 (.signed .i32 321)
        let input := context (.rawSlice (.scalar (.signed .i32)) 16 3) (.rawSlice (.scalar (.signed .i32)) 32 3)
        let query := Expr.call Extracted.«lowering::body_expression».Functions.«expression_kind».core.id
          ([input, .signed .i32 3, .signed .i32 2, .signed .i32 depth].map Expr.value)
        let .done result after := evalExpr 1000 extractedProgram before query
          | throw (IO.userError "cached-void operand query trapped")
        let expected := if depth == 1 then invalid else unsupported
        unless result == expected do throw (IO.userError s!"operand result at depth {depth}: {repr result}")
        unless (after.heap.loadBytes 16 12).toOption == some codes &&
            (after.heap.loadBytes 32 12).toOption == some depths &&
            (after.heap.loadBytes 256 48).toOption == some node && after.locals == before.locals do
          throw (IO.userError "failed operand inference wrote a cache entry or changed source/caller state")
        let lower := Expr.call Extracted.«lowering::body_expression».Functions.«expression».core.id
          ([input, .signed .i32 3, .signed .i32 2, .unit, .signed .i32 0, .signed .i32 depth].map Expr.value)
        let .done result after := evalExpr 1000 extractedProgram before lower
          | throw (IO.userError "void operand was not rejected before output access")
        unless result == .signed .i32 (if depth == 1 then -1 else -2) &&
            (after.heap.loadBytes 16 12).toOption == some codes &&
            (after.heap.loadBytes 32 12).toOption == some depths &&
            (after.heap.loadBytes 256 48).toOption == some node &&
            after.heap.nextAddress == before.heap.nextAddress && after.locals == before.locals do
          throw (IO.userError "failed operand lowering changed memory or failure status")
        checked := checked + 1
  IO.println s!"{checked} void-operand/depth-exhaustion cases passed" : IO Unit)

end IROperandTests

namespace IRUnaryTests

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics IRTypeRefProof IRExpressionKindProof IRUnaryInferenceProof

private def ordinal : Value → Nat | .enumeration _ tag _ => tag | _ => 0
private def nodeType : Ty := match source_value Extracted.«verified::surface_expr».Types.«ExpressionNode».mk [] with
  | .structure id _ => .structure id | _ => .unit
private def context (nodes : Value) : Value :=
  IRExpressionValidationProof.context nodes .unit (.signed .i32 2) (fun _ => .unit)
    ([.rawSlice (.scalar (.signed .i32)) 16 2, .rawSlice (.scalar (.signed .i32)) 32 2] ++
      List.replicate 6 .unit ++ [source_value Extracted.«lowering::allocation».Types.«Index».mk [.unit]])

-- The model classifies types by constructors, independently of their numeric
-- cache encodings. Nominal boundary IDs test the representation bridge too.
#eval (do
  let kinds : List Reference := [.Invalid, .Void, .I32, .Bool, .Usize, .Pointer, .String, .Slice,
    .Nominal (-1), .Nominal 0, .Nominal 1073741807, .Nominal 1073741808,
    .NominalSlice (-1), .NominalSlice 0, .NominalSlice 1073741807, .NominalSlice 1073741808]
  let operations : List Operation := [.positive, .negate, .not]
  let statuses : List Status := [.KnownExpression, .InvalidExpression, .UnsupportedExpression]
  let mut decisions := 0
  let mut queries := 0
  for op in operations do
    for kind in kinds do
      for status in statuses do
        let before := ({} : State).bindLocal 99 (.signed .i32 321)
        let call := Expr.call Extracted.«lowering::body_expression».Functions.«unary_kind».core.id
          [.value op.targetValue, .value (result status kind)]
        let .done value after := evalExpr 200 extractedProgram before call
          | throw (IO.userError "unary decision trapped")
        unless value == outcome op status kind && after.locals == before.locals &&
            after.heap.blocks.isEmpty && after.heap.nextAddress == before.heap.nextAddress do
          throw (IO.userError s!"unary decision differs from scalar typing rule: {repr value}")
        decisions := decisions + 1
      if isValidResult kind then
        let unary := source_value Extracted.«verified::surface_expr».Types.«SurfaceExprKind».«Unary» []
        let node := encodeNatLE 8 (ordinal unary) ++ encodeNatLE 8 (ordinal op.sourceValue) ++
          ([0, -1, -1, -1] : List Int).flatMap (fun n => i32Bytes n ++ List.replicate 4 0)
        let codes := [typeCode kind, -1].flatMap i32Bytes
        let depths := ([1, -77] : List Int).flatMap i32Bytes
        let before := ({ heap := { blocks := [
          { base := 16, size := 8, alignment := 4, bytes := codes },
          { base := 32, size := 8, alignment := 4, bytes := depths },
          { base := 256, size := 48, alignment := 8, bytes := node }], nextAddress := 304 } } : State)
          |>.bindLocal 99 (.signed .i32 321)
        let input := context (.rawSlice nodeType 344 2)
        let call := Expr.call Extracted.«lowering::body_expression».Functions.«expression_kind».core.id
          ([input, .signed .i32 2, .signed .i32 1, .signed .i32 3].map Expr.value)
        let .done value after := evalExpr 1000 extractedProgram before call
          | throw (IO.userError "recursive unary query trapped")
        let accepted := accepts op kind
        let expectedCodes := [typeCode kind, if accepted then typeCode op.kind else -1].flatMap i32Bytes
        let expectedDepths := ([1, if accepted then 3 else -77] : List Int).flatMap i32Bytes
        unless value == outcome op .KnownExpression kind &&
            (after.heap.loadBytes 16 8).toOption == some expectedCodes &&
            (after.heap.loadBytes 32 8).toOption == some expectedDepths &&
            (after.heap.loadBytes 256 48).toOption == some node && after.locals == before.locals do
          throw (IO.userError "unary query result, cache writes, or source/caller frame violated")
        if accepted then
          let reuse := Expr.call Extracted.«lowering::body_expression».Functions.«expression_kind».core.id
            ([context .unit, .signed .i32 2, .signed .i32 1, .signed .i32 3].map Expr.value)
          let .done reused final := evalExpr 200 extractedProgram after reuse
            | throw (IO.userError "cached unary query reread source nodes")
          unless reused == value && (final.heap.loadBytes 16 8).toOption == some expectedCodes &&
              (final.heap.loadBytes 32 8).toOption == some expectedDepths && final.locals == before.locals do
            throw (IO.userError "cached unary query changed type or memory")
        queries := queries + 1
  IO.println s!"{decisions} unary type/status decisions and {queries} recursive cache-write/reuse cases passed" : IO Unit)

-- Cold recursion must retain the child's writes, then store the parent only
-- when its operand type is accepted. Stale entries deliberately claim a wrong
-- type, so accidentally taking the hit path changes the observed result.
#eval (do
  let mut checked := 0
  for op in ([.positive, .negate, .not] : List Operation) do
    for literal in ([.integer, .boolean false, .boolean true, .string] : List IRTypeCacheFillProof.Literal) do
      for depth in ([2, 7, 2147483647] : List Int) do
        for stale in [false, true] do
          let unary := source_value Extracted.«verified::surface_expr».Types.«SurfaceExprKind».«Unary» []
          let literalTag := source_value Extracted.«verified::surface_expr».Types.«SurfaceExprKind».«Literal» []
          let encodeNode := fun tag operator left => encodeNatLE 8 (ordinal tag) ++ encodeNatLE 8 (ordinal operator) ++
            ([left, -1, -1, -1] : List Int).flatMap (fun n => i32Bytes n ++ List.replicate 4 0)
          let nodes := encodeNode unary op.sourceValue 0 ++ encodeNode literalTag literal.operator (-1)
          let before := ({ heap := { blocks := [
            { base := 16, size := 8, alignment := 4, bytes := ([if stale then 6 else -1, -1] : List Int).flatMap i32Bytes },
            { base := 32, size := 8, alignment := 4, bytes := ([depth, -77] : List Int).flatMap i32Bytes },
            { base := 256, size := 96, alignment := 8, bytes := nodes }], nextAddress := 352 } } : State)
            |>.bindLocal 99 (.signed .i32 321)
          let call := fun data => Expr.call Extracted.«lowering::body_expression».Functions.«expression_kind».core.id
            ([context data, .signed .i32 2, .signed .i32 1, .signed .i32 depth].map Expr.value)
          let .done value after := evalExpr 1000 extractedProgram before (call (.rawSlice nodeType 344 2))
            | throw (IO.userError "cold unary query trapped")
          let accepted := accepts op literal.kind
          let codes := [typeCode literal.kind, if accepted then typeCode op.kind else -1].flatMap i32Bytes
          let depths := [depth - 1, if accepted then depth else -77].flatMap i32Bytes
          unless value == outcome op .KnownExpression literal.kind && after.locals == before.locals &&
              after.heap.nextAddress == before.heap.nextAddress &&
              (after.heap.loadBytes 16 8).toOption == some codes &&
              (after.heap.loadBytes 32 8).toOption == some depths &&
              (after.heap.loadBytes 256 96).toOption == some nodes do
            throw (IO.userError "cold unary result, recursive cache writes, or memory frame violated")
          if accepted then
            let .done reused final := evalExpr 200 extractedProgram after (call .unit)
              | throw (IO.userError "filled parent cache reread the native syntax")
            unless reused == value && final.locals == before.locals &&
                final.heap.nextAddress == after.heap.nextAddress &&
                (final.heap.loadBytes 16 8).toOption == some codes &&
                (final.heap.loadBytes 32 8).toOption == some depths &&
                (final.heap.loadBytes 256 96).toOption == some nodes do
              throw (IO.userError "cold unary cache reuse changed result or heap")
          checked := checked + 1
  IO.println s!"{checked} cold unary empty/stale/rejection/reuse cases passed" : IO Unit)

end IRUnaryTests
