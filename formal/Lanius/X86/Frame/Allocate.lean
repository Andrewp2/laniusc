import Lanius.X86.Source.Allocate
import Lanius.X86.Buffer.Locals
import Lanius.X86.Buffer.Reservation
import Lanius.Separation.SliceStore

namespace Lanius.X86.Frame.Allocate

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView.Core Lanius.X86.Source Lanius.X86.Buffer

def limit : Nat := 1048576

/-- Compiler workspace ownership, separate from the native stack being laid out. -/
structure Ready (state : State) (work : CellId) (values : List Int) (count : Int) : Prop where
  wellFormed : StateWellFormed state
  slice : state.local? 0 = some (.slice i32 work [] 0 values.length)
  request : state.local? 1 = some (.signed .i32 count)
  backing : state.cellEntry? work = some { id := work, value := some (.array (signedI32Values values)) }

theorem Ready.field (ready : Ready before work values count) (constant : IntegerConstant program)
    (index : Nat) (identity : constant.value = index) (found : values[index]? = some value) :
    Evaluates program before (Source.Allocate.field constant.id) (.signed .i32 value) before := by
  have bound : index < values.length := by
    by_cases inside : index < values.length
    · exact inside
    · rw [List.getElem?_eq_none (by omega)] at found
      cases found
  have exactValue : values.get ⟨index, bound⟩ = value := by
    change values[index] = value
    simpa only [List.getElem?_eq_getElem bound, Option.some.injEq] using found
  have literal := constant.evaluates (before := before)
  rw [identity] at literal
  have run := evaluatesSignedI32SliceIndex program before before before values (read 0) (.constant constant.id)
    work index bound (local_evaluates program ready.slice) literal ready.backing
  rw [exactValue] at run
  exact run

theorem Ready.assign (ready : Ready before work values count) (constant : IntegerConstant program)
    (index : Nat) (identity : constant.value = index) (bound : index < values.length)
    (op : AssignOp) (run : Evaluates program before right (.signed .i32 value) before)
    (operation : evalAssignValue program.target op (some (.signed .i32 (values.get ⟨index, bound⟩)))
      (.signed .i32 value) = .ok (.signed .i32 replacement)) :
    ∃ after, Executes program before (Source.Allocate.assign constant.id op right) .next after ∧
      Ready after work (values.set index replacement) count ∧
      CellEffect (CellSet.singleton work) before after ∧ HeapFrame before after := by
  have literal := constant.evaluates (before := before)
  rw [identity] at literal
  obtain ⟨after, update, contents, _, heap, effect⟩ := evaluatesFramedSliceAssign program before before
    values 0 (.constant constant.id) right work index op value replacement ready.wellFormed bound
    ready.slice literal run (CellEffect.refl (writes := CellSet.empty) ready.wellFormed)
    (by simp [CellSet.empty]) operation ready.backing
  refine ⟨after, executesExpression update, ⟨effect.wellFormed, ?_, ?_, contents⟩, effect, heap⟩
  · simpa only [List.length_set] using effect.preserves_local_of_distinct_value ready.wellFormed ready.slice
      ready.backing (by intro same; cases same)
  · exact effect.preserves_local_of_distinct_value ready.wellFormed ready.request ready.backing (by intro same; cases same)

theorem Ready.set (ready : Ready before work values count) (constant : IntegerConstant program)
    (index : Nat) (identity : constant.value = index) (bound : index < values.length)
    (run : Evaluates program before right (.signed .i32 value) before) :
    ∃ after, Executes program before (Source.Allocate.assign constant.id .set right) .next after ∧
      Ready after work (values.set index value) count ∧
      CellEffect (CellSet.singleton work) before after ∧ HeapFrame before after :=
  ready.assign constant index identity bound .set run (by simp [evalAssignValue, assignOpBinary?])

theorem guard (checked : Source.Allocate.Checked program) (ready : Ready before work values count)
    (top : Nat) (bounded : top ≤ limit) (current : values[6]? = some (top : Int)) :
    Evaluates program.core before (Source.Allocate.guard checked.top.id)
      (.boolean (decide (count < 1 ∨ ((limit - top : Nat) : Int) < count))) before := by
  have low : Evaluates program.core before (.binary .less (read 1) (number 1))
      (.boolean (decide (count < 1))) before := by
    apply evaluatesEagerBinary (by decide) (by decide) (local_evaluates _ ready.request)
      (show Evaluates program.core before (number 1) (.signed .i32 1) before from ⟨1, rfl⟩)
    rfl
  have remaining := evaluatesNatI32Subtract
    (show Evaluates program.core before (number 1048576) (.signed .i32 (limit : Int)) before from ⟨1, rfl⟩)
    (ready.field checked.top 6 checked.values.1 current) bounded (by unfold limit at *; omega)
  have high : Evaluates program.core before
      (.binary .greater (read 1) (.binary .subtract (number 1048576) (Source.Allocate.field checked.top.id)))
      (.boolean (decide (((limit - top : Nat) : Int) < count))) before := by
    apply evaluatesEagerBinary (by decide) (by decide) (local_evaluates _ ready.request) remaining
    rfl
  simpa only [Source.Allocate.guard, Bool.decide_or] using evaluatesPureLogicalOr low high

def updated (values : List Int) (top peak count : Nat) : List Int :=
  let pushed := values.set 6 (top + count : Nat)
  if peak < top + count then pushed.set 2 (top + count : Nat) else pushed

theorem updated_top {top peak count : Nat} (within : 6 < values.length) :
    (updated values top peak count)[6]? = some ((top + count : Nat) : Int) := by
  unfold updated
  split <;> simp [List.getElem?_set, within]

theorem updated_peak {top peak count : Nat} (within : 6 < values.length) (current : values[2]? = some (peak : Int)) :
    (updated values top peak count)[2]? = some ((max peak (top + count) : Nat) : Int) := by
  unfold updated
  split
  · rename_i grows
    simp [List.getElem?_set, show 2 < values.length by omega, Nat.max_eq_right (by omega : peak ≤ top + count)]
  · rename_i stays
    simp [List.getElem?_set, current, Nat.max_eq_left (by omega : top + count ≤ peak)]

@[simp] theorem updated_length : (updated values top peak count).length = values.length := by
  unfold updated
  split <;> simp

theorem updated_frame (other : index ≠ 6 ∧ index ≠ 2) :
    (updated values top peak count)[index]? = values[index]? := by
  unfold updated
  split <;> simp [List.getElem?_set, Ne.symm other.1, Ne.symm other.2]

theorem body_success (checked : Source.Allocate.Checked program)
    (top peak count : Nat) (ready : Ready before work values (count : Int))
    (within : 6 < values.length) (current : values[6]? = some (top : Int))
    (watermark : values[2]? = some (peak : Int)) (ordered : top ≤ peak) (bounded : peak ≤ limit)
    (positive : 0 < count) (room : top + count ≤ limit) :
    ∃ after, Executes program.core before (Source.Allocate.body checked.top.id checked.slots.id checked.failed.id)
        (.returned (some (.signed .i32 (top + count - 1 : Nat)))) after ∧
      Ready after work (updated values top peak count) count ∧
      CellEffect (CellSet.singleton work) before after ∧ HeapFrame before after := by
  have guardRun := guard checked ready top (by omega) current
  have accepted : ¬ ((count : Int) < 1 ∨ ((limit - top : Nat) : Int) < count) := by omega
  simp only [accepted, decide_false] at guardRun
  have old : values.get ⟨6, within⟩ = (top : Int) := by
    change values[6] = (top : Int)
    simpa only [List.getElem?_eq_getElem within, Option.some.injEq] using current
  obtain ⟨pushed, pushRun, pushReady, pushEffect, pushHeap⟩ := ready.assign checked.top 6 checked.values.1 within
    .add (local_evaluates _ ready.request) (replacement := (top + count : Nat)) (by
      simp only [evalAssignValue, assignOpBinary?, old, evalBinaryValue, evalSignedBinary]
      change Except.ok (Value.signed .i32 (wrapSigned program.core.target .i32 ((top : Int) + (count : Int)))) = _
      rw [← Int.natCast_add]
      exact congrArg (fun value => Except.ok (Value.signed .i32 value))
        (wrapSigned_i32_ofNat program.core.target (top + count) (by unfold limit at room; omega)))
  have pushedTop := pushReady.field checked.top 6 checked.values.1 (List.getElem?_set_self within)
  have pushedPeak := pushReady.field checked.slots 2 checked.values.2.1
    (by simpa [List.getElem?_set] using watermark)
  have grows : Evaluates program.core pushed
      (.binary .greater (Source.Allocate.field checked.top.id) (Source.Allocate.field checked.slots.id))
      (.boolean (decide (peak < top + count))) pushed := by
    apply evaluatesEagerBinary (by decide) (by decide) pushedTop pushedPeak
    simp [evalBinaryValue, evalSignedBinary]
    omega
  have continuation (state : State) (newReady : Ready state work (updated values top peak count) count) :
      Executes program.core state (returned (.binary .subtract (Source.Allocate.field checked.top.id) (number 1)))
        (.returned (some (.signed .i32 (top + count - 1 : Nat)))) state := by
    have result := evaluatesNatI32Subtract (leftValue := top + count) (rightValue := 1)
      (newReady.field checked.top 6 checked.values.1 (updated_top within))
      (show Evaluates program.core state (number 1) (.signed .i32 1) state from ⟨1, rfl⟩)
      (by omega) (by unfold limit at room; omega)
    exact executesSequenceReturned (executesReturnValue result)
  by_cases larger : peak < top + count
  · simp only [larger, decide_true] at grows
    obtain ⟨after, markRun, markReady, markEffect, markHeap⟩ := pushReady.set checked.slots 2 checked.values.2.1
      (by simpa only [List.length_set] using (show 2 < values.length by omega)) pushedTop
    have afterReady : Ready after work (updated values top peak count) count := by
      simpa only [updated, if_pos larger] using markReady
    exact ⟨after, executesSequence (executesIfFalse guardRun (executesSkip _ _))
      (executesSequence pushRun (executesSequence
        (executesIfTrue grows (executesSequence markRun (executesSkip _ _))) (continuation after afterReady))),
      afterReady, pushEffect.trans markEffect, pushHeap.trans markHeap⟩
  · simp only [larger, decide_false] at grows
    have afterReady : Ready pushed work (updated values top peak count) count := by
      simpa only [updated, if_neg larger] using pushReady
    exact ⟨pushed, executesSequence (executesIfFalse guardRun (executesSkip _ _))
      (executesSequence pushRun (executesSequence (executesIfFalse grows (executesSkip _ _))
        (continuation pushed afterReady))), afterReady, pushEffect, pushHeap⟩

theorem body_reject (checked : Source.Allocate.Checked program) (ready : Ready before work values count)
    (top : Nat) (within : 6 < values.length) (current : values[6]? = some (top : Int))
    (bounded : top ≤ limit) (rejected : count < 1 ∨ ((limit - top : Nat) : Int) < count) :
    ∃ after, Executes program.core before (Source.Allocate.body checked.top.id checked.slots.id checked.failed.id)
        (.returned (some (.signed .i32 (-1)))) after ∧
      Ready after work (values.set 4 1) count ∧
      CellEffect (CellSet.singleton work) before after ∧ HeapFrame before after := by
  have guardRun := guard checked ready top bounded current
  simp only [rejected, decide_true] at guardRun
  obtain ⟨after, markRun, markReady, markEffect, markHeap⟩ := ready.set checked.failed 4 checked.values.2.2
    (by omega) (show Evaluates program.core before (number 1) (.signed .i32 1) before from ⟨1, rfl⟩)
  have result : Evaluates program.core after (.unary .negate (number 1)) (.signed .i32 (-1)) after := by
    apply evaluatesUnary (show Evaluates program.core after (number 1) (.signed .i32 1) after from ⟨1, rfl⟩)
    simp [evalUnaryValue, wrapSigned_i32_neg_one]
  exact ⟨after, executesSequenceReturned (executesIfTrue guardRun
    (executesSequence markRun (executesSequenceReturned (executesReturnValue result)))), markReady, markEffect, markHeap⟩

def inputValues (work : CellId) (length : Nat) (count : Int) : List Value :=
  [.slice i32 work [] 0 length, .signed .i32 count]

private theorem call_body (checked : Source.Allocate.Checked program)
    (wellFormed : StateWellFormed before)
    (backing : before.cellEntry? work = some { id := work, value := some (.array (signedI32Values values)) })
    (argumentsResult : ArgumentsEvaluateTo program.core caller arguments (inputValues work values.length count) before)
    (body : ∀ initial, Ready initial work values count →
      ∃ completed, Executes program.core initial
          (Source.Allocate.body checked.top.id checked.slots.id checked.failed.id)
          (.returned (some (.signed .i32 result))) completed ∧
        Ready completed work nextValues count ∧
        CellEffect (CellSet.singleton work) initial completed ∧ HeapFrame initial completed) :
    ∃ after, Evaluates program.core caller (.call checked.internal.source.function.id arguments)
        (.signed .i32 result) after ∧
      after.cellEntry? work = some { id := work, value := some (.array (signedI32Values nextValues)) } ∧
      CellEffect (CellSet.singleton work) before after ∧ HeapFrame before after := by
  let params := parameterBindings (fun index : Fin 2 => (inputValues work values.length count).get index)
  have initialBacking := ((enterCall_effect before params).oldCells work
    (StateWellFormed.cell_lt_next_of_entry wellFormed backing) (by simp [CellSet.empty])).trans backing
  have ready : Ready (enterCall before params) work values count :=
    ⟨enterCall_preserves_wellFormed wellFormed,
      enterCall_parameterBindings_matches wellFormed ⟨0, by decide⟩,
      enterCall_parameterBindings_matches wellFormed ⟨1, by decide⟩, initialBacking⟩
  obtain ⟨completed, run, afterReady, effect, heap⟩ := body _ ready
  have called := checked.internal.call wellFormed argumentsResult (bindings := params) rfl run effect
  exact ⟨restoreLocals before completed, called.1, afterReady.backing, called.2, HeapFrame.closeCall before params heap⟩

/-- The actual allocator reserves slots `[top, top + count)`, returns their
last slot, and updates only TOP and (when needed) SLOTS. Caller bindings and
all cells except the owned workspace are preserved. -/
theorem succeeds (checked : Source.Allocate.Checked program) (top peak count : Nat)
    (wellFormed : StateWellFormed before)
    (backing : before.cellEntry? work = some { id := work, value := some (.array (signedI32Values values)) })
    (within : 6 < values.length) (current : values[6]? = some (top : Int))
    (watermark : values[2]? = some (peak : Int)) (ordered : top ≤ peak) (bounded : peak ≤ limit)
    (positive : 0 < count) (room : top + count ≤ limit)
    (argumentsResult : ArgumentsEvaluateTo program.core caller arguments (inputValues work values.length count) before) :
    ∃ after, Evaluates program.core caller (.call checked.internal.source.function.id arguments)
        (.signed .i32 (top + count - 1 : Nat)) after ∧
      after.cellEntry? work = some { id := work, value := some (.array (signedI32Values (updated values top peak count))) } ∧
      CellEffect (CellSet.singleton work) before after ∧ HeapFrame before after :=
  call_body checked wellFormed backing argumentsResult
    (fun _ ready => body_success checked top peak count ready within current watermark ordered bounded positive room)

/-- Invalid counts and exhausted slot capacity return -1 and set FAILED;
TOP, SLOTS, the rest of the workspace, and the caller are unchanged. -/
theorem rejects (checked : Source.Allocate.Checked program) (top : Nat) (count : Int)
    (wellFormed : StateWellFormed before)
    (backing : before.cellEntry? work = some { id := work, value := some (.array (signedI32Values values)) })
    (within : 6 < values.length) (current : values[6]? = some (top : Int))
    (bounded : top ≤ limit) (rejected : count < 1 ∨ ((limit - top : Nat) : Int) < count)
    (argumentsResult : ArgumentsEvaluateTo program.core caller arguments (inputValues work values.length count) before) :
    ∃ after, Evaluates program.core caller (.call checked.internal.source.function.id arguments)
        (.signed .i32 (-1)) after ∧
      after.cellEntry? work = some { id := work, value := some (.array (signedI32Values (values.set 4 1))) } ∧
      CellEffect (CellSet.singleton work) before after ∧ HeapFrame before after :=
  call_body checked wellFormed backing argumentsResult
    (fun _ ready => body_reject checked ready top within current bounded rejected)

end Lanius.X86.Frame.Allocate
