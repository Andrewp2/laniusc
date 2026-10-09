import verified_compiler.tests.direct_ir_body_production_inputs
import Lanius.Core.Bindings
import Lanius.Semantics.RawFieldStore
import Lanius.Semantics.ScopedEffect
import Lanius.Semantics.HostCall
import Lanius.Memory.Allocated

namespace IRBodyProductionInputs

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics

def localsConstructor := Extracted.«lowering::locals».Functions.«from_raw_parts».core
def localCountId : TypeId := match source_value Extracted.«lowering::locals».Types.«CountCell».mk [] with
  | .structure id _ => id | _ => 0
def localBindingType : Ty := match source_value Extracted.«lowering::locals».Types.«Binding».mk [] with
  | .structure id _ => .structure id | _ => .unit
def localBytes (capacity : Nat) : Nat := 8 + max capacity 1 * 24
def localFirst (memory capacity : Nat) : Nat := memory + if capacity = 0 then 8 else capacity * 24
def localsValue (memory capacity : Nat) : Value := source_value Extracted.«lowering::locals».Types.«Table».mk
  [.rawSlice localBindingType (localFirst memory capacity) capacity,
    .rawSlice (.structure localCountId) memory 1, .signed .i32 capacity]

@[core_pure_rule] theorem actualLocalBytes (capacity : Nat) (positive : 0 < capacity) (bound : capacity ≤ 89478484)
    (formed : before.CellsWellFormed) : ∃ after, RunsExpr extractedProgram before
      (.call Extracted.«lowering::locals».Functions.«allocation_bytes».core.id [.value (.signed .i32 capacity)])
      (.signed .i32 (localBytes capacity)) after ∧ PureFrame before after := by
  have maximum : max capacity 1 = capacity := Nat.max_eq_left (by omega)
  have productFits : capacity * 24 < 2 ^ 31 := by omega
  have totalFits : 8 + capacity * 24 < 2 ^ 31 := by omega
  simp only [localBytes, maximum]
  core_call_pure Extracted.«lowering::locals».Functions.«allocation_bytes».core as callee
  core_pure

theorem actualLocalAllocation (capacity : Nat)
    (available : consumeBudget before.heap.remaining (localBytes capacity) = some budget)
    (noViews : before.i32ArrayViews = []) : RunsExpr extractedProgram before
      (.call Extracted.«verified::host».Functions.«alloc».core.id
        [.value (.unsigned .usize (localBytes capacity)), .value (.unsigned .usize 8)])
      (.pointer (before.heap.allocationAddress 8))
      ({ before with
        heap := before.heap.allocatedBytes (localBytes capacity) 8 budget
        world := World.record before.world .alloc }) := by
  let allocator := Extracted.«verified::host».Functions.«alloc».core
  apply RunsExpr.hostCall (functionId := allocator.id) (function := allocator)
    (values := [.unsigned .usize (localBytes capacity), .unsigned .usize 8])
    (bindings := [(allocator.argumentId 0, .unsigned .usize (localBytes capacity)),
      (allocator.argumentId 1, .unsigned .usize 8)]) (by dsimp only [allocator]; core_lookup) rfl rfl rfl noViews
  have allocated := Heap.allocate_of_budget (alignment := 8) (by decide) available
  simp only [World.call, World.callSimple, allocated]
theorem actualLocalExhaustion (capacity : Nat)
    (exhausted : consumeBudget before.heap.remaining (localBytes capacity) = none)
    (noViews : before.i32ArrayViews = []) : RunsExpr extractedProgram before
      (.call Extracted.«verified::host».Functions.«alloc».core.id
        [.value (.unsigned .usize (localBytes capacity)), .value (.unsigned .usize 8)])
      (.pointer 0) ({ before with world := World.record before.world .alloc }) := by
  let allocator := Extracted.«verified::host».Functions.«alloc».core
  apply RunsExpr.hostCall (functionId := allocator.id) (function := allocator)
    (values := [.unsigned .usize (localBytes capacity), .unsigned .usize 8])
    (bindings := [(allocator.argumentId 0, .unsigned .usize (localBytes capacity)),
      (allocator.argumentId 1, .unsigned .usize 8)]) (by dsimp only [allocator]; core_lookup) rfl rfl rfl noViews
  simp only [World.call, World.callSimple, Heap.allocate, show validAlignment 8 = true from rfl,
    Bool.not_true, Bool.false_eq_true, ↓reduceIte, exhausted, null]

theorem countCellRead {program : Program} {state : State} {id : TypeId} {address length : Nat} {value : Int}
    (declaration : program.structure? id = some { id, fields := [.scalar (.signed .i32)] })
    (offset : NativeLayout.structureFieldOffset? program id 0 = some 0)
    (layout : NativeLayout.valueWords? program (.structure id) = some 1) (bound : 0 < length)
    (read : readNativeValue 64 program state.heap (.scalar (.signed .i32)) address = .ok (.signed .i32 value)) :
    readRawSliceIndex program state (.structure id) address length 0 = .ok (.structure id [.signed .i32 value]) := by
  have location : rawSliceElementAddress? program (.structure id) address 0 = .ok address := by
    simp [rawSliceElementAddress?, layout, NativeLayout.elementBase?, NativeLayout.wordBytes, Pure.pure, Except.pure]
  have fieldRead : readNativeValue 63 program state.heap (.scalar (.signed .i32)) address =
    .ok (.signed .i32 value) := read
  simp only [readRawSliceIndex, Nat.not_le_of_lt bound, ↓reduceIte, location]
  dsimp only [Bind.bind, Except.bind]
  change readNativeValue 64 program state.heap (.structure id) address = _
  rw [readNativeValue, declaration]
  simp only [List.length_cons, List.length_nil, List.range_succ, List.range_zero,
    List.nil_append, List.mapM_cons, List.mapM_nil, List.getElem?_cons_zero,
    offset, Nat.add_zero, fieldRead]
  rfl

@[core_pure_rule] theorem actualLocalSave (memory capacity : Nat)
    (snapshot : NativeSnapshot 64 extractedProgram before.heap (.scalar (.signed .i32)) memory (.signed .i32 value) 4)
    (formed : before.CellsWellFormed) : ∃ after, RunsExpr extractedProgram before
      (.call Extracted.«lowering::locals».Functions.«save».core.id [.value (localsValue memory capacity)])
      (.signed .i32 value) after ∧ PureFrame before after := by
  have read := countCellRead (state := before) (id := localCountId) (length := 1)
    (by decide +kernel) (by decide +kernel) (by decide +kernel) (by decide) snapshot.read
  core_call_pure Extracted.«lowering::locals».Functions.«save».core as callee
  core_pure

/-- Restore overwrites only the actual four-byte count field; no old record decode. -/
theorem actualLocalRestore (memory capacity : Nat) (value : Int32)
    (room : before.heap.Readable memory 4) (unique : HeapBlockBasesUnique before.heap)
    (formed : before.CellsWellFormed) (noViews : before.i32ArrayViews = []) :
    ∃ after, RunsExpr extractedProgram before
      (.call Extracted.«lowering::locals».Functions.«restore».core.id
        [.value (localsValue memory capacity), .value (.signed .i32 value.toInt)]) .unit after ∧
      MemoryEffect (fun old heap => NativeSnapshot 64 extractedProgram heap (.scalar (.signed .i32))
        memory (.signed .i32 value.toInt) 4 ∧ HeapRegionWrite old heap memory 4) before after := by
  let source := Extracted.«lowering::locals».Functions.«restore».core
  have declaration : extractedProgram.structure? localCountId =
    some { id := localCountId, fields := [.scalar (.signed .i32)] } := by decide +kernel
  have offset : NativeLayout.structureFieldOffset? extractedProgram localCountId 0 = some 0 := by decide +kernel
  have layout : NativeLayout.valueWords? extractedProgram (.structure localCountId) = some 1 := by decide +kernel
  have location : rawSliceElementAddress? extractedProgram (.structure localCountId) memory 0 = .ok memory := by
    simp [rawSliceElementAddress?, layout, NativeLayout.elementBase?, NativeLayout.wordBytes, Pure.pure, Except.pure]
  have codec : NativeStoreSpec 64 extractedProgram (.scalar (.signed .i32)) (.signed .i32 value.toInt) 4 := by
    simpa using NativeStoreSpec.i32 (program := extractedProgram) (fuel := 63) value.toBitVec
  let values := [localsValue memory capacity, Value.signed .i32 value.toInt]
  let bindings := [(source.argumentId 0, localsValue memory capacity),
    (source.argumentId 1, Value.signed .i32 value.toInt)]
  let callee := ({ before with locals := [] }).bindLocals bindings
  let ready := callee.bindLocal (source.bindingId 0) (.rawSlice (.structure localCountId) memory 1)
  have calleeFormed : callee.CellsWellFormed := by core_formed
  have readyHeap : ready.heap = before.heap := rfl
  obtain ⟨heap, run, snapshot, write, _⟩ := RunsExpr.assignRawFieldNative
    (program := extractedProgram) (before := ready) (indexed := ready) (ready := ready)
    (sourceId := source.bindingId 0)
    (field := 0) (indexExpression := .value (.signed .i32 0)) (expression := .local (source.argumentId 1))
    (by core_local) (.ofStable .value rfl) (by decide) location declaration rfl offset codec
    (by simpa only [readyHeap, Nat.add_zero] using room) unique (by exact noViews) (by core_run)
  let completed := restoreLocals callee { ready with heap }
  have body : RunsStmt extractedProgram callee (source.body.getD .skip) .next completed := by
    exact RunsStmt.letLocal (by core_run) (RunsStmt.sequenceNext (RunsStmt.expression run) (RunsStmt.skip _ _))
  refine ⟨restoreLocals before completed, ?_, ?_⟩
  · exact RunsExpr.callUnit (functionId := source.id) (function := source) (values := values) (bindings := bindings)
      (by dsimp only [source]; core_lookup) rfl rfl (by simpa only [values, List.map] using RunsExprs.values (program := extractedProgram) (state := before) values) rfl body
  · exact ⟨(FreshCellFrame.bindLocals ({ before with locals := [] }) bindings).trans
      (FreshCellFrame.bindLocal callee (source.bindingId 0) (.rawSlice (.structure localCountId) memory 1)), rfl, rfl,
      by change NativeSnapshot 64 extractedProgram heap (.scalar (.signed .i32)) memory (.signed .i32 value.toInt) 4
         simpa only [Nat.add_zero, NativeLayout.maxDepth] using snapshot,
      by change HeapRegionWrite before.heap heap memory 4
         simpa only [readyHeap, Nat.add_zero] using write⟩

#print axioms actualLocalBytes
#print axioms countCellRead
#print axioms actualLocalAllocation
#print axioms actualLocalExhaustion
#print axioms actualLocalSave
#print axioms actualLocalRestore

end IRBodyProductionInputs
