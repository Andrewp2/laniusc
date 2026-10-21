import verified_compiler.tests.direct_ir_binary_kind
import verified_compiler.tests.direct_ir_type_cache_invariant
import Lanius.Semantics.EffectProof

namespace IRBinaryInferenceProof

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics
open IRTypeRefProof IRExpressionKindProof IRTypeCacheProof IRBinaryKindProof
open IRTypeCacheFillProof (Environment nodeType)

private def source := Extracted.«lowering::body_expression».Functions.«expression_kind_uncached».core
private def hasKind := Extracted.«verified::surface_expr».Functions.«has_kind».core
private def binaryTag := source_value Extracted.«verified::surface_expr».Types.«SurfaceExprKind».«Binary» []
private def literalTag := source_value Extracted.«verified::surface_expr».Types.«SurfaceExprKind».«Literal» []
private def unaryTag := source_value Extracted.«verified::surface_expr».Types.«SurfaceExprKind».«Unary» []

@[core_pure_rule] private theorem binaryIsLiteral (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before (.call hasKind.id [.value binaryTag, .value literalTag])
      (.boolean false) after ∧ PureFrame before after := by
  core_call_pure hasKind as callee
  core_pure

@[core_pure_rule] private theorem binaryIsUnary (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before (.call hasKind.id [.value binaryTag, .value unaryTag])
      (.boolean false) after ∧ PureFrame before after := by
  core_call_pure hasKind as callee
  core_pure

@[core_pure_rule] private theorem binaryIsBinary (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before (.call hasKind.id [.value binaryTag, .value binaryTag])
      (.boolean true) after ∧ PureFrame before after := by
  core_call_pure hasKind as callee
  core_pure

def nodeValue (op : Surface.BinaryOp) (left right : Nat) (unused : Fin 2 → Value) : Value :=
  source_value Extracted.«verified::surface_expr».Types.«ExpressionNode».mk
    [binaryTag, sourceValue op, .signed .i32 left, .signed .i32 right, unused 0, unused 1]

/-- Native syntax and bounds for one binary node. No child execution is a
    field; the recursive theorem supplies those by induction. -/
structure Input (before : State) where
  left : Query
  right : Nat
  rightInside : right < left.count
  root : Nat
  inside : root < left.count
  depth : Int32
  predecessor : depth.toInt - 1 = left.depth.toInt
  nodes : Nat
  env : Environment
  op : Surface.BinaryOp
  unused : Fin 2 → Value
  nodeRead : readRawSliceIndex extractedProgram before nodeType nodes left.capacity root =
    .ok (nodeValue op left.node right unused)

def Input.context (input : Input before) : Value :=
  input.left.context input.env.header (.rawSlice nodeType input.nodes input.left.capacity)
    input.env.countCell input.env.suffix
def Input.call (input : Input before) : Expr :=
  .call source.id ([input.context, .signed .i32 input.left.count, .signed .i32 input.root,
    .signed .i32 input.depth.toInt].map Expr.value)
def Input.rightQuery (input : Input before) : Query :=
  { input.left with node := input.right, inside := input.rightInside }
def Input.query (input : Input before) : Query :=
  { input.left with
    node := input.root
    inside := input.inside
    depth := input.depth
    positive := by have := input.predecessor; have := input.left.positive; omega }
def Input.site (input : Input before) : Site :=
  ⟨input.context, input.left.count, input.left.node, input.right⟩
def Input.reheap (input : Input before) (same : after.heap = before.heap) : Input after :=
  { input with nodeRead := by simpa only [readRawSliceIndex, same] using input.nodeRead }

/-- Compose operand evaluation in source order. The right callback receives
    the left operand's retained cache writes, not the original empty heap. -/
theorem actualWith {relation : Heap → Heap → Prop} {result : Value}
    (input : Input before) (leftKind rightKind : Reference)
    (leftValid : isValid leftKind = true) (rightValid : isValid rightKind = true)
    (compose : ∀ {a b c}, relation a b → relation b c → relation a c)
    (left : ∀ {state : State}, state.heap = before.heap → state.CellsWellFormed →
      state.i32ArrayViews = before.i32ArrayViews →
      ∃ after, RunsExpr extractedProgram state
        (input.left.call input.env.header (.rawSlice nodeType input.nodes input.left.capacity)
          input.env.countCell input.env.suffix) (known leftKind) after ∧ MemoryEffect relation state after)
    (right : ∀ {state : State}, relation before.heap state.heap → state.CellsWellFormed →
      state.i32ArrayViews = before.i32ArrayViews →
      ∃ after, RunsExpr extractedProgram state
        (input.rightQuery.call input.env.header (.rawSlice nodeType input.nodes input.left.capacity)
          input.env.countCell input.env.suffix) (known rightKind) after ∧ MemoryEffect relation state after)
    (decision : ∀ {state : State}, state.CellsWellFormed →
      ∃ after, RunsExpr extractedProgram state
        (input.site.call input.op (known leftKind) (known rightKind)) result after ∧ PureFrame state after)
    (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before input.call result after ∧ MemoryEffect relation before after := by
  core_facts 4 [input]
  have depthBound := input.depth.toInt_lt
  have subtract := eval_i32_subNonneg extractedProgram.target input.depth.toInt 1 (by omega) (by omega)
  rw [input.predecessor] at subtract
  have operation := fun {state : State} (h : state.CellsWellFormed) => actualOperation input.op h
  have notInvalid : evalBinaryValue extractedProgram.target .equal (operationValue input.op)
      (source_value Extracted.«backend::syntax».Types.«BinaryOperation».«InvalidBinaryOperation» []) =
      .ok (.boolean false) := by cases input.op <;> rfl
  have operandLeft := fun {state : State} (h : state.CellsWellFormed) => actualOperand .KnownExpression leftKind h
  have operandRight := fun {state : State} (h : state.CellsWellFormed) => actualOperand .KnownExpression rightKind h
  simp only [operand, leftValid, ↓reduceIte] at operandLeft
  simp only [operand, rightValid, ↓reduceIte] at operandRight
  core_call_framed (RunsExpr.callEffect (MemoryEffect.scopeStable _)) source as callee
  core_effect compose

#print axioms actualWith

end IRBinaryInferenceProof
