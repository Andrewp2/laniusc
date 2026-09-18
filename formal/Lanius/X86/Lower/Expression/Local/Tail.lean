import Lanius.X86.Lower.Expression.Local.Binding
import Lanius.X86.Lower.Value.Get

namespace Lanius.X86.Lower.Expression.Local

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView.Core Lanius.X86.Source Lanius.X86.Buffer

/-- Initialized i32 and pointer locals skip both exceptional local handling and aggregate
snapshotting. The actual getter emits their RBP-relative load, then the real
aggregate predicate is evaluated and the source kind is returned. -/
theorem tail {literal : Source.Expression.Literal.Checked emitters} (checked : Source.Expression.Local.Checked literal) (width : Register.Width)
    (slot capacity start : Nat)
    (ready : Literal.Ready before bindings frontier input output work transport values workspace)
    (workLocal : before.local? 2 = some (.slice i32 work [] 0 workspace.length))
    (outputLocal : before.local? 3 = some (.slice i32 output [] 0 values.length))
    (capacityLocal : before.local? 4 = some (.signed .i32 capacity))
    (kindLocal : before.local? 16 = some (.signed .i32 (Value.Get.kind width)))
    (slotLocal : before.local? 17 = some (.signed .i32 slot))
    (cursor : workspace[1]? = some (start : Int)) (slotBound : slot ≤ 1048576)
    (room : start + (Value.Get.bytes width slot).length ≤ capacity) (storage : capacity ≤ values.length) (bounded : capacity ≤ 2147483647) :
    ∃ after emitted, Executes emitters.pack.program.core before
        (Source.Expression.Local.tail literal.layout.aggregate.source.function.id checked.get.internal.source.function.id
          checked.negativeBranch checked.aggregateBranch) (.returned (some (.signed .i32 (Value.Get.kind width)))) after ∧
      after.cellEntry? output = some { id := output, value := some (.array (signedI32Values emitted)) } ∧
      after.cellEntry? work = some { id := work, value := some (.array (signedI32Values (workspace.set 1 (start + (Value.Get.bytes width slot).length : Nat)))) } ∧
      Emission values start (Value.Get.bytes width slot) emitted ∧
      CellEffect (Literal.writes output work) before after ∧ HeapFrame before after := by
  have guard : Evaluates emitters.pack.program.core before Source.Expression.Local.negativeKind (.boolean false) before :=
    evaluatesEagerBinary (by decide) (by decide) (local_evaluates _ kindLocal)
      (show Evaluates emitters.pack.program.core before (number 0) (.signed .i32 0) before from ⟨1, rfl⟩) (by cases width <;> rfl)
  have arguments : ArgumentsEvaluateTo emitters.pack.program.core before Source.Expression.Local.getArguments
      (Value.Get.inputValues width (.slice i32 output [] 0 values.length) capacity (.slice i32 work [] 0 workspace.length) slot) before :=
    .cons (local_evaluates _ outputLocal) (.cons (local_evaluates _ capacityLocal)
      (.cons (local_evaluates _ workLocal) (.cons (local_evaluates _ slotLocal) (.cons (local_evaluates _ kindLocal) (.nil _ _)))))
  obtain ⟨loaded, emitted, loadRun, loadedOutput, loadedWork, bytes, _, outputLength, outputFrame, loadEffect, loadHeap⟩ :=
    Value.Get.emits checked.get width slot capacity start ready.wellFormed slotBound ready.outputWork ready.outputBacking
      ready.workBacking cursor room storage bounded arguments
  have loadedKind := keeps_scalar ready loadEffect kindLocal
  obtain ⟨classified, classification, classEffect, classHeap⟩ := Literal.Layout.aggregate literal.layout (Value.Get.kind width) loadEffect.wellFormed
    (.cons (local_evaluates _ loadedKind) (.nil _ _))
  simp only [Value.Get.kind_not_aggregate] at classification
  have returnedKind := classEffect.empty_preserves_local loadEffect.wellFormed loadedKind
  exact ⟨classified, emitted,
    executesSequence (executesIfFalse guard (executesSkip _ _))
      (executesSequence (executesExpression loadRun)
        (executesSequence (executesIfFalse classification (executesSkip _ _))
          (executesSequenceReturned (executesReturnValue (local_evaluates _ returnedKind))))),
    classEffect.empty_preserves_entry loadEffect.wellFormed loadedOutput,
    classEffect.empty_preserves_entry loadEffect.wellFormed loadedWork, ⟨outputLength, bytes, outputFrame⟩,
    loadEffect.trans (classEffect.weaken CellSet.empty_subset), loadHeap.trans classHeap⟩

end Lanius.X86.Lower.Expression.Local
