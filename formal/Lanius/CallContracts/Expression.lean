import Lanius.CallContracts.CellSpec
import Lanius.Separation.SliceStore

namespace Lanius.CallContracts

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation

/-- The expression's input bindings are outside its write footprint. This
protects cell identities, not just the numerical values of the inputs. -/
structure LocalFrame (values : List Value) (writes : CellSet) (state : State) : Prop where
  reads : ∀ index (within : index < values.length), state.local? index = some values[index]
  untouched : ∀ index, index < values.length → ∀ cell, state.cellId? index = some cell → ¬ writes cell

theorem LocalFrame.preserved (frame : LocalFrame values writes before) (wellFormed : StateWellFormed before)
    (effect : CellEffect writes before after) : LocalFrame values writes after := by
  refine ⟨fun index within => effect.preserves_local wellFormed (frame.reads index within) (frame.untouched index within), ?_⟩
  intro index within cell found
  exact frame.untouched index within cell (by simpa only [State.cellId?, effect.locals] using found)

theorem LocalFrame.empty (reads : ∀ index (within : index < values.length), before.local? index = some values[index]) :
    LocalFrame values CellSet.empty before := ⟨reads, by simp [CellSet.empty]⟩

theorem LocalFrame.cell (cell : CellId) (original : Value)
    (reads : ∀ index (within : index < values.length), before.local? index = some values[index])
    (backing : before.cellEntry? cell = some ⟨cell, some original⟩)
    (plain : ∀ value, value ∈ values → value ≠ original) :
    LocalFrame values (CellSet.singleton cell) before :=
  ⟨reads, fun index within _ found => local_cell_ne_of_distinct_value (reads index within) backing
    (plain values[index] (List.getElem_mem within)) found⟩

/-- Total expression and argument contracts. Preconditions and postconditions
are ordinary state predicates; the shared rules compose actual evaluations,
termination, cell effects, and the heap frame, without interpreting callees. -/
def ExprSpec (program : Program) (locals : List Value) (writes : CellSet) (expression : Expr) (value : Value)
    (pre post : State → Prop) : Prop :=
  ∀ before, StateWellFormed before → LocalFrame locals writes before → pre before →
    ∃ after, Evaluates program before expression value after ∧ post after ∧ CellEffect writes before after ∧ HeapFrame before after

def ArgsSpec (program : Program) (locals : List Value) (writes : CellSet) (expressions : List Expr) (values : List Value)
    (pre post : State → Prop) : Prop :=
  ∀ before, StateWellFormed before → LocalFrame locals writes before → pre before →
    ∃ after, ArgumentsEvaluateTo program before expressions values after ∧ post after ∧ CellEffect writes before after ∧ HeapFrame before after

theorem ExprSpec.pure (evaluate : ∀ before, LocalFrame locals writes before → Evaluates program before expression value before) :
    ExprSpec program locals writes expression value pre pre := by
  intro before wellFormed frame held
  exact ⟨before, evaluate before frame, held, CellEffect.refl wellFormed, HeapFrame.refl before⟩

theorem ArgsSpec.nil : ArgsSpec program locals writes [] [] pre pre := by
  intro before wellFormed _ held
  exact ⟨before, .nil _ _, held, CellEffect.refl wellFormed, HeapFrame.refl before⟩

theorem ArgsSpec.cons (head : ExprSpec program locals writes expression value pre middle)
    (tail : ArgsSpec program locals writes expressions values middle post) :
    ArgsSpec program locals writes (expression :: expressions) (value :: values) pre post := by
  intro before wellFormed frame held
  obtain ⟨next, first, ready, effect, heap⟩ := head before wellFormed frame held
  obtain ⟨after, last, result, effects, heaps⟩ := tail next effect.wellFormed (frame.preserved wellFormed effect) ready
  exact ⟨after, .cons first last, result, effect.trans effects, heap.trans heaps⟩

theorem ExprSpec.call (arguments : ArgsSpec program locals writes expressions values pre requires)
    (callee : CellSpec program function values value requires (fun _ after => post after) footprint)
    (subset : CellSet.Subset footprint writes) :
    ExprSpec program locals writes (.call function expressions) value pre post := by
  intro before wellFormed frame held
  obtain ⟨next, args, ready, effect, heap⟩ := arguments before wellFormed frame held
  obtain ⟨after, run, result, effects, heaps⟩ := callee.call effect.wellFormed args ready
  exact ⟨after, run, result, effect.trans (effects.weaken subset), heap.trans heaps⟩

end Lanius.CallContracts
