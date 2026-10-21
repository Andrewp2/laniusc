import verified_compiler.tests.direct_ir_error

namespace IRExpressionValidationProof

open Lanius Lanius.Core Lanius.Semantics

private def source := Extracted.«lowering::body_expression».Functions.«expression».core

/-- The context prefix used before validation. All memory descriptors and
    unused fields may be arbitrary: the rejected call must not read them. -/
def context (data count capacity : Value) (header : Fin 5 → Value) (suffix : List Value) : Value :=
  .structure (match source_value Extracted.«lowering::body_context».Types.«BodyContext».mk [] with
    | .structure id _ => id | _ => 0)
    ([header 0, header 1, header 2, header 3, header 4,
      source_value Extracted.«verified::surface_expr».Types.«ExpressionArena».mk [data, count, capacity]] ++ suffix)

def call (context : Value) (count node depth : Int) (output : Value) (position : Int) : Expr :=
  .call source.id ([context, .signed .i32 count, .signed .i32 node, output,
    .signed .i32 position, .signed .i32 depth].map Expr.value)

/-- Every out-of-range root or exhausted recursion budget rejects before
    reading source nodes or touching output, even with invalid descriptors. -/
theorem actualBounds (data count capacity : Value) (header : Fin 5 → Value) (unused : List Value)
    (nodes node depth : Int) (bad : depth ≤ 0 ∨ node < 0 ∨ nodes ≤ node)
    (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before
      (call (context data count capacity header unused) nodes node depth output position)
      (.signed .i32 (-1)) after ∧ PureFrame before after := by
  core_call_pure source as callee
  core_pure

#print axioms actualBounds

end IRExpressionValidationProof
