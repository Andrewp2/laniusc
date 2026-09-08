import Lanius.Separation

namespace Lanius.Separation

open Lanius.Core Lanius.Semantics Lanius.Properties

/-- A logical write footprint with caller-local and host-world preservation.
Unlike `ModifiesOnly`, this does not assert heap/view identity: helpers may
introduce borrowed storage. Raw-memory claims require separate evidence. -/
structure CellEffect (writes : CellSet) (before after : State) : Prop where
  wellFormed : StateWellFormed after
  locals : after.locals = before.locals
  world : after.world = before.world
  oldCells : ∀ cell, cell < before.nextCell → ¬ writes cell → after.cellEntry? cell = before.cellEntry? cell
  nextCell : before.nextCell ≤ after.nextCell
  domain : CellDomainExtension before after

theorem CellEffect.refl (wellFormed : StateWellFormed before) : CellEffect writes before before :=
  ⟨wellFormed, rfl, rfl, fun _ _ _ => rfl, Nat.le_refl _, CellDomainExtension.refl _⟩

theorem CellEffect.trans (first : CellEffect writes before middle) (second : CellEffect writes middle after) :
    CellEffect writes before after := by
  refine ⟨second.wellFormed, second.locals.trans first.locals, second.world.trans first.world,
    ?_, Nat.le_trans first.nextCell second.nextCell, first.domain.trans second.domain⟩
  intro cell old untouched
  exact (second.oldCells cell (Nat.lt_of_lt_of_le old first.nextCell) untouched).trans (first.oldCells cell old untouched)

theorem CellEffect.weaken (frame : CellEffect writes before after) (subset : CellSet.Subset writes larger) :
    CellEffect larger before after := by
  refine ⟨frame.wellFormed, frame.locals, frame.world, ?_, frame.nextCell, frame.domain⟩
  intro cell old untouched
  exact frame.oldCells cell old (fun written => untouched (subset cell written))

/-- Compose phases whose live lexical scopes differ. Restoring the outer caller
does not undo their cell changes; the combined footprint and host world still
compose, and retained cell identities justify restoring the original locals. -/
theorem CellEffect.transScoped
    (first : CellEffect writes before (restoreLocals before middle))
    (second : CellEffect writes middle (restoreLocals middle after))
    (wellFormed : StateWellFormed before) :
    CellEffect writes before (restoreLocals before after) := by
  have domain : CellDomainExtension before (restoreLocals middle after) :=
    first.domain.trans ⟨second.domain.cells⟩
  refine ⟨domain.restoreLocals_wellFormed wellFormed second.wellFormed, rfl,
    second.world.trans first.world, ?_, Nat.le_trans first.nextCell second.nextCell, domain.restoreLocals⟩
  intro cell old untouched
  exact (second.oldCells cell (Nat.lt_of_lt_of_le old first.nextCell) untouched).trans
    (first.oldCells cell old untouched)

/-- Hide writes to fresh temporary cells when closing a caller scope. Only
the part of the write set below the caller's frontier needs to remain visible. -/
theorem CellEffect.narrow (frame : CellEffect writes before after)
    (visible : ∀ cell, cell < before.nextCell → writes cell → kept cell) :
    CellEffect kept before after := by
  refine ⟨frame.wellFormed, frame.locals, frame.world, ?_, frame.nextCell, frame.domain⟩
  intro cell old untouched
  exact frame.oldCells cell old (fun written => untouched (visible cell old written))

theorem CellEffect.ofModifiesOnly (effect : ModifiesOnly writes before after)
    (wellFormed : StateWellFormed after) : CellEffect writes before after :=
  ⟨wellFormed, effect.locals, effect.world, effect.oldCells, effect.nextCell, effect.domain⟩

theorem CellEffect.empty_preserves_cell (frame : CellEffect CellSet.empty before after)
    (cell : CellId) (old : cell < before.nextCell) : after.cellEntry? cell = before.cellEntry? cell :=
  frame.oldCells cell old (by simp [CellSet.empty])

theorem CellEffect.preserves_local {id : VarId} (frame : CellEffect writes before after)
    (beforeWF : StateWellFormed before) (found : before.local? id = some value)
    (untouched : ∀ cell, before.cellId? id = some cell → ¬ writes cell) :
    after.local? id = some value := by
  rw [State.local?, Option.bind_eq_some_iff] at found
  obtain ⟨cell, cellId, cellValue⟩ := found
  have old := StateWellFormed.cell_lt_next_of_local_binding id cell beforeWF cellId
  have afterId : after.cellId? id = some cell := by
    simpa only [State.cellId?, frame.locals] using cellId
  rw [State.local?, afterId]
  simpa only [Option.bind_some, State.cell?, frame.oldCells cell old (untouched cell cellId)] using cellValue

theorem CellEffect.empty_preserves_local {id : VarId} (frame : CellEffect CellSet.empty before after)
    (beforeWF : StateWellFormed before) (found : before.local? id = some value) :
    after.local? id = some value :=
  frame.preserves_local beforeWF found (by simp [CellSet.empty])

theorem CellEffect.preserves_entry (frame : CellEffect writes before after)
    (beforeWF : StateWellFormed before)
    (found : before.cellEntry? cell = some { id := cell, value := value }) (untouched : ¬ writes cell) :
    after.cellEntry? cell = some { id := cell, value := value } :=
  (frame.oldCells cell (StateWellFormed.cell_lt_next_of_entry beforeWF found) untouched).trans found

theorem CellEffect.empty_preserves_entry (frame : CellEffect CellSet.empty before after)
    (beforeWF : StateWellFormed before)
    (found : before.cellEntry? cell = some { id := cell, value := value }) :
    after.cellEntry? cell = some { id := cell, value := value } :=
  frame.preserves_entry beforeWF found (by simp [CellSet.empty])

theorem CellEffect.preserves_localPointsTo {id : VarId} (frame : CellEffect writes before after)
    (beforeWF : StateWellFormed before)
    (owned : (Assertion.localPointsTo id cell value).holds before) (untouched : ¬ writes cell) :
    (Assertion.localPointsTo id cell value).holds after := by
  refine ⟨?_, frame.preserves_entry beforeWF owned.2 untouched⟩
  simpa only [State.cellId?, frame.locals] using owned.1

/-- Close a lexical temporary after a body that may allocate borrowed storage.
The write footprint concerns pre-existing cells; fresh local cells stay hidden. -/
theorem CellEffect.closeLocal (before : State) (id : VarId) (value : Value)
    (wellFormed : StateWellFormed before)
    (frame : CellEffect writes (before.bindLocal id value) completed) :
    CellEffect writes before (restoreLocals before completed) := by
  have entered := bindLocal_effect before id value
  have domain := entered.domain.trans frame.domain
  refine ⟨domain.restoreLocals_wellFormed wellFormed frame.wellFormed, rfl,
    frame.world.trans entered.world, ?_, Nat.le_trans entered.nextCell frame.nextCell,
    domain.restoreLocals⟩
  intro cell old untouched
  exact (frame.oldCells cell (Nat.lt_of_lt_of_le old entered.nextCell) untouched).trans
    (entered.oldCells cell old (by simp [CellSet.empty]))

/-- Restore a caller after a function body with a logical write footprint. -/
theorem CellEffect.closeCall (before : State) (bindings : List (VarId × Value))
    (wellFormed : StateWellFormed before)
    (frame : CellEffect writes (enterCall before bindings) completed) :
    CellEffect writes before (restoreLocals before completed) := by
  have entered := enterCall_effect before bindings
  have domain := entered.domain.trans frame.domain
  refine ⟨domain.restoreLocals_wellFormed wellFormed frame.wellFormed, rfl,
    frame.world.trans entered.world, ?_, Nat.le_trans entered.nextCell frame.nextCell,
    domain.restoreLocals⟩
  intro cell old untouched
  exact (frame.oldCells cell (Nat.lt_of_lt_of_le old entered.nextCell) untouched).trans
    (entered.oldCells cell old (by simp [CellSet.empty]))

end Lanius.Separation
