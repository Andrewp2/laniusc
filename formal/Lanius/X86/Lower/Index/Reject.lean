import Lanius.X86.Source.Index
import Lanius.X86.Buffer.Reservation

namespace Lanius.X86.Lower.Index.Reject

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView.Core Lanius.X86.Source Lanius.X86.Buffer

/-- Invalid index kinds return before any cursor, output, workspace, or
descriptor access. This is the whole authenticated address-helper body. -/
theorem body (checked : Source.Index.Checked emitters) (kind : Int)
    (kindRead : before.local? 4 = some (.signed .i32 kind))
    (notSigned : kind ≠ 1) (notUnsigned : kind ≠ 3) :
    Executes emitters.pack.program.core before (Source.Index.body checked.constants checked.helpers.calls)
      (.returned (some (.signed .i32 (-1)))) before := by
  have signedLiteral := checked.constants.signed.evaluates (before := before)
  have unsignedLiteral := checked.constants.unsigned.evaluates (before := before)
  rw [checked.constants.values.2.1] at signedLiteral
  rw [checked.constants.values.2.2.1] at unsignedLiteral
  have left : Evaluates emitters.pack.program.core before
      (.binary .notEqual (read 4) (.constant checked.constants.signed.id)) (.boolean true) before := by
    apply evaluatesEagerBinary (by decide) (by decide) (local_evaluates _ kindRead) signedLiteral
    simp [evalBinaryValue, scalarEqual, notSigned]
  have right : Evaluates emitters.pack.program.core before
      (.binary .notEqual (read 4) (.constant checked.constants.unsigned.id)) (.boolean true) before := by
    apply evaluatesEagerBinary (by decide) (by decide) (local_evaluates _ kindRead) unsignedLiteral
    simp [evalBinaryValue, scalarEqual, notUnsigned]
  have guard := evaluatesPureLogicalAnd left right
  have negative : Evaluates emitters.pack.program.core before negativeOne (.signed .i32 (-1)) before := by
    apply evaluatesUnary (show Evaluates emitters.pack.program.core before (number 1) (.signed .i32 1) before from ⟨1, rfl⟩)
    simp [evalUnaryValue, wrapSigned_i32_neg_one]
  exact executesSequenceReturned (executesIfTrue guard
    (executesSequenceReturned (executesReturnValue negative)))

def inputValues (output capacity work slot : Value) (kind : Int) : List Value :=
  [output, capacity, work, slot, .signed .i32 kind]

/-- Whole-call invalid-kind rejection. None of the four untouched arguments
needs a validity premise; parameter cells are fresh and caller state is
preserved outside those administrative cells. -/
theorem rejects (checked : Source.Index.Checked emitters) (kind : Int)
    (wellFormed : StateWellFormed before) (notSigned : kind ≠ 1) (notUnsigned : kind ≠ 3)
    (argumentsResult : ArgumentsEvaluateTo emitters.pack.program.core caller arguments
      (inputValues output capacity work slot kind) before) :
    ∃ after, Evaluates emitters.pack.program.core caller (.call checked.internal.source.function.id arguments)
        (.signed .i32 (-1)) after ∧
      CellEffect CellSet.empty before after ∧ HeapFrame before after := by
  let params := parameterBindings (fun index : Fin 5 => (inputValues output capacity work slot kind).get index)
  have enteredWF := enterCall_preserves_wellFormed wellFormed (bindings := params)
  have kindRead : (enterCall before params).local? 4 = some (.signed .i32 kind) :=
    enterCall_parameterBindings_matches wellFormed ⟨4, by decide⟩
  have run := body checked kind kindRead notSigned notUnsigned
  have called := checked.internal.call wellFormed argumentsResult (bindings := params) rfl run
    (CellEffect.refl (writes := CellSet.empty) enteredWF)
  exact ⟨restoreLocals before (enterCall before params), called.1, called.2,
    HeapFrame.closeCall before params (HeapFrame.refl _)⟩

end Lanius.X86.Lower.Index.Reject
