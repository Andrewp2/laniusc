import Lanius.Extraction.Host.ReadOnly
import Lanius.Separation.HeapFrame

namespace Lanius.Extraction.Host

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation

/-- A completed I/O command may update the host world and raw bytes, while
retaining its caller's bindings, registered buffers, allocation budget, and
all old cells outside the explicit write set. World behavior is stated by
the command's separate functional postcondition. -/
structure Effect (writes : CellSet) (before after : State) : Prop where
  wellFormed : StateWellFormed after
  locals : after.locals = before.locals
  oldCells : ∀ cell, cell < before.nextCell → ¬ writes cell → after.cellEntry? cell = before.cellEntry? cell
  nextCell : before.nextCell ≤ after.nextCell
  domain : CellDomainExtension before after
  views : after.i32ArrayViews = before.i32ArrayViews
  remaining : after.heap.remaining = before.heap.remaining

theorem Effect.ofPure (effect : ModifiesOnly writes before after) (valid : StateWellFormed after) :
    Effect writes before after :=
  ⟨valid, effect.locals, effect.oldCells, effect.nextCell, effect.domain, effect.views,
    congrArg (fun heap => heap.remaining) effect.heap⟩

theorem Effect.ofCells (effect : CellEffect writes before after) (frame : HeapFrame before after) :
    Effect writes before after :=
  ⟨effect.wellFormed, effect.locals, effect.oldCells, effect.nextCell, effect.domain, frame.views,
    congrArg (fun heap => heap.remaining) frame.heap⟩

theorem Effect.refl (valid : StateWellFormed before) : Effect writes before before :=
  ⟨valid, rfl, fun _ _ _ => rfl, Nat.le_refl _, CellDomainExtension.refl _, rfl, rfl⟩

theorem Effect.trans (first : Effect writes before middle) (second : Effect writes middle after) :
    Effect writes before after :=
  ⟨second.wellFormed, second.locals.trans first.locals,
    fun cell old kept => (second.oldCells cell (Nat.lt_of_lt_of_le old first.nextCell) kept).trans
      (first.oldCells cell old kept), Nat.le_trans first.nextCell second.nextCell,
    first.domain.trans second.domain, second.views.trans first.views, second.remaining.trans first.remaining⟩

theorem Effect.weaken (effect : Effect writes before after) (subset : CellSet.Subset writes larger) :
    Effect larger before after :=
  ⟨effect.wellFormed, effect.locals, fun cell old kept => effect.oldCells cell old (fun changed => kept (subset cell changed)),
    effect.nextCell, effect.domain, effect.views, effect.remaining⟩

theorem Effect.narrow (effect : Effect writes before after)
    (visible : ∀ cell, cell < before.nextCell → writes cell → retained cell) : Effect retained before after :=
  ⟨effect.wellFormed, effect.locals,
    fun cell old kept => effect.oldCells cell old (fun written => kept (visible cell old written)),
    effect.nextCell, effect.domain, effect.views, effect.remaining⟩

theorem Effect.closeLocal (before : State) (id : VarId) (value : Value) (valid : StateWellFormed before)
    (effect : Effect writes (before.bindLocal id value) after) : Effect writes before (restoreLocals before after) := by
  have bound := bindLocal_effect before id value
  have domain := bound.domain.trans effect.domain
  exact ⟨domain.restoreLocals_wellFormed valid effect.wellFormed, rfl,
    fun cell old kept => (effect.oldCells cell (Nat.lt_of_lt_of_le old bound.nextCell) kept).trans
      (bound.oldCells cell old (by simp [CellSet.empty])), Nat.le_trans bound.nextCell effect.nextCell,
    domain.restoreLocals, effect.views, effect.remaining⟩

theorem Effect.closeCall (before : State) (bindings : List (VarId × Value)) (valid : StateWellFormed before)
    (effect : Effect writes (enterCall before bindings) after) : Effect writes before (restoreLocals before after) := by
  have bound := enterCall_effect before bindings
  have domain := bound.domain.trans effect.domain
  exact ⟨domain.restoreLocals_wellFormed valid effect.wellFormed, rfl,
    fun cell old kept => (effect.oldCells cell (Nat.lt_of_lt_of_le old bound.nextCell) kept).trans
      (bound.oldCells cell old (by simp [CellSet.empty])), Nat.le_trans bound.nextCell effect.nextCell,
    domain.restoreLocals, effect.views.trans bound.views,
    effect.remaining.trans (congrArg (fun heap => heap.remaining) bound.heap)⟩

/-- Close a pure preparation prefix whose only changes were fresh locals.
The effectful continuation may mutate exactly the retained storage. -/
theorem Effect.closePrefix (prefixEffect : StoreEffect CellSet.empty before middle)
    (valid : StateWellFormed before) (effect : Effect writes middle after) :
    Effect writes before (restoreLocals before after) := by
  have domain := prefixEffect.domain.trans effect.domain
  exact ⟨domain.restoreLocals_wellFormed valid effect.wellFormed, rfl,
    fun cell old kept => (effect.oldCells cell (Nat.lt_of_lt_of_le old prefixEffect.nextCell) kept).trans
      (prefixEffect.oldCells cell old (by simp [CellSet.empty])), Nat.le_trans prefixEffect.nextCell effect.nextCell,
    domain.restoreLocals, effect.views.trans prefixEffect.views,
    effect.remaining.trans (congrArg (fun heap => heap.remaining) prefixEffect.heap)⟩

theorem Effect.preservesLocal (effect : Effect writes before after) (valid : StateWellFormed before)
    {id : VarId} (found : before.local? id = some value)
    (kept : ∀ cell, before.cellId? id = some cell → ¬ writes cell) : after.local? id = some value := by
  rw [State.local?, Option.bind_eq_some_iff] at found
  obtain ⟨cell, binding, stored⟩ := found
  have old := StateWellFormed.cell_lt_next_of_local_binding id cell valid binding
  have afterBinding : after.cellId? id = some cell := by simpa only [State.cellId?, effect.locals] using binding
  rw [State.local?, afterBinding]
  simpa only [Option.bind_some, State.cell?, effect.oldCells cell old (kept cell binding)] using stored

theorem Effect.preservesEntry (effect : Effect writes before after) (valid : StateWellFormed before)
    (found : before.cellEntry? cell = some { id := cell, value := value }) (kept : ¬ writes cell) :
    after.cellEntry? cell = some { id := cell, value := value } :=
  (effect.oldCells cell (StateWellFormed.cell_lt_next_of_entry valid found) kept).trans found

theorem Effect.preservesLocalPointsTo (effect : Effect writes before after) (valid : StateWellFormed before)
    (owned : (Assertion.localPointsTo localId cell value).holds before) (kept : ¬ writes cell) :
    (Assertion.localPointsTo localId cell value).holds after :=
  ⟨by simpa only [State.cellId?, effect.locals] using owned.1,
    effect.preservesEntry valid owned.2 kept⟩

theorem Frame.domain (frame : Frame before after) (initial : Allocation.Registry before)
    (finalRegistry : Allocation.Registry after) : CellDomainExtension before after := by
  constructor
  intro entry member
  by_cases registered : ∃ view ∈ before.i32ArrayViews, view.root = entry.id
  · obtain ⟨view, present, same⟩ := registered
    obtain ⟨words, _, found⟩ := finalRegistry.storage (by simpa only [frame.views] using present)
    exact ⟨_, List.mem_of_find?_eq_some found, same⟩
  · have separate : ∀ view ∈ before.i32ArrayViews, entry.id ≠ view.root := by
      intro view present same
      exact registered ⟨view, present, same.symm⟩
    cases found : before.cellEntry? entry.id with
    | none =>
        have missing := (List.find?_eq_none.mp found) entry member
        simp at missing
    | some stored =>
        have afterFound := (frame.nonViews entry.id separate).trans found
        exact ⟨stored, List.mem_of_find?_eq_some afterFound, by simpa using List.find?_some found⟩

theorem Effect.ofHost (frame : Frame before after) (initial : Allocation.Registry before)
    (finalRegistry : Allocation.Registry after)
    (keptViews : ∀ view ∈ before.i32ArrayViews, ¬ writes view.root →
      after.cellEntry? view.root = before.cellEntry? view.root) : Effect writes before after := by
  refine ⟨finalRegistry.wellFormed, frame.locals, ?_, Nat.le_of_eq frame.next.symm,
    frame.domain initial finalRegistry, frame.views, frame.remaining⟩
  intro cell _ kept
  by_cases registered : ∃ view ∈ before.i32ArrayViews, view.root = cell
  · obtain ⟨view, member, same⟩ := registered
    simpa only [same] using keptViews view member (same.symm ▸ kept)
  · exact frame.nonViews cell (fun view member same => registered ⟨view, member, same.symm⟩)

end Lanius.Extraction.Host
