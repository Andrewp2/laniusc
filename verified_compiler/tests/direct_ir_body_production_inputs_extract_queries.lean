import verified_compiler.tests.direct_ir_body_production_inputs

namespace IRBodyProductionInputs

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics

def buildContext (tree : Tree) (arena : Value) : Value := source_value Extracted.«verified::surface_expr».Types.«BuildContext».mk
  [tree.value, arena]
@[core_pure_rule] theorem actualExpressionProduction (node : NativeNode tree heap index)
    (arena : Value) (same : before.heap = heap) (formed : before.CellsWellFormed) : ∃ after, RunsExpr extractedProgram before
      (.call Extracted.«verified::surface_expr».Functions.«production».core.id
        [.value (buildContext tree arena), .value (.signed .i32 index)])
      (.signed .i32 node.production) after ∧ PureFrame before after := by
  subst heap
  core_call_pure Extracted.«verified::surface_expr».Functions.«production».core as callee
  core_pure
@[core_pure_rule] theorem actualExpressionChildren (node : NativeNode tree heap index)
    (arena : Value) (same : before.heap = heap) (formed : before.CellsWellFormed) : ∃ after, RunsExpr extractedProgram before
      (.call Extracted.«verified::surface_expr».Functions.«children».core.id
        [.value (buildContext tree arena), .value (.signed .i32 index)])
      (.signed .i32 node.count) after ∧ PureFrame before after := by
  subst heap
  core_call_pure Extracted.«verified::surface_expr».Functions.«children».core as callee
  core_pure
@[core_pure_rule] theorem actualExpressionChild (node : NativeNode tree heap index) (slot : Nat)
    (bound : slot < node.count) (child : NativeChild tree heap (node.first + slot))
    (kind : child.kind = .StateChild) (arena : Value) (same : before.heap = heap) (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before
      (.call Extracted.«verified::surface_expr».Functions.«child».core.id
        [.value (buildContext tree arena), .value (.signed .i32 index), .value (.signed .i32 slot)])
      (.signed .i32 child.payload) after ∧ PureFrame before after := by
  subst heap
  have selected : childKindValue child.kind = childKindValue .StateChild := by rw [kind]
  core_call_pure Extracted.«verified::surface_expr».Functions.«child».core as callee
  core_pure
@[core_pure_rule] theorem actualExpressionToken (node : NativeNode tree heap index) (slot : Nat)
    (bound : slot < node.count) (child : NativeChild tree heap (node.first + slot))
    (kind : child.kind = .TokenChild) (arena : Value) (same : before.heap = heap) (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before
      (.call Extracted.«verified::surface_expr».Functions.«token_child».core.id
        [.value (buildContext tree arena), .value (.signed .i32 index), .value (.signed .i32 slot)])
      (.signed .i32 child.payload) after ∧ PureFrame before after := by
  subst heap
  have selected : childKindValue child.kind = childKindValue .TokenChild := by rw [kind]
  core_call_pure Extracted.«verified::surface_expr».Functions.«token_child».core as callee
  core_pure

#print axioms actualExpressionProduction
#print axioms actualExpressionChildren
#print axioms actualExpressionChild
#print axioms actualExpressionToken

end IRBodyProductionInputs
