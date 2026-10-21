import verified_compiler.tests.direct_ir_expression_kind
import verified_compiler.tests.direct_ir_expression_validation

namespace IRTypeCacheProof

open Lanius Lanius.Core Lanius.Semantics IRTypeRefProof IRExpressionKindProof

private def source := Extracted.«lowering::body_expression».Functions.«expression_kind».core
/-- Query bounds shared by cold inference and cache reuse. -/
structure Query where
  node : Nat
  count : Nat
  capacity : Nat
  codes : Nat
  depths : Nat
  depth : Int32
  inside : node < count
  storage : count ≤ capacity
  fits : capacity < 2 ^ 31
  positive : 0 < depth.toInt

/-- Recursive queries change the node and budget, not the cache's storage. -/
def Query.storageKey (query : Query) : Nat × Nat × Nat × Nat :=
  (query.codes, query.depths, query.count, query.capacity)

/-- A cache entry carries a readable encoded type and the budget under which
    inference established it. Its semantic validity belongs to the caller's
    arena/cache invariant, not an assumed successful lookup execution. -/
structure Entry (before : State) extends Query where
  storedDepth : Int32
  kind : Reference
  sufficient : storedDepth.toInt ≤ depth.toInt
  supported : isValidResult kind = true
  codeRead : readRawSliceIndex extractedProgram before (.scalar (.signed .i32)) codes capacity node =
    .ok (.signed .i32 (typeCode kind))
  depthRead : readRawSliceIndex extractedProgram before (.scalar (.signed .i32)) depths capacity node =
    .ok (.signed .i32 storedDepth.toInt)

def Query.context (query : Query) (header : Fin 5 → Value) (nodes countCell : Value) (unused : List Value) : Value :=
  IRExpressionValidationProof.context nodes countCell (.signed .i32 query.capacity) header
    ([.rawSlice (.scalar (.signed .i32)) query.codes query.capacity,
      .rawSlice (.scalar (.signed .i32)) query.depths query.capacity] ++ unused)

def Query.call (query : Query) (header : Fin 5 → Value) (nodes countCell : Value) (unused : List Value) : Expr :=
  .call source.id ([query.context header nodes countCell unused, .signed .i32 query.count,
    .signed .i32 query.node, .signed .i32 query.depth.toInt].map Expr.value)

/-- The actual query returns exactly the stored type and preserves memory.
    A hit does not inspect source nodes or the unused context fields. -/
theorem actualHit (entry : Entry before) (header : Fin 5 → Value) (nodes countCell : Value) (unused : List Value)
    (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before (entry.toQuery.call header nodes countCell unused)
      (known entry.kind) after ∧ PureFrame before after := by
  core_facts [entry]
  have nonnegative : 0 ≤ typeCode entry.kind := of_decide_eq_true entry.supported
  core_call_pure source as callee
  core_pure

#print axioms actualHit

end IRTypeCacheProof
