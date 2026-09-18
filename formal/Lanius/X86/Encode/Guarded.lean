import Lanius.X86.Source.Guarded
import Lanius.X86.Encode.Register
import Lanius.Automation.Execute
import Lanius.Extraction.Source.Call
import Lanius.X86.Machine.Scalar

namespace Lanius.X86.Encode.Guarded

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView.Core Lanius.X86.Source Lanius.X86.Buffer

abbrev Kind := GuardedRegister

theorem constant_guard (guard : ConstantGuard program) (operation : Int)
    (found : before.local? 4 = some (.signed .i32 operation)) :
    Evaluates program before guard.expression (.boolean (decide (operation ∉ guard.values))) before := by
  induction guard with
  | compare id value declaration lookup valueExact =>
      have constant : Evaluates program before (.constant id) (.signed .i32 value) before := by
        refine ⟨1, ?_⟩
        simp only [evalExpr, lookup, valueExact]
      apply evaluatesEagerBinary (by decide) (by decide) (local_evaluates program found) constant
      simp [evalBinaryValue, scalarEqual, ConstantGuard.values]
      apply Bool.eq_iff_iff.mpr
      simp
  | both left right leftRun rightRun =>
      have run := evaluatesPureLogicalAnd leftRun rightRun
      simpa only [ConstantGuard.expression, ConstantGuard.values, List.mem_append, not_or,
        Bool.decide_and] using run

def inputs (kind : Kind) (output : Value) (capacity cursor width operation destination source : Int) : List Value :=
  match kind with
  | .binary => [output, .signed .i32 capacity, .signed .i32 cursor, .signed .i32 width,
      .signed .i32 operation, .signed .i32 destination, .signed .i32 source]
  | .shift => [output, .signed .i32 capacity, .signed .i32 cursor, .signed .i32 width,
      .signed .i32 operation, .signed .i32 destination]

def opcode (kind : Kind) (operation : Int) : Int := match kind with | .binary => operation | .shift => 211
def reg (kind : Kind) (operation source : Int) : Int := match kind with | .binary => source | .shift => operation

def delegated (kind : Kind) (output : Value) (capacity cursor width operation destination source : Int) : List Value :=
  rawArguments output capacity cursor width (opcode kind operation) (reg kind operation source) destination false

structure Choice (kind : Kind) where
  value : Nat
  allowed : (value : Int) ∈ kind.allowed

theorem Choice.byte (choice : Choice kind) : choice.value < 256 := by
  have member := choice.allowed
  cases kind <;> simp only [GuardedRegister.allowed, List.mem_cons, List.not_mem_nil, or_false] at member <;> omega

theorem Choice.digit (choice : Choice .shift) : choice.value < 8 := by
  have member := choice.allowed
  simp only [GuardedRegister.allowed, List.mem_cons, List.not_mem_nil, or_false] at member
  omega

def config (kind : Kind) (choice : Choice kind) (width : Register.Width) (destination source : Fin 16) : Config :=
  match kind, choice with
  | .binary, choice => ⟨width, .primary ⟨choice.value, choice.byte⟩, source, destination, false⟩
  | .shift, choice => ⟨width, .primary ⟨211, by decide⟩, ⟨choice.value, by have := choice.digit; omega⟩, destination, false⟩

def comparison : Choice .binary := ⟨57, by decide⟩

theorem compare32_decodes (left right : Fin 16) :
    Machine.decode ((config .binary comparison .w32 left right).bytes.map UInt8.ofNat) =
      some (.compare32 left right, (config .binary comparison .w32 left right).size) :=
  (by decide : ∀ left right : Fin 16,
    Machine.decode ((config .binary comparison .w32 left right).bytes.map UInt8.ofNat) =
      some (.compare32 left right, (config .binary comparison .w32 left right).size)) left right

/-- Reuse the source emitter's exact output, including REX register bits. -/
theorem compare32_step
    (emission : (config .binary comparison .w32 left right).Emission original start emitted)
    (machine : Machine.State)
    (loaded : Machine.CodeAt machine.memory machine.rip
      (byteSlice emitted start (config .binary comparison .w32 left right).size)) :
    Machine.Step machine (machine.compare32 left right (config .binary comparison .w32 left right).size) := by
  rw [emission.bytes] at loaded
  exact .decoded _ loaded _ _ (compare32_decodes left right) rfl

theorem config_arguments (kind : Kind) (choice : Choice kind) (width : Register.Width) (destination source : Fin 16) :
    (config kind choice width destination source).arguments output capacity cursor =
      delegated kind output capacity cursor width.bits choice.value destination.val source.val := by
  cases kind <;> rfl

theorem bound (kind : Kind) :
    bindParameters kind.parameters (inputs kind output capacity cursor width operation destination source) =
      some (parameterBindings (fun index : Fin (inputs kind output capacity cursor width operation destination source).length =>
        (inputs kind output capacity cursor width operation destination source)[index])) := by
  cases kind <;> rfl

theorem arguments_evaluate (program : Program) (kind : Kind)
    (locals : ∀ index (within : index < (inputs kind output capacity cursor width operation destination source).length),
      before.local? index = some ((inputs kind output capacity cursor width operation destination source)[index])) :
    ArgumentsEvaluateTo program before kind.arguments
      (delegated kind output capacity cursor width operation destination source) before := by
  cases kind <;> core_args [inputs, delegated, rawArguments, opcode, reg]

theorem guard_evaluates (checked : CheckedGuardedRegister program form kind)
    (locals : ∀ index (within : index < (inputs kind output capacity cursor width operation destination source).length),
      before.local? index = some ((inputs kind output capacity cursor width operation destination source)[index])) :
    Evaluates program.core before checked.guard.expression (.boolean (decide (operation ∉ kind.allowed))) before := by
  have found : before.local? 4 = some (.signed .i32 operation) := by
    have read := locals 4 (by cases kind <;> simp [inputs])
    cases kind <;> exact read
  simpa only [checked.valuesExact] using constant_guard checked.guard operation found

theorem succeeds (checked : CheckedGuardedRegister program form kind) (choice : Choice kind)
    (width : Register.Width) (destination source : Fin 16) (capacity start : Nat)
    (room : start + (config kind choice width destination source).size ≤ capacity)
    (storage : capacity ≤ values.length) (bounded : capacity ≤ 2147483647) :
    checked.internal.Spec (inputs kind (.slice i32 cell [] 0 values.length)
        capacity start width.bits choice.value destination.val source.val)
      (.signed .i32 (start + (config kind choice width destination source).size : Nat))
      (requires := fun before => before.cellEntry? cell = some {
        id := cell, value := some (.array (signedI32Values values)) })
      (ensures := fun _ after => after.cellEntry? cell = some {
        id := cell, value := some (.array (signedI32Values
          (writtenBytes values start (config kind choice width destination source).bytes))) })
      (writes := CellSet.singleton cell) := by
  apply checked.internal.specCell (bound kind)
  intro callee wellFormed locals backing
  have guard := guard_evaluates checked locals
  simp only [choice.allowed, not_true_eq_false, decide_false] at guard
  have args := arguments_evaluate program.core kind locals
  rw [← config_arguments kind choice width destination source] at args
  obtain ⟨after, run, contents, _, effect, heap⟩ := Encode.succeeds form
    (config kind choice width destination source) capacity start wellFormed room storage bounded backing args
  exact ⟨after, by core_exec [], contents, effect, heap⟩

theorem rejects_operation (checked : CheckedGuardedRegister program form kind) (output : Value)
    (capacity start width operation destination source : Int) (bad : operation ∉ kind.allowed) :
    checked.internal.Spec (inputs kind output capacity start width operation destination source) (.signed .i32 (-1)) := by
  apply checked.internal.specPure (bound kind)
  intro callee locals
  have guard := guard_evaluates checked locals
  simp only [bad] at guard
  core_exec []

theorem rejects_capacity (checked : CheckedGuardedRegister program form kind) (choice : Choice kind)
    (width : Register.Width) (destination source : Fin 16) (output : Value) (capacity start : Int)
    (bounded : capacity ≤ 2147483647)
    (bad : reserved capacity start (config kind choice width destination source).size = false) :
    checked.internal.Spec (inputs kind output capacity start width.bits choice.value destination.val source.val)
      (.signed .i32 (-1)) := by
  apply checked.internal.specFrame (bound kind)
  intro callee wellFormed locals
  have guard := guard_evaluates checked locals
  simp only [choice.allowed, not_true_eq_false, decide_false] at guard
  have args := arguments_evaluate program.core kind locals
  rw [← config_arguments kind choice width destination source] at args
  obtain ⟨after, run, effect, heap⟩ := Encode.rejects_capacity form
    (config kind choice width destination source) output capacity start wellFormed bounded bad args
  exact ⟨after, by core_exec [], effect, heap⟩

theorem rejects_invalid (checked : CheckedGuardedRegister program form kind) (choice : Choice kind) (output : Value)
    (capacity start width destination source : Int)
    (bad : Register.Validation.register.accepts (reg kind choice.value source) = false ∨
      Register.Validation.register.accepts destination = false ∨ Register.Validation.width.accepts width = false) :
    checked.internal.Spec (inputs kind output capacity start width choice.value destination source) (.signed .i32 (-1)) := by
  apply checked.internal.specFrame (bound kind)
  intro callee wellFormed locals
  have guard := guard_evaluates checked locals
  simp only [choice.allowed, not_true_eq_false, decide_false] at guard
  obtain ⟨after, run, effect, heap⟩ := Encode.rejects_invalid form output capacity start width
    (opcode kind choice.value) (reg kind choice.value source) destination false wellFormed bad
    (arguments_evaluate program.core kind locals)
  exact ⟨after, by core_exec [], effect, heap⟩

end Lanius.X86.Encode.Guarded
