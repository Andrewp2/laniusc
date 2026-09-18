import Lanius.X86.Buffer.Locals
import Lanius.CallContracts.CellSpec

namespace Lanius.X86.Buffer

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts

/-- A returned source block, with its postcondition and complete cell/heap frame. -/
def Returns (program : Program) (before : State) (body : Stmt) (value : Value)
    (post : State → Prop) (writes : CellSet) : Prop :=
  ∃ after, Executes program before body (.returned (some value)) after ∧
    post after ∧ CellEffect writes before after ∧ HeapFrame before after

/-- A read-only call followed by a fresh binding retains both the input
locals and every old cell. The initializer's execution is not a premise here. -/
structure Scope (values : List Value) (before after : State) : Prop where
  wellFormed : StateWellFormed after
  locals : Locals values after.nextCell after
  entry : ∀ {cell value}, before.cellEntry? cell = some { id := cell, value := value } →
    after.cellEntry? cell = some { id := cell, value := value }

theorem Scope.trans (first : Scope values before middle) (last : Scope next middle after) :
    Scope next before after := ⟨last.wellFormed, last.locals, fun found => last.entry (first.entry found)⟩

theorem Locals.letCall (inputs : Locals values frontier before) (wellFormed : StateWellFormed before)
    (spec : CellSpec program function arguments value)
    (evaluated : ArgumentsEvaluateTo program before expressions arguments before)
    (continuation : ∀ selected, Scope (values ++ [value]) before (selected.bindLocal values.length value) →
      Returns program (selected.bindLocal values.length value) body result
        (fun after => post (restoreLocals selected after)) writes) :
    Returns program before (.letLocal values.length type (.call function expressions) body) result post writes := by
  obtain ⟨selected, call, _, effect, heap⟩ := spec.call wellFormed evaluated
  have entered : Scope (values ++ [value]) before (selected.bindLocal values.length value) := {
    wellFormed := bindLocal_preserves_well_formed selected values.length value effect.wellFormed
    locals := (inputs.empty wellFormed effect).push effect.wellFormed value
    entry := fun found => ((bindLocal_effect selected values.length value).oldCells _
      (StateWellFormed.cell_lt_next_of_entry effect.wellFormed (effect.empty_preserves_entry wellFormed found))
      (by simp [CellSet.empty])).trans (effect.empty_preserves_entry wellFormed found) }
  obtain ⟨after, run, held, bodyEffect, bodyHeap⟩ := continuation selected entered
  exact ⟨_, executesLetLocal call run, held,
    (effect.weaken CellSet.empty_subset).trans (CellEffect.closeLocal selected values.length value effect.wellFormed bodyEffect),
    heap.trans (HeapFrame.closeLocal selected values.length value bodyHeap)⟩

end Lanius.X86.Buffer
