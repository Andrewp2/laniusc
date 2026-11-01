import Lanius.Mini.Shape

/-! # Typed Core states (review finding 2, step 2)

A store typing `Σ` gives some cells a type. `CellsOk P Σ st`: every cell `Σ`
types is in `st` and holds, when initialized, a value of that type's shape;
every cell is below `nextCell`; and no i32 view is registered (the fragment
without raw memory makes none). `LocalsOk Σ Γ st`: every local the typing
context `Γ` names is bound to a cell `Σ` gives its type. Binding a local, or
a list of them, assigning a typed value to a typed cell, and restoring a
caller's locals keep both, with `Σ` only growing. -/

namespace Lanius.Mini

open Lanius.Core (Value Ty)
open Lanius.Semantics (State Cell)

/-- A store typing: the types of some cells. -/
abbrev CellTypes := Nat → Option Ty

/-- `Σ'` keeps every type `Σ` gives. -/
def CellTypes.Le (S S' : CellTypes) : Prop := ∀ c t, S c = some t → S' c = some t

theorem CellTypes.Le.refl (S : CellTypes) : S.Le S := fun _ _ h => h

theorem CellTypes.Le.trans {S S' S'' : CellTypes} (a : S.Le S') (b : S'.Le S'') : S.Le S'' :=
  fun c t h => b c t (a c t h)

/-- `Σ` with cell `c` of type `t`. -/
def CellTypes.set (S : CellTypes) (c : Nat) (t : Ty) : CellTypes := fun d => if d = c then some t else S d

structure CellsOk (P : Core.Program) (S : CellTypes) (st : State) : Prop where
  views : st.i32ArrayViews = []
  typed : ∀ c t, S c = some t → ∃ cell, st.cellEntry? c = some cell ∧ ∀ v, cell.value = some v → Shape P v t
  below : ∀ cell ∈ st.cells, cell.id < st.nextCell

def LocalsOk (S : CellTypes) (Γ : Typing.Context) (st : State) : Prop :=
  ∀ id t, Γ id = some t → ∃ c, st.cellId? id = some c ∧ S c = some t

theorem LocalsOk.mono {S S' : CellTypes} {Γ : Typing.Context} {st st' : State} (h : LocalsOk S Γ st)
    (le : S.Le S') (same : st'.locals = st.locals) : LocalsOk S' Γ st' := by
  intro id t found
  obtain ⟨c, cell, ty⟩ := h id t found
  refine ⟨c, ?_, le c t ty⟩
  simp only [State.cellId?, same] at cell ⊢
  exact cell

theorem cellEntry_id {st : State} {c : Nat} {cell : Cell} (h : st.cellEntry? c = some cell) : cell.id = c := by
  simpa [State.cellEntry?] using List.find?_some h

theorem cellEntry_mem {st : State} {c : Nat} {cell : Cell} (h : st.cellEntry? c = some cell) : cell ∈ st.cells :=
  List.mem_of_find?_eq_some h

/-- A typed cell is below `nextCell`. -/
theorem CellsOk.lt {P : Core.Program} {S : CellTypes} {st : State} (h : CellsOk P S st) {c : Nat} {t : Ty}
    (typed : S c = some t) : c < st.nextCell := by
  obtain ⟨cell, found, -⟩ := h.typed c t typed
  have := h.below cell (cellEntry_mem found)
  rw [cellEntry_id found] at this
  exact this

/-! ## Binding a local -/

theorem bindCell_cellEntry (st : State) (id : Nat) (value : Option Value) (below : ∀ cell ∈ st.cells, cell.id < st.nextCell)
    (c : Nat) : (st.bindCell id value).cellEntry? c =
      if c = st.nextCell then some { id := st.nextCell, value } else st.cellEntry? c := by
  simp only [State.bindCell, State.cellEntry?, List.find?_append]
  by_cases eq : c = st.nextCell
  · subst eq
    rw [if_pos rfl]
    have none : st.cells.find? (fun cell => cell.id == st.nextCell) = none := by
      rw [List.find?_eq_none]
      intro cell mem eq
      have := below cell mem
      simp only [beq_iff_eq] at eq
      exact Nat.ne_of_lt this eq
    simp [none]
  · rw [if_neg eq]
    cases h : st.cells.find? (fun cell => cell.id == c) with
    | some cell => simp
    | none =>
      have ne : (st.nextCell == c) = false := beq_false_of_ne (Ne.symm eq)
      simp [ne]

theorem bindCell_cellId (st : State) (id : Nat) (value : Option Value) (x : Nat) :
    (st.bindCell id value).cellId? x = if x = id then some st.nextCell else st.cellId? x := by
  simp only [State.bindCell, State.cellId?, List.find?_cons]
  by_cases eq : x = id
  · subst eq; simp
  · have ne : (id == x) = false := beq_false_of_ne (Ne.symm eq)
    simp [ne, eq]

theorem CellsOk.bindCell {P : Core.Program} {S : CellTypes} {st : State} (h : CellsOk P S st) (id : Nat)
    {value : Option Value} {t : Ty} (shaped : ∀ v, value = some v → Shape P v t) :
    CellsOk P (S.set st.nextCell t) (st.bindCell id value) ∧ S.Le (S.set st.nextCell t) := by
  have le : S.Le (S.set st.nextCell t) := by
    intro c u typed
    have := h.lt typed
    simp only [CellTypes.set]
    rw [if_neg (by omega)]
    exact typed
  refine ⟨⟨h.views, fun c u typed => ?_, fun cell mem => ?_⟩, le⟩
  · rw [bindCell_cellEntry st id value h.below]
    simp only [CellTypes.set] at typed
    by_cases eq : c = st.nextCell
    · rw [if_pos eq] at typed ⊢
      cases typed
      exact ⟨_, rfl, shaped⟩
    · rw [if_neg eq] at typed ⊢
      exact h.typed c u typed
  · have mem' : cell ∈ st.cells ∨ cell = { id := st.nextCell, value } := by
      simpa [State.bindCell] using mem
    show cell.id < st.nextCell + 1
    rcases mem' with mem | rfl
    · exact Nat.lt_succ_of_lt (h.below cell mem)
    · exact Nat.lt_succ_self _

theorem LocalsOk.bindCell {P : Core.Program} {S : CellTypes} {Γ : Typing.Context} {st : State}
    (cells : CellsOk P S st) (h : LocalsOk S Γ st) (id : Nat) (value : Option Value) (t : Ty) :
    LocalsOk (S.set st.nextCell t) (Γ.bind id t) (st.bindCell id value) := by
  intro x u found
  rw [bindCell_cellId]
  simp only [Typing.Context.bind, beq_iff_eq] at found
  by_cases eq : x = id
  · rw [if_pos eq] at found ⊢
    cases found
    exact ⟨_, rfl, by simp [CellTypes.set]⟩
  · rw [if_neg eq] at found ⊢
    obtain ⟨c, cell, ty⟩ := h x u found
    have := cells.lt ty
    exact ⟨c, cell, by simp only [CellTypes.set]; rw [if_neg (by omega)]; exact ty⟩

/-! ## Assigning a cell -/

theorem replaceCell_eq : ∀ (cells : List Cell) (c : Nat) (v : Value),
    Lanius.Semantics.replaceCell cells c v =
      cells.map fun cell => if cell.id == c then { cell with value := some v } else cell
  | [], _, _ => rfl
  | cell :: rest, c, v => by
    simp only [Lanius.Semantics.replaceCell, List.map_cons]
    split <;> simp_all [replaceCell_eq rest c v]

theorem find_replace (cells : List Cell) (c d : Nat) (v : Value) :
    (cells.map fun cell => if cell.id == c then { cell with value := some v } else cell).find?
        (fun cell => cell.id == d) =
      (cells.find? fun cell => cell.id == d).map
        fun cell => if cell.id == c then { cell with value := some v } else cell := by
  induction cells with
  | nil => rfl
  | cons cell rest ih =>
    have idf : (if cell.id == c then { cell with value := some v } else cell).id = cell.id := by
      split <;> rfl
    simp only [List.map_cons, List.find?_cons, idf]
    cases h : cell.id == d
    · exact ih
    · rfl

theorem assignCell_cellEntry {st st' : State} {c : Nat} {v : Value} (h : st.assignCell c v = some st') (d : Nat) :
    st'.cellEntry? d = (st.cellEntry? d).map
      fun cell => if cell.id == c then { cell with value := some v } else cell := by
  simp only [State.assignCell] at h
  split at h
  · cases h
    simp only [State.cellEntry?, replaceCell_eq, find_replace]
  · cases h

theorem assignCell_locals {st st' : State} {c : Nat} {v : Value} (h : st.assignCell c v = some st') :
    st'.locals = st.locals ∧ st'.nextCell = st.nextCell ∧ st'.i32ArrayViews = st.i32ArrayViews ∧
      ∀ cell' ∈ st'.cells, ∃ cell ∈ st.cells, cell'.id = cell.id := by
  simp only [State.assignCell] at h
  split at h
  · cases h
    refine ⟨rfl, rfl, rfl, fun cell' mem => ?_⟩
    simp only [replaceCell_eq, List.mem_map] at mem
    obtain ⟨cell, mem, rfl⟩ := mem
    exact ⟨cell, mem, by split <;> rfl⟩
  · cases h

theorem CellsOk.assignCell {P : Core.Program} {S : CellTypes} {st st' : State} (h : CellsOk P S st)
    {c : Nat} {t : Ty} (typed : S c = some t) {v : Value} (shaped : Shape P v t)
    (assigned : st.assignCell c v = some st') : CellsOk P S st' := by
  obtain ⟨locals, next, views, ids⟩ := assignCell_locals assigned
  refine ⟨views.trans h.views, fun d u ty => ?_, fun cell' mem => ?_⟩
  · rw [assignCell_cellEntry assigned]
    obtain ⟨cell, found, shapedOld⟩ := h.typed d u ty
    have cid := cellEntry_id found
    rw [found]
    by_cases eq : d = c
    · subst eq
      rw [typed] at ty
      cases ty
      refine ⟨_, rfl, fun w hw => ?_⟩
      simp only [cid, beq_self_eq_true, if_true, Option.some.injEq] at hw
      subst hw; exact shaped
    · have ne : (cell.id == c) = false := beq_false_of_ne (by rw [cid]; exact eq)
      refine ⟨cell, ?_, shapedOld⟩
      simp only [Option.map_some, ne, Bool.false_eq_true, if_false]
  · obtain ⟨cell, mem, same⟩ := ids cell' mem
    rw [same, next]
    exact h.below cell mem

/-! ## Restoring the caller's locals -/

theorem CellsOk.restore {P : Core.Program} {S : CellTypes} {caller st : State} (h : CellsOk P S st) :
    CellsOk P S (Lanius.Semantics.restoreLocals caller st) := ⟨h.views, h.typed, h.below⟩

theorem LocalsOk.restore {S S' : CellTypes} {Γ : Typing.Context} {caller st : State} (h : LocalsOk S Γ caller)
    (le : S.Le S') : LocalsOk S' Γ (Lanius.Semantics.restoreLocals caller st) :=
  h.mono le rfl

end Lanius.Mini
