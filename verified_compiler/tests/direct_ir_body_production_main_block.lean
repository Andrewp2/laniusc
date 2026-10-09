import verified_compiler.tests.direct_ir_body_production_main_composition
import verified_compiler.tests.direct_ir_body_production_inputs_locals

namespace IRBodyProductionProof

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics IRBodyProductionInputs

private def blockSource := Extracted.«lowering::body_statement».Functions.«block_statements».core
def terminalBlockCall (context : Value) (block : Nat) (output : Value) (position : Int) (depth : Nat) : Expr :=
  .call blockSource.id [.value context, .value (.signed .i32 block), .value output,
    .value (.signed .i32 position), .value (.signed .i32 depth)]

/-- The real block restores only its count field after the proved stream phase.
    The stream relation is retained once, not reconstructed from a decoder. -/
def BlockHeapEffect (stream : Heap → Heap → Prop) (memory : Nat) (before after : Heap) : Prop :=
  ∃ emitted, stream before emitted ∧
    NativeSnapshot 64 extractedProgram after (.scalar (.signed .i32)) memory (.signed .i32 0) 4 ∧
    HeapRegionWrite emitted after memory 4

theorem BlockHeapEffect.footprint
    (effect : BlockHeapEffect stream memory before after)
    (writes : ∀ {a b}, stream a b → HeapWritesOn a b allowed) :
    HeapWritesOn before after (fun address => allowed address ∨ memory ≤ address ∧ address < memory + 4) := by
  obtain ⟨emitted, produced, _, restored⟩ := effect
  exact ((writes produced).weaken (fun _ inside => Or.inl inside)).trans
    (restored.footprint.weaken (fun _ inside => Or.inr inside))

/-- Pure source queries/save compose automatically; the only effect boundary
    is the terminal stream followed by the actual four-byte locals restore. -/
theorem actualTerminalBlock (input : Inputs) (workspace : Workspace)
    (memory capacity block list depth : Nat) (positive : 1 < depth) (fits : depth < 2 ^ 31)
    (query : ∀ {current : State}, current.heap = before.heap → current.CellsWellFormed → ∃ after,
      RunsExpr extractedProgram current (.call Extracted.«verified::surface_statement».Functions.«block_statements».core.id
        [.value input.tree.value, .value (.signed .i32 block)]) (.signed .i32 list) after ∧ PureFrame current after)
    (lower : ∀ {current : State}, current.heap = before.heap → current.i32ArrayViews = before.i32ArrayViews →
      current.CellsWellFormed → ∃ after,
      RunsExpr extractedProgram current
        (terminalListCall (bodyContext input workspace (localsValue memory capacity)) list output position (depth - 1))
        result after ∧ MemoryEffect stream current after)
    (writes : ∀ {a b}, stream a b → HeapWritesOn a b allowed)
    (count : NativeSnapshot 64 extractedProgram before.heap (.scalar (.signed .i32)) memory (.signed .i32 0) 4)
    (room : before.heap.Readable memory 4) (formed : before.CellsWellFormed)
    (noViews : before.i32ArrayViews = []) : ∃ after,
    RunsExpr extractedProgram before
      (terminalBlockCall (bodyContext input workspace (localsValue memory capacity)) block output position depth)
      result after ∧ MemoryEffect (BlockHeapEffect stream memory) before after := by
  have decrement := eval_i32_subNat extractedProgram.target depth 1 (by omega) fits
  have save {current : State} (heap : current.heap = before.heap) (formed : current.CellsWellFormed) :=
    actualLocalSave memory capacity (by rw [heap]; exact count) formed
  core_call_framed (RunsExpr.callEffect (MemoryEffect.scopeStable _)) blockSource as callee
  repeat first
    | (apply RunsStmt.guardEffectFalse (MemoryEffect.scopeStable _); core_pure_guard; intro ready frame)
    | (apply RunsStmt.letEffect (MemoryEffect.scopeStable _); core_run; core_formed)
    | (apply RunsStmt.letFramedEffect (MemoryEffect.scopeStable _); core_pure_expr; intro ready frame)
  core_state ready
  have readyHeap : ready.heap = before.heap := by core_frame
  have readyViews : ready.i32ArrayViews = before.i32ArrayViews := by core_frame
  have readyFormed : ready.CellsWellFormed := by core_formed
  have localsAtReady : ready.local? (blockSource.bindingId 1) = some (localsValue memory capacity) := by core_local
  have savedAtReady : ready.local? (blockSource.bindingId 2) = some (.signed .i32 0) := by core_local
  obtain ⟨emitted, producedRun, produced⟩ := lower readyHeap readyViews readyFormed
  have initial : RunsExpr extractedProgram ready (blockSource.bindingInitializer 3) result emitted := by
    apply RunsExpr.callArguments (by core_arguments) producedRun
  let bound := emitted.bindLocal (blockSource.bindingId 3) result
  have emittedFormed := producedRun.cellsWellFormed readyFormed
  have localsAtBound := State.bindLocal_local?_of_ne emitted emittedFormed
    (blockSource.bindingId 1) (blockSource.bindingId 3) (localsValue memory capacity) result (by decide)
    (produced.1.localFound producedRun.choose_spec.2 _ _ localsAtReady)
  have savedAtBound := State.bindLocal_local?_of_ne emitted emittedFormed
    (blockSource.bindingId 2) (blockSource.bindingId 3) (.signed .i32 0) result (by decide)
    (produced.1.localFound producedRun.choose_spec.2 _ _ savedAtReady)
  have emittedWrites := writes produced.2.2.2
  obtain ⟨restored, restoreRun, restoredEffect⟩ := actualLocalRestore memory capacity (Int32.ofInt 0)
    (before := bound) (emittedWrites.readable memory 4 (by rw [readyHeap]; exact room))
    emittedWrites.unique (by core_formed)
    (produced.2.2.1.trans (readyViews.trans noViews))
  have restoring : RunsExpr extractedProgram bound (blockSource.effectExpression 0) .unit restored := by
    apply RunsExpr.callArguments
      (.cons (.ofStable (.local localsAtBound) rfl) (.cons (.ofStable (.local savedAtBound) rfl) .nil)) restoreRun
  have resultFound : bound.local? (blockSource.bindingId 3) = some result :=
    State.bindLocal_local? emitted (by core_formed) _ _
  have returned := restoredEffect.1.localFound restoreRun.choose_spec.2 _ _ resultFound
  refine ⟨restoreLocals emitted restored, RunsStmt.letLocal initial ?_, ?_⟩
  · exact RunsStmt.sequenceNext (RunsStmt.expression restoring)
      (RunsStmt.returnValue (.ofStable (.local returned) rfl))
  · refine ⟨(produced.1.trans (FreshCellFrame.bindLocal emitted (blockSource.bindingId 3) result)).trans
      restoredEffect.1, restoredEffect.2.1.trans produced.2.1,
      restoredEffect.2.2.1.trans produced.2.2.1, emitted.heap, produced.2.2.2, ?_, restoredEffect.2.2.2.2⟩
    simpa only [restoreLocals, show (Int32.ofInt 0).toInt = 0 from by decide]
      using restoredEffect.2.2.2.1

#print axioms BlockHeapEffect.footprint
#print axioms actualTerminalBlock

end IRBodyProductionProof
