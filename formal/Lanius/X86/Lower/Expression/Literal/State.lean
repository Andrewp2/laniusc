import Lanius.X86.Source.Expression.Literal
import Lanius.X86.Buffer.Emission

namespace Lanius.X86.Lower.Expression.Literal

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView.Core Lanius.X86.Source Lanius.X86.Buffer

def writes (output work : CellId) : CellSet := CellSet.union (CellSet.singleton output) (CellSet.singleton work)

def inputValues (input work output inputLength workLength outputLength length capacity depth : Nat)
    (active context contextLength : Value) : List Value :=
  [.slice i32 input [] 0 inputLength, .signed .i32 length, .slice i32 work [] 0 workLength,
    .slice i32 output [] 0 outputLength, .signed .i32 capacity, active, .signed .i32 depth, context, contextLength]

/-- Local values and the three source compiler arrays. The transport is
read-only; only workspace and emitted bytes may change between phases. -/
structure Ready (state : State) (bindings : List Value) (frontier input output work : Nat)
    (transport emitted workspace : List Int) : Prop where
  wellFormed : StateWellFormed state
  locals : Locals bindings frontier state
  plain : ∀ value ∈ bindings, ∀ elements, value ≠ .array elements
  inputBacking : state.cellEntry? input = some { id := input, value := some (.array (signedI32Values transport)) }
  outputBacking : state.cellEntry? output = some { id := output, value := some (.array (signedI32Values emitted)) }
  workBacking : state.cellEntry? work = some { id := work, value := some (.array (signedI32Values workspace)) }
  inputOutput : input ≠ output
  inputWork : input ≠ work
  outputWork : output ≠ work

/-- Enter a source call once: parameters get fresh cells while all three
compiler buffers retain their contents and distinct identities. -/
theorem Ready.enterCall {bindings : List Value} (wellFormed : StateWellFormed before)
    (plain : ∀ value ∈ bindings, ∀ elements, value ≠ .array elements)
    (inputBacking : before.cellEntry? input = some { id := input, value := some (.array (signedI32Values transport)) })
    (outputBacking : before.cellEntry? output = some { id := output, value := some (.array (signedI32Values values)) })
    (workBacking : before.cellEntry? work = some { id := work, value := some (.array (signedI32Values workspace)) })
    (inputOutput : input ≠ output) (inputWork : input ≠ work) (outputWork : output ≠ work) :
    let callee := enterCall before (parameterBindings (fun index : Fin bindings.length => bindings.get index))
    Ready callee bindings callee.nextCell input output work transport values workspace := by
  let params := parameterBindings (fun index : Fin bindings.length => bindings.get index)
  have calleeWF := enterCall_preserves_wellFormed wellFormed (bindings := params)
  have preserve (cell : CellId) {contents : Option Value}
      (found : before.cellEntry? cell = some { id := cell, value := contents }) :=
    ((enterCall_effect before params).oldCells cell
      (StateWellFormed.cell_lt_next_of_entry wellFormed found) (by simp [CellSet.empty])).trans found
  exact ⟨calleeWF, Locals.ofReads calleeWF (fun index => enterCall_parameterBindings_matches wellFormed index),
    plain, preserve input inputBacking, preserve output outputBacking, preserve work workBacking,
    inputOutput, inputWork, outputWork⟩

theorem Ready.read (ready : Ready before bindings frontier input output work transport emitted workspace)
    (index : Nat) (found : bindings[index]? = some value) : before.local? index = some value := by
  obtain ⟨bound, entry⟩ := List.getElem?_eq_some_iff.mp found
  simpa only [List.get_eq_getElem, entry] using ready.locals.found ⟨index, bound⟩

theorem Ready.entry (ready : Ready before bindings frontier input output work transport emitted workspace)
    (index : Nat) (bound : index < bindings.length) (found : before.local? index = some value) :
    bindings[index]? = some value := by
  have same := (ready.locals.found ⟨index, bound⟩).symm.trans found
  simpa only [Option.some.injEq, List.get_eq_getElem, List.getElem?_eq_getElem bound] using same

theorem Ready.frame (ready : Ready before bindings frontier input output work transport emitted workspace)
    (effect : CellEffect (writes output work) before after)
    (nextOutput : after.cellEntry? output = some { id := output, value := some (.array (signedI32Values nextEmitted)) })
    (nextWork : after.cellEntry? work = some { id := work, value := some (.array (signedI32Values nextWorkspace)) }) :
    Ready after bindings frontier input output work transport nextEmitted nextWorkspace := by
  refine ⟨effect.wellFormed, ?_, ready.plain,
    effect.preserves_entry ready.wellFormed ready.inputBacking (by
      intro changed; rcases changed with out | work
      · exact ready.inputOutput out
      · exact ready.inputWork work), nextOutput, nextWork, ready.inputOutput, ready.inputWork, ready.outputWork⟩
  apply ready.locals.frame ready.wellFormed effect
  intro index cell binding changed
  have plain := ready.plain _ (List.get_mem bindings index)
  rcases changed with out | work
  · exact local_cell_ne_of_distinct_value (ready.locals.found index) ready.outputBacking (plain _) binding out
  · exact local_cell_ne_of_distinct_value (ready.locals.found index) ready.workBacking (plain _) binding work

theorem Ready.empty (ready : Ready before bindings frontier input output work transport emitted workspace)
    (effect : CellEffect CellSet.empty before after) :
    Ready after bindings frontier input output work transport emitted workspace :=
  ready.frame (effect.weaken CellSet.empty_subset)
    (effect.empty_preserves_entry ready.wellFormed ready.outputBacking)
    (effect.empty_preserves_entry ready.wellFormed ready.workBacking)

theorem Ready.bind (ready : Ready before bindings frontier input output work transport emitted workspace)
    (id : VarId) (fresh : bindings.length ≤ id) (value : Value) :
    Ready (before.bindLocal id value) bindings frontier input output work transport emitted workspace := by
  have preserve (cell : CellId) {contents : Option Value} (found : before.cellEntry? cell = some { id := cell, value := contents }) :=
    ((bindLocal_effect before id value).oldCells cell
      (StateWellFormed.cell_lt_next_of_entry ready.wellFormed found) (by simp [CellSet.empty])).trans found
  exact ⟨bindLocal_preserves_well_formed before id value ready.wellFormed,
    ready.locals.bind ready.wellFormed fresh value, ready.plain, preserve input ready.inputBacking,
    preserve output ready.outputBacking, preserve work ready.workBacking, ready.inputOutput, ready.inputWork, ready.outputWork⟩

theorem Ready.push (ready : Ready before bindings frontier input output work transport emitted workspace)
    (value : Value) (plain : ∀ elements, value ≠ .array elements) :
    Ready (before.bindLocal bindings.length value) (bindings ++ [value])
      (before.bindLocal bindings.length value).nextCell input output work transport emitted workspace := by
  have preserve (cell : CellId) {contents : Option Value} (found : before.cellEntry? cell = some { id := cell, value := contents }) :=
    ((bindLocal_effect before bindings.length value).oldCells cell
      (StateWellFormed.cell_lt_next_of_entry ready.wellFormed found) (by simp [CellSet.empty])).trans found
  refine ⟨bindLocal_preserves_well_formed before bindings.length value ready.wellFormed,
    ready.locals.push ready.wellFormed value, ?_, preserve input ready.inputBacking,
    preserve output ready.outputBacking, preserve work ready.workBacking, ready.inputOutput, ready.inputWork, ready.outputWork⟩
  intro candidate member elements
  simp only [List.mem_append, List.mem_singleton] at member
  rcases member with old | rfl
  · exact ready.plain candidate old elements
  · exact plain elements

theorem Ready.field (ready : Ready before bindings frontier input output work transport emitted workspace)
    (constant : IntegerConstant program) (index : Nat) (identity : constant.value = index)
    (slice : before.local? 2 = some (.slice i32 work [] 0 workspace.length))
    (found : workspace[index]? = some value) :
    Evaluates program before (Source.Expression.Literal.field constant.id) (.signed .i32 value) before := by
  have bound : index < workspace.length := by
    by_cases inside : index < workspace.length
    · exact inside
    · rw [List.getElem?_eq_none (by omega)] at found
      cases found
  have literal := constant.evaluates (before := before)
  rw [identity] at literal
  have run := evaluatesSignedI32SliceIndex program before before before workspace (Source.read 2) (.constant constant.id)
    work index bound (local_evaluates program slice) literal ready.workBacking
  have entry : workspace.get ⟨index, bound⟩ = value := by
    simpa only [List.getElem?_eq_getElem bound, Option.some.injEq, List.get_eq_getElem] using found
  simpa only [Source.Expression.Literal.field, entry] using run

theorem Ready.take (checked : Source.Take.Checked program)
    (ready : Ready before bindings frontier input output work transport emitted workspace)
    (length position : Nat)
    (inputLocal : before.local? 0 = some (.slice i32 input [] 0 transport.length))
    (lengthLocal : before.local? 1 = some (.signed .i32 length))
    (workLocal : before.local? 2 = some (.slice i32 work [] 0 workspace.length))
    (current : workspace[0]? = some (position : Int))
    (readable : position < length) (storage : length ≤ transport.length) (bounded : length ≤ 2147483647)
    (word : transport[position]? = some value) :
    ∃ after, Evaluates program.core before (.call checked.internal.source.function.id Source.Expression.Literal.takeArguments)
        (.signed .i32 value) after ∧
      Ready after bindings frontier input output work transport emitted (workspace.set 0 (position + 1 : Nat)) ∧
      CellEffect (writes output work) before after ∧ HeapFrame before after := by
  have arguments : ArgumentsEvaluateTo program.core before Source.Expression.Literal.takeArguments
      (Frame.Take.inputValues input work transport.length length workspace.length) before :=
    .cons (local_evaluates _ inputLocal) (.cons (local_evaluates _ lengthLocal)
      (.cons (local_evaluates _ workLocal) (.nil _ _)))
  obtain ⟨after, run, _, nextWork, effect, heap⟩ := Frame.Take.succeeds checked length position
    ready.wellFormed ready.inputWork ready.inputBacking ready.workBacking current readable storage bounded word arguments
  have nextOutput := effect.preserves_entry ready.wellFormed ready.outputBacking ready.outputWork
  have total := effect.weaken (larger := writes output work) CellSet.subset_union_right
  exact ⟨after, run, ready.frame total nextOutput nextWork, total, heap⟩

end Lanius.X86.Lower.Expression.Literal
