import Lanius.X86.Lower.Expression.Literal.Preservation
import Lanius.X86.Lower.Expression.Literal.Capacity

namespace Lanius.X86.Lower.Expression.Literal.Boolean

open Lanius.Core Lanius.Semantics Lanius.Separation Lanius.CallContracts Lanius.X86.Buffer

/-- One native instruction evaluates the Core Boolean, with canonical 0/1
bits, unchanged memory and flags, the caller frame and following code intact. -/
def NativeRefines (value : Bool) (bytes : List UInt8) : Prop :=
  ∀ (program : Program) (runtime : State) (native entry started : Machine.State),
    Frame.BodyFrame entry started native →
    ∀ tail : List UInt8, Machine.CodeAt native.memory native.rip (bytes ++ tail) →
    ∃ after, Machine.Steps 1 native after ∧
      Evaluates program runtime (.value (.boolean value))
        (.boolean ((after.registers 0).setWidth 32 != 0)) runtime ∧
      (after.registers 0).setWidth 32 = (if value then 1 else 0) ∧
      (∀ register, register ≠ 0 → after.registers register = native.registers register) ∧
      after.memory = native.memory ∧ after.flags = native.flags ∧
      Frame.BodyFrame entry started after ∧
      after.rip = native.rip + BitVec.ofNat 64 bytes.length ∧ Machine.CodeAt after.memory after.rip tail

theorem bytes_refines (value : Bool) : NativeRefines value (Encode.Immediate.bytes (if value then 1 else 0)) := by
  intro program runtime native entry started frame tail loaded
  have canonical : -2147483648 ≤ (if value then 1 else 0 : Int) ∧
      (if value then 1 else 0 : Int) ≤ 2147483647 := by cases value <;> decide
  obtain ⟨after, steps, _, bits, _, other, memory, flags, frame, cursor, following⟩ :=
    Literal.bytes_refines canonical program runtime native entry started frame tail loaded
  refine ⟨after, steps, ?_, ?_, other, memory, flags, frame, cursor, following⟩
  · rw [bits]
    cases value <;> exact ⟨1, rfl⟩
  · cases value <;> simpa using bits

/-- Source emission and native Boolean evaluation, on the same output window. -/
theorem compiles (checked : Source.Expression.Literal.Checked emitters) (c : Context) (valid : c.Valid)
    (value : Bool) (source : Syntax c 2 (if value then 1 else 0)) (room : c.start + 5 ≤ c.capacity) :
    c.Emits emitters.pack.program.core checked.wrapper.source.function.id 2
      (Encode.Immediate.bytes (if value then 1 else 0)) (afterLiteral c.workspace c.position c.start)
      (NativeRefines value) := by
  constructor
  intro caller arguments before wellFormed evaluated memory
  obtain ⟨after, run, ⟨emitted, output, work, _, window⟩, effect, heap⟩ :=
    (Literal.compiles checked c valid source room).call wellFormed evaluated memory
  exact ⟨after, run, ⟨emitted, output, work, window, window.bytes.symm ▸ bytes_refines value⟩, effect, heap⟩

/-- Serialization supplies the Boolean guard and all three bounded reads. -/
theorem input {c : Context}
    (serialized : Transport.expression? program (.value (.boolean value)) = some words)
    (stream : (c.transport.take c.length).drop c.position = words ++ suffix) :
    Syntax c 2 (if value then 1 else 0) := by
  obtain ⟨available, tag, kind, low⟩ := Transport.bool_window serialized stream
  have readable : c.position + 3 ≤ c.length := by
    simp only [List.length_take] at available
    omega
  rw [List.getElem?_take_of_lt (by omega)] at tag
  rw [List.getElem?_take_of_lt (by omega)] at kind
  rw [List.getElem?_take_of_lt (by omega)] at low
  exact ⟨.inr ⟨rfl, by cases value <;> simp⟩, readable, tag, kind, low⟩

theorem from_transport (checked : Source.Expression.Literal.Checked emitters) (c : Context) (valid : c.Valid)
    (serialized : Transport.expression? program (.value (.boolean value)) = some words)
    (stream : (c.transport.take c.length).drop c.position = words ++ suffix) (room : c.start + 5 ≤ c.capacity) :
    c.Emits emitters.pack.program.core checked.wrapper.source.function.id 2
      (Encode.Immediate.bytes (if value then 1 else 0)) (afterLiteral c.workspace c.position c.start)
      (NativeRefines value) := compiles checked c valid value (input serialized stream) room

/-- A short output buffer consumes the Boolean, returns kind 2, and records
CODE = -1 without writing output. This is a sticky compiler failure, not code. -/
theorem rejects_capacity (checked : Source.Expression.Literal.Checked emitters) (c : Context) (valid : c.Valid)
    (value : Bool) (source : Syntax c 2 (if value then 1 else 0)) (bad : c.capacity < c.start + 5) :
    c.Call emitters.pack.program.core checked.wrapper.source.function.id 2
      (Capacity.afterFailure c.workspace c.position) (fun emitted => emitted = c.values) := by
  have sameTop : (Capacity.afterFailure c.workspace c.position)[6]? = some c.top := by
    simpa only [Capacity.afterFailure, List.getElem?_set_ne (by decide : 1 ≠ 6),
      List.getElem?_set_ne (by decide : 0 ≠ 6)] using valid.topFound
  apply (Wrapper.finish_eq (kind := 2) sameTop) ▸
    Wrapper.call checked c 2 _ _ valid.topFound (by simp [Capacity.afterFailure])
  constructor
  intro caller arguments before wellFormed evaluated memory
  obtain ⟨after, run, output, work, effect, heap⟩ :=
    Capacity.emit_call checked c.length c.position c.depth c.capacity c.start _ source.scalar
      c.active c.context c.contextLength wellFormed memory.plain memory.inputBacking memory.outputBacking memory.workBacking
      memory.inputOutput memory.inputWork memory.outputWork valid.current valid.cursor valid.healthy valid.depthBound
      source.readable valid.storage valid.bounded bad valid.outputBound source.tagWord source.kindWord source.lowWord evaluated
  exact ⟨after, run, ⟨_, output, work, rfl⟩, effect, heap⟩

end Lanius.X86.Lower.Expression.Literal.Boolean
