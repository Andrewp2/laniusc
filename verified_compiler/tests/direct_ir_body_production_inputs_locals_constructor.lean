import verified_compiler.tests.direct_ir_body_production_inputs_locals
import Lanius.Semantics.LocalPair
import Lanius.Semantics.CallProof
import Lanius.Semantics.RawSlice

namespace IRBodyProductionInputs

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics

private def firstGuard : Stmt := match localsConstructor.bindingStatement 0 with
  | .letLocal _ _ _ (.sequence guard _) => guard | _ => .skip

/-- The real constructor borrows its allocation and initializes only the count field. -/
private theorem constructorRun (capacity : Nat) (positive : 0 < capacity) (bounded : capacity ≤ 89478484)
    (allocated : before.heap = origin.allocatedBytes (localBytes capacity) 8 budget)
    (below : HeapBlocksBelowNext origin) (unique : HeapBlockBasesUnique origin)
    (fits : origin.allocationAddress 8 + localBytes capacity < 2 ^ 64)
    (formed : before.CellsWellFormed) (noViews : before.i32ArrayViews = []) :
    ∃ after, RunsExpr extractedProgram before (.call localsConstructor.id
      [.value (.pointer (origin.allocationAddress 8)), .value (.signed .i32 capacity)])
      (localsValue (origin.allocationAddress 8) capacity) after ∧
      MemoryEffect (fun _ heap => heap = before.heap.borrowBlock (origin.allocationAddress 8)) before after := by
  let memory := origin.allocationAddress 8
  have maximum : max capacity 1 = capacity := Nat.max_eq_left (by omega)
  have bytes : localBytes capacity = 8 + capacity * 24 := by simp only [localBytes, maximum]
  have extent : 8 < localBytes capacity := by rw [bytes]; omega
  have productFits : capacity * 24 < 2 ^ 31 := by omega
  have pointerFits : memory + capacity * 24 < 2 ^ 64 :=
    Nat.lt_of_le_of_lt (Nat.add_le_add_left
      (show capacity * 24 ≤ localBytes capacity by rw [bytes]; omega) memory) fits
  have initialFits : memory + 8 < 2 ^ 64 :=
    Nat.lt_of_le_of_lt (Nat.add_le_add_left (Nat.le_of_lt extent) memory) fits
  have countDecl : extractedProgram.structure? localCountId =
      some { id := localCountId, fields := [.scalar (.signed .i32)] } := by decide +kernel
  have countLayout : NativeLayout.valueWords? extractedProgram (.structure localCountId) = some 1 := by decide +kernel
  have bindingLayout : NativeLayout.valueWords? extractedProgram localBindingType = some 3 := by decide +kernel
  have offset : NativeLayout.structureFieldOffset? extractedProgram localCountId 0 = some 0 := by decide +kernel
  have location : rawSliceElementAddress? extractedProgram (.structure localCountId) memory 0 = .ok memory := by
    simp [rawSliceElementAddress?, countLayout, NativeLayout.elementBase?, NativeLayout.wordBytes, Pure.pure, Except.pure]
  have allocatedUnique : HeapBlockBasesUnique before.heap := by
    rw [allocated]; exact origin.allocatedBytes_unique below unique (by decide)
  have bindingBorrow (state : State) (same : state.heap = before.heap) :
      mapRawNominalSlice extractedProgram state localBindingType (memory + capacity * 24) capacity =
        .done (.rawSlice localBindingType (memory + capacity * 24) capacity)
          { state with heap := before.heap.borrowBlock memory } := by
    have found := origin.allocatedBytes_containing (size := localBytes capacity) (budget := budget)
      (offset := 8) below (by decide : 0 < 8) extent
    have start : memory + capacity * 24 + 8 - capacity * 3 * 8 = memory + 8 := by
      rw [Nat.mul_assoc]
      change memory + capacity * 24 + 8 - capacity * 24 = memory + 8
      rw [Nat.add_right_comm memory (capacity * 24) 8, Nat.add_sub_cancel]
    have mapped := mapRawNominalSlice_of_block (state := state) (address := memory + capacity * 24)
      (block := origin.allocationBlock (localBytes capacity) 8) capacity positive rfl bindingLayout (by decide)
      (by change capacity * 3 * 8 ≤ memory + capacity * 24 + 8
          rw [Nat.mul_assoc]
          exact Nat.le_trans (Nat.le_add_left (capacity * 24) memory) (Nat.le_add_right _ _)) (by
        change state.heap.containingBlock? (memory + capacity * 24 + 8 - capacity * 3 * 8) = _
        rw [start]
        simpa only [same, allocated, memory] using found)
      (by change (memory + capacity * 24 + 8 - capacity * 3 * 8) % 8 = 0
          rw [start]
          simpa only [memory, Nat.add_mod, Nat.mod_self, Nat.add_zero, Nat.mod_mod] using
            origin.allocationAddress_aligned (alignment := 8))
      (by change 8 ≤ 8; decide) (by
        dsimp only [Heap.allocationBlock, NativeLayout.wordBytes]
        change memory + capacity * 24 + 8 ≤ memory + localBytes capacity
        simpa only [Nat.add_assoc] using Nat.add_le_add_left
          (show capacity * 24 + 8 ≤ localBytes capacity by rw [bytes]; omega) memory)
      (by rw [same]; exact allocatedUnique)
    simpa only [Heap.allocationBlock, memory, same] using mapped
  have countBorrow (state : State) (same : state.heap = before.heap.borrowBlock memory) :
      mapRawNominalSlice extractedProgram state (.structure localCountId) memory 1 =
        .done (.rawSlice (.structure localCountId) memory 1) state := by
    have found := origin.allocatedBytes_containing (size := localBytes capacity) (budget := budget)
      (offset := 0) below (by decide : 0 < 8) (by omega)
    have borrowed := Heap.containingBlock?_borrowSelected found
    have mapped := mapRawNominalSlice_of_block (state := state) (address := memory)
      (block := { origin.allocationBlock (localBytes capacity) 8 with owned := false }) 1
      (by decide) rfl countLayout (by decide) (by omega) (by
        simpa only [NativeLayout.wordBytes, Nat.mul_one, Nat.one_mul, Nat.add_sub_cancel,
          same, allocated, memory, Heap.allocationBlock, Nat.add_zero] using borrowed)
      (by simpa only [NativeLayout.wordBytes, Nat.mul_one, Nat.one_mul, Nat.add_sub_cancel, memory] using
        origin.allocationAddress_aligned (alignment := 8)) (by change 8 ≤ 8; decide)
      (by dsimp only [Heap.allocationBlock, NativeLayout.wordBytes]
          exact Nat.add_le_add_left (Nat.le_of_lt extent) memory)
      (by rw [same]; exact allocatedUnique.borrowBlock)
    have borrowedHeap : state.heap.borrowBlock memory = state.heap := by rw [same, Heap.borrowBlock_idempotent]
    change mapRawNominalSlice extractedProgram state (.structure localCountId) memory 1 =
      .done (Value.rawSlice (.structure localCountId) memory 1)
        { state with heap := state.heap.borrowBlock memory } at mapped
    rw [borrowedHeap] at mapped
    cases state
    exact mapped
  have bindingCall {state : State} (same : state.heap = before.heap) (formed : state.CellsWellFormed) :
      ∃ after, RunsExpr extractedProgram state
        (.call Extracted.«lowering::locals».Functions.«binding_slice_from_raw_parts».core.id
          [.value (.pointer (memory + capacity * 24)), .value (.signed .i32 capacity)])
        (.rawSlice localBindingType (memory + capacity * 24) capacity) after ∧
        MemoryEffect (fun _ heap => heap = before.heap.borrowBlock memory) state after := by
    core_call_framed (RunsExpr.callEffect (MemoryEffect.scopeStable _))
      Extracted.«lowering::locals».Functions.«binding_slice_from_raw_parts».core as callee
    apply RunsStmt.returnEffect
    exact ⟨{ callee with heap := before.heap.borrowBlock memory },
      RunsExpr.nominalSliceFromParts (by core_run) (by core_run) (bindingBorrow callee same) rfl,
      ⟨(CallerFrame.refl (state := callee) (by core_formed)).cells, rfl, rfl, rfl⟩⟩
  simp only [localsValue, localFirst, Nat.ne_of_gt positive, if_false]
  core_call_framed (RunsExpr.callEffect (MemoryEffect.scopeStable _)) localsConstructor as callee
  let first := callee.bindLocal (localsConstructor.bindingId 0) (.pointer (memory + 8))
  let offsetState := first.bindLocal (localsConstructor.bindingId 1) (.signed .i32 (capacity * 24 : Nat))
  have calleeFormed : callee.CellsWellFormed := by core_formed
  have calleeMemory : callee.local? (localsConstructor.argumentId 0) = some (.pointer memory) := by core_local
  have calleeCapacity : callee.local? (localsConstructor.argumentId 1) = some (.signed .i32 capacity) := by core_local
  have pair : LocalPair callee offsetState (localsConstructor.bindingId 0) (localsConstructor.bindingId 1)
      (.pointer (memory + 8)) (.signed .i32 (capacity * 24 : Nat)) := LocalPair.start calleeFormed (by decide)
  have pointerAdd := eval_pointer_addNat extractedProgram.target memory (capacity * 24) pointerFits
  obtain ⟨updated, setFirst, updatedPair, updatedHeap, updatedWorld, updatedViews⟩ :=
    LocalPair.replaceFirst (program := extractedProgram) (expression := .binary .add
      (.local (localsConstructor.argumentId 0)) (.local (localsConstructor.bindingId 1)))
      pair calleeFormed (by exact noViews) ⟨offsetState, (by core_run), PureFrame.refl (by core_formed)⟩
  let scopedState := restoreLocals first updated
  have scopedFirst : scopedState.local? (localsConstructor.bindingId 0) = some (.pointer (memory + capacity * 24)) := by
    have found := updatedPair.first
    simp only [State.local?, updatedPair.firstCell, Option.bind_some] at found
    change (first.cellId? (localsConstructor.bindingId 0) >>= updated.cell?) = _
    rw [State.bindLocal_cellId]
    exact found
  have prefixRun : RunsStmt extractedProgram first firstGuard .next scopedState := by
    apply RunsStmt.ifThenElseTrue (by core_run)
    exact RunsStmt.letLocal (by core_run) (RunsStmt.sequenceNext (RunsStmt.expression setFirst) (RunsStmt.skip _ _))
  have prefixFrame : CallerFrame callee scopedState :=
    ⟨calleeFormed, updatedPair.cells, updatedHeap, updatedWorld, updatedViews⟩
  have scopedMemory : scopedState.local? (localsConstructor.argumentId 0) = some (.pointer memory) :=
    prefixFrame.cells.localFoundAt
      (State.bindLocal_cellId_of_ne callee _ _ (by decide) _) _ calleeMemory
  have scopedCapacity : scopedState.local? (localsConstructor.argumentId 1) = some (.signed .i32 capacity) :=
    prefixFrame.cells.localFoundAt
      (State.bindLocal_cellId_of_ne callee _ _ (by decide) _) _ calleeCapacity
  have scopedNoViews : scopedState.i32ArrayViews = [] := prefixFrame.views.trans noViews
  have rest : ∃ completed, RunsStmt extractedProgram scopedState (localsConstructor.bindingStatement 2)
      (.returned (some (source_value Extracted.«lowering::locals».Types.«Table».mk
        [.rawSlice localBindingType (memory + capacity * 24) capacity,
          .rawSlice (.structure localCountId) memory 1, .signed .i32 capacity]))) completed ∧
      MemoryEffect (fun _ heap => heap = before.heap.borrowBlock memory) scopedState completed := by
    apply RunsStmt.letMemoryEffect (id := localsConstructor.bindingId 2)
      (value := .rawSlice localBindingType (memory + capacity * 24) capacity)
    · apply RunsExpr.argumentsEffect
        (values := [.pointer (memory + capacity * 24), .signed .i32 capacity])
        (.cons (.ofStable (.local scopedFirst) rfl) (.cons (.ofStable (.local scopedCapacity) rfl) .nil))
      change ∃ after, RunsExpr extractedProgram scopedState
        (.call Extracted.«lowering::locals».Functions.«binding_slice_from_raw_parts».core.id
          [.value (.pointer (memory + capacity * 24)), .value (.signed .i32 capacity)])
        (.rawSlice localBindingType (memory + capacity * 24) capacity) after ∧ _
      exact bindingCall prefixFrame.heap prefixFrame.currentFormed
    intro ready entriesRun effect
    have readyFormed := entriesRun.cellsWellFormed prefixFrame.currentFormed
    have readyMemory := effect.1.localFound entriesRun.choose_spec.2 _ _ scopedMemory
    have readyCapacity := effect.1.localFound entriesRun.choose_spec.2 _ _ scopedCapacity
    core_state entered
    have same : entered.heap = before.heap.borrowBlock memory := effect.2.2.2
    have enteredUnique : HeapBlockBasesUnique entered.heap := by rw [same]; exact allocatedUnique.borrowBlock
    apply RunsStmt.letPure (id := localsConstructor.bindingId 3)
      (value := .rawSlice (.structure localCountId) memory 1)
    · exact RunsExpr.nominalSliceFromParts (middle := entered) (afterLength := entered) (after := entered)
        (.ofStable (.local (by core_local)) rfl) (.ofStable .value rfl) (countBorrow entered same) rfl
    · core_formed
    core_state counted
    have zero : counted.heap.loadBytes memory 4 = .ok (i32Bytes 0) := by
      rw [show counted.heap = before.heap.borrowBlock memory from same, Heap.loadBytes_borrowBlock, allocated]
      simpa only [memory, Nat.add_zero, show i32Bytes 0 = List.replicate 4 0 by rfl] using
        origin.allocatedBytes_zeroRange (size := localBytes capacity) (budget := budget) (offset := 0)
          below (by decide : 0 < 8) (by omega)
    have zeroCodec : NativeStoreSpec 64 extractedProgram (.scalar (.signed .i32)) (.signed .i32 0) 4 := by
      simpa using NativeStoreSpec.i32 (program := extractedProgram) (fuel := 63) (0 : BitVec 32)
    obtain ⟨heap, setCount, _, _, written⟩ := RunsExpr.assignRawFieldNative
      (program := extractedProgram) (before := counted) (indexed := counted) (ready := counted)
      (sourceId := localsConstructor.bindingId 3)
      (field := 0) (indexExpression := .value (.signed .i32 0)) (expression := .value (.signed .i32 0))
      (by core_local) (.ofStable .value rfl) (by decide) location countDecl rfl offset zeroCodec
      (by simpa only [Nat.add_zero] using Heap.Readable.of_loadBytes zero) enteredUnique
      (by exact effect.2.2.1.trans scopedNoViews) (.ofStable .value rfl)
    have unchanged : writeNativeValue 64 extractedProgram counted counted.heap (.scalar (.signed .i32))
        (memory + 0) (.signed .i32 0) = .ok counted.heap := by
      simpa only [writeNativeValue, Nat.add_zero] using
        Heap.storeBytes_same (heap := counted.heap) (bytes := i32Bytes 0) enteredUnique zero
    change writeNativeValue 64 extractedProgram counted counted.heap (.scalar (.signed .i32))
      (memory + 0) (.signed .i32 0) = .ok heap at written
    rw [unchanged] at written
    cases written
    have setCountSame : RunsExpr extractedProgram counted
        (.assign .set (.field (.index (.local (localsConstructor.bindingId 3)) (.value (.signed .i32 0))) 0)
          (.value (.signed .i32 0))) .unit counted := by
      have eta : { counted with heap := counted.heap } = counted := by cases counted; rfl
      exact Eq.mp (congrArg (fun after => RunsExpr extractedProgram counted
        (.assign .set (.field (.index (.local (localsConstructor.bindingId 3)) (.value (.signed .i32 0))) 0)
          (.value (.signed .i32 0))) .unit after) eta) setCount
    apply RunsStmt.sequencePureNext (RunsStmt.expression setCountSame)
    apply RunsStmt.returnPure
    refine ⟨counted, RunsExpr.structValue (before := counted) (after := counted) ?_, PureFrame.refl (by core_formed)⟩
    exact .cons (.ofStable (.local (by core_local)) rfl)
      (.cons (.ofStable (.local (by core_local)) rfl) (.cons (.ofStable (.local (by core_local)) rfl) .nil))
  obtain ⟨completed, body, effect⟩ := rest
  refine ⟨restoreLocals callee completed, ?_, ?_⟩
  · have initialAdd := eval_pointer_addNat extractedProgram.target memory 8 initialFits
    exact RunsStmt.letLocal (by core_run) (RunsStmt.sequenceNext prefixRun body)
  · exact (MemoryEffect.scopeStable _).restore callee (effect.prependCaller prefixFrame)

structure LocalStorage (origin : Heap) (memory capacity : Nat) (heap : Heap) : Prop where
  count : NativeSnapshot 64 extractedProgram heap (.scalar (.signed .i32)) memory (.signed .i32 0) 4
  backing : heap.Readable memory (localBytes capacity)
  reads : HeapReads origin heap
  unique : HeapBlockBasesUnique heap
  below : HeapBlocksBelowNext heap

/-- Post-host constructor contract for the genuine positive token-count route. -/
theorem actualLocalConstructor (capacity : Nat) (positive : 0 < capacity) (bounded : capacity ≤ 89478484)
    (allocated : before.heap = origin.allocatedBytes (localBytes capacity) 8 budget)
    (below : HeapBlocksBelowNext origin) (unique : HeapBlockBasesUnique origin)
    (fits : origin.allocationAddress 8 + localBytes capacity < 2 ^ 64)
    (formed : before.CellsWellFormed) (noViews : before.i32ArrayViews = []) :
    ∃ after, RunsExpr extractedProgram before (.call localsConstructor.id
      [.value (.pointer (origin.allocationAddress 8)), .value (.signed .i32 capacity)])
      (localsValue (origin.allocationAddress 8) capacity) after ∧
      MemoryEffect (fun _ heap => heap = before.heap.borrowBlock (origin.allocationAddress 8) ∧
        LocalStorage origin (origin.allocationAddress 8) capacity heap ∧
        HeapRegionWrite (before.heap.borrowBlock (origin.allocationAddress 8)) heap (origin.allocationAddress 8) 4) before after := by
  obtain ⟨after, run, effect⟩ := constructorRun capacity positive bounded allocated below unique fits formed noViews
  have same := effect.2.2.2
  have finalUnique : HeapBlockBasesUnique after.heap := by
    rw [same, allocated]; exact (origin.allocatedBytes_unique below unique (by decide)).borrowBlock
  have zero : after.heap.loadBytes (origin.allocationAddress 8) 4 = .ok (i32Bytes 0) := by
    rw [same, Heap.loadBytes_borrowBlock, allocated]
    simpa only [Nat.add_zero, show i32Bytes 0 = List.replicate 4 0 by rfl] using
      origin.allocatedBytes_zeroRange (size := localBytes capacity) (budget := budget) (offset := 0) below
        (by decide : 0 < 8) (by simp only [localBytes]; omega)
  have reads : HeapReads origin after.heap := by
    intro pointer offset byte loaded
    rw [same, Heap.loadByte_borrowBlock, allocated]
    exact Heap.allocatedBytes_oldRead loaded
  have backing : after.heap.Readable (origin.allocationAddress 8) (localBytes capacity) := by
    apply Heap.Readable.of_loadBytes
    rw [same, Heap.loadBytes_borrowBlock, allocated]
    simpa only [Nat.add_zero] using origin.allocatedBytes_zeroRange (size := localBytes capacity)
      (budget := budget) (offset := 0) below (by decide : 0 < 8) (by omega)
  refine ⟨after, run, effect.1, effect.2.1, effect.2.2.1, same,
    ⟨NativeSnapshot.i32 (fuel := 63) 0 zero, backing, reads, finalUnique, ?_⟩, ?_⟩
  · rw [same, allocated]; exact (origin.allocatedBytes_below below (by decide : 0 < 8)).borrowBlock
  · rw [← same]; exact HeapRegionWrite.refl _ finalUnique

#print axioms actualLocalConstructor

end IRBodyProductionInputs
