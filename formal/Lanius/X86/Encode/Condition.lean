import Lanius.X86.Source.Condition
import Lanius.X86.Encode.Register
import Lanius.Extraction.Source.Call
import Lanius.Automation.Execute
import Lanius.X86.Machine.Scalar

namespace Lanius.X86.Encode.Condition

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView.Core Lanius.X86.Source Lanius.X86.Buffer

def inputs (output : Value) (capacity start code destination : Int) : List Value :=
  [output, .signed .i32 capacity, .signed .i32 start, .signed .i32 code, .signed .i32 destination]

def config (code destination : Fin 16) : Config :=
  ⟨.w32, .escaped ⟨144 + code.val, by omega⟩, 0, destination, decide (4 ≤ destination.val)⟩

theorem arguments (program : Program) (code : Fin 16) (destination : Int)
    (locals : ∀ index (within : index < 5), before.local? index =
      some ((inputs output capacity start code.val destination)[index])) :
    ArgumentsEvaluateTo program before Source.Condition.arguments
      (rawArguments output capacity start 32 (3984 + code.val : Nat) 0 destination (decide (4 ≤ destination))) before := by
  core_args [inputs]

theorem config_arguments (code destination : Fin 16) :
    (config code destination).arguments output capacity start =
      rawArguments output capacity start 32 (3984 + code.val : Nat) 0 destination.val
        (decide (4 ≤ (destination.val : Int))) := by
  simp [config, Config.arguments, rawArguments, Register.Width.bits, Encoding.Opcode.packed,
    Encoding.Opcode.extended, Encoding.Opcode.byte, ← Nat.add_assoc]
  omega

private theorem guarded (code : Fin 16)
    (locals : ∀ index (within : index < 5), before.local? index =
      some ((inputs output capacity start code.val destination)[index]))
    (run : Evaluates program before (.call function Source.Condition.arguments) result after) :
    Executes program before (Source.Condition.body function) (.returned (some result)) after := by
  have range := code.isLt
  core_exec [Source.Condition.guard, inputs]

/-- Execute the actual guarded delegation, reusing the complete register-form
proof. The shared call rule handles parameter cells and caller restoration. -/
theorem succeeds (checked : Source.Condition.Checked program form) (code destination : Fin 16)
    (capacity start : Nat) (room : start + (config code destination).size ≤ capacity)
    (storage : capacity ≤ values.length) (bounded : capacity ≤ 2147483647) :
    checked.Spec (inputs (.slice i32 cell [] 0 values.length) capacity start code.val destination.val)
      (.signed .i32 (start + (config code destination).size : Nat))
      (requires := fun before => before.cellEntry? cell = some {
        id := cell, value := some (.array (signedI32Values values)) })
      (ensures := fun _ after => after.cellEntry? cell = some {
        id := cell, value := some (.array (signedI32Values (writtenBytes values start (config code destination).bytes))) })
      (writes := CellSet.singleton cell) := by
  apply checked.specCell rfl
  intro callee wellFormed locals backing
  have args := arguments program.core code destination.val locals
  rw [← config_arguments] at args
  obtain ⟨after, run, contents, _, effect, heap⟩ := Encode.succeeds form (config code destination)
    capacity start wellFormed room storage bounded backing args
  exact ⟨after, guarded code locals run, contents, effect, heap⟩

theorem rejects_condition (checked : Source.Condition.Checked program form)
    (output : Value) (capacity start code destination : Int) (bad : code < 0 ∨ 15 < code) :
    checked.Spec (inputs output capacity start code destination) (.signed .i32 (-1)) := by
  apply checked.specPure rfl
  intro callee locals
  core_exec [Source.Condition.guard, inputs]

theorem rejects_capacity (checked : Source.Condition.Checked program form) (code destination : Fin 16)
    (output : Value) (capacity start : Int) (bounded : capacity ≤ 2147483647)
    (bad : reserved capacity start (config code destination).size = false) :
    checked.Spec (inputs output capacity start code.val destination.val) (.signed .i32 (-1)) := by
  apply checked.specFrame rfl
  intro callee wellFormed locals
  have args := arguments program.core code destination.val locals
  rw [← config_arguments] at args
  obtain ⟨after, run, effect, heap⟩ := Encode.rejects_capacity form (config code destination)
    output capacity start wellFormed bounded bad args
  exact ⟨after, guarded code locals run, effect, heap⟩

theorem rejects_register (checked : Source.Condition.Checked program form) (code : Fin 16)
    (output : Value) (capacity start destination : Int)
    (bad : Register.Validation.register.accepts destination = false) :
    checked.Spec (inputs output capacity start code.val destination) (.signed .i32 (-1)) := by
  apply checked.specFrame rfl
  intro callee wellFormed locals
  obtain ⟨after, run, effect, heap⟩ := Encode.rejects_invalid form output capacity start 32
    (3984 + code.val : Nat) 0 destination (decide (4 ≤ destination)) wellFormed
    (Or.inr (Or.inl bad)) (arguments program.core code destination locals)
  exact ⟨after, guarded code locals run, effect, heap⟩

theorem decodes (code destination : Fin 16) :
    Machine.decode ((config code destination).bytes.map UInt8.ofNat) =
      some (.setCondition code destination, (config code destination).size) :=
  (by decide : ∀ code destination : Fin 16,
    Machine.decode ((config code destination).bytes.map UInt8.ofNat) =
      some (.setCondition code destination, (config code destination).size)) code destination

theorem step (emission : (config code destination).Emission original start emitted)
    (machine : Machine.State)
    (loaded : Machine.CodeAt machine.memory machine.rip (byteSlice emitted start (config code destination).size)) :
    Machine.Step machine (machine.setCondition code destination (config code destination).size) := by
  rw [emission.bytes] at loaded
  exact .decoded _ loaded _ _ (decodes code destination) rfl

end Lanius.X86.Encode.Condition
