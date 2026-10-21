import verified_compiler.tests.direct_ir_expression_validation

namespace IRExpressionTests

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics IRExpressionValidationProof

private def tag (value : Value) : Nat := match value with
  | .enumeration _ ordinal _ => ordinal | _ => 0
private def nodeType : Ty := match source_value Extracted.«verified::surface_expr».Types.«ExpressionNode».mk [] with
  | .structure id _ => .structure id | _ => .unit
private def nodeBytes (kind operator : Value) (left right : Int) : List UInt8 :=
  encodeNatLE 8 (tag kind) ++ encodeNatLE 8 (tag operator) ++
    [left, right, -1, -1].flatMap (fun n => i32Bytes n ++ List.replicate 4 0)

-- Exercise the recursive public lowering entry point, not only its leaf
-- writer. A failed inference may populate the type cache but must not emit IR.
#eval (do
  let literal := source_value Extracted.«verified::surface_expr».Types.«SurfaceExprKind».«Literal» []
  let unary := source_value Extracted.«verified::surface_expr».Types.«SurfaceExprKind».«Unary» []
  let binary := source_value Extracted.«verified::surface_expr».Types.«SurfaceExprKind».«Binary» []
  let boolean := source_value Extracted.«verified::surface_expr».Types.«ExpressionOperator».«LiteralTrue» []
  let missing := source_value Extracted.«verified::surface_expr».Types.«ExpressionOperator».«NoOperator» []
  let cases : List (String × Value × Value × Bool) := [
    ("not", unary, source_value Extracted.«verified::surface_expr».Types.«ExpressionOperator».«UnaryNot» [], true),
    ("positive", unary, source_value Extracted.«verified::surface_expr».Types.«ExpressionOperator».«UnaryPositive» [], false),
    ("negative", unary, source_value Extracted.«verified::surface_expr».Types.«ExpressionOperator».«UnaryNegate» [], false),
    ("and", binary, source_value Extracted.«verified::surface_expr».Types.«ExpressionOperator».«BinaryAndThen» [], true),
    ("or", binary, source_value Extracted.«verified::surface_expr».Types.«ExpressionOperator».«BinaryOrElse» [], true),
    ("equal", binary, source_value Extracted.«verified::surface_expr».Types.«ExpressionOperator».«BinaryEqual» [], true),
    ("not equal", binary, source_value Extracted.«verified::surface_expr».Types.«ExpressionOperator».«BinaryNotEqual» [], true),
    ("add", binary, source_value Extracted.«verified::surface_expr».Types.«ExpressionOperator».«BinaryAdd» [], false),
    ("less", binary, source_value Extracted.«verified::surface_expr».Types.«ExpressionOperator».«BinaryLess» [], false),
    ("bad operator", unary, missing, false)]
  let eventTy : Ty := ((Extracted.«ir::body_events».Functions.«append».core.parameters[2]?).getD (0, .unit)).2
  let refTy : Ty := ((Extracted.«ir::type_ref».Functions.«is_invalid».core.parameters[0]?).getD (0, .unit)).2
  let output := source_value Extracted.«ir::body_events».Types.«Region».mk
    [.rawSlice eventTy 128 3, .rawSlice refTy 176 3, .boolean true, .signed .i32 3]
  let allocated := source_value Extracted.«lowering::allocation».Types.«Index».mk [.unit]
  let mut checked := 0
  for (name, kind, operator, valid) in cases do
    for warm in [false, true] do
      for depth in ([0, 1, 16] : List Int) do
        let nodes := nodeBytes kind operator 0 1 ++ nodeBytes literal boolean (-1) (-1) ++
          nodeBytes literal boolean (-1) (-1)
        let heap : Heap := {
          blocks := [
            { base := 16, size := 168, alignment := 8, bytes := List.replicate 168 0 },
            { base := 256, size := 144, alignment := 8, bytes := nodes, owned := false },
            { base := 512, size := 12, alignment := 4,
              bytes := [if warm then 2 else -1, if warm then 2 else -1,
                if warm && valid then 2 else -1].flatMap i32Bytes },
            { base := 544, size := 12, alignment := 4, bytes := [1, 1, 2].flatMap i32Bytes }]
          nextAddress := 556 }
        let before := ({ heap } : State).bindLocal 77 (.signed .i32 321)
        let input := context (.rawSlice nodeType 392 3) .unit (.signed .i32 3) (fun _ => .unit)
          ([.rawSlice (.scalar (.signed .i32)) 512 3, .rawSlice (.scalar (.signed .i32)) 544 3] ++
            List.replicate 6 .unit ++ [allocated])
        let success := valid && depth > 1
        let expected := if depth ≤ 0 then -1 else if operator == missing then -2 else if depth ≤ 1 then -1 else if !valid then -2
          else if kind == unary then 2 else 3
        let .done actual after := evalExpr 1000 extractedProgram before (call input 3 2 depth output 0)
          | throw (IO.userError s!"{name}, warm={warm}, depth={depth}: lowering trapped")
        unless actual == .signed .i32 expected do
          throw (IO.userError s!"{name}, warm={warm}, depth={depth}: {repr actual}, expected {expected}")
        if success then
          unless (readRawSliceIndex extractedProgram after refTy 176 3 0).toOption ==
              some (source_value Extracted.«ir::type_ref».Types.«TypeRef».«Bool» []) do
            throw (IO.userError "successful root lacks its inferred Bool annotation")
        else
          unless (after.heap.loadBytes 16 168).toOption == some (List.replicate 168 0) do
            throw (IO.userError s!"{name}, warm={warm}, depth={depth}: rejected expression wrote IR")
          let .done rejected _ := evalExpr 1000 extractedProgram before (call input 3 2 depth .unit 0)
            | throw (IO.userError "rejection touched invalid output descriptor")
          unless rejected == actual do throw (IO.userError "rejection depends on output storage")
        unless (after.heap.loadBytes 256 144).toOption == some nodes && after.locals == before.locals do
          throw (IO.userError "lowering changed source nodes or caller locals")
        checked := checked + 1
  IO.println s!"{checked} recursive expression validation cases passed" : IO Unit)

end IRExpressionTests
