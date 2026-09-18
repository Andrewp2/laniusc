import Lanius.X86.Lower.Compile

namespace Lanius.X86.Lower.Parameter

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView.Core Lanius.X86.Source Lanius.X86.Source.Lower Lanius.X86.Buffer

theorem negative_evaluates (program : Program) :
    Evaluates program before negativeOne (.signed .i32 (-1)) before := by
  apply evaluatesUnary (show Evaluates program before (number 1) (.signed .i32 1) before from ⟨1, rfl⟩)
  simp [evalUnaryValue, wrapSigned, signedModulus, signedSignBit, SignedIntTy.bits]

/-- Whole-function reservation fails before either emitter or any output
access. In particular, `output` need not be a valid slice on this path. -/
theorem reserve_reject (checked : CheckedCompile emitters) (position : Fin 6) (capacity start : Int)
    (wellFormed : StateWellFormed before)
    (capacityRead : before.local? 3 = some (.signed .i32 capacity))
    (cursorRead : before.local? 4 = some (.signed .i32 start))
    (sizeRead : before.local? 7 = some (.signed .i32 (codeSize position)))
    (bounded : capacity ≤ 2147483647) (bad : reserved capacity start (codeSize position) = false) :
    ∃ after, Executes emitters.pack.program.core before
        (reserveTail emitters.fits.source.function.id (emitters.registerWrappers .move).source.function.id
          emitters.returnNear.source.function.id checked.resultRegister.id)
        (.returned (some (.signed .i32 (-1)))) after ∧
      CellEffect CellSet.empty before after ∧ HeapFrame before after := by
  have args : ArgumentsEvaluateTo emitters.pack.program.core before [read 3, read 4, read 7]
      (fitsValues capacity start (codeSize position)) before :=
    .cons (local_evaluates _ capacityRead) (.cons (local_evaluates _ cursorRead)
      (.cons (local_evaluates _ sizeRead) (.nil _ _)))
  obtain ⟨after, fitRun, effect, heap⟩ := fits_call emitters.fits capacity start (codeSize position) wellFormed bounded args
  rw [bad] at fitRun
  have guard := evaluatesUnary fitRun (show evalUnaryValue emitters.pack.program.core.target .logicalNot
    (.boolean false) = .ok (.boolean true) from rfl)
  exact ⟨after, executesSequenceReturned (executesIfTrue guard
    (executesSequenceReturned (executesReturnValue (negative_evaluates _)))), effect, heap⟩

theorem mapped_reject (checked : CheckedCompile emitters) (position : Fin 6) (capacity start : Int)
    (wellFormed : StateWellFormed before)
    (inputs : Locals (mappedInputs position input length output capacity start) frontier before)
    (bounded : capacity ≤ 2147483647) (bad : reserved capacity start (codeSize position) = false) :
    ∃ after, Executes emitters.pack.program.core before
        (mappedTail emitters.fits.source.function.id (emitters.registerWrappers .move).source.function.id
          emitters.returnNear.source.function.id checked.resultRegister.id)
        (.returned (some (.signed .i32 (-1)))) after ∧
      CellEffect CellSet.empty before after ∧ HeapFrame before after := by
  obtain ⟨sized, sizeRun, sizeRead, sizedInputs, sizeEffect, sizeHeap⟩ := choose_size emitters.pack.program.core position wellFormed inputs
  obtain ⟨after, run, effect, heap⟩ := reserve_reject checked position capacity start sizeEffect.wellFormed
    (sizedInputs.found ⟨3, by simp [mappedInputs, selectedInputs, compileInputs]⟩)
    (sizedInputs.found ⟨4, by simp [mappedInputs, selectedInputs, compileInputs]⟩) sizeRead bounded bad
  have closed := CellEffect.closeLocal before 7 (.signed .i32 3) wellFormed
    (sizeEffect.trans (effect.weaken CellSet.empty_subset))
  have narrow : CellEffect CellSet.empty before (restoreLocals before after) :=
    closed.narrow (by intro cell old member; exact False.elim ((Nat.ne_of_lt old) member))
  exact ⟨restoreLocals before after, executesLetLocal
    (show Evaluates emitters.pack.program.core before (number 3) (.signed .i32 3) before from ⟨1, rfl⟩)
    (executesSequence sizeRun run), narrow,
    HeapFrame.closeLocal before 7 (.signed .i32 3) (sizeHeap.trans heap)⟩

theorem selected_reject (checked : CheckedCompile emitters) (position : Fin 6) (capacity start : Int)
    (wellFormed : StateWellFormed before)
    (inputs : Locals (selectedInputs position input length output capacity start) frontier before)
    (bounded : capacity ≤ 2147483647) (bad : reserved capacity start (codeSize position) = false) :
    ∃ after, Executes emitters.pack.program.core before
        (selectedTail checked.mapping.internal.source.function.id emitters.fits.source.function.id
          (emitters.registerWrappers .move).source.function.id emitters.returnNear.source.function.id checked.resultRegister.id)
        (.returned (some (.signed .i32 (-1)))) after ∧
      CellEffect CellSet.empty before after ∧ HeapFrame before after := by
  have positionRead := inputs.found ⟨5, by simp [selectedInputs, compileInputs]⟩
  obtain ⟨mapped, mappingRun, mappingEffect, mappingHeap⟩ := argument_call checked.mapping position wellFormed
    (ArgumentsEvaluateTo.cons (local_evaluates _ positionRead) (.nil _ _))
  have mappedInputs := inputs.empty wellFormed mappingEffect
  let register := (argumentRegister position).val
  let scope := mapped.bindLocal 6 (.signed .i32 register)
  have scopeWF := bindLocal_preserves_well_formed mapped 6 (.signed .i32 register) mappingEffect.wellFormed
  have scopeInputs := mappedInputs.push mappingEffect.wellFormed (.signed .i32 register)
  obtain ⟨after, run, effect, heap⟩ := mapped_reject checked position capacity start scopeWF scopeInputs bounded bad
  exact ⟨restoreLocals mapped after,
    executesSequence (nonnegative_guard _ 5 position.val positionRead) (executesLetLocal mappingRun run),
    mappingEffect.trans (CellEffect.closeLocal mapped 6 (.signed .i32 register) mappingEffect.wellFormed effect),
    mappingHeap.trans (HeapFrame.closeLocal mapped 6 (.signed .i32 register) heap)⟩

theorem compile_capacity_reject (checked : CheckedCompile emitters) (position : Fin 6) (capacity start : Int)
    (wellFormed : StateWellFormed before)
    (argumentsResult : ArgumentsEvaluateTo emitters.pack.program.core caller arguments
      (compileInputs input length output capacity start) before)
    (selection : let entered := enterCall before (compileBindings input length output capacity start)
      ∃ selected, Evaluates emitters.pack.program.core entered (.call checked.selector.source.function.id [read 0, read 1])
          (.signed .i32 position.val) selected ∧ CellEffect CellSet.empty entered selected ∧ HeapFrame entered selected)
    (bounded : capacity ≤ 2147483647) (bad : reserved capacity start (codeSize position) = false) :
    ∃ after, Evaluates emitters.pack.program.core caller (.call checked.internal.source.function.id arguments)
        (.signed .i32 (-1)) after ∧ CellEffect CellSet.empty before after ∧ HeapFrame before after := by
  let params := compileBindings input length output capacity start
  let entered := enterCall before params
  have enteredWF := enterCall_preserves_wellFormed wellFormed (bindings := params)
  have enteredReads (index : Fin 5) : entered.local? index.val = some
      ((compileInputs input length output capacity start).get index) := enterCall_parameterBindings_matches wellFormed index
  have enteredInputs := Locals.ofReads (values := compileInputs input length output capacity start) enteredWF enteredReads
  obtain ⟨selected, selectRun, selectEffect, selectHeap⟩ := selection
  have selectedInputs := enteredInputs.empty enteredWF selectEffect
  have scopeWF := bindLocal_preserves_well_formed selected 5 (.signed .i32 position.val) selectEffect.wellFormed
  have scopeInputs := selectedInputs.push selectEffect.wellFormed (.signed .i32 position.val)
  obtain ⟨after, run, effect, heap⟩ := selected_reject checked position capacity start scopeWF scopeInputs bounded bad
  have compiled := checked.internal.call wellFormed argumentsResult (bindings := params) rfl
    (executesLetLocal selectRun run)
    (selectEffect.trans (CellEffect.closeLocal selected 5 (.signed .i32 position.val) selectEffect.wellFormed effect))
  exact ⟨restoreLocals before (restoreLocals selected after), compiled.1, compiled.2,
    HeapFrame.closeCall before params (selectHeap.trans (HeapFrame.closeLocal selected 5 (.signed .i32 position.val) heap))⟩

/-- A selector failure returns before register mapping, reservation, or any
output access. The selector's own rejection proof remains an explicit input. -/
theorem compile_selection_reject (checked : CheckedCompile emitters) (capacity start : Int)
    (wellFormed : StateWellFormed before)
    (argumentsResult : ArgumentsEvaluateTo emitters.pack.program.core caller arguments
      (compileInputs input length output capacity start) before)
    (selection : let entered := enterCall before (compileBindings input length output capacity start)
      ∃ selected, Evaluates emitters.pack.program.core entered (.call checked.selector.source.function.id [read 0, read 1])
          (.signed .i32 (-1)) selected ∧ CellEffect CellSet.empty entered selected ∧ HeapFrame entered selected) :
    ∃ after, Evaluates emitters.pack.program.core caller (.call checked.internal.source.function.id arguments)
        (.signed .i32 (-1)) after ∧ CellEffect CellSet.empty before after ∧ HeapFrame before after := by
  let params := compileBindings input length output capacity start
  obtain ⟨selected, selectRun, selectEffect, selectHeap⟩ := selection
  let scope := selected.bindLocal 5 (.signed .i32 (-1))
  have scopeWF := bindLocal_preserves_well_formed selected 5 (.signed .i32 (-1)) selectEffect.wellFormed
  have selectedRead := bindLocal_finds_local selected 5 (.signed .i32 (-1)) selectEffect.wellFormed
  have guard : Evaluates emitters.pack.program.core scope (.binary .less (read 5) (number 0)) (.boolean true) scope := by
    apply evaluatesEagerBinary (by decide) (by decide) (local_evaluates _ selectedRead)
      (show Evaluates emitters.pack.program.core scope (number 0) (.signed .i32 0) scope from ⟨1, rfl⟩)
    rfl
  have run : Executes emitters.pack.program.core scope
      (selectedTail checked.mapping.internal.source.function.id emitters.fits.source.function.id
        (emitters.registerWrappers .move).source.function.id emitters.returnNear.source.function.id checked.resultRegister.id)
      (.returned (some (.signed .i32 (-1)))) scope :=
    executesSequenceReturned (executesIfTrue guard (executesSequenceReturned (executesReturnValue (negative_evaluates _))))
  have compiled := checked.internal.call wellFormed argumentsResult (bindings := params) rfl (executesLetLocal selectRun run)
    (selectEffect.trans (CellEffect.closeLocal selected 5 (.signed .i32 (-1)) selectEffect.wellFormed (CellEffect.refl scopeWF)))
  exact ⟨restoreLocals before (restoreLocals selected scope), compiled.1, compiled.2,
    HeapFrame.closeCall before params (selectHeap.trans (HeapFrame.closeLocal selected 5 (.signed .i32 (-1)) (HeapFrame.refl scope)))⟩

end Lanius.X86.Lower.Parameter
