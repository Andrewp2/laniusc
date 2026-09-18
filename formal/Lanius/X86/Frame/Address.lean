import Lanius.X86.Source.Address
import Lanius.X86.Encode.Address
import Lanius.X86.Frame.Slot

namespace Lanius.X86.Frame.Address

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView.Core Lanius.X86.Source Lanius.X86.Buffer

def bytes (slot : Nat) (register : Fin 16) : List UInt8 :=
  Encode.Address.bytes register 5 (Frame.displacement slot)

@[simp] theorem bytes_length (slot : Nat) (register : Fin 16) : (bytes slot register).length = 7 := by
  simp [bytes, show (5 : Fin 16).val % 8 ≠ 4 by decide]

/-- The RHS reads the current workspace cursor, evaluates the actual frame
offset helper, and calls the source-authenticated public memory emitter. -/
theorem emit_rhs (checked : Source.Address.CheckedFrame program emit offset) (slot capacity start : Nat) (register : Fin 16)
    (wellFormed : StateWellFormed before) (slotBound : slot ≤ 1048576)
    (inputs : Locals (Slot.inputValues (.slice i32 output [] 0 values.length) capacity (.slice i32 work [] 0 workspace.length) slot register) frontier before)
    (backing : before.cellEntry? output = some { id := output, value := some (.array (signedI32Values values)) })
    (workspaceBacking : before.cellEntry? work = some { id := work, value := some (.array (signedI32Values workspace)) })
    (current : workspace[1]? = some (start : Int))
    (room : start + (bytes slot register).length ≤ capacity) (storage : capacity ≤ values.length)
    (bounded : capacity ≤ 2147483647) :
    ∃ after emitted, Evaluates program.core before
        (.call emit.source.function.id (Source.Address.frameArguments offset.source.function.id checked.code.id checked.base.id))
        (.signed .i32 (start + (bytes slot register).length : Nat)) after ∧
      after.cellEntry? output = some { id := output, value := some (.array (signedI32Values emitted)) } ∧
      byteSlice emitted start (bytes slot register).length = bytes slot register ∧
      emitted.length = values.length ∧
      (∀ index, index < start ∨ start + (bytes slot register).length ≤ index → emitted[index]? = values[index]?) ∧
      CellEffect (CellSet.singleton output) before after ∧ HeapFrame before after := by
  have currentRun := Slot.code_read checked.code checked.codeValue (inputs.found ⟨2, by simp⟩) workspaceBacking current
  obtain ⟨middle, offsetRun, offsetEffect, offsetHeap⟩ := Frame.displacement_call offset slot slotBound wellFormed
    (.cons (local_evaluates program.core (inputs.found ⟨3, by simp⟩)) (.nil _ _))
  have args : ArgumentsEvaluateTo program.core before
      (Source.Address.frameArguments offset.source.function.id checked.code.id checked.base.id)
      (Encode.Address.inputValues (.slice i32 output [] 0 values.length) capacity start register 5 (Frame.displacement slot)) middle :=
    .cons (local_evaluates program.core (inputs.found ⟨0, by simp⟩))
      (.cons (local_evaluates program.core (inputs.found ⟨1, by simp⟩))
        (.cons currentRun (.cons (local_evaluates program.core (inputs.found ⟨4, by simp⟩))
          (.cons (by
            change Evaluates program.core before (.constant checked.base.id) (.signed .i32 5) before
            rw [← checked.baseValue]
            exact checked.base.evaluates)
            (.cons offsetRun (.nil _ _))))))
  obtain ⟨after, emitted, run, contents, exactBytes, _, length, framed, effect, heap⟩ :=
    Encode.Address.emits emit register 5 (Frame.displacement slot) capacity start offsetEffect.wellFormed
      room storage bounded (offsetEffect.empty_preserves_entry wellFormed backing) args
  exact ⟨after, emitted, run, contents, exactBytes, length, framed,
    (offsetEffect.weaken CellSet.empty_subset).trans effect, offsetHeap.trans heap⟩

theorem body (checked : Source.Address.CheckedFrame program emit offset) (slot capacity start : Nat) (register : Fin 16)
    (wellFormed : StateWellFormed before) (slotBound : slot ≤ 1048576)
    (inputs : Locals (Slot.inputValues (.slice i32 output [] 0 values.length) capacity (.slice i32 work [] 0 workspace.length) slot register) frontier before)
    (distinct : output ≠ work)
    (backing : before.cellEntry? output = some { id := output, value := some (.array (signedI32Values values)) })
    (workspaceBacking : before.cellEntry? work = some { id := work, value := some (.array (signedI32Values workspace)) })
    (current : workspace[1]? = some (start : Int))
    (room : start + (bytes slot register).length ≤ capacity) (storage : capacity ≤ values.length)
    (bounded : capacity ≤ 2147483647) :
    ∃ after emitted, Executes program.core before
        (Source.Address.frameBody emit.source.function.id offset.source.function.id checked.code.id checked.base.id)
        (.returned (some (.signed .i32 (start + (bytes slot register).length : Nat)))) after ∧
      after.cellEntry? output = some { id := output, value := some (.array (signedI32Values emitted)) } ∧
      after.cellEntry? work = some { id := work, value := some (.array (signedI32Values
        (workspace.set 1 (start + (bytes slot register).length : Nat)))) } ∧
      byteSlice emitted start (bytes slot register).length = bytes slot register ∧
      emitted.length = values.length ∧
      (∀ index, index < start ∨ start + (bytes slot register).length ≤ index → emitted[index]? = values[index]?) ∧
      CellEffect (CellSet.union (CellSet.singleton output) (CellSet.singleton work)) before after ∧ HeapFrame before after := by
  have within : 1 < workspace.length := by
    by_cases inside : 1 < workspace.length
    · exact inside
    · rw [List.getElem?_eq_none (by omega)] at current
      cases current
  obtain ⟨written, emitted, rhsRun, outputContents, exactBytes, length, framed, rhsEffect, rhsHeap⟩ :=
    emit_rhs checked slot capacity start register wellFormed slotBound inputs backing workspaceBacking current room storage bounded
  have codeLiteral : Evaluates program.core before (.constant checked.code.id) (.signed .i32 (Int.ofNat 1)) before := by
    change Evaluates program.core before (.constant checked.code.id) (.signed .i32 1) before
    rw [← checked.codeValue]
    exact checked.code.evaluates
  obtain ⟨after, update, workContents, effect, updateHeap, updateEffect⟩ := evaluatesFramedSliceStore
    program.core before written workspace 2 (.constant checked.code.id)
      (.call emit.source.function.id (Source.Address.frameArguments offset.source.function.id checked.code.id checked.base.id))
      work 1 (start + (bytes slot register).length : Nat) wellFormed within
      (inputs.found ⟨2, by simp⟩) codeLiteral rhsRun rhsEffect (Ne.symm distinct) workspaceBacking
  have rightInputs := inputs.store wellFormed rhsEffect backing
    (fun index => Slot.inputs_not_array output work values.length workspace.length capacity slot register index _)
  have rightWork := rhsEffect.preserves_entry wellFormed workspaceBacking (Ne.symm distinct)
  have afterInputs := rightInputs.store rhsEffect.wellFormed updateEffect rightWork
    (fun index => Slot.inputs_not_array output work values.length workspace.length capacity slot register index _)
  have sliceAfter : after.local? 2 = some (.slice i32 work [] 0 workspace.length) := afterInputs.found ⟨2, by simp⟩
  have returned := Slot.code_read checked.code checked.codeValue
    (show after.local? 2 = some (.slice i32 work [] 0 (workspace.set 1 (start + (bytes slot register).length : Nat)).length) from
      by simpa only [List.length_set] using sliceAfter)
    workContents (List.getElem?_set_self within)
  exact ⟨after, emitted, executesSequence (executesExpression update) (executesSequenceReturned (executesReturnValue returned)),
    updateEffect.preserves_entry rhsEffect.wellFormed outputContents distinct,
    workContents, exactBytes, length, framed, effect, rhsHeap.trans updateHeap⟩

/-- Source-to-machine contract for the actual frame-slot address helper,
including its workspace cursor update around the LEA emitter call.
Output and workspace are distinct caller-owned arrays. -/
theorem emits (checked : Source.Address.CheckedFrame program emit offset) (slot capacity start : Nat) (register : Fin 16)
    (wellFormed : StateWellFormed before) (slotBound : slot ≤ 1048576) (distinct : output ≠ work)
    (backing : before.cellEntry? output = some { id := output, value := some (.array (signedI32Values values)) })
    (workspaceBacking : before.cellEntry? work = some { id := work, value := some (.array (signedI32Values workspace)) })
    (current : workspace[1]? = some (start : Int))
    (room : start + (bytes slot register).length ≤ capacity) (storage : capacity ≤ values.length)
    (bounded : capacity ≤ 2147483647)
    (argumentsResult : ArgumentsEvaluateTo program.core caller arguments
      (Slot.inputValues (.slice i32 output [] 0 values.length) capacity (.slice i32 work [] 0 workspace.length) slot register) before) :
    ∃ after emitted, Evaluates program.core caller (.call checked.internal.source.function.id arguments)
        (.signed .i32 (start + (bytes slot register).length : Nat)) after ∧
      after.cellEntry? output = some { id := output, value := some (.array (signedI32Values emitted)) } ∧
      after.cellEntry? work = some { id := work, value := some (.array (signedI32Values
        (workspace.set 1 (start + (bytes slot register).length : Nat)))) } ∧
      byteSlice emitted start (bytes slot register).length = bytes slot register ∧
      (∀ machine, Machine.CodeAt machine.memory machine.rip (byteSlice emitted start (bytes slot register).length) →
        Machine.Step machine (machine.address64 register 5 none 0 (BitVec.ofInt 32 (Frame.displacement slot))
          (bytes slot register).length)) ∧
      emitted.length = values.length ∧
      (∀ index, index < start ∨ start + (bytes slot register).length ≤ index → emitted[index]? = values[index]?) ∧
      CellEffect (CellSet.union (CellSet.singleton output) (CellSet.singleton work)) before after ∧ HeapFrame before after := by
  let params := parameterBindings (fun index : Fin 5 =>
    (Slot.inputValues (.slice i32 output [] 0 values.length) capacity (.slice i32 work [] 0 workspace.length) slot register).get index)
  let callee := enterCall before params
  have calleeWF := enterCall_preserves_wellFormed wellFormed (bindings := params)
  have inputs := Locals.ofReads (values := Slot.inputValues (.slice i32 output [] 0 values.length) capacity
      (.slice i32 work [] 0 workspace.length) slot register) calleeWF
    (fun index => enterCall_parameterBindings_matches wellFormed index)
  have initialOutput := ((enterCall_effect before params).oldCells output
    (StateWellFormed.cell_lt_next_of_entry wellFormed backing) (by simp [CellSet.empty])).trans backing
  have initialWork := ((enterCall_effect before params).oldCells work
    (StateWellFormed.cell_lt_next_of_entry wellFormed workspaceBacking) (by simp [CellSet.empty])).trans workspaceBacking
  obtain ⟨completed, emitted, run, outputContents, workContents, exactBytes, length, framed, effect, heap⟩ :=
    body checked slot capacity start register calleeWF slotBound inputs distinct
      initialOutput initialWork
      current room storage bounded
  have called := checked.internal.call wellFormed argumentsResult (bindings := params) rfl run effect
  refine ⟨restoreLocals before completed, emitted, called.1, outputContents, workContents, exactBytes,
    ?_, length, framed, called.2, HeapFrame.closeCall before params heap⟩
  intro machine loaded
  rw [exactBytes] at loaded
  exact .decoded _ loaded _ _ (by simpa only [bytes, List.append_nil] using
    (Encode.Address.decodes register 5 (Frame.displacement slot) [])) rfl

end Lanius.X86.Frame.Address
