import verified_compiler.tests.direct_ir_body_production_inputs_context
import verified_compiler.tests.direct_ir_body_production_inputs_locals
import Lanius.Semantics.EffectProof

namespace IRBodyProductionProof

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics IRBodyProductionInputs IRTypeRefProof

def producerSource := Extracted.«lowering::bodies».Functions.«append_function».core
def producerCall (input : Inputs) (workspace : Workspace) (declaration depth : Nat) : Expr :=
  .call producerSource.id [.value input.value, .value workspace.value, .value (.signed .i32 declaration),
    .value (.signed .i32 input.signature.id), .value (.signed .i32 depth)]

/-- One final heap/world/view post crosses the pure prefix and lexical scopes.
    It does not erase the actual allocator observation. -/
private def Finished (post : Heap → World.State → List I32ArrayView → Prop) (before after : State) : Prop :=
  FreshCellFrame before after ∧ post after.heap after.world after.i32ArrayViews
private theorem finishedScopes (post : Heap → World.State → List I32ArrayView → Prop) :
    ScopeStable (Finished post) :=
  ⟨fun frame effect => ⟨frame.cells.trans effect.1, effect.2⟩,
    fun _ effect => ⟨effect.1, effect.2⟩⟩

@[core_pure_rule] private theorem actualBodyInvalid (formed : before.CellsWellFormed) : ∃ after,
    RunsExpr extractedProgram before (.call Extracted.«lowering::body_context».Functions.«invalid».core.id [])
      (.signed .i32 (-1)) after ∧ PureFrame before after := by
  let invalid := source_value Extracted.«lowering::error».Types.«LoweringError».«InvalidInput» []
  have invalidCode {state : State} (formed : state.CellsWellFormed) : ∃ after,
      RunsExpr extractedProgram state
        (.call Extracted.«lowering::error».Functions.«error_code».core.id [.value invalid])
        (.signed .i32 1) after ∧ PureFrame state after := by
    core_call_pure Extracted.«lowering::error».Functions.«error_code».core as callee
    core_pure
  have failure {state : State} (formed : state.CellsWellFormed) : ∃ after,
      RunsExpr extractedProgram state
        (.call Extracted.«lowering::error».Functions.«failure».core.id [.value invalid])
        (.signed .i32 (-1)) after ∧ PureFrame state after := by
    core_call_pure Extracted.«lowering::error».Functions.«failure».core as callee
    core_pure
  core_call_pure Extracted.«lowering::body_context».Functions.«invalid».core as callee
  core_pure

/-- Locals exhaustion is a complete real1179 call: signature reads precede
    its one failed allocation; no producer or append execution is assumed. -/
theorem actualLocalsExhausted (input : Inputs) (workspace : Workspace) (declaration depth : Nat)
    (signature : input.signature.Read before) (valid : isValidResult input.signature.result = true)
    (positive : 0 < input.tokenCount) (capacity : input.tokenCount ≤ 89478484)
    (exhausted : consumeBudget before.heap.remaining (localBytes input.tokenCount) = none)
    (formed : before.CellsWellFormed) (noViews : before.i32ArrayViews = []) : ∃ after,
    RunsExpr extractedProgram before (producerCall input workspace declaration depth) (.signed .i32 (-1)) after ∧
    FreshCellFrame before after ∧ after.heap = before.heap ∧
    after.world = World.record before.world .alloc ∧ after.i32ArrayViews = before.i32ArrayViews ∧
    after.locals = before.locals := by
  let post : Heap → World.State → List I32ArrayView → Prop := fun heap world views =>
    heap = before.heap ∧ world = World.record before.world .alloc ∧ views = before.i32ArrayViews
  suffices finished : ∃ after, RunsExpr extractedProgram before (producerCall input workspace declaration depth)
      (.signed .i32 (-1)) after ∧ Finished post before after by
    obtain ⟨after, run, cells, heap, world, views⟩ := finished
    exact ⟨after, run, cells, heap, world, views, run.choose_spec.2⟩
  have signatureRead := signature
  unfold Signature.Read at signatureRead
  have validResult {state : State} (formed : state.CellsWellFormed) : ∃ after,
      RunsExpr extractedProgram state
        (.call Extracted.«ir::type_ref».Functions.«valid_result».core.id
          [.value (referenceValue input.signature.result)]) (.boolean true) after ∧ PureFrame state after := by
    have proof := actualValidResult input.signature.result formed
    change ∃ after, RunsExpr extractedProgram state
      (.call Extracted.«ir::type_ref».Functions.«valid_result».core.id
        [.value (referenceValue input.signature.result)])
      (.boolean (isValidResult input.signature.result)) after ∧ PureFrame state after at proof
    simpa only [valid] using proof
  have bytesCast := eval_unsigned_castNat extractedProgram.target .usize .i32 (localBytes input.tokenCount)
    (by change localBytes input.tokenCount < 2 ^ 64; dsimp only [localBytes]; omega)
  have alignmentCast := eval_unsigned_castNat extractedProgram.target .usize .i32 8 (by decide)
  core_facts [input.signature]
  core_call_framed (RunsExpr.callEffect (finishedScopes post)) producerSource as callee
  repeat first
    | (apply RunsStmt.letEffect (finishedScopes post); core_run; core_formed)
    | (apply RunsStmt.letFramedEffect (finishedScopes post); core_pure_expr; intro ready frame)
  apply RunsStmt.guardEffectFalse (finishedScopes post)
  · core_pure_guard
  intro supported guardFrame
  repeat first
    | (apply RunsStmt.letEffect (finishedScopes post); core_run; core_formed)
    | (apply RunsStmt.letFramedEffect (finishedScopes post); core_pure_expr; intro ready frame)
  core_state ready
  have readyHeap : ready.heap = before.heap := by core_frame
  have readyWorld : ready.world = before.world := by core_frame
  have readyViews : ready.i32ArrayViews = before.i32ArrayViews := by core_frame
  have readyFormed : ready.CellsWellFormed := by core_formed
  have bytesFound : ready.local? (producerSource.bindingId 20) =
      some (.unsigned .usize (localBytes input.tokenCount)) := by core_local
  have alignmentFound : ready.local? (producerSource.bindingId 21) =
      some (.unsigned .usize 8) := by core_local
  let allocated := { ready with world := World.record ready.world .alloc }
  have allocation : RunsExpr extractedProgram ready (producerSource.bindingInitializer 22) (.pointer 0) allocated := by
    apply RunsExpr.callArguments
      (values := [.unsigned .usize (localBytes input.tokenCount), .unsigned .usize 8]) (by core_arguments)
    exact actualLocalExhaustion input.tokenCount (by rw [readyHeap]; exact exhausted) (readyViews.trans noViews)
  let bound := allocated.bindLocal (producerSource.bindingId 22) (.pointer 0)
  let tail := match producerSource.bindingStatement 22 with | .letLocal _ _ _ rest => rest | _ => .skip
  obtain ⟨rejected, rejection, pure⟩ : ∃ rejected,
      RunsStmt extractedProgram bound tail (.returned (some (.signed .i32 (-1)))) rejected ∧
      PureFrame bound rejected := by
    have nullFound : bound.local? (producerSource.bindingId 22) = some (.pointer 0) :=
      State.bindLocal_local? allocated (by change ready.CellsWellFormed; exact readyFormed) _ _
    core_pure
  refine ⟨restoreLocals allocated rejected, RunsStmt.letLocal allocation rejection, ?_, ?_⟩
  · exact ((CallerFrame.refl readyFormed).cells.trans
      (FreshCellFrame.bindLocal allocated (producerSource.bindingId 22) (.pointer 0))).trans pure.cells
  · exact ⟨pure.heap.trans readyHeap, by simpa only
      [restoreLocals, bound, allocated, State.bindLocal, State.bindCell, readyWorld] using pure.world,
      pure.views.trans readyViews⟩

#print axioms actualLocalsExhausted

end IRBodyProductionProof
