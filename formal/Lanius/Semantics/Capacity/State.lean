import Lanius.Semantics.Capacity.Value
import Lanius.Properties

namespace Lanius.Semantics.Capacity

open Lanius.Core Lanius.Properties

def stored (config : Config) (id : CellId) (entry : Value) : Value :=
  if id = config.root then
    match entry with
    | .array entries => .array (values config entries ++ config.tail)
    | other => value config other
  else if config.reachable id then value config entry else entry

def cell (config : Config) (entry : Cell) : Cell :=
  { entry with value := entry.value.map (stored config entry.id) }

def state (config : Config) (before : State) : State :=
  { before with cells := before.cells.map (cell config) }

/-- A callee can reach old buffers explicitly supplied by its caller and its
fresh locals. No active local directly aliases the enlarged backing array. -/
structure Ready (config : Config) (before : State) : Prop where
  frontier : config.boundary ≤ before.nextCell
  root : ∃ entries, before.cell? config.root = some (.array entries)
  locals : ∀ binding ∈ before.locals, config.boundary ≤ binding.2
  cells : ∀ entry ∈ before.cells, config.reachable entry.id = true →
    ∀ contents, entry.value = some contents → closed config contents = true

private theorem find_cells (config : Config) (entries : List Cell) (id : CellId) :
    (entries.map (cell config)).find? (fun entry => entry.id == id) =
      (entries.find? (fun entry => entry.id == id)).map (cell config) := by
  induction entries with
  | nil => rfl
  | cons first rest ih =>
    by_cases same : first.id = id <;> simp [cell, same, ih]

theorem cellEntry (config : Config) (before : State) (id : CellId) :
    (state config before).cellEntry? id = (before.cellEntry? id).map (cell config) :=
  find_cells config before.cells id

theorem cellValue (config : Config) (before : State) (id : CellId) :
    (state config before).cell? id = (before.cell? id).map (stored config id) := by
  simp only [State.cell?, cellEntry]
  cases found : before.cellEntry? id with
  | none => rfl
  | some entry =>
    have same : entry.id = id := by simpa using List.find?_some found
    cases entry.value <;> simp [cell, same]

theorem stored_reachable (config : Config) {id : CellId} (reachable : config.reachable id = true) (different : id ≠ config.root)
    (entry : Value) : stored config id entry = value config entry := by simp [stored, different, reachable]

theorem stored_unreachable {id : CellId} (valid : config.Valid) (unreachable : config.reachable id = false)
    (entry : Value) : stored config id entry = entry := by
  have different : id ≠ config.root := by
    intro same
    subst id
    simp [Config.reachable, valid.included] at unreachable
  simp [stored, different, unreachable]

theorem Ready.localCell {id : VarId} {root : CellId} (ready : Ready config before) (found : before.cellId? id = some root) : config.boundary ≤ root := by
  obtain ⟨binding, selected, same⟩ := Option.map_eq_some_iff.mp found
  exact same ▸ ready.locals binding (List.mem_of_find?_eq_some selected)

theorem Ready.cellClosed {root : CellId} (ready : Ready config before) (reachable : config.reachable root = true)
    (found : before.cell? root = some contents) : closed config contents = true := by
  obtain ⟨entry, selected, stored⟩ := Option.bind_eq_some_iff.mp found
  have same : entry.id = root := by simpa using List.find?_some selected
  exact ready.cells entry (List.mem_of_find?_eq_some selected) (same.symm ▸ reachable) contents stored

theorem Ready.localClosed {id : VarId} (ready : Ready config before) (found : before.local? id = some contents) :
    closed config contents = true := by
  obtain ⟨root, selected, contents⟩ := Option.bind_eq_some_iff.mp found
  exact ready.cellClosed (by simp [Config.reachable, ready.localCell selected]) contents

theorem localValue (valid : config.Valid) (ready : Ready config before) (id : VarId) :
    (state config before).local? id = (before.local? id).map (value config) := by
  simp only [State.local?, show (state config before).cellId? id = before.cellId? id from rfl]
  cases found : before.cellId? id with
  | none => rfl
  | some root =>
    have lower := ready.localCell found
    have different : root ≠ config.root := Ne.symm (Nat.ne_of_lt (Nat.lt_of_lt_of_le valid.old lower))
    simp only [Option.bind_some, cellValue]
    cases before.cell? root <;> simp only [Option.map, stored_reachable config (by simp [Config.reachable, lower]) different]

theorem bindCell (valid : config.Valid) (before : State) (frontier : config.boundary ≤ before.nextCell)
    (id : VarId) (entry : Option Value) :
    state config (before.bindCell id entry) = (state config before).bindCell id (entry.map (value config)) := by
  have different : before.nextCell ≠ config.root := Ne.symm (Nat.ne_of_lt (Nat.lt_of_lt_of_le valid.old frontier))
  cases entry <;> simp [state, State.bindCell, cell, stored, different, Config.reachable, frontier]

theorem Ready.bindCell (valid : config.Valid) (ready : Ready config before) (id : VarId) (entry : Option Value)
    (entryClosed : ∀ contents, entry = some contents → closed config contents = true) :
    Ready config (before.bindCell id entry) := by
  refine ⟨Nat.le_trans ready.frontier (Nat.le_succ _), ?_, ?_, ?_⟩
  · obtain ⟨entries, found⟩ := ready.root
    refine ⟨entries, ?_⟩
    have kept := bindCell_preserves_old_cell before id entry config.root (Nat.lt_of_lt_of_le valid.old ready.frontier)
    simpa only [State.cell?, kept] using found
  · intro binding member
    rcases List.mem_cons.mp member with rfl | old
    · exact ready.frontier
    · exact ready.locals binding old
  · intro stored member reachable contents found
    rcases List.mem_append.mp member with old | fresh
    · exact ready.cells stored old reachable contents found
    · have same : stored = { id := before.nextCell, value := entry } := by simpa using fresh
      subst stored
      exact entryClosed contents found

theorem Ready.bindLocal (valid : config.Valid) (ready : Ready config before) (id : VarId) (entry : Value)
    (entryClosed : closed config entry = true) : Ready config (before.bindLocal id entry) :=
  ready.bindCell valid id (some entry) (by intro contents same; cases same; exact entryClosed)

theorem Ready.clearLocals (ready : Ready config before) : Ready config { before with locals := [] } :=
  ⟨ready.frontier, ready.root, by simp, ready.cells⟩

theorem Ready.restoreLocals (ready : Ready config after) (caller : Ready config before) :
    Ready config (restoreLocals before after) :=
  ⟨ready.frontier, ready.root, caller.locals, ready.cells⟩

theorem restore (config : Config) (caller after : State) :
    state config (restoreLocals caller after) = restoreLocals (state config caller) (state config after) := rfl

theorem state_wellFormed (config : Config) (wellFormed : StateWellFormed before) : StateWellFormed (state config before) := by
  constructor
  · exact wellFormed.heapWellFormed
  · intro left leftMember right rightMember sameId
    obtain ⟨oldLeft, oldLeftMember, rfl⟩ := List.mem_map.mp leftMember
    obtain ⟨oldRight, oldRightMember, rfl⟩ := List.mem_map.mp rightMember
    exact congrArg (cell config) (wellFormed.cellIdsUnique oldLeft oldLeftMember oldRight oldRightMember sameId)
  · intro entry member
    obtain ⟨old, oldMember, rfl⟩ := List.mem_map.mp member
    exact wellFormed.cellIdsBelowNext old oldMember
  · intro binding member
    obtain ⟨entry, cellMember, same⟩ := wellFormed.localsReferenceCells binding member
    exact ⟨cell config entry, List.mem_map.mpr ⟨entry, cellMember, rfl⟩, same⟩

end Lanius.Semantics.Capacity
