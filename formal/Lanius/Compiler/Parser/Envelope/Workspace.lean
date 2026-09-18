import Lanius.Compiler.Parser.Bounds

namespace Lanius.Compiler.Parser.Envelope

/-- Position, production, dot, and origin. Certificate items deliberately
omit state IDs and derivation backpointers. -/
abbrev Item := Nat × Nat × Nat × Nat

def item (position : Nat) (key : StateKey) : Item :=
  (position, key.production, key.dot, key.origin)

def state (entry : Item) : EarleyState :=
  { position := entry.1, production := entry.2.1, dot := entry.2.2.1,
    origin := entry.2.2.2, previous := none, child := .none }

/-- A logical chart used only to state the certificate's meaning. The
executable checker uses indexed item membership, not these list scans. -/
def workspace (items : List Item) : LogicalWorkspace where
  states := items.map state
  chart position := (List.range items.length).filter fun id =>
    (items[id]?.map Prod.fst) == some position

theorem chartSound (items : List Item) : ChartSound (workspace items) := by
  intro position id listed
  obtain ⟨bound, located⟩ := List.mem_filter.mp listed
  have bound := List.mem_range.mp bound
  simp only [List.getElem?_eq_getElem bound, Option.map_some, beq_iff_eq,
    Option.some.injEq] at located
  exact ⟨state items[id], by simp [LogicalWorkspace.state?, workspace, bound], located⟩

theorem contains_iff : (workspace items).containsKey position key ↔ item position key ∈ items := by
  constructor
  · rintro ⟨id, foundState, listed, found, sameKey⟩
    obtain ⟨bound, located⟩ := List.mem_filter.mp listed
    have bound := List.mem_range.mp bound
    simp only [List.getElem?_eq_getElem bound, Option.map_some, beq_iff_eq,
      Option.some.injEq] at located
    have foundEq : state items[id] = foundState := by
      simpa [LogicalWorkspace.state?, workspace, bound] using found
    subst foundState
    have sameItem : item position key = items[id] := by
      rw [← sameKey, ← located]
      rfl
    rw [sameItem]
    exact List.getElem_mem bound
  · intro member
    obtain ⟨id, bound, found⟩ := List.mem_iff_getElem.mp member
    refine ⟨id, state (item position key), ?_, ?_, rfl⟩
    · apply List.mem_filter.mpr
      exact ⟨List.mem_range.mpr bound, by simp [List.getElem?_eq_getElem bound, found, item]⟩
    · simp [LogicalWorkspace.state?, workspace, bound, found]

@[simp] theorem states_length : (workspace items).states.length = items.length := by
  simp [workspace]

end Lanius.Compiler.Parser.Envelope
