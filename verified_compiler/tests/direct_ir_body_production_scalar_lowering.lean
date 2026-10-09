import verified_compiler.tests.direct_ir_body_production_scalar_extract_reset
import verified_compiler.tests.direct_ir_body_production_scalar_cache
import verified_compiler.tests.direct_ir_type_cache_reset

namespace IRBodyProductionScalar

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics IRBodyProductionInputs

variable {before after : State}

private def lowerSource := Extracted.«lowering::body_expression».Functions.«extract_expression».core
def lowerExtractCall (input : Inputs) (workspace : Workspace) (locals : Value) (root depth : Nat) : Expr :=
  .call lowerSource.id ([bodyContext input workspace locals, .signed .i32 root, .signed .i32 depth].map Expr.value)

def PreparedNodes (storage : ScalarStorage workspace initial slots) (count : Nat) (nodes : Nat → Value)
    (before after : Heap) : Prop :=
  ProducedNodes storage count nodes before after ∧
  ∀ index, index < count → readRawSliceIndex extractedProgram { initial with heap := after }
    (.scalar (.signed .i32)) storage.codes storage.arena.capacity index = .ok (.signed .i32 (-1))

theorem ProducedNodes.nodeRead (storage : ScalarStorage workspace initial slots)
    (produced : ProducedNodes storage count nodes before.heap after.heap)
    (used : count ≤ slots) (index : Nat) (inside : index < count) :
    readRawSliceIndex extractedProgram after expressionNodeType storage.arena.nodes storage.arena.capacity index =
      .ok (nodes index) := by
  have bound := Nat.lt_of_lt_of_le inside (Nat.le_trans used storage.bound)
  simp only [readRawSliceIndex, Nat.not_le_of_lt bound, ↓reduceIte]
  rw [storage.locations index (Nat.lt_of_lt_of_le inside used)]
  change readNativeValue 64 extractedProgram after.heap expressionNodeType (storage.bases index) = .ok (nodes index)
  exact (produced.1 index inside).read

/-- One actual1249 wrapper for the arena produced by1871. Its extraction
    continuation is internal and discharged by the closed natural extractor. -/
theorem actualExtractExpressionWith (input : Inputs) (workspace : Workspace) (locals : Value)
    (surface depth : Nat) (storage : ScalarStorage workspace before slots)
    (count root : Nat) (used : count ≤ slots) (inside : root < count)
    (extract : ∀ {state : State}, state.heap = before.heap → state.CellsWellFormed →
      state.i32ArrayViews = before.i32ArrayViews → ∃ after,
      RunsExpr extractedProgram state (extractCall input.tree storage.arena surface depth)
        (.signed .i32 root) after ∧ MemoryEffect (ProducedNodes storage count nodes) state after)
    (formed : before.CellsWellFormed) (noViews : before.i32ArrayViews = []) :
    ∃ after, RunsExpr extractedProgram before (lowerExtractCall input workspace locals surface depth)
      (.signed .i32 root) after ∧ MemoryEffect (PreparedNodes storage count nodes) before after := by
  have capacity : workspace.expressionCapacity = storage.arena.capacity := by
    have selected := congrArg (fun value : Value => match value with
      | .structure _ fields => fields[2]?.getD Value.unit | _ => Value.unit) storage.arenaValue
    change Value.signed .i32 workspace.expressionCapacity = Value.signed .i32 storage.arena.capacity at selected
    simpa only [Value.signed.injEq, true_and, Int.natCast_inj] using selected
  core_facts [storage, storage.arena]
  core_call_framed (RunsExpr.callEffect (MemoryEffect.scopeStable _)) lowerSource as callee
  apply RunsStmt.letEffect (MemoryEffect.scopeStable _) (value := expressionInput input.tree surface depth)
  · core_run
  · core_formed
  · core_state ready
    have same : ready.heap = before.heap := rfl
    have readyFormed : ready.CellsWellFormed := by core_formed
    obtain ⟨produced, extracted, producedEffect⟩ := extract same readyFormed rfl
    change RunsExpr extractedProgram ready
      (.call Extracted.«verified::surface_expr».Functions.«extract».core.id
        [.value (expressionInput input.tree surface depth), .value storage.arena.value]) (.signed .i32 root) produced at extracted
    have initial : RunsExpr extractedProgram ready (lowerSource.bindingInitializer 1) (.signed .i32 root) produced := by
      rw [← storage.arenaValue] at extracted
      exact RunsExpr.callArguments (by core_arguments) extracted
    have producedFormed : produced.CellsWellFormed := producedEffect.1.after_cellsWellFormed readyFormed
    core_facts [producedEffect]
    rcases producedEffect.2.2.2 with ⟨native, storedCount, producedWrites⟩
    let rooted := produced.bindLocal (lowerSource.bindingId 1) (.signed .i32 root)
    have rootedFormed : rooted.CellsWellFormed := producedFormed.bindLocal _ _
    have rootFound : rooted.local? (lowerSource.bindingId 1) = some (.signed .i32 root) :=
      producedFormed.bindLocal_local _ _
    have nodeCount {state : State} (heap : state.heap = produced.heap) (cells : state.CellsWellFormed) :=
      actualNodeCount storage.arena (by rw [heap]; exact storedCount.read) cells
    have clearTail {state : State} (heap : state.heap = produced.heap) (cells : state.CellsWellFormed)
        (views : state.i32ArrayViews = rooted.i32ArrayViews)
        (rootFound : state.local? (lowerSource.bindingId 1) = some (.signed .i32 root))
        (contextFound : state.local? (lowerSource.argumentId 0) = some (bodyContext input workspace locals))
        (countFound : state.local? (lowerSource.bindingId 2) = some (.signed .i32 count)) :
        ∃ completed, RunsStmt extractedProgram state
          (match lowerSource.bindingStatement 2 with
            | .letLocal _ _ _ rest =>
                match rest with
                | .sequence _ tail => tail
                | _ => .skip
            | _ => .skip)
          (.returned (some (.signed .i32 root))) completed ∧
          MemoryEffect (PreparedNodes storage count nodes) state completed := by
      let clearing : IRTypeCacheResetProof.Input state := {
        address := storage.codes, count, capacity := storage.arena.capacity
        inside := Nat.le_trans used storage.bound
        fits := by have := storage.arena.fits; omega
        room := by
          rw [heap]
          exact (producedWrites.readable _ _ (by simpa only [same] using storage.codesRoom)).subrange
            (start := 0) (length := count * 4) (by omega) }
      obtain ⟨completed, clearRun, effect, cleared⟩ := IRTypeCacheResetProof.actualReset clearing cells
        (by rw [heap]; exact producedWrites.unique)
        (views.trans (producedEffect.2.2.1.trans noViews))
      change RunsExpr extractedProgram state
        (.call Extracted.«lowering::body_expression».Functions.«clear_expression_kinds».core.id
          [.value (.rawSlice (.scalar (.signed .i32)) storage.codes storage.arena.capacity),
            .value (.signed .i32 count)]) .unit completed at clearRun
      have rootAfter : completed.local? (lowerSource.bindingId 1) = some (.signed .i32 root) :=
        effect.1.localFound (clearRun.choose_spec.2) _ _ rootFound
      have localClear : RunsExpr extractedProgram state (lowerSource.effectExpression 0) .unit completed := by
        rw [← storage.codesValue] at clearRun
        exact RunsExpr.callArguments (by core_arguments) clearRun
      have clearWrite : HeapRegionWrite state.heap completed.heap storage.codes (count * 4) := effect.2.2.2
      have body : RunsStmt extractedProgram state
          (match lowerSource.bindingStatement 2 with
            | .letLocal _ _ _ rest =>
                match rest with
                | .sequence _ tail => tail
                | _ => .skip
            | _ => .skip)
          (.returned (some (.signed .i32 root))) completed := by
        exact RunsStmt.sequenceNext (RunsStmt.expression localClear)
          (RunsStmt.returnValue (RunsExpr.ofStable (StableExpr.local rootAfter) rfl))
      refine ⟨completed, body, effect.1, effect.2.1, effect.2.2.1, ?_, ?_⟩
      · refine ⟨?_, ?_, ?_⟩
        · intro index bound
          have current : NativeSnapshot 64 extractedProgram state.heap expressionNodeType
              (storage.bases index) (nodes index) 48 := by simpa only [heap] using native index bound
          exact current.afterWrite clearWrite
            (by have := storage.nodeCodes index (Nat.lt_of_lt_of_le bound used); omega)
        · have current : NativeSnapshot 64 extractedProgram state.heap (.scalar (.signed .i32))
              storage.arena.count (.signed .i32 count) 4 := by simpa only [heap] using storedCount
          exact current.afterWrite clearWrite (by have := storage.countCodes; omega)
        · apply clearWrite.footprint.weaken (larger := storage.writes)
          intro address range
          change storage.codes ≤ address ∧ address < storage.codes + count * 4 at range
          change (_ ∨ _ ∨ (storage.codes ≤ address ∧ address < storage.codes + slots * 4) ∨ _)
          exact Or.inr (Or.inr (Or.inl ⟨range.1,
            Nat.lt_of_lt_of_le range.2 (Nat.add_le_add_left (Nat.mul_le_mul_right 4 used) storage.codes)⟩))
      · intro index bound
        simpa only [IRTypeCacheResetProof.Cleared, readRawSliceIndex, clearing] using cleared index bound
    obtain ⟨completed, body, rest⟩ : ∃ completed, RunsStmt extractedProgram rooted
        (match lowerSource.bindingStatement 1 with | .letLocal _ _ _ rest => rest | _ => .skip)
        (.returned (some (.signed .i32 root))) completed ∧
        MemoryEffect (PreparedNodes storage count nodes) rooted completed := by
      apply RunsStmt.guardEffectFalse (MemoryEffect.scopeStable _)
      · core_pure_guard
      · intro guarded guardFrame
        apply RunsStmt.letFramedEffect (MemoryEffect.scopeStable _) (value := .signed .i32 count)
        · apply RunsExpr.callPureArguments
          · core_arguments
          · have countedRun := nodeCount guardFrame.heap (by core_formed)
            change ∃ counted, RunsExpr extractedProgram guarded
              (.call 1853 [.value storage.arena.value]) (.signed .i32 count) counted ∧ PureFrame guarded counted at countedRun
            rw [← storage.arenaValue] at countedRun
            exact countedRun
        · intro counted countFrame
          apply RunsStmt.guardEffectFalse (MemoryEffect.scopeStable _)
          · core_pure_guard
          · intro selected selectedFrame
            exact clearTail (selectedFrame.heap.trans (countFrame.heap.trans guardFrame.heap))
              (by core_formed) (selectedFrame.views.trans (countFrame.views.trans guardFrame.views))
              (by core_local) (by core_local) (by core_local)
    rcases rest.2.2.2 with ⟨⟨finalNodes, finalCount, restWrites⟩, finalCodes⟩
    refine ⟨restoreLocals produced completed, RunsStmt.letLocal initial body,
      (producedEffect.1.trans (FreshCellFrame.bindLocal produced _ _)).trans rest.1,
      rest.2.1.trans producedEffect.2.1, rest.2.2.1.trans producedEffect.2.2.1,
      ⟨finalNodes, finalCount, ?_⟩, finalCodes⟩
    exact producedWrites.trans restWrites

#print axioms actualExtractExpressionWith
#print axioms ProducedNodes.nodeRead

end IRBodyProductionScalar
