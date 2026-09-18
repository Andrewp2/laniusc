import Lanius.X86.Lower.Expression.Indexed.Continue

namespace Lanius.X86.Lower.Expression.Indexed

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView.Core Lanius.X86.Source Lanius.X86.Buffer

/-- The actual indexed-expression body, conditional only on the recursive
expression case. Allocation, descriptor saving, the bounds/address emitter,
boolean result, and both lexical scopes are supplied by proved source calls.
This does not assert the recursive IH for the current compiler. -/
theorem body (checked : Source.Expression.Indexed.Checked emitters) (signed : Bool)
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
    (room : start + (saveBytes top).length + recursiveBytes.length + (Machine.Index.bytes signed top).length ≤ capacity)
    (storage : capacity ≤ values.length) (bounded : capacity ≤ 2147483647)
    (recursive : ∀ prepared preparedValues,
      Prepared prepared inputs frontier output work top peak start values workspace preparedValues →
      StoreEffect (writes output work) before prepared →
      ∃ recursed recursiveValues recursiveWorkspace,
        RecursiveCall checked signed prepared recursed output work (start + (saveBytes top).length)
          workspace.length preparedValues recursiveValues recursiveWorkspace recursiveBytes) :
    ∃ after emitted finalWorkspace,
      Executes emitters.pack.program.core before
        (Source.Expression.Indexed.preparation checked.allocate.internal.source.function.id
          checked.save.internal.source.function.id checked.index.constants.rax.id
          (Source.Expression.Indexed.continuation checked.expression.function.id checked.index.internal.source.function.id))
        (.returned (some (.boolean true))) after ∧
      after.cellEntry? output = some { id := output, value := some (.array (signedI32Values emitted)) } ∧
      after.cellEntry? work = some { id := work, value := some (.array (signedI32Values finalWorkspace)) } ∧
      Emission values start (saveBytes top ++ recursiveBytes ++ Machine.Index.bytes signed top) emitted ∧
      Index.Emission.Refines signed top (byteSlice emitted
        (start + (saveBytes top).length + recursiveBytes.length) (Machine.Index.bytes signed top).length) ∧
      CellEffect (writes output work) before after ∧ HeapFrame before after := by
  obtain ⟨allocated, prepared, preparedValues, allocateRun, guard, saveRun, ready,
      allocationEffect, allocationHeap, saveEffect, saveHeap⟩ :=
    prepare checked top peak capacity start wellFormed locals inputCount plain workLocal outputLocal capacityLocal
      distinct outputBacking workBacking within current watermark cursor ordered peakBound slotRoom (by omega) storage bounded
  have preserved (id : Nat) (inside : id < inputs.length) (value : Value)
      (found : before.local? id = some value) : prepared.local? id = some value :=
    (ready.locals.found ⟨id, inside⟩).trans ((locals.found ⟨id, inside⟩).symm.trans found)
  have preparationFrame : StoreEffect (writes output work) before prepared :=
    (allocationEffect.modifiesOnly allocationHeap).toStoreEffect.trans_same
      (((bindLocal_effect allocated 9 (.signed .i32 top)).weaken CellSet.empty_subset).trans_same
        (saveEffect.modifiesOnly saveHeap).toStoreEffect)
  obtain ⟨recursed, recursiveValues, recursiveWorkspace, child⟩ := recursive prepared preparedValues ready preparationFrame
  obtain ⟨completed, emitted, restRun, finalOutput, finalWork, window, refinement, restEffect, restHeap⟩ :=
    continues checked signed capacity ready child
      (preserved 2 (by omega) _ workLocal) (preserved 3 (by omega) _ outputLocal)
      (preserved 4 (by omega) _ capacityLocal) distinct (by unfold Frame.Allocate.limit at slotRoom; omega)
      room storage bounded
  have scopedRun := executesSequence
    (executesIfFalse (thenBranch := returned (.value (.boolean false))) guard (executesSkip _ _))
    (executesSequence saveRun restRun)
  have effect := allocationEffect.trans (CellEffect.closeLocal allocated 9 (.signed .i32 top)
    allocationEffect.wellFormed (saveEffect.trans restEffect))
  have heap := allocationHeap.trans (HeapFrame.closeLocal allocated 9 (.signed .i32 top) (saveHeap.trans restHeap))
  exact ⟨restoreLocals allocated completed, emitted, _, executesLetLocal allocateRun scopedRun,
    finalOutput, finalWork, window, refinement, effect, heap⟩

def inputValues (input length active depth context contextLength : Value)
    (work output workLength outputLength capacity : Nat) : List Value :=
  [input, length, .slice i32 work [] 0 workLength, .slice i32 output [] 0 outputLength,
    .signed .i32 capacity, active, depth, context, contextLength]

/-- Close the complete actual indexed call around the induction case.
`recursive` receives the initial caller's storage frame as well as the
prepared workspace, so source/input/context invariants can be transported
through preparation instead of being assumed for arbitrary fresh states. -/
theorem compiles (checked : Source.Expression.Indexed.Checked emitters) (signed : Bool)
    (top peak capacity start : Nat) (recursiveBytes : List UInt8)
    (input length active depth context contextLength : Value)
    (wellFormed : StateWellFormed before)
    (plain : ∀ index : Fin 9, ∀ elements,
      (inputValues input length active depth context contextLength work output workspace.length values.length capacity).get index ≠ .array elements)
    (distinct : output ≠ work)
    (outputBacking : before.cellEntry? output = some { id := output, value := some (.array (signedI32Values values)) })
    (workBacking : before.cellEntry? work = some { id := work, value := some (.array (signedI32Values workspace)) })
    (within : 6 < workspace.length) (current : workspace[6]? = some (top : Int))
    (watermark : workspace[2]? = some (peak : Int)) (cursor : workspace[1]? = some (start : Int))
    (ordered : top ≤ peak) (peakBound : peak ≤ Frame.Allocate.limit) (slotRoom : top < Frame.Allocate.limit)
    (room : start + (saveBytes top).length + recursiveBytes.length + (Machine.Index.bytes signed top).length ≤ capacity)
    (storage : capacity ≤ values.length) (bounded : capacity ≤ 2147483647)
    (argumentsResult : ArgumentsEvaluateTo emitters.pack.program.core caller arguments
      (inputValues input length active depth context contextLength work output workspace.length values.length capacity) before)
    (recursive : ∀ prepared frontier preparedValues,
      Prepared prepared (inputValues input length active depth context contextLength work output workspace.length values.length capacity)
        frontier output work top peak start values workspace preparedValues →
      StoreEffect (writes output work) before prepared →
      ∃ recursed recursiveValues recursiveWorkspace,
        RecursiveCall checked signed prepared recursed output work (start + (saveBytes top).length)
          workspace.length preparedValues recursiveValues recursiveWorkspace recursiveBytes) :
    ∃ after emitted finalWorkspace,
      Evaluates emitters.pack.program.core caller (.call checked.internal.source.function.id arguments) (.boolean true) after ∧
      after.cellEntry? output = some { id := output, value := some (.array (signedI32Values emitted)) } ∧
      after.cellEntry? work = some { id := work, value := some (.array (signedI32Values finalWorkspace)) } ∧
      Emission values start (saveBytes top ++ recursiveBytes ++ Machine.Index.bytes signed top) emitted ∧
      Index.Emission.Refines signed top (byteSlice emitted
        (start + (saveBytes top).length + recursiveBytes.length) (Machine.Index.bytes signed top).length) ∧
      CellEffect (writes output work) before after ∧ HeapFrame before after := by
  let inputs := inputValues input length active depth context contextLength work output workspace.length values.length capacity
  let params := parameterBindings (fun index : Fin 9 => inputs.get index)
  have calleeWF := enterCall_preserves_wellFormed wellFormed (bindings := params)
  have calleeLocals := Locals.ofReads (values := inputs) calleeWF
    (fun index => enterCall_parameterBindings_matches wellFormed index)
  have initialOutput := ((enterCall_effect before params).oldCells output
    (StateWellFormed.cell_lt_next_of_entry wellFormed outputBacking) (by simp [CellSet.empty])).trans outputBacking
  have initialWork := ((enterCall_effect before params).oldCells work
    (StateWellFormed.cell_lt_next_of_entry wellFormed workBacking) (by simp [CellSet.empty])).trans workBacking
  obtain ⟨completed, emitted, finalWorkspace, run, finalOutput, finalWork, window, refinement, effect, heap⟩ :=
    body checked signed top peak capacity start recursiveBytes calleeWF calleeLocals rfl plain
      (calleeLocals.found ⟨2, by simp [inputs, inputValues]⟩)
      (calleeLocals.found ⟨3, by simp [inputs, inputValues]⟩)
      (calleeLocals.found ⟨4, by simp [inputs, inputValues]⟩)
      distinct initialOutput initialWork within current watermark cursor ordered peakBound slotRoom room storage bounded
      (fun prepared preparedValues ready frame => recursive prepared _ preparedValues ready
        (((enterCall_effect before params).weaken CellSet.empty_subset).trans_same frame))
  have called := checked.internal.call wellFormed argumentsResult (bindings := params) rfl run effect
  exact ⟨restoreLocals before completed, emitted, finalWorkspace, called.1, finalOutput, finalWork,
    window, refinement, called.2, HeapFrame.closeCall before params heap⟩

end Lanius.X86.Lower.Expression.Indexed
