import Lanius.X86.Source.Expression.Literal
import Lanius.X86.Buffer.Reservation
import Lanius.Automation.Execute

namespace Lanius.X86.Lower.Expression.Literal.Layout

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView.Core Lanius.X86.Source Lanius.X86.Buffer

/-- Both i32 and Boolean values take the real helper's 32-bit branch. -/
theorem width32_body (checked : Source.Expression.Literal.Layout program) {kind : Int}
    (narrow : kind = 1 ∨ kind = 2) (kindRead : before.local? 0 = some (.signed .i32 kind)) :
    Executes program.core before (Source.Expression.Literal.widthBody checked.signed.id checked.boolean.id)
      (.returned (some (.signed .i32 32))) before := by
  have signed := checked.signed.evaluates (before := before)
  have boolean := checked.boolean.evaluates (before := before)
  rw [checked.values.1] at signed
  rw [checked.values.2.1] at boolean
  rcases narrow with rfl | rfl <;> core_exec [Source.Expression.Literal.widthBody, Source.Expression.Literal.widthGuard]

/-- The source-linked width call preserves caller storage for either kind. -/
theorem width32 (checked : Source.Expression.Literal.Layout program) {kind : Int}
    (narrow : kind = 1 ∨ kind = 2) (wellFormed : StateWellFormed before)
    (argumentsResult : ArgumentsEvaluateTo program.core caller arguments [.signed .i32 kind] before) :
    ∃ after, Evaluates program.core caller (.call checked.width.source.function.id arguments)
        (.signed .i32 32) after ∧
      CellEffect CellSet.empty before after ∧ HeapFrame before after := by
  let params := parameterBindings (fun _ : Fin 1 => Value.signed .i32 kind)
  have enteredWF := enterCall_preserves_wellFormed wellFormed (bindings := params)
  have kindRead : (enterCall before params).local? 0 = some (.signed .i32 kind) :=
    enterCall_parameterBindings_matches wellFormed ⟨0, by decide⟩
  have run := width32_body checked narrow kindRead
  have called := checked.width.call wellFormed argumentsResult (bindings := params) rfl run
    (CellEffect.refl (writes := CellSet.empty) enteredWF)
  exact ⟨restoreLocals before (enterCall before params), called.1, called.2,
    HeapFrame.closeCall before params (HeapFrame.refl _)⟩

/-- Pointer kind 4 takes the actual width function's 64-bit fallthrough. -/
theorem width64_body (checked : Source.Expression.Literal.Layout program)
    (kindRead : before.local? 0 = some (.signed .i32 4)) :
    Executes program.core before (Source.Expression.Literal.widthBody checked.signed.id checked.boolean.id)
      (.returned (some (.signed .i32 64))) before := by
  have signedLiteral := checked.signed.evaluates (before := before)
  have booleanLiteral := checked.boolean.evaluates (before := before)
  rw [checked.values.1] at signedLiteral
  rw [checked.values.2.1] at booleanLiteral
  have signedTest : Evaluates program.core before (.binary .equal (read 0) (.constant checked.signed.id))
      (.boolean false) before :=
    evaluatesEagerBinary (by decide) (by decide) (local_evaluates _ kindRead) signedLiteral rfl
  have booleanTest : Evaluates program.core before (.binary .equal (read 0) (.constant checked.boolean.id))
      (.boolean false) before :=
    evaluatesEagerBinary (by decide) (by decide) (local_evaluates _ kindRead) booleanLiteral rfl
  exact executesSequence (executesIfFalse (evaluatesPureLogicalOr signedTest booleanTest) (executesSkip _ _))
    (executesSequenceReturned (executesReturnValue
      (show Evaluates program.core before (number 64) (.signed .i32 64) before from ⟨1, rfl⟩)))

theorem width64 (checked : Source.Expression.Literal.Layout program)
    (wellFormed : StateWellFormed before)
    (argumentsResult : ArgumentsEvaluateTo program.core caller arguments [.signed .i32 4] before) :
    ∃ after, Evaluates program.core caller (.call checked.width.source.function.id arguments)
        (.signed .i32 64) after ∧
      CellEffect CellSet.empty before after ∧ HeapFrame before after := by
  let params := parameterBindings (fun _ : Fin 1 => Value.signed .i32 4)
  have enteredWF := enterCall_preserves_wellFormed wellFormed (bindings := params)
  have kindRead : (enterCall before params).local? 0 = some (.signed .i32 4) :=
    enterCall_parameterBindings_matches wellFormed ⟨0, by decide⟩
  have run := width64_body checked kindRead
  have called := checked.width.call wellFormed argumentsResult (bindings := params) rfl run
    (CellEffect.refl (writes := CellSet.empty) enteredWF)
  exact ⟨restoreLocals before (enterCall before params), called.1, called.2,
    HeapFrame.closeCall before params (HeapFrame.refl _)⟩

/-- The actual aggregate classifier: slices, strings and record kinds retain
their allocated frame storage; scalar kinds do not. -/
def aggregateKind (kind : Int) : Bool :=
  (decide (kind = 6) || decide (kind = 5)) || decide (16 ≤ kind)

/-- All type constants and all three comparisons come from the authenticated
layout function. This handles pointer, slice and error results as well as i32. -/
theorem aggregate_body (checked : Source.Expression.Literal.Layout program) (kind : Int)
    (kindRead : before.local? 0 = some (.signed .i32 kind)) :
    Executes program.core before
      (Source.Expression.Literal.aggregateBody checked.slice.id checked.string.id checked.record.id)
      (.returned (some (.boolean (aggregateKind kind)))) before := by
  have sliceLiteral := checked.slice.evaluates (before := before)
  have stringLiteral := checked.string.evaluates (before := before)
  have recordLiteral := checked.record.evaluates (before := before)
  rw [checked.values.2.2.1] at sliceLiteral
  rw [checked.values.2.2.2.1] at stringLiteral
  rw [checked.values.2.2.2.2] at recordLiteral
  have sliceTest : Evaluates program.core before (.binary .equal (read 0) (.constant checked.slice.id))
      (.boolean (decide (kind = 6))) before := by
    apply evaluatesEagerBinary (by decide) (by decide) (local_evaluates _ kindRead) sliceLiteral
    rfl
  have stringTest : Evaluates program.core before (.binary .equal (read 0) (.constant checked.string.id))
      (.boolean (decide (kind = 5))) before := by
    apply evaluatesEagerBinary (by decide) (by decide) (local_evaluates _ kindRead) stringLiteral
    rfl
  have recordTest : Evaluates program.core before (.binary .greaterEqual (read 0) (.constant checked.record.id))
      (.boolean (decide (16 ≤ kind))) before := by
    apply evaluatesEagerBinary (by decide) (by decide) (local_evaluates _ kindRead) recordLiteral
    rfl
  exact executesSequenceReturned (executesReturnValue
    (evaluatesPureLogicalOr (evaluatesPureLogicalOr sliceTest stringTest) recordTest))

/-- Full source-linked aggregate call, including fresh call parameters and
caller restoration. No classifier execution is left as a caller premise. -/
theorem aggregate (checked : Source.Expression.Literal.Layout program) (kind : Int)
    (wellFormed : StateWellFormed before)
    (argumentsResult : ArgumentsEvaluateTo program.core caller arguments [.signed .i32 kind] before) :
    ∃ after, Evaluates program.core caller (.call checked.aggregate.source.function.id arguments)
        (.boolean (aggregateKind kind)) after ∧
      CellEffect CellSet.empty before after ∧ HeapFrame before after := by
  let params := parameterBindings (fun _ : Fin 1 => Value.signed .i32 kind)
  have enteredWF := enterCall_preserves_wellFormed wellFormed (bindings := params)
  have kindRead : (enterCall before params).local? 0 = some (.signed .i32 kind) :=
    enterCall_parameterBindings_matches wellFormed ⟨0, by decide⟩
  have run := aggregate_body checked kind kindRead
  have called := checked.aggregate.call wellFormed argumentsResult (bindings := params) rfl run
    (CellEffect.refl (writes := CellSet.empty) enteredWF)
  exact ⟨restoreLocals before (enterCall before params), called.1, called.2,
    HeapFrame.closeCall before params (HeapFrame.refl _)⟩

end Lanius.X86.Lower.Expression.Literal.Layout
