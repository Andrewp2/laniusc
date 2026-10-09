import verified_compiler.tests.direct_ir_body_production_main_composition

namespace IRBodyProductionProof

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics IRBodyProductionInputs
open IREventStoreProof IRTypeRefProof

private def valueSource := Extracted.«lowering::body_statement».Functions.«return_value».core
def expectedScalarCall (input : Inputs) (workspace : Workspace) (locals : Value)
    (root : Nat) (output : Value) (position : Int) (depth : Nat) : Expr :=
  .call Extracted.«lowering::body_expression».Functions.«expression_from_surface_expected».core.id
    [.value (bodyContext input workspace locals), .value (.signed .i32 root),
      .value (referenceValue input.signature.result), .value output,
      .value (.signed .i32 position), .value (.signed .i32 depth)]

/-- The actual return header precedes one source-derived scalar phase.
    Its native snapshot is interpreted and framed by the final body consumer. -/
def ValueReturnHeapEffect (output : Context anchor) (expression : Heap → Heap → Prop)
    (before after : Heap) : Prop :=
  ∃ header, appendHeapEffect output.enabled output.eventBase output.typeBase
    (returnEvent true) before header ∧ expression header after

/-- This is an internal composition boundary. The natural scalar theorem
    discharges `expected`; no extraction or writer run is an original input. -/
theorem actualValueReturnWith (input : Inputs) (workspace : Workspace) (locals : Value)
    (root depth : Nat) (positive : 0 < depth) (fits : depth < 2 ^ 31)
    (output : Context before) (next : Int)
    (expected : ∀ {current : State},
      appendHeapEffect output.enabled output.eventBase output.typeBase (returnEvent true)
        before.heap current.heap → current.CellsWellFormed →
      current.i32ArrayViews = before.i32ArrayViews → ∃ after,
      RunsExpr extractedProgram current
        (expectedScalarCall input workspace locals root output.value (output.position + 1) (depth - 1))
        (.signed .i32 next) after ∧ MemoryEffect expression current after)
    (formed : before.CellsWellFormed) (unique : HeapBlockBasesUnique before.heap)
    (noViews : before.i32ArrayViews = []) : ∃ after,
    RunsExpr extractedProgram before
      (terminalLeaf (some root) (bodyContext input workspace locals) output.value output.position depth)
      (.signed .i32 next) after ∧ MemoryEffect (ValueReturnHeapEffect output expression) before after := by
  have decrement := eval_i32_subNat extractedProgram.target depth 1 (by omega) fits
  core_call_framed (RunsExpr.callEffect (MemoryEffect.scopeStable _)) valueSource as callee
  have calleeHeap : callee.heap = before.heap := by core_frame
  have calleeViews : callee.i32ArrayViews = before.i32ArrayViews := by core_frame
  obtain ⟨header, headerRun, written⟩ := actualReturn true (output.reheap calleeHeap)
    (by core_formed) (by rw [calleeHeap]; exact unique) (calleeViews.trans noViews)
  have initialization : RunsExpr extractedProgram callee (valueSource.bindingInitializer 0)
      (.signed .i32 (output.position + 1 : Nat)) header := by
    apply RunsExpr.callArguments (middle := callee)
      (values := [output.value, .signed .i32 output.position, returnPresence true]) (by core_arguments)
    change RunsExpr extractedProgram callee (returnCall true output.value output.position)
      (.signed .i32 (output.position + 1 : Nat)) header
    simpa only [Context.reheap, Context.value] using headerRun
  let bound := header.bindLocal (valueSource.bindingId 0) (.signed .i32 (output.position + 1 : Nat))
  have headerEffect : appendHeapEffect output.enabled output.eventBase output.typeBase (returnEvent true)
      before.heap bound.heap := by
    simpa only [Context.reheap, bound, State.bindLocal, State.bindCell, calleeHeap] using written.2.2.2
  have boundFormed : bound.CellsWellFormed := (written.1.after_cellsWellFormed (by core_formed)).bindLocal _ _
  have boundViews : bound.i32ArrayViews = before.i32ArrayViews := written.2.2.1.trans calleeViews
  have argumentsKept (id : VarId) (value : Value)
      (found : callee.local? id = some value) (different : valueSource.bindingId 0 ≠ id) :
      bound.local? id = some value :=
    State.bindLocal_local?_of_ne header (written.1.after_cellsWellFormed (by core_formed))
      id (valueSource.bindingId 0) value (.signed .i32 (output.position + 1 : Nat)) different
      (written.1.localFound headerRun.choose_spec.2 id value found)
  have contextFound : bound.local? (valueSource.argumentId 0) =
      some (bodyContext input workspace locals) :=
    argumentsKept _ _ (by core_local) (by decide)
  have returnKind : RunsExpr extractedProgram bound
      (.field (.local (valueSource.argumentId 0)) 19) (referenceValue input.signature.result) bound :=
    .ofStable (.field (.local contextFound) rfl) rfl
  have depthFound : bound.local? (valueSource.argumentId 4) = some (.signed .i32 depth) :=
    argumentsKept _ _ (by core_local) (by decide)
  obtain ⟨after, scalarRun, scalarEffect⟩ := expected headerEffect boundFormed boundViews
  let returnExpression := match valueSource.bindingStatement 0 with
    | .letLocal _ _ _ (.returnValue (some expression)) => expression
    | _ => .value .unit
  have returning : RunsExpr extractedProgram bound
      returnExpression (.signed .i32 next) after := by
    have nextFound := State.bindLocal_local? header (by core_formed) (valueSource.bindingId 0)
      (.signed .i32 (output.position + 1 : Nat))
    apply RunsExpr.callArguments (middle := bound)
      (values := [bodyContext input workspace locals, .signed .i32 root,
        referenceValue input.signature.result, output.value,
        .signed .i32 (output.position + 1 : Nat), .signed .i32 (depth - 1 : Nat)]) (by core_arguments)
    change RunsExpr extractedProgram bound
      (expectedScalarCall input workspace locals root output.value (output.position + 1 : Nat) (depth - 1))
      (.signed .i32 next) after
    simpa only [expectedScalarCall, List.map, Int.natCast_add, Int.natCast_one] using scalarRun
  refine ⟨restoreLocals header after, RunsStmt.letLocal initialization (RunsStmt.returnValue returning),
    (written.1.trans (FreshCellFrame.bindLocal header _ _)).trans scalarEffect.1,
    scalarEffect.2.1.trans written.2.1, scalarEffect.2.2.1.trans written.2.2.1,
    header.heap, ?_, scalarEffect.2.2.2⟩
  change appendHeapEffect output.enabled output.eventBase output.typeBase (returnEvent true)
    callee.heap header.heap
  simpa only [Context.reheap, calleeHeap] using written.2.2.2

#print axioms actualValueReturnWith

end IRBodyProductionProof
