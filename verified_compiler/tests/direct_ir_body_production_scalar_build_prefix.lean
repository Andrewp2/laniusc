import verified_compiler.tests.direct_ir_body_production_scalar_arena
import verified_compiler.tests.direct_ir_body_production_inputs_extract_queries
import Lanius.Semantics.EffectProof

namespace IRBodyProductionScalar

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics IRBodyProductionInputs

def buildSource := Extracted.«verified::surface_expr».Functions.«build».core
def expressionMode : Value := source_value Extracted.«verified::surface_expr».Types.«BuildMode».«ExpressionMode» []
def buildCall (tree : Tree) (arena : Arena) (node depth : Nat) : Expr :=
  .call buildSource.id ([buildContext tree arena.value, .signed .i32 node,
    .signed .i32 depth, expressionMode].map Expr.value)

private def modeValue : Extracted.«verified::surface_expr».Types.«BuildMode» → Value
  | .ExpressionMode => expressionMode
  | .ArgumentListMode => source_value Extracted.«verified::surface_expr».Types.«BuildMode».«ArgumentListMode» []
  | .ArrayListMode => source_value Extracted.«verified::surface_expr».Types.«BuildMode».«ArrayListMode» []
  | .StructFieldListMode => source_value Extracted.«verified::surface_expr».Types.«BuildMode».«StructFieldListMode» []
  | .MatchArmListMode => source_value Extracted.«verified::surface_expr».Types.«BuildMode».«MatchArmListMode» []
  | .PatternMode => source_value Extracted.«verified::surface_expr».Types.«BuildMode».«PatternMode» []
  | .PatternListMode => source_value Extracted.«verified::surface_expr».Types.«BuildMode».«PatternListMode» []
private def expressionModeMatches : Extracted.«verified::surface_expr».Types.«BuildMode» → Bool
  | .ExpressionMode => true | _ => false

@[core_pure_rule] private theorem actualMode (expected : Extracted.«verified::surface_expr».Types.«BuildMode»)
    (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before
      (.call Extracted.«verified::surface_expr».Functions.«mode_is».core.id [.value expressionMode, .value (modeValue expected)])
      (.boolean (expressionModeMatches expected)) after ∧ PureFrame before after := by
  cases expected <;> dsimp only [modeValue, expressionModeMatches, expressionMode]
  all_goals (core_call_pure Extracted.«verified::surface_expr».Functions.«mode_is».core as callee; core_pure)

/-- The shared real expression-mode prefix ends at the actual production
    binding. The closed extractor discharges this internal continuation. -/
theorem actualBuildWith (tree : Tree) (arena : Arena) (index depth : Nat)
    (positive : 0 < depth) (depthFits : depth < 2 ^ 31) (formed : before.CellsWellFormed)
    (continuation : ∀ {state : State}, state.heap = before.heap → state.CellsWellFormed →
      state.i32ArrayViews = before.i32ArrayViews →
      state.local? (buildSource.argumentId 0) = some (buildContext tree arena.value) →
      state.local? (buildSource.argumentId 1) = some (.signed .i32 index) →
      state.local? (buildSource.argumentId 2) = some (.signed .i32 depth) →
      state.local? (buildSource.bindingId 0) = some arena.value →
      state.local? (buildSource.bindingId 1) = some (.rawSlice expressionNodeType arena.nodes arena.capacity) →
      ∃ after, RunsStmt extractedProgram state (buildSource.bindingStatement 49)
        (.returned (some value)) after ∧ MemoryEffect relation state after) :
    ∃ after, RunsExpr extractedProgram before (buildCall tree arena index depth) value after ∧
      MemoryEffect relation before after := by
  have modeExpression {state : State} (cells : state.CellsWellFormed) := actualMode .ExpressionMode cells
  have modeArguments {state : State} (cells : state.CellsWellFormed) := actualMode .ArgumentListMode cells
  have modeArray {state : State} (cells : state.CellsWellFormed) := actualMode .ArrayListMode cells
  have modeFields {state : State} (cells : state.CellsWellFormed) := actualMode .StructFieldListMode cells
  have modeMatch {state : State} (cells : state.CellsWellFormed) := actualMode .MatchArmListMode cells
  have modePattern {state : State} (cells : state.CellsWellFormed) := actualMode .PatternMode cells
  have modePatterns {state : State} (cells : state.CellsWellFormed) := actualMode .PatternListMode cells
  dsimp only [modeValue, expressionModeMatches, expressionMode] at modeExpression modeArguments modeArray modeFields modeMatch modePattern modePatterns
  core_facts [arena, tree]
  core_call_framed (RunsExpr.callEffect (MemoryEffect.scopeStable _)) buildSource as callee
  repeat first
    | (apply RunsStmt.letEffect (MemoryEffect.scopeStable _); core_run; core_formed)
    | (apply RunsStmt.guardEffectFalse (MemoryEffect.scopeStable _);
        core_pure_guard; intro ready frame)
  core_state ready
  exact continuation (by core_frame) (by core_formed) (by core_frame)
    (by core_local) (by core_local) (by core_local) (by core_local) (by core_local)

#print axioms actualBuildWith

end IRBodyProductionScalar
