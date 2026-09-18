import Lanius.Separation.SliceStore

namespace Lanius.X86.Buffer

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation

/-- A dense input prefix whose cells precede the emitter's temporary cells.
The frontier is about cell identity, not value inequality: a temporary cursor
may numerically equal any input without being allowed to overwrite it. -/
structure Locals (values : List Value) (frontier : Nat) (state : State) : Prop where
  found : ∀ index : Fin values.length, state.local? index.val = some (values.get index)
  below : ∀ index : Fin values.length, ∀ cell, state.cellId? index.val = some cell → cell < frontier
  frontierBound : frontier ≤ state.nextCell

theorem Locals.ofReads (wellFormed : StateWellFormed state)
    (found : ∀ index : Fin values.length, state.local? index.val = some (values.get index)) :
    Locals values state.nextCell state :=
  ⟨found, fun index cell binding => StateWellFormed.cell_lt_next_of_local_binding index.val cell wellFormed binding,
    Nat.le_refl _⟩

theorem Locals.bind {id : VarId} (inputs : Locals values frontier before)
    (wellFormed : StateWellFormed before) (fresh : values.length ≤ id) (value : Value) :
    Locals values frontier (before.bindLocal id value) := by
  have different (index : Fin values.length) : id ≠ index.val :=
    Nat.ne_of_gt (Nat.lt_of_lt_of_le index.isLt fresh)
  refine ⟨fun index => (bindLocal_preserves_other_local (boundId := id) (queriedId := index.val)
    (value := value) wellFormed (different index)).trans (inputs.found index), ?_,
    Nat.le_trans inputs.frontierBound (bindLocal_effect before id value).nextCell⟩
  intro index cell binding
  apply inputs.below index cell
  simpa only [bindLocal_preserves_other_cellId before id index.val value (different index)] using binding

theorem Locals.push (inputs : Locals values frontier before) (wellFormed : StateWellFormed before) (value : Value) :
    Locals (values ++ [value]) (before.bindLocal values.length value).nextCell
      (before.bindLocal values.length value) := by
  apply Locals.ofReads (bindLocal_preserves_well_formed before values.length value wellFormed)
  intro index
  by_cases old : index.val < values.length
  · have readOld := (inputs.bind wellFormed (Nat.le_refl _) value).found ⟨index.val, old⟩
    simpa only [List.get_eq_getElem, List.getElem_append_left old] using readOld
  · have last : index.val = values.length := by have := index.isLt; simp only [List.length_append, List.length_singleton] at this; omega
    simpa only [last, List.get_eq_getElem, List.getElem_append_right (Nat.le_refl _), Nat.sub_self,
      List.getElem_cons_zero] using bindLocal_finds_local before values.length value wellFormed

theorem Locals.frame (inputs : Locals values frontier before) (wellFormed : StateWellFormed before)
    (effect : CellEffect writes before after)
    (untouched : ∀ index : Fin values.length, ∀ cell, before.cellId? index.val = some cell → ¬ writes cell) :
    Locals values frontier after := by
  refine ⟨fun index => effect.preserves_local wellFormed (inputs.found index) (untouched index), ?_,
    Nat.le_trans inputs.frontierBound effect.nextCell⟩
  intro index cell binding
  apply inputs.below index cell
  simpa only [State.cellId?, effect.locals] using binding

theorem Locals.empty (inputs : Locals values frontier before) (wellFormed : StateWellFormed before)
    (effect : CellEffect CellSet.empty before after) : Locals values frontier after :=
  inputs.frame wellFormed effect (by simp [CellSet.empty])

theorem Locals.fresh (inputs : Locals values frontier before) (wellFormed : StateWellFormed before)
    (effect : CellEffect (CellSet.singleton temporary) before after) (newCell : frontier ≤ temporary) :
    Locals values frontier after := by
  apply inputs.frame wellFormed effect
  intro index cell binding same
  exact (Nat.ne_of_lt (Nat.lt_of_lt_of_le (inputs.below index cell binding) newCell)) same

theorem Locals.store (inputs : Locals values frontier before) (wellFormed : StateWellFormed before)
    (effect : CellEffect (CellSet.singleton output) before after)
    (backing : before.cellEntry? output = some { id := output, value := some (.array elements) })
    (notArray : ∀ index : Fin values.length, values.get index ≠ .array elements) :
    Locals values frontier after := by
  apply inputs.frame wellFormed effect
  intro index cell binding same
  exact local_cell_ne_of_distinct_value (inputs.found index) backing (notArray index) binding same

end Lanius.X86.Buffer
