import SelfCore
import Lanius.Core.Bindings
import Lanius.Semantics.CallProof
import Lanius.Semantics.PureProof
import Lanius.Semantics.SourceValue
import Lanius.Semantics.RawStore
import Lanius.Semantics.ScopedEffect

namespace IREventStoreProof

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics

private def source := Extracted.«ir::body_events».Functions.«append».core
def eventType : Ty := ((source.parameters[2]?).getD (0, .unit)).2
def referenceType : Ty := ((Extracted.«ir::type_ref».Functions.«is_invalid».core.parameters[0]?).getD (0, .unit)).2
def invalid : Value := source_value Extracted.«ir::type_ref».Types.«TypeRef».«Invalid» []
def integer (value : BitVec 32) : Value :=
  source_value Extracted.«ir::body_events».Types.«Event».«ExpressionInteger» [.signed .i32 value.toInt]
def boolean (value : Bool) : Value :=
  source_value Extracted.«ir::body_events».Types.«Event».«ExpressionBoolean» [.boolean value]
def pointerNull : Value := source_value Extracted.«ir::body_events».Types.«Event».«ExpressionPointerNull» []

theorem invalidCodec : NativeStoreSpec 64 extractedProgram referenceType invalid 16 := by
  exact (NativeStoreSpec.enumEmpty (by core_lookup) rfl (by decide)).enlarge (by decide)

theorem integerCodec (value : BitVec 32) : NativeStoreSpec 64 extractedProgram eventType (integer value) 40 := by
  exact (NativeStoreSpec.enumSingle (by core_lookup) rfl (by decide) (NativeStoreSpec.i32 value)).enlarge (by decide)

theorem booleanCodec (value : Bool) : NativeStoreSpec 64 extractedProgram eventType (boolean value) 40 := by
  exact (NativeStoreSpec.enumSingle (by core_lookup) rfl (by decide) (NativeStoreSpec.boolean value)).enlarge (by decide)

theorem nullCodec : NativeStoreSpec 64 extractedProgram eventType pointerNull 40 := by
  exact (NativeStoreSpec.enumEmpty (by core_lookup) rfl (by decide)).enlarge (by decide)

/-- Writable native IR storage, with the two mutable slots separated.
    SET needs no decoding of either destination's previous contents. -/
structure Context (state : State) where
  position : Nat
  capacity : Nat
  events : Nat
  types : Nat
  typesLength : Nat
  enabled : Bool
  eventBase : Nat
  typeBase : Nat
  bound : position < capacity
  fits : capacity < 2 ^ 31
  eventLocation : rawSliceElementAddress? extractedProgram eventType events position = .ok eventBase
  typeBound : enabled = true → position < typesLength
  typeLocation : enabled = true → rawSliceElementAddress? extractedProgram referenceType types position = .ok typeBase
  eventRoom : state.heap.Readable eventBase 40
  typeRoom : enabled = true → state.heap.Readable typeBase 16
  separate : enabled = true → eventBase + 40 ≤ typeBase ∨ typeBase + 16 ≤ eventBase

def Context.reheap (input : Context before) (same : after.heap = before.heap) : Context after := {
  input with
  eventRoom := by simpa only [same] using input.eventRoom
  typeRoom := fun enabled => by simpa only [same] using input.typeRoom enabled }

/-- A proved write preserves the slot permissions; old values and disjointness
    are unnecessary when the next operation overwrites those slots. -/
def Context.afterWrite (input : Context before)
    (write : HeapRegionWrite before.heap after.heap address size) : Context after := {
  input with
  eventRoom := write.readable _ _ input.eventRoom
  typeRoom := fun enabled => write.readable _ _ (input.typeRoom enabled) }

/-- One append's semantic postcondition. Its heap relation retains the exact
    event and reset annotation, with separate frames for both actual stores. -/
def appendHeapEffect (enabled : Bool) (eventBase typeBase : Nat) (event : Value) (before after : Heap) : Prop :=
  NativeSnapshot 64 extractedProgram after eventType eventBase event 40 ∧
  ∃ middle, HeapRegionWrite before middle eventBase 40 ∧
    if enabled then NativeSnapshot 64 extractedProgram after referenceType typeBase invalid 16 ∧
      HeapRegionWrite middle after typeBase 16 else after = middle
def Appended (input : Context state) (event : Value) : State → State → Prop :=
  MemoryEffect (appendHeapEffect input.enabled input.eventBase input.typeBase event)

/-- The one actual append footprint retains permission and allocator metadata
    in both modes; disabled annotation addresses grant no writes. -/
theorem appendHeapEffect.footprint
    (effect : appendHeapEffect enabled eventAddress typeAddress value before after) :
    HeapWritesOn before after (fun location =>
      (eventAddress ≤ location ∧ location < eventAddress + 40) ∨
      (enabled = true ∧ typeAddress ≤ location ∧ location < typeAddress + 16)) := by
  obtain ⟨_, middle, eventWrite, tail⟩ := effect
  have first : HeapWritesOn before middle (fun location =>
      (eventAddress ≤ location ∧ location < eventAddress + 40) ∨
      (enabled = true ∧ typeAddress ≤ location ∧ location < typeAddress + 16)) :=
    eventWrite.footprint.weaken (fun _ inside => Or.inl inside)
  cases enabled
  · simp only [Bool.false_eq_true, ↓reduceIte] at tail
    subst after
    exact first
  · simp only [↓reduceIte] at tail
    exact first.trans (tail.2.footprint.weaken (fun _ inside => Or.inr ⟨rfl, inside⟩))

def Context.afterAppend {enabled : Bool} {eventAddress typeAddress : Nat} {value : Value} (input : Context before)
    (effect : appendHeapEffect enabled eventAddress typeAddress value before.heap after.heap) : Context after := {
  input with
  eventRoom := effect.footprint.readable _ _ input.eventRoom
  typeRoom := fun enabled => effect.footprint.readable _ _ (input.typeRoom enabled) }

def Context.value (input : Context state) : Value :=
  source_value Extracted.«ir::body_events».Types.«Region».mk
    [.rawSlice eventType input.events input.capacity, .rawSlice referenceType input.types input.typesLength,
      .boolean input.enabled, .signed .i32 input.capacity]
def appendProducer (event output : Value) (position : Int) : Expr :=
  .call source.id ([output, .signed .i32 position, event].map Expr.value)
def Context.call (input : Context state) (event : Value) : Expr :=
  appendProducer event input.value input.position

/-- A writer's complete slot contract. Inputs describe available native
    storage and ordinary model invariants, not successful execution. -/
def Produces (producer : Value → Int → Expr) (event : Value) : Prop :=
  ∀ {before} (input : Context before), before.CellsWellFormed → HeapBlockBasesUnique before.heap →
    before.i32ArrayViews = [] → ∃ after, RunsExpr extractedProgram before (producer input.value input.position)
      (.signed .i32 (input.position + 1 : Nat)) after ∧ Appended input event before after

/-- Actual append, not a model of append: write the event, reset its annotation
    to Invalid, advance once, and retain caller cells and all other memory. -/
theorem actualAppend (input : Context before) (codec : NativeStoreSpec 64 extractedProgram eventType event 40)
    (formed : before.CellsWellFormed) (unique : HeapBlockBasesUnique before.heap) (noViews : before.i32ArrayViews = []) :
    ∃ after, RunsExpr extractedProgram before (input.call event) (.signed .i32 (input.position + 1 : Nat)) after ∧
      Appended input event before after := by
  let bindings := [(source.argumentId 0, input.value), (source.argumentId 1, Value.signed .i32 input.position),
    (source.argumentId 2, event)]
  let callee := ({ before with locals := [] }).bindLocals bindings
  let ready := callee.bindLocal (source.bindingId 0) (.rawSlice eventType input.events input.capacity)
  have readyFormed : ready.CellsWellFormed := by core_formed
  obtain ⟨eventHeap, eventRun, eventSnapshot, eventEffect⟩ := RunsExpr.assignRawNative (program := extractedProgram)
    (before := ready) (indexed := ready) (ready := ready) (expression := .local (source.argumentId 2))
    (sourceId := source.bindingId 0) (indexExpression := .local (source.argumentId 1))
    (by core_local) (by core_run) input.bound input.eventLocation codec input.eventRoom unique noViews (by core_run)
  let written := { ready with heap := eventHeap }
  have advance : evalBinaryValue extractedProgram.target .add (.signed .i32 input.position) (.signed .i32 1) =
      .ok (.signed .i32 (input.position + 1 : Nat)) := by
    simpa only [Int.natCast_add, Int.natCast_one] using eval_i32_addNonneg extractedProgram.target
      input.position 1 (by omega) (by have := input.bound; have := input.fits; omega)
  by_cases enabled : input.enabled = true
  · let annotated := written.bindLocal (source.bindingId 1) (.rawSlice referenceType input.types input.typesLength)
    have annotatedFormed : annotated.CellsWellFormed := by core_formed
    obtain ⟨heap, typeRun, typeSnapshot, typeEffect⟩ := RunsExpr.assignRawNative (program := extractedProgram)
      (before := annotated) (indexed := annotated) (ready := annotated) (expression := .enumValue _ _ [])
      (sourceId := source.bindingId 1) (indexExpression := .local (source.argumentId 1))
      (by core_local) (by core_run) (input.typeBound enabled) (input.typeLocation enabled) invalidCodec
      (eventEffect.readable _ _ (input.typeRoom enabled)) eventEffect.unique noViews (by core_run)
    let returned := { annotated with heap, locals := written.locals }
    have restoredCells : FreshCellFrame written returned :=
      FreshCellFrame.bindLocal written (source.bindingId 1) (.rawSlice referenceType input.types input.typesLength)
    have positionFound : written.local? (source.argumentId 1) = some (.signed .i32 input.position) := by core_local
    have returnedPosition := restoredCells.localFound rfl _ _ positionFound
    let completed := { annotated with heap, locals := callee.locals }
    have body : RunsStmt extractedProgram callee (source.body.getD .skip)
        (.returned (some (.signed .i32 (input.position + 1 : Nat)))) completed := by
      have bound := input.bound
      core_stmt_forward
    have cells := (FreshCellFrame.bindLocals ({ before with locals := [] }) bindings).trans
      ((FreshCellFrame.bindLocal callee (source.bindingId 0) (.rawSlice eventType input.events input.capacity)).trans
        (FreshCellFrame.bindLocal written (source.bindingId 1) (.rawSlice referenceType input.types input.typesLength)))
    refine ⟨restoreLocals before completed,
      RunsExpr.call (function := source) (values := [input.value, .signed .i32 input.position, event])
        (bindings := bindings) (by core_lookup) rfl (RunsExprs.values _) rfl body,
      cells, rfl, rfl, eventSnapshot.afterWrite typeEffect (input.separate enabled), eventHeap, eventEffect, ?_⟩
    simp only [enabled, ↓reduceIte]
    change NativeSnapshot 64 extractedProgram heap referenceType input.typeBase invalid 16 ∧
      HeapRegionWrite eventHeap heap input.typeBase 16
    exact ⟨by simpa only [NativeLayout.maxDepth] using typeSnapshot, typeEffect⟩
  · have disabled : input.enabled = false := Bool.eq_false_iff.mpr enabled
    let completed := { written with locals := callee.locals }
    have body : RunsStmt extractedProgram callee (source.body.getD .skip)
        (.returned (some (.signed .i32 (input.position + 1 : Nat)))) completed := by
      have bound := input.bound
      core_stmt_forward
    have cells := (FreshCellFrame.bindLocals ({ before with locals := [] }) bindings).trans
      (FreshCellFrame.bindLocal callee (source.bindingId 0) (.rawSlice eventType input.events input.capacity))
    refine ⟨restoreLocals before completed,
      RunsExpr.call (function := source) (values := [input.value, .signed .i32 input.position, event])
        (bindings := bindings) (by core_lookup) rfl (RunsExprs.values _) rfl body,
      cells, rfl, rfl, eventSnapshot, eventHeap, eventEffect, ?_⟩
    simp only [disabled, ↓reduceIte]
    rfl

/-- Out-of-range positions return before either typed-memory store. -/
theorem actualReject (region event : Value) (position capacity : Int)
    (shape : region = source_value Extracted.«ir::body_events».Types.«Region».mk
      [events, types, enabled, .signed .i32 capacity])
    (bad : position < 0 ∨ capacity ≤ position) (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before (.call source.id [.value region, .value (.signed .i32 position), .value event])
      (.signed .i32 (-1)) after ∧ PureFrame before after := by
  subst region
  core_call_pure source as callee
  core_pure

#print axioms actualAppend
#print axioms appendHeapEffect.footprint
#print axioms actualReject
#print axioms integerCodec
#print axioms booleanCodec

end IREventStoreProof
