import Lanius.X86.Frame.Take

namespace Lanius.X86.Frame.Take.Reject

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView.Core
open Lanius.X86.Source Lanius.X86.Buffer

/-- Failure does not dereference the input argument. It can be unrelated to
any live backing allocation; only the workspace must be addressable. -/
def arguments (input : Value) (work : CellId) (length : Int) (workLength : Nat) : List Value :=
  [input, .signed .i32 length, .slice i32 work [] 0 workLength]

theorem guard (program : Program) (position length : Int)
    (positionRead : before.local? 3 = some (.signed .i32 position))
    (lengthRead : before.local? 1 = some (.signed .i32 length))
    (bad : position < 0 ∨ length ≤ position) :
    Evaluates program before Source.Take.guard (.boolean true) before := by
  have negative : Evaluates program before (.binary .less (read 3) (number 0))
      (.boolean (decide (position < 0))) before := by
    apply evaluatesEagerBinary (by decide) (by decide) (local_evaluates program positionRead)
      (show Evaluates program before (number 0) (.signed .i32 0) before from ⟨1, rfl⟩)
    rfl
  by_cases below : position < 0
  · rw [show decide (position < 0) = true from decide_eq_true below] at negative
    exact evaluatesLogicalOrTrue negative
  · rw [show decide (position < 0) = false from decide_eq_false below] at negative
    have outside : Evaluates program before (.binary .greaterEqual (read 3) (read 1)) (.boolean true) before := by
      apply evaluatesEagerBinary (by decide) (by decide) (local_evaluates program positionRead)
        (local_evaluates program lengthRead)
      have beyond : length ≤ position := bad.resolve_left below
      simp [evalBinaryValue, evalSignedBinary, beyond]
    exact evaluatesLogicalOrFalse negative outside

/-- The source body reads only INPUT and sets FAILED. The invalid transport
array is never inspected, and the INPUT cursor is not incremented. -/
theorem body (checked : Source.Take.Checked program) (length position : Int)
    (wellFormed : StateWellFormed before)
    (locals : Locals (arguments input work length workspace.length) frontier before)
    (workBacking : before.cellEntry? work = some { id := work, value := some (.array (signedI32Values workspace)) })
    (current : workspace[0]? = some position) (room : 4 < workspace.length)
    (bad : position < 0 ∨ length ≤ position) :
    ∃ after, Executes program.core before (Source.Take.body checked.input.id checked.failed.id)
        (.returned (some (.signed .i32 0))) after ∧
      after.cellEntry? work = some { id := work, value := some (.array (signedI32Values (workspace.set 4 1))) } ∧
      CellEffect (CellSet.singleton work) before after ∧ HeapFrame before after := by
  have within : 0 < workspace.length := by omega
  have initialConstant := checked.input.evaluates (before := before)
  rw [checked.values.1] at initialConstant
  have initial : Evaluates program.core before (Source.Take.field checked.input.id) (.signed .i32 position) before := by
    have read := evaluatesSignedI32SliceIndex program.core before before before workspace (Source.read 2)
      (.constant checked.input.id) work 0 within (local_evaluates _ (locals.found ⟨2, by simp [arguments]⟩))
      initialConstant workBacking
    have entry : workspace.get ⟨0, within⟩ = position := by
      simpa only [List.getElem?_eq_getElem within, Option.some.injEq, List.get_eq_getElem] using current
    simpa only [entry, Source.Take.field] using read
  let entered := before.bindLocal 3 (.signed .i32 position)
  have enteredWF := bindLocal_preserves_well_formed before 3 (.signed .i32 position) wellFormed
  have enteredLocals := locals.bind (id := 3) wellFormed (by simp [arguments]) (.signed .i32 position)
  have positionRead := bindLocal_finds_local before 3 (.signed .i32 position) wellFormed
  have enteredWork := ((bindLocal_effect before 3 (.signed .i32 position)).oldCells work
    (StateWellFormed.cell_lt_next_of_entry wellFormed workBacking) (by simp [CellSet.empty])).trans workBacking
  have invalid := guard program.core position length positionRead (enteredLocals.found ⟨1, by simp [arguments]⟩) bad
  have failureConstant := checked.failed.evaluates (before := entered)
  rw [checked.values.2] at failureConstant
  obtain ⟨completed, store, completedWork, _, heap, effect⟩ := evaluatesFramedSliceStore program.core entered entered workspace 2
    (.constant checked.failed.id) (number 1) work 4 1 enteredWF room
    (enteredLocals.found ⟨2, by simp [arguments]⟩) failureConstant
    (show Evaluates program.core entered (number 1) (.signed .i32 1) entered from ⟨1, rfl⟩)
    (CellEffect.refl (writes := CellSet.empty) enteredWF) (by simp [CellSet.empty]) enteredWork
  have zero : Evaluates program.core completed (number 0) (.signed .i32 0) completed := ⟨1, rfl⟩
  exact ⟨restoreLocals before completed,
    executesLetLocal initial (executesSequenceReturned
      (executesIfTrue invalid (executesSequence (executesExpression store)
        (executesSequenceReturned (executesReturnValue zero))))),
    completedWork, CellEffect.closeLocal before 3 (.signed .i32 position) wellFormed effect,
    HeapFrame.closeLocal before 3 (.signed .i32 position) heap⟩

/-- The actual source-authenticated call rejects negative and exhausted
cursors, including a negative declared length. No input buffer premise or
integer-overflow bound is needed because this branch performs no increment. -/
theorem rejects (checked : Source.Take.Checked program) (input : Value) (length position : Int)
    (wellFormed : StateWellFormed before)
    (workBacking : before.cellEntry? work = some { id := work, value := some (.array (signedI32Values workspace)) })
    (current : workspace[0]? = some position) (room : 4 < workspace.length)
    (bad : position < 0 ∨ length ≤ position)
    (argumentsResult : ArgumentsEvaluateTo program.core caller expressions
      (arguments input work length workspace.length) before) :
    ∃ after, Evaluates program.core caller (.call checked.internal.source.function.id expressions) (.signed .i32 0) after ∧
      after.cellEntry? work = some { id := work, value := some (.array (signedI32Values (workspace.set 4 1))) } ∧
      CellEffect (CellSet.singleton work) before after ∧ HeapFrame before after := by
  let params := parameterBindings (fun index : Fin 3 => (arguments input work length workspace.length).get index)
  have initialWF := enterCall_preserves_wellFormed wellFormed (bindings := params)
  have initialLocals := Locals.ofReads (values := arguments input work length workspace.length) initialWF
    (fun index => enterCall_parameterBindings_matches wellFormed index)
  have initialWork := ((enterCall_effect before params).oldCells work
    (StateWellFormed.cell_lt_next_of_entry wellFormed workBacking) (by simp [CellSet.empty])).trans workBacking
  obtain ⟨completed, run, finalWork, effect, heap⟩ := body checked length position initialWF initialLocals initialWork current room bad
  have called := checked.internal.call wellFormed argumentsResult (bindings := params) rfl run effect
  exact ⟨restoreLocals before completed, called.1, finalWork, called.2, HeapFrame.closeCall before params heap⟩

theorem retained_input (workspace : List Int) : (workspace.set 4 1)[0]? = workspace[0]? := by simp

theorem frame (workspace : List Int) (other : Nat) (different : other ≠ 4) :
    (workspace.set 4 1)[other]? = workspace[other]? := List.getElem?_set_ne (Ne.symm different)

end Lanius.X86.Frame.Take.Reject
