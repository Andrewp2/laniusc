import Lanius.X86.Source.Index
import Lanius.X86.Frame.Slot
import Lanius.X86.Buffer.Emission
import Lanius.Separation.LocalCall

namespace Lanius.X86.Lower.Index.Emission

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView.Core Lanius.X86.Source Lanius.X86.Buffer

def inputValues (output work : CellId) (outputLength workLength capacity slot : Nat) (kind : Int) : List Core.Value :=
  [.slice i32 output [] 0 outputLength, .signed .i32 capacity, .slice i32 work [] 0 workLength,
    .signed .i32 slot, .signed .i32 kind]

@[simp] theorem inputValues_length : (inputValues output work outputLength workLength capacity slot kind).length = 5 := rfl

theorem inputs_not_array : ∀ index : Fin 5, ∀ elements,
    (inputValues output work outputLength workLength capacity slot kind).get index ≠ .array elements := by
  intro ⟨index, bound⟩ elements
  have cases : index = 0 ∨ index = 1 ∨ index = 2 ∨ index = 3 ∨ index = 4 := by omega
  rcases cases with rfl | rfl | rfl | rfl | rfl <;> intro same <;> cases same

/-- The routine's two caller arrays and its one fresh lexical cursor.
The input frontier protects parameters even when their scalar values happen
to equal the cursor. Array lengths are tied to the retained slice values. -/
structure Ready (state : State) (output work temporary frontier capacity slot : Nat) (kind : Int)
    (cursor : Nat) (values workspace : List Int) : Prop where
  wellFormed : StateWellFormed state
  inputs : Locals (inputValues output work values.length workspace.length capacity slot kind) frontier state
  outputBacking : state.cellEntry? output = some { id := output, value := some (.array (signedI32Values values)) }
  workBacking : state.cellEntry? work = some { id := work, value := some (.array (signedI32Values workspace)) }
  position : (Assertion.localPointsTo 5 temporary (some (.signed .i32 cursor))).holds state
  fresh : frontier ≤ temporary
  distinct : output ≠ work

theorem Ready.read (ready : Ready before output work temporary frontier capacity slot kind cursor values workspace) :
    before.local? 5 = some (.signed .i32 cursor) := Assertion.localPointsTo_local _ _ _ _ ready.position

theorem Ready.next_ne_output (ready : Ready before output work temporary frontier capacity slot kind cursor values workspace) :
    temporary ≠ output := local_cell_ne_of_distinct_value ready.read ready.outputBacking
      (by intro same; cases same) ready.position.1

theorem Ready.next_ne_work (ready : Ready before output work temporary frontier capacity slot kind cursor values workspace) :
    temporary ≠ work := local_cell_ne_of_distinct_value ready.read ready.workBacking
      (by intro same; cases same) ready.position.1

theorem Ready.afterOutput (ready : Ready before output work temporary frontier capacity slot kind cursor values workspace)
    (effect : CellEffect (CellSet.singleton output) before after)
    (backing : after.cellEntry? output = some { id := output, value := some (.array (signedI32Values emitted)) })
    (length : emitted.length = values.length) :
    Ready after output work temporary frontier capacity slot kind cursor emitted workspace := by
  refine ⟨effect.wellFormed, ?_, backing,
    effect.preserves_entry ready.wellFormed ready.workBacking (Ne.symm ready.distinct),
    effect.preserves_localPointsTo ready.wellFormed ready.position ready.next_ne_output, ready.fresh, ready.distinct⟩
  simpa only [length] using ready.inputs.store ready.wellFormed effect ready.outputBacking (fun index => inputs_not_array index _)

/-- Assign a source emitter's returned cursor without hiding its writes.
One rule covers normalization, descriptor loads, comparison, and the guard. -/
theorem Ready.assign {next : Nat} (ready : Ready before output work temporary frontier capacity slot kind cursor values workspace)
    (run : Evaluates program before right (.signed .i32 next) middle)
    (effect : CellEffect (CellSet.singleton output) before middle) (heap : HeapFrame before middle)
    (backing : middle.cellEntry? output = some { id := output, value := some (.array (signedI32Values emitted)) })
    (length : emitted.length = values.length) :
    ∃ after, Executes program before (Source.Index.setNext right) .next after ∧
      Ready after output work temporary frontier capacity slot kind next emitted workspace ∧
      CellEffect (CellSet.union (CellSet.singleton output) (CellSet.singleton temporary)) before after ∧ HeapFrame before after := by
  have middleReady := ready.afterOutput effect backing length
  obtain ⟨after, update, owned, combined, store, storeHeap, _⟩ :=
    evaluatesOwnedLocalSet ready.position run effect middleReady.position
  exact ⟨after, executesExpression update,
    ⟨store.wellFormed, middleReady.inputs.fresh effect.wellFormed store ready.fresh,
      store.preserves_entry effect.wellFormed backing (Ne.symm middleReady.next_ne_output),
      store.preserves_entry effect.wellFormed middleReady.workBacking (Ne.symm middleReady.next_ne_work),
      owned, ready.fresh, ready.distinct⟩, combined, heap.trans storeHeap⟩

/-- A workspace cursor assignment may call an emitter in its RHS. Its
resolved workspace cell survives that call, and the lexical cursor survives
the subsequent store. -/
theorem Ready.code (ready : Ready before output work temporary frontier capacity slot kind cursor values workspace)
    (constants : Source.Index.Constants program) (within : 1 < workspace.length)
    (run : Evaluates program before right (.signed .i32 result) middle)
    (effect : CellEffect (CellSet.singleton output) before middle) (heap : HeapFrame before middle)
    (backing : middle.cellEntry? output = some { id := output, value := some (.array (signedI32Values emitted)) })
    (length : emitted.length = values.length) :
    ∃ after, Executes program before (Source.Index.setCode constants right) .next after ∧
      Ready after output work temporary frontier capacity slot kind cursor emitted (workspace.set 1 result) ∧
      CellEffect (CellSet.union (CellSet.singleton output) (CellSet.singleton work)) before after ∧ HeapFrame before after := by
  have code : Evaluates program before (.constant constants.code.id) (.signed .i32 (Int.ofNat 1)) before := by
    have run := constants.code.evaluates (before := before)
    rw [constants.values.1] at run
    exact run
  obtain ⟨after, update, contents, combined, storeHeap, store⟩ := evaluatesFramedSliceStore program before middle
    workspace 2 (.constant constants.code.id) right work 1 result ready.wellFormed within
    (ready.inputs.found ⟨2, by simp⟩) code run effect (Ne.symm ready.distinct) ready.workBacking
  have middleReady := ready.afterOutput effect backing length
  refine ⟨after, executesExpression update, ⟨store.wellFormed, ?_,
    store.preserves_entry effect.wellFormed backing ready.distinct, contents,
    store.preserves_localPointsTo effect.wellFormed middleReady.position middleReady.next_ne_work,
    ready.fresh, ready.distinct⟩, combined, heap.trans storeHeap⟩
  simpa only [List.length_set] using middleReady.inputs.store effect.wellFormed store middleReady.workBacking
    (fun index => inputs_not_array index _)

end Lanius.X86.Lower.Index.Emission
