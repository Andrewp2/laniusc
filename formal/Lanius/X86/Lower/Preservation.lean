import Lanius.X86.Lower.Compile

namespace Lanius.X86.Lower.Parameter

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView.Core Lanius.X86.Source Lanius.X86.Source.Lower Lanius.X86.Buffer

/-- The implementation proof itself supplies the machine-code certificate for
the actual output buffer. This does not run `certify?` or assume that an output
checker accepts. `Implementation.compile_function_certified` discharges the
selector premise from the input function and storage. -/
theorem compile_certified (checked : CheckedCompile emitters) (target : Checked function) (capacity start : Nat)
    (wellFormed : StateWellFormed before)
    (argumentsResult : ArgumentsEvaluateTo emitters.pack.program.core caller arguments
      (compileInputs input length (.slice i32 cell [] 0 values.length) capacity start) before)
    (selection : let entered := enterCall before (compileBindings input length (.slice i32 cell [] 0 values.length) capacity start)
      ∃ selected, Evaluates emitters.pack.program.core entered (.call checked.selector.source.function.id [read 0, read 1])
          (.signed .i32 target.argument.val) selected ∧ CellEffect CellSet.empty entered selected ∧ HeapFrame entered selected)
    (backing : before.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values values)) })
    (room : start + codeSize target.argument ≤ capacity) (storage : capacity ≤ values.length) (bounded : capacity ≤ 2147483647) :
    ∃ after emitted, Evaluates emitters.pack.program.core caller (.call checked.internal.source.function.id arguments)
        (.signed .i32 (start + codeSize target.argument : Nat)) after ∧
      after.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values emitted)) } ∧
      emitted.length = values.length ∧
      (∀ index, index < start ∨ start + codeSize target.argument ≤ index → emitted[index]? = values[index]?) ∧
      Nonempty (Certified function (byteSlice emitted start (codeSize target.argument))) ∧
      CellEffect (CellSet.singleton cell) before after ∧ HeapFrame before after := by
  obtain ⟨after, execution, contents, encoding, effect, heap⟩ := compile_selected checked target.argument capacity start
    wellFormed argumentsResult selection backing room storage bounded
  refine ⟨after, writtenBytes values start (code target.argument), execution, contents, writtenBytes_length, ?_,
    ⟨⟨target, encoding⟩⟩, effect, heap⟩
  intro index outside
  apply writtenBytes_frame
  rwa [(code_encoding target.argument).2.2]

end Lanius.X86.Lower.Parameter
