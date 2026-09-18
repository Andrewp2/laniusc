import Lanius.X86.Lower.Expression.Indexed.Body
import Lanius.X86.Lower.Expression.Literal

namespace Lanius.X86.Lower.Expression.Indexed.Literal

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView.Core Lanius.X86.Source Lanius.X86.Buffer

def resultWorkspace (workspace : List Int) (top peak position start : Nat) : List Int :=
  (Expression.Literal.afterLiteral (workspaceAfter workspace top peak (start + (saveBytes top).length))
    position (start + (saveBytes top).length)).set 1
      (start + (saveBytes top).length + 5 + (Machine.Index.bytes true top).length : Nat)

theorem resultWorkspace_input (within : 6 < workspace.length) :
    (resultWorkspace workspace top peak position start)[0]? = some ((position + 3 : Nat) : Int) := by
  unfold resultWorkspace Expression.Literal.afterLiteral
  rw [List.getElem?_set_ne (by decide), List.getElem?_set_ne (by decide)]
  exact List.getElem?_set_self (by simp only [workspaceAfter, List.length_set, Frame.Allocate.updated_length]; omega)

private theorem workspace_other (index : Nat) (different : index ≠ 1 ∧ index ≠ 6 ∧ index ≠ 2) :
    (workspaceAfter workspace top peak cursor)[index]? = workspace[index]? := by
  simp only [workspaceAfter, List.getElem?_set, Ne.symm different.1, ↓reduceIte]
  exact Frame.Allocate.updated_frame ⟨different.2.1, different.2.2⟩

/-- Discharge the existing recursive source-call IH with the proved literal
compiler. The original transport backing is carried through preparation's
storage effect, not assumed again at an arbitrary prepared state. -/
theorem literal_recurses (checked : Source.Expression.Indexed.Checked emitters)
    (literal : Source.Expression.Literal.Checked emitters)
    (sameExpression : checked.expression.function.id = literal.wrapper.source.function.id)
    (top peak length position depth capacity start : Nat) (low : Int) (active context contextLength : Value)
    (wellFormed : StateWellFormed before)
    (plain : ∀ value ∈ Expression.Literal.inputValues input work output transport.length workspace.length values.length
      length capacity depth active context contextLength, ∀ elements, value ≠ .array elements)
    (inputBacking : before.cellEntry? input = some { id := input, value := some (.array (signedI32Values transport)) })
    (inputOutput : input ≠ output) (inputWork : input ≠ work) (outputWork : output ≠ work)
    (within : 6 < workspace.length) (inputCursor : workspace[0]? = some (position : Int)) (healthy : workspace[4]? = some 0)
    (depthBound : depth < 512) (readable : position + 3 ≤ length)
    (inputStorage : length ≤ transport.length) (inputBound : length ≤ 2147483647)
    (room : start + (saveBytes top).length + 5 ≤ capacity) (storage : capacity ≤ values.length) (bounded : capacity ≤ 2147483647)
    (tagWord : transport[position]? = some 0) (kindWord : transport[position + 1]? = some 1) (lowWord : transport[position + 2]? = some low)
    (ready : Prepared prepared (Indexed.inputValues (.slice i32 input [] 0 transport.length) (.signed .i32 length)
      active (.signed .i32 depth) context contextLength work output workspace.length values.length capacity)
      frontier output work top peak start values workspace preparedValues)
    (frame : StoreEffect (writes output work) before prepared) :
    ∃ recursed, RecursiveCall checked true prepared recursed output work (start + (saveBytes top).length)
      workspace.length preparedValues (Encode.Immediate.written preparedValues (start + (saveBytes top).length) low)
      (Expression.Literal.afterLiteral (workspaceAfter workspace top peak (start + (saveBytes top).length))
        position (start + (saveBytes top).length)) (Encode.Immediate.bytes low) := by
  have preparedInput := (frame.oldCells input (StateWellFormed.cell_lt_next_of_entry wellFormed inputBacking) (by
    intro changed; rcases changed with out | work
    · exact inputOutput out
    · exact inputWork work)).trans inputBacking
  have workLength : (workspaceAfter workspace top peak (start + (saveBytes top).length)).length = workspace.length := by
    simp only [workspaceAfter, List.length_set, Frame.Allocate.updated_length]
  have preparedPlain : ∀ value ∈ Expression.Literal.inputValues input work output transport.length
      (workspaceAfter workspace top peak (start + (saveBytes top).length)).length preparedValues.length
      length capacity depth active context contextLength, ∀ elements, value ≠ .array elements := by
    simpa only [workLength, ready.window.length] using plain
  have args : ArgumentsEvaluateTo emitters.pack.program.core prepared Source.Expression.Indexed.recurseArguments
      (Expression.Literal.inputValues input work output transport.length
        (workspaceAfter workspace top peak (start + (saveBytes top).length)).length preparedValues.length
        length capacity depth active context contextLength) prepared := by
    rw [workLength, ready.window.length]
    exact .cons (local_evaluates _ (ready.locals.found ⟨0, by simp [Indexed.inputValues]⟩))
      (.cons (local_evaluates _ (ready.locals.found ⟨1, by simp [Indexed.inputValues]⟩))
        (.cons (local_evaluates _ (ready.locals.found ⟨2, by simp [Indexed.inputValues]⟩))
          (.cons (local_evaluates _ (ready.locals.found ⟨3, by simp [Indexed.inputValues]⟩))
            (.cons (local_evaluates _ (ready.locals.found ⟨4, by simp [Indexed.inputValues]⟩))
              (.cons (local_evaluates _ (ready.locals.found ⟨5, by simp [Indexed.inputValues]⟩))
                (.cons (local_evaluates _ (ready.locals.found ⟨6, by simp [Indexed.inputValues]⟩))
                  (.cons (local_evaluates _ (ready.locals.found ⟨7, by simp [Indexed.inputValues]⟩))
                    (.cons (local_evaluates _ (ready.locals.found ⟨8, by simp [Indexed.inputValues]⟩)) (.nil _ _)))))))))
  have preparedCursor := (workspace_other (workspace := workspace) (top := top) (peak := peak)
    (cursor := start + (saveBytes top).length) 0 (by decide)).trans inputCursor
  have preparedHealthy := (workspace_other (workspace := workspace) (top := top) (peak := peak)
    (cursor := start + (saveBytes top).length) 4 (by decide)).trans healthy
  have codeCursor : (workspaceAfter workspace top peak (start + (saveBytes top).length))[1]? =
      some ((start + (saveBytes top).length : Nat) : Int) := by
    exact List.getElem?_set_self (by simpa only [Frame.Allocate.updated_length] using (show 1 < workspace.length by omega))
  let c : Context := {
    input := input, output := output, work := work, transport := transport, values := preparedValues,
    workspace := workspaceAfter workspace top peak (start + (saveBytes top).length),
    length := length, position := position, depth := depth, active := active, capacity := capacity,
    start := start + (saveBytes top).length, top := (top + 1 : Nat), context := context, contextLength := contextLength }
  obtain ⟨recursed, run, ⟨_, finalOutput, finalWork, rfl, window⟩, effect, heap⟩ :=
    (Expression.Literal.compiles literal c
      ⟨preparedCursor, codeCursor, preparedHealthy, workspaceAfter_top within, depthBound, inputStorage, inputBound,
        by simpa only [c, ready.window.length] using storage, bounded⟩
      ⟨.inl rfl, readable, tagWord, kindWord, lowWord⟩ room).call ready.wellFormed args
      ⟨preparedPlain, preparedInput, ready.outputBacking, ready.workBacking, inputOutput, inputWork, outputWork⟩
  rw [← sameExpression] at run
  refine ⟨recursed, ⟨run, finalOutput, finalWork, ?_, ?_, window, effect, heap⟩⟩
  · simp only [Expression.Literal.afterLiteral, List.length_set, workLength]
  · simpa only [Expression.Literal.afterLiteral, Encode.Immediate.bytes_length] using
      (List.getElem?_set_self (l := (workspaceAfter workspace top peak (start + (saveBytes top).length)).set 0 (position + 3 : Nat))
        (a := ((start + (saveBytes top).length + 5 : Nat) : Int))
        (by simp only [List.length_set, workLength]; omega : 1 < ((workspaceAfter workspace top peak
          (start + (saveBytes top).length)).set 0 (position + 3 : Nat)).length))

/-- A concrete indexed expression with an i32 literal operand: the recursive
source execution premise is gone. Preparation, literal compilation, checked
address emission and both lexical scopes execute from their real bodies. -/
theorem body (checked : Source.Expression.Indexed.Checked emitters) (literal : Source.Expression.Literal.Checked emitters)
    (sameExpression : checked.expression.function.id = literal.wrapper.source.function.id)
    (top peak length position depth capacity start : Nat) (low : Int) (active context contextLength : Value)
    (wellFormed : StateWellFormed before)
    (locals : Locals (Indexed.inputValues (.slice i32 input [] 0 transport.length) (.signed .i32 length)
      active (.signed .i32 depth) context contextLength work output workspace.length values.length capacity) frontier before)
    (plain : ∀ value ∈ Expression.Literal.inputValues input work output transport.length workspace.length values.length
      length capacity depth active context contextLength, ∀ elements, value ≠ .array elements)
    (inputBacking : before.cellEntry? input = some { id := input, value := some (.array (signedI32Values transport)) })
    (outputBacking : before.cellEntry? output = some { id := output, value := some (.array (signedI32Values values)) })
    (workBacking : before.cellEntry? work = some { id := work, value := some (.array (signedI32Values workspace)) })
    (inputOutput : input ≠ output) (inputWork : input ≠ work) (outputWork : output ≠ work)
    (within : 6 < workspace.length) (current : workspace[6]? = some (top : Int))
    (watermark : workspace[2]? = some (peak : Int)) (cursor : workspace[1]? = some (start : Int))
    (inputCursor : workspace[0]? = some (position : Int)) (healthy : workspace[4]? = some 0)
    (ordered : top ≤ peak) (peakBound : peak ≤ Frame.Allocate.limit) (slotRoom : top < Frame.Allocate.limit)
    (depthBound : depth < 512) (readable : position + 3 ≤ length)
    (inputStorage : length ≤ transport.length) (inputBound : length ≤ 2147483647)
    (room : start + (saveBytes top).length + 5 + (Machine.Index.bytes true top).length ≤ capacity)
    (storage : capacity ≤ values.length) (bounded : capacity ≤ 2147483647)
    (tagWord : transport[position]? = some 0) (kindWord : transport[position + 1]? = some 1) (lowWord : transport[position + 2]? = some low) :
    ∃ after emitted, Executes emitters.pack.program.core before
        (Source.Expression.Indexed.preparation checked.allocate.internal.source.function.id checked.save.internal.source.function.id
          checked.index.constants.rax.id (Source.Expression.Indexed.continuation checked.expression.function.id checked.index.internal.source.function.id))
        (.returned (some (.boolean true))) after ∧
      after.cellEntry? output = some { id := output, value := some (.array (signedI32Values emitted)) } ∧
      after.cellEntry? work = some { id := work, value := some (.array (signedI32Values (resultWorkspace workspace top peak position start))) } ∧
      Emission values start (saveBytes top ++ Encode.Immediate.bytes low ++ Machine.Index.bytes true top) emitted ∧
      Index.Emission.Refines true top (byteSlice emitted (start + (saveBytes top).length + 5) (Machine.Index.bytes true top).length) ∧
      CellEffect (writes output work) before after ∧ HeapFrame before after := by
  obtain ⟨allocated, prepared, preparedValues, allocateRun, guard, saveRun, ready, allocationEffect, allocationHeap, saveEffect, saveHeap⟩ :=
    prepare checked top peak capacity start wellFormed locals rfl (fun index elements => plain _ (List.get_mem _ index) elements)
      (locals.found ⟨2, by simp [Indexed.inputValues]⟩) (locals.found ⟨3, by simp [Indexed.inputValues]⟩)
      (locals.found ⟨4, by simp [Indexed.inputValues]⟩) outputWork outputBacking workBacking within current watermark cursor
      ordered peakBound slotRoom (by omega) storage bounded
  have preparationFrame : StoreEffect (writes output work) before prepared :=
    (allocationEffect.modifiesOnly allocationHeap).toStoreEffect.trans_same
      (((bindLocal_effect allocated 9 (.signed .i32 top)).weaken CellSet.empty_subset).trans_same
        (saveEffect.modifiesOnly saveHeap).toStoreEffect)
  obtain ⟨recursed, child⟩ := literal_recurses checked literal sameExpression top peak length position depth capacity start low
    active context contextLength wellFormed plain inputBacking inputOutput inputWork outputWork within inputCursor healthy
    depthBound readable inputStorage inputBound (by omega) storage bounded tagWord kindWord lowWord ready preparationFrame
  obtain ⟨completed, emitted, continuation, finalOutput, finalWork, window, refinement, effect, heap⟩ :=
    continues checked true capacity ready child (ready.locals.found ⟨2, by simp [Indexed.inputValues]⟩)
      (ready.locals.found ⟨3, by simp [Indexed.inputValues]⟩) (ready.locals.found ⟨4, by simp [Indexed.inputValues]⟩)
      outputWork (by unfold Frame.Allocate.limit at slotRoom; omega) (by simpa only [Encode.Immediate.bytes_length] using room) storage bounded
  simp only [Encode.Immediate.bytes_length] at finalWork refinement
  have scopedRun := executesSequence (executesIfFalse (thenBranch := returned (.value (.boolean false))) guard (executesSkip _ _))
    (executesSequence saveRun continuation)
  exact ⟨_, emitted, executesLetLocal allocateRun scopedRun, finalOutput, finalWork, window, refinement,
    allocationEffect.trans (CellEffect.closeLocal allocated 9 (.signed .i32 top) allocationEffect.wellFormed (saveEffect.trans effect)),
    allocationHeap.trans (HeapFrame.closeLocal allocated 9 (.signed .i32 top) (saveHeap.trans heap))⟩

/-- The real indexed call with a signed-literal child, with no recursive
source-call hypothesis. The output window includes capture, operand, and
bounds/address bytes. The original input array survives all preparation and
emission, and its transport cursor advances by exactly three words. -/
theorem compiles (checked : Source.Expression.Indexed.Checked emitters) (literal : Source.Expression.Literal.Checked emitters)
    (sameExpression : checked.expression.function.id = literal.wrapper.source.function.id)
    (top peak length position depth capacity start : Nat) (low : Int) (active context contextLength : Value)
    (wellFormed : StateWellFormed before)
    (plain : ∀ value ∈ Expression.Literal.inputValues input work output transport.length workspace.length values.length
      length capacity depth active context contextLength, ∀ elements, value ≠ .array elements)
    (inputBacking : before.cellEntry? input = some { id := input, value := some (.array (signedI32Values transport)) })
    (outputBacking : before.cellEntry? output = some { id := output, value := some (.array (signedI32Values values)) })
    (workBacking : before.cellEntry? work = some { id := work, value := some (.array (signedI32Values workspace)) })
    (inputOutput : input ≠ output) (inputWork : input ≠ work) (outputWork : output ≠ work)
    (within : 6 < workspace.length) (current : workspace[6]? = some (top : Int))
    (watermark : workspace[2]? = some (peak : Int)) (cursor : workspace[1]? = some (start : Int))
    (inputCursor : workspace[0]? = some (position : Int)) (healthy : workspace[4]? = some 0)
    (ordered : top ≤ peak) (peakBound : peak ≤ Frame.Allocate.limit) (slotRoom : top < Frame.Allocate.limit)
    (depthBound : depth < 512) (readable : position + 3 ≤ length)
    (inputStorage : length ≤ transport.length) (inputBound : length ≤ 2147483647)
    (room : start + (saveBytes top).length + 5 + (Machine.Index.bytes true top).length ≤ capacity)
    (storage : capacity ≤ values.length) (bounded : capacity ≤ 2147483647)
    (tagWord : transport[position]? = some 0) (kindWord : transport[position + 1]? = some 1) (lowWord : transport[position + 2]? = some low)
    (argumentsResult : ArgumentsEvaluateTo emitters.pack.program.core caller arguments
      (Indexed.inputValues (.slice i32 input [] 0 transport.length) (.signed .i32 length) active (.signed .i32 depth)
        context contextLength work output workspace.length values.length capacity) before) :
    ∃ after emitted, Evaluates emitters.pack.program.core caller (.call checked.internal.source.function.id arguments)
        (.boolean true) after ∧
      after.cellEntry? input = some { id := input, value := some (.array (signedI32Values transport)) } ∧
      after.cellEntry? output = some { id := output, value := some (.array (signedI32Values emitted)) } ∧
      after.cellEntry? work = some { id := work, value := some (.array (signedI32Values (resultWorkspace workspace top peak position start))) } ∧
      (resultWorkspace workspace top peak position start)[0]? = some ((position + 3 : Nat) : Int) ∧
      Emission values start (saveBytes top ++ Encode.Immediate.bytes low ++ Machine.Index.bytes true top) emitted ∧
      Index.Emission.Refines true top (byteSlice emitted (start + (saveBytes top).length + 5) (Machine.Index.bytes true top).length) ∧
      CellEffect (writes output work) before after ∧ HeapFrame before after := by
  let inputs := Indexed.inputValues (.slice i32 input [] 0 transport.length) (.signed .i32 length) active (.signed .i32 depth)
    context contextLength work output workspace.length values.length capacity
  let params := parameterBindings (fun index : Fin 9 => inputs.get index)
  have ready := Literal.Ready.enterCall (bindings := inputs) wellFormed plain
    inputBacking outputBacking workBacking inputOutput inputWork outputWork
  obtain ⟨completed, emitted, run, finalOutput, finalWork, window, refinement, effect, heap⟩ :=
    body checked literal sameExpression top peak length position depth capacity start low active context contextLength ready.wellFormed
      ready.locals ready.plain ready.inputBacking ready.outputBacking ready.workBacking
      inputOutput inputWork outputWork within current watermark cursor inputCursor healthy ordered peakBound slotRoom
      depthBound readable inputStorage inputBound room storage bounded tagWord kindWord lowWord
  have called := checked.internal.call wellFormed argumentsResult (bindings := params) rfl run effect
  have finalInput := called.2.preserves_entry wellFormed inputBacking (by
    intro changed; rcases changed with out | work
    · exact inputOutput out
    · exact inputWork work)
  exact ⟨restoreLocals before completed, emitted, called.1, finalInput, finalOutput, finalWork,
    resultWorkspace_input within, window, refinement, called.2, HeapFrame.closeCall before params heap⟩

end Lanius.X86.Lower.Expression.Indexed.Literal
