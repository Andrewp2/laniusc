import verified_compiler.tests.direct_ir_recursive_inference

namespace IRRecursiveInferenceTests

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics
open IRTypeRefProof IRExpressionKindProof IRUnaryInferenceProof IRSourceCacheProof
open IRTypeCacheFillProof (Literal Environment nodeType)

private def ordinal : Value → Nat | .enumeration _ tag _ => tag | _ => 0

private def nodeBytes (tag operator : Value) (child : Int) : List UInt8 :=
  encodeNatLE 8 (ordinal tag) ++ encodeNatLE 8 (ordinal operator) ++
    ([child, -1, -1, -1] : List Int).flatMap (fun n => i32Bytes n ++ List.replicate 4 0)

-- The reference traverses source syntax, independently of native layout and
-- numeric cache encodings. Clear stale Void entries before traversing, then
-- exercise the entire table, not just the root result.
#eval (do
  let unary := source_value Extracted.«verified::surface_expr».Types.«SurfaceExprKind».«Unary» []
  let leaf := source_value Extracted.«verified::surface_expr».Types.«SurfaceExprKind».«Literal» []
  let env : Environment := {
    header := fun _ => .unit, countCell := .unit, middle := fun _ => .unit,
    table := .unit, allocationTail := [], tail := [] }
  let scenarios : List (Literal × (Nat → Operation)) := [
    (.integer, fun _ => .positive), (.integer, fun _ => .negate),
    (.integer, fun index => if index % 2 == 0 then .positive else .negate),
    (.boolean false, fun _ => .not), (.boolean true, fun _ => .not), (.string, fun _ => .positive)]
  let mut checked := 0
  let mut reused := 0
  let mut mixed := 0
  for (literal, operation) in scenarios do
    for layers in [0, 1, 2, 8, 24] do
      if (match literal with | .string => true | _ => false) && layers != 0 then continue
      let count := layers + 1
      let mut source := Surface.Expr.literal (surfaceLiteral literal "2147483648")
      let mut nodes := nodeBytes leaf literal.operator (-1)
      for child in List.range layers do
        source := .unary (surfaceOperation (operation child)) source
        nodes := nodeBytes unary (operation child).sourceValue child ++ nodes
      let some (kind, needed) := IRRecursiveInferenceProof.classify source
        | throw (IO.userError "accepted recursive fixture has no source classification")
      unless needed == count do throw (IO.userError "reference depth differs from source height")
      let emptyCodes := (List.replicate count (-1 : Int)).flatMap i32Bytes
      let emptyDepths := (List.replicate count (-77 : Int)).flatMap i32Bytes
      let stale := ({ heap := { blocks := [
        { base := 16, size := count * 4, alignment := 4, bytes := (List.replicate count (typeCode .Void)).flatMap i32Bytes },
        { base := 1024, size := count * 4, alignment := 4, bytes := emptyDepths },
        { base := 4096, size := count * 48, alignment := 8, bytes := nodes }], nextAddress := 4096 + count * 48 } } : State)
        |>.bindLocal 99 (.signed .i32 321)
      let clear := Expr.call Extracted.«lowering::body_expression».Functions.«clear_expression_kinds».core.id
        [.value (.rawSlice (.scalar (.signed .i32)) 16 count), .value (.signed .i32 count)]
      let .done .unit before := evalExpr 5000 extractedProgram stale clear
        | throw (IO.userError "reset before recursive query trapped")
      unless (before.heap.loadBytes 16 (count * 4)).toOption == some emptyCodes &&
          (before.heap.loadBytes 1024 (count * 4)).toOption == some emptyDepths &&
          (before.heap.loadBytes 4096 (count * 48)).toOption == some nodes &&
          before.locals == stale.locals && before.heap.nextAddress == stale.heap.nextAddress do
        throw (IO.userError "reset failed to establish the empty cache and preserve the source/caller")
      let context := fun data => IRExpressionValidationProof.context data .unit (.signed .i32 count) env.header
        ([.rawSlice (.scalar (.signed .i32)) 16 count,
          .rawSlice (.scalar (.signed .i32)) 1024 count] ++ env.suffix)
      let call := fun data index depth => Expr.call
        Extracted.«lowering::body_expression».Functions.«expression_kind».core.id
        ([context data, .signed .i32 count, .signed .i32 index, .signed .i32 depth].map Expr.value)
      for depth in [needed - 1, needed, needed + 7] do
        let accepted := needed ≤ depth
        let .done value after := evalExpr 5000 extractedProgram before
            (call (.rawSlice nodeType (4096 + count * 48 - 8) count) layers depth)
          | throw (IO.userError s!"recursive query trapped at height {count}, budget {depth}")
        let codes := if accepted then (List.replicate count (typeCode kind)).flatMap i32Bytes else emptyCodes
        let depths := if accepted then ((List.range count).map fun index => ((depth - layers + index : Nat) : Int)).flatMap
          i32Bytes else emptyDepths
        let expected := if accepted then known kind else result .InvalidExpression .Invalid
        unless value == expected && after.locals == before.locals &&
            after.heap.nextAddress == before.heap.nextAddress &&
            (after.heap.loadBytes 16 (count * 4)).toOption == some codes &&
            (after.heap.loadBytes 1024 (count * 4)).toOption == some depths &&
            (after.heap.loadBytes 4096 (count * 48)).toOption == some nodes do
          throw (IO.userError s!"recursive result or memory invariant failed at height {count}, budget {depth}")
        if accepted then
          -- Excess query budget makes accidental recomputation observable in
          -- the retained child budgets; one deep tree per operator is enough.
          for warmRoot in (if layers == 8 && depth == needed + 7 then [0, layers / 2, layers] else [] : List Nat) do
            for priorDepth in [warmRoot + 1, depth + 1] do
              let data := Value.rawSlice nodeType (4096 + count * 48 - 8) count
              let .done primed warm := evalExpr 5000 extractedProgram before (call data warmRoot priorDepth)
                | throw (IO.userError "warmRoot inference trapped")
              let .done value final := evalExpr 5000 extractedProgram warm (call data layers depth)
                | throw (IO.userError "partially populated recursive query trapped")
              let hit := priorDepth ≤ depth - layers + warmRoot
              let expectedDepths := ((List.range count).map fun index =>
                ((if hit && index ≤ warmRoot then priorDepth - warmRoot + index else depth - layers + index : Nat) : Int)).flatMap i32Bytes
              unless primed == known kind && value == known kind && final.locals == before.locals &&
                  final.heap.nextAddress == before.heap.nextAddress &&
                  (final.heap.loadBytes 16 (count * 4)).toOption == some codes &&
                  (final.heap.loadBytes 1024 (count * 4)).toOption == some expectedDepths &&
                  (final.heap.loadBytes 4096 (count * 48)).toOption == some nodes do
                throw (IO.userError s!"mixed-cache mismatch: height={count}, warmRoot={warmRoot}, prior={priorDepth}, query={depth}")
              mixed := mixed + 1
          for index in List.range count do
            let .done value final := evalExpr 200 extractedProgram after (call .unit index depth)
              | throw (IO.userError "recursive cache reuse accessed unreadable syntax")
            unless value == known kind && final.locals == before.locals &&
                final.heap.nextAddress == after.heap.nextAddress &&
                (final.heap.loadBytes 16 (count * 4)).toOption == some codes &&
                (final.heap.loadBytes 1024 (count * 4)).toOption == some depths &&
                (final.heap.loadBytes 4096 (count * 48)).toOption == some nodes do
              throw (IO.userError "recursive cache reuse changed a source fact or memory")
            reused := reused + 1
        checked := checked + 1
  IO.println s!"{checked} reset/recursive cases, {mixed} mixed-cache sequences and {reused} source-free reuses passed" : IO Unit)

end IRRecursiveInferenceTests
