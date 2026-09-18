import Lanius.X86.Source.Buffer
import Lanius.X86.Relative
import Lanius.FunctionalViewCoreSimulation
import Lanius.Separation.HeapFrame

namespace Lanius.X86.Buffer

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView.Core Lanius.X86.Source

theorem local_evaluates (program : Program) {id : VarId} (found : before.local? id = some value) :
    Evaluates program before (.local id) value before :=
  ⟨1, evalLocal_of_local 0 program before id value found⟩

def reserved (capacity cursor count : Int) : Bool :=
  decide (0 ≤ cursor ∧ 0 ≤ count ∧ cursor + count ≤ capacity)

private def bad (capacity cursor count : Int) : Bool :=
  decide (capacity < 0) || decide (cursor < 0) || decide (count < 0) || decide (capacity < cursor)

private theorem less_evaluates
    (left : Evaluates program before a (.signed .i32 x) before)
    (right : Evaluates program before b (.signed .i32 y) before) :
    Evaluates program before (.binary .less a b) (.boolean (decide (x < y))) before := by
  apply evaluatesEagerBinary (by decide) (by decide) left right
  simp [evalBinaryValue, evalSignedBinary]

private theorem greater_evaluates
    (left : Evaluates program before a (.signed .i32 x) before)
    (right : Evaluates program before b (.signed .i32 y) before) :
    Evaluates program before (.binary .greater a b) (.boolean (decide (y < x))) before := by
  apply evaluatesEagerBinary (by decide) (by decide) left right
  simp [evalBinaryValue, evalSignedBinary]

private theorem guard_evaluates (program : Program)
    (capacityRead : before.local? 0 = some (.signed .i32 capacity))
    (cursorRead : before.local? 1 = some (.signed .i32 cursor))
    (countRead : before.local? 2 = some (.signed .i32 count)) :
    Evaluates program before fitsGuard (.boolean (bad capacity cursor count)) before := by
  exact evaluatesPureLogicalOr (evaluatesPureLogicalOr (evaluatesPureLogicalOr
    (less_evaluates (local_evaluates program capacityRead) ⟨1, rfl⟩)
    (less_evaluates (local_evaluates program cursorRead) ⟨1, rfl⟩))
    (less_evaluates (local_evaluates program countRead) ⟨1, rfl⟩))
    (greater_evaluates (local_evaluates program cursorRead) (local_evaluates program capacityRead))

/-- The actual guard executes before subtraction. Even negative arguments and
exhausted ranges return a Boolean without reading or modifying any buffer. -/
theorem fits_body (program : Program) (capacity cursor count : Int)
    (capacityBound : capacity ≤ 2147483647)
    (capacityRead : before.local? 0 = some (.signed .i32 capacity))
    (cursorRead : before.local? 1 = some (.signed .i32 cursor))
    (countRead : before.local? 2 = some (.signed .i32 count)) :
    Executes program before fitsBody (.returned (some (.boolean (reserved capacity cursor count)))) before := by
  have guard := guard_evaluates program capacityRead cursorRead countRead
  cases flag : bad capacity cursor count with
  | true =>
      rw [flag] at guard
      have result : reserved capacity cursor count = false := by
        simp only [bad, Bool.or_eq_true, decide_eq_true_eq] at flag
        simp only [reserved, decide_eq_false_iff_not]
        omega
      rw [result]
      exact executesSequenceReturned (executesIfTrue guard
        (executesSequenceReturned (executesReturnValue ⟨1, rfl⟩)))
  | false =>
      rw [flag] at guard
      have domain : 0 ≤ capacity ∧ 0 ≤ cursor ∧ 0 ≤ count ∧ cursor ≤ capacity := by
        simp only [bad, Bool.or_eq_false_iff, decide_eq_false_iff_not] at flag
        omega
      have subtraction : Evaluates program before (.binary .subtract (read 0) (read 1))
          (.signed .i32 (capacity - cursor)) before := by
        apply evaluatesEagerBinary (by decide) (by decide)
          (local_evaluates program capacityRead) (local_evaluates program cursorRead)
        have wrap := wrapSigned_i32_of_nonnegative program.target (capacity - cursor) (by omega) (by omega)
        simpa only [evalBinaryValue, evalSignedBinary, BEq.rfl, ↓reduceIte] using
          congrArg (fun n => (Except.ok (.signed .i32 n) : Except Lanius.Trap Value)) wrap
      have compared : Evaluates program before
          (.binary .lessEqual (read 2) (.binary .subtract (read 0) (read 1)))
          (.boolean (decide (count ≤ capacity - cursor))) before := by
        apply evaluatesEagerBinary (by decide) (by decide) (local_evaluates program countRead) subtraction
        simp [evalBinaryValue, evalSignedBinary]
      have same : decide (count ≤ capacity - cursor) = reserved capacity cursor count := by
        simp only [reserved]
        apply Bool.eq_iff_iff.mpr
        simp only [decide_eq_true_eq]
        omega
      rw [same] at compared
      exact executesSequence (executesIfFalse guard (executesSkip _ _))
        (executesSequenceReturned (executesReturnValue compared))

def fitsValues (capacity cursor count : Int) : List Value :=
  [.signed .i32 capacity, .signed .i32 cursor, .signed .i32 count]

def fitsBindings (capacity cursor count : Int) : List (VarId × Value) :=
  parameterBindings (fun index : Fin 3 => (fitsValues capacity cursor count).get index)

theorem fits_call (checked : CheckedFits program) (capacity cursor count : Int)
    (wellFormed : StateWellFormed before) (capacityBound : capacity ≤ 2147483647)
    (argumentsResult : ArgumentsEvaluateTo program.core caller arguments (fitsValues capacity cursor count) before) :
    ∃ after, Evaluates program.core caller (.call checked.source.function.id arguments)
        (.boolean (reserved capacity cursor count)) after ∧
      CellEffect CellSet.empty before after ∧ HeapFrame before after := by
  let bindings := fitsBindings capacity cursor count
  let callee := enterCall before bindings
  have locals (index : Fin 3) : callee.local? index.val = some ((fitsValues capacity cursor count).get index) :=
    enterCall_parameterBindings_matches wellFormed index
  have run := fits_body program.core capacity cursor count capacityBound
    (locals ⟨0, by decide⟩) (locals ⟨1, by decide⟩) (locals ⟨2, by decide⟩)
  have called := checked.call wellFormed argumentsResult (bindings := bindings) rfl run
    (CellEffect.refl (writes := CellSet.empty) (enterCall_preserves_wellFormed wellFormed))
  exact ⟨restoreLocals before callee, called.1, called.2,
    HeapFrame.closeCall before bindings (HeapFrame.refl callee)⟩

end Lanius.X86.Buffer
