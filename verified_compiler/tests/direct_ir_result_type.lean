import verified_compiler.tests.direct_ir_type_ref
import verified_compiler.tests.direct_ir_event_store
import Lanius.Core.Bindings
import Lanius.Semantics.RawStore
import Lanius.Semantics.NativeStoreProof

namespace IRResultTypeProof

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics IRTypeRefProof

private def source := Extracted.«ir::body_events».Functions.«record_result_type».core
def referenceType : Ty := ((source.parameters[2]?).getD (0, .unit)).2
def region (events types : Value) (enabled : Bool) (capacity : Int) : Value :=
  source_value Extracted.«ir::body_events».Types.«Region».mk
    [events, types, .boolean enabled, .signed .i32 capacity]
def call (events types : Value) (enabled : Bool) (capacity position : Int) (kind : Reference) : Expr :=
  .call source.id ([region events types enabled capacity, .signed .i32 position,
    referenceValue kind].map Expr.value)

@[native_store_rule] theorem referenceCodec (kind : Reference) :
    NativeStoreSpec (fuel + 2) extractedProgram referenceType (referenceValue kind) 16 := by
  cases kind <;> dsimp only [referenceValue]
  all_goals first
    | exact (NativeStoreSpec.enumEmpty (by core_lookup) rfl (by decide)).enlarge (by decide)
    | exact (NativeStoreSpec.enumSingle (by core_lookup) rfl (by decide)
        (NativeStoreSpec.i32 _)).enlarge (by decide)

/-- Bounds are checked before type validation or access to either buffer. -/
theorem actualOutOfBounds (kind : Reference) (position capacity : Int)
    (bad : position < 0 ∨ capacity ≤ position) (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before (call events types enabled capacity position kind)
      (.boolean false) after ∧ PureFrame before after := by
  core_call_pure source as callee
  core_pure

/-- Invalid type codes are rejected without changing either buffer. -/
theorem actualInvalid (kind : Reference) (position capacity : Int)
    (bad : typeCode kind < 0) (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before (call events types enabled capacity position kind)
      (.boolean false) after ∧ PureFrame before after := by
  have rejected : isValidResult kind = false := by simp only [isValidResult, decide_eq_false_iff_not]; omega
  core_call_pure source as callee
  core_pure

/-- Regions without annotations still validate the input, but require no
    backing storage and make no memory writes. Void is a valid result type. -/
theorem actualDisabled (kind : Reference) (position capacity : Int)
    (bound : 0 ≤ position ∧ position < capacity) (valid : 0 ≤ typeCode kind)
    (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before (call events types false capacity position kind)
      (.boolean true) after ∧ PureFrame before after := by
  have accepted : isValidResult kind = true := by simpa only [isValidResult, decide_eq_true_eq] using valid
  core_call_pure source as callee
  core_pure

/-- Only the annotation slot needs storage. The event buffer is never read. -/
structure Slot (state : State) where
  position : Nat
  capacity : Nat
  enabled : Bool
  typesLength : Nat
  types : Nat
  address : Nat
  bound : position < capacity
  typeBound : enabled = true → position < typesLength
  location : enabled = true → rawSliceElementAddress? extractedProgram referenceType types position = .ok address
  room : enabled = true → state.heap.Readable address 16

def Slot.call (slot : Slot state) (events : Value) (kind : Reference) : Expr :=
  IRResultTypeProof.call events (.rawSlice referenceType slot.types slot.typesLength) slot.enabled slot.capacity slot.position kind

def Recorded (slot : Slot state) (kind : Reference) (before after : Heap) : Prop :=
  if slot.enabled then
    NativeSnapshot 64 extractedProgram after referenceType slot.address (referenceValue kind) 16 ∧
      HeapRegionWrite before after slot.address 16
  else after = before

def annotationSlot (context : IREventStoreProof.Context state) : Slot state := {
  position := context.position, capacity := context.capacity, enabled := context.enabled
  typesLength := context.typesLength, types := context.types, address := context.typeBase
  bound := context.bound, typeBound := context.typeBound
  location := context.typeLocation, room := context.typeRoom }

private def guard : Expr := match source.body.getD .skip with
  | .sequence (.ifThenElse condition _ _) _ => condition
  | _ => .value (.boolean false)

/-- The real annotation write stores any valid TypeRef (including nominal
    payloads), returns true, and preserves every byte outside that slot. -/
theorem actualRecord (slot : Slot before) (kind : Reference) (valid : 0 ≤ typeCode kind)
    (formed : before.CellsWellFormed) (unique : HeapBlockBasesUnique before.heap)
    (noViews : before.i32ArrayViews = []) :
    ∃ after, RunsExpr extractedProgram before (slot.call events kind) (.boolean true) after ∧
      FreshCellFrame before after ∧ after.world = before.world ∧ after.i32ArrayViews = before.i32ArrayViews ∧
      Recorded slot kind before.heap after.heap := by
  cases enabled : slot.enabled with
  | false =>
      obtain ⟨after, run, frame⟩ := actualDisabled (events := events)
        (types := .rawSlice referenceType slot.types slot.typesLength) kind slot.position slot.capacity
        ⟨by omega, by exact_mod_cast slot.bound⟩ valid formed
      refine ⟨after, ?_, frame.cells, frame.world, frame.views, ?_⟩
      · simpa only [Slot.call, enabled] using run
      · simpa only [Recorded, enabled, Bool.false_eq_true, if_false] using frame.heap
  | true =>
      simp only [Slot.call, Recorded, enabled, ↓reduceIte]
      let descriptor := Value.rawSlice referenceType slot.types slot.typesLength
      let bindings := [(source.argumentId 0, region events descriptor true slot.capacity),
        (source.argumentId 1, Value.signed .i32 slot.position), (source.argumentId 2, referenceValue kind)]
      let callee := ({ before with locals := [] }).bindLocals bindings
      have calleeFormed : callee.CellsWellFormed := by core_formed
      have bound := slot.bound
      have accepted : isValidResult kind = true := by simpa only [isValidResult, decide_eq_true_eq] using valid
      have condition : ∃ guarded, RunsExpr extractedProgram callee guard (.boolean false) guarded ∧ PureFrame callee guarded := by
        core_pure_guard
      obtain ⟨guarded, guardRun, guardFrame⟩ := condition
      let ready := guarded.bindLocal (source.bindingId 0) descriptor
      have readyFormed : ready.CellsWellFormed := by core_formed
      obtain ⟨heap, storeRun, snapshot, effect⟩ := RunsExpr.assignRawNative (program := extractedProgram)
        (before := ready) (indexed := ready) (ready := ready) (expression := .local (source.argumentId 2))
        (sourceId := source.bindingId 0) (indexExpression := .local (source.argumentId 1))
        (by core_local) (by core_run) (slot.typeBound enabled) (slot.location enabled)
        (referenceCodec kind) (by change guarded.heap.Readable _ _; rw [guardFrame.heap]; exact slot.room enabled)
        (by change HeapBlockBasesUnique guarded.heap; rw [guardFrame.heap]; exact unique)
        (by change guarded.i32ArrayViews = []; rw [guardFrame.views]; exact noViews) (by core_run)
      let completed := restoreLocals guarded { ready with heap }
      have body : RunsStmt extractedProgram callee (source.body.getD .skip)
          (.returned (some (.boolean true))) completed := by core_stmt_forward
      have cells := (FreshCellFrame.bindLocals ({ before with locals := [] }) bindings).trans
        (guardFrame.cells.trans (FreshCellFrame.bindLocal guarded (source.bindingId 0) descriptor))
      refine ⟨restoreLocals before completed,
        RunsExpr.call (function := source) (values := [region events descriptor true slot.capacity,
          .signed .i32 slot.position, referenceValue kind]) (bindings := bindings)
          (by core_lookup) rfl (RunsExprs.values _) rfl body,
        cells, guardFrame.world, guardFrame.views, snapshot, ?_⟩
      change HeapRegionWrite guarded.heap heap slot.address 16 at effect
      rw [guardFrame.heap] at effect
      exact effect
    
#print axioms referenceCodec
#print axioms actualOutOfBounds
#print axioms actualInvalid
#print axioms actualDisabled
#print axioms actualRecord

end IRResultTypeProof
