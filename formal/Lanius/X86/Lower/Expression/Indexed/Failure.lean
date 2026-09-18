import Lanius.X86.Lower.Expression.Indexed.Reject
import Lanius.X86.Lower.Expression.Indexed.Body

namespace Lanius.X86.Lower.Expression.Indexed.Failure

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView.Core Lanius.X86.Source Lanius.X86.Buffer

/-- The failure case's recursive induction hypothesis records the actual
child call and its emitted bytes and workspace. Rejection is not atomic:
the operand save and any child bytes remain in the output. -/
structure RecursiveCall (checked : Source.Expression.Indexed.Checked emitters)
    (kind : Int) (before after : State) (output work cursor : Nat)
    (original emitted workspace : List Int) (code : List UInt8) : Prop where
  run : Evaluates emitters.pack.program.core before
    (.call checked.expression.function.id Source.Expression.Indexed.recurseArguments)
    (.signed .i32 kind) after
  outputBacking : after.cellEntry? output = some { id := output, value := some (.array (signedI32Values emitted)) }
  workBacking : after.cellEntry? work = some { id := work, value := some (.array (signedI32Values workspace)) }
  window : Emission original cursor code emitted
  effect : CellEffect (writes output work) before after
  heap : HeapFrame before after

/-- Compose actual allocation, descriptor capture, recursive compilation,
and invalid-kind rejection into the complete indexed body. The recursive
IH receives the preparation's effect from the original state, retaining
the unchanged input/context backing invariants needed by the child proof. -/
theorem body (checked : Source.Expression.Indexed.Checked emitters) (kind : Int)
    (top peak capacity start : Nat) (recursiveBytes : List UInt8)
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
    (room : start + (saveBytes top).length ≤ capacity)
    (storage : capacity ≤ values.length) (bounded : capacity ≤ 2147483647)
    (notSigned : kind ≠ 1) (notUnsigned : kind ≠ 3)
    (recursive : ∀ prepared preparedValues,
      Prepared prepared inputs frontier output work top peak start values workspace preparedValues →
      StoreEffect (writes output work) before prepared →
      ∃ recursed recursiveValues recursiveWorkspace,
        RecursiveCall checked kind prepared recursed output work (start + (saveBytes top).length)
          preparedValues recursiveValues recursiveWorkspace recursiveBytes) :
    ∃ after emitted finalWorkspace,
      Executes emitters.pack.program.core before
        (Source.Expression.Indexed.preparation checked.allocate.internal.source.function.id
          checked.save.internal.source.function.id checked.index.constants.rax.id
          (Source.Expression.Indexed.continuation checked.expression.function.id checked.index.internal.source.function.id))
        (.returned (some (.boolean false))) after ∧
      after.cellEntry? output = some { id := output, value := some (.array (signedI32Values emitted)) } ∧
      after.cellEntry? work = some { id := work, value := some (.array (signedI32Values finalWorkspace)) } ∧
      Emission values start (saveBytes top ++ recursiveBytes) emitted ∧
      CellEffect (writes output work) before after ∧ HeapFrame before after := by
  obtain ⟨allocated, prepared, preparedValues, allocateRun, guard, saveRun, ready,
      allocationEffect, allocationHeap, saveEffect, saveHeap⟩ :=
    prepare checked top peak capacity start wellFormed locals inputCount plain workLocal outputLocal capacityLocal
      distinct outputBacking workBacking within current watermark cursor ordered peakBound slotRoom room storage bounded
  have preserved (id : Nat) (inside : id < inputs.length) (value : Value)
      (found : before.local? id = some value) : prepared.local? id = some value :=
    (ready.locals.found ⟨id, inside⟩).trans ((locals.found ⟨id, inside⟩).symm.trans found)
  have preparationFrame : StoreEffect (writes output work) before prepared :=
    (allocationEffect.modifiesOnly allocationHeap).toStoreEffect.trans_same
      (((bindLocal_effect allocated 9 (.signed .i32 top)).weaken CellSet.empty_subset).trans_same
        (saveEffect.modifiesOnly saveHeap).toStoreEffect)
  obtain ⟨recursed, recursiveValues, recursiveWorkspace, child⟩ := recursive prepared preparedValues ready preparationFrame
  obtain ⟨completed, restRun, restEffect, restHeap, noWrites, _⟩ :=
    Reject.continues checked kind capacity ready child.run child.effect child.heap
      (preserved 2 (by omega) _ workLocal) (preserved 3 (by omega) _ outputLocal)
      (preserved 4 (by omega) _ capacityLocal) notSigned notUnsigned
  have finalOutput := noWrites.empty_preserves_entry child.effect.wellFormed child.outputBacking
  have finalWork := noWrites.empty_preserves_entry child.effect.wellFormed child.workBacking
  have scopedRun := executesSequence
    (executesIfFalse (thenBranch := returned (.value (.boolean false))) guard (executesSkip _ _))
    (executesSequence saveRun restRun)
  have effect := allocationEffect.trans (CellEffect.closeLocal allocated 9 (.signed .i32 top)
    allocationEffect.wellFormed (saveEffect.trans restEffect))
  have heap := allocationHeap.trans (HeapFrame.closeLocal allocated 9 (.signed .i32 top) (saveHeap.trans restHeap))
  exact ⟨restoreLocals allocated completed, recursiveValues, recursiveWorkspace,
    executesLetLocal allocateRun scopedRun, finalOutput, finalWork, ready.window.append child.window, effect, heap⟩

/-- Whole indexed-call rejection after a child with an invalid kind. The
recursive IH retains the original caller's frame, including through call
entry and operand preparation. Emitted capture/child bytes are retained;
the address helper emits nothing and leaves the child's workspace intact. -/
theorem rejects (checked : Source.Expression.Indexed.Checked emitters) (kind : Int)
    (top peak capacity start : Nat) (recursiveBytes : List UInt8)
    (input length active depth context contextLength : Value)
    (wellFormed : StateWellFormed before)
    (plain : ∀ index : Fin 9, ∀ elements,
      (Indexed.inputValues input length active depth context contextLength work output workspace.length values.length capacity).get index ≠ .array elements)
    (distinct : output ≠ work)
    (outputBacking : before.cellEntry? output = some { id := output, value := some (.array (signedI32Values values)) })
    (workBacking : before.cellEntry? work = some { id := work, value := some (.array (signedI32Values workspace)) })
    (within : 6 < workspace.length) (current : workspace[6]? = some (top : Int))
    (watermark : workspace[2]? = some (peak : Int)) (cursor : workspace[1]? = some (start : Int))
    (ordered : top ≤ peak) (peakBound : peak ≤ Frame.Allocate.limit) (slotRoom : top < Frame.Allocate.limit)
    (room : start + (saveBytes top).length ≤ capacity)
    (storage : capacity ≤ values.length) (bounded : capacity ≤ 2147483647)
    (notSigned : kind ≠ 1) (notUnsigned : kind ≠ 3)
    (argumentsResult : ArgumentsEvaluateTo emitters.pack.program.core caller arguments
      (Indexed.inputValues input length active depth context contextLength work output workspace.length values.length capacity) before)
    (recursive : ∀ prepared frontier preparedValues,
      Prepared prepared (Indexed.inputValues input length active depth context contextLength work output workspace.length values.length capacity)
        frontier output work top peak start values workspace preparedValues →
      StoreEffect (writes output work) before prepared →
      ∃ recursed recursiveValues recursiveWorkspace,
        RecursiveCall checked kind prepared recursed output work (start + (saveBytes top).length)
          preparedValues recursiveValues recursiveWorkspace recursiveBytes) :
    ∃ after emitted finalWorkspace,
      Evaluates emitters.pack.program.core caller (.call checked.internal.source.function.id arguments) (.boolean false) after ∧
      after.cellEntry? output = some { id := output, value := some (.array (signedI32Values emitted)) } ∧
      after.cellEntry? work = some { id := work, value := some (.array (signedI32Values finalWorkspace)) } ∧
      Emission values start (saveBytes top ++ recursiveBytes) emitted ∧
      CellEffect (writes output work) before after ∧ HeapFrame before after := by
  let inputs := Indexed.inputValues input length active depth context contextLength work output workspace.length values.length capacity
  let params := parameterBindings (fun index : Fin 9 => inputs.get index)
  have calleeWF := enterCall_preserves_wellFormed wellFormed (bindings := params)
  have calleeLocals := Locals.ofReads (values := inputs) calleeWF
    (fun index => enterCall_parameterBindings_matches wellFormed index)
  have initialOutput := ((enterCall_effect before params).oldCells output
    (StateWellFormed.cell_lt_next_of_entry wellFormed outputBacking) (by simp [CellSet.empty])).trans outputBacking
  have initialWork := ((enterCall_effect before params).oldCells work
    (StateWellFormed.cell_lt_next_of_entry wellFormed workBacking) (by simp [CellSet.empty])).trans workBacking
  obtain ⟨completed, emitted, finalWorkspace, run, finalOutput, finalWork, window, effect, heap⟩ :=
    body checked kind top peak capacity start recursiveBytes calleeWF calleeLocals rfl plain
      (calleeLocals.found ⟨2, by simp [inputs, Indexed.inputValues]⟩)
      (calleeLocals.found ⟨3, by simp [inputs, Indexed.inputValues]⟩)
      (calleeLocals.found ⟨4, by simp [inputs, Indexed.inputValues]⟩)
      distinct initialOutput initialWork within current watermark cursor ordered peakBound slotRoom room storage bounded
      notSigned notUnsigned
      (fun prepared preparedValues ready frame => recursive prepared _ preparedValues ready
        (((enterCall_effect before params).weaken CellSet.empty_subset).trans_same frame))
  have called := checked.internal.call wellFormed argumentsResult (bindings := params) rfl run effect
  exact ⟨restoreLocals before completed, emitted, finalWorkspace, called.1, finalOutput, finalWork,
    window, called.2, HeapFrame.closeCall before params heap⟩

end Lanius.X86.Lower.Expression.Indexed.Failure
