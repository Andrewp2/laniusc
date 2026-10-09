import verified_compiler.tests.direct_ir_event_write

namespace IRBodyProductionProof

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics
open IREventStoreProof IRTypeRefProof

private def returnSource := Extracted.«lowering::body_event_write».Functions.«statement_return».core

def returnEvent : Bool → Value
  | false => source_value Extracted.«ir::body_events».Types.«Event».«StatementReturnVoid» []
  | true => source_value Extracted.«ir::body_events».Types.«Event».«StatementReturnValue» []

def returnPresence : Bool → Value
  | false => source_value Extracted.«backend::syntax».Types.«Presence».«Absent» []
  | true => source_value Extracted.«backend::syntax».Types.«Presence».«Present» []

def returnCall (present : Bool) (output : Value) (position : Int) : Expr :=
  .call returnSource.id [.value output, .value (.signed .i32 position), .value (returnPresence present)]

/-- The actual shared return writer, including its annotation reset and exact
    two-store frame. Neither old destination value is decoded. -/
theorem actualReturn (present : Bool) : Produces (returnCall present) (returnEvent present) := by
  intro before input formed unique noViews
  have codec : NativeStoreSpec 64 extractedProgram eventType (returnEvent present) 40 := by
    cases present <;> dsimp only [returnEvent] <;> native_store
  cases present <;> dsimp only [returnCall, returnPresence, returnEvent]
  all_goals
    core_call_framed (RunsExpr.callEffect (MemoryEffect.scopeStable _)) returnSource as callee
    apply RunsStmt.returnEffect
    apply RunsExpr.matchEffect (MemoryEffect.scopeStable _)
    · core_run
    · rfl
    · core_formed
    · apply RunsExpr.argumentsEffect
      · core_arguments
      · core_state branch
        exact actualAppend (input.reheap (after := branch) rfl) codec (by core_formed) unique noViews

#print axioms actualReturn

end IRBodyProductionProof
