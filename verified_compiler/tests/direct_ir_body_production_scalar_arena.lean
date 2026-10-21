import verified_compiler.tests.direct_ir_body_production_inputs_context
import verified_compiler.tests.direct_ir_body_production_inputs_locals
import Lanius.Semantics.RawFieldStore
import Lanius.Semantics.NativeStoreProof
import Lanius.Semantics.ScopedEffect

namespace IRBodyProductionScalar

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics

def appendSource := Extracted.«verified::surface_expr».Functions.«append».core
def expressionNodeType : Ty := match source_value Extracted.«verified::surface_expr».Types.«ExpressionNode».mk [] with
  | .structure id _ => .structure id | _ => .unit
def expressionCountId : TypeId := match source_value Extracted.«verified::surface_expr».Types.«CountCell».mk [] with
  | .structure id _ => id | _ => 0
def expressionNode (kind operator : Value) (left right token : Int32) : Value :=
  source_value Extracted.«verified::surface_expr».Types.«ExpressionNode».mk
    [kind, operator, .signed .i32 left.toInt, .signed .i32 right.toInt,
      .signed .i32 token.toInt, .signed .i32 (-1)]

structure Arena where
  nodes : Nat
  capacity : Nat
  count : Nat
  countLength : Nat
  fits : capacity < 2 ^ 31
  countPositive : 0 < countLength
def Arena.value (arena : Arena) : Value :=
  source_value Extracted.«verified::surface_expr».Types.«ExpressionArena».mk
    [.rawSlice expressionNodeType arena.nodes arena.capacity,
      .rawSlice (.structure expressionCountId) arena.count arena.countLength,
      .signed .i32 arena.capacity]

@[core_pure_rule] theorem actualNodeCount (arena : Arena)
    (read : readNativeValue 64 extractedProgram before.heap (.scalar (.signed .i32)) arena.count =
      .ok (.signed .i32 count)) (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before
      (.call Extracted.«verified::surface_expr».Functions.«node_count».core.id [.value arena.value])
      (.signed .i32 count) after ∧ PureFrame before after := by
  have countRead := IRBodyProductionInputs.countCellRead (state := before) (id := expressionCountId)
    (by decide +kernel) (by decide +kernel) (by decide +kernel) arena.countPositive read
  core_call_pure Extracted.«verified::surface_expr».Functions.«node_count».core as callee
  core_pure

/-- Only the selected fresh node and sole count field must be writable. -/
structure ArenaSlot (before : State) where
  arena : Arena
  next : Nat
  base : Nat
  bound : next < arena.capacity
  location : rawSliceElementAddress? extractedProgram expressionNodeType arena.nodes next = .ok base
  countRead : readNativeValue 64 extractedProgram before.heap (.scalar (.signed .i32)) arena.count =
    .ok (.signed .i32 next)
  nodeRoom : before.heap.Readable base 48
  countRoom : before.heap.Readable arena.count 4
  separate : base + 48 ≤ arena.count ∨ arena.count + 4 ≤ base
def ArenaSlot.reheap (slot : ArenaSlot before) (same : after.heap = before.heap) : ArenaSlot after := {
  slot with
  countRead := by simpa only [same] using slot.countRead
  nodeRoom := by simpa only [same] using slot.nodeRoom
  countRoom := by simpa only [same] using slot.countRoom }
def ArenaSlot.call (slot : ArenaSlot state) (kind operator : Value) (left right token : Int32) : Expr :=
  .call appendSource.id ([slot.arena.value, kind, operator, .signed .i32 left.toInt,
    .signed .i32 right.toInt, .signed .i32 token.toInt].map Expr.value)
def ArenaStored (slot : ArenaSlot state) (node : Value) (before after : Heap) : Prop :=
  NativeSnapshot 64 extractedProgram after expressionNodeType slot.base node 48 ∧
  NativeSnapshot 64 extractedProgram after (.scalar (.signed .i32)) slot.arena.count
    (.signed .i32 (slot.next + 1 : Nat)) 4 ∧
  ∃ middle, HeapRegionWrite before middle slot.base 48 ∧ HeapRegionWrite middle after slot.arena.count 4

/-- The actual semantic-node allocator overwrites without reading an old spare node. -/
theorem actualArenaAppend (slot : ArenaSlot before) (kind operator : Value) (left right token : Int32)
    (codec : NativeStoreSpec 64 extractedProgram expressionNodeType (expressionNode kind operator left right token) 48)
    (formed : before.CellsWellFormed) (unique : HeapBlockBasesUnique before.heap) (noViews : before.i32ArrayViews = []) :
    ∃ after, RunsExpr extractedProgram before (slot.call kind operator left right token)
      (.signed .i32 slot.next) after ∧ MemoryEffect (ArenaStored slot (expressionNode kind operator left right token)) before after := by
  core_call_framed (RunsExpr.callEffect (MemoryEffect.scopeStable _)) appendSource as callee
  apply RunsStmt.letFramedEffect (MemoryEffect.scopeStable _)
  · apply RunsExpr.callPureArguments
    · core_arguments
    · exact actualNodeCount slot.arena slot.countRead (by core_formed)
  · intro counted countFrame
    apply RunsStmt.guardEffectFalse (MemoryEffect.scopeStable _)
    · core_facts [slot, slot.arena]
      core_pure_guard
    · intro selected guardFrame
      apply RunsStmt.letEffect (MemoryEffect.scopeStable _)
      · core_run
      · core_formed
      · core_state ready
        have heap : ready.heap = before.heap := guardFrame.heap.trans countFrame.heap
        obtain ⟨nodeHeap, nodeRun, nodeSnapshot, nodeEffect⟩ := RunsExpr.assignRawNative
          (program := extractedProgram) (before := ready) (indexed := ready) (ready := ready)
          (sourceId := appendSource.bindingId 1) (indexExpression := .local (appendSource.bindingId 0))
          (expression := match appendSource.effectExpression 0 with | .assign _ _ rhs => rhs | _ => .value .unit)
          (by core_local) (by core_run) slot.bound slot.location codec
          (by simpa only [heap] using slot.nodeRoom)
          (by simpa only [heap] using unique) (guardFrame.views.trans (countFrame.views.trans noViews)) (by core_run)
        let written := { ready with heap := nodeHeap }
        let annotated := written.bindLocal (appendSource.bindingId 2)
          (.rawSlice (.structure expressionCountId) slot.arena.count slot.arena.countLength)
        have readyFormed : ready.CellsWellFormed :=
          (show selected.CellsWellFormed by core_formed).bindLocal (appendSource.bindingId 1)
            (.rawSlice expressionNodeType slot.arena.nodes slot.arena.capacity)
        have writtenFormed : written.CellsWellFormed := readyFormed
        have annotatedFormed : annotated.CellsWellFormed := writtenFormed.bindLocal (appendSource.bindingId 2)
          (.rawSlice (.structure expressionCountId) slot.arena.count slot.arena.countLength)
        have nextFound : written.local? (appendSource.bindingId 0) = some (.signed .i32 slot.next) := by
          change ready.local? (appendSource.bindingId 0) = _
          core_local
        have annotatedNext : annotated.local? (appendSource.bindingId 0) = some (.signed .i32 slot.next) :=
          State.bindLocal_local?_of_ne written writtenFormed (appendSource.bindingId 0) (appendSource.bindingId 2)
            (.signed .i32 slot.next) (.rawSlice (.structure expressionCountId) slot.arena.count slot.arena.countLength)
            (by decide +kernel) nextFound
        have advance : evalBinaryValue extractedProgram.target .add (.signed .i32 slot.next) (.signed .i32 1) =
            .ok (.signed .i32 (slot.next + 1 : Nat)) := by
          simpa only [Int.natCast_add, Int.natCast_one] using eval_i32_addNonneg extractedProgram.target
            slot.next 1 (by omega) (by have := slot.bound; have := slot.arena.fits; omega)
        have nextFits : -2147483648 ≤ ((slot.next + 1 : Nat) : Int) ∧ ((slot.next + 1 : Nat) : Int) < 2147483648 := by
          have := slot.bound; have := slot.arena.fits; omega
        have represented : (BitVec.ofInt 32 (slot.next + 1 : Nat)).toInt = (slot.next + 1 : Nat) :=
          BitVec.toInt_ofInt_eq_self (by decide) nextFits.1 nextFits.2
        have nextCodec : NativeStoreSpec 64 extractedProgram (.scalar (.signed .i32))
            (.signed .i32 (slot.next + 1 : Nat)) 4 := by
          simpa only [represented] using NativeStoreSpec.i32 (program := extractedProgram)
            (fuel := 63) (BitVec.ofInt 32 (slot.next + 1 : Nat))
        have declaration : extractedProgram.structure? expressionCountId =
            some { id := expressionCountId, fields := [.scalar (.signed .i32)] } := by decide +kernel
        have countLayout : NativeLayout.valueWords? extractedProgram (.structure expressionCountId) = some 1 := by decide +kernel
        have countLocation : rawSliceElementAddress? extractedProgram (.structure expressionCountId) slot.arena.count 0 =
            .ok slot.arena.count := by
          simp [rawSliceElementAddress?, countLayout, NativeLayout.elementBase?,
            NativeLayout.wordBytes, Pure.pure, Except.pure]
        obtain ⟨heap', countRun, countSnapshot, countEffect, _⟩ := RunsExpr.assignRawFieldNative
          (program := extractedProgram) (before := annotated) (indexed := annotated) (ready := annotated)
          (sourceId := appendSource.bindingId 2) (indexExpression := .value (.signed .i32 0))
          (field := 0) (displacement := 0)
          (expression := .binary .add (.local (appendSource.bindingId 0)) (.value (.signed .i32 1)))
          (writtenFormed.bindLocal_local (appendSource.bindingId 2)
            (.rawSlice (.structure expressionCountId) slot.arena.count slot.arena.countLength))
          (by core_run) slot.arena.countPositive
          countLocation declaration rfl (by decide +kernel) nextCodec
          (by
            change nodeHeap.Readable slot.arena.count 4
            exact nodeEffect.readable _ _ (by simpa only [heap] using slot.countRoom))
          nodeEffect.unique (guardFrame.views.trans (countFrame.views.trans noViews)) (by core_run)
        let completed := { annotated with heap := heap', locals := written.locals }
        have body : RunsStmt extractedProgram ready
            (match appendSource.bindingStatement 1 with | .letLocal _ _ _ rest => rest | _ => .skip)
            (.returned (some (.signed .i32 slot.next))) completed := by
          core_stmt_forward
        exact ⟨completed, body,
          FreshCellFrame.bindLocal written (appendSource.bindingId 2)
            (.rawSlice (.structure expressionCountId) slot.arena.count slot.arena.countLength),
          rfl, rfl, nodeSnapshot.afterWrite countEffect slot.separate, countSnapshot,
          nodeHeap, nodeEffect, countEffect⟩

#print axioms actualNodeCount
#print axioms actualArenaAppend

end IRBodyProductionScalar
