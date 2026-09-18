import Lanius.X86.Lower.Emission

namespace Lanius.X86.Lower.Parameter

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView.Core Lanius.X86.Source Lanius.X86.Source.Lower Lanius.X86.Buffer

def compileInputs (input : Value) (length : Int) (output : Value) (capacity cursor : Int) : List Value :=
  [input, .signed .i32 length, output, .signed .i32 capacity, .signed .i32 cursor]

def compileBindings (input : Value) (length : Int) (output : Value) (capacity cursor : Int) : List (VarId × Value) :=
  parameterBindings (fun index : Fin 5 => (compileInputs input length output capacity cursor).get index)

def selectedInputs (position : Fin 6) (input : Value) (length : Int) (output : Value) (capacity cursor : Int) : List Value :=
  compileInputs input length output capacity cursor ++ [.signed .i32 position.val]

def mappedInputs (position : Fin 6) (input : Value) (length : Int) (output : Value) (capacity cursor : Int) : List Value :=
  selectedInputs position input length output capacity cursor ++ [.signed .i32 (argumentRegister position).val]

theorem choose_size (program : Program) (position : Fin 6) (wellFormed : StateWellFormed before)
    (inputs : Locals (mappedInputs position input length output capacity cursor) frontier before) :
    ∃ after, Executes program (before.bindLocal 7 (.signed .i32 3)) chooseSize .next after ∧
      after.local? 7 = some (.signed .i32 (codeSize position)) ∧
      Locals (mappedInputs position input length output capacity cursor) frontier after ∧
      CellEffect (CellSet.singleton before.nextCell) (before.bindLocal 7 (.signed .i32 3)) after ∧
      HeapFrame (before.bindLocal 7 (.signed .i32 3)) after := by
  let scope := before.bindLocal 7 (.signed .i32 3)
  have scopeWF := bindLocal_preserves_well_formed before 7 (.signed .i32 3) wellFormed
  have scopeInputs := inputs.bind wellFormed (id := 7) (by simp [mappedInputs, selectedInputs, compileInputs]) (.signed .i32 3)
  have positionRead : scope.local? 5 = some (.signed .i32 position.val) :=
    scopeInputs.found ⟨5, by simp [mappedInputs, selectedInputs, compileInputs]⟩
  have compared : Evaluates program scope (.binary .greaterEqual (read 5) (number 4))
      (.boolean (decide (4 ≤ position.val))) scope := by
    apply evaluatesEagerBinary (by decide) (by decide)
      (local_evaluates program positionRead)
      (show Evaluates program scope (number 4) (.signed .i32 4) scope from ⟨1, rfl⟩)
    simp [evalBinaryValue, evalSignedBinary]
    omega
  by_cases high : 4 ≤ position.val
  · simp only [high, decide_true] at compared
    obtain ⟨after, updated, owned, effect, heap⟩ := evaluatesOwnedLocalUpdate scopeWF
      (bindLocal_owns_fresh before 7 (.signed .i32 3) wellFormed)
      (show Evaluates program scope (number 4) (.signed .i32 4) scope from ⟨1, rfl⟩)
      (show evalAssignValue program.target .set (some (.signed .i32 3)) (.signed .i32 4) = .ok (.signed .i32 4) from rfl)
    refine ⟨after, executesIfTrue compared (executesSequence (executesExpression updated) (executesSkip _ _)), ?_,
      scopeInputs.fresh scopeWF effect inputs.frontierBound, effect, heap⟩
    rw [codeSize, if_pos high]
    exact Assertion.localPointsTo_local 7 before.nextCell _ after owned
  · simp only [high, decide_false] at compared
    exact ⟨scope, executesIfFalse compared (executesSkip _ _),
      by rw [codeSize, if_neg high]; exact bindLocal_finds_local before 7 (.signed .i32 3) wellFormed,
      scopeInputs, CellEffect.refl scopeWF, HeapFrame.refl scope⟩

theorem mapped_return (checked : CheckedCompile emitters) (position : Fin 6) (capacity start : Nat)
    (wellFormed : StateWellFormed before)
    (inputs : Locals (mappedInputs position input length (.slice i32 cell [] 0 values.length) capacity start) frontier before)
    (backing : before.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values values)) })
    (room : start + codeSize position ≤ capacity) (storage : capacity ≤ values.length) (bounded : capacity ≤ 2147483647) :
    ∃ after, Executes emitters.pack.program.core before
        (mappedTail emitters.fits.source.function.id (emitters.registerWrappers .move).source.function.id
          emitters.returnNear.source.function.id checked.resultRegister.id)
        (.returned (some (.signed .i32 (start + codeSize position : Nat)))) after ∧
      after.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values (writtenBytes values start (code position)))) } ∧
      CellEffect (CellSet.singleton cell) before after ∧ HeapFrame before after := by
  have scopeWF := bindLocal_preserves_well_formed before 7 (.signed .i32 3) wellFormed
  obtain ⟨sized, sizeRun, sizeRead, sizedInputs, sizeEffect, sizeHeap⟩ := choose_size emitters.pack.program.core position wellFormed inputs
  have scopeBacking := ((bindLocal_effect before 7 (.signed .i32 3)).oldCells cell
    (StateWellFormed.cell_lt_next_of_entry wellFormed backing) (by simp [CellSet.empty])).trans backing
  have sizedBacking := sizeEffect.preserves_entry scopeWF scopeBacking
    (Nat.ne_of_lt (StateWellFormed.cell_lt_next_of_entry wellFormed backing))
  obtain ⟨written, run, contents, effect, heap⟩ := reserve_return checked position capacity start sizeEffect.wellFormed
    (sizedInputs.found ⟨2, by simp [mappedInputs, selectedInputs, compileInputs]⟩)
    (sizedInputs.found ⟨3, by simp [mappedInputs, selectedInputs, compileInputs]⟩)
    (sizedInputs.found ⟨4, by simp [mappedInputs, selectedInputs, compileInputs]⟩)
    (sizedInputs.found ⟨6, by simp [mappedInputs, selectedInputs, compileInputs]⟩)
    sizeRead sizedBacking room storage bounded
  have closed := CellEffect.closeLocal before 7 (.signed .i32 3) wellFormed
    ((sizeEffect.weaken CellSet.subset_union_left).trans (effect.weaken CellSet.subset_union_right))
  have narrow : CellEffect (CellSet.singleton cell) before (restoreLocals before written) := by
    apply closed.narrow
    intro changed old member
    rcases member with temporary | output
    · exact False.elim ((Nat.ne_of_lt old) temporary)
    · exact output
  exact ⟨restoreLocals before written, executesLetLocal
    (show Evaluates emitters.pack.program.core before (number 3) (.signed .i32 3) before from ⟨1, rfl⟩)
    (executesSequence sizeRun run), contents, narrow,
    HeapFrame.closeLocal before 7 (.signed .i32 3) (sizeHeap.trans heap)⟩

/-- Everything after selection is proved from the actual Lanius body: reject
negative positions, map the ABI register, choose the complete size, reserve,
emit both instructions, and restore every temporary/caller frame. -/
theorem selected_return (checked : CheckedCompile emitters) (position : Fin 6) (capacity start : Nat)
    (wellFormed : StateWellFormed before)
    (inputs : Locals (selectedInputs position input length (.slice i32 cell [] 0 values.length) capacity start) frontier before)
    (backing : before.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values values)) })
    (room : start + codeSize position ≤ capacity) (storage : capacity ≤ values.length) (bounded : capacity ≤ 2147483647) :
    ∃ after, Executes emitters.pack.program.core before
        (selectedTail checked.mapping.internal.source.function.id emitters.fits.source.function.id
          (emitters.registerWrappers .move).source.function.id emitters.returnNear.source.function.id checked.resultRegister.id)
        (.returned (some (.signed .i32 (start + codeSize position : Nat)))) after ∧
      after.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values (writtenBytes values start (code position)))) } ∧
      CellEffect (CellSet.singleton cell) before after ∧ HeapFrame before after := by
  have positionRead := inputs.found ⟨5, by simp [selectedInputs, compileInputs]⟩
  obtain ⟨mapped, mappingRun, mappingEffect, mappingHeap⟩ := argument_call checked.mapping position wellFormed
    (ArgumentsEvaluateTo.cons (local_evaluates _ positionRead) (.nil _ _))
  have mappedInputs := inputs.empty wellFormed mappingEffect
  have mappedBacking := mappingEffect.empty_preserves_entry wellFormed backing
  let register := (argumentRegister position).val
  let scope := mapped.bindLocal 6 (.signed .i32 register)
  have scopeWF := bindLocal_preserves_well_formed mapped 6 (.signed .i32 register) mappingEffect.wellFormed
  have scopeInputs := mappedInputs.push mappingEffect.wellFormed (.signed .i32 register)
  have scopeBacking := ((bindLocal_effect mapped 6 (.signed .i32 register)).oldCells cell
    (StateWellFormed.cell_lt_next_of_entry mappingEffect.wellFormed mappedBacking) (by simp [CellSet.empty])).trans mappedBacking
  obtain ⟨written, run, contents, effect, heap⟩ := mapped_return checked position capacity start scopeWF scopeInputs scopeBacking room storage bounded
  exact ⟨restoreLocals mapped written,
    executesSequence (nonnegative_guard _ 5 position.val positionRead) (executesLetLocal mappingRun run), contents,
    (mappingEffect.weaken CellSet.empty_subset).trans
      (CellEffect.closeLocal mapped 6 (.signed .i32 register) mappingEffect.wellFormed effect),
    mappingHeap.trans (HeapFrame.closeLocal mapped 6 (.signed .i32 register) heap)⟩

/-- Composition boundary for the actual public Lanius compile call.
`Implementation.compile_function` supplies this selector obligation from the
input transport; no output-validator hypothesis is needed. -/
theorem compile_selected (checked : CheckedCompile emitters) (position : Fin 6) (capacity start : Nat)
    (wellFormed : StateWellFormed before)
    (argumentsResult : ArgumentsEvaluateTo emitters.pack.program.core caller arguments
      (compileInputs input length (.slice i32 cell [] 0 values.length) capacity start) before)
    (selection : let entered := enterCall before (compileBindings input length (.slice i32 cell [] 0 values.length) capacity start)
      ∃ selected, Evaluates emitters.pack.program.core entered (.call checked.selector.source.function.id [read 0, read 1])
          (.signed .i32 position.val) selected ∧ CellEffect CellSet.empty entered selected ∧ HeapFrame entered selected)
    (backing : before.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values values)) })
    (room : start + codeSize position ≤ capacity) (storage : capacity ≤ values.length) (bounded : capacity ≤ 2147483647) :
    ∃ after, Evaluates emitters.pack.program.core caller (.call checked.internal.source.function.id arguments)
        (.signed .i32 (start + codeSize position : Nat)) after ∧
      after.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values (writtenBytes values start (code position)))) } ∧
      byteSlice (writtenBytes values start (code position)) start (codeSize position) = bytes position ∧
      CellEffect (CellSet.singleton cell) before after ∧ HeapFrame before after := by
  let params := compileBindings input length (.slice i32 cell [] 0 values.length) capacity start
  let entered := enterCall before params
  have enteredWF := enterCall_preserves_wellFormed wellFormed (bindings := params)
  have enteredReads (index : Fin 5) : entered.local? index.val = some
      ((compileInputs input length (.slice i32 cell [] 0 values.length) capacity start).get index) :=
    enterCall_parameterBindings_matches wellFormed index
  have enteredInputs := Locals.ofReads (values := compileInputs input length (.slice i32 cell [] 0 values.length) capacity start) enteredWF enteredReads
  have enteredBacking := ((enterCall_effect before params).oldCells cell
    (StateWellFormed.cell_lt_next_of_entry wellFormed backing) (by simp [CellSet.empty])).trans backing
  obtain ⟨selected, selectRun, selectEffect, selectHeap⟩ := selection
  have selectedInputs := enteredInputs.empty enteredWF selectEffect
  have selectedBacking := selectEffect.empty_preserves_entry enteredWF enteredBacking
  let scope := selected.bindLocal 5 (.signed .i32 position.val)
  have scopeWF := bindLocal_preserves_well_formed selected 5 (.signed .i32 position.val) selectEffect.wellFormed
  have scopeInputs := selectedInputs.push selectEffect.wellFormed (.signed .i32 position.val)
  have scopeBacking := ((bindLocal_effect selected 5 (.signed .i32 position.val)).oldCells cell
    (StateWellFormed.cell_lt_next_of_entry selectEffect.wellFormed selectedBacking) (by simp [CellSet.empty])).trans selectedBacking
  obtain ⟨written, run, contents, effect, heap⟩ := selected_return checked position capacity start scopeWF scopeInputs scopeBacking room storage bounded
  have compiled := checked.internal.call wellFormed argumentsResult (bindings := params) rfl
    (executesLetLocal selectRun run) ((selectEffect.weaken CellSet.empty_subset).trans
      (CellEffect.closeLocal selected 5 (.signed .i32 position.val) selectEffect.wellFormed effect))
  refine ⟨restoreLocals before (restoreLocals selected written), compiled.1, contents, ?_, compiled.2,
    HeapFrame.closeCall before params (selectHeap.trans (HeapFrame.closeLocal selected 5 (.signed .i32 position.val) heap))⟩
  have encoding := code_encoding position
  rw [← encoding.2.2, writtenBytes_byteSlice (by rw [encoding.2.2]; omega), encoding.1]

end Lanius.X86.Lower.Parameter
