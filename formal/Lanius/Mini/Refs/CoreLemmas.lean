module

public import Lanius.Mini.Refs.Model

@[expose] public section

/-! # References: facts about Core's reads of places (F5)

Reads at a path through its prefixes, and a local's evaluation, for F5's
Core statements (`Lanius/Open/F5/Core*`). Untrusted; kept apart from
`Refs/Lemmas.lean`.
-/

open Lanius.Mini
open Lanius.Core (Value ValueProjection)
open Lanius.Semantics (State)

namespace Lanius.Mini.CoreRefs

/-- A read at a path is a read of the cell's initialized value. -/
theorem readCell_ok {st : State} {cell : Lanius.CellId} {path : List ValueProjection} {v : Value}
    (h : Semantics.readCellProjection st cell path = .ok v) :
    ∃ id root, st.cellEntry? cell = some { id := id, value := some root } ∧
      Semantics.projectedValue root path = .ok v := by
  unfold Semantics.readCellProjection at h
  cases he : st.cellEntry? cell with
  | none => rw [he] at h; cases h
  | some entry =>
    rw [he] at h
    obtain ⟨id, value⟩ := entry
    cases value with
    | none => cases h
    | some root => exact ⟨id, root, rfl, h⟩

theorem readCell_eq {st : State} {cell : Lanius.CellId} {id : Lanius.CellId} {root : Value}
    (he : st.cellEntry? cell = some { id := id, value := some root }) (path : List ValueProjection) :
    Semantics.readCellProjection st cell path = Semantics.projectedValue root path := by
  unfold Semantics.readCellProjection
  rw [he]

/-- A read at a path one projection longer goes through the shorter one. -/
theorem projectedValue_snoc (root : Value) (path : List ValueProjection) (q : ValueProjection) (v : Value)
    (h : Semantics.projectedValue root (path ++ [q]) = .ok v) :
    ∃ u, Semantics.projectedValue root path = .ok u ∧ Semantics.projectedValue u [q] = .ok v := by
  induction path generalizing root with
  | nil => exact ⟨root, by simp [Semantics.projectedValue], by simpa using h⟩
  | cons p rest ih =>
    simp only [List.cons_append] at h
    cases p with
    | field f =>
      cases root <;> simp [Semantics.projectedValue] at h ⊢
      rename_i fields
      cases hf : fields[f]? with
      | none => simp [hf] at h
      | some w => simp only [hf] at h ⊢; exact ih w h
    | index i =>
      cases root <;> simp [Semantics.projectedValue] at h ⊢
      rename_i elements
      cases hf : elements[i]? with
      | none => simp [hf] at h
      | some w => simp only [hf] at h ⊢; exact ih w h

theorem projectedValue_field {u v : Value} {f : Nat}
    (h : Semantics.projectedValue u [.field f] = .ok v) :
    ∃ id fields, u = .structure id fields ∧ fields[f]? = some v := by
  cases u <;> simp [Semantics.projectedValue] at h
  rename_i id fields
  cases hf : fields[f]? with
  | none => simp [hf] at h
  | some w => simp [hf] at h; exact ⟨id, fields, rfl, by rw [hf, h]⟩

theorem projectedValue_index {u v : Value} {i : Nat}
    (h : Semantics.projectedValue u [.index i] = .ok v) :
    ∃ elements, u = .array elements ∧ elements[i]? = some v := by
  cases u <;> simp [Semantics.projectedValue] at h
  rename_i elements
  cases hf : elements[i]? with
  | none => simp [hf] at h
  | some w => simp [hf] at h; exact ⟨elements, rfl, by rw [hf, h]⟩

/-- The value at a path one projection longer: the cell's value at the
shorter path, then one projection. -/
theorem readCell_snoc {st : State} {cell : Lanius.CellId} {path : List ValueProjection}
    {q : ValueProjection} {v : Value}
    (h : Semantics.readCellProjection st cell (path ++ [q]) = .ok v) :
    ∃ u, Semantics.readCellProjection st cell path = .ok u ∧ Semantics.projectedValue u [q] = .ok v := by
  obtain ⟨_, root, he, hv⟩ := readCell_ok h
  obtain ⟨u, hu, hq⟩ := projectedValue_snoc root path q v hv
  exact ⟨u, by rw [readCell_eq he]; exact hu, hq⟩

theorem evalExpr_local {prog : Lanius.Core.Program} {st : State} {id : Lanius.VarId} {v : Value}
    (h : coreLocal st id = some v) (k : Nat) :
    Semantics.evalExpr (k + 1) prog st (.local id) = .done v st := by
  unfold coreLocal at h
  cases hc : st.cellId? id with
  | none => simp [hc] at h
  | some cell =>
    cases he : st.cellEntry? cell with
    | none => simp [hc, he] at h
    | some entry =>
      obtain ⟨cid, value⟩ := entry
      cases value with
      | none => simp [hc, he] at h
      | some w =>
        simp only [hc, he, Option.some.injEq] at h
        subst h
        simp [Semantics.evalExpr, hc, he]

end Lanius.Mini.CoreRefs
