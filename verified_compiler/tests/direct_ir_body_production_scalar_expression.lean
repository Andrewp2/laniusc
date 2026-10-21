import verified_compiler.tests.direct_ir_body_production_scalar_lowering
import verified_compiler.tests.direct_ir_body_production_scalar_emit
import verified_compiler.tests.direct_ir_body_production_scalar_token
import verified_compiler.tests.direct_ir_literal_lowering

namespace IRBodyProductionScalar

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics IRBodyProductionInputs
open IRTypeCacheFillProof (Literal)

variable {before after : State}

def untypedSource := Extracted.«lowering::body_expression».Functions.«expression_untyped».core
def untypedCall (input : Inputs) (workspace : Workspace) (locals : Value)
    (count root depth : Nat) (output : Value) (position : Nat) : Expr :=
  .call untypedSource.id ([bodyContext input workspace locals, .signed .i32 count,
    .signed .i32 root, output, .signed .i32 position, .signed .i32 depth].map Expr.value)
def literalEmitCall (context node output : Value) (position : Nat) : Expr :=
  .call Extracted.«lowering::body_literal».Functions.«emit».core.id
    [.value context, .value node, .value output, .value (.signed .i32 position)]
def negativeEmitCall (context output : Value) (token position : Nat) : Expr :=
  .call Extracted.«lowering::body_literal».Functions.«negative».core.id
    [.value context, .value (.signed .i32 token), .value output, .value (.signed .i32 position)]

/-- The actual untyped dispatch reads the genuinely produced literal node.
    Its emitter continuation is discharged below or by the decimal contract. -/
theorem actualUntypedLiteralWith (input : Inputs) (workspace : Workspace) (locals : Value)
    (storage : ScalarStorage workspace before slots) (count root depth position next : Nat)
    (inside : root < count) (bound : count ≤ storage.arena.capacity) (positive : 0 < depth)
    (literal : Literal) (fields : Fin 4 → Value)
    (native : readRawSliceIndex extractedProgram before expressionNodeType storage.arena.nodes storage.arena.capacity root =
      .ok (literal.value fields))
    (emit : ∀ {state : State}, state.heap = before.heap → state.CellsWellFormed →
      state.i32ArrayViews = before.i32ArrayViews → ∃ after,
      RunsExpr extractedProgram state (literalEmitCall (bodyContext input workspace locals)
        (literal.value fields) output position) (.signed .i32 next) after ∧ MemoryEffect relation state after)
    (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before
      (untypedCall input workspace locals count root depth output position) (.signed .i32 next) after ∧
      MemoryEffect relation before after := by
  simp only [Literal.value] at native
  have nodeRead {state : State} (same : state.heap = before.heap) :
      readRawSliceIndex extractedProgram state expressionNodeType storage.arena.nodes storage.arena.capacity root =
        .ok (literal.value fields) := by
    simpa only [Literal.value, readRawSliceIndex, same] using native
  core_facts [storage, storage.arena]
  core_call_framed (RunsExpr.callEffect (MemoryEffect.scopeStable _)) untypedSource as callee
  apply RunsStmt.letEffect (MemoryEffect.scopeStable _) (value := storage.arena.value)
  · rw [← storage.arenaValue]; core_run
  · core_formed
  · apply RunsStmt.letEffect (MemoryEffect.scopeStable _)
      (value := .rawSlice expressionNodeType storage.arena.nodes storage.arena.capacity)
    · core_run
    · core_formed
    · apply RunsStmt.letFramedEffect (MemoryEffect.scopeStable _)
      · core_pure_expr
      · intro allocated allocationFrame
        apply RunsStmt.guardEffectFalse (MemoryEffect.scopeStable _)
        · core_pure_guard
        · intro bounded boundFrame
          apply RunsStmt.letFramedEffect (MemoryEffect.scopeStable _)
          · core_pure_expr
          · intro selected nodeFrame
            apply RunsStmt.letFramedEffect (MemoryEffect.scopeStable _)
            · core_pure_expr
            · intro kinded kindFrame
              apply RunsStmt.guardEffectTrue (MemoryEffect.scopeStable _) (by intro impossible; cases impossible)
              · core_pure_guard
              · intro literalState literalFrame
                apply RunsStmt.returnEffect
                apply RunsExpr.callFramedEffectArguments (MemoryEffect.scopeStable _)
                · core_pure_arguments
                · intro arguments argumentFrame
                  exact emit (by core_frame) (by core_formed) (by core_frame)

/-- Boolean emission consumes the real body-literal producer, not an assumed
    writer run or bytes supplied by the final caller. -/
theorem actualUntypedBoolean (input : Inputs) (workspace : Workspace) (locals : Value)
    (storage : ScalarStorage workspace before slots) (count root depth : Nat)
    (inside : root < count) (bound : count ≤ storage.arena.capacity) (positive : 0 < depth)
    (flag : Bool) (token : Int32) (output : IREventStoreProof.Context before)
    (native : readRawSliceIndex extractedProgram before expressionNodeType storage.arena.nodes storage.arena.capacity root =
      .ok (IRLiteralLoweringProof.booleanNode flag token))
    (formed : before.CellsWellFormed) (unique : HeapBlockBasesUnique before.heap) (noViews : before.i32ArrayViews = []) :
    ∃ after, RunsExpr extractedProgram before
      (untypedCall input workspace locals count root depth output.value output.position)
      (.signed .i32 (output.position + 1 : Nat)) after ∧
      MemoryEffect (IREventStoreProof.appendHeapEffect output.enabled output.eventBase output.typeBase
        (IREventStoreProof.boolean flag)) before after := by
  let fields : Fin 4 → Value := fun i => if i = 2 then .signed .i32 token.toInt else .signed .i32 (-1)
  have sameNode : (Literal.boolean flag).value fields = IRLiteralLoweringProof.booleanNode flag token := by
    cases flag <;> rfl
  apply actualUntypedLiteralWith input workspace locals storage count root depth output.position (output.position + 1)
    inside bound positive (.boolean flag) fields (by simpa only [sameNode] using native) ?_ formed
  intro state same cells views
  have produced := IRLiteralLoweringProof.actualBoolean (bodyContext input workspace locals) flag token
    (output.reheap same) cells (by rw [same]; exact unique) (views.trans noViews)
  change ∃ after, RunsExpr extractedProgram state
    (literalEmitCall (bodyContext input workspace locals) (IRLiteralLoweringProof.booleanNode flag token)
      output.value output.position) (.signed .i32 (output.position + 1 : Nat)) after ∧
    MemoryEffect (IREventStoreProof.appendHeapEffect output.enabled output.eventBase output.typeBase
      (IREventStoreProof.boolean flag)) state after at produced
  simpa only [literalEmitCall, sameNode] using produced

/-- Decimal emission uses the original token's native row and grammar-valid
    spelling to derive the decoder result and execute the actual literal writer. -/
theorem actualUntypedInteger (input : Inputs) (workspace : Workspace) (locals : Value)
    (storage : ScalarStorage workspace before slots) (count root depth : Nat)
    (inside : root < count) (bound : count ≤ storage.arena.capacity) (positive : 0 < depth)
    (token : OriginalToken input before index text integerToken)
    (spelled : DecimalSpelling (ascii text) magnitude) (magnitudeBound : magnitude < 2 ^ 31)
    (output : IREventStoreProof.Context before)
    (native : readRawSliceIndex extractedProgram before expressionNodeType storage.arena.nodes storage.arena.capacity root =
      .ok (IRLiteralLoweringProof.integerNode index))
    (formed : before.CellsWellFormed) (unique : HeapBlockBasesUnique before.heap) (noViews : before.i32ArrayViews = []) :
    ∃ after, RunsExpr extractedProgram before
      (untypedCall input workspace locals count root depth output.value output.position)
      (.signed .i32 (output.position + 1 : Nat)) after ∧
      MemoryEffect (IREventStoreProof.appendHeapEffect output.enabled output.eventBase output.typeBase
        (IREventStoreProof.integer (Int32.ofNat magnitude).toBitVec)) before after := by
  let fields : Fin 4 → Value := fun i => if i = 2 then .signed .i32 index else .signed .i32 (-1)
  have sameNode : Literal.integer.value fields = IRLiteralLoweringProof.integerNode index := rfl
  apply actualUntypedLiteralWith input workspace locals storage count root depth output.position (output.position + 1)
    inside bound positive Literal.integer fields (by simpa only [sameNode] using native) ?_ formed
  intro state same cells views
  have reads : HeapReads before.heap state.heap := by rw [same]; exact HeapReads.refl _
  let reached := token.afterReads reads
  let scanner := reached.integerInput spelled
  have produced := actualDecimalEmission scanner (bodyContextSuffix input workspace locals)
    spelled (by simp only [scanner, OriginalToken.integerInput, ascii, List.length_map]) (fun _ _ => rfl)
    magnitudeBound (output.reheap same) cells (by rw [same]; exact unique) (views.trans noViews)
  have context := reached.integerContext spelled workspace locals
  change ∃ after, RunsExpr extractedProgram state
    (.call Extracted.«lowering::body_literal».Functions.«emit».core.id
      [.value (IRLiteralLoweringProof.integerContext scanner (bodyContextSuffix input workspace locals)),
        .value (IRLiteralLoweringProof.integerNode index), .value output.value, .value (.signed .i32 output.position)])
    (.signed .i32 (output.position + 1 : Nat)) after ∧
    MemoryEffect (IREventStoreProof.appendHeapEffect output.enabled output.eventBase output.typeBase
      (IREventStoreProof.integer (Int32.ofNat magnitude).toBitVec)) state after at produced
  rw [context] at produced
  simpa only [literalEmitCall, sameNode] using produced

/-- The real unary dispatch recognizes the produced integer operand and
    takes the literal-negative path before ordinary positive-i32 emission.
    This same path handles the signed minimum. -/
theorem actualUntypedNegativeWith (input : Inputs) (workspace : Workspace) (locals : Value)
    (storage : ScalarStorage workspace before 2) (depth token position next : Nat) (positive : 1 < depth)
    (parentRead : readRawSliceIndex extractedProgram before expressionNodeType storage.arena.nodes storage.arena.capacity 1 =
      .ok (IRUnaryInferenceProof.nodeValue .negate 0 (fun _ => .signed .i32 (-1))))
    (leafRead : readRawSliceIndex extractedProgram before expressionNodeType storage.arena.nodes storage.arena.capacity 0 =
      .ok (IRLiteralLoweringProof.integerNode token))
    (emit : ∀ {state : State}, state.heap = before.heap → state.CellsWellFormed →
      state.i32ArrayViews = before.i32ArrayViews → ∃ after,
      RunsExpr extractedProgram state (negativeEmitCall (bodyContext input workspace locals) output token position)
        (.signed .i32 next) after ∧ MemoryEffect relation state after)
    (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before
      (untypedCall input workspace locals 2 1 depth output position) (.signed .i32 next) after ∧
      MemoryEffect relation before after := by
  simp only [IRUnaryInferenceProof.nodeValue, IRUnaryInferenceProof.Operation.sourceValue,
    IRLiteralLoweringProof.integerNode] at parentRead leafRead
  have parentHere {state : State} (same : state.heap = before.heap) :
      readRawSliceIndex extractedProgram state expressionNodeType storage.arena.nodes storage.arena.capacity 1 =
        .ok (IRUnaryInferenceProof.nodeValue .negate 0 (fun _ => .signed .i32 (-1))) := by
    simpa only [IRUnaryInferenceProof.nodeValue, IRUnaryInferenceProof.Operation.sourceValue,
      readRawSliceIndex, same] using parentRead
  have leafHere {state : State} (same : state.heap = before.heap) :
      readRawSliceIndex extractedProgram state expressionNodeType storage.arena.nodes storage.arena.capacity 0 =
        .ok (IRLiteralLoweringProof.integerNode token) := by
    simpa only [IRLiteralLoweringProof.integerNode, readRawSliceIndex, same] using leafRead
  have operation {state : State} (cells : state.CellsWellFormed) :
      ∃ after, RunsExpr extractedProgram state
        (.call Extracted.«lowering::body_expression».Functions.«unary_operation».core.id
          [.value IRUnaryInferenceProof.Operation.negate.sourceValue])
        IRUnaryInferenceProof.Operation.negate.targetValue after ∧ PureFrame state after := by
    simpa only [IRUnaryInferenceProof.operationSource] using IRUnaryInferenceProof.actualOperation .negate cells
  core_facts [storage, storage.arena]
  core_call_framed (RunsExpr.callEffect (MemoryEffect.scopeStable _)) untypedSource as callee
  apply RunsStmt.letEffect (MemoryEffect.scopeStable _) (value := storage.arena.value)
  · rw [← storage.arenaValue]; core_run
  · core_formed
  · apply RunsStmt.letEffect (MemoryEffect.scopeStable _)
      (value := .rawSlice expressionNodeType storage.arena.nodes storage.arena.capacity)
    · core_run
    · core_formed
    · apply RunsStmt.letFramedEffect (MemoryEffect.scopeStable _)
      · core_pure_expr
      · intro allocated allocationFrame
        apply RunsStmt.guardEffectFalse (MemoryEffect.scopeStable _)
        · core_pure_guard
        · intro bounded boundFrame
          apply RunsStmt.letFramedEffect (MemoryEffect.scopeStable _)
          · core_pure_expr
          · intro selected nodeFrame
            apply RunsStmt.letFramedEffect (MemoryEffect.scopeStable _)
            · core_pure_expr
            · intro kinded kindFrame
              apply RunsStmt.guardEffectFalse (MemoryEffect.scopeStable _)
              · core_pure_guard
              · intro notLiteral literalFrame
                apply RunsStmt.guardEffectTrue (MemoryEffect.scopeStable _) (by intro impossible; cases impossible)
                · core_pure_guard
                · intro unaryState unaryFrame
                  apply RunsStmt.letFramedEffect (MemoryEffect.scopeStable _)
                    (value := IRUnaryInferenceProof.Operation.targetValue .negate)
                  · core_pure_expr
                  · intro operated operationFrame
                    apply RunsStmt.guardEffectFalse (MemoryEffect.scopeStable _)
                    · core_pure_guard
                    · intro supported supportedFrame
                      apply RunsStmt.letFramedEffect (MemoryEffect.scopeStable _) (value := .signed .i32 0)
                      · core_pure_expr
                      · intro operandState operandFrame
                        apply RunsStmt.guardEffectTrue (MemoryEffect.scopeStable _) (by intro impossible; cases impossible)
                        · core_pure_guard
                        · intro integerState integerFrame
                          apply RunsStmt.guardEffectFalse (MemoryEffect.scopeStable _)
                          · core_pure_guard
                          · intro sufficient depthFrame
                            apply RunsStmt.returnEffect
                            apply RunsExpr.callFramedEffectArguments (MemoryEffect.scopeStable _)
                            · core_pure_arguments
                            · intro arguments argumentFrame
                              exact emit (by core_frame) (by core_formed) (by core_frame)

/-- The two writer contexts come from one original descriptor and its used
    permissions; plane order is unrestricted beyond actual separation. -/
private def negativeStorage {output : IREventStoreProof.Context before}
    (permissions : OutputPermissions output used) (position : Nat)
    (headInside : position < used) (tailInside : position + 1 < used) : IRNegativeLoweringProof.Storage before := {
  head := permissions.slot position headInside (fun _ _ room => room)
  tail := permissions.slot (position + 1) tailInside (fun _ _ room => room)
  same := rfl
  next := rfl
  eventsApart := permissions.eventOrder position (position + 1) headInside tailInside (by omega)
  typesApart := fun enabled => permissions.typeOrder enabled position (position + 1) headInside tailInside (by omega)
  planesApart := fun enabled => permissions.planes enabled position (position + 1) headInside tailInside }

theorem actualUntypedNegative (input : Inputs) (workspace : Workspace) (locals : Value)
    {output : IREventStoreProof.Context before}
    (storage : ScalarStorage workspace before 2) (depth position : Nat) (positive : 1 < depth)
    (token : OriginalToken input before index text integerToken)
    (spelled : DecimalSpelling (ascii text) magnitude) (magnitudeBound : magnitude < 2 ^ 31)
    (permissions : OutputPermissions output used) (headInside : position < used) (tailInside : position + 1 < used)
    (parentRead : readRawSliceIndex extractedProgram before expressionNodeType storage.arena.nodes storage.arena.capacity 1 =
      .ok (IRUnaryInferenceProof.nodeValue .negate 0 (fun _ => .signed .i32 (-1))))
    (leafRead : readRawSliceIndex extractedProgram before expressionNodeType storage.arena.nodes storage.arena.capacity 0 =
      .ok (IRLiteralLoweringProof.integerNode index))
    (formed : before.CellsWellFormed) (unique : HeapBlockBasesUnique before.heap) (noViews : before.i32ArrayViews = []) :
    ∃ after, RunsExpr extractedProgram before
      (untypedCall input workspace locals 2 1 depth output.value position)
      (.signed .i32 (position + 2 : Nat)) after ∧
      MemoryEffect (IRNegativeLoweringProof.effect (negativeStorage permissions position headInside tailInside) magnitude) before after := by
  apply actualUntypedNegativeWith input workspace locals storage depth index position (position + 2) positive
    parentRead leafRead ?_ formed
  intro state same cells views
  have reads : HeapReads before.heap state.heap := by rw [same]; exact HeapReads.refl _
  let reached := token.afterReads reads
  let scanner := reached.integerInput spelled
  let writer := negativeStorage permissions position headInside tailInside
  have produced := actualNegativeEmission scanner (bodyContextSuffix input workspace locals)
    spelled (by simp only [scanner, OriginalToken.integerInput, ascii, List.length_map]) (fun _ _ => rfl)
    magnitudeBound (writer.reheap same) cells (by rw [same]; exact unique) (views.trans noViews)
  have context := reached.integerContext spelled workspace locals
  change ∃ after, RunsExpr extractedProgram state
    (.call Extracted.«lowering::body_literal».Functions.«negative».core.id
      [.value (IRLiteralLoweringProof.integerContext scanner (bodyContextSuffix input workspace locals)),
        .value (.signed .i32 index), .value output.value, .value (.signed .i32 position)])
    (.signed .i32 (position + 2 : Nat)) after ∧
    MemoryEffect (IRNegativeLoweringProof.effect writer magnitude) state after at produced
  rw [context] at produced
  exact produced

theorem actualUntypedMinimum (input : Inputs) (workspace : Workspace) (locals : Value)
    (storage : ScalarStorage workspace before 2) (depth : Nat) (positive : 1 < depth)
    (token : OriginalToken input before index text integerToken) (spelled : DecimalSpelling (ascii text) (2 ^ 31))
    (output : IREventStoreProof.Context before)
    (parentRead : readRawSliceIndex extractedProgram before expressionNodeType storage.arena.nodes storage.arena.capacity 1 =
      .ok (IRUnaryInferenceProof.nodeValue .negate 0 (fun _ => .signed .i32 (-1))))
    (leafRead : readRawSliceIndex extractedProgram before expressionNodeType storage.arena.nodes storage.arena.capacity 0 =
      .ok (IRLiteralLoweringProof.integerNode index))
    (formed : before.CellsWellFormed) (unique : HeapBlockBasesUnique before.heap) (noViews : before.i32ArrayViews = []) :
    ∃ after, RunsExpr extractedProgram before
      (untypedCall input workspace locals 2 1 depth output.value output.position)
      (.signed .i32 (output.position + 1 : Nat)) after ∧
      MemoryEffect (IREventStoreProof.appendHeapEffect output.enabled output.eventBase output.typeBase
        (IREventStoreProof.integer (-2147483648))) before after := by
  apply actualUntypedNegativeWith input workspace locals storage depth index output.position (output.position + 1) positive
    parentRead leafRead ?_ formed
  intro state same cells views
  have reads : HeapReads before.heap state.heap := by rw [same]; exact HeapReads.refl _
  let reached := token.afterReads reads
  let scanner := reached.integerInput spelled
  have produced := actualMinimumEmission scanner (bodyContextSuffix input workspace locals)
    spelled (by simp only [scanner, OriginalToken.integerInput, ascii, List.length_map]) (fun _ _ => rfl)
    (output.reheap same) cells (by rw [same]; exact unique) (views.trans noViews)
  have context := reached.integerContext spelled workspace locals
  change ∃ after, RunsExpr extractedProgram state
    (.call Extracted.«lowering::body_literal».Functions.«negative».core.id
      [.value (IRLiteralLoweringProof.integerContext scanner (bodyContextSuffix input workspace locals)),
        .value (.signed .i32 index), .value output.value, .value (.signed .i32 output.position)])
    (.signed .i32 (output.position + 1 : Nat)) after ∧
    MemoryEffect (IREventStoreProof.appendHeapEffect output.enabled output.eventBase output.typeBase
      (IREventStoreProof.integer (-2147483648))) state after at produced
  rw [context] at produced
  exact produced

#print axioms actualUntypedLiteralWith
#print axioms actualUntypedBoolean
#print axioms actualUntypedInteger
#print axioms actualUntypedNegativeWith
#print axioms actualUntypedNegative
#print axioms actualUntypedMinimum

end IRBodyProductionScalar
