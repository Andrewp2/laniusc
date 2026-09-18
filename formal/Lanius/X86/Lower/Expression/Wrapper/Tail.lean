import Lanius.X86.Lower.Expression.Literal.State
import Lanius.X86.Lower.Expression.Literal.Layout

namespace Lanius.X86.Lower.Expression.Wrapper

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView.Core Lanius.X86.Source Lanius.X86.Buffer
open Literal

/-- Only aggregate results retain the emitter's final TOP. Scalars restore
the caller's captured TOP, including pointers and negative error results. -/
def finish (kind top : Int) (workspace : List Int) : List Int :=
  if Literal.Layout.aggregateKind kind then workspace else workspace.set 6 top

/-- Restoring an already retained TOP is a no-op, for every result kind. -/
theorem finish_eq (found : workspace[6]? = some top) : finish kind top workspace = workspace := by
  obtain ⟨inside, rfl⟩ := List.getElem?_eq_some_iff.mp found
  simp [finish]

/-- Execute the actual wrapper classification and conditional TOP store.
One rule covers every result kind; the aggregate branch performs no store. -/
theorem tail (checked : Source.Expression.Literal.Checked emitters)
    (ready : Ready before bindings frontier input output work transport emitted workspace)
    (kind top : Int) (within : 6 < workspace.length)
    (workLocal : before.local? 2 = some (.slice i32 work [] 0 workspace.length))
    (topLocal : before.local? 9 = some (.signed .i32 top))
    (kindLocal : before.local? 10 = some (.signed .i32 kind)) :
    ∃ after, Executes emitters.pack.program.core before
        (.sequence (.ifThenElse (.unary .logicalNot (.call checked.layout.aggregate.source.function.id [read 10]))
          (.sequence (Source.Expression.Literal.assign checked.constants.top.id (read 9)) .skip) .skip)
          (returned (read 10))) (.returned (some (.signed .i32 kind))) after ∧
      after.cellEntry? output = some { id := output, value := some (.array (signedI32Values emitted)) } ∧
      after.cellEntry? work = some { id := work, value := some (.array (signedI32Values (finish kind top workspace))) } ∧
      CellEffect (writes output work) before after ∧ HeapFrame before after := by
  obtain ⟨classified, classify, classifyEffect, classifyHeap⟩ := Literal.Layout.aggregate checked.layout kind ready.wellFormed
    (.cons (local_evaluates _ kindLocal) (.nil _ _))
  have guard := evaluatesUnary classify
    (show evalUnaryValue emitters.pack.program.core.target .logicalNot (.boolean (Literal.Layout.aggregateKind kind)) =
      .ok (.boolean (!(Literal.Layout.aggregateKind kind))) from rfl)
  have classifiedReady := ready.empty classifyEffect
  have classifiedWork := classifyEffect.empty_preserves_local ready.wellFormed workLocal
  have classifiedTop := classifyEffect.empty_preserves_local ready.wellFormed topLocal
  have classifiedKind := classifyEffect.empty_preserves_local ready.wellFormed kindLocal
  cases aggregate : Literal.Layout.aggregateKind kind with
  | true =>
      refine ⟨classified, executesSequence (executesIfFalse (by simpa only [aggregate, Bool.not_true] using guard)
        (executesSkip _ _)) (executesSequenceReturned (executesReturnValue (local_evaluates _ classifiedKind))),
        classifiedReady.outputBacking, ?_, classifyEffect.weaken CellSet.empty_subset, classifyHeap⟩
      simpa only [finish, aggregate, ↓reduceIte] using classifiedReady.workBacking
  | false =>
      have topConstant := checked.constants.top.evaluates (before := classified)
      rw [checked.constants.values.2.2.2.2.2.2] at topConstant
      obtain ⟨after, update, workContents, _, storeHeap, storeEffect⟩ := evaluatesFramedSliceStore emitters.pack.program.core
        classified classified workspace 2 (.constant checked.constants.top.id) (read 9) work 6 top
        classifiedReady.wellFormed within classifiedWork topConstant (local_evaluates _ classifiedTop)
        (CellEffect.refl (writes := CellSet.empty) classifiedReady.wellFormed) (by simp [CellSet.empty]) classifiedReady.workBacking
      have finalOutput := storeEffect.preserves_entry classifiedReady.wellFormed classifiedReady.outputBacking ready.outputWork
      have finalKind := storeEffect.preserves_local_of_distinct_value classifiedReady.wellFormed classifiedKind
        classifiedReady.workBacking (by intro same; cases same)
      refine ⟨after, executesSequence (executesIfTrue (by simpa only [aggregate, Bool.not_false] using guard)
        (executesSequence (executesExpression update) (executesSkip _ _)))
        (executesSequenceReturned (executesReturnValue (local_evaluates _ finalKind))), finalOutput, ?_,
        (classifyEffect.weaken CellSet.empty_subset).trans (storeEffect.weaken CellSet.subset_union_right),
        classifyHeap.trans storeHeap⟩
      simpa only [finish, aggregate, Bool.false_eq_true, ↓reduceIte] using workContents

end Lanius.X86.Lower.Expression.Wrapper
