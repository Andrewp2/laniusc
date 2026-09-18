import Lanius.X86.Source.Expression.Raw
import Lanius.X86.Lower.Expression.Literal.State
import Lanius.X86.Frame.Allocate
import Lanius.X86.Frame.Slot

namespace Lanius.X86.Lower.Expression.Raw

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView.Core Lanius.X86.Source Lanius.X86.Buffer

/-- A two-word allocation returns its upper slot, where the descriptor pointer
is stored. The adjacent lower slot is reserved for the eventual length. -/
def saveBytes (top : Nat) : List UInt8 := Frame.Slot.bytes .save64 (top + 1) 0
def workspaceAfter (workspace : List Int) (top peak cursor : Nat) : List Int :=
  (Frame.Allocate.updated workspace top peak 2).set 1 cursor

structure Prepared (state : State) (bindings : List Value)
    (frontier input output work slot top peak cursor : Nat)
    (transport values workspace emitted : List Int) : Prop where
  ready : Literal.Ready state bindings frontier input output work transport emitted
    (workspaceAfter workspace top peak (cursor + (saveBytes top).length))
  saved : state.local? slot = some (.signed .i32 (top + 1 : Nat))
  window : Emission values cursor (saveBytes top) emitted

theorem workspaceAfter_top {top peak cursor : Nat} (within : 6 < workspace.length) :
    (workspaceAfter workspace top peak cursor)[6]? = some ((top + 2 : Nat) : Int) := by
  simp only [workspaceAfter, List.getElem?_set_ne (by decide : 1 ≠ 6)]
  exact Frame.Allocate.updated_top within

theorem workspaceAfter_peak {top peak cursor : Nat} (within : 6 < workspace.length)
    (watermark : workspace[2]? = some (peak : Int)) :
    (workspaceAfter workspace top peak cursor)[2]? = some ((max peak (top + 2) : Nat) : Int) := by
  simp only [workspaceAfter, List.getElem?_set_ne (by decide : 1 ≠ 2)]
  exact Frame.Allocate.updated_peak within watermark

theorem workspaceAfter_cursor {top peak cursor : Nat} (within : 6 < workspace.length) :
    (workspaceAfter workspace top peak cursor)[1]? = some (cursor : Int) := by
  apply List.getElem?_set_self
  simpa only [Frame.Allocate.updated_length] using (show 1 < workspace.length by omega)

/-- The explicit recursive-operand induction obligation. It describes only
the actual recursive call; allocation and pointer saving are proved below. -/
structure OperandCall {literal : Source.Expression.Literal.Checked emitters}
    (checked : Source.Expression.Raw.Checked literal) (kind : Int)
    (before after : State) (output work cursor oldWorkLength : Nat)
    (original emitted workspace : List Int) (code : List UInt8) : Prop where
  run : Evaluates emitters.pack.program.core before
    (.call literal.wrapper.source.function.id Source.Expression.Raw.recurseArguments)
    (.signed .i32 kind) after
  outputBacking : after.cellEntry? output = some { id := output, value := some (.array (signedI32Values emitted)) }
  workBacking : after.cellEntry? work = some { id := work, value := some (.array (signedI32Values workspace)) }
  workspaceLength : workspace.length = oldWorkLength
  current : workspace[1]? = some ((cursor + code.length : Nat) : Int)
  window : Emission original cursor code emitted
  effect : CellEffect (Literal.writes output work) before after
  heap : HeapFrame before after

/-- Execute the real allocator and save-word calls after the pointer child.
The returned slot, rejected=false guard, TOP/peak updates and emitted bytes
are all derived. No native backing-allocation or nonnegative length premise
is needed at this stage of the compiler. -/
theorem allocate_save {literal : Source.Expression.Literal.Checked emitters}
    (checked : Source.Expression.Raw.Checked literal)
    (ready : Literal.Ready before bindings frontier input output work transport values workspace)
    (top peak capacity cursor : Nat)
    (inputPrefix : 5 ≤ bindings.length) (fresh : bindings.length ≤ checked.locals.slot)
    (workLocal : before.local? 2 = some (.slice i32 work [] 0 workspace.length))
    (outputLocal : before.local? 3 = some (.slice i32 output [] 0 values.length))
    (capacityLocal : before.local? 4 = some (.signed .i32 capacity))
    (within : 6 < workspace.length) (current : workspace[6]? = some (top : Int))
    (watermark : workspace[2]? = some (peak : Int)) (position : workspace[1]? = some (cursor : Int))
    (ordered : top ≤ peak) (peakBound : peak ≤ Frame.Allocate.limit)
    (slotRoom : top + 2 ≤ Frame.Allocate.limit)
    (room : cursor + (saveBytes top).length ≤ capacity)
    (storage : capacity ≤ values.length) (bounded : capacity ≤ 2147483647) :
    ∃ allocated prepared emitted,
      Evaluates emitters.pack.program.core before
        (.call checked.helpers.allocate.internal.source.function.id [read 2, number 2])
        (.signed .i32 (top + 1 : Nat)) allocated ∧
      Evaluates emitters.pack.program.core (allocated.bindLocal checked.locals.slot (.signed .i32 (top + 1 : Nat)))
        (Source.Expression.Raw.rejected checked.locals) (.boolean false)
        (allocated.bindLocal checked.locals.slot (.signed .i32 (top + 1 : Nat))) ∧
      Executes emitters.pack.program.core (allocated.bindLocal checked.locals.slot (.signed .i32 (top + 1 : Nat)))
        (.expression (.call checked.helpers.save.internal.source.function.id
          (Source.Expression.Raw.saveArguments literal checked.locals))) .next prepared ∧
      Prepared prepared bindings frontier input output work checked.locals.slot top peak cursor transport values workspace emitted ∧
      CellEffect (Literal.writes output work) before allocated ∧ HeapFrame before allocated ∧
      CellEffect (Literal.writes output work) (allocated.bindLocal checked.locals.slot (.signed .i32 (top + 1 : Nat))) prepared ∧
      HeapFrame (allocated.bindLocal checked.locals.slot (.signed .i32 (top + 1 : Nat))) prepared := by
  have workEntry := ready.entry 2 (by omega) workLocal
  have outputEntry := ready.entry 3 (by omega) outputLocal
  have capacityEntry := ready.entry 4 (by omega) capacityLocal
  have args : ArgumentsEvaluateTo emitters.pack.program.core before [read 2, number 2]
      (Frame.Allocate.inputValues work workspace.length 2) before :=
    .cons (local_evaluates _ workLocal) (.cons ⟨1, rfl⟩ (.nil _ _))
  obtain ⟨allocated, allocateRun, allocatedWork, allocationEffect, allocationHeap⟩ :=
    Frame.Allocate.succeeds checked.helpers.allocate top peak 2 ready.wellFormed ready.workBacking within current watermark
      ordered peakBound (by decide) slotRoom args
  have returnedSlot : top + 2 - 1 = top + 1 := by omega
  rw [returnedSlot] at allocateRun
  have allocationWrites := allocationEffect.weaken (larger := Literal.writes output work) CellSet.subset_union_right
  have allocatedReady := ready.frame allocationWrites
    (allocationEffect.preserves_entry ready.wellFormed ready.outputBacking ready.outputWork) allocatedWork
  let entered := allocated.bindLocal checked.locals.slot (.signed .i32 (top + 1 : Nat))
  have enteredReady := allocatedReady.bind checked.locals.slot fresh (.signed .i32 (top + 1 : Nat))
  have saved := bindLocal_finds_local allocated checked.locals.slot (.signed .i32 (top + 1 : Nat)) allocatedReady.wellFormed
  have guard : Evaluates emitters.pack.program.core entered (Source.Expression.Raw.rejected checked.locals)
      (.boolean false) entered := by
    apply evaluatesEagerBinary (by decide) (by decide) (local_evaluates _ saved)
      (show Evaluates emitters.pack.program.core entered (number 0) (.signed .i32 0) entered from ⟨1, rfl⟩)
    simp [evalBinaryValue, evalSignedBinary]
    omega
  have rax := literal.constants.rax.evaluates (before := entered)
  rw [literal.constants.values.2.2.2.2.2.1] at rax
  have saveArgs : ArgumentsEvaluateTo emitters.pack.program.core entered
      (Source.Expression.Raw.saveArguments literal checked.locals)
      (Frame.Slot.inputValues (.slice i32 output [] 0 values.length) capacity
        (.slice i32 work [] 0 (Frame.Allocate.updated workspace top peak 2).length) (top + 1) 0) entered := by
    simp only [Frame.Allocate.updated_length]
    exact .cons (local_evaluates _ (enteredReady.read 3 outputEntry))
      (.cons (local_evaluates _ (enteredReady.read 4 capacityEntry))
        (.cons (local_evaluates _ (enteredReady.read 2 workEntry)) (.cons (local_evaluates _ saved) (.cons rax (.nil _ _)))))
  obtain ⟨prepared, emitted, saveRun, finalOutput, finalWork, exactBytes, _, length, frame, saveEffect, saveHeap⟩ :=
    Frame.Slot.emits checked.helpers.save (top + 1) capacity cursor 0 enteredReady.wellFormed
      (by unfold Frame.Allocate.limit at slotRoom; omega) ready.outputWork enteredReady.outputBacking enteredReady.workBacking
      ((Frame.Allocate.updated_frame (values := workspace) (top := top) (peak := peak) (count := 2)
        (by decide : 1 ≠ 6 ∧ 1 ≠ 2)).trans position) room storage bounded saveArgs
  have keptSlot := saveEffect.preserves_local enteredReady.wellFormed saved (by
    intro cell binding changed
    rcases changed with out | work
    · exact local_cell_ne_of_distinct_value saved enteredReady.outputBacking (by intro same; cases same) binding out
    · exact local_cell_ne_of_distinct_value saved enteredReady.workBacking (by intro same; cases same) binding work)
  exact ⟨allocated, prepared, emitted, allocateRun, guard, executesExpression saveRun,
    ⟨enteredReady.frame saveEffect finalOutput finalWork, keptSlot, ⟨length, exactBytes, frame⟩⟩,
    allocationWrites, allocationHeap, saveEffect, saveHeap⟩

/-- Close the actual preparation, including its pointer-kind guard and the
allocated slot's lexical scope, around a proved length/tail continuation.
The continuation receives the original state's storage frame: it is not an
impossible obligation over arbitrary states merely satisfying Prepared. Its
exact final workspace is retained through scope closure for the wrapper proof. -/
theorem prepares {literal : Source.Expression.Literal.Checked emitters}
    (checked : Source.Expression.Raw.Checked literal)
    (ready : Literal.Ready before bindings frontier input output work transport values workspace)
    (top peak capacity start : Nat) (rest : Stmt) (restBytes : List UInt8) (completion : Completion)
    (pointer : OperandCall checked 4 before pointerState output work start workspace.length
      values pointerValues pointerWorkspace pointerBytes)
    (inputPrefix : 5 ≤ bindings.length) (fresh : bindings.length ≤ checked.locals.slot)
    (workLocal : before.local? 2 = some (.slice i32 work [] 0 workspace.length))
    (outputLocal : before.local? 3 = some (.slice i32 output [] 0 values.length))
    (capacityLocal : before.local? 4 = some (.signed .i32 capacity))
    (within : 6 < pointerWorkspace.length) (current : pointerWorkspace[6]? = some (top : Int))
    (watermark : pointerWorkspace[2]? = some (peak : Int))
    (ordered : top ≤ peak) (peakBound : peak ≤ Frame.Allocate.limit)
    (slotRoom : top + 2 ≤ Frame.Allocate.limit)
    (room : start + pointerBytes.length + (saveBytes top).length ≤ capacity)
    (storage : capacity ≤ values.length) (bounded : capacity ≤ 2147483647)
    {finalWorkspace : List Int}
    (continuation : ∀ prepared preparedValues,
      Prepared prepared bindings frontier input output work checked.locals.slot top peak
        (start + pointerBytes.length) transport pointerValues pointerWorkspace preparedValues →
      StoreEffect (Literal.writes output work) before prepared →
      ∃ completed emitted,
        Executes emitters.pack.program.core prepared rest completion completed ∧
        completed.cellEntry? output = some { id := output, value := some (.array (signedI32Values emitted)) } ∧
        completed.cellEntry? work = some { id := work, value := some (.array (signedI32Values finalWorkspace)) } ∧
        Emission preparedValues (start + pointerBytes.length + (saveBytes top).length) restBytes emitted ∧
        CellEffect (Literal.writes output work) prepared completed ∧ HeapFrame prepared completed) :
    ∃ after emitted,
      Executes emitters.pack.program.core before
        (Source.Expression.Raw.preparation literal checked.helpers.calls checked.locals rest) completion after ∧
      after.cellEntry? output = some { id := output, value := some (.array (signedI32Values emitted)) } ∧
      after.cellEntry? work = some { id := work, value := some (.array (signedI32Values finalWorkspace)) } ∧
      Emission values start (pointerBytes ++ saveBytes top ++ restBytes) emitted ∧
      CellEffect (Literal.writes output work) before after ∧ HeapFrame before after := by
  have pointerReady := ready.frame pointer.effect pointer.outputBacking pointer.workBacking
  have workEntry := ready.entry 2 (by omega) workLocal
  have outputEntry := ready.entry 3 (by omega) outputLocal
  have capacityEntry := ready.entry 4 (by omega) capacityLocal
  have pointerWorkLocal : pointerState.local? 2 = some (.slice i32 work [] 0 pointerWorkspace.length) := by
    rw [pointer.workspaceLength]
    exact pointerReady.read 2 workEntry
  have pointerOutputLocal : pointerState.local? 3 = some (.slice i32 output [] 0 pointerValues.length) := by
    rw [pointer.window.length]
    exact pointerReady.read 3 outputEntry
  have pointerConstant := literal.constants.pointer.evaluates (before := pointerState)
  rw [literal.constants.values.2.2.2.2.1] at pointerConstant
  have pointerGuard : Evaluates emitters.pack.program.core before
      (Source.Expression.Raw.pointerGuard literal checked.helpers.calls) (.boolean false) pointerState := by
    apply evaluatesEagerBinary (by decide) (by decide) pointer.run pointerConstant
    simp [evalBinaryValue, scalarEqual]
  obtain ⟨allocated, prepared, preparedValues, allocateRun, guard, saveRun, preparedReady,
      allocationEffect, allocationHeap, saveEffect, saveHeap⟩ :=
    allocate_save checked pointerReady top peak capacity (start + pointerBytes.length) inputPrefix fresh
      pointerWorkLocal pointerOutputLocal (pointerReady.read 4 capacityEntry)
      within current watermark pointer.current ordered peakBound slotRoom room
      (by simpa only [pointer.window.length] using storage) bounded
  have preparedFrame : StoreEffect (Literal.writes output work) before prepared :=
    (pointer.effect.modifiesOnly pointer.heap).toStoreEffect.trans_same
      ((allocationEffect.modifiesOnly allocationHeap).toStoreEffect.trans_same
        (((bindLocal_effect allocated checked.locals.slot (.signed .i32 (top + 1 : Nat))).weaken
          CellSet.empty_subset).trans_same (saveEffect.modifiesOnly saveHeap).toStoreEffect))
  obtain ⟨completed, emitted, restRun, finalOutput, finalWork, restWindow, restEffect, restHeap⟩ :=
    continuation prepared preparedValues preparedReady preparedFrame
  have scopeRun := executesLetLocal (id := checked.locals.slot) (type := i32) allocateRun
    (executesSequence (executesIfFalse (thenBranch := returned negativeOne) guard (executesSkip _ _))
      (executesSequence saveRun restRun))
  have whole := executesSequence
    (executesIfFalse (thenBranch := returned negativeOne) pointerGuard (executesSkip _ _)) scopeRun
  have effect := pointer.effect.trans (allocationEffect.trans
    (CellEffect.closeLocal allocated checked.locals.slot (.signed .i32 (top + 1 : Nat))
      allocationEffect.wellFormed (saveEffect.trans restEffect)))
  have heap := pointer.heap.trans (allocationHeap.trans
    (HeapFrame.closeLocal allocated checked.locals.slot (.signed .i32 (top + 1 : Nat)) (saveHeap.trans restHeap)))
  have allBytes := (pointer.window.append preparedReady.window).append
    (by simpa only [List.length_append, Nat.add_assoc] using restWindow)
  exact ⟨restoreLocals allocated completed, emitted, whole,
    finalOutput, finalWork, allBytes, effect, heap⟩

end Lanius.X86.Lower.Expression.Raw
