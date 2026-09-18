import Lanius.X86.Source.Direct
import Lanius.X86.Encode.Register
import Lanius.X86.Machine.Scalar
import Lanius.Automation.Execute
import Lanius.Extraction.Source.Call

namespace Lanius.X86.Encode.Direct

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView.Core Lanius.X86.Source Lanius.X86.Buffer

abbrev Kind := RegisterWrapper

/-- Arguments of the actual public signatures. Fixed-width extensions do not
take a width argument; negation has no second register operand. -/
def inputs (kind : Kind) (output : Value) (capacity cursor width destination source : Int) : List Value :=
  match kind with
  | .move | .multiply => [output, .signed .i32 capacity, .signed .i32 cursor,
      .signed .i32 width, .signed .i32 destination, .signed .i32 source]
  | .signExtend | .zeroExtend => [output, .signed .i32 capacity, .signed .i32 cursor,
      .signed .i32 destination, .signed .i32 source]
  | .negate => [output, .signed .i32 capacity, .signed .i32 cursor, .signed .i32 width, .signed .i32 destination]

def operandWidth (kind : Kind) (width : Int) : Int :=
  match kind with | .signExtend => 64 | .zeroExtend => 32 | _ => width

def opcode : Kind → Encoding.Opcode
  | .move => .primary ⟨137, by decide⟩
  | .multiply => .escaped ⟨175, by decide⟩
  | .signExtend => .primary ⟨99, by decide⟩
  | .zeroExtend => .escaped ⟨182, by decide⟩
  | .negate => .primary ⟨247, by decide⟩

def reg (kind : Kind) (destination source : Int) : Int :=
  match kind with | .move => source | .negate => 3 | _ => destination

def rm (kind : Kind) (destination source : Int) : Int :=
  match kind with | .move | .negate => destination | _ => source

def forceByte (kind : Kind) (source : Int) : Bool :=
  match kind with | .zeroExtend => decide (4 ≤ source) | _ => false

def delegated (kind : Kind) (output : Value) (capacity cursor width destination source : Int) : List Value :=
  rawArguments output capacity cursor (operandWidth kind width) (opcode kind).packed
    (reg kind destination source) (rm kind destination source) (forceByte kind source)

/-- Architectural fields for the supported forms: MOV 89 /r, IMUL 0F AF /r,
MOVSXD REX.W 63 /r, MOVZX 0F B6 /r, and NEG F7 /3. This is a byte-encoding
contract; register/flag execution semantics are not assumed here. -/
def config (kind : Kind) (width : Register.Width) (destination source : Fin 16) : Config :=
  { width := match kind with | .signExtend => .w64 | .zeroExtend => .w32 | _ => width
    opcode := opcode kind
    reg := match kind with | .move => source | .negate => ⟨3, by decide⟩ | _ => destination
    rm := match kind with | .move | .negate => destination | _ => source
    forceByte := forceByte kind source.val }

theorem config_arguments (kind : Kind) (width : Register.Width) (destination source : Fin 16) :
    (config kind width destination source).arguments output capacity cursor =
      delegated kind output capacity cursor width.bits destination.val source.val := by
  cases kind <;> rfl

/-- Decode the bytes established by the existing Lanius MOVZX emitter
proof, including neutral REX and all extended-register combinations. -/
theorem zeroExtend_decodes (destination source : Fin 16) :
    Machine.decode ((config .zeroExtend .w32 destination source).bytes.map UInt8.ofNat) =
      some (.zeroExtendByte destination source, (config .zeroExtend .w32 destination source).size) :=
  (by decide : ∀ destination source : Fin 16,
    Machine.decode ((config .zeroExtend .w32 destination source).bytes.map UInt8.ofNat) =
      some (.zeroExtendByte destination source, (config .zeroExtend .w32 destination source).size)) destination source

/-- Feed the window returned by `succeeds` directly into native execution;
neither emission nor operand decoding is repeated. -/
theorem zeroExtend_step
    (emission : (config .zeroExtend .w32 destination source).Emission original start emitted)
    (machine : Machine.State)
    (loaded : Machine.CodeAt machine.memory machine.rip
      (byteSlice emitted start (config .zeroExtend .w32 destination source).size)) :
    Machine.Step machine (machine.zeroExtendByte destination source
      (config .zeroExtend .w32 destination source).size) := by
  rw [emission.bytes] at loaded
  exact .decoded _ loaded _ _ (zeroExtend_decodes destination source) rfl

theorem bound (kind : Kind) :
    bindParameters kind.parameters (inputs kind output capacity cursor width destination source) =
      some (parameterBindings (fun index : Fin (inputs kind output capacity cursor width destination source).length =>
        (inputs kind output capacity cursor width destination source)[index])) := by
  cases kind <;> rfl

theorem arguments_evaluate (program : Program) (kind : Kind)
    (locals : ∀ index (within : index < (inputs kind output capacity cursor width destination source).length),
      before.local? index = some ((inputs kind output capacity cursor width destination source)[index])) :
    ArgumentsEvaluateTo program before kind.arguments
      (delegated kind output capacity cursor width destination source) before := by
  cases kind <;>
    core_args [inputs, delegated, rawArguments, operandWidth, opcode, Encoding.Opcode.packed, reg, rm, forceByte]

/-- The public call emits the selected instruction into the reserved window,
preserving caller locals, all other old cells, and the modeled host state.
`Config.emission` supplies the byte-window/frame facts from this exact output. -/
theorem succeeds (checked : CheckedRegisterWrapper program form kind) (width : Register.Width)
    (destination source : Fin 16) (capacity start : Nat)
    (room : start + (config kind width destination source).size ≤ capacity)
    (storage : capacity ≤ values.length) (bounded : capacity ≤ 2147483647) :
    checked.Spec (inputs kind (.slice i32 cell [] 0 values.length) capacity start width.bits destination.val source.val)
      (.signed .i32 (start + (config kind width destination source).size : Nat))
      (requires := fun before => before.cellEntry? cell = some {
        id := cell, value := some (.array (signedI32Values values)) })
      (ensures := fun _ after => after.cellEntry? cell = some {
        id := cell, value := some (.array (signedI32Values
          (writtenBytes values start (config kind width destination source).bytes))) })
      (writes := CellSet.singleton cell) := by
  apply checked.specCell (bound kind)
  intro callee wellFormed locals backing
  have args := arguments_evaluate program.core kind locals
  rw [← config_arguments kind width destination source] at args
  obtain ⟨after, run, contents, _, effect, heap⟩ := Encode.succeeds form
    (config kind width destination source) capacity start wellFormed room storage bounded backing args
  exact ⟨after, by core_exec [], contents, effect, heap⟩

theorem rejects_capacity (checked : CheckedRegisterWrapper program form kind) (width : Register.Width)
    (destination source : Fin 16) (output : Value) (capacity start : Int)
    (bounded : capacity ≤ 2147483647)
    (bad : reserved capacity start (config kind width destination source).size = false) :
    checked.Spec (inputs kind output capacity start width.bits destination.val source.val) (.signed .i32 (-1)) := by
  apply checked.specFrame (bound kind)
  intro callee wellFormed locals
  have args := arguments_evaluate program.core kind locals
  rw [← config_arguments kind width destination source] at args
  obtain ⟨after, run, effect, heap⟩ := Encode.rejects_capacity form
    (config kind width destination source) output capacity start wellFormed bounded bad args
  exact ⟨after, by core_exec [], effect, heap⟩

/-- Invalid actual operands are rejected before accessing output. Fixed-width
extensions have no caller width to reject, and NEG has only one register. -/
theorem rejects_invalid (checked : CheckedRegisterWrapper program form kind) (output : Value)
    (capacity start width destination source : Int)
    (bad : Register.Validation.register.accepts (reg kind destination source) = false ∨
      Register.Validation.register.accepts (rm kind destination source) = false ∨
      Register.Validation.width.accepts (operandWidth kind width) = false) :
    checked.Spec (inputs kind output capacity start width destination source) (.signed .i32 (-1)) := by
  apply checked.specFrame (bound kind)
  intro callee wellFormed locals
  obtain ⟨after, run, effect, heap⟩ := Encode.rejects_invalid form output capacity start
    (operandWidth kind width) (opcode kind).packed (reg kind destination source) (rm kind destination source)
    (forceByte kind source) wellFormed bad (arguments_evaluate program.core kind locals)
  exact ⟨after, by core_exec [], effect, heap⟩

end Lanius.X86.Encode.Direct
