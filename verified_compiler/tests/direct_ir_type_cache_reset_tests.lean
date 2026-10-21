import verified_compiler.tests.direct_ir_type_cache_reset

namespace IRTypeCacheResetTests

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics

-- Partial resets must preserve the suffix, other tables and caller state.
-- Count zero deliberately receives an unreadable pointer. Repeating a reset
-- must be harmless, including when old entries contain invalid type codes.
#eval (do
  let mut checked := 0
  for capacity in [0, 1, 3, 8] do
    for count in List.range (capacity + 1) do
      for old in ([1, 1073741808, -2147483648] : List Int) do
        let initial := [91] ++ List.replicate capacity old ++ [92]
        let expected := [91] ++ List.replicate count (-1) ++ List.replicate (capacity - count) old ++ [92]
        let budgets := (List.range capacity).map (fun index => Int.ofNat index + 1)
        let before := ({ heap := {
          blocks := [
            { base := 16, size := (capacity + 2) * 4, alignment := 4, bytes := initial.flatMap i32Bytes },
            { base := 128, size := capacity * 4, alignment := 4, bytes := budgets.flatMap i32Bytes }]
          nextAddress := 160 } } : State) |>.bindLocal 99 (.signed .i32 321)
        let call := Expr.call Extracted.«lowering::body_expression».Functions.«clear_expression_kinds».core.id
          [.value (.rawSlice (.scalar (.signed .i32)) (if count == 0 then 9999 else 20) capacity),
            .value (.signed .i32 count)]
        let .done value after := evalExpr 1000 extractedProgram before call
          | throw (IO.userError "cache reset trapped")
        let .done again final := evalExpr 1000 extractedProgram after call
          | throw (IO.userError "repeated cache reset trapped")
        unless value == .unit && again == .unit do throw (IO.userError "cache reset returned a value")
        for state in [after, final] do
          unless (state.heap.loadBytes 16 ((capacity + 2) * 4)).toOption == some (expected.flatMap i32Bytes) &&
              (state.heap.loadBytes 128 (capacity * 4)).toOption == some (budgets.flatMap i32Bytes) &&
              state.locals == before.locals && state.heap.nextAddress == before.heap.nextAddress do
            throw (IO.userError s!"reset/frame mismatch: capacity={capacity}, count={count}, old={old}")
        checked := checked + 1
  IO.println s!"{checked} stale/corrupt/partial/empty cache reset cases passed" : IO Unit)

end IRTypeCacheResetTests
