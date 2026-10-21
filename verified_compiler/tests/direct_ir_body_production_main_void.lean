import verified_compiler.tests.direct_ir_body_production_main_statement
import verified_compiler.tests.direct_ir_body_production_inputs_context

namespace IRBodyProductionProof

open Lanius Lanius.Core Lanius.Semantics IRTypeRefProof IRBodyProductionInputs
open IREventStoreProof

private def voidSource := Extracted.«lowering::body_statement».Functions.«return_void».core
def voidCall (context output : Value) (position : Int) : Expr :=
  .call voidSource.id [.value context, .value output, .value (.signed .i32 position)]

/-- The real Void-type guard followed by the real return writer. -/
theorem actualVoid (input : Inputs) (workspace : Workspace) (locals : Value)
    (kind : input.signature.result = .Void) :
    Produces (voidCall (bodyContext input workspace locals)) (returnEvent false) := by
  intro before output formed unique noViews
  core_call_framed (RunsExpr.callEffect (MemoryEffect.scopeStable _)) voidSource as callee
  apply RunsStmt.guardEffectFalse (MemoryEffect.scopeStable _)
  · apply RunsExpr.unaryPure (value := .boolean true)
    · apply RunsExpr.callPureArguments (values := [referenceValue .Void, referenceValue .Void])
      · apply RunsExprs.cons
        · apply RunsExpr.field (by core_run)
          change some (referenceValue input.signature.result) = some (referenceValue .Void)
          rw [kind]
        · core_arguments
      · exact actualSame .Void .Void (by core_formed)
    · rfl
  · intro ready pure
    apply RunsStmt.returnEffect
    apply RunsExpr.argumentsEffect
    · core_arguments
    · have heap : ready.heap = before.heap := by
        simpa only [State.bindLocals, List.foldl, State.bindLocal, State.bindCell] using pure.heap
      have views : ready.i32ArrayViews = before.i32ArrayViews := by
        simpa only [State.bindLocals, List.foldl, State.bindLocal, State.bindCell] using pure.views
      exact actualReturn false (output.reheap heap) pure.afterFormed
        (by rw [heap]; exact unique) (views.trans noViews)

#print axioms actualVoid

end IRBodyProductionProof
