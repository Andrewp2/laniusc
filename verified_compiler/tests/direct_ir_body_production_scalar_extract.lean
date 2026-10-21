import verified_compiler.tests.direct_ir_body_production_scalar_build_prefix
import verified_compiler.tests.direct_ir_type_cache_fill
import Lanius.Semantics.EffectProof

namespace IRBodyProductionScalar

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics IRBodyProductionInputs
open IRTypeCacheFillProof (Literal)

def literalKind : Value := source_value Extracted.«verified::surface_expr».Types.«SurfaceExprKind».«Literal» []
def literalProduction : Literal → Int
  | .integer => 175 | .boolean true => 185 | .boolean false => 186 | .string => 177
private theorem literalProductionRange (literal : Literal) :
    175 ≤ literalProduction literal ∧ literalProduction literal ≤ 186 := by
  cases literal <;> try (rename_i flag; cases flag)
  all_goals decide
def literalNode (literal : Literal) (token : Int32) : Value :=
  expressionNode literalKind literal.operator (-1) (-1) token

@[native_store_rule] private theorem minusOneCodec :
    NativeStoreSpec (fuel + 1) extractedProgram (.scalar (.signed .i32)) (.signed .i32 (-1)) 8 := by
  simpa using (NativeStoreSpec.i32 (program := extractedProgram) (fuel := fuel)
    (BitVec.ofInt 32 (-1))).enlarge (by decide : 4 ≤ 8)

theorem literalNodeCodec (literal : Literal) (token : Int32) :
    NativeStoreSpec 64 extractedProgram expressionNodeType (literalNode literal token) 48 := by
  cases literal <;> try (rename_i flag; cases flag)
  all_goals (dsimp only [literalNode, expressionNode, literalKind, Literal.operator]; native_store)

@[core_pure_rule] private theorem actualLiteralProduction (literal : Literal) (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before
      (.call Extracted.«verified::surface_expr».Functions.«literal_production».core.id [.value (.signed .i32 (literalProduction literal))])
      (.boolean true) after ∧ PureFrame before after := by
  cases literal <;> try (rename_i flag; cases flag)
  all_goals
    dsimp only [literalProduction]
    core_call_pure Extracted.«verified::surface_expr».Functions.«literal_production».core as callee
    core_pure

@[core_pure_rule] private theorem actualLiteralOperator (literal : Literal) (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before
      (.call Extracted.«verified::surface_expr».Functions.«literal_operator».core.id [.value (.signed .i32 (literalProduction literal))])
      literal.operator after ∧ PureFrame before after := by
  cases literal <;> try (rename_i flag; cases flag)
  all_goals
    dsimp only [literalProduction, Literal.operator]
    core_call_pure Extracted.«verified::surface_expr».Functions.«literal_operator».core as callee
    core_pure

private theorem actualBuildLiteralTail (node : NativeNode tree before.heap index) (literal : Literal)
    (production : node.production = literalProduction literal) (count : node.count = 1)
    (child : NativeChild tree before.heap node.first) (kind : child.kind = .TokenChild)
    (token : Nat) (payload : child.payload = Int.ofNat token) (tokenFits : token < 2 ^ 31)
    (slot : ArenaSlot before) (depth : Nat) (positive : 0 < depth) (depthFits : depth < 2 ^ 31)
    (formed : before.CellsWellFormed) (unique : HeapBlockBasesUnique before.heap) (noViews : before.i32ArrayViews = [])
    (contextFound : before.local? (buildSource.argumentId 0) = some (buildContext tree slot.arena.value))
    (indexFound : before.local? (buildSource.argumentId 1) = some (.signed .i32 index))
    (depthFound : before.local? (buildSource.argumentId 2) = some (.signed .i32 depth))
    (arenaFound : before.local? (buildSource.bindingId 0) = some slot.arena.value)
    (nodesFound : before.local? (buildSource.bindingId 1) =
      some (.rawSlice expressionNodeType slot.arena.nodes slot.arena.capacity)) :
    ∃ after, RunsStmt extractedProgram before (buildSource.bindingStatement 49)
      (.returned (some (.signed .i32 slot.next))) after ∧
      MemoryEffect (ArenaStored slot (literalNode literal (Int32.ofNat token))) before after := by
  have represented : (Int32.ofNat token).toInt = token := by
    rw [Int32.toInt_ofNat']
    change (token : Int).bmod 4294967296 = token
    apply Int.bmod_eq_of_le <;> omega
  have minusOne : (-1 : Int32).toInt = (-1 : Int) := by decide +kernel
  have selectedToken {state : State} (same : state.heap = before.heap) (cells : state.CellsWellFormed) :
      ∃ after, RunsExpr extractedProgram state
        (.call Extracted.«verified::surface_expr».Functions.«token_child».core.id
          [.value (buildContext tree slot.arena.value), .value (.signed .i32 index), .value (.signed .i32 0)])
        (.signed .i32 token) after ∧ PureFrame state after := by
    simpa only [payload, Int.natCast_zero, Int.ofNat_eq_natCast] using actualExpressionToken node 0 (by rw [count]; decide)
      child kind slot.arena.value same cells
  have append {state : State} (same : state.heap = before.heap) (cells : state.CellsWellFormed)
      (views : state.i32ArrayViews = before.i32ArrayViews) :
      ∃ after, RunsExpr extractedProgram state
        (.call Extracted.«verified::surface_expr».Functions.«append».core.id
          [.value slot.arena.value, .value literalKind, .value literal.operator,
            .value (.signed .i32 (-1)), .value (.signed .i32 (-1)), .value (.signed .i32 token)])
        (.signed .i32 slot.next) after ∧
        MemoryEffect (ArenaStored slot (literalNode literal (Int32.ofNat token))) state after := by
    simpa only [literalNode, MemoryEffect, ArenaSlot.call, appendSource, List.map, ArenaSlot.reheap, ArenaStored, represented, minusOne] using
      actualArenaAppend (slot.reheap same) literalKind literal.operator (-1) (-1) (Int32.ofNat token)
        (literalNodeCodec literal _) cells (by rw [same]; exact unique) (views.trans noViews)
  have recognized {state : State} (cells : state.CellsWellFormed) :
      ∃ after, RunsExpr extractedProgram state
        (.call Extracted.«verified::surface_expr».Functions.«literal_production».core.id [.value (.signed .i32 node.production)])
        (.boolean true) after ∧ PureFrame state after := by
    rw [production]
    exact actualLiteralProduction literal cells
  have operator {state : State} (cells : state.CellsWellFormed) :
      ∃ after, RunsExpr extractedProgram state
        (.call Extracted.«verified::surface_expr».Functions.«literal_operator».core.id [.value (.signed .i32 node.production)])
        literal.operator after ∧ PureFrame state after := by
    rw [production]
    exact actualLiteralOperator literal cells
  have productionRange : 175 ≤ node.production ∧ node.production ≤ 186 := by
    simpa only [production] using literalProductionRange literal
  core_facts [slot, slot.arena, node]
  core_effect (by assumption)

/-- A reached original literal leaf is extracted by the actual build1869 call.
    Its original queries and arena append execution are both discharged here. -/
theorem actualBuildLiteral (node : NativeNode tree before.heap index) (literal : Literal)
    (production : node.production = literalProduction literal) (count : node.count = 1)
    (child : NativeChild tree before.heap node.first) (kind : child.kind = .TokenChild)
    (token : Nat) (payload : child.payload = Int.ofNat token) (tokenFits : token < 2 ^ 31)
    (slot : ArenaSlot before) (depth : Nat) (positive : 0 < depth) (depthFits : depth < 2 ^ 31)
    (formed : before.CellsWellFormed) (unique : HeapBlockBasesUnique before.heap) (noViews : before.i32ArrayViews = []) :
    ∃ after, RunsExpr extractedProgram before (buildCall tree slot.arena index depth)
      (.signed .i32 slot.next) after ∧
      MemoryEffect (ArenaStored slot (literalNode literal (Int32.ofNat token))) before after := by
  apply actualBuildWith tree slot.arena index depth positive depthFits formed
  intro state same cells views contextFound indexFound depthFound arenaFound nodesFound
  let reachedNode : NativeNode tree state.heap index :=
    { node with snapshot := by simpa only [same] using node.snapshot }
  let reachedChild : NativeChild tree state.heap node.first :=
    { child with snapshot := by simpa only [same] using child.snapshot }
  simpa only [reachedNode, reachedChild, MemoryEffect, ArenaSlot.reheap, ArenaStored] using
    actualBuildLiteralTail reachedNode literal production count reachedChild kind token payload tokenFits
      (slot.reheap same) depth positive depthFits cells (by rw [same]; exact unique) (views.trans noViews)
      contextFound indexFound depthFound arenaFound nodesFound

def expressionInput (tree : Tree) (root depth : Nat) : Value :=
  source_value Extracted.«verified::surface_expr».Types.«ExpressionInput».mk
    [tree.value, .signed .i32 root, .signed .i32 depth]
private def extractAppendSource := Extracted.«verified::surface_expr».Functions.«extract_append».core
def extractAppendCall (tree : Tree) (arena : Arena) (root depth : Nat) : Expr :=
  .call extractAppendSource.id [.value (expressionInput tree root depth), .value arena.value]

/-- The real extractor's checked entry calls the proved builder, rather than
    receiving a successful build run or a preconstructed expression node. -/
theorem actualExtractAppendLiteral (node : NativeNode tree before.heap index) (literal : Literal)
    (production : node.production = literalProduction literal) (count : node.count = 1)
    (child : NativeChild tree before.heap node.first) (kind : child.kind = .TokenChild)
    (token : Nat) (payload : child.payload = Int.ofNat token) (tokenFits : token < 2 ^ 31)
    (slot : ArenaSlot before) (depth : Nat) (positive : 0 < depth) (depthFits : depth < 2 ^ 31)
    (formed : before.CellsWellFormed) (unique : HeapBlockBasesUnique before.heap) (noViews : before.i32ArrayViews = []) :
    ∃ after, RunsExpr extractedProgram before (extractAppendCall tree slot.arena index depth)
      (.signed .i32 slot.next) after ∧
      MemoryEffect (ArenaStored slot (literalNode literal (Int32.ofNat token))) before after := by
  have countRead := countCellRead (state := before) (id := expressionCountId)
    (by decide +kernel) (by decide +kernel) (by decide +kernel) slot.arena.countPositive slot.countRead
  have builder {state : State} (same : state.heap = before.heap) (cells : state.CellsWellFormed)
      (views : state.i32ArrayViews = before.i32ArrayViews) :
      ∃ after, RunsExpr extractedProgram state (buildCall tree slot.arena index depth)
        (.signed .i32 slot.next) after ∧
        MemoryEffect (ArenaStored slot (literalNode literal (Int32.ofNat token))) state after := by
    let reachedNode : NativeNode tree state.heap index :=
      { node with snapshot := by simpa only [same] using node.snapshot }
    let reachedChild : NativeChild tree state.heap node.first :=
      { child with snapshot := by simpa only [same] using child.snapshot }
    simpa only [reachedNode, reachedChild, MemoryEffect, ArenaSlot.reheap, ArenaStored] using
      actualBuildLiteral reachedNode literal production count reachedChild kind token payload tokenFits
        (slot.reheap same) depth positive depthFits cells (by rw [same]; exact unique) (views.trans noViews)
  core_facts [slot, slot.arena]
  core_call_framed (RunsExpr.callEffect (MemoryEffect.scopeStable _)) extractAppendSource as callee
  core_effect (by assumption)

#print axioms literalNodeCodec
#print axioms actualBuildLiteral
#print axioms actualExtractAppendLiteral

end IRBodyProductionScalar
