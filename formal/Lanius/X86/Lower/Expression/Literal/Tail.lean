import Lanius.X86.Lower.Expression.Literal.State
import Lanius.X86.Lower.Expression.Literal.Layout
import Lanius.X86.Encode.Immediate

namespace Lanius.X86.Lower.Expression.Literal

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView.Core Lanius.X86.Source Lanius.X86.Buffer

/-- The literal's actual immediate call and CODE assignment. Width is proved
by the real layout helper; the emitted word is the transport value captured
before any emitter call. -/
theorem emit (checked : Source.Expression.Literal.Checked emitters) {kind : Int}
    (capacity start : Nat) (low : Int) (narrow : kind = 1 ∨ kind = 2)
    (ready : Ready before bindings frontier input output work transport values workspace)
    (workValue : bindings[2]? = some (.slice i32 work [] 0 workspace.length))
    (outputValue : bindings[3]? = some (.slice i32 output [] 0 values.length))
    (capacityValue : bindings[4]? = some (.signed .i32 capacity))
    (kindValue : bindings[10]? = some (.signed .i32 kind))
    (lowValue : bindings[11]? = some (.signed .i32 low))
    (highRead : before.local? 13 = some (.signed .i32 0))
    (cursor : workspace[1]? = some (start : Int))
    (room : start + 5 ≤ capacity) (storage : capacity ≤ values.length) (bounded : capacity ≤ 2147483647) :
    ∃ after, Executes emitters.pack.program.core before
        (.sequence (Source.Expression.Literal.assign checked.constants.code.id
          (.call checked.immediate.source.function.id [read 3, read 4, Source.Expression.Literal.field checked.constants.code.id,
            .call checked.layout.width.source.function.id [read 10], .constant checked.constants.rax.id, read 11, read 13]))
          (returned (read 10))) (.returned (some (.signed .i32 kind))) after ∧
      after.cellEntry? output = some { id := output, value := some (.array
        (signedI32Values (Encode.Immediate.written values start low))) } ∧
      after.cellEntry? work = some { id := work, value := some (.array
        (signedI32Values (workspace.set 1 (start + 5 : Nat)))) } ∧
      CellEffect (writes output work) before after ∧ HeapFrame before after := by
  have codeRead := ready.field checked.constants.code 1 checked.constants.values.2.2.1
    (ready.read 2 workValue) cursor
  obtain ⟨widthState, widthRun, widthEffect, widthHeap⟩ := Layout.width32 checked.layout narrow ready.wellFormed
    (.cons (local_evaluates _ (ready.read 10 kindValue)) (.nil _ _))
  have widthReady := ready.empty widthEffect
  have rax := checked.constants.rax.evaluates (before := widthState)
  rw [checked.constants.values.2.2.2.2.2.1] at rax
  have highAfter := widthEffect.preserves_local ready.wellFormed highRead (by simp [CellSet.empty])
  have arguments : ArgumentsEvaluateTo emitters.pack.program.core before
      [read 3, read 4, Source.Expression.Literal.field checked.constants.code.id,
        .call checked.layout.width.source.function.id [read 10], .constant checked.constants.rax.id, read 11, read 13]
      (Encode.Immediate.inputs (.slice i32 output [] 0 values.length) capacity start low 0) widthState :=
    .cons (local_evaluates _ (ready.read 3 outputValue)) (.cons (local_evaluates _ (ready.read 4 capacityValue))
      (.cons codeRead (.cons widthRun (.cons rax (.cons (local_evaluates _ (widthReady.read 11 lowValue))
        (.cons (local_evaluates _ highAfter) (.nil _ _)))))))
  obtain ⟨written, rhs, outputContents, outputEffect, outputHeap⟩ := Encode.Immediate.succeeds32
    checked.immediate capacity start low 0 widthEffect.wellFormed room storage bounded widthReady.outputBacking arguments
  have rhsEffect := (widthEffect.weaken (larger := CellSet.singleton output) CellSet.empty_subset).trans outputEffect
  have within : 1 < workspace.length := by
    by_cases inside : 1 < workspace.length
    · exact inside
    · rw [List.getElem?_eq_none (by omega)] at cursor
      cases cursor
  have code := checked.constants.code.evaluates (before := before)
  rw [checked.constants.values.2.2.1] at code
  obtain ⟨after, update, workContents, effect, storeHeap, storeEffect⟩ := evaluatesFramedSliceStore
    emitters.pack.program.core before written workspace 2 (.constant checked.constants.code.id)
      (.call checked.immediate.source.function.id [read 3, read 4, Source.Expression.Literal.field checked.constants.code.id,
        .call checked.layout.width.source.function.id [read 10], .constant checked.constants.rax.id, read 11, read 13])
      work 1 (start + 5 : Nat) ready.wellFormed within (ready.read 2 workValue) code rhs rhsEffect
      (Ne.symm ready.outputWork) ready.workBacking
  have finalOutput := storeEffect.preserves_entry rhsEffect.wellFormed outputContents ready.outputWork
  have finalReady := ready.frame effect finalOutput workContents
  exact ⟨after, executesSequence (executesExpression update)
    (executesSequenceReturned (executesReturnValue (local_evaluates _ (finalReady.read 10 kindValue)))),
    finalOutput, workContents, effect, widthHeap.trans (outputHeap.trans storeHeap)⟩

/-- A 32-bit scalar literal never reads a high transport word. The real width
test skips that branch, emits MOV EAX, imm32, and closes the local13 scope. -/
theorem tail (checked : Source.Expression.Literal.Checked emitters) {kind : Int}
    (capacity start : Nat) (low : Int) (narrow : kind = 1 ∨ kind = 2)
    (ready : Ready before bindings frontier input output work transport values workspace)
    (fresh : bindings.length ≤ 13)
    (workValue : bindings[2]? = some (.slice i32 work [] 0 workspace.length))
    (outputValue : bindings[3]? = some (.slice i32 output [] 0 values.length))
    (capacityValue : bindings[4]? = some (.signed .i32 capacity))
    (kindValue : bindings[10]? = some (.signed .i32 kind))
    (lowValue : bindings[11]? = some (.signed .i32 low))
    (cursor : workspace[1]? = some (start : Int))
    (room : start + 5 ≤ capacity) (storage : capacity ≤ values.length) (bounded : capacity ≤ 2147483647) :
    ∃ after, Executes emitters.pack.program.core before
        (Source.Expression.Literal.literalTail checked.layout checked.constants
          checked.take.internal.source.function.id checked.immediate.source.function.id)
        (.returned (some (.signed .i32 kind))) after ∧
      after.cellEntry? output = some { id := output, value := some (.array
        (signedI32Values (Encode.Immediate.written values start low))) } ∧
      after.cellEntry? work = some { id := work, value := some (.array
        (signedI32Values (workspace.set 1 (start + 5 : Nat)))) } ∧
      CellEffect (writes output work) before after ∧ HeapFrame before after := by
  have enteredReady := ready.bind 13 fresh (.signed .i32 0)
  have high := bindLocal_finds_local before 13 (.signed .i32 0) ready.wellFormed
  obtain ⟨guarded, widthRun, widthEffect, widthHeap⟩ := Layout.width32 checked.layout narrow enteredReady.wellFormed
    (.cons (local_evaluates _ (enteredReady.read 10 kindValue)) (.nil _ _))
  have guard : Evaluates emitters.pack.program.core (before.bindLocal 13 (.signed .i32 0))
      (.binary .equal (.call checked.layout.width.source.function.id [read 10]) (number 64)) (.boolean false) guarded := by
    apply evaluatesEagerBinary (by decide) (by decide) widthRun
      (show Evaluates emitters.pack.program.core guarded (number 64) (.signed .i32 64) guarded from ⟨1, rfl⟩)
    rfl
  obtain ⟨completed, run, outputContents, workContents, effect, heap⟩ := emit checked capacity start low narrow
    (enteredReady.empty widthEffect) workValue outputValue capacityValue kindValue lowValue
    (widthEffect.preserves_local enteredReady.wellFormed high (by simp [CellSet.empty])) cursor room storage bounded
  exact ⟨restoreLocals before completed,
    executesLetLocal (show Evaluates emitters.pack.program.core before (number 0) (.signed .i32 0) before from ⟨1, rfl⟩)
      (executesSequence (executesIfFalse guard (executesSkip _ _)) run), outputContents, workContents,
    CellEffect.closeLocal before 13 (.signed .i32 0) ready.wellFormed
      ((widthEffect.weaken CellSet.empty_subset).trans effect),
    HeapFrame.closeLocal before 13 (.signed .i32 0) (widthHeap.trans heap)⟩

end Lanius.X86.Lower.Expression.Literal
