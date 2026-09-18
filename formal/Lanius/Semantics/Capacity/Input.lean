import Lanius.Semantics.Capacity.Storage
import Lanius.Semantics.Capacity.Execution.Arguments

namespace Lanius.Semantics.Capacity
open Lanius.Core Lanius.Properties

/-- Caller data for removing unused capacity before applying a logical-buffer
proof. Only explicitly selected old buffers are interpreted by transport;
unrelated historical caller cells may contain arbitrary values. -/
structure Input (before : State) where
  root : CellId
  roots : CellId → Bool
  contents : List Value
  tail : List Value
  included : roots root = true
  source : before.cellEntry? root = some { id := root, value := some (.array (contents ++ tail)) }
  contentsPlain : plains contents = true
  buffersPlain : ∀ id, roots id = true → ∀ entry, before.cell? id = some entry → plain entry = true

def Input.config (input : Input before) : Config := ⟨input.root, before.nextCell, input.roots, input.tail⟩

def Input.logical (input : Input before) : State :=
  { before with cells := replaceCell before.cells input.root (.array input.contents) }

theorem Input.assigned (input : Input before) : before.assignCell input.root (.array input.contents) = some input.logical := by
  simp [State.assignCell, input.source, Input.logical]

theorem Input.valid (input : Input before) (wellFormed : StateWellFormed before) : input.config.Valid :=
  ⟨found_cell_is_below_next before input.root _ wellFormed input.source, input.included⟩

theorem Input.logical_wellFormed (input : Input before) (wellFormed : StateWellFormed before) : StateWellFormed input.logical :=
  assignCell_preserves_well_formed wellFormed input.assigned

theorem Input.logical_source (input : Input before) :
    input.logical.cellEntry? input.root = some { id := input.root, value := some (.array input.contents) } :=
  assignCell_finds_assigned input.assigned

theorem Input.logical_other (input : Input before) {id : CellId} (different : id ≠ input.root) :
    input.logical.cellEntry? id = before.cellEntry? id := assignCell_preserves_other input.assigned different

private theorem member_lookup (wellFormed : StateWellFormed before) (member : entry ∈ before.cells) :
    before.cellEntry? entry.id = some entry := by
  have present : (before.cellEntry? entry.id).isSome = true := List.find?_isSome.mpr ⟨entry, member, by simp⟩
  cases found : before.cellEntry? entry.id with
  | none => simp [found] at present
  | some selected =>
    have same : selected.id = entry.id := by simpa using List.find?_some found
    have equal := wellFormed.cellIdsUnique selected (List.mem_of_find?_eq_some found) entry member same
    subst selected
    rfl

theorem Input.restored (input : Input before) (wellFormed : StateWellFormed before) : state input.config input.logical = before := by
  have cells : (replaceCell before.cells input.root (.array input.contents)).map (cell input.config) = before.cells := by
    rw [replaceCell_eq_map, List.map_map]
    apply Eq.trans ?_ (List.map_id before.cells)
    apply List.map_congr_left
    intro entry member
    have found := member_lookup wellFormed member
    have below := wellFormed.cellIdsBelowNext entry member
    by_cases selected : entry.id = input.root
    · have equal : entry = { id := input.root, value := some (.array (input.contents ++ input.tail)) } :=
        Option.some.inj ((selected ▸ found).symm.trans input.source)
      subst entry
      simp only [Function.comp_apply, beq_self_eq_true, ↓reduceIte, cell, Option.map_some, stored,
        Input.config, plains_fixed _ _ input.contentsPlain, id_eq]
    · simp only [Function.comp_apply, beq_iff_eq, selected, ↓reduceIte, id_eq]
      by_cases chosen : input.roots entry.id = true
      · have reachable : input.config.reachable entry.id = true := by simp [Config.reachable, Input.config, chosen]
        cases entry with
        | mk entryId contents =>
          cases contents with
          | none => rfl
          | some contents =>
            have contentPlain := input.buffersPlain entryId chosen contents (by simp [State.cell?, found])
            simp only [cell, Option.map_some, stored_reachable input.config reachable selected, plain_fixed _ _ contentPlain]
      · have unreachable : input.config.reachable entry.id = false := by
          simp [Config.reachable, Input.config, chosen, Nat.not_le_of_lt below]
        cases entry with
        | mk entryId contents =>
          cases contents <;> simp only [cell, Option.map, stored_unreachable (input.valid wellFormed) unreachable]
  cases before
  simp only [state, Input.logical] at cells ⊢
  rw [cells]

theorem Input.ready (input : Input before) (wellFormed : StateWellFormed before) :
    Ready input.config { input.logical with locals := [] } := by
  refine ⟨Nat.le_refl _, ⟨input.contents, ?_⟩, by simp, ?_⟩
  · exact congrArg (fun entry : Option Cell => entry.bind Cell.value) input.logical_source
  · intro entry member reachable contents found
    have logicalWF := input.logical_wellFormed wellFormed
    have below := logicalWF.cellIdsBelowNext entry member
    change entry.id < before.nextCell at below
    have chosen : input.roots entry.id = true := by
      simpa only [Config.reachable, Input.config, Input.logical, Nat.not_le_of_lt below, decide_false, Bool.or_false] using reachable
    have lookup : input.logical.cell? entry.id = some contents := by
      simp [State.cell?, member_lookup logicalWF member, found]
    by_cases selected : entry.id = input.root
    · have same : contents = .array input.contents := Option.some.inj (lookup.symm.trans (by
        simp only [State.cell?, selected, input.logical_source, Option.bind_some]))
      subst contents
      exact plains_closed input.config input.contents input.contentsPlain
    · have oldLookup : before.cell? entry.id = some contents := by
        simpa only [State.cell?, input.logical_other selected] using lookup
      exact plain_closed input.config contents (input.buffersPlain entry.id chosen contents oldLookup)

end Lanius.Semantics.Capacity
