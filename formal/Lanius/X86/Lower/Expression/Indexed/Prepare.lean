import Lanius.X86.Source.Expression.Indexed
import Lanius.X86.Frame.Allocate
import Lanius.X86.Frame.Slot
import Lanius.X86.Buffer.Emission

namespace Lanius.X86.Lower.Expression.Indexed

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView.Core Lanius.X86.Source Lanius.X86.Buffer

def saveBytes (slot : Nat) : List UInt8 := Frame.Slot.bytes .save64 slot 0
def workspaceAfter (workspace : List Int) (top peak cursor : Nat) : List Int :=
  (Frame.Allocate.updated workspace top peak 1).set 1 cursor
def writes (output work : CellId) : CellSet := CellSet.union (CellSet.singleton output) (CellSet.singleton work)

/-- Facts at the recursive index-expression call. The private slot is the old
TOP, TOP has advanced, and the emitted descriptor store precedes recursion.
These are derived from the actual allocator/save calls, not caller premises. -/
structure Prepared (state : State) (inputs : List Value) (frontier output work : Nat)
    (top peak start : Nat) (values workspace emitted : List Int) : Prop where
  wellFormed : StateWellFormed state
  locals : Locals inputs frontier state
  saved : state.local? 9 = some (.signed .i32 top)
  outputBacking : state.cellEntry? output = some { id := output, value := some (.array (signedI32Values emitted)) }
  workBacking : state.cellEntry? work = some { id := work, value := some (.array
    (signedI32Values (workspaceAfter workspace top peak (start + (saveBytes top).length)))) }
  window : Emission values start (saveBytes top) emitted

theorem workspaceAfter_top {top peak cursor : Nat}
    (within : 6 < workspace.length) :
    (workspaceAfter workspace top peak cursor)[6]? = some ((top + 1 : Nat) : Int) := by
  simp only [workspaceAfter, List.getElem?_set, show ¬ (1 = 6) by decide, ↓reduceIte]
  exact Frame.Allocate.updated_top within

theorem workspaceAfter_peak {top peak cursor : Nat}
    (within : 6 < workspace.length) (watermark : workspace[2]? = some (peak : Int)) :
    (workspaceAfter workspace top peak cursor)[2]? = some ((max peak (top + 1) : Nat) : Int) := by
  simp only [workspaceAfter, List.getElem?_set, show ¬ (1 = 2) by decide, ↓reduceIte]
  exact Frame.Allocate.updated_peak within watermark

/-- Source-linked preparation for the indexed-expression induction case.
The continuation below this prefix will be supplied by recursive simulation. -/
theorem prepare (checked : Source.Expression.Indexed.Checked emitters) (top peak capacity start : Nat)
    (wellFormed : StateWellFormed before) (locals : Locals inputs frontier before)
    (inputCount : inputs.length = 9)
    (plain : ∀ index : Fin inputs.length, ∀ elements, inputs.get index ≠ .array elements)
    (workLocal : before.local? 2 = some (.slice i32 work [] 0 workspace.length))
    (outputLocal : before.local? 3 = some (.slice i32 output [] 0 values.length))
    (capacityLocal : before.local? 4 = some (.signed .i32 capacity))
    (distinct : output ≠ work)
    (outputBacking : before.cellEntry? output = some { id := output, value := some (.array (signedI32Values values)) })
    (workBacking : before.cellEntry? work = some { id := work, value := some (.array (signedI32Values workspace)) })
    (within : 6 < workspace.length) (current : workspace[6]? = some (top : Int))
    (watermark : workspace[2]? = some (peak : Int)) (cursor : workspace[1]? = some (start : Int))
    (ordered : top ≤ peak) (peakBound : peak ≤ Frame.Allocate.limit) (slotRoom : top < Frame.Allocate.limit)
    (room : start + (saveBytes top).length ≤ capacity) (storage : capacity ≤ values.length) (bounded : capacity ≤ 2147483647) :
    ∃ allocated prepared emitted,
      Evaluates emitters.pack.program.core before (.call checked.allocate.internal.source.function.id [Source.read 2, Source.number 1])
        (.signed .i32 top) allocated ∧
      Evaluates emitters.pack.program.core (allocated.bindLocal 9 (.signed .i32 top)) Source.Expression.Indexed.rejected
        (.boolean false) (allocated.bindLocal 9 (.signed .i32 top)) ∧
      Executes emitters.pack.program.core (allocated.bindLocal 9 (.signed .i32 top))
        (.expression (.call checked.save.internal.source.function.id
          (Source.Expression.Indexed.saveArguments checked.index.constants.rax.id))) .next prepared ∧
      Prepared prepared inputs frontier output work top peak start values workspace emitted ∧
      CellEffect (writes output work) before allocated ∧ HeapFrame before allocated ∧
      CellEffect (writes output work) (allocated.bindLocal 9 (.signed .i32 top)) prepared ∧
      HeapFrame (allocated.bindLocal 9 (.signed .i32 top)) prepared := by
  have args : ArgumentsEvaluateTo emitters.pack.program.core before [Source.read 2, Source.number 1]
      (Frame.Allocate.inputValues work workspace.length 1) before :=
    .cons (local_evaluates _ workLocal) (.cons ⟨1, rfl⟩ (.nil _ _))
  obtain ⟨allocated, allocatedRun, allocatedWork, allocatedEffect, allocatedHeap⟩ :=
    Frame.Allocate.succeeds checked.allocate top peak 1 wellFormed workBacking within current watermark
      ordered peakBound (by decide) (by omega) args
  simp only [Nat.add_sub_cancel] at allocatedRun
  have allocatedLocals := locals.store wellFormed allocatedEffect workBacking (fun i => plain i _)
  have allocatedOutput := allocatedEffect.preserves_entry wellFormed outputBacking distinct
  have allocatedWorkLocal := allocatedEffect.preserves_local_of_distinct_value wellFormed workLocal workBacking (by intro same; cases same)
  have allocatedOutputLocal := allocatedEffect.preserves_local_of_distinct_value wellFormed outputLocal workBacking (by intro same; cases same)
  have allocatedCapacity := allocatedEffect.preserves_local_of_distinct_value wellFormed capacityLocal workBacking (by intro same; cases same)
  let entered := allocated.bindLocal 9 (.signed .i32 top)
  have enteredWF := bindLocal_preserves_well_formed allocated 9 (.signed .i32 top) allocatedEffect.wellFormed
  have enteredLocals := allocatedLocals.bind (id := 9) allocatedEffect.wellFormed (by omega) (.signed .i32 top)
  have enteredOutput := ((bindLocal_effect allocated 9 (.signed .i32 top)).oldCells output
    (StateWellFormed.cell_lt_next_of_entry allocatedEffect.wellFormed allocatedOutput) (by simp [CellSet.empty])).trans allocatedOutput
  have enteredWork := ((bindLocal_effect allocated 9 (.signed .i32 top)).oldCells work
    (StateWellFormed.cell_lt_next_of_entry allocatedEffect.wellFormed allocatedWork) (by simp [CellSet.empty])).trans allocatedWork
  have enteredWorkLocal := (bindLocal_preserves_other_local (boundId := 9) (queriedId := 2)
    (value := .signed .i32 top) allocatedEffect.wellFormed (by decide)).trans allocatedWorkLocal
  have enteredOutputLocal := (bindLocal_preserves_other_local (boundId := 9) (queriedId := 3)
    (value := .signed .i32 top) allocatedEffect.wellFormed (by decide)).trans allocatedOutputLocal
  have enteredCapacity := (bindLocal_preserves_other_local (boundId := 9) (queriedId := 4)
    (value := .signed .i32 top) allocatedEffect.wellFormed (by decide)).trans allocatedCapacity
  have saved := bindLocal_finds_local allocated 9 (.signed .i32 top) allocatedEffect.wellFormed
  have guard : Evaluates emitters.pack.program.core entered Source.Expression.Indexed.rejected (.boolean false) entered := by
    apply evaluatesEagerBinary (by decide) (by decide) (local_evaluates _ saved)
      (show Evaluates emitters.pack.program.core entered (Source.number 0) (.signed .i32 0) entered from ⟨1, rfl⟩)
    simp [evalBinaryValue, evalSignedBinary]
  have rax := checked.index.constants.rax.evaluates (before := entered)
  rw [checked.index.constants.values.2.2.2.1] at rax
  have saveArgs : ArgumentsEvaluateTo emitters.pack.program.core entered
      (Source.Expression.Indexed.saveArguments checked.index.constants.rax.id)
      (Frame.Slot.inputValues (.slice i32 output [] 0 values.length) capacity
        (.slice i32 work [] 0 (Frame.Allocate.updated workspace top peak 1).length) top 0) entered := by
    simp only [Frame.Allocate.updated_length]
    exact .cons (local_evaluates _ enteredOutputLocal) (.cons (local_evaluates _ enteredCapacity)
      (.cons (local_evaluates _ enteredWorkLocal) (.cons (local_evaluates _ saved) (.cons rax (.nil _ _)))))
  obtain ⟨prepared, emitted, saveRun, finalOutput, finalWork, exactBytes, _, length, framed, saveEffect, saveHeap⟩ :=
    Frame.Slot.emits checked.save top capacity start 0 enteredWF (by unfold Frame.Allocate.limit at slotRoom; omega)
      distinct enteredOutput enteredWork
      ((Frame.Allocate.updated_frame (values := workspace) (top := top) (peak := peak) (count := 1) (by decide : 1 ≠ 6 ∧ 1 ≠ 2)).trans cursor)
      room storage bounded saveArgs
  have untouched (id : Nat) (value : Value) (found : entered.local? id = some value)
      (notOutput : value ≠ .array (signedI32Values values))
      (notWork : value ≠ .array (signedI32Values (Frame.Allocate.updated workspace top peak 1))) :
      ∀ cell, entered.cellId? id = some cell → ¬ writes output work cell := by
    intro cell binding changed
    rcases changed with out | work
    · exact local_cell_ne_of_distinct_value found enteredOutput notOutput binding out
    · exact local_cell_ne_of_distinct_value found enteredWork notWork binding work
  have keptLocals := enteredLocals.frame enteredWF saveEffect
    (fun index => untouched index.val _ (enteredLocals.found index) (plain index _) (plain index _))
  have keptSaved := saveEffect.preserves_local enteredWF saved
    (untouched 9 _ saved (by intro same; cases same) (by intro same; cases same))
  exact ⟨allocated, prepared, emitted, allocatedRun, guard, executesExpression saveRun,
    ⟨saveEffect.wellFormed, keptLocals, keptSaved, finalOutput, finalWork, ⟨length, exactBytes, framed⟩⟩,
    allocatedEffect.weaken CellSet.subset_union_right, allocatedHeap, saveEffect, saveHeap⟩

end Lanius.X86.Lower.Expression.Indexed
