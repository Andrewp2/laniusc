import verified_compiler.tests.direct_ir_literal_lowering
import verified_compiler.tests.direct_ir_result_type

namespace IRNegativeLoweringProof

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics IREventStoreProof IREventWriteProof
  IRDecimalProof IRIntegerLoweringProof IRLiteralLoweringProof

private def source := Extracted.«lowering::body_literal».Functions.«negative».core
private def minimumSource := Extracted.«lowering::constant_expression».Functions.«is_min_magnitude».core
def call (input : Input before) (unused : List Value) (output : Value) (position : Int) : Expr :=
  .call source.id [.value (integerContext input unused), .value (.signed .i32 input.tokenIndex),
    .value output, .value (.signed .i32 position)]

@[core_pure_rule] theorem actualMinimum (state : Accumulator) (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before (.call minimumSource.id [.value (resultValue state)])
      (.boolean (decide (state = .minimum))) after ∧ PureFrame before after := by
  cases state <;> dsimp only [resultValue] <;> simp only [reduceCtorEq, decide_true, decide_false]
  all_goals (core_call_pure minimumSource as callee; core_pure)

/-- Consecutive event slots; annotation separation is needed only when enabled. -/
structure Storage (before : State) where
  head : Context before
  tail : Context before
  same : tail.value = head.value
  next : tail.position = head.position + 1
  eventsApart : tail.eventBase + 40 ≤ head.eventBase
  typesApart : head.enabled = true → tail.typeBase + 16 ≤ head.typeBase
  planesApart : head.enabled = true →
    head.eventBase + 40 ≤ tail.typeBase ∨ tail.typeBase + 16 ≤ head.eventBase

theorem Storage.sameEnabled (storage : Storage before) : storage.tail.enabled = storage.head.enabled := by
  have selected := congrArg (fun value : Value => match value with
    | .structure _ fields => fields[2]?.getD Value.unit | _ => Value.unit) storage.same
  change Value.boolean storage.tail.enabled = Value.boolean storage.head.enabled at selected
  exact Value.boolean.inj selected

def Storage.reheap (storage : Storage before) (same : after.heap = before.heap) : Storage after := {
  storage with
  head := storage.head.reheap same
  tail := storage.tail.reheap same }

private def writeBody : Stmt := match source.body.getD .skip with
  | .letLocal _ _ _ (.sequence _ (.sequence _ body)) => body
  | _ => .skip

/-- Exact two append effects and the conditional child's I32 annotation. -/
def effect (storage : Storage state) (number : Nat) (before after : Heap) : Prop :=
  ∃ first second,
    appendHeapEffect storage.head.enabled storage.head.eventBase storage.head.typeBase negateEvent before first ∧
    appendHeapEffect storage.tail.enabled storage.tail.eventBase storage.tail.typeBase
      (integer (Int32.ofNat number).toBitVec) first second ∧
    IRResultTypeProof.Recorded (IRResultTypeProof.annotationSlot storage.tail) .I32 second after ∧
    NativeSnapshot 64 extractedProgram after eventType storage.head.eventBase negateEvent 40 ∧
    NativeSnapshot 64 extractedProgram after eventType storage.tail.eventBase (integer (Int32.ofNat number).toBitVec) 40

private theorem keepAfterAppend
    (snapshot : NativeSnapshot 64 extractedProgram before type pointer value size)
    (writes : appendHeapEffect enabled eventAddress typeAddress event before after)
    (events : pointer + size ≤ eventAddress ∨ eventAddress + 40 ≤ pointer)
    (types : enabled = true → pointer + size ≤ typeAddress ∨ typeAddress + 16 ≤ pointer) :
    NativeSnapshot 64 extractedProgram after type pointer value size := by
  obtain ⟨_, middle, first, last⟩ := writes
  have snapshot := snapshot.afterWrite first events
  cases enabled
  · simp only [Bool.false_eq_true, ↓reduceIte] at last
    subst after
    exact snapshot
  · simp only [↓reduceIte] at last
    exact snapshot.afterWrite last.2 (types rfl)

private theorem keepAfterRecord
    (snapshot : NativeSnapshot 64 extractedProgram before type pointer value size)
    (writes : IRResultTypeProof.Recorded slot kind before after)
    (types : slot.enabled = true → pointer + size ≤ slot.address ∨ slot.address + 16 ≤ pointer) :
    NativeSnapshot 64 extractedProgram after type pointer value size := by
  cases enabled : slot.enabled
  · simp only [IRResultTypeProof.Recorded, enabled, Bool.false_eq_true, ↓reduceIte] at writes
    subst after
    exact snapshot
  · simp only [IRResultTypeProof.Recorded, enabled, ↓reduceIte] at writes
    exact snapshot.afterWrite writes.2 (types enabled)

private theorem writeNumber (storage : Storage before) (number : Nat) (fits : number < 2 ^ 31)
    (formed : before.CellsWellFormed) (unique : HeapBlockBasesUnique before.heap) (noViews : before.i32ArrayViews = [])
    (outputFound : before.local? (source.argumentId 2) = some storage.head.value)
    (positionFound : before.local? (source.argumentId 3) = some (.signed .i32 storage.head.position))
    (literalFound : before.local? (source.bindingId 0) = some (resultValue (.number number))) :
    ∃ after, RunsStmt extractedProgram before writeBody (.returned (some (.signed .i32 (storage.head.position + 2 : Nat)))) after ∧
      MemoryEffect (effect storage number) before after := by
  have represented : (Int32.ofNat number).toInt = number := by
    rw [Int32.toInt_ofNat']; change (number : Int).bmod 4294967296 = number
    apply Int.bmod_eq_of_le <;> omega
  obtain ⟨first, unary, firstCells, firstWorld, firstViews, firstEffect⟩ :=
    actualNegate storage.head formed unique noViews
  rw [← storage.next] at unary
  let ready := first.bindLocal (source.bindingId 1) (.signed .i32 storage.tail.position)
  have readyFormed : ready.CellsWellFormed := (firstCells.after_cellsWellFormed formed).bindLocal _ _
  let tail : Context ready := storage.tail.afterAppend firstEffect
  obtain ⟨valued, valueRun, valueFrame⟩ := actualValue (.number number) readyFormed
  let active := tail.reheap (after := valued) valueFrame.heap
  have produces : Produces (fun output position => literalCall output position (.IntegerValue (Int32.ofNat number)))
      (integer (Int32.ofNat number).toBitVec) := actualLiteral (.IntegerValue (Int32.ofNat number))
  obtain ⟨second, literal, secondCells, secondWorld, secondViews, secondEffect⟩ :=
    produces active valueFrame.afterFormed (by rw [valueFrame.heap]; exact firstEffect.footprint.unique)
      (valueFrame.views.trans (firstViews.trans noViews))
  change RunsExpr extractedProgram valued
    (literalCall storage.tail.value storage.tail.position (.IntegerValue (Int32.ofNat number)))
    (.signed .i32 (storage.tail.position + 1 : Nat)) second at literal
  dsimp only [literalCall, literalValue] at literal
  rw [represented, storage.same] at literal
  let annotated := second.bindLocal (source.bindingId 2) (.signed .i32 (storage.tail.position + 1 : Nat))
  have annotatedFormed : annotated.CellsWellFormed :=
    (secondCells.after_cellsWellFormed valueFrame.afterFormed).bindLocal _ _
  let slot := IRResultTypeProof.annotationSlot (active.afterAppend (after := annotated) secondEffect)
  obtain ⟨recorded, recordRun, lastCells, lastWorld, lastViews, recordEffect⟩ :=
    IRResultTypeProof.actualRecord (events := .rawSlice eventType storage.tail.events storage.tail.capacity)
      slot .I32 (by decide) annotatedFormed secondEffect.footprint.unique
      (secondViews.trans (valueFrame.views.trans (firstViews.trans noViews)))
  change RunsExpr extractedProgram annotated
    (.call _ [.value storage.tail.value, .value (.signed .i32 storage.tail.position),
      .value (IRTypeRefProof.referenceValue .I32)]) (.boolean true) recorded at recordRun
  rw [storage.same] at recordRun
  have body : RunsStmt extractedProgram before writeBody
      (.returned (some (.signed .i32 (storage.head.position + 2 : Nat))))
      (restoreLocals first (restoreLocals second recorded)) := by
    rw [show storage.head.position + 2 = storage.tail.position + 1 by have := storage.next; omega]
    core_stmt_forward
  have frame := firstCells.trans ((FreshCellFrame.bindLocal first _ _).trans
    ((valueFrame.cells.trans secondCells).trans ((FreshCellFrame.bindLocal second _ _).trans lastCells)))
  have header : NativeSnapshot 64 extractedProgram valued.heap eventType storage.head.eventBase negateEvent 40 := by
    rw [valueFrame.heap]
    exact firstEffect.1
  have headSecond := keepAfterAppend header secondEffect (Or.inr storage.eventsApart)
    (fun enabled => storage.planesApart (storage.sameEnabled.symm.trans enabled))
  have headAfter := keepAfterRecord headSecond recordEffect
    (fun enabled => storage.planesApart (storage.sameEnabled.symm.trans enabled))
  have tailAfter := keepAfterRecord secondEffect.1 recordEffect storage.tail.separate
  have secondStart : appendHeapEffect storage.tail.enabled storage.tail.eventBase storage.tail.typeBase
      (integer (Int32.ofNat number).toBitVec) first.heap second.heap := by
    change appendHeapEffect _ _ _ _ valued.heap second.heap at secondEffect
    rwa [valueFrame.heap] at secondEffect
  exact ⟨_, body, frame, lastWorld.trans (secondWorld.trans (valueFrame.world.trans firstWorld)),
    lastViews.trans (secondViews.trans (valueFrame.views.trans firstViews)), first.heap, second.heap,
    firstEffect, secondStart, recordEffect, headAfter, tailAfter⟩

/-- Ordinary negative literals retain the source-shaped unary node and its
    positive child. Both events come from the actual source token's digits. -/
theorem actualNumber (input : Input before) (unused : List Value) (number : Nat)
    (decoded : IRDecimalLoopProof.scan input.bytes input.length 0 .empty = .number number)
    (storage : Storage before) (formed : before.CellsWellFormed)
    (unique : HeapBlockBasesUnique before.heap) (noViews : before.i32ArrayViews = []) :
    ∃ after, RunsExpr extractedProgram before (call input unused storage.head.value storage.head.position)
      (.signed .i32 (storage.head.position + 2 : Nat)) after ∧ MemoryEffect (effect storage number) before after := by
  have fits : number < 2 ^ 31 := by
    have bound := IRDecimalLoopProof.scan_bounded input.bytes input.length 0 .empty trivial
    rw [decoded] at bound
    exact bound
  core_call_framed (RunsExpr.callEffect (MemoryEffect.scopeStable _)) source as callee
  apply RunsStmt.letFramedEffect (MemoryEffect.scopeStable _)
  · apply RunsExpr.callPureArguments
    · core_arguments
    · core_state current
      have parsed := IRIntegerLoweringProof.actualInteger (input.reheap (after := current) rfl) (by core_formed) noViews
      dsimp only [Input.reheap] at parsed
      rw [decoded] at parsed
      exact parsed
  · intro ready decodedFrame
    apply RunsStmt.guardEffectFalse (MemoryEffect.scopeStable _)
    · apply RunsExpr.callPureArguments
      · core_arguments
      · exact actualMinimum (.number number) (by core_formed)
    · intro ordinary minimumFrame
      apply RunsStmt.guardEffectFalse (MemoryEffect.scopeStable _)
      · apply RunsExpr.unaryPure
        · apply RunsExpr.callPureArguments
          · core_arguments
          · exact actualSucceeded (.number number) (by core_formed)
        · rfl
      · intro active successFrame
        have heap : active.heap = before.heap := successFrame.heap.trans (minimumFrame.heap.trans decodedFrame.heap)
        exact writeNumber (storage.reheap heap) number fits (by core_formed)
          (by rw [heap]; exact unique)
          (successFrame.views.trans (minimumFrame.views.trans (decodedFrame.views.trans noViews)))
          (by core_local) (by core_local) (by core_local)

/-- The signed minimum uses its representable negative value directly,
    rather than ever constructing the unrepresentable positive i32 operand. -/
theorem actualSignedMinimum (input : Input before) (unused : List Value)
    (decoded : IRDecimalLoopProof.scan input.bytes input.length 0 .empty = .minimum)
    (storage : Context before) (formed : before.CellsWellFormed)
    (unique : HeapBlockBasesUnique before.heap) (noViews : before.i32ArrayViews = []) :
    ∃ after, RunsExpr extractedProgram before (call input unused storage.value storage.position)
      (.signed .i32 (storage.position + 1 : Nat)) after ∧ Appended storage (integer (-2147483648)) before after := by
  have produces : Produces (fun output position => literalCall output position (.IntegerValue (-2147483648)))
      (integer (-2147483648)) := actualLiteral (.IntegerValue (-2147483648))
  core_call_framed (RunsExpr.callEffect (MemoryEffect.scopeStable _)) source as callee
  apply RunsStmt.letFramedEffect (MemoryEffect.scopeStable _)
  · apply RunsExpr.callPureArguments
    · core_arguments
    · core_state current
      have parsed := IRIntegerLoweringProof.actualInteger (input.reheap (after := current) rfl) (by core_formed) noViews
      dsimp only [Input.reheap] at parsed
      rw [decoded] at parsed
      exact parsed
  · intro ready decodedFrame
    apply RunsStmt.guardEffectTrue (MemoryEffect.scopeStable _)
    · simp
    · apply RunsExpr.callPureArguments
      · core_arguments
      · exact actualMinimum .minimum (by core_formed)
    · intro active minimumFrame
      apply RunsStmt.returnEffect
      apply RunsExpr.argumentsEffect
      · core_arguments
      · have heap : active.heap = before.heap := minimumFrame.heap.trans decodedFrame.heap
        exact produces (storage.reheap (after := active) heap) (by core_formed)
          (by rw [heap]; exact unique)
          (minimumFrame.views.trans (decodedFrame.views.trans noViews))

/-- Malformed magnitudes reject before touching arbitrary output values. -/
theorem actualReject (input : Input before) (unused : List Value) (output : Value) (position : Int)
    (invalid : IRDecimalLoopProof.scan input.bytes input.length 0 .empty = .empty ∨
      IRDecimalLoopProof.scan input.bytes input.length 0 .empty = .rejected)
    (formed : before.CellsWellFormed) (noViews : before.i32ArrayViews = []) :
    ∃ after, RunsExpr extractedProgram before (call input unused output position)
      (.signed .i32 (-1)) after ∧ PureFrame before after := by
  rcases invalid with decoded | decoded
  all_goals
    core_call_pure source as callee
    apply RunsStmt.letFramedPure
    · apply RunsExpr.callPureArguments
      · core_arguments
      · core_state current
        have parsed := IRIntegerLoweringProof.actualInteger (input.reheap (after := current) rfl) (by core_formed) noViews
        dsimp only [Input.reheap] at parsed
        rw [decoded] at parsed
        exact parsed
    · intro ready frame
      core_pure

#print axioms actualMinimum
#print axioms writeNumber
#print axioms actualNumber
#print axioms actualSignedMinimum
#print axioms actualReject

end IRNegativeLoweringProof
