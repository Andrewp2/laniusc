import Lanius.Semantics.WellFormed

namespace Lanius.Semantics

open Lanius.Core

/-- Cell identity and allocation are independent of mutable values and the
    lexical, native-memory and host-effect components of a state. -/
structure CellInventory where
  ids : List CellId
  next : CellId

def State.cellInventory (state : State) : CellInventory :=
  ⟨state.cells.map Cell.id, state.nextCell⟩

/-- Existing identities survive in order; precisely the intervening fresh
    identities are appended. This does not require the input to be valid. -/
def CellInventory.Extends (before after : CellInventory) : Prop :=
  ∃ count, after.ids = before.ids ++ List.range' before.next count ∧
    after.next = before.next + count

theorem CellInventory.Extends.refl (inventory : CellInventory) :
    inventory.Extends inventory := ⟨0, by simp, by simp⟩

theorem CellInventory.Extends.trans {before middle after : CellInventory} (first : before.Extends middle)
    (second : middle.Extends after) : before.Extends after := by
  obtain ⟨left, ids, next⟩ := first
  obtain ⟨right, ids', next'⟩ := second
  refine ⟨left + right, ?_, ?_⟩
  · rw [ids', ids, List.append_assoc, next, List.range'_append_1]
  · rw [next', next, Nat.add_assoc]

theorem CellInventory.Extends.append (inventory : CellInventory) :
    inventory.Extends ⟨inventory.ids ++ [inventory.next], inventory.next + 1⟩ :=
  ⟨1, by simp [List.range'], rfl⟩

theorem State.cellInventory_bindCell (state : State) (id : VarId) (value : Option Value) :
    state.cellInventory.Extends (state.bindCell id value).cellInventory := by
  simpa [State.cellInventory, State.bindCell] using CellInventory.Extends.append state.cellInventory

theorem State.cellInventory_bindLocal (state : State) (id : VarId) (value : Value) :
    state.cellInventory.Extends (state.bindLocal id value).cellInventory :=
  state.cellInventory_bindCell id (some value)

theorem State.cellInventory_bindUninitialized (state : State) (id : VarId) :
    state.cellInventory.Extends (state.bindUninitialized id).cellInventory :=
  state.cellInventory_bindCell id none

theorem State.cellInventory_bindLocals (state : State) (bindings : List (VarId × Value)) :
    state.cellInventory.Extends (state.bindLocals bindings).cellInventory := by
  induction bindings generalizing state with
  | nil => exact CellInventory.Extends.refl state.cellInventory
  | cons binding rest ih =>
    exact (state.cellInventory_bindLocal binding.1 binding.2).trans (ih _)

theorem State.cellInventory_allocateTemporary (state : State) (value : Value) :
    state.cellInventory.Extends (state.allocateTemporary value).2.cellInventory := by
  simpa [State.cellInventory, State.allocateTemporary] using CellInventory.Extends.append state.cellInventory

theorem replaceCell_ids (cells : List Cell) (id : CellId) (value : Value) :
    (replaceCell cells id value).map Cell.id = cells.map Cell.id := by
  induction cells with
  | nil => rfl
  | cons cell cells ih => simp only [replaceCell]; split <;> simp [ih]

theorem CellInventory.Extends.frontier {before after : CellInventory} (extension : before.Extends after) :
    before.next ≤ after.next := by
  obtain ⟨_, _, next⟩ := extension
  rw [next]
  exact Nat.le_add_right _ _

theorem CellInventory.Extends.retains {before after : CellInventory} (extension : before.Extends after) :
    before.ids <+: after.ids := by
  obtain ⟨_, ids, _⟩ := extension
  rw [ids]
  exact List.prefix_append _ _

/-- A retained cell may have a different value; its lookup cannot disappear. -/
theorem CellInventory.Extends.retainsCell {before after : State} {id : CellId} {entry : Cell}
    (extension : before.cellInventory.Extends after.cellInventory)
    (found : before.cellEntry? id = some entry) : (after.cellEntry? id).isSome := by
  have old : id ∈ before.cellInventory.ids := List.mem_map.mpr
    ⟨entry, List.mem_of_find?_eq_some found, by simpa using List.find?_some found⟩
  obtain ⟨cell, member, same⟩ := List.mem_map.mp (extension.retains.sublist.subset old)
  exact List.find?_isSome.mpr ⟨cell, member, by simp [same]⟩

theorem CellInventory.Extends.cellsWellFormed
    {before after : State}
    (extension : before.cellInventory.Extends after.cellInventory)
    (formed : before.CellsWellFormed) : after.CellsWellFormed := by
  obtain ⟨count, ids, next⟩ := extension
  simp only [State.cellInventory] at ids next
  intro cell member
  have idMember : cell.id ∈ after.cells.map Cell.id := List.mem_map.mpr ⟨cell, member, rfl⟩
  rw [ids] at idMember
  rcases List.mem_append.mp idMember with old | fresh
  · obtain ⟨oldCell, member, same⟩ := List.mem_map.mp old
    have bound := formed oldCell member
    change after.nextCell = before.nextCell + count at next
    change oldCell.id = cell.id at same
    rw [next, ← same]
    exact Nat.lt_of_lt_of_le bound (Nat.le_add_right _ _)
  · have bound := (List.mem_range'_1.mp fresh).2
    rw [next]
    exact bound

theorem CellInventory.Extends.unique
    {before after : State}
    (extension : before.cellInventory.Extends after.cellInventory)
    (formed : before.CellsWellFormed) (unique : (before.cells.map Cell.id).Nodup) :
    (after.cells.map Cell.id).Nodup := by
  obtain ⟨count, ids, _⟩ := extension
  simp only [State.cellInventory] at ids
  rw [ids]
  apply List.nodup_append.mpr
  refine ⟨unique, List.nodup_range', ?_⟩
  intro id old other fresh same
  obtain ⟨cell, member, rfl⟩ := List.mem_map.mp old
  have below := formed cell member
  have above := (List.mem_range'_1.mp fresh).1
  exact Nat.not_le_of_lt below (same ▸ above)

end Lanius.Semantics
