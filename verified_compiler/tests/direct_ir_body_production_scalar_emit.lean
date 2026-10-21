import verified_compiler.tests.direct_ir_result_type
import Lanius.Semantics.EffectProof

namespace IRBodyProductionScalar

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics IRTypeRefProof

private def annotateSource := Extracted.«lowering::body_expression».Functions.«annotate_result».core
def annotateCall (output : IREventStoreProof.Context state) (next : Nat) (kind : Reference) : Expr :=
  .call annotateSource.id [.value output.value, .value (.signed .i32 output.position),
    .value (.signed .i32 next), .value (referenceValue kind)]

/-- The annotation guard is an effectful call. Disabled annotations do not
    require type storage; enabled annotations write only their selected slot. -/
theorem actualAnnotateResult (output : IREventStoreProof.Context before) (next : Nat)
    (kind : Reference) (valid : 0 ≤ typeCode kind) (formed : before.CellsWellFormed)
    (unique : HeapBlockBasesUnique before.heap) (noViews : before.i32ArrayViews = []) :
    ∃ after, RunsExpr extractedProgram before (annotateCall output next kind)
      (.signed .i32 next) after ∧
      MemoryEffect (IRResultTypeProof.Recorded (IRResultTypeProof.annotationSlot output) kind) before after := by
  core_facts [output]
  core_call_framed (RunsExpr.callEffect (MemoryEffect.scopeStable _)) annotateSource as callee
  apply RunsStmt.guardEffectFalse (MemoryEffect.scopeStable _)
  · core_pure_guard
  · intro selected guardFrame
    let reached := output.reheap (after := selected) guardFrame.heap
    obtain ⟨after, record, cells, world, views, writes⟩ := IRResultTypeProof.actualRecord
      (events := .rawSlice IREventStoreProof.eventType output.events output.capacity)
      (IRResultTypeProof.annotationSlot reached) kind valid (by core_formed)
      (by rw [guardFrame.heap]; exact unique) (guardFrame.views.trans noViews)
    have localRecord : RunsExpr extractedProgram selected
        (.call Extracted.«ir::body_events».Functions.«record_result_type».core.id
          [.local (annotateSource.argumentId 0), .local (annotateSource.argumentId 1),
            .local (annotateSource.argumentId 3)]) (.boolean true) after := by
      apply RunsExpr.callArguments
      · core_arguments
      · exact record
    have condition : RunsExpr extractedProgram selected
        (.unary .logicalNot (.call Extracted.«ir::body_events».Functions.«record_result_type».core.id
          [.local (annotateSource.argumentId 0), .local (annotateSource.argumentId 1),
            .local (annotateSource.argumentId 3)])) (.boolean false) after :=
      RunsExpr.unary localRecord rfl
    have body : RunsStmt extractedProgram selected
        (match annotateSource.body.getD .skip with | .sequence _ rest => rest | _ => .skip)
        (.returned (some (.signed .i32 next))) after := by
      exact RunsStmt.sequenceNext (RunsStmt.ifThenElseFalse condition (RunsStmt.skip _ _))
        (RunsStmt.returnValue (by core_run))
    exact ⟨after, body, cells, world, views, writes⟩

#print axioms actualAnnotateResult

end IRBodyProductionScalar
