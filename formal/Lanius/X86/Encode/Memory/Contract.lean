import Lanius.X86.Encode.Memory
import Lanius.Extraction.Source.Call
import Lanius.X86.Buffer.Writer

namespace Lanius.X86.Encode.Memory

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts Lanius.X86.Buffer

/-- The public memory emitter's exact storage contract, for composition with
other source calls. The existing encoding theorem supplies its byte window. -/
theorem move_spec (checked : Source.Memory.CheckedMove program form load) (width : Register.Width)
    (reg base : Fin 16) (displacement : Int) (capacity start : Nat)
    (room : start + (moveConfig width load reg base displacement).size ≤ capacity)
    (storage : capacity ≤ values.length) (bounded : capacity ≤ 2147483647) :
    checked.Spec (moveValues (.slice Source.i32 cell [] 0 values.length) capacity start width reg base displacement)
      (.signed .i32 (start + (moveConfig width load reg base displacement).size : Nat))
      (fun before => before.cellEntry? cell = some ⟨cell, some (.array (signedI32Values values))⟩)
      (fun _ after => after.cellEntry? cell = some ⟨cell, some (.array
        (signedI32Values ((moveConfig width load reg base displacement).written values start)))⟩) (CellSet.singleton cell) := by
  apply checked.specCell rfl
  intro before wellFormed reads backing
  obtain ⟨after, run, result, effect, heap⟩ := succeeds form _ capacity start wellFormed room storage bounded backing
    (move_arguments program.core load (fun index => reads index.val index.isLt))
  exact ⟨after, executesSequenceReturned (executesReturnValue run), result, effect, heap⟩

/-- The public readonly call contract for a move rejected by its capacity check. -/
theorem move_rejects_spec (checked : Source.Memory.CheckedMove program form load)
    (width : Register.Width) (reg base : Fin 16) (displacement : Int) (output : Value)
    (capacity start : Int) (bounded : capacity ≤ 2147483647)
    (bad : reserved capacity start (Machine.memoryBytes width load reg base displacement).length = false) :
    CellSpec program.core checked.source.function.id
      (moveValues output capacity start width reg base displacement) (.signed .i32 (-1)) := by
  constructor
  intro caller arguments state wellFormed evaluated _
  obtain ⟨after, run, effect, heap⟩ := move_rejects_capacity checked width reg base displacement output capacity start
    wellFormed bounded bad evaluated
  exact ⟨after, run, trivial, effect, heap⟩

theorem attempt (checked : Source.Memory.CheckedMove program form load) (width : Register.Width)
    (reg base : Fin 16) (displacement : Int) (capacity : Nat) (before : Writer.Result)
    (storage : capacity ≤ before.values.length) (bounded : capacity ≤ 2147483647) :
    Writer.Spec program.core checked.source.function.id
      (moveValues (.slice Source.i32 cell [] 0 before.values.length) capacity before.cursor width reg base displacement)
      cell before (before.append capacity (moveConfig width load reg base displacement).size
        (moveConfig width load reg base displacement).written) := by
  apply Writer.reserve
  · intro start cursor room
    simpa only [Writer.Spec, Writer.Stored, cursor] using move_spec checked width reg base displacement capacity start room storage bounded
  · intro bad
    exact move_rejects_spec checked width reg base displacement _ capacity before.cursor (by omega)
      (by simpa only [(move_encoding width load reg base displacement).2] using bad)

end Lanius.X86.Encode.Memory
