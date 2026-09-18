import Lanius.X86.Lower.Expression.Literal
import Lanius.X86.Frame.Function
import Lanius.X86.Transport.Literal

namespace Lanius.X86.Lower.Expression.Literal

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView.Core Lanius.X86.Source Lanius.X86.Buffer

/-- A literal's complete emitted window evaluates to its Core signed value
in EAX. The Core state and native memory are unchanged; caller state and the
following code survive. This base case has no recursive/source execution IH. -/
def NativeRefines (value : Int) (bytes : List UInt8) : Prop :=
  ∀ (program : Lanius.Core.Program) (runtime : Lanius.Semantics.State)
    (native entry started : Machine.State), Frame.BodyFrame entry started native →
    ∀ tail : List UInt8, Machine.CodeAt native.memory native.rip (bytes ++ tail) →
    ∃ after, Machine.Steps 1 native after ∧
      Evaluates program runtime (.value (.signed .i32 value))
        (.signed .i32 ((after.registers 0).setWidth 32).toInt) runtime ∧
      (after.registers 0).setWidth 32 = BitVec.ofInt 32 value ∧
      ((after.registers 0).setWidth 32).toInt = value ∧
      (∀ register, register ≠ 0 → after.registers register = native.registers register) ∧
      after.memory = native.memory ∧ after.flags = native.flags ∧
      Frame.BodyFrame entry started after ∧
      after.rip = native.rip + BitVec.ofNat 64 bytes.length ∧
      Machine.CodeAt after.memory after.rip tail

/-- Byte emission accepts arbitrary Ints, but preserving a Core i32 literal
requires its canonical signed range. Otherwise MOV retains only the low 32
bits, while Core's literal rule returns the supplied Int without wrapping. -/
theorem bytes_refines (canonical : -2147483648 ≤ low ∧ low ≤ 2147483647) :
    NativeRefines low (Encode.Immediate.bytes low) := by
  intro program runtime native entry started frame tail loaded
  let after := native.immediate32 0 (BitVec.ofInt 32 low) 5
  have step : Machine.Step native after := Encode.Immediate.executes native loaded.prefix
  have bits : (after.registers 0).setWidth 32 = BitVec.ofInt 32 low := by
    simp [after, Machine.State.immediate32]
  have observed : ((after.registers 0).setWidth 32).toInt = low := by
    rw [bits]
    exact BitVec.toInt_ofInt_eq_self (by decide) canonical.1 (by omega)
  have other (register : Machine.Register) (different : register ≠ 0) :
      after.registers register = native.registers register := by
    simp [after, Machine.State.immediate32, different]
  have keptFrame : Frame.BodyFrame entry started after := by
    refine ⟨(other 5 (by decide)).trans frame.framePointer, frame.savedPointer, frame.returnAddress,
      ?_, frame.direction⟩
    intro register saved
    rw [other]
    · exact frame.registers register saved
    · rcases saved with rfl | rfl | rfl | rfl | rfl <;> decide
  refine ⟨after, .cons step (.refl after), ?_, bits, observed, other, rfl, rfl, keptFrame, ?_, ?_⟩
  · rw [observed]
    exact ⟨1, rfl⟩
  · simp only [after, Machine.State.immediate32, Encode.Immediate.bytes_length]
  · simpa only [after, Machine.State.immediate32, Encode.Immediate.bytes_length] using loaded.suffix

namespace Preservation

/-- The actual Lanius expression compiler emits native code preserving a
canonical signed-i32 Core literal. Transport reads, dispatch, helper calls,
emission, and TOP restoration are all supplied by proved source execution. -/
theorem compiles (checked : Source.Expression.Literal.Checked emitters)
    (length position depth capacity start : Nat) (low top : Int) (active context contextLength : Value)
    (canonical : -2147483648 ≤ low ∧ low ≤ 2147483647)
    (wellFormed : StateWellFormed before)
    (plain : ∀ value ∈ inputValues input work output transport.length workspace.length values.length
      length capacity depth active context contextLength, ∀ elements, value ≠ .array elements)
    (inputBacking : before.cellEntry? input = some { id := input, value := some (.array (signedI32Values transport)) })
    (outputBacking : before.cellEntry? output = some { id := output, value := some (.array (signedI32Values values)) })
    (workBacking : before.cellEntry? work = some { id := work, value := some (.array (signedI32Values workspace)) })
    (inputOutput : input ≠ output) (inputWork : input ≠ work) (outputWork : output ≠ work)
    (current : workspace[0]? = some (position : Int))
    (cursor : workspace[1]? = some (start : Int)) (healthy : workspace[4]? = some 0) (topFound : workspace[6]? = some top)
    (depthBound : depth < 512) (readable : position + 3 ≤ length)
    (storage : length ≤ transport.length) (bounded : length ≤ 2147483647)
    (room : start + 5 ≤ capacity) (outputStorage : capacity ≤ values.length) (outputBound : capacity ≤ 2147483647)
    (tagWord : transport[position]? = some 0) (kindWord : transport[position + 1]? = some 1)
    (lowWord : transport[position + 2]? = some low)
    (argumentsResult : ArgumentsEvaluateTo emitters.pack.program.core caller arguments
      (inputValues input work output transport.length workspace.length values.length length capacity depth active context contextLength) before) :
    ∃ after, Evaluates emitters.pack.program.core caller (.call checked.wrapper.source.function.id arguments)
        (.signed .i32 1) after ∧
      after.cellEntry? output = some { id := output, value := some (.array (signedI32Values (Encode.Immediate.written values start low))) } ∧
      after.cellEntry? work = some { id := work, value := some (.array (signedI32Values (afterLiteral workspace position start))) } ∧
      Emission values start (Encode.Immediate.bytes low) (Encode.Immediate.written values start low) ∧
      NativeRefines low (byteSlice (Encode.Immediate.written values start low) start 5) ∧
      CellEffect (writes output work) before after ∧ HeapFrame before after := by
  let c : Context := {
    input := input, output := output, work := work, transport := transport, values := values, workspace := workspace,
    length := length, position := position, depth := depth, active := active, capacity := capacity,
    start := start, top := top, context := context, contextLength := contextLength }
  obtain ⟨after, run, ⟨_, outputContents, workContents, rfl, window⟩, effect, heap⟩ :=
    (Literal.compiles checked c
      ⟨current, cursor, healthy, topFound, depthBound, storage, bounded, outputStorage, outputBound⟩
      ⟨.inl rfl, readable, tagWord, kindWord, lowWord⟩ room).call wellFormed argumentsResult
      ⟨plain, inputBacking, outputBacking, workBacking, inputOutput, inputWork, outputWork⟩
  have exactBytes : byteSlice (Encode.Immediate.written values start low) start 5 = Encode.Immediate.bytes low := by
    simpa only [Encode.Immediate.bytes_length] using window.bytes
  exact ⟨after, run, outputContents, workContents, window, exactBytes.symm ▸ bytes_refines canonical, effect, heap⟩

/-- Feed an actual serialized Core literal to the source-linked base case.
The transport prefix is restricted to the declared input length, so the
three-word read bounds, tags, and canonical signed range all follow from
serialization rather than independent caller assertions. -/
theorem from_transport (checked : Source.Expression.Literal.Checked emitters)
    (length position depth capacity start : Nat) (low top : Int) (active context contextLength : Value)
    (serialized : Transport.expression? sourceProgram (.value (.signed .i32 low)) = some words)
    (stream : ((transport : List Int).take length).drop position = words ++ suffix)
    (wellFormed : StateWellFormed before)
    (plain : ∀ value ∈ inputValues input work output transport.length workspace.length values.length
      length capacity depth active context contextLength, ∀ elements, value ≠ .array elements)
    (inputBacking : before.cellEntry? input = some { id := input, value := some (.array (signedI32Values transport)) })
    (outputBacking : before.cellEntry? output = some { id := output, value := some (.array (signedI32Values values)) })
    (workBacking : before.cellEntry? work = some { id := work, value := some (.array (signedI32Values workspace)) })
    (inputOutput : input ≠ output) (inputWork : input ≠ work) (outputWork : output ≠ work)
    (current : workspace[0]? = some (position : Int))
    (cursor : workspace[1]? = some (start : Int)) (healthy : workspace[4]? = some 0) (topFound : workspace[6]? = some top)
    (depthBound : depth < 512)
    (storage : length ≤ transport.length) (bounded : length ≤ 2147483647)
    (room : start + 5 ≤ capacity) (outputStorage : capacity ≤ values.length) (outputBound : capacity ≤ 2147483647)
    (argumentsResult : ArgumentsEvaluateTo emitters.pack.program.core caller arguments
      (inputValues input work output transport.length workspace.length values.length length capacity depth active context contextLength) before) :
    ∃ after, Evaluates emitters.pack.program.core caller (.call checked.wrapper.source.function.id arguments)
        (.signed .i32 1) after ∧
      after.cellEntry? output = some { id := output, value := some (.array (signedI32Values (Encode.Immediate.written values start low))) } ∧
      after.cellEntry? work = some { id := work, value := some (.array (signedI32Values (afterLiteral workspace position start))) } ∧
      Emission values start (Encode.Immediate.bytes low) (Encode.Immediate.written values start low) ∧
      NativeRefines low (byteSlice (Encode.Immediate.written values start low) start 5) ∧
      CellEffect (writes output work) before after ∧ HeapFrame before after := by
  obtain ⟨canonical, available, tag, kind, value⟩ := Transport.i32_window serialized stream
  have readable : position + 3 ≤ length := by
    simp only [List.length_take] at available
    omega
  rw [List.getElem?_take_of_lt (by omega)] at tag
  rw [List.getElem?_take_of_lt (by omega)] at kind
  rw [List.getElem?_take_of_lt (by omega)] at value
  exact compiles checked length position depth capacity start low top active context contextLength canonical
    wellFormed plain inputBacking outputBacking workBacking inputOutput inputWork outputWork current cursor healthy topFound
    depthBound readable storage bounded room outputStorage outputBound tag kind value argumentsResult

end Preservation
end Lanius.X86.Lower.Expression.Literal
