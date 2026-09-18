import Lanius.X86.Lower.Expression.Literal.Emit
import Lanius.X86.Lower.Expression.Wrapper

namespace Lanius.X86.Lower.Expression.Literal

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView.Core Lanius.X86.Source Lanius.X86.Buffer

/-- A valid scalar literal at the current input cursor, not an execution premise. -/
structure Syntax (c : Context) (kind low : Int) : Prop where
  scalar : Scalar32 kind low
  readable : c.position + 3 ≤ c.length
  tagWord : c.transport[c.position]? = some 0
  kindWord : c.transport[c.position + 1]? = some kind
  lowWord : c.transport[c.position + 2]? = some low

/-- The actual expression call consumes three words, writes MOV32, restores
TOP and terminates. Retain exact integer output as well as its byte window. -/
theorem compiles (checked : Source.Expression.Literal.Checked emitters) (c : Context) (valid : c.Valid)
    (source : Syntax c kind low) (room : c.start + 5 ≤ c.capacity) :
    c.Call emitters.pack.program.core checked.wrapper.source.function.id kind
      (afterLiteral c.workspace c.position c.start)
      (fun emitted => emitted = Encode.Immediate.written c.values c.start low ∧
        Emission c.values c.start (Encode.Immediate.bytes low) emitted) := by
  have window : Emission c.values c.start (Encode.Immediate.bytes low) (Encode.Immediate.written c.values c.start low) := by
    refine ⟨Encode.Immediate.written_length, ?_, ?_⟩
    · simpa only [Encode.Immediate.bytes_length] using Encode.Immediate.emission (by have := valid.outputStorage; omega)
    · intro index outside
      exact Encode.Immediate.frame (by simpa only [Encode.Immediate.bytes_length] using outside)
  have sameTop : (afterLiteral c.workspace c.position c.start)[6]? = some c.top := by
    simpa only [afterLiteral, List.getElem?_set_ne (by decide : 1 ≠ 6),
      List.getElem?_set_ne (by decide : 0 ≠ 6)] using valid.topFound
  apply (Wrapper.finish_eq (kind := kind) sameTop) ▸
    Wrapper.call checked c kind _ _ valid.topFound (by simp [afterLiteral])
  constructor
  intro caller arguments before wellFormed evaluated memory
  obtain ⟨after, run, output, work, effect, heap⟩ :=
    emit_call checked c.length c.position c.depth c.capacity c.start low source.scalar c.active c.context c.contextLength
      wellFormed memory.plain memory.inputBacking memory.outputBacking memory.workBacking
      memory.inputOutput memory.inputWork memory.outputWork valid.current valid.cursor valid.healthy valid.depthBound
      source.readable valid.storage valid.bounded room valid.outputStorage valid.outputBound
      source.tagWord source.kindWord source.lowWord evaluated
  exact ⟨after, run, ⟨_, output, work, rfl, window⟩, effect, heap⟩

end Lanius.X86.Lower.Expression.Literal
