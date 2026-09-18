import Lanius.X86.Source.Value.Get
import Lanius.X86.Frame.Slot
import Lanius.X86.Lower.Expression.Literal.Layout

namespace Lanius.X86.Lower.Value.Get

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView.Core Lanius.X86.Source Lanius.X86.Buffer

def kind : Register.Width → Int
  | .w32 => 1
  | .w64 => 4

@[simp] theorem kind_not_aggregate (width : Register.Width) :
    Expression.Literal.Layout.aggregateKind (kind width) = false := by
  cases width <;> rfl

def inputValues (width : Register.Width) (output : Value) (capacity : Int) (work : Value) (slot : Nat) : List Value :=
  [output, .signed .i32 capacity, work, .signed .i32 slot, .signed .i32 (kind width)]
def bytes (width : Register.Width) (slot : Nat) : List UInt8 :=
  Frame.Slot.bytes (match width with | .w32 => .load32 | .w64 => .load64) slot 0

theorem bytes_memory (width : Register.Width) (slot : Nat) :
    bytes width slot = Machine.memoryBytes width true 0 5 (Frame.displacement slot) := by
  cases width <;> rfl

@[simp] theorem inputValues_length : (inputValues width output capacity work slot).length = 5 := rfl

theorem bytes_eq (width : Register.Width) (slot : Nat) :
    bytes width slot = (match width with | .w32 => [139, 133] | .w64 => [72, 139, 133]) ++
      i32Bytes (Frame.displacement slot) := by cases width <;> rfl
@[simp] theorem bytes_length (width : Register.Width) (slot : Nat) :
    (bytes width slot).length = (match width with | .w32 => 6 | .w64 => 7) := by
  cases width <;> simp [bytes_eq, i32Bytes_length]

theorem inputs_not_array (width : Register.Width) (output work : CellId) (outputLength workLength : Nat) (capacity : Int) (slot : Nat) :
    ∀ index : Fin 5, ∀ elements,
      (inputValues width (.slice i32 output [] 0 outputLength) capacity (.slice i32 work [] 0 workLength) slot).get index ≠ .array elements := by
  intro ⟨index, bound⟩ elements
  have cases : index = 0 ∨ index = 1 ∨ index = 2 ∨ index = 3 ∨ index = 4 := by omega
  rcases cases with rfl | rfl | rfl | rfl | rfl <;> intro same <;> cases same

/-- Evaluate arguments in the actual source order, including the effectful
width and displacement calls. The selected MOV32 or MOV64 encoding is not assumed. -/
theorem emit_rhs (checked : Source.Value.Get.Checked program layout emit offset) (width : Register.Width) (slot capacity start : Nat)
    (wellFormed : StateWellFormed before) (slotBound : slot ≤ 1048576)
    (inputs : Locals (inputValues width (.slice i32 output [] 0 values.length) capacity
      (.slice i32 work [] 0 workspace.length) slot) frontier before)
    (backing : before.cellEntry? output = some { id := output, value := some (.array (signedI32Values values)) })
    (workspaceBacking : before.cellEntry? work = some { id := work, value := some (.array (signedI32Values workspace)) })
    (current : workspace[1]? = some (start : Int))
    (room : start + (bytes width slot).length ≤ capacity) (storage : capacity ≤ values.length) (bounded : capacity ≤ 2147483647) :
    ∃ after emitted, Evaluates program.core before
        (.call emit.source.function.id (Source.Value.Get.arguments layout.width.source.function.id offset.source.function.id
          checked.code.id checked.rax.id checked.base.id))
        (.signed .i32 (start + (bytes width slot).length : Nat)) after ∧
      after.cellEntry? output = some { id := output, value := some (.array (signedI32Values emitted)) } ∧
      byteSlice emitted start (bytes width slot).length = bytes width slot ∧ emitted.length = values.length ∧
      (∀ index, index < start ∨ start + (bytes width slot).length ≤ index → emitted[index]? = values[index]?) ∧
      CellEffect (CellSet.singleton output) before after ∧ HeapFrame before after := by
  have currentRun := Frame.Slot.code_read checked.code checked.values.1 (inputs.found ⟨2, by simp⟩) workspaceBacking current
  have widthCall : ∃ sized, Evaluates program.core before
      (.call layout.width.source.function.id [read 4]) (.signed .i32 width.bits) sized ∧
      CellEffect CellSet.empty before sized ∧ HeapFrame before sized := by
    cases width with
    | w32 =>
      exact Expression.Literal.Layout.width32 layout (.inl rfl) wellFormed
        (.cons (local_evaluates program.core (inputs.found ⟨4, by simp⟩)) (.nil _ _))
    | w64 =>
      exact Expression.Literal.Layout.width64 layout wellFormed
        (.cons (local_evaluates program.core (inputs.found ⟨4, by simp⟩)) (.nil _ _))
  obtain ⟨sized, widthRun, widthEffect, widthHeap⟩ := widthCall
  have sizedInputs := inputs.empty wellFormed widthEffect
  obtain ⟨displaced, offsetRun, offsetEffect, offsetHeap⟩ := Frame.displacement_call offset slot slotBound widthEffect.wellFormed
    (.cons (local_evaluates program.core (sizedInputs.found ⟨3, by simp⟩)) (.nil _ _))
  have rax := checked.rax.evaluates (before := sized)
  have base := checked.base.evaluates (before := sized)
  rw [checked.values.2.1] at rax
  rw [checked.values.2.2] at base
  have args : ArgumentsEvaluateTo program.core before
      (Source.Value.Get.arguments layout.width.source.function.id offset.source.function.id checked.code.id checked.rax.id checked.base.id)
      (Encode.Memory.moveValues (.slice i32 output [] 0 values.length) capacity start width 0 5 (Frame.displacement slot)) displaced :=
    .cons (local_evaluates program.core (inputs.found ⟨0, by simp⟩))
      (.cons (local_evaluates program.core (inputs.found ⟨1, by simp⟩))
        (.cons currentRun (.cons widthRun (.cons rax (.cons base (.cons offsetRun (.nil _ _)))))))
  have preparedEffect := widthEffect.trans offsetEffect
  obtain ⟨after, emitted, run, contents, exactBytes, _, length, framed, effect, heap⟩ :=
    Encode.Memory.move_emits emit width 0 5 (Frame.displacement slot) capacity start offsetEffect.wellFormed (by simpa only [bytes_memory] using room) storage bounded
      (preparedEffect.empty_preserves_entry wellFormed backing) args
  rw [← bytes_memory] at run exactBytes framed
  exact ⟨after, emitted, run, contents, exactBytes, length, framed,
    (preparedEffect.weaken CellSet.empty_subset).trans effect, (widthHeap.trans offsetHeap).trans heap⟩

theorem tail (checked : Source.Value.Get.Checked program layout emit offset) (width : Register.Width) (slot capacity start : Nat)
    (wellFormed : StateWellFormed before) (slotBound : slot ≤ 1048576)
    (inputs : Locals (inputValues width (.slice i32 output [] 0 values.length) capacity
      (.slice i32 work [] 0 workspace.length) slot) frontier before)
    (distinct : output ≠ work)
    (backing : before.cellEntry? output = some { id := output, value := some (.array (signedI32Values values)) })
    (workspaceBacking : before.cellEntry? work = some { id := work, value := some (.array (signedI32Values workspace)) })
    (current : workspace[1]? = some (start : Int))
    (room : start + (bytes width slot).length ≤ capacity) (storage : capacity ≤ values.length) (bounded : capacity ≤ 2147483647) :
    ∃ after emitted, Executes program.core before
        (Source.Value.Get.tail emit.source.function.id layout.width.source.function.id offset.source.function.id
          checked.code.id checked.rax.id checked.base.id)
        (.returned (some (.signed .i32 (start + (bytes width slot).length : Nat)))) after ∧
      after.cellEntry? output = some { id := output, value := some (.array (signedI32Values emitted)) } ∧
      after.cellEntry? work = some { id := work, value := some (.array (signedI32Values (workspace.set 1 (start + (bytes width slot).length : Nat)))) } ∧
      byteSlice emitted start (bytes width slot).length = bytes width slot ∧ emitted.length = values.length ∧
      (∀ index, index < start ∨ start + (bytes width slot).length ≤ index → emitted[index]? = values[index]?) ∧
      CellEffect (CellSet.union (CellSet.singleton output) (CellSet.singleton work)) before after ∧ HeapFrame before after := by
  have within : 1 < workspace.length := by
    by_cases inside : 1 < workspace.length
    · exact inside
    · rw [List.getElem?_eq_none (by omega)] at current
      cases current
  obtain ⟨written, emitted, rhsRun, outputContents, exactBytes, length, framed, rhsEffect, rhsHeap⟩ :=
    emit_rhs checked width slot capacity start wellFormed slotBound inputs backing workspaceBacking current room storage bounded
  have codeLiteral := checked.code.evaluates (before := before)
  rw [checked.values.1] at codeLiteral
  obtain ⟨after, update, workContents, effect, updateHeap, updateEffect⟩ := evaluatesFramedSliceStore
    program.core before written workspace 2 (.constant checked.code.id)
      (.call emit.source.function.id (Source.Value.Get.arguments layout.width.source.function.id offset.source.function.id
        checked.code.id checked.rax.id checked.base.id))
      work 1 (start + (bytes width slot).length : Nat) wellFormed within (inputs.found ⟨2, by simp⟩)
      codeLiteral rhsRun rhsEffect (Ne.symm distinct) workspaceBacking
  have rightInputs := inputs.store wellFormed rhsEffect backing
    (fun index => inputs_not_array width output work values.length workspace.length capacity slot index _)
  have rightWork := rhsEffect.preserves_entry wellFormed workspaceBacking (Ne.symm distinct)
  have afterInputs := rightInputs.store rhsEffect.wellFormed updateEffect rightWork
    (fun index => inputs_not_array width output work values.length workspace.length capacity slot index _)
  have sliceAfter : after.local? 2 = some (.slice i32 work [] 0 (workspace.set 1 (start + (bytes width slot).length : Nat)).length) :=
    by simpa [inputValues] using afterInputs.found ⟨2, by simp⟩
  have returned := Frame.Slot.code_read checked.code checked.values.1 sliceAfter workContents (List.getElem?_set_self within)
  exact ⟨after, emitted, executesSequence (executesExpression update) (executesSequenceReturned (executesReturnValue returned)),
    updateEffect.preserves_entry rhsEffect.wellFormed outputContents distinct,
    workContents, exactBytes, length, framed, effect, rhsHeap.trans updateHeap⟩

/-- The actual scalar or pointer get body rejects the aggregate branch via the
proved layout predicate, then emits its scalar stack load and records CODE. -/
theorem body (checked : Source.Value.Get.Checked program layout emit offset) (width : Register.Width) (slot capacity start : Nat)
    (wellFormed : StateWellFormed before) (slotBound : slot ≤ 1048576)
    (inputs : Locals (inputValues width (.slice i32 output [] 0 values.length) capacity
      (.slice i32 work [] 0 workspace.length) slot) frontier before)
    (distinct : output ≠ work)
    (backing : before.cellEntry? output = some { id := output, value := some (.array (signedI32Values values)) })
    (workspaceBacking : before.cellEntry? work = some { id := work, value := some (.array (signedI32Values workspace)) })
    (current : workspace[1]? = some (start : Int))
    (room : start + (bytes width slot).length ≤ capacity) (storage : capacity ≤ values.length) (bounded : capacity ≤ 2147483647) :
    ∃ after emitted, Executes program.core before
        (Source.Value.Get.body layout.aggregate.source.function.id emit.source.function.id layout.width.source.function.id
          offset.source.function.id checked.code.id checked.rax.id checked.base.id checked.aggregateBranch)
        (.returned (some (.signed .i32 (start + (bytes width slot).length : Nat)))) after ∧
      after.cellEntry? output = some { id := output, value := some (.array (signedI32Values emitted)) } ∧
      after.cellEntry? work = some { id := work, value := some (.array (signedI32Values (workspace.set 1 (start + (bytes width slot).length : Nat)))) } ∧
      byteSlice emitted start (bytes width slot).length = bytes width slot ∧ emitted.length = values.length ∧
      (∀ index, index < start ∨ start + (bytes width slot).length ≤ index → emitted[index]? = values[index]?) ∧
      CellEffect (CellSet.union (CellSet.singleton output) (CellSet.singleton work)) before after ∧ HeapFrame before after := by
  obtain ⟨guarded, guardRun, guardEffect, guardHeap⟩ := Expression.Literal.Layout.aggregate layout (kind width) wellFormed
    (.cons (local_evaluates program.core (inputs.found ⟨4, by simp⟩)) (.nil _ _))
  simp only [kind_not_aggregate] at guardRun
  obtain ⟨after, emitted, run, outputContents, workContents, exactBytes, length, framed, effect, heap⟩ :=
    tail checked width slot capacity start guardEffect.wellFormed slotBound (inputs.empty wellFormed guardEffect) distinct
      (guardEffect.empty_preserves_entry wellFormed backing) (guardEffect.empty_preserves_entry wellFormed workspaceBacking)
      current room storage bounded
  exact ⟨after, emitted, executesSequence (executesIfFalse guardRun (executesSkip _ _)) run,
    outputContents, workContents, exactBytes, length, framed,
    (guardEffect.weaken CellSet.empty_subset).trans effect, guardHeap.trans heap⟩

theorem emits (checked : Source.Value.Get.Checked program layout emit offset) (width : Register.Width) (slot capacity start : Nat)
    (wellFormed : StateWellFormed before) (slotBound : slot ≤ 1048576) (distinct : output ≠ work)
    (backing : before.cellEntry? output = some { id := output, value := some (.array (signedI32Values values)) })
    (workspaceBacking : before.cellEntry? work = some { id := work, value := some (.array (signedI32Values workspace)) })
    (current : workspace[1]? = some (start : Int))
    (room : start + (bytes width slot).length ≤ capacity) (storage : capacity ≤ values.length) (bounded : capacity ≤ 2147483647)
    (argumentsResult : ArgumentsEvaluateTo program.core caller arguments
      (inputValues width (.slice i32 output [] 0 values.length) capacity (.slice i32 work [] 0 workspace.length) slot) before) :
    ∃ after emitted, Evaluates program.core caller (.call checked.internal.source.function.id arguments)
        (.signed .i32 (start + (bytes width slot).length : Nat)) after ∧
      after.cellEntry? output = some { id := output, value := some (.array (signedI32Values emitted)) } ∧
      after.cellEntry? work = some { id := work, value := some (.array (signedI32Values (workspace.set 1 (start + (bytes width slot).length : Nat)))) } ∧
      byteSlice emitted start (bytes width slot).length = bytes width slot ∧
      (∀ machine, Machine.CodeAt machine.memory machine.rip (byteSlice emitted start (bytes width slot).length) →
        Machine.Step machine (Machine.execute
          (Machine.memoryInstruction width true 0 5 (BitVec.ofInt 32 (Frame.displacement slot)))
          (bytes width slot).length machine)) ∧
      emitted.length = values.length ∧
      (∀ index, index < start ∨ start + (bytes width slot).length ≤ index → emitted[index]? = values[index]?) ∧
      CellEffect (CellSet.union (CellSet.singleton output) (CellSet.singleton work)) before after ∧ HeapFrame before after := by
  let params := parameterBindings (fun index : Fin 5 =>
    (inputValues width (.slice i32 output [] 0 values.length) capacity (.slice i32 work [] 0 workspace.length) slot).get index)
  let callee := enterCall before params
  have calleeWF := enterCall_preserves_wellFormed wellFormed (bindings := params)
  have inputs := Locals.ofReads (values := inputValues width (.slice i32 output [] 0 values.length) capacity
      (.slice i32 work [] 0 workspace.length) slot) calleeWF
    (fun index => enterCall_parameterBindings_matches wellFormed index)
  have initialOutput := ((enterCall_effect before params).oldCells output
    (StateWellFormed.cell_lt_next_of_entry wellFormed backing) (by simp [CellSet.empty])).trans backing
  have initialWork := ((enterCall_effect before params).oldCells work
    (StateWellFormed.cell_lt_next_of_entry wellFormed workspaceBacking) (by simp [CellSet.empty])).trans workspaceBacking
  obtain ⟨completed, emitted, run, outputContents, workContents, exactBytes, length, framed, effect, heap⟩ :=
    body checked width slot capacity start calleeWF slotBound inputs distinct initialOutput initialWork current room storage bounded
  have called := checked.internal.call wellFormed argumentsResult (bindings := params) rfl run effect
  refine ⟨restoreLocals before completed, emitted, called.1, outputContents, workContents, exactBytes,
    ?_, length, framed, called.2, HeapFrame.closeCall before params heap⟩
  intro machine loaded
  rw [exactBytes] at loaded
  exact .decoded _ loaded _ _ (by
    simpa only [bytes_memory, List.append_nil] using
      Machine.memory_decodes width true 0 5 (Frame.displacement slot) []) rfl

end Lanius.X86.Lower.Value.Get
