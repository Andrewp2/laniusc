import verified_compiler.tests.direct_ir_event_write
import verified_compiler.tests.direct_ir_integer_lowering

namespace IRLiteralLoweringProof

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics IREventStoreProof IREventWriteProof

private def source := Extracted.«lowering::body_literal».Functions.«emit».core
def booleanNode (flag : Bool) (token : Int32) : Value :=
  source_value Extracted.«verified::surface_expr».Types.«ExpressionNode».mk
    [source_value Extracted.«verified::surface_expr».Types.«SurfaceExprKind».«Literal» [],
      if flag then source_value Extracted.«verified::surface_expr».Types.«ExpressionOperator».«LiteralTrue» []
      else source_value Extracted.«verified::surface_expr».Types.«ExpressionOperator».«LiteralFalse» [],
      .signed .i32 (-1), .signed .i32 (-1), .signed .i32 token.toInt, .signed .i32 (-1)]
def booleanCall (context : Value) (flag : Bool) (token : Int32) (output : Value) (position : Int) : Expr :=
  .call source.id [.value context, .value (booleanNode flag token), .value output, .value (.signed .i32 position)]

def integerContext (input : IRIntegerLoweringProof.Input before) (unused : List Value) : Value :=
  .structure (match source_value Extracted.«lowering::body_context».Types.«BodyContext».mk [] with
    | .structure id _ => id | _ => 0)
    ([.rawSlice (.scalar (.signed .i32)) input.address input.capacity, .signed .i32 input.count,
      input.tokens, .signed .i32 input.tokenCount] ++ unused)
def integerNode (token : Nat) : Value := source_value Extracted.«verified::surface_expr».Types.«ExpressionNode».mk
  [source_value Extracted.«verified::surface_expr».Types.«SurfaceExprKind».«Literal» [],
    source_value Extracted.«verified::surface_expr».Types.«ExpressionOperator».«LiteralInteger» [],
    .signed .i32 (-1), .signed .i32 (-1), .signed .i32 token, .signed .i32 (-1)]
def integerCall (input : IRIntegerLoweringProof.Input before) (unused : List Value) (output : Value) (position : Int) : Expr :=
  .call source.id [.value (integerContext input unused), .value (integerNode input.tokenIndex),
    .value output, .value (.signed .i32 position)]

/-- Lowering consumes the parsed Boolean operator directly. It never reads
    the context's source/token buffers on this path, even for arbitrary token IDs. -/
theorem actualBoolean (context : Value) (flag : Bool) (token : Int32) :
    Produces (booleanCall context flag token) (boolean flag) := by
  intro before input formed unique noViews
  have produces : Produces (fun output position => literalCall output position (.BooleanValue flag)) (boolean flag) :=
    actualLiteral (.BooleanValue flag)
  cases flag
  all_goals
    core_call_framed (RunsExpr.callEffect (MemoryEffect.scopeStable _)) source as callee
    apply RunsStmt.letEffect (MemoryEffect.scopeStable _)
    · core_run
    · core_formed
    · apply RunsStmt.guardEffectFalse (MemoryEffect.scopeStable _)
      · core_pure_guard
      · intro ready first
        apply RunsStmt.guardEffectTrue (MemoryEffect.scopeStable _)
        · simp
        · core_pure_guard
        · intro selected second
          apply RunsStmt.letEffect (MemoryEffect.scopeStable _)
          · core_run
          · core_formed
          · apply RunsStmt.returnEffect
            apply RunsExpr.argumentsEffect
            · core_arguments
            · core_state current
              exact produces (input.reheap (after := current) (second.heap.trans first.heap))
                (by core_formed) (by change HeapBlockBasesUnique selected.heap; rw [second.heap, first.heap]; exact unique)
                (second.views.trans (first.views.trans noViews))

/-- Decode the actual token span, then emit precisely that integer. Unused
    context fields are left to callers; no decoder execution is assumed. -/
theorem actualInteger (input : IRIntegerLoweringProof.Input before) (unused : List Value)
    (number : Nat) (decoded : IRDecimalLoopProof.scan input.bytes input.length 0 .empty = .number number)
    (storage : Context before) (formed : before.CellsWellFormed)
    (unique : HeapBlockBasesUnique before.heap) (noViews : before.i32ArrayViews = []) :
    ∃ after, RunsExpr extractedProgram before (integerCall input unused storage.value storage.position)
      (.signed .i32 (storage.position + 1 : Nat)) after ∧
      Appended storage (integer (Int32.ofNat number).toBitVec) before after := by
  have fits : number < 2 ^ 31 := by
    have bound := IRDecimalLoopProof.scan_bounded input.bytes input.length 0 .empty trivial
    rw [decoded] at bound
    exact bound
  have represented : (Int32.ofNat number).toInt = number := by
    rw [Int32.toInt_ofNat']
    change (number : Int).bmod 4294967296 = number
    apply Int.bmod_eq_of_le <;> omega
  have produces : Produces (fun output position => literalCall output position (.IntegerValue (Int32.ofNat number)))
      (integer (Int32.ofNat number).toBitVec) := actualLiteral (.IntegerValue (Int32.ofNat number))
  core_call_framed (RunsExpr.callEffect (MemoryEffect.scopeStable _)) source as callee
  apply RunsStmt.letEffect (MemoryEffect.scopeStable _)
  · core_run
  · core_formed
  · apply RunsStmt.guardEffectTrue (MemoryEffect.scopeStable _)
    · simp
    · core_pure_guard
    · intro selected prefixFrame
      apply RunsStmt.letFramedEffect (MemoryEffect.scopeStable _)
      · apply RunsExpr.callPureArguments
        · core_arguments
        · core_state current
          have decodedRun := IRIntegerLoweringProof.actualDecimal (input.reheap (after := current) prefixFrame.heap)
            (by core_formed) (prefixFrame.views.trans noViews)
          dsimp only [IRIntegerLoweringProof.Input.reheap] at decodedRun
          rw [decoded] at decodedRun
          dsimp only [IRIntegerLoweringProof.loweredValue] at decodedRun
          exact decodedRun
      · intro ready valueFrame
        apply RunsStmt.guardEffectFalse (MemoryEffect.scopeStable _)
        · core_pure_guard
        · intro active guardFrame
          apply RunsStmt.returnEffect
          apply RunsExpr.argumentsEffect
          · core_arguments
          · have heap : active.heap = before.heap := guardFrame.heap.trans (valueFrame.heap.trans prefixFrame.heap)
            have views := guardFrame.views.trans (valueFrame.views.trans (prefixFrame.views.trans noViews))
            have produced := produces (storage.reheap (after := active) heap)
              (by core_formed) (by change HeapBlockBasesUnique active.heap; rw [heap]; exact unique) views
            have callEq : literalCall storage.value storage.position (.IntegerValue (Int32.ofNat number)) =
                .call Extracted.«lowering::body_event_write».Functions.«expression_value».core.id
                  [.value storage.value, .value (.signed .i32 storage.position),
                    .value (source_value Extracted.«ir::body_events».Types.«LiteralValue».«IntegerValue» [.signed .i32 number])] := by
              dsimp only [literalCall, literalValue]
              rw [represented]
              rfl
            change ∃ after, RunsExpr extractedProgram active
              (literalCall storage.value storage.position (.IntegerValue (Int32.ofNat number)))
              (.signed .i32 (storage.position + 1 : Nat)) after ∧
              Appended storage (integer (Int32.ofNat number).toBitVec) active after at produced
            rw [callEq] at produced
            exact produced

/-- Invalid decimal contents, including the positive-only overflow magnitude,
    reject before any output access. The output need not be valid storage. -/
theorem actualIntegerReject (input : IRIntegerLoweringProof.Input before) (unused : List Value)
    (output : Value) (position : Int)
    (invalid : IRIntegerLoweringProof.succeeded (IRDecimalLoopProof.scan input.bytes input.length 0 .empty) = false)
    (formed : before.CellsWellFormed) (noViews : before.i32ArrayViews = []) :
    ∃ after, RunsExpr extractedProgram before (integerCall input unused output position)
      (.signed .i32 (-1)) after ∧ PureFrame before after := by
  have rejected : IRIntegerLoweringProof.loweredValue
      (IRDecimalLoopProof.scan input.bytes input.length 0 .empty) = -1 := by
    cases result : IRDecimalLoopProof.scan input.bytes input.length 0 .empty <;>
      simp_all [IRIntegerLoweringProof.succeeded, IRIntegerLoweringProof.loweredValue]
  core_call_pure source as callee
  apply RunsStmt.letPure
  · core_run
  · core_formed
  · apply RunsStmt.guardPureTrue
    · simp
    · core_run
    · apply RunsStmt.letFramedPure
      · apply RunsExpr.callPureArguments
        · core_arguments
        · core_state current
          have decodedRun := IRIntegerLoweringProof.actualDecimal (input.reheap (after := current) rfl)
            (by core_formed) noViews
          dsimp only [IRIntegerLoweringProof.Input.reheap] at decodedRun
          rw [rejected] at decodedRun
          exact decodedRun
      · intro ready frame
        core_pure

#print axioms actualBoolean
#print axioms actualInteger
#print axioms actualIntegerReject

end IRLiteralLoweringProof
