import verified_compiler.tests.direct_ir_event_codecs
import Lanius.Semantics.ScopedEffect

namespace IREventWriteProof

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics IREventStoreProof IREventCodecProof
open IRTypeRefProof

private def source := Extracted.«lowering::body_event_write».Functions.«expression_call».core
private def matching := Extracted.«lowering::body_event_write».Functions.«expression_match».core
private def literalSource := Extracted.«lowering::body_event_write».Functions.«expression_value».core
def headerCall (output : Value) (position : Int) (functionId arguments : Int32) : Expr :=
  .call source.id [.value output, .value (.signed .i32 position), .value (callHeader functionId arguments)]
def matchingCall (output : Value) (position : Int) (kind : Reference) (scrutinee arms : Int32) : Expr :=
  .call matching.id [.value output, .value (.signed .i32 position), .value (matchingHeader kind scrutinee arms)]
abbrev Literal := Extracted.«ir::body_events».Types.«LiteralValue»
def literalValue : Literal → Value
  | .IntegerValue word => source_value Extracted.«ir::body_events».Types.«LiteralValue».«IntegerValue» [.signed .i32 word.toInt]
  | .BooleanValue flag => source_value Extracted.«ir::body_events».Types.«LiteralValue».«BooleanValue» [.boolean flag]
def literalEvent : Literal → Value
  | .IntegerValue word => integer word.toBitVec
  | .BooleanValue flag => boolean flag
def literalKind : Literal → Reference
  | .IntegerValue _ => .I32
  | .BooleanValue _ => .Bool
def literalCall (output : Value) (position : Int) (literal : Literal) : Expr :=
  .call literalSource.id [.value output, .value (.signed .i32 position), .value (literalValue literal)]

def negateEvent : Value := source_value Extracted.«ir::body_events».Types.«Event».«ExpressionUnaryNegate» []
def negateCall (output : Value) (position : Int) : Expr :=
  .call Extracted.«lowering::body_event_write».Functions.«expression_unary».core.id
    [.value output, .value (.signed .i32 position),
      .value (source_value Extracted.«backend::syntax».Types.«UnaryOperation».«UnaryNegate» [])]

theorem actualNegate : Produces negateCall negateEvent := by
  intro before input formed unique noViews
  have codec : NativeStoreSpec 64 extractedProgram eventType negateEvent 40 :=
    (NativeStoreSpec.enumEmpty (by core_lookup) rfl (by decide)).enlarge (by decide)
  core_call_framed (RunsExpr.callEffect (MemoryEffect.scopeStable _))
    Extracted.«lowering::body_event_write».Functions.«expression_unary».core as callee
  apply RunsStmt.returnEffect
  apply RunsExpr.matchEffect (MemoryEffect.scopeStable _)
  · core_run
  · rfl
  · core_formed
  · apply RunsExpr.argumentsEffect
    · core_arguments
    · core_state branch
      exact actualAppend (input.reheap (after := branch) rfl) codec (by core_formed) unique noViews

macro "ir_return_append" : tactic => `(tactic| (
  apply RunsStmt.returnEffect
  apply RunsExpr.argumentsEffect
  · core_arguments
  · assumption))

/-- The actual frontend writer validates both header fields, constructs the
    Call event, and stores that exact header. It does not prove target lookup
    or argument-expression typing; those belong to its frontend caller. -/
theorem actualCallHeader (functionId arguments : Int32) (valid : 0 ≤ functionId.toInt ∧ 0 ≤ arguments.toInt) :
    Produces (fun output position => headerCall output position functionId arguments) (callEvent functionId arguments) := by
  intro before input formed unique noViews
  core_call_framed (RunsExpr.callEffect (MemoryEffect.scopeStable _)) source as callee
  let boundInput := input.reheap (after := callee) rfl
  apply RunsStmt.guardEffectFalse (MemoryEffect.scopeStable _)
  · core_pure_guard
  · intro ready pure
    let active := boundInput.reheap pure.heap
    have append := actualAppend active (callCodec functionId arguments) pure.afterFormed
      (by rw [pure.heap]; exact unique) (pure.views.trans noViews)
    ir_return_append

/-- Invalid headers are rejected before touching even a null output region. -/
theorem actualCallReject (functionId arguments : Int32) (bad : functionId.toInt < 0 ∨ arguments.toInt < 0)
    (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before (headerCall output position functionId arguments)
      (.signed .i32 (-1)) after ∧ PureFrame before after := by
  core_call_pure source as callee
  core_pure

/-- This writer checks the result type and positive arm count. Scrutinee
    identity and arm exhaustiveness are obligations of its frontend caller. -/
theorem actualMatchHeader (kind : Reference) (scrutinee arms : Int32) (valid : isValid kind = true ∧ 0 < arms.toInt) :
    Produces (fun output position => matchingCall output position kind scrutinee arms) (matchingEvent kind scrutinee arms) := by
  intro before input formed unique noViews
  core_call_framed (RunsExpr.callEffect (MemoryEffect.scopeStable _)) matching as callee
  let boundInput := input.reheap (after := callee) rfl
  apply RunsStmt.guardEffectFalse (MemoryEffect.scopeStable _)
  · core_pure_guard
  · intro ready pure
    let active := boundInput.reheap pure.heap
    have append := actualAppend active (matchingCodec kind scrutinee arms) pure.afterFormed
      (by rw [pure.heap]; exact unique) (pure.views.trans noViews)
    ir_return_append

theorem actualMatchReject (kind : Reference) (scrutinee arms : Int32)
    (bad : isValid kind = false ∨ arms.toInt ≤ 0) (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before (matchingCall output position kind scrutinee arms)
      (.signed .i32 (-1)) after ∧ PureFrame before after := by
  core_call_pure matching as callee
  core_pure

/-- Pattern dispatch, payload binding and the exact native store are connected
    to the actual writer, for every signed word and Boolean literal. -/
theorem actualLiteral (literal : Literal) :
    Produces (fun output position => literalCall output position literal) (literalEvent literal) := by
  intro before input formed unique noViews
  have codec : NativeStoreSpec 64 extractedProgram eventType (literalEvent literal) 40 := by
    cases literal <;> dsimp only [literalEvent] <;> native_store
  cases literal <;> dsimp only [literalValue, literalEvent]
  all_goals
    core_call_framed (RunsExpr.callEffect (MemoryEffect.scopeStable _)) literalSource as callee
    apply RunsStmt.returnEffect
    apply RunsExpr.matchEffect (MemoryEffect.scopeStable _)
    · core_run
    · rfl
    · core_formed
    · apply RunsExpr.argumentsEffect
      · core_arguments
      · core_state branch
        exact actualAppend (input.reheap (after := branch) rfl) codec (by core_formed) unique noViews

#print axioms actualCallHeader
#print axioms actualCallReject
#print axioms actualMatchHeader
#print axioms actualMatchReject
#print axioms actualLiteral
#print axioms actualNegate

end IREventWriteProof
