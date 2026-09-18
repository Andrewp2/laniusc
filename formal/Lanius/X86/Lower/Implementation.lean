import Lanius.X86.Lower.Preservation
import Lanius.X86.Lower.Reject
import Lanius.X86.Select.Source
import Lanius.X86.Select.Frame

namespace Lanius.X86.Lower.Parameter

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView.Core Lanius.X86.Source Lanius.X86.Source.Lower Lanius.X86.Buffer

/-- Discharge selection in the precise state created by the public compile
call, including arbitrary output values and possibly aliased buffers. -/
theorem select_entered (checked : CheckedCompile emitters) (target : Checked function)
    (output : Value) (capacity start : Int)
    (wellFormed : StateWellFormed before)
    (inputBacking : before.cellEntry? inputCell =
      some { id := inputCell, value := some (.array (signedI32Values target.words)) }) :
    let input := Value.slice i32 inputCell [] 0 target.words.length
    let entered := enterCall before (compileBindings input target.words.length output capacity start)
    ∃ selected, Evaluates emitters.pack.program.core entered
        (.call checked.selector.source.function.id [read 0, read 1]) (.signed .i32 target.argument.val) selected ∧
      CellEffect CellSet.empty entered selected ∧ HeapFrame entered selected := by
  let input := Value.slice i32 inputCell [] 0 target.words.length
  let params := compileBindings input target.words.length output capacity start
  let entered := enterCall before params
  have enteredWF := enterCall_preserves_wellFormed wellFormed (bindings := params)
  have enteredReads (index : Fin 5) : entered.local? index.val = some
      ((compileInputs input target.words.length output capacity start).get index) :=
    enterCall_parameterBindings_matches wellFormed index
  have enteredBacking := ((enterCall_effect before params).oldCells inputCell
    (StateWellFormed.cell_lt_next_of_entry wellFormed inputBacking) (by simp [CellSet.empty])).trans inputBacking
  have dataBacking : entered.cellEntry? inputCell =
      some { id := inputCell, value := some (.array (signedI32Values target.selectorInput.words)) } := by
    rw [target.selector_words]
    exact enteredBacking
  have argumentsResult : ArgumentsEvaluateTo emitters.pack.program.core entered [read 0, read 1]
      [.slice i32 inputCell [] 0 target.selectorInput.words.length, .signed .i32 target.selectorInput.words.length] entered := by
    rw [target.selector_words]
    exact .cons (local_evaluates _ (enteredReads ⟨0, by decide⟩))
      (.cons (local_evaluates _ (enteredReads ⟨1, by decide⟩)) (.nil _ _))
  exact Select.Frame.call checked.selector target.selectorInput enteredWF dataBacking argumentsResult

/-- The Lanius implementation produces the exact machine encoding from the
actual Core-function transport. No selector, emitter, or validator success is
assumed. Buffer ownership/capacity and the supported Core domain are explicit. -/
theorem compile_function (checked : CheckedCompile emitters) (target : Checked function) (capacity start : Nat)
    (wellFormed : StateWellFormed before)
    (argumentsResult : ArgumentsEvaluateTo emitters.pack.program.core caller arguments
      (compileInputs (.slice i32 inputCell [] 0 target.words.length) target.words.length
        (.slice i32 cell [] 0 values.length) capacity start) before)
    (inputBacking : before.cellEntry? inputCell =
      some { id := inputCell, value := some (.array (signedI32Values target.words)) })
    (backing : before.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values values)) })
    (room : start + codeSize target.argument ≤ capacity) (storage : capacity ≤ values.length) (bounded : capacity ≤ 2147483647) :
    ∃ after, Evaluates emitters.pack.program.core caller (.call checked.internal.source.function.id arguments)
        (.signed .i32 (start + codeSize target.argument : Nat)) after ∧
      after.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values (writtenBytes values start (code target.argument)))) } ∧
      byteSlice (writtenBytes values start (code target.argument)) start (codeSize target.argument) = bytes target.argument ∧
      CellEffect (CellSet.singleton cell) before after ∧ HeapFrame before after :=
  compile_selected checked target.argument capacity start wellFormed argumentsResult
    (select_entered checked target (.slice i32 cell [] 0 values.length) capacity start wellFormed inputBacking)
    backing room storage bounded

/-- Failed whole-function reservation rejects without reading or writing the
output, now with the selector's execution also proved from the input storage. -/
theorem compile_function_rejects_capacity (checked : CheckedCompile emitters) (target : Checked function) (capacity start : Int)
    (wellFormed : StateWellFormed before)
    (argumentsResult : ArgumentsEvaluateTo emitters.pack.program.core caller arguments
      (compileInputs (.slice i32 inputCell [] 0 target.words.length) target.words.length output capacity start) before)
    (inputBacking : before.cellEntry? inputCell =
      some { id := inputCell, value := some (.array (signedI32Values target.words)) })
    (bounded : capacity ≤ 2147483647) (bad : reserved capacity start (codeSize target.argument) = false) :
    ∃ after, Evaluates emitters.pack.program.core caller (.call checked.internal.source.function.id arguments)
        (.signed .i32 (-1)) after ∧ CellEffect CellSet.empty before after ∧ HeapFrame before after :=
  compile_capacity_reject checked target.argument capacity start wellFormed argumentsResult
    (select_entered checked target output capacity start wellFormed inputBacking) bounded bad

/-- The certificate is constructed from execution of the complete Lanius
lowering implementation, not from accepting untrusted emitted bytes. -/
theorem compile_function_certified (checked : CheckedCompile emitters) (target : Checked function) (capacity start : Nat)
    (wellFormed : StateWellFormed before)
    (argumentsResult : ArgumentsEvaluateTo emitters.pack.program.core caller arguments
      (compileInputs (.slice i32 inputCell [] 0 target.words.length) target.words.length
        (.slice i32 cell [] 0 values.length) capacity start) before)
    (inputBacking : before.cellEntry? inputCell =
      some { id := inputCell, value := some (.array (signedI32Values target.words)) })
    (backing : before.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values values)) })
    (room : start + codeSize target.argument ≤ capacity) (storage : capacity ≤ values.length) (bounded : capacity ≤ 2147483647) :
    ∃ after emitted, Evaluates emitters.pack.program.core caller (.call checked.internal.source.function.id arguments)
        (.signed .i32 (start + codeSize target.argument : Nat)) after ∧
      after.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values emitted)) } ∧
      emitted.length = values.length ∧
      (∀ index, index < start ∨ start + codeSize target.argument ≤ index → emitted[index]? = values[index]?) ∧
      Nonempty (Certified function (byteSlice emitted start (codeSize target.argument))) ∧
      CellEffect (CellSet.singleton cell) before after ∧ HeapFrame before after :=
  compile_certified checked target capacity start wellFormed argumentsResult
    (select_entered checked target (.slice i32 cell [] 0 values.length) capacity start wellFormed inputBacking)
    backing room storage bounded

end Lanius.X86.Lower.Parameter
