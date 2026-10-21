import verified_compiler.tests.direct_ir_body_production_scalar_recursive
import verified_compiler.tests.direct_ir_body_production_scalar_lowering
import verified_compiler.tests.direct_ir_body_production_scalar_emit

namespace IRBodyProductionScalar

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics IRBodyProductionInputs IRTypeRefProof

variable {before after : State}

/-- The expression portion of the same source-selected return body. Position0
    is the real return header, framed by the assembled statement consumer. -/
def NaturalExpectedHeap (input : Inputs) (storage : ScalarStorage workspace initial slots)
    (output : IREventStoreProof.Context initial) (body : IRBodyProductionProof.ReturnBody)
    (permissions : OutputPermissions output body.count) (before after : Heap) : Prop :=
  (∀ index, 1 ≤ index → index < body.count →
    NativeSnapshot 64 extractedProgram after IREventStoreProof.eventType
      (permissions.eventBases index) (body.event index) 40) ∧
  (output.enabled = true → ∀ index, 1 ≤ index → index < body.count →
    NativeSnapshot 64 extractedProgram after IREventStoreProof.referenceType
      (permissions.typeBases index) (IRTypeRefProof.referenceValue input.signature.result) 16) ∧
  HeapWritesOn before after (fun address => storage.writes address ∨ permissions.writesFrom 1 address)

/-- Root annotation completes the same native expression stream. The input
    snapshots here come from the actual untyped writer; this law does not
    execute a second producer or read any disabled annotation slot. -/
theorem NaturalExpectedHeap.recordRoot {input : Inputs} {origin middle last : Heap}
    (storage : ScalarStorage workspace initial slots) (output : IREventStoreProof.Context initial)
    (body : IRBodyProductionProof.ReturnBody) (permissions : OutputPermissions output body.count)
    (inside : 1 < body.count)
    (retained : ∀ pointer count, initial.heap.Readable pointer count → middle.Readable pointer count)
    (events : ∀ index, 1 ≤ index → index < body.count →
      NativeSnapshot 64 extractedProgram middle IREventStoreProof.eventType
        (permissions.eventBases index) (body.event index) 40)
    (children : output.enabled = true → ∀ index, 2 ≤ index → index < body.count →
      NativeSnapshot 64 extractedProgram middle IREventStoreProof.referenceType
        (permissions.typeBases index) (referenceValue input.signature.result) 16)
    (written : HeapWritesOn origin middle
      (fun address => storage.writes address ∨ permissions.writesFrom 1 address))
    (recorded : IRResultTypeProof.Recorded
      (IRResultTypeProof.annotationSlot
        (permissions.slot (after := { initial with heap := middle }) 1 inside retained))
      input.signature.result middle last) :
    NaturalExpectedHeap input storage output body permissions origin last := by
  cases enabled : output.enabled with
  | false =>
      have same : last = middle := by
        simpa only [IRResultTypeProof.Recorded, IRResultTypeProof.annotationSlot,
          OutputPermissions.slot, enabled, Bool.false_eq_true, if_false] using recorded
      subst last
      exact ⟨events, (by intro impossible; have contradiction := enabled.symm.trans impossible; cases contradiction), written⟩
  | true =>
      have result : NativeSnapshot 64 extractedProgram last IREventStoreProof.referenceType
          (permissions.typeBases 1) (referenceValue input.signature.result) 16 ∧
          HeapRegionWrite middle last (permissions.typeBases 1) 16 := by
        simpa only [IRResultTypeProof.Recorded, IRResultTypeProof.annotationSlot,
          OutputPermissions.slot, enabled, if_true,
          show IRResultTypeProof.referenceType = IREventStoreProof.referenceType from rfl] using recorded
      refine ⟨?_, ?_, written.trans ?_⟩
      · intro index lower upper
        exact (events index lower upper).afterWrite result.2 (permissions.planes enabled index 1 upper inside)
      · intro _ index lower upper
        by_cases root : index = 1
        · subst index; exact result.1
        · exact (children enabled index (by omega) upper).afterWrite result.2
            (permissions.typeSeparation enabled index 1 upper inside root)
      · exact result.2.footprint.weaken (fun address range =>
          Or.inr ⟨1, Nat.le_refl _, inside, Or.inr ⟨enabled, range.1, range.2⟩⟩)

#print axioms NaturalExpectedHeap.recordRoot

/-- The closed natural producer selects its original token once, then runs
    the actual1871 reset/build and actual1249 live-code clearing. -/
theorem OriginalScalar.actualLower
    (original : OriginalScalar input before index expression route)
    (storage : ScalarStorage workspace before slots) (used : scalarCount expression ≤ slots)
    (apart : InputApart input storage.writes) (locals : Value) (depth : Nat)
    (enough : route.length < depth) (fits : depth < 2 ^ 31)
    (formed : before.CellsWellFormed) (unique : HeapBlockBasesUnique before.heap)
    (noViews : before.i32ArrayViews = []) :
    ∃ token, ScalarToken input before expression token ∧
      ∃ after, RunsExpr extractedProgram before (lowerExtractCall input workspace locals index depth)
        (.signed .i32 (scalarRoot expression)) after ∧
        MemoryEffect (PreparedNodes storage (scalarCount expression) (scalarNodes expression token)) before after := by
  have positive : 0 < scalarCount expression := by
    unfold scalarCount
    split <;> decide
  have inside : scalarRoot expression < scalarCount expression := by
    dsimp only [scalarRoot]
    omega
  obtain ⟨token, originalToken, build⟩ := original.actualBuild
  refine ⟨token, originalToken, ?_⟩
  apply actualExtractExpressionWith input workspace locals index depth storage
    (scalarCount expression) (scalarRoot expression) used inside ?_ formed noViews
  intro state same cells views
  have reads : HeapReads before.heap state.heap := by rw [same]; exact HeapReads.refl _
  let reached := storage.afterReads reads
  have extraction := actualExtractWith input.tree reached index depth
    (scalarCount expression) (scalarRoot expression) (scalarNodes expression token) (by
      intro ready written zero readyFormed readyViews
      have total : HeapWritesOn before.heap ready.heap storage.writes := by
        rw [← same]
        exact written
      exact build ready (reached.afterFootprint written) total used zero apart depth enough fits readyFormed
        (readyViews.trans (views.trans noViews))) cells (by rw [same]; exact unique) (views.trans noViews)
  exact extraction

#print axioms OriginalScalar.actualLower

def expectedSource := Extracted.«lowering::body_expression».Functions.«expression_from_surface_expected».core
def naturalExpectedCall (input : Inputs) (workspace : Workspace) (locals : Value)
    (surface depth : Nat) (output : Value) : Expr :=
  .call expectedSource.id ([bodyContext input workspace locals, .signed .i32 surface,
    referenceValue input.signature.result, output, .signed .i32 1, .signed .i32 depth].map Expr.value)

/-- The actual1251 wrapper obtains its count and root from the closed natural
    extraction, not from an assumed arena/output. Its1247 continuation is
    discharged by the final natural scalar theorem. -/
theorem OriginalScalar.actualFromSurfaceExpectedWith
    (original : OriginalScalar input before surface expression route)
    (storage : ScalarStorage workspace before (scalarCount expression))
    (body : IRBodyProductionProof.ReturnBody) (output : IREventStoreProof.Context before)
    (permissions : OutputPermissions output body.count)
    (apart : InputApart input storage.writes) (locals : Value) (depth : Nat)
    (enough : route.length < depth) (fits : depth < 2 ^ 31)
    (expected : ∀ {origin : State}, origin.heap = before.heap → ∀ token,
      ScalarToken input origin expression token → ∀ {state : State},
      PreparedNodes storage (scalarCount expression) (scalarNodes expression token) origin.heap state.heap →
      state.CellsWellFormed → state.i32ArrayViews = before.i32ArrayViews → ∃ after,
      RunsExpr extractedProgram state
        (.call Extracted.«lowering::body_expression».Functions.«expression_expected».core.id
          ([bodyContext input workspace locals, .signed .i32 (scalarCount expression),
            .signed .i32 (scalarRoot expression), referenceValue input.signature.result,
            output.value, .signed .i32 1, .signed .i32 depth].map Expr.value))
        (.signed .i32 body.count) after ∧
      MemoryEffect (NaturalExpectedHeap input storage output body permissions) state after)
    (formed : before.CellsWellFormed) (unique : HeapBlockBasesUnique before.heap)
    (noViews : before.i32ArrayViews = []) :
    ∃ after, RunsExpr extractedProgram before (naturalExpectedCall input workspace locals surface depth output.value)
      (.signed .i32 body.count) after ∧
      MemoryEffect (NaturalExpectedHeap input storage output body permissions) before after := by
  have positive : 0 < scalarCount expression := by unfold scalarCount; split <;> decide
  core_facts [storage, storage.arena]
  core_call_framed (RunsExpr.callEffect (MemoryEffect.scopeStable _)) expectedSource as callee
  apply RunsStmt.letEffect (MemoryEffect.scopeStable _) (value := workspace.arena)
  · core_run
  · core_formed
  · core_state arenaState
    have same : arenaState.heap = before.heap := rfl
    have reads : HeapReads before.heap arenaState.heap := by rw [same]; exact HeapReads.refl _
    obtain ⟨token, sourceToken, produced, lowerRun, lowerEffect⟩ :=
      (original.afterReads reads).actualLower (storage.afterReads reads) (Nat.le_refl _) apart locals depth enough fits
        (by core_formed) (by rw [same]; exact unique) noViews
    have initial : RunsExpr extractedProgram arenaState (expectedSource.bindingInitializer 1)
        (.signed .i32 (scalarRoot expression)) produced := by
      exact RunsExpr.callArguments (by core_arguments) lowerRun
    have prepared : PreparedNodes storage (scalarCount expression) (scalarNodes expression token)
        arenaState.heap produced.heap := lowerEffect.2.2.2
    have lowerFrame := lowerEffect.1
    have arenaFound : produced.local? (expectedSource.bindingId 0) = some storage.arena.value := by
      rw [← storage.arenaValue]
      exact lowerRun.localFound lowerFrame (by core_local)
    let rooted := produced.bindLocal (expectedSource.bindingId 1) (.signed .i32 (scalarRoot expression))
    have rootedFormed : rooted.CellsWellFormed := by core_formed
    have nodeCount {state : State} (heap : state.heap = produced.heap) (cells : state.CellsWellFormed) :=
      actualNodeCount storage.arena (by rw [heap]; exact prepared.1.2.1.read) cells
    have finish {state : State} (heap : state.heap = produced.heap) (cells : state.CellsWellFormed)
        (views : state.i32ArrayViews = rooted.i32ArrayViews) :
        ∃ after, RunsExpr extractedProgram state
          (.call Extracted.«lowering::body_expression».Functions.«expression_expected».core.id
            ([bodyContext input workspace locals, .signed .i32 (scalarCount expression),
              .signed .i32 (scalarRoot expression), referenceValue input.signature.result,
              output.value, .signed .i32 1, .signed .i32 depth].map Expr.value))
          (.signed .i32 body.count) after ∧
          MemoryEffect (NaturalExpectedHeap input storage output body permissions) state after := by
      exact expected same token sourceToken (by rw [heap]; exact prepared) cells
        (views.trans lowerEffect.2.2.1)
    obtain ⟨completed, tailRun, tailEffect⟩ : ∃ completed, RunsStmt extractedProgram rooted
        (match expectedSource.bindingStatement 1 with | .letLocal _ _ _ rest => rest | _ => .skip)
        (.returned (some (.signed .i32 body.count))) completed ∧
        MemoryEffect (NaturalExpectedHeap input storage output body permissions) rooted completed := by
      apply RunsStmt.guardEffectFalse (MemoryEffect.scopeStable _)
      · core_pure_guard
      · intro guarded guardFrame
        apply RunsStmt.returnEffect
        apply RunsExpr.callFramedEffectArguments (MemoryEffect.scopeStable _)
          (values := [bodyContext input workspace locals, .signed .i32 (scalarCount expression),
            .signed .i32 (scalarRoot expression), referenceValue input.signature.result,
            output.value, .signed .i32 1, .signed .i32 depth])
        · core_pure_arguments
        · intro arguments argumentFrame
          exact finish (argumentFrame.heap.trans guardFrame.heap) (by core_formed)
            (argumentFrame.views.trans guardFrame.views)
    refine ⟨restoreLocals produced completed, RunsStmt.letLocal initial tailRun,
      (lowerEffect.1.trans (FreshCellFrame.bindLocal produced _ _)).trans tailEffect.1,
      tailEffect.2.1.trans lowerEffect.2.1, tailEffect.2.2.1.trans lowerEffect.2.2.1,
      tailEffect.2.2.2.1, tailEffect.2.2.2.2.1, ?_⟩
    exact (prepared.1.2.2.weaken (fun _ allowed => Or.inl allowed)).trans tailEffect.2.2.2.2.2

#print axioms OriginalScalar.actualFromSurfaceExpectedWith

end IRBodyProductionScalar
