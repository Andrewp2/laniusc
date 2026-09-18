import Lanius.Extraction.Allocation.Transport
import Lanius.Extraction.Input.Unpacking
import Lanius.Semantics.I32Views.Refresh
import Lanius.Extraction.Allocation.Borrowed

namespace Lanius.Extraction.Host

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation

/-- Registered words fit their signed i32 representation. This is separate
from structural registration and from non-overlapping address ranges. -/
def RepresentableViews (state : State) : Prop :=
  ∀ view ∈ state.i32ArrayViews, ∀ words : List Int,
    state.cellEntry? view.root = some { id := view.root, value := some (.array (signedI32Values words)) } →
    ∀ word ∈ words, -2147483648 ≤ word ∧ word ≤ 2147483647

theorem representableAfterRefresh (initial : Allocation.Registry before)
    (refreshed : syncI32ViewsFromHeap before = .ok after) : RepresentableViews after := by
  intro view member words contents
  obtain ⟨_, _, views, _⟩ :=
    syncI32RootViewsFromHeapFrom_preserves_structure initial.roots initial.wellFormed refreshed
  have originalMember : view ∈ before.i32ArrayViews := by simpa only [views] using member
  obtain ⟨raw, elements, loaded, decoded⟩ := syncI32ViewsFromHeapFrom_view_read originalMember refreshed
  have stored := syncI32ViewsFromHeapFrom_reads_view initial.distinct originalMember
    (initial.roots view originalMember) loaded decoded refreshed
  obtain ⟨values, equal, _, range⟩ := Input.decode_i32_array_values decoded
  subst elements
  have same : signedI32Values values = signedI32Values words := by
    injection stored.symm.trans contents with same
    injection same with _ arrays
    injection arrays with arrays
    exact Value.array.inj arrays
  exact signedI32Values_injective same ▸ range

theorem RepresentableViews.bindLocal (representable : RepresentableViews before)
    (initial : Allocation.Registry before) (id : VarId) (value : Value) :
    RepresentableViews (before.bindLocal id value) := by
  intro view member words contents
  have kept := (bindLocal_effect before id value).oldCells view.root
    (initial.root_lt_next member) (by simp [CellSet.empty])
  exact representable view member words (kept.symm.trans contents)

theorem RepresentableViews.enterCall (representable : RepresentableViews before)
    (initial : Allocation.Registry before) (bindings : List (VarId × Value)) :
    RepresentableViews (Lanius.Separation.enterCall before bindings) := by
  intro view member words contents
  have originalMember : view ∈ before.i32ArrayViews := by
    simpa only [(enterCall_effect before bindings).views] using member
  have kept := (enterCall_effect before bindings).oldCells view.root
    (initial.root_lt_next originalMember) (by simp [CellSet.empty])
  exact representable view originalMember words (kept.symm.trans contents)

theorem RepresentableViews.transport (representable : RepresentableViews before)
    (initial : Allocation.Registry before) (effect : CellEffect writes before after)
    (frame : HeapFrame before after)
    (changed : ∀ view ∈ before.i32ArrayViews, writes view.root → ∀ words : List Int,
      after.cellEntry? view.root = some { id := view.root, value := some (.array (signedI32Values words)) } →
      ∀ word ∈ words, -2147483648 ≤ word ∧ word ≤ 2147483647) : RepresentableViews after := by
  intro view member words contents
  rw [frame.views] at member
  by_cases written : writes view.root
  · exact changed view member written words contents
  · have kept := effect.oldCells view.root (initial.root_lt_next member) written
    exact representable view member words (kept.symm.trans contents)

/-- Fresh borrowed words are decoded from bytes, so their signed values are
representable. Existing registered roots keep their original contents. -/
theorem RepresentableViews.borrowed (representable : RepresentableViews before)
    (initial : Allocation.Registry before) (resources : I32BorrowedResources before count after) :
    RepresentableViews after := by
  obtain ⟨address, elements, views, _, cells, _, _, _⟩ := resources.storage
  intro view member words contents
  rw [views] at member
  rcases List.mem_append.mp member with old | fresh
  · have kept : after.cellEntry? view.root = before.cellEntry? view.root := by
      have kept := allocateTemporary_preserves_old_cell before (.array elements) view.root
        (initial.root_lt_next old)
      simpa only [State.allocateTemporary, State.cellEntry?, cells] using kept
    exact representable view old words (kept.symm.trans contents)
  · simp only [List.mem_singleton] at fresh
    subst view
    exact resources.representable words contents

end Lanius.Extraction.Host
