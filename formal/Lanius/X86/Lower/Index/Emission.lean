import Lanius.X86.Lower.Index.Body

namespace Lanius.X86.Lower.Index.Emission

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView.Core Lanius.X86.Source Lanius.X86.Buffer

/-- Enter and close the real lexical scope. The cursor's fresh cell cannot
belong to the old caller frame and is removed from the public footprint. -/
theorem body (checked : Source.Index.Checked emitters) (signed : Bool) (capacity slot start : Nat)
    (wellFormed : StateWellFormed before)
    (inputs : Locals (inputValues output work values.length workspace.length capacity slot (kindValue signed)) frontier before)
    (distinct : output ≠ work)
    (outputBacking : before.cellEntry? output = some { id := output, value := some (.array (signedI32Values values)) })
    (workBacking : before.cellEntry? work = some { id := work, value := some (.array (signedI32Values workspace)) })
    (current : workspace[1]? = some (start : Int)) (slotBound : slot ≤ 1048576)
    (room : start + (codeBytes signed slot).length ≤ capacity) (storage : capacity ≤ values.length) (bounded : capacity ≤ 2147483647) :
    ∃ after emitted, Executes emitters.pack.program.core before (Source.Index.body checked.constants checked.helpers.calls)
        (.returned (some (.signed .i32 (start + (codeBytes signed slot).length : Nat)))) after ∧
      after.cellEntry? output = some { id := output, value := some (.array (signedI32Values emitted)) } ∧
      after.cellEntry? work = some { id := work, value := some (.array (signedI32Values (workspace.set 1 (start + (codeBytes signed slot).length : Nat)))) } ∧
      Buffer.Emission values start (codeBytes signed slot) emitted ∧
      CellEffect (CellSet.union (CellSet.singleton output) (CellSet.singleton work)) before after ∧ HeapFrame before after := by
  have within : 1 < workspace.length := by
    by_cases inside : 1 < workspace.length
    · exact inside
    · rw [List.getElem?_eq_none (by omega)] at current
      cases current
  have guard := kind_valid checked.constants signed (inputs.found ⟨4, by simp⟩)
  have initial := Frame.Slot.code_read checked.constants.code checked.constants.values.1
    (inputs.found ⟨2, by simp⟩) workBacking current
  let entered := before.bindLocal 5 (.signed .i32 start)
  have enteredWF := bindLocal_preserves_well_formed before 5 (.signed .i32 start) wellFormed
  have ready : Ready entered output work before.nextCell frontier capacity slot (kindValue signed) start values workspace :=
    ⟨enteredWF, inputs.bind wellFormed (by simp) (.signed .i32 start),
      ((bindLocal_effect before 5 (.signed .i32 start)).oldCells output
        (StateWellFormed.cell_lt_next_of_entry wellFormed outputBacking) (by simp [CellSet.empty])).trans outputBacking,
      ((bindLocal_effect before 5 (.signed .i32 start)).oldCells work
        (StateWellFormed.cell_lt_next_of_entry wellFormed workBacking) (by simp [CellSet.empty])).trans workBacking,
      bindLocal_owns_fresh before 5 (.signed .i32 start) wellFormed, inputs.frontierBound, distinct⟩
  obtain ⟨completed, emitted, run, outputContents, workContents, window, effect, heap⟩ :=
    scope checked signed ready within slotBound room storage bounded
  have closed := (CellEffect.closeLocal before 5 (.signed .i32 start) wellFormed effect).narrow
    (kept := CellSet.union (CellSet.singleton output) (CellSet.singleton work)) (by
      intro cell old changed
      rcases changed with out | work | temporary
      · exact Or.inl out
      · exact Or.inr work
      · change cell = before.nextCell at temporary
        exact False.elim ((Nat.ne_of_lt old) temporary))
  exact ⟨restoreLocals before completed, emitted,
    executesSequence (executesIfFalse guard (executesSkip _ _)) (executesLetLocal initial run),
    outputContents, workContents, window, closed, HeapFrame.closeLocal before 5 (.signed .i32 start) heap⟩

/-- The actual checked-address function emits the complete machine sequence,
not just its individual instructions. Both index widths, workspace updates,
the lexical cursor, exact bytes, and restoration of the caller are composed.
This is the sufficient-capacity contract; rejection remains separate. -/
theorem emits (checked : Source.Index.Checked emitters) (signed : Bool) (capacity slot start : Nat)
    (wellFormed : StateWellFormed before) (distinct : output ≠ work)
    (outputBacking : before.cellEntry? output = some { id := output, value := some (.array (signedI32Values values)) })
    (workBacking : before.cellEntry? work = some { id := work, value := some (.array (signedI32Values workspace)) })
    (current : workspace[1]? = some (start : Int)) (slotBound : slot ≤ 1048576)
    (room : start + (Machine.Index.bytes signed slot).length ≤ capacity) (storage : capacity ≤ values.length) (bounded : capacity ≤ 2147483647)
    (argumentsResult : ArgumentsEvaluateTo emitters.pack.program.core caller arguments
      (inputValues output work values.length workspace.length capacity slot (kindValue signed)) before) :
    ∃ after emitted, Evaluates emitters.pack.program.core caller (.call checked.internal.source.function.id arguments)
        (.signed .i32 (start + (Machine.Index.bytes signed slot).length : Nat)) after ∧
      after.cellEntry? output = some { id := output, value := some (.array (signedI32Values emitted)) } ∧
      after.cellEntry? work = some { id := work, value := some (.array (signedI32Values
        (workspace.set 1 (start + (Machine.Index.bytes signed slot).length : Nat)))) } ∧
      Buffer.Emission values start (Machine.Index.bytes signed slot) emitted ∧
      CellEffect (CellSet.union (CellSet.singleton output) (CellSet.singleton work)) before after ∧ HeapFrame before after := by
  let params := parameterBindings (fun index : Fin 5 =>
    (inputValues output work values.length workspace.length capacity slot (kindValue signed)).get index)
  have calleeWF := enterCall_preserves_wellFormed wellFormed (bindings := params)
  have inputs := Locals.ofReads (values := inputValues output work values.length workspace.length capacity slot (kindValue signed)) calleeWF
    (fun index => enterCall_parameterBindings_matches wellFormed index)
  have calleeOutput := ((enterCall_effect before params).oldCells output
    (StateWellFormed.cell_lt_next_of_entry wellFormed outputBacking) (by simp [CellSet.empty])).trans outputBacking
  have calleeWork := ((enterCall_effect before params).oldCells work
    (StateWellFormed.cell_lt_next_of_entry wellFormed workBacking) (by simp [CellSet.empty])).trans workBacking
  obtain ⟨completed, emitted, run, outputContents, workContents, window, effect, heap⟩ := body checked signed capacity slot start
    calleeWF inputs distinct calleeOutput calleeWork current slotBound (by rw [code_bytes]; exact room) storage bounded
  rw [code_bytes] at run workContents window
  have called := checked.internal.call wellFormed argumentsResult (bindings := params) rfl run effect
  exact ⟨restoreLocals before completed, emitted, called.1, outputContents, workContents, window,
    called.2, HeapFrame.closeCall before params heap⟩

end Lanius.X86.Lower.Index.Emission
