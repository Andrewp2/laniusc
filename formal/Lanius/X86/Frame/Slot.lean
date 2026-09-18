import Lanius.X86.Source.Slot
import Lanius.X86.Encode.Memory

namespace Lanius.X86.Frame.Slot

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView.Core Lanius.X86.Source Lanius.X86.Buffer

def inputValues (output : Value) (capacity : Int) (work : Value) (slot : Nat) (register : Fin 16) : List Value :=
  [output, .signed .i32 capacity, work, .signed .i32 slot, .signed .i32 register.val]

@[simp] theorem inputValues_length : (inputValues output capacity work slot register).length = 5 := rfl

theorem inputs_not_array (output work : CellId) (outputLength workLength : Nat) (capacity : Int) (slot : Nat) (register : Fin 16) :
    ∀ index : Fin 5, ∀ elements,
      (inputValues (.slice i32 output [] 0 outputLength) capacity (.slice i32 work [] 0 workLength) slot register).get index ≠ .array elements := by
  intro ⟨index, bound⟩ elements
  have cases : index = 0 ∨ index = 1 ∨ index = 2 ∨ index = 3 ∨ index = 4 := by omega
  rcases cases with rfl | rfl | rfl | rfl | rfl <;> intro same <;> cases same

theorem code_read (entry : IntegerConstant program) (codeValue : entry.value = 1)
    (sliceRead : before.local? 2 = some (.slice i32 cell [] 0 values.length))
    (backing : before.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values values)) })
    (current : values[1]? = some cursor) :
    Evaluates program before (Source.Slot.cursor entry.id) (.signed .i32 cursor) before := by
  have bound : 1 < values.length := by
    by_cases inside : 1 < values.length
    · exact inside
    · rw [List.getElem?_eq_none (by omega)] at current
      cases current
  have lookup : values.get ⟨1, bound⟩ = cursor := by
    change values[1] = cursor
    simpa only [List.getElem?_eq_getElem bound, Option.some.injEq] using current
  have literal : Evaluates program before (.constant entry.id) (.signed .i32 (Int.ofNat 1)) before := by
    change Evaluates program before (.constant entry.id) (.signed .i32 1) before
    rw [← codeValue]
    exact entry.evaluates
  have run := evaluatesSignedI32SliceIndex program before before before values (read 2) (.constant entry.id) cell 1 bound
    (local_evaluates program sliceRead) literal backing
  rw [lookup] at run
  exact run

def bytes (kind : Source.Slot.Kind) (slot : Nat) (register : Fin 16) : List UInt8 :=
  Machine.memoryBytes kind.width kind.load register 5 (Frame.displacement slot)

/-- The RHS reads the current workspace cursor, evaluates the actual frame
offset helper, and calls the source-authenticated public memory emitter. -/
theorem emit_rhs (checked : Source.Slot.Checked program kind emit offset) (slot capacity start : Nat) (register : Fin 16)
    (wellFormed : StateWellFormed before) (slotBound : slot ≤ 1048576)
    (inputs : Locals (inputValues (.slice i32 output [] 0 values.length) capacity (.slice i32 work [] 0 workspace.length) slot register) frontier before)
    (backing : before.cellEntry? output = some { id := output, value := some (.array (signedI32Values values)) })
    (workspaceBacking : before.cellEntry? work = some { id := work, value := some (.array (signedI32Values workspace)) })
    (current : workspace[1]? = some (start : Int))
    (room : start + (bytes kind slot register).length ≤ capacity) (storage : capacity ≤ values.length)
    (bounded : capacity ≤ 2147483647) :
    ∃ after emitted, Evaluates program.core before
        (.call emit.source.function.id (Source.Slot.arguments kind offset.source.function.id checked.code.id checked.base.id))
        (.signed .i32 (start + (bytes kind slot register).length : Nat)) after ∧
      after.cellEntry? output = some { id := output, value := some (.array (signedI32Values emitted)) } ∧
      byteSlice emitted start (bytes kind slot register).length = bytes kind slot register ∧
      emitted.length = values.length ∧
      (∀ index, index < start ∨ start + (bytes kind slot register).length ≤ index → emitted[index]? = values[index]?) ∧
      CellEffect (CellSet.singleton output) before after ∧ HeapFrame before after := by
  have currentRun := code_read checked.code checked.codeValue (inputs.found ⟨2, by simp⟩) workspaceBacking current
  obtain ⟨middle, offsetRun, offsetEffect, offsetHeap⟩ := Frame.displacement_call offset slot slotBound wellFormed
    (.cons (local_evaluates program.core (inputs.found ⟨3, by simp⟩)) (.nil _ _))
  have args : ArgumentsEvaluateTo program.core before
      (Source.Slot.arguments kind offset.source.function.id checked.code.id checked.base.id)
      (Encode.Memory.moveValues (.slice i32 output [] 0 values.length) capacity start kind.width register 5 (Frame.displacement slot)) middle :=
    .cons (local_evaluates program.core (inputs.found ⟨0, by simp⟩))
      (.cons (local_evaluates program.core (inputs.found ⟨1, by simp⟩))
        (.cons currentRun (.cons ⟨1, rfl⟩ (.cons (local_evaluates program.core (inputs.found ⟨4, by simp⟩))
          (.cons (by
            change Evaluates program.core before (.constant checked.base.id) (.signed .i32 5) before
            rw [← checked.baseValue]
            exact checked.base.evaluates)
            (.cons offsetRun (.nil _ _)))))))
  obtain ⟨after, emitted, run, contents, exactBytes, _, length, framed, effect, heap⟩ :=
    Encode.Memory.move_emits emit kind.width register 5 (Frame.displacement slot) capacity start offsetEffect.wellFormed
      room storage bounded (offsetEffect.empty_preserves_entry wellFormed backing) args
  exact ⟨after, emitted, run, contents, exactBytes, length, framed,
    (offsetEffect.weaken CellSet.empty_subset).trans effect, offsetHeap.trans heap⟩

theorem body (checked : Source.Slot.Checked program kind emit offset) (slot capacity start : Nat) (register : Fin 16)
    (wellFormed : StateWellFormed before) (slotBound : slot ≤ 1048576)
    (inputs : Locals (inputValues (.slice i32 output [] 0 values.length) capacity (.slice i32 work [] 0 workspace.length) slot register) frontier before)
    (distinct : output ≠ work)
    (backing : before.cellEntry? output = some { id := output, value := some (.array (signedI32Values values)) })
    (workspaceBacking : before.cellEntry? work = some { id := work, value := some (.array (signedI32Values workspace)) })
    (current : workspace[1]? = some (start : Int))
    (room : start + (bytes kind slot register).length ≤ capacity) (storage : capacity ≤ values.length)
    (bounded : capacity ≤ 2147483647) :
    ∃ after emitted, Executes program.core before
        (Source.Slot.body kind emit.source.function.id offset.source.function.id checked.code.id checked.base.id)
        (.returned (some (.signed .i32 (start + (bytes kind slot register).length : Nat)))) after ∧
      after.cellEntry? output = some { id := output, value := some (.array (signedI32Values emitted)) } ∧
      after.cellEntry? work = some { id := work, value := some (.array (signedI32Values
        (workspace.set 1 (start + (bytes kind slot register).length : Nat)))) } ∧
      byteSlice emitted start (bytes kind slot register).length = bytes kind slot register ∧
      emitted.length = values.length ∧
      (∀ index, index < start ∨ start + (bytes kind slot register).length ≤ index → emitted[index]? = values[index]?) ∧
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
      (.call emit.source.function.id (Source.Slot.arguments kind offset.source.function.id checked.code.id checked.base.id))
      work 1 (start + (bytes kind slot register).length : Nat) wellFormed within
      (inputs.found ⟨2, by simp⟩) codeLiteral rhsRun rhsEffect (Ne.symm distinct) workspaceBacking
  have rightInputs := inputs.store wellFormed rhsEffect backing
    (fun index => inputs_not_array output work values.length workspace.length capacity slot register index _)
  have rightWork := rhsEffect.preserves_entry wellFormed workspaceBacking (Ne.symm distinct)
  have afterInputs := rightInputs.store rhsEffect.wellFormed updateEffect rightWork
    (fun index => inputs_not_array output work values.length workspace.length capacity slot register index _)
  have sliceAfter : after.local? 2 = some (.slice i32 work [] 0 workspace.length) := afterInputs.found ⟨2, by simp⟩
  have returned := code_read checked.code checked.codeValue
    (show after.local? 2 = some (.slice i32 work [] 0 (workspace.set 1 (start + (bytes kind slot register).length : Nat)).length) from
      by simpa only [List.length_set] using sliceAfter)
    workContents (List.getElem?_set_self within)
  exact ⟨after, emitted, executesSequence (executesExpression update) (executesSequenceReturned (executesReturnValue returned)),
    updateEffect.preserves_entry rhsEffect.wellFormed outputContents distinct,
    workContents, exactBytes, length, framed, effect, rhsHeap.trans updateHeap⟩

/-- Source-to-machine contract for actual frame loads, word loads, and word
stores, including the workspace cursor update around the emitter call.
Output and workspace are distinct caller-owned arrays. -/
theorem emits (checked : Source.Slot.Checked program kind emit offset) (slot capacity start : Nat) (register : Fin 16)
    (wellFormed : StateWellFormed before) (slotBound : slot ≤ 1048576) (distinct : output ≠ work)
    (backing : before.cellEntry? output = some { id := output, value := some (.array (signedI32Values values)) })
    (workspaceBacking : before.cellEntry? work = some { id := work, value := some (.array (signedI32Values workspace)) })
    (current : workspace[1]? = some (start : Int))
    (room : start + (bytes kind slot register).length ≤ capacity) (storage : capacity ≤ values.length)
    (bounded : capacity ≤ 2147483647)
    (argumentsResult : ArgumentsEvaluateTo program.core caller arguments
      (inputValues (.slice i32 output [] 0 values.length) capacity (.slice i32 work [] 0 workspace.length) slot register) before) :
    ∃ after emitted, Evaluates program.core caller (.call checked.internal.source.function.id arguments)
        (.signed .i32 (start + (bytes kind slot register).length : Nat)) after ∧
      after.cellEntry? output = some { id := output, value := some (.array (signedI32Values emitted)) } ∧
      after.cellEntry? work = some { id := work, value := some (.array (signedI32Values
        (workspace.set 1 (start + (bytes kind slot register).length : Nat)))) } ∧
      byteSlice emitted start (bytes kind slot register).length = bytes kind slot register ∧
      (∀ machine, Machine.CodeAt machine.memory machine.rip (byteSlice emitted start (bytes kind slot register).length) →
        Machine.Step machine (Machine.execute (Machine.memoryInstruction kind.width kind.load register 5 (BitVec.ofInt 32 (Frame.displacement slot)))
          (bytes kind slot register).length machine)) ∧
      emitted.length = values.length ∧
      (∀ index, index < start ∨ start + (bytes kind slot register).length ≤ index → emitted[index]? = values[index]?) ∧
      CellEffect (CellSet.union (CellSet.singleton output) (CellSet.singleton work)) before after ∧ HeapFrame before after := by
  let params := parameterBindings (fun index : Fin 5 =>
    (inputValues (.slice i32 output [] 0 values.length) capacity (.slice i32 work [] 0 workspace.length) slot register).get index)
  let callee := enterCall before params
  have calleeWF := enterCall_preserves_wellFormed wellFormed (bindings := params)
  have inputs := Locals.ofReads (values := inputValues (.slice i32 output [] 0 values.length) capacity
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
    (Machine.memory_decodes kind.width kind.load register 5 (Frame.displacement slot) [])) rfl

end Lanius.X86.Frame.Slot
