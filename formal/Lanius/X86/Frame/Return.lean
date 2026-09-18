import Lanius.X86.Frame.Function
import Lanius.X86.Buffer.Fixed

namespace Lanius.X86.Frame

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.X86.Source Lanius.X86.Buffer

/-- Authenticate the actual Lanius return routine against the same byte
protocol whose decoded machine execution is proved in `Frame.Protocol`. -/
abbrev CheckedReturn (program : Lanius.Extraction.CoreSynthesis.Program.CheckedProgram artifacts)
    (fits : CheckedFits program) :=
  CheckedFixed program fits ["backend", "frame"] "return_value" (epilogue.map UInt8.toNat)

def checkReturn? (program : Lanius.Extraction.CoreSynthesis.Program.CheckedProgram artifacts)
    (fits : CheckedFits program) : Option (CheckedReturn program fits) :=
  checkFixed? program fits ["backend", "frame"] "return_value" (epilogue.map UInt8.toNat)

/-- Source execution emits the actual executable epilogue, preserving every
other output position and caller cell. Loading those emitted bytes gives the
three decoded return steps used by `function_returns`; no output validator or
assumed encoder execution is needed. Loading/mapping remains explicit. -/
theorem return_emits (checked : CheckedReturn program fits) (capacity cursor : Nat)
    (wellFormed : StateWellFormed before) (room : cursor + 5 ≤ capacity)
    (storage : capacity ≤ values.length) (bounded : capacity ≤ 2147483647)
    (backing : before.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values values)) })
    (argumentsResult : ArgumentsEvaluateTo program.core caller arguments
      (fixedValues (.slice i32 cell [] 0 values.length) capacity cursor) before) :
    ∃ after emitted, Evaluates program.core caller (.call checked.source.function.id arguments)
        (.signed .i32 (cursor + 5 : Nat)) after ∧
      after.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values emitted)) } ∧
      byteSlice emitted cursor 5 = epilogue ∧
      (∀ machine, Machine.CodeAt machine.memory machine.rip (byteSlice emitted cursor 5) →
        Machine.Steps 3 machine (teardown machine)) ∧
      emitted.length = values.length ∧
      (∀ index, index < cursor ∨ cursor + 5 ≤ index → emitted[index]? = values[index]?) ∧
      CellEffect (CellSet.singleton cell) before after ∧ HeapFrame before after := by
  obtain ⟨after, run, contents, effect, heap⟩ := fixed_success checked capacity cursor
    wellFormed room storage bounded backing argumentsResult
  let emitted := writtenBytes values cursor (epilogue.map UInt8.toNat)
  have exactBytes : byteSlice emitted cursor 5 = epilogue := by
    change byteSlice emitted cursor (epilogue.map UInt8.toNat).length = epilogue
    rw [writtenBytes_byteSlice (by simpa [epilogue] using Nat.le_trans room storage)]
    rfl
  refine ⟨after, emitted, run, contents, exactBytes, ?_, writtenBytes_length, ?_, effect, heap⟩
  · intro machine loaded
    rw [exactBytes] at loaded
    exact epilogue_steps machine loaded
  · intro index outside
    exact writtenBytes_frame outside

end Lanius.X86.Frame
