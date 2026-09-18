import Lanius.X86.Source.Boolean
import Lanius.X86.Encode.Condition
import Lanius.X86.Encode.Direct
import Lanius.X86.Machine.Boolean
import Lanius.Automation.Contract
import Lanius.Extraction.Source.Expression

namespace Lanius.X86.Encode.Boolean

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView.Core Lanius.X86.Source Lanius.X86.Buffer

def inputs (output : Value) (capacity cursor code : Int) : List Value :=
  [output, .signed .i32 capacity, .signed .i32 cursor, .signed .i32 code]

def bytes (code : Fin 16) : List Nat := [15, 144 + code.val, 192, 15, 182, 192]

private theorem first_bytes (code : Fin 16) : (Condition.config code 0).bytes = [15, 144 + code.val, 192] :=
  (by decide : ∀ code : Fin 16, (Condition.config code 0).bytes = [15, 144 + code.val, 192]) code

/-- A failed second instruction retains the first three bytes. -/
theorem write (checked : Source.Boolean.Checked emitters) (code : Fin 16) (capacity start : Nat)
    (room : start + 3 ≤ capacity) (storage : capacity ≤ values.length) (bounded : capacity ≤ 2147483647) :
    checked.internal.Spec (inputs (.slice i32 cell [] 0 values.length) capacity start code.val)
      (.signed .i32 (if start + 6 ≤ capacity then (start + 6 : Nat) else -1))
      (requires := fun before => before.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values values)) })
      (ensures := fun _ after => after.cellEntry? cell = some {
        id := cell, value := some (.array (signedI32Values (writtenBytes values start
          (if start + 6 ≤ capacity then bytes code else [15, 144 + code.val, 192])))) })
      (writes := CellSet.singleton cell) := by
  
  apply checked.internal.specCell rfl
  intro callee wellFormed locals backing
  have rax (state : State) := checked.rax.evaluates (before := state)
  simp only [checked.zero] at rax
  obtain ⟨middle, first, contents, effect, heap⟩ := (Condition.succeeds emitters.condition code 0 capacity start
    room storage bounded).call
      (caller := callee)
      (arguments := [read 0, read 1, read 2, read 3, .constant checked.rax.id])
      wellFormed (by have := rax callee; core_args [inputs]) backing
  have arguments : ArgumentsEvaluateTo emitters.pack.program.core callee
      (Source.Boolean.arguments emitters.condition.source.function.id checked.rax.id)
      (Direct.inputs .zeroExtend (.slice i32 cell [] 0 values.length) capacity (start + 3 : Nat) 32 0 0) middle := by
    have := rax middle
    core_args [inputs]
  by_cases enough : start + 6 ≤ capacity
  · simp only [if_pos enough]
    obtain ⟨after, last, written, total, finalHeap⟩ := (Direct.succeeds (emitters.registerWrappers .zeroExtend) .w32 0 0
      capacity (start + 3) (by change start + 3 + 3 ≤ capacity; omega)
      (by simpa only [writtenBytes_length] using storage) bounded).call effect.wellFormed
        (by simpa [Register.Width.bits] using arguments) contents
    change Evaluates _ _ _ (.signed .i32 (start + 3 + 3 : Nat)) _ at last
    rw [show start + 3 + 3 = start + 6 by omega] at last
    rw [first_bytes] at written
    exact ⟨after, by core_exec [], written, effect.trans total, heap.trans finalHeap⟩
  · simp only [if_neg enough]
    obtain ⟨after, last, _, total, finalHeap⟩ := (Direct.rejects_capacity (emitters.registerWrappers .zeroExtend) .w32 0 0
      _ capacity (start + 3 : Nat) (by omega) (by change reserved capacity (start + 3 : Nat) 3 = false; simp [reserved]; omega)).call
        effect.wellFormed arguments
    exact ⟨after, by core_exec [], (by simpa only [first_bytes] using
      (total.empty_preserves_entry effect.wellFormed contents)),
      effect.trans (total.weaken CellSet.empty_subset), heap.trans finalHeap⟩

theorem rejects (checked : Source.Boolean.Checked emitters) (output : Value) (capacity start code : Int)
  (bounded : capacity ≤ 2147483647) (bad : code < 0 ∨ 15 < code ∨ reserved capacity start 3 = false) :
    checked.internal.Spec (inputs output capacity start code) (.signed .i32 (-1)) := by
  have rejected : emitters.condition.Spec (Condition.inputs output capacity start code 0) (.signed .i32 (-1)) := by
    by_cases invalid : code < 0 ∨ 15 < code
    · exact Condition.rejects_condition emitters.condition output capacity start code 0 invalid
    · have nonnegative : 0 ≤ code := by omega
      let cc : Fin 16 := ⟨code.toNat, by omega⟩
      have capacityBad : reserved capacity start (Condition.config cc 0).size = false := by
        change reserved capacity start 3 = false
        rcases bad with h | h | h <;> first | exact h | omega
      simpa [cc, Int.toNat_of_nonneg nonnegative] using
        Condition.rejects_capacity emitters.condition cc 0 output capacity start bounded capacityBad
  have rax (state : State) := checked.rax.evaluates (before := state)
  simp only [checked.zero] at rax
  have extending := Direct.rejects_capacity (emitters.registerWrappers .zeroExtend) .w32 0 0
    output capacity (-1) bounded (by change reserved capacity (-1) 3 = false; simp [reserved])
  refine checked.internal.specExpressionFrame rfl ?_
  core_spec [inputs, Condition.inputs, Direct.inputs, rejected, extending, rax]
/-- The exact successful output executes to the condition value in RAX,
preserving other registers, flags, and memory, even with dirty upper bits. -/
theorem steps (code : Fin 16) (room : start + 6 ≤ values.length) (machine : Machine.State)
    (loaded : Machine.CodeAt machine.memory machine.rip (byteSlice (writtenBytes values start (bytes code)) start 6)) :
    Machine.Steps 2 machine { machine with
      registers := fun register => if register = 0 then
        (if Machine.condition machine.flags code then 1 else 0) else machine.registers register
      rip := machine.rip + 6 } := by
  have window := writtenBytes_byteSlice (values := values) (position := start) (bytes := bytes code) room
  change byteSlice (writtenBytes values start (bytes code)) start 6 = _ at window
  rw [window] at loaded
  change Machine.CodeAt machine.memory machine.rip (Machine.ReadOnly.code (Machine.Boolean.materialize code)) at loaded
  have count : (Machine.Boolean.materialize code).length = 2 := rfl
  simpa only [Machine.Boolean.materialize_run, count] using Machine.ReadOnly.steps (Machine.Boolean.materialize code) machine loaded

end Lanius.X86.Encode.Boolean
