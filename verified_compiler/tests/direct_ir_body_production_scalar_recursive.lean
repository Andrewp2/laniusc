import verified_compiler.tests.direct_ir_body_production_scalar_extract_reset
import verified_compiler.tests.direct_ir_body_production_scalar_cache
import Lanius.Semantics.CountedLocal
import Lanius.Semantics.LoopRun

namespace IRBodyProductionScalar

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics IRBodyProductionInputs

variable {before after : State} {input : Inputs}

/-- A literal child uses the same original storage map as its enclosing
    unary expression; it writes only slot0 and the selected count field. -/
private theorem actualLiteralStored (storage : ScalarStorage workspace before slots)
    (node : NativeNode input.tree before.heap index) (literal : IRTypeCacheFillProof.Literal)
    (production : node.production = literalProduction literal) (count : node.count = 1)
    (child : NativeChild input.tree before.heap node.first) (kind : child.kind = .TokenChild)
    (token : Nat) (payload : child.payload = Int.ofNat token) (tokenFits : token < 2 ^ 31)
    (zero : readNativeValue 64 extractedProgram before.heap (.scalar (.signed .i32)) storage.arena.count =
      .ok (.signed .i32 0))
    (depth : Nat) (positive : 0 < depth) (fits : depth < 2 ^ 31)
    (formed : before.CellsWellFormed) (unique : HeapBlockBasesUnique before.heap) (noViews : before.i32ArrayViews = []) :
    ∃ after, RunsExpr extractedProgram before (buildCall input.tree storage.arena index depth) (.signed .i32 0) after ∧
      MemoryEffect (ProducedNodes storage 1 (fun _ => literalNode literal (Int32.ofNat token))) before after := by
  let slot : ArenaSlot before := {
    arena := storage.arena, next := 0, base := storage.bases 0
    bound := by have := storage.bound; have := storage.positive; omega
    location := storage.locations 0 storage.positive
    countRead := zero
    nodeRoom := storage.nodeRoom 0 storage.positive
    countRoom := storage.countRoom
    separate := storage.nodeCount 0 storage.positive }
  obtain ⟨after, run, effect⟩ := actualBuildLiteral node literal production count child kind token payload tokenFits
    slot depth positive fits formed unique noViews
  rcases effect.2.2.2 with ⟨native, one, middle, nodeWrite, countWrite⟩
  have nodesWrite := nodeWrite.footprint.weaken (larger := storage.writes)
    (fun address range => Or.inr (Or.inl ⟨0, storage.positive, range⟩))
  have countWrites := countWrite.footprint.weaken (larger := storage.writes)
    (fun address range => Or.inl range)
  refine ⟨after, run, effect.1, effect.2.1, effect.2.2.1, ?_, one, nodesWrite.trans countWrites⟩
  intro index bound
  have atZero : index = 0 := by omega
  subst index
  exact native

@[core_pure_rule] private theorem actualNonLiteral (production : Int) (lower : 0 ≤ production)
    (upper : production < 175) (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before
      (.call Extracted.«verified::surface_expr».Functions.«literal_production».core.id
        [.value (.signed .i32 production)]) (.boolean false) after ∧ PureFrame before after := by
  core_call_pure Extracted.«verified::surface_expr».Functions.«literal_production».core as callee
  core_pure

private def wrapperRest : Stmt := match buildSource.bindingStatement 59 with
  | .letLocal _ _ _ rest => rest | _ => .skip
private def wrapperGuard : Stmt := match wrapperRest with
  | .sequence first _ => first | _ => .skip
private def wrapperReturn : Stmt := match wrapperRest with
  | .sequence _ last => last | _ => .skip

/-- GROUP's selected-child local is fresh to this scope. Its real SET does
    not preserve that fresh cell, but it preserves the caller's cells. -/
private theorem actualWrapperScope (node : NativeNode tree before.heap index) (arena : Arena)
    (slot operand depth : Nat) (selected : slot = if node.production = 172 then 1 else 0)
    (inside : slot < node.count) (child : NativeChild tree before.heap (node.first + slot))
    (kind : child.kind = .StateChild) (payload : child.payload = Int.ofNat operand)
    (depthFits : depth < 2 ^ 31) (positive : 1 < depth) (formed : before.CellsWellFormed)
    (contextFound : before.local? (buildSource.argumentId 0) = some (buildContext tree arena.value))
    (indexFound : before.local? (buildSource.argumentId 1) = some (.signed .i32 index))
    (depthFound : before.local? (buildSource.argumentId 2) = some (.signed .i32 depth))
    (productionFound : before.local? (buildSource.bindingId 49) = some (.signed .i32 node.production))
    (recursive : ∀ {state : State}, state.heap = before.heap → state.CellsWellFormed →
      state.i32ArrayViews = before.i32ArrayViews → ∃ after,
      RunsExpr extractedProgram state (buildCall tree arena operand (depth - 1)) value after ∧
        MemoryEffect relation state after) :
    ∃ after, RunsStmt extractedProgram before (buildSource.bindingStatement 59)
      (.returned (some value)) after ∧ MemoryEffect relation before after := by
  change before.local? 2462 = some (buildContext tree arena.value) at contextFound
  change before.local? 2466 = some (.signed .i32 index) at indexFound
  change before.local? 2470 = some (.signed .i32 depth) at depthFound
  change before.local? 4306 = some (.signed .i32 node.production) at productionFound
  let indexed := before.bindLocal (buildSource.bindingId 59) (.signed .i32 0)
  have indexedFormed : indexed.CellsWellFormed := formed.bindLocal _ _
  have subtract := eval_i32_subNat extractedProgram.target depth 1 (by omega) depthFits
  have selectedChild : ∃ selectedState, RunsStmt extractedProgram indexed wrapperGuard .next selectedState ∧
      CallerFrame before selectedState ∧ CountedLocal before selectedState (buildSource.bindingId 59) slot := by
    by_cases group : node.production = 172
    · have one : slot = 1 := by simpa only [group, ↓reduceIte] using selected
      subst slot
      obtain ⟨assigned, assignment, assignedLocal, effect⟩ := RunsExpr.assignI32
        (program := extractedProgram) (before := indexed)
        (State.bindLocal_cellId before (buildSource.bindingId 59) _)
        (formed.bindLocal_local _ _) (RunsExpr.ofStable StableExpr.value rfl) (by rfl :
          evalAssignValue extractedProgram.target .set (some (.signed .i32 0)) (.signed .i32 1) = .ok (.signed .i32 1))
      have frame : CallerFrame before assigned :=
        ((CallerFrame.refl formed).bindLocal _ _).assignLocalFresh _ before.nextCell _
          (State.bindLocal_cellId before _ _) (Nat.le_refl _) assignedLocal
      have counted : CountedLocal before assigned (buildSource.bindingId 59) 1 :=
        ⟨frame.cells, effect.locals, assignLocal_finds_assigned _ _ _ (State.bindLocal_cellId before _ _) assignedLocal⟩
      refine ⟨assigned, ?_, frame, by simpa only [group, ↓reduceIte, Int.natCast_one] using counted⟩
      core_facts [counted]
      core_stmt_forward
    · have zero : slot = 0 := by simpa only [group, ↓reduceIte] using selected
      subst slot
      have counted := CountedLocal.start formed (buildSource.bindingId 59) 0
      refine ⟨indexed, ?_, (CallerFrame.refl formed).bindLocal _ _,
        by simpa only [group, ↓reduceIte, Int.natCast_zero] using counted⟩
      core_facts [counted]
      core_stmt_forward
  obtain ⟨selectedState, prefixRun, prefixFrame, counted⟩ := selectedChild
  have childRun {state : State} (same : state.heap = before.heap) (cells : state.CellsWellFormed) :=
    actualExpressionChild node slot inside child kind arena.value same cells
  simp only [payload, Int.ofNat_eq_natCast] at childRun
  core_facts [counted, prefixFrame]
  obtain ⟨after, returned, effect⟩ : ∃ after, RunsStmt extractedProgram selectedState wrapperReturn
      (.returned (some value)) after ∧ MemoryEffect relation selectedState after := by
    core_effect (by assumption)
  refine ⟨restoreLocals before after, ?_, ?_⟩
  · exact RunsStmt.letLocal (by core_run) (RunsStmt.sequenceNext prefixRun returned)
  · exact (MemoryEffect.scopeStable relation).restore before (effect.prependCaller prefixFrame)

/-- Natural EXPR/BASE/GROUP wrappers execute their selected original child.
    The recursive continuation is discharged by OriginalScalar induction. -/
theorem actualBuildWrapper (node : NativeNode tree before.heap index) (arena : Arena)
    (production : node.production = 104 ∨ node.production = 159 ∨ node.production = 172)
    (slot operand depth : Nat) (selected : slot = if node.production = 172 then 1 else 0)
    (inside : slot < node.count) (child : NativeChild tree before.heap (node.first + slot))
    (kind : child.kind = .StateChild) (payload : child.payload = Int.ofNat operand)
    (depthFits : depth < 2 ^ 31) (positive : 1 < depth) (formed : before.CellsWellFormed)
    (recursive : ∀ {state : State}, state.heap = before.heap → state.CellsWellFormed →
      state.i32ArrayViews = before.i32ArrayViews → ∃ after,
      RunsExpr extractedProgram state (buildCall tree arena operand (depth - 1)) value after ∧
        MemoryEffect relation state after) :
    ∃ after, RunsExpr extractedProgram before (buildCall tree arena index depth) value after ∧
      MemoryEffect relation before after := by
  apply actualBuildWith tree arena index depth (by omega) depthFits formed
  intro state same cells views contextFound indexFound depthFound arenaFound nodesFound
  have startingViews := views
  have notLiteral {current : State} (formed : current.CellsWellFormed) :=
    actualNonLiteral node.production (by rcases production with h | h | h <;> omega)
      (by rcases production with h | h | h <;> omega) formed
  have descend {current : State} (heap : current.heap = state.heap) (formed : current.CellsWellFormed)
      (views : current.i32ArrayViews = state.i32ArrayViews)
      (contextFound : current.local? (buildSource.argumentId 0) = some (buildContext tree arena.value))
      (indexFound : current.local? (buildSource.argumentId 1) = some (.signed .i32 index))
      (depthFound : current.local? (buildSource.argumentId 2) = some (.signed .i32 depth))
      (productionFound : current.local? (buildSource.bindingId 49) = some (.signed .i32 node.production)) :=
    actualWrapperScope (before := current) ({ node with snapshot := by simpa only [heap, same] using node.snapshot }) arena
      slot operand depth selected inside
      { child with snapshot := by simpa only [heap, same] using child.snapshot } kind payload depthFits positive
      formed contextFound indexFound depthFound productionFound
      (fun nextHeap nextFormed nextViews => recursive ((nextHeap.trans heap).trans same) nextFormed
        ((nextViews.trans views).trans startingViews))
  core_facts [node]
  core_effect (by assumption)

#print axioms actualBuildWrapper

def negateNode : Value := expressionNode
  (source_value Extracted.«verified::surface_expr».Types.«SurfaceExprKind».«Unary» [])
  IRUnaryInferenceProof.Operation.negate.sourceValue 0 (-1) (-1)

theorem negateNodeCodec : NativeStoreSpec 64 extractedProgram expressionNodeType negateNode 48 := by
  dsimp only [negateNode, expressionNode, IRUnaryInferenceProof.Operation.sourceValue]
  native_store

@[core_pure_rule] private theorem actualNegateProduction (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before
      (.call Extracted.«verified::surface_expr».Functions.«unary_production».core.id
        [.value (.signed .i32 157)]) (.boolean true) after ∧ PureFrame before after := by
  core_call_pure Extracted.«verified::surface_expr».Functions.«unary_production».core as callee
  core_pure

@[core_pure_rule] private theorem actualNegateOperator (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before
      (.call Extracted.«verified::surface_expr».Functions.«unary_operator».core.id
        [.value (.signed .i32 157)]) IRUnaryInferenceProof.Operation.negate.sourceValue after ∧ PureFrame before after := by
  core_call_pure Extracted.«verified::surface_expr».Functions.«unary_operator».core as callee
  core_pure

private theorem actualNegateTail (storage : ScalarStorage workspace before slots) (available : 2 ≤ slots)
    (node : NativeNode input.tree before.heap index) (count : node.count = 2)
    (child : NativeChild input.tree before.heap (node.first + 1)) (kind : child.kind = .StateChild)
    (operand depth : Nat) (payload : child.payload = Int.ofNat operand)
    (positive : 1 < depth) (depthFits : depth < 2 ^ 31)
    (formed : before.CellsWellFormed) (noViews : before.i32ArrayViews = [])
    (contextFound : before.local? (buildSource.argumentId 0) = some (buildContext input.tree storage.arena.value))
    (indexFound : before.local? (buildSource.argumentId 1) = some (.signed .i32 index))
    (depthFound : before.local? (buildSource.argumentId 2) = some (.signed .i32 depth))
    (arenaFound : before.local? (buildSource.bindingId 0) = some storage.arena.value)
    (productionFound : before.local? (buildSource.bindingId 49) = some (.signed .i32 157))
    (recursive : ∀ {state : State}, state.heap = before.heap → state.CellsWellFormed →
      state.i32ArrayViews = before.i32ArrayViews → ∃ after,
      RunsExpr extractedProgram state (buildCall input.tree storage.arena operand (depth - 1)) (.signed .i32 0) after ∧
        MemoryEffect (ProducedNodes storage 1 nodes) state after) :
    ∃ after, RunsStmt extractedProgram before (buildSource.bindingStatement 60)
      (.returned (some (.signed .i32 1))) after ∧
      MemoryEffect (ProducedNodes storage 2 (fun i => if i = 0 then nodes 0 else negateNode)) before after := by
  have subtract := eval_i32_subNat extractedProgram.target depth 1 (by omega) depthFits
  have childRun {state : State} (same : state.heap = before.heap) (cells : state.CellsWellFormed) :=
    actualExpressionChild node 1 (by rw [count]; decide) child kind storage.arena.value same cells
  simp only [payload, Int.ofNat_eq_natCast] at childRun
  obtain ⟨produced, operandRun, first⟩ : ∃ produced,
      RunsExpr extractedProgram before (buildSource.bindingInitializer 60) (.signed .i32 0) produced ∧
      MemoryEffect (ProducedNodes storage 1 nodes) before produced := by
    apply RunsExpr.callFramedEffectArguments (MemoryEffect.scopeStable _)
    · core_pure_arguments
    · intro ready frame
      exact recursive frame.heap frame.afterFormed frame.views
  let bound := produced.bindLocal 4917 (.signed .i32 0)
  have boundFormed : bound.CellsWellFormed := (first.1.after_cellsWellFormed formed).bindLocal _ _
  let slot : ArenaSlot bound := {
    arena := storage.arena, next := 1, base := storage.bases 1
    bound := by have := storage.bound; omega
    location := storage.locations 1 (by omega)
    countRead := first.2.2.2.2.1.read
    nodeRoom := first.2.2.2.2.2.readable _ _ (storage.nodeRoom 1 (by omega))
    countRoom := first.2.2.2.2.2.readable _ _ storage.countRoom
    separate := storage.nodeCount 1 (by omega) }
  have zero32 : (0 : Int32).toInt = (0 : Int) := by decide +kernel
  have minusOne : (-1 : Int32).toInt = (-1 : Int) := by decide +kernel
  have appendId : Extracted.«verified::surface_expr».Functions.«append».core.id = 1855 := rfl
  have append {state : State} (same : state.heap = bound.heap) (cells : state.CellsWellFormed)
      (views : state.i32ArrayViews = bound.i32ArrayViews) : ∃ after,
      RunsExpr extractedProgram state
        (.call 1855 [.value storage.arena.value,
          .value (source_value Extracted.«verified::surface_expr».Types.«SurfaceExprKind».«Unary» []),
          .value IRUnaryInferenceProof.Operation.negate.sourceValue,
          .value (.signed .i32 0), .value (.signed .i32 (-1)), .value (.signed .i32 (-1))])
        (.signed .i32 1) after ∧ MemoryEffect (ArenaStored slot negateNode) state after := by
    simpa only [ArenaSlot.call, appendSource, appendId, slot, negateNode, List.map, MemoryEffect, ArenaSlot.reheap, ArenaStored,
      zero32, minusOne, Int.natCast_one] using
      actualArenaAppend (slot.reheap same)
        (source_value Extracted.«verified::surface_expr».Types.«SurfaceExprKind».«Unary» [])
        IRUnaryInferenceProof.Operation.negate.sourceValue 0 (-1) (-1) negateNodeCodec cells
        (by rw [same]; exact first.2.2.2.2.2.unique) (views.trans (first.2.2.1.trans noViews))
  have operator {state : State} (cells : state.CellsWellFormed) : ∃ after,
      RunsExpr extractedProgram state (.call 1846 [.value (.signed .i32 157)])
        IRUnaryInferenceProof.Operation.negate.sourceValue after ∧ PureFrame state after :=
    actualNegateOperator cells
  change before.local? 2462 = some (buildContext input.tree storage.arena.value) at contextFound
  change before.local? 2466 = some (.signed .i32 index) at indexFound
  change before.local? 2470 = some (.signed .i32 depth) at depthFound
  change before.local? 2482 = some storage.arena.value at arenaFound
  change before.local? 4306 = some (.signed .i32 157) at productionFound
  have boundArena : bound.local? 2482 = some storage.arena.value :=
    State.bindLocal_local?_of_ne produced (first.1.after_cellsWellFormed formed) 2482 4917 _ _ (by decide)
      (first.1.localFound operandRun.choose_spec.2 _ _ arenaFound)
  have boundProduction : bound.local? 4306 = some (.signed .i32 157) :=
    State.bindLocal_local?_of_ne produced (first.1.after_cellsWellFormed formed) 4306 4917 _ _ (by decide)
      (first.1.localFound operandRun.choose_spec.2 _ _ productionFound)
  have boundOperand : bound.local? 4917 = some (.signed .i32 0) :=
    (first.1.after_cellsWellFormed formed).bindLocal_local _ _
  obtain ⟨completed, body, last⟩ : ∃ completed, RunsStmt extractedProgram bound
      (match buildSource.bindingStatement 60 with | .letLocal _ _ _ rest => rest | _ => .skip)
      (.returned (some (.signed .i32 1))) completed ∧ MemoryEffect (ArenaStored slot negateNode) bound completed := by
    core_facts [slot, slot.arena]
    apply RunsStmt.guardEffectFalse (MemoryEffect.scopeStable _)
    · core_pure_guard
    · intro selected guardFrame
      apply RunsStmt.returnEffect
      apply RunsExpr.callFramedEffectArguments (MemoryEffect.scopeStable _)
        (values := [storage.arena.value,
          source_value Extracted.«verified::surface_expr».Types.«SurfaceExprKind».«Unary» [],
          IRUnaryInferenceProof.Operation.negate.sourceValue, .signed .i32 0,
          .signed .i32 (-1), .signed .i32 (-1)])
      · core_pure_arguments
      · intro ready arguments
        exact append (arguments.heap.trans guardFrame.heap) arguments.afterFormed
          (arguments.views.trans guardFrame.views)
  rcases last.2.2.2 with ⟨parent, storedCount, middle, nodeWrite, countWrite⟩
  have leaf := (first.2.2.2.1 0 (by decide)).afterWrite nodeWrite
    (storage.nodeSeparation 0 1 (by omega) (by omega) (by decide))
  have leaf := leaf.afterWrite countWrite (storage.nodeCount 0 (by omega))
  have nodesWrite := nodeWrite.footprint.weaken (larger := storage.writes)
    (fun address range => Or.inr (Or.inl ⟨1, by omega, range⟩))
  have countWrites := countWrite.footprint.weaken (larger := storage.writes)
    (fun address range => Or.inl range)
  refine ⟨restoreLocals produced completed, RunsStmt.letLocal operandRun body,
    (first.1.trans (FreshCellFrame.bindLocal produced _ _)).trans last.1,
    last.2.1.trans first.2.1, last.2.2.1.trans first.2.2.1, ?_, storedCount, ?_⟩
  · intro i inside
    by_cases zero : i = 0
    · subst i; simpa only [restoreLocals, ↓reduceIte] using leaf
    · have one : i = 1 := by omega
      subst i; simpa only [slot, restoreLocals, ↓reduceIte, Nat.one_ne_zero] using parent
  · exact first.2.2.2.2.2.trans (nodesWrite.trans countWrites)

/-- The actual unary source call derives its parent node after executing
    its operand. The final natural extractor supplies that recursive proof. -/
theorem actualBuildNegativeWith (storage : ScalarStorage workspace before slots) (available : 2 ≤ slots)
    (node : NativeNode input.tree before.heap index) (production : node.production = 157) (count : node.count = 2)
    (child : NativeChild input.tree before.heap (node.first + 1)) (kind : child.kind = .StateChild)
    (operand depth : Nat) (payload : child.payload = Int.ofNat operand)
    (positive : 1 < depth) (depthFits : depth < 2 ^ 31)
    (formed : before.CellsWellFormed) (noViews : before.i32ArrayViews = [])
    (recursive : ∀ {state : State}, state.heap = before.heap → state.CellsWellFormed →
      state.i32ArrayViews = before.i32ArrayViews → ∃ after,
      RunsExpr extractedProgram state (buildCall input.tree storage.arena operand (depth - 1)) (.signed .i32 0) after ∧
        MemoryEffect (ProducedNodes storage 1 nodes) state after) :
    ∃ after, RunsExpr extractedProgram before (buildCall input.tree storage.arena index depth) (.signed .i32 1) after ∧
      MemoryEffect (ProducedNodes storage 2 (fun i => if i = 0 then nodes 0 else negateNode)) before after := by
  apply actualBuildWith input.tree storage.arena index depth (by omega) depthFits formed
  intro state same cells views contextFound indexFound depthFound arenaFound nodesFound
  have startingViews := views
  have notLiteral {current : State} (formed : current.CellsWellFormed) :=
    actualNonLiteral node.production (by omega) (by omega) formed
  have unary {current : State} (formed : current.CellsWellFormed) : ∃ after,
      RunsExpr extractedProgram current
        (.call Extracted.«verified::surface_expr».Functions.«unary_production».core.id
          [.value (.signed .i32 node.production)]) (.boolean true) after ∧ PureFrame current after := by
    simpa only [production] using actualNegateProduction formed
  have descend {current : State} (heap : current.heap = state.heap) (formed : current.CellsWellFormed)
      (views : current.i32ArrayViews = state.i32ArrayViews)
      (contextFound : current.local? (buildSource.argumentId 0) = some (buildContext input.tree storage.arena.value))
      (indexFound : current.local? (buildSource.argumentId 1) = some (.signed .i32 index))
      (depthFound : current.local? (buildSource.argumentId 2) = some (.signed .i32 depth))
      (arenaFound : current.local? (buildSource.bindingId 0) = some storage.arena.value)
      (productionFound : current.local? (buildSource.bindingId 49) = some (.signed .i32 node.production)) :
      ∃ after, RunsStmt extractedProgram current (buildSource.bindingStatement 60)
        (.returned (some (.signed .i32 1))) after ∧
        MemoryEffect (ProducedNodes storage 2 (fun i => if i = 0 then nodes 0 else negateNode)) current after := by
    have reads : HeapReads before.heap current.heap := by rw [heap, same]; exact HeapReads.refl _
    exact actualNegateTail (before := current) (storage.afterReads reads) available (node.afterReads reads) count (child.afterReads reads) kind
        operand depth payload positive depthFits formed ((views.trans startingViews).trans noViews)
        contextFound indexFound depthFound arenaFound (by simpa only [production] using productionFound)
        (fun nextHeap nextFormed nextViews => recursive ((nextHeap.trans heap).trans same) nextFormed
          ((nextViews.trans views).trans startingViews))
  core_facts [node]
  core_effect (by assumption)

#print axioms actualBuildNegativeWith
#print axioms negateNodeCodec

private def binaryEndValue (production ending : Int) : Int :=
  if production = 105 ∨ production = 160 then -1 else ending

/-- An empty native grammar tail returns on the first actual loop iteration.
    The fuel decrement targets the fresh local, not a caller cell. -/
private theorem actualBinaryStop (ending : NativeNode tree before.heap tail)
    (production : Int) (empty : emptyBinary production ending.production)
    (arena : Arena) (left depth : Nat) (positive : 0 < depth) (fits : depth < 2 ^ 31)
    (formed : before.CellsWellFormed)
    (contextFound : before.local? (buildSource.argumentId 0) = some (buildContext tree arena.value))
    (depthFound : before.local? (buildSource.argumentId 2) = some (.signed .i32 depth))
    (productionFound : before.local? (buildSource.bindingId 49) = some (.signed .i32 production))
    (endFound : before.local? (buildSource.bindingId 61) = some (.signed .i32 (binaryEndValue production ending.production)))
    (leftFound : before.local? (buildSource.bindingId 62) = some (.signed .i32 left))
    (tailFound : before.local? (buildSource.bindingId 63) = some (.signed .i32 tail)) :
    ∃ after, RunsStmt extractedProgram before (buildSource.bindingStatement 64)
      (.returned (some (.signed .i32 left))) after ∧ PureFrame before after := by
  have closing : 0 < ending.production ∧
      (production = 160 → ending.production = 164) ∧
      (production = 105 → ending.production = 117) := by
    simp only [emptyBinary, List.mem_cons, List.not_mem_nil, or_false, Prod.mk.injEq] at empty
    rcases empty with h | h | h | h | h | h | h | h | h | h | h | h <;>
      rcases h with ⟨first, last⟩ <;> omega
  let indexed := before.bindLocal 5072 (.signed .i32 depth)
  obtain ⟨assigned, assignment, assignedLocal, effect⟩ := RunsExpr.assignI32
    (program := extractedProgram) (before := indexed) (op := .subtract)
    (operand := 1) (replacement := (depth : Int) - 1)
    (State.bindLocal_cellId before 5072 _)
    (formed.bindLocal_local _ _) (RunsExpr.ofStable StableExpr.value rfl) (by
      simpa only [evalAssignValue, assignOpBinary?] using eval_i32_predecessor extractedProgram.target depth fits)
  have frame : CallerFrame before assigned :=
    ((CallerFrame.refl formed).bindLocal _ _).assignLocalFresh _ before.nextCell _
      (State.bindLocal_cellId before _ _) (Nat.le_refl _) assignedLocal
  have counted : CountedLocal before assigned (buildSource.bindingId 64) ((depth : Int) - 1) :=
    ⟨frame.cells, effect.locals, assignLocal_finds_assigned _ _ _ (State.bindLocal_cellId before _ _) assignedLocal⟩
  have operation {state : State} (heap : state.heap = assigned.heap) (cells : state.CellsWellFormed) :=
    actualExpressionProduction ending arena.value (heap.trans frame.heap) cells
  change ∀ {state : State}, state.heap = assigned.heap → state.CellsWellFormed → ∃ after,
    RunsExpr extractedProgram state
      (.call 1858 [.value (buildContext tree arena.value), .value (.signed .i32 tail)])
      (.signed .i32 ending.production) after ∧ PureFrame state after at operation
  change before.local? 2462 = some (buildContext tree arena.value) at contextFound
  change before.local? 2470 = some (.signed .i32 depth) at depthFound
  change before.local? 4306 = some (.signed .i32 production) at productionFound
  change before.local? 4977 = some (.signed .i32 (binaryEndValue production ending.production)) at endFound
  change before.local? 5020 = some (.signed .i32 left) at leftFound
  change before.local? 5058 = some (.signed .i32 tail) at tailFound
  change CountedLocal before assigned 5072 ((depth : Int) - 1) at counted
  core_facts [frame, counted, ending, closing]
  obtain ⟨completed, operationRun, pure⟩ : ∃ completed,
      RunsStmt extractedProgram assigned (buildSource.bindingStatement 65)
        (.returned (some (.signed .i32 left))) completed ∧ PureFrame assigned completed := by
    dsimp only [binaryEndValue] at endFound
    by_cases isPostfix : production = 160
    · core_pure
    · by_cases assignment : production = 105
      · core_pure
      · core_pure
  have iteration : RunsStmt extractedProgram indexed (buildSource.whileLoop 4).2
      (.returned (some (.signed .i32 left))) completed := by
    core_stmt_forward
  have loop : RunsStmt extractedProgram indexed
      (.whileLoop (buildSource.whileLoop 4).1 (buildSource.whileLoop 4).2)
      (.returned (some (.signed .i32 left))) completed :=
    RunsStmt.whileReturn (by core_run) iteration
  have body : RunsStmt extractedProgram indexed
      (match buildSource.bindingStatement 64 with | .letLocal _ _ _ rest => rest | _ => .skip)
      (.returned (some (.signed .i32 left))) completed := by
    core_stmt_forward
  exact ⟨restoreLocals before completed, RunsStmt.letLocal (by core_run) body,
    (frame.transPure pure).restoreLocals⟩

@[core_pure_rule] private theorem actualEmptyBinaryEnd (production ending : Int)
    (empty : emptyBinary production ending) (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before
      (.call Extracted.«verified::surface_expr».Functions.«binary_end».core.id [.value (.signed .i32 production)])
      (.signed .i32 (binaryEndValue production ending)) after ∧ PureFrame before after := by
  simp only [emptyBinary, List.mem_cons, List.not_mem_nil, or_false, Prod.mk.injEq] at empty
  rcases empty with h | h | h | h | h | h | h | h | h | h | h | h
  all_goals
    rcases h with ⟨rfl, rfl⟩
    dsimp only [binaryEndValue]
    core_call_pure Extracted.«verified::surface_expr».Functions.«binary_end».core as callee
    core_pure

@[core_pure_rule] private theorem actualNotUnary (production : Int)
    (notPos : production ≠ 156) (notNeg : production ≠ 157) (notNot : production ≠ 158)
    (formed : before.CellsWellFormed) : ∃ after, RunsExpr extractedProgram before
      (.call Extracted.«verified::surface_expr».Functions.«unary_production».core.id [.value (.signed .i32 production)])
      (.boolean false) after ∧ PureFrame before after := by
  core_call_pure Extracted.«verified::surface_expr».Functions.«unary_production».core as callee
  core_pure

private theorem actualBinaryTail (storage : ScalarStorage workspace before slots)
    (node : NativeNode input.tree before.heap index) (count : node.count = 2)
    (left : NativeChild input.tree before.heap node.first) (leftKind : left.kind = .StateChild)
    (operand : Nat) (leftPayload : left.payload = Int.ofNat operand)
    (tail : NativeChild input.tree before.heap (node.first + 1)) (tailKind : tail.kind = .StateChild)
    (tailIndex : Nat) (tailPayload : tail.payload = Int.ofNat tailIndex)
    (ending : NativeNode input.tree before.heap tailIndex) (empty : emptyBinary node.production ending.production)
    (apart : InputApart input storage.writes) (depth root producedCount : Nat)
    (positive : 1 < depth) (fits : depth < 2 ^ 31) (formed : before.CellsWellFormed)
    (contextFound : before.local? (buildSource.argumentId 0) = some (buildContext input.tree storage.arena.value))
    (indexFound : before.local? (buildSource.argumentId 1) = some (.signed .i32 index))
    (depthFound : before.local? (buildSource.argumentId 2) = some (.signed .i32 depth))
    (productionFound : before.local? (buildSource.bindingId 49) = some (.signed .i32 node.production))
    (endFound : before.local? (buildSource.bindingId 61) =
      some (.signed .i32 (binaryEndValue node.production ending.production)))
    (recursive : ∀ {state : State}, state.heap = before.heap → state.CellsWellFormed →
      state.i32ArrayViews = before.i32ArrayViews → ∃ after,
      RunsExpr extractedProgram state (buildCall input.tree storage.arena operand (depth - 1)) (.signed .i32 root) after ∧
        MemoryEffect (ProducedNodes storage producedCount nodes) state after) :
    ∃ after, RunsStmt extractedProgram before (buildSource.bindingStatement 62)
      (.returned (some (.signed .i32 root))) after ∧ MemoryEffect (ProducedNodes storage producedCount nodes) before after := by
  have subtract := eval_i32_subNat extractedProgram.target depth 1 (by omega) fits
  have leftQuery {state : State} (heap : state.heap = before.heap) (cells : state.CellsWellFormed) :=
    actualExpressionChild node 0 (by rw [count]; decide) left leftKind storage.arena.value heap cells
  simp only [leftPayload, Int.ofNat_eq_natCast, Int.natCast_zero] at leftQuery
  apply RunsStmt.letMemoryEffect
  · apply RunsExpr.callFramedEffectArguments (MemoryEffect.scopeStable _)
    · core_pure_arguments
    · intro ready pure
      exact recursive pure.heap pure.afterFormed pure.views
  · intro produced producerRun effect
    let bound := produced.bindLocal (buildSource.bindingId 62) (.signed .i32 root)
    have boundFormed : bound.CellsWellFormed := (effect.1.after_cellsWellFormed formed).bindLocal _ _
    have writes := effect.2.2.2.2.2
    let reachedNode : NativeNode input.tree produced.heap index :=
      { node with snapshot := node.snapshot.afterFootprint writes (apart.nodes _ _ node.inside node.location) }
    let reachedTail : NativeChild input.tree produced.heap (node.first + 1) :=
      { tail with snapshot := tail.snapshot.afterFootprint writes (apart.children _ _ tail.inside tail.location) }
    let reachedEnd : NativeNode input.tree produced.heap tailIndex :=
      { ending with snapshot := ending.snapshot.afterFootprint writes (apart.nodes _ _ ending.inside ending.location) }
    have tailQuery {state : State} (heap : state.heap = produced.heap) (cells : state.CellsWellFormed) :
        ∃ after, RunsExpr extractedProgram state
          (.call Extracted.«verified::surface_expr».Functions.«child».core.id
            [.value (buildContext input.tree storage.arena.value), .value (.signed .i32 index), .value (.signed .i32 1)])
          (.signed .i32 tailIndex) after ∧ PureFrame state after := by
      simpa only [reachedTail, tailPayload, Int.ofNat_eq_natCast, Int.natCast_one] using
        actualExpressionChild reachedNode 1 (by rw [count]; decide) reachedTail tailKind storage.arena.value heap cells
    core_facts [effect]
    apply RunsStmt.guardPureFalse
    · core_run
    · apply RunsStmt.letFramedPure
      · apply RunsExpr.callPureArguments
        · core_arguments
        · exact tailQuery rfl boundFormed
      · intro ready pure
        core_state current
        have same : current.heap = produced.heap := pure.heap
        exact actualBinaryStop (before := current)
          ({ reachedEnd with snapshot := by simpa only [same] using reachedEnd.snapshot })
          node.production empty storage.arena root depth (by omega) fits (by core_formed)
          (by core_local) (by core_local) (by core_local) (by core_local) (by core_local) (by core_local)

/-- Empty binary/parser suffixes execute their real first iteration and keep
    the operand's arena result. The final source induction supplies the operand. -/
theorem actualBuildBinaryEndWith (storage : ScalarStorage workspace before slots)
    (node : NativeNode input.tree before.heap index) (count : node.count = 2)
    (left : NativeChild input.tree before.heap node.first) (leftKind : left.kind = .StateChild)
    (operand : Nat) (leftPayload : left.payload = Int.ofNat operand)
    (tail : NativeChild input.tree before.heap (node.first + 1)) (tailKind : tail.kind = .StateChild)
    (tailIndex : Nat) (tailPayload : tail.payload = Int.ofNat tailIndex)
    (ending : NativeNode input.tree before.heap tailIndex) (empty : emptyBinary node.production ending.production)
    (apart : InputApart input storage.writes) (depth root producedCount : Nat)
    (positive : 1 < depth) (fits : depth < 2 ^ 31) (formed : before.CellsWellFormed)
    (recursive : ∀ {state : State}, state.heap = before.heap → state.CellsWellFormed →
      state.i32ArrayViews = before.i32ArrayViews → ∃ after,
      RunsExpr extractedProgram state (buildCall input.tree storage.arena operand (depth - 1)) (.signed .i32 root) after ∧
        MemoryEffect (ProducedNodes storage producedCount nodes) state after) :
    ∃ after, RunsExpr extractedProgram before (buildCall input.tree storage.arena index depth) (.signed .i32 root) after ∧
      MemoryEffect (ProducedNodes storage producedCount nodes) before after := by
  have productions : 0 ≤ node.production ∧ node.production < 175 ∧
      node.production ≠ 156 ∧ node.production ≠ 157 ∧ node.production ≠ 158 ∧
      node.production ≠ 104 ∧ node.production ≠ 159 ∧ node.production ≠ 172 := by
    simp only [emptyBinary, List.mem_cons, List.not_mem_nil, or_false, Prod.mk.injEq] at empty
    rcases empty with h | h | h | h | h | h | h | h | h | h | h | h <;>
      rcases h with ⟨h, _⟩ <;> omega
  apply actualBuildWith input.tree storage.arena index depth (by omega) fits formed
  intro state same cells views contextFound indexFound depthFound arenaFound nodesFound
  have startingViews := views
  have notLiteral {current : State} (cells : current.CellsWellFormed) :=
    actualNonLiteral node.production productions.1 productions.2.1 cells
  have notUnary {current : State} (cells : current.CellsWellFormed) :=
    actualNotUnary node.production productions.2.2.1 productions.2.2.2.1 productions.2.2.2.2.1 cells
  have endQuery {current : State} (cells : current.CellsWellFormed) := actualEmptyBinaryEnd node.production ending.production empty cells
  change ∀ {current : State}, current.CellsWellFormed → ∃ after,
    RunsExpr extractedProgram current (.call 1865 [.value (.signed .i32 node.production)])
      (.boolean false) after ∧ PureFrame current after at notLiteral
  change ∀ {current : State}, current.CellsWellFormed → ∃ after,
    RunsExpr extractedProgram current (.call 1866 [.value (.signed .i32 node.production)])
      (.boolean false) after ∧ PureFrame current after at notUnary
  change ∀ {current : State}, current.CellsWellFormed → ∃ after,
    RunsExpr extractedProgram current (.call 1867 [.value (.signed .i32 node.production)])
      (.signed .i32 (binaryEndValue node.production ending.production)) after ∧ PureFrame current after at endQuery
  change state.local? 2462 = some (buildContext input.tree storage.arena.value) at contextFound
  change state.local? 2466 = some (.signed .i32 index) at indexFound
  change state.local? 2470 = some (.signed .i32 depth) at depthFound
  change state.local? 2482 = some storage.arena.value at arenaFound
  change state.local? 2491 = some (.rawSlice expressionNodeType storage.arena.nodes storage.arena.capacity) at nodesFound
  have descend {current : State} (heap : current.heap = state.heap) (cells : current.CellsWellFormed)
      (views : current.i32ArrayViews = state.i32ArrayViews)
      (contextFound : current.local? 2462 = some (buildContext input.tree storage.arena.value))
      (indexFound : current.local? 2466 = some (.signed .i32 index))
      (depthFound : current.local? 2470 = some (.signed .i32 depth))
      (productionFound : current.local? 4306 = some (.signed .i32 node.production))
      (endFound : current.local? 4977 =
        some (.signed .i32 (binaryEndValue node.production ending.production))) :
      ∃ after, RunsStmt extractedProgram current (buildSource.bindingStatement 62)
        (.returned (some (.signed .i32 root))) after ∧
        MemoryEffect (ProducedNodes storage producedCount nodes) current after := by
    have reads : HeapReads before.heap current.heap := by rw [heap, same]; exact HeapReads.refl _
    exact actualBinaryTail (before := current) (storage.afterReads reads) (node.afterReads reads) count (left.afterReads reads) leftKind operand leftPayload
        (tail.afterReads reads) tailKind tailIndex tailPayload (ending.afterReads reads) empty apart depth root producedCount
        positive fits cells contextFound indexFound depthFound productionFound endFound
        (fun nextHeap nextFormed nextViews => recursive ((nextHeap.trans heap).trans same) nextFormed
          ((nextViews.trans views).trans startingViews))
  dsimp only [binaryEndValue] at endQuery descend
  have binaryRanges : 105 ≤ node.production ∧ node.production ≤ 160 ∧ 0 < ending.production := by
    simp only [emptyBinary, List.mem_cons, List.not_mem_nil, or_false, Prod.mk.injEq] at empty
    rcases empty with h | h | h | h | h | h | h | h | h | h | h | h <;>
      rcases h with ⟨first, last⟩ <;> omega
  have productionLower := binaryRanges.1
  have productionUpper := binaryRanges.2.1
  have endingPositive := binaryRanges.2.2
  core_facts [node, productions]
  apply RunsStmt.letFramedEffect (MemoryEffect.scopeStable _)
  · core_pure_expr
  · intro reached productionFrame
    repeat (apply RunsStmt.guardEffectFalse (MemoryEffect.scopeStable _); core_pure_guard; intro guarded guardFrame)
    apply RunsStmt.letFramedEffect (MemoryEffect.scopeStable _)
    · core_pure_expr
    · intro ended endFrame
      apply RunsStmt.guardEffectFalse (MemoryEffect.scopeStable _)
      · core_pure_guard
      · intro guarded guardFrame
        core_effect_contract

#print axioms actualBuildBinaryEndWith

/-- The finite natural domain uses the existing surface expression directly.
    These are its actual arena payloads, not a second syntax or typing tree. -/
def scalarCount : Surface.Expr → Nat
  | .unary .negative (.literal (.integer _)) => 2
  | _ => 1

def scalarRoot (expression : Surface.Expr) : Nat := scalarCount expression - 1

def scalarNodes (expression : Surface.Expr) (token index : Nat) : Value :=
  match expression with
  | .literal (.boolean flag) => literalNode (.boolean flag) (Int32.ofNat token)
  | .literal (.integer _) => literalNode .integer (Int32.ofNat token)
  | .unary .negative (.literal (.integer _)) =>
      if index = 0 then literalNode .integer (Int32.ofNat token) else negateNode
  | _ => .unit

def ScalarToken (input : Inputs) (state : State) (expression : Surface.Expr) (token : Nat) : Prop :=
  match expression with
  | .literal (.boolean flag) =>
      Nonempty (OriginalToken input state token (if flag then "true" else "false") (booleanToken flag))
  | .literal (.integer text) | .unary .negative (.literal (.integer text)) =>
      Nonempty (OriginalToken input state token text integerToken)
  | _ => False

/-- One induction over original native topology discharges every recursive
    build continuation. The token is selected from original input before any
    runtime state is quantified, so unary/wrapper calls share the same payload. -/
theorem OriginalScalar.actualBuild {origin : State}
    (original : OriginalScalar input origin index expression route) :
    ∃ token, ScalarToken input origin expression token ∧
      ∀ {workspace : Workspace} {slots : Nat} (state : State)
        (storage : ScalarStorage workspace state slots)
        (written : HeapWritesOn origin.heap state.heap storage.writes)
        (used : scalarCount expression ≤ slots)
        (zero : readNativeValue 64 extractedProgram state.heap (.scalar (.signed .i32)) storage.arena.count =
          .ok (.signed .i32 0))
        (apart : InputApart input storage.writes) (depth : Nat)
        (enough : route.length < depth) (fits : depth < 2 ^ 31)
        (formed : state.CellsWellFormed)
        (noViews : state.i32ArrayViews = []),
        ∃ after, RunsExpr extractedProgram state (buildCall input.tree storage.arena index depth)
          (.signed .i32 (scalarRoot expression)) after ∧
          MemoryEffect (ProducedNodes storage (scalarCount expression) (scalarNodes expression token)) state after := by
  induction original with
  | @boolean index flag token node production count child kind payload spelling =>
      refine ⟨token, ⟨spelling⟩, ?_⟩
      intro workspace slots state storage written used zero apart depth enough fits formed noViews
      let reachedNode : NativeNode input.tree state.heap index :=
        { node with snapshot := node.snapshot.afterFootprint written (apart.nodes _ _ node.inside node.location) }
      let reachedChild : NativeChild input.tree state.heap node.first :=
        { child with snapshot := child.snapshot.afterFootprint written (apart.children _ _ child.inside child.location) }
      have actualProduction : node.production = literalProduction (.boolean flag) := by
        cases flag <;> exact production
      change ∃ after, RunsExpr extractedProgram state (buildCall input.tree storage.arena index depth)
        (.signed .i32 0) after ∧ MemoryEffect
          (ProducedNodes storage 1 (fun _ => literalNode (.boolean flag) (Int32.ofNat token))) state after
      exact actualLiteralStored storage reachedNode (.boolean flag) actualProduction count
          reachedChild kind token payload (by have := spelling.inside; have := spelling.tokensFit; omega)
          zero depth (by simp only [List.length_singleton] at enough; omega) fits formed written.unique noViews
  | @integer index token text node production count child kind payload spelling =>
      refine ⟨token, ⟨spelling⟩, ?_⟩
      intro workspace slots state storage written used zero apart depth enough fits formed noViews
      let reachedNode : NativeNode input.tree state.heap index :=
        { node with snapshot := node.snapshot.afterFootprint written (apart.nodes _ _ node.inside node.location) }
      let reachedChild : NativeChild input.tree state.heap node.first :=
        { child with snapshot := child.snapshot.afterFootprint written (apart.children _ _ child.inside child.location) }
      change ∃ after, RunsExpr extractedProgram state (buildCall input.tree storage.arena index depth)
        (.signed .i32 0) after ∧ MemoryEffect
          (ProducedNodes storage 1 (fun _ => literalNode .integer (Int32.ofNat token))) state after
      exact actualLiteralStored storage reachedNode .integer production count
          reachedChild kind token payload (by have := spelling.inside; have := spelling.tokensFit; omega)
          zero depth (by simp only [List.length_singleton] at enough; omega) fits formed written.unique noViews
  | @negative index operand minusToken text route node production count child kind payload minus minusKind minusPayload minusSpelling operandSyntax ih =>
      obtain ⟨token, spelling, build⟩ := ih
      refine ⟨token, spelling, ?_⟩
      intro workspace slots state storage written used zero apart depth enough fits formed noViews
      let reachedNode : NativeNode input.tree state.heap index :=
        { node with snapshot := node.snapshot.afterFootprint written (apart.nodes _ _ node.inside node.location) }
      let reachedChild : NativeChild input.tree state.heap (node.first + 1) :=
        { child with snapshot := child.snapshot.afterFootprint written (apart.children _ _ child.inside child.location) }
      simp only [List.length_cons] at enough
      change ∃ after, RunsExpr extractedProgram state (buildCall input.tree storage.arena index depth)
        (.signed .i32 1) after ∧ MemoryEffect
          (ProducedNodes storage 2 (fun i => if i = 0 then literalNode .integer (Int32.ofNat token) else negateNode)) state after
      apply actualBuildNegativeWith (nodes := fun _ => literalNode .integer (Int32.ofNat token)) storage used reachedNode production count
        reachedChild kind operand depth payload (by omega) fits formed noViews
      intro current heap cells views
      have currentReads : HeapReads state.heap current.heap := by rw [heap]; exact HeapReads.refl _
      have currentWritten : HeapWritesOn origin.heap current.heap storage.writes := by rw [heap]; exact written
      have currentZero : readNativeValue 64 extractedProgram current.heap (.scalar (.signed .i32))
          storage.arena.count = .ok (.signed .i32 0) := by rw [heap]; exact zero
      have result := build current (storage.afterReads currentReads) currentWritten
        (by change 1 ≤ slots; have := storage.positive; omega) currentZero apart (depth - 1) (by omega) (by omega) cells
        (views.trans noViews)
      exact result
  | @wrapper index operand expression route node production slot selected inside child kind payload operandSyntax ih =>
      obtain ⟨token, spelling, build⟩ := ih
      refine ⟨token, spelling, ?_⟩
      intro workspace slots state storage written used zero apart depth enough fits formed noViews
      let reachedNode : NativeNode input.tree state.heap index :=
        { node with snapshot := node.snapshot.afterFootprint written (apart.nodes _ _ node.inside node.location) }
      let reachedChild : NativeChild input.tree state.heap (node.first + slot) :=
        { child with snapshot := child.snapshot.afterFootprint written (apart.children _ _ child.inside child.location) }
      simp only [List.length_cons] at enough
      apply actualBuildWrapper reachedNode storage.arena production slot operand depth selected inside
        reachedChild kind payload fits (by omega) formed
      intro current heap cells views
      have currentReads : HeapReads state.heap current.heap := by rw [heap]; exact HeapReads.refl _
      have currentWritten : HeapWritesOn origin.heap current.heap storage.writes := by rw [heap]; exact written
      have currentZero : readNativeValue 64 extractedProgram current.heap (.scalar (.signed .i32))
          storage.arena.count = .ok (.signed .i32 0) := by rw [heap]; exact zero
      exact build current (storage.afterReads currentReads) currentWritten used currentZero apart
        (depth - 1) (by omega) (by omega) cells (views.trans noViews)
  | @binaryEnd index operand tailIndex expression route node count left leftKind leftPayload tail tailKind tailPayload ending production operandSyntax ih =>
      obtain ⟨token, spelling, build⟩ := ih
      refine ⟨token, spelling, ?_⟩
      intro workspace slots state storage written used zero apart depth enough fits formed noViews
      let reachedNode : NativeNode input.tree state.heap index :=
        { node with snapshot := node.snapshot.afterFootprint written (apart.nodes _ _ node.inside node.location) }
      let reachedLeft : NativeChild input.tree state.heap node.first :=
        { left with snapshot := left.snapshot.afterFootprint written (apart.children _ _ left.inside left.location) }
      let reachedTail : NativeChild input.tree state.heap (node.first + 1) :=
        { tail with snapshot := tail.snapshot.afterFootprint written (apart.children _ _ tail.inside tail.location) }
      let reachedEnd : NativeNode input.tree state.heap tailIndex :=
        { ending with snapshot := ending.snapshot.afterFootprint written (apart.nodes _ _ ending.inside ending.location) }
      simp only [List.length_cons] at enough
      apply actualBuildBinaryEndWith storage reachedNode count reachedLeft leftKind operand leftPayload
        reachedTail tailKind tailIndex tailPayload reachedEnd production apart
        depth (scalarRoot expression) (scalarCount expression) (by omega) fits formed
      intro current heap cells views
      have currentReads : HeapReads state.heap current.heap := by rw [heap]; exact HeapReads.refl _
      have currentWritten : HeapWritesOn origin.heap current.heap storage.writes := by rw [heap]; exact written
      have currentZero : readNativeValue 64 extractedProgram current.heap (.scalar (.signed .i32))
          storage.arena.count = .ok (.signed .i32 0) := by rw [heap]; exact zero
      exact build current (storage.afterReads currentReads) currentWritten used currentZero apart
        (depth - 1) (by omega) (by omega) cells (views.trans noViews)

#print axioms OriginalScalar.actualBuild

/-- The actual1871 reset feeds the closed source induction. Its token
    witness remains an original-input fact, not a post-decoder assumption. -/
theorem OriginalScalar.actualExtract
    (original : OriginalScalar input before index expression route)
    (storage : ScalarStorage workspace before slots) (used : scalarCount expression ≤ slots)
    (apart : InputApart input storage.writes) (depth : Nat) (enough : route.length < depth)
    (fits : depth < 2 ^ 31) (formed : before.CellsWellFormed)
    (unique : HeapBlockBasesUnique before.heap) (noViews : before.i32ArrayViews = []) :
    ∃ token, ScalarToken input before expression token ∧
      ∃ after, RunsExpr extractedProgram before (extractCall input.tree storage.arena index depth)
        (.signed .i32 (scalarRoot expression)) after ∧
        MemoryEffect (ProducedNodes storage (scalarCount expression) (scalarNodes expression token)) before after := by
  obtain ⟨token, sourceToken, build⟩ := original.actualBuild
  refine ⟨token, sourceToken, ?_⟩
  apply actualExtractWith input.tree storage index depth (scalarCount expression) (scalarRoot expression)
    (scalarNodes expression token) ?_ formed unique noViews
  intro state written zero cells views
  exact build state (storage.afterFootprint written) written used zero apart depth enough fits cells (views.trans noViews)

#print axioms OriginalScalar.actualExtract

end IRBodyProductionScalar
