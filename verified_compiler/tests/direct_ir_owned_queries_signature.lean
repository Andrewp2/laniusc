import verified_compiler.tests.direct_ir_owned_inputs_signature
import Lanius.Core.Bindings

namespace IRBodyOwnedInputs

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics IRBodyProductionInputs

private def contains := Extracted.«lowering::signature_index».Functions.«contains».core
private def hasShape := Extracted.«lowering::signature_index».Functions.«has_shape».core
private def hasFunction := Extracted.«lowering::body_lookup».Functions.«has_function_signature».core

/-- Signed guards reject without touching any signature row. -/
@[core_pure_rule] theorem actualSignatureOutside (index : SignatureIndex) (query : Int32)
    (outside : query.toInt ≤ -1 ∨ index.count.toInt ≤ query.toInt)
    (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before (.call contains.id
      [.value index.value, .value (.signed .i32 query.toInt)]) (.boolean false) after ∧ PureFrame before after := by
  core_call_pure contains as callee
  core_pure

/-- ID mismatch is an actual false result, not excluded from native storage. -/
@[core_pure_rule] theorem actualSignatureContainsAt (index : SignatureIndex) (query : Int32)
    (bounds : 0 ≤ query.toInt ∧ query.toInt < index.count.toInt)
    (native : NativeSignatureSlot index before.heap query.toInt.toNat)
    (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before (.call contains.id
      [.value index.value, .value (.signed .i32 query.toInt)])
      (.boolean (decide (native.entry.id.toInt = query.toInt))) after ∧ PureFrame before after := by
  have nonnegative := bounds.1
  have bounded := bounds.2
  have cast : (query.toInt.toNat : Int) = query.toInt := Int.toNat_of_nonneg bounds.1
  have read := native.read (before := before)
  core_call_pure contains as callee
  apply RunsStmt.guardPureFalse
  · core_run
  · apply RunsStmt.letPure
    · core_run
    · core_formed
    · core_state entries
      have heapSame : entries.heap = before.heap := rfl
      have currentRead : readRawSliceIndex extractedProgram entries signatureType
          index.address index.length query.toInt.toNat = .ok native.entry.value := by
        simpa only [readRawSliceIndex, heapSame] using read
      have queryFound : entries.local? (contains.argumentId 1) = some (.signed .i32 query.toInt) := by
        core_local
      have entryRun : RunsExpr extractedProgram entries
          (.index (.local (contains.bindingId 0)) (.local (contains.argumentId 1)))
          native.entry.value entries := by
        apply RunsExpr.ofStable
        · exact StableExpr.rawSliceRead (.local (by core_local))
            (.local (by simpa only [cast] using queryFound)) currentRead
        · rfl
      have idRun := RunsExpr.field (fields := [.signed .i32 native.entry.id.toInt,
        kindValue native.entry.kind, shapeValue native.entry.shape, .signed .i32 native.entry.arity.toInt,
        IRTypeRefProof.referenceValue native.entry.result, .signed .i32 (native.entry.starts 0).toInt,
        .signed .i32 (native.entry.starts 1).toInt, .signed .i32 (native.entry.starts 2).toInt])
        entryRun (fieldId := 0) (by rfl)
      exact ⟨entries, RunsStmt.returnValue (RunsExpr.binary idRun
        (RunsExpr.ofStable (StableExpr.local queryFound) rfl) (by decide) (by rfl)),
        PureFrame.refl (by core_formed)⟩

private theorem actualSignatureShapeMissing (index : SignatureIndex) (query : Int32) (shape : SignatureShape)
    (absent : ∀ {state : State}, state.heap = before.heap → state.CellsWellFormed →
      ∃ after, RunsExpr extractedProgram state (.call contains.id
        [.value index.value, .value (.signed .i32 query.toInt)]) (.boolean false) after ∧ PureFrame state after)
    (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before (.call hasShape.id
      [.value index.value, .value (.signed .i32 query.toInt), .value (shapeValue shape)])
      (.boolean false) after ∧ PureFrame before after := by
  core_call_pure hasShape as callee
  core_pure

@[core_pure_rule] theorem actualSignatureShapeOutside (index : SignatureIndex) (query : Int32)
    (shape : SignatureShape) (outside : query.toInt ≤ -1 ∨ index.count.toInt ≤ query.toInt)
    (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before (.call hasShape.id
      [.value index.value, .value (.signed .i32 query.toInt), .value (shapeValue shape)])
      (.boolean false) after ∧ PureFrame before after :=
  actualSignatureShapeMissing index query shape (fun _ cells => actualSignatureOutside index query outside cells) formed

@[core_pure_rule] theorem actualSignatureShapeAt (index : SignatureIndex) (query : Int32)
    (shape : SignatureShape) (bounds : 0 ≤ query.toInt ∧ query.toInt < index.count.toInt)
    (native : NativeSignatureSlot index before.heap query.toInt.toNat)
    (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before (.call hasShape.id
      [.value index.value, .value (.signed .i32 query.toInt), .value (shapeValue shape)])
      (.boolean (decide (native.entry.id.toInt = query.toInt) && shapeSame native.entry.shape shape)) after ∧
      PureFrame before after := by
  have cast : (query.toInt.toNat : Int) = query.toInt := Int.toNat_of_nonneg bounds.1
  have read {state : State} (same : state.heap = before.heap) :
      readRawSliceIndex extractedProgram state signatureType index.address index.length query.toInt.toNat =
        .ok native.entry.value := by
    simpa only [readRawSliceIndex, same] using native.read (before := before)
  have contained {state : State} (same : state.heap = before.heap) (cells : state.CellsWellFormed) :
      ∃ after, RunsExpr extractedProgram state (.call contains.id
        [.value index.value, .value (.signed .i32 query.toInt)])
        (.boolean (decide (native.entry.id.toInt = query.toInt))) after ∧ PureFrame state after := by
    exact actualSignatureContainsAt index query bounds
      { native with snapshot := by rw [same]; exact native.snapshot } cells
  have equality : evalBinaryValue extractedProgram.target .equal (shapeValue native.entry.shape) (shapeValue shape) =
      .ok (.boolean (shapeSame native.entry.shape shape)) := by
    cases native.entry.shape <;> cases shape <;> rfl
  by_cases present : native.entry.id.toInt = query.toInt
  · have presentBool : decide (native.entry.id.toInt = query.toInt) = true := decide_eq_true present
    rw [presentBool, Bool.true_and]
    core_call_pure hasShape as callee
    have calleeHeap : callee.heap = before.heap := rfl
    apply RunsStmt.guardFramedFalse
    · apply RunsExpr.unaryPure (value := .boolean true)
      · apply RunsExpr.callPureArguments (values := [index.value, .signed .i32 query.toInt])
        · core_arguments
        · change ∃ after, RunsExpr extractedProgram callee
              (.call 1449 [.value index.value, .value (.signed .i32 query.toInt)])
              (.boolean true) after ∧ PureFrame callee after
          have actual := contained (state := callee) calleeHeap (by core_formed)
          change ∃ after, RunsExpr extractedProgram callee
              (.call 1449 [.value index.value, .value (.signed .i32 query.toInt)])
              (.boolean (decide (native.entry.id.toInt = query.toInt))) after ∧ PureFrame callee after at actual
          simpa only [presentBool] using actual
      · rfl
    · intro middle frame
      apply RunsStmt.letPure
      · core_run
      · core_formed
      · core_state entries
        have heapSame : entries.heap = before.heap := frame.heap.trans calleeHeap
        have currentRead := read heapSame
        have queryFound : entries.local? (hasShape.argumentId 1) = some (.signed .i32 query.toInt) := by
          core_local
        have entryRun : RunsExpr extractedProgram entries
            (.index (.local (hasShape.bindingId 0)) (.local (hasShape.argumentId 1)))
            native.entry.value entries := by
          apply RunsExpr.ofStable
          · exact StableExpr.rawSliceRead (.local (by core_local))
              (.local (by simpa only [cast] using queryFound)) currentRead
          · rfl
        have shapeRun := RunsExpr.field (fields := [.signed .i32 native.entry.id.toInt,
          kindValue native.entry.kind, shapeValue native.entry.shape, .signed .i32 native.entry.arity.toInt,
          IRTypeRefProof.referenceValue native.entry.result, .signed .i32 (native.entry.starts 0).toInt,
          .signed .i32 (native.entry.starts 1).toInt, .signed .i32 (native.entry.starts 2).toInt])
          entryRun (fieldId := 2) (by rfl)
        exact ⟨entries, RunsStmt.returnValue (RunsExpr.binary shapeRun
          (RunsExpr.ofStable (StableExpr.local (by core_local)) rfl) (by decide) equality),
          PureFrame.refl (by core_formed)⟩
  · simp only [present, decide_false, Bool.false_and]
    core_call_pure hasShape as callee
    core_pure

@[core_pure_rule] theorem actualHasFunctionSignatureOutside (index : SignatureIndex) (query : Int32)
    (outside : query.toInt ≤ -1 ∨ index.count.toInt ≤ query.toInt)
    (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before (.call hasFunction.id
      [.value index.value, .value (.signed .i32 query.toInt)]) (.boolean false) after ∧ PureFrame before after := by
  have missing {state : State} (cells : state.CellsWellFormed) :=
    actualSignatureShapeOutside (before := state) index query .InternalFunctionShape outside cells
  core_call_pure hasFunction as callee
  core_pure

@[core_pure_rule] theorem actualHasFunctionSignatureAt (index : SignatureIndex) (query : Int32)
    (bounds : 0 ≤ query.toInt ∧ query.toInt < index.count.toInt)
    (native : NativeSignatureSlot index before.heap query.toInt.toNat)
    (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before (.call hasFunction.id
      [.value index.value, .value (.signed .i32 query.toInt)])
      (.boolean (decide (native.entry.id.toInt = query.toInt) && shapeSame native.entry.shape .InternalFunctionShape)) after ∧
      PureFrame before after := by
  have shaped {state : State} (same : state.heap = before.heap) (cells : state.CellsWellFormed) :=
    actualSignatureShapeAt (before := state) index query .InternalFunctionShape bounds
      { native with snapshot := by rw [same]; exact native.snapshot } cells
  core_call_pure hasFunction as callee
  core_pure

#print axioms actualSignatureOutside
#print axioms actualSignatureContainsAt
#print axioms actualSignatureShapeOutside
#print axioms actualSignatureShapeAt
#print axioms actualHasFunctionSignatureOutside
#print axioms actualHasFunctionSignatureAt

end IRBodyOwnedInputs
