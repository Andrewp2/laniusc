import Lanius.Open.F5.CorePlace.Stmt

open Lanius.Mini
open Lanius.Core (Value ValueProjection)
open Lanius.Semantics (State)

namespace Lanius.Open.CorePlace

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

/-- A place that resolves, at a path with a value, evaluates for every
access to its cell, path and value, with no raw storage and the state
unchanged. -/
theorem resolves {prog : Lanius.Core.Program} {st : State} {p : RPlace} {cell : Lanius.CellId}
    {path : List ValueProjection} (h : p.Resolves prog st cell path) :
    ∀ v, Semantics.readCellProjection st cell path = .ok v →
      ∃ N, ∀ fuel, N ≤ fuel → ∀ access, ∃ r : Semantics.ResolvedPlace,
        Semantics.evalPlace fuel prog st access p.toCore = .done r st ∧
        r.root = cell ∧ r.projections = path ∧ r.raw = none ∧ r.value = some v := by
  induction h with
  | @home id cell hc =>
    intro v hv
    obtain ⟨_, root, he, hroot⟩ := readCell_ok hv
    simp only [Semantics.projectedValue, Except.ok.injEq] at hroot
    subst hroot
    refine ⟨1, fun fuel hf access => ?_⟩
    obtain ⟨k, rfl⟩ : ∃ k, fuel = k + 1 := ⟨fuel - 1, by omega⟩
    cases access <;>
      exact ⟨_, by simp [RPlace.toCore, Semantics.evalPlace, hc, he]; rfl, rfl, rfl, rfl, rfl⟩
  | @deref id T cell path hc =>
    intro v hv
    refine ⟨2, fun fuel hf access => ?_⟩
    obtain ⟨k, rfl⟩ : ∃ k, fuel = k + 2 := ⟨fuel - 2, by omega⟩
    refine ⟨{ root := cell, projections := path, value := some v }, ?_, rfl, rfl, rfl, rfl⟩
    simp only [RPlace.toCore, Semantics.evalPlace, evalExpr_local hc k, hv]
  | @field base f cell path _ ih =>
    intro v hv
    obtain ⟨u, hu, hq⟩ := readCell_snoc hv
    obtain ⟨id, fields, rfl, hf⟩ := projectedValue_field hq
    obtain ⟨N, hN⟩ := ih _ hu
    refine ⟨N + 1, fun fuel hfuel access => ?_⟩
    obtain ⟨k, rfl⟩ : ∃ k, fuel = k + 1 := ⟨fuel - 1, by omega⟩
    obtain ⟨r, hr, hroot, hpath, hraw, hval⟩ := hN k (by omega) .address
    refine ⟨{ r with projections := r.projections ++ [.field f], value := some v }, ?_, hroot,
      by simp [hpath], hraw, rfl⟩
    simp only [RPlace.toCore, Semantics.evalPlace, hr, hraw, hval, hf]
  | @index base index code slot cell path iv i _ hidx hi ih =>
    intro v hv
    obtain ⟨u, hu, hq⟩ := readCell_snoc hv
    obtain ⟨elements, rfl, hf⟩ := projectedValue_index hq
    obtain ⟨N, hN⟩ := ih _ hu
    obtain ⟨M, hM⟩ := hidx
    refine ⟨N + M + 1, fun fuel hfuel access => ?_⟩
    obtain ⟨k, rfl⟩ : ∃ k, fuel = k + 1 := ⟨fuel - 1, by omega⟩
    obtain ⟨r, hr, hroot, hpath, hraw, hval⟩ := hN k (by omega) .read
    refine ⟨{ r with projections := r.projections ++ [.index i], value := some v }, ?_, hroot,
      by simp [hpath], hraw, rfl⟩
    simp only [RPlace.toCore, Semantics.evalPlace, hr, hval, hM k (by omega), hi, hf]

/-- A place whose resolution traps evaluates, for every access, to that
trap. -/
theorem traps {prog : Lanius.Core.Program} {st : State} {p : RPlace} {r : Lanius.Trap} {st' : State}
    (h : p.Traps prog st r st') :
    ∃ N, ∀ fuel, N ≤ fuel → ∀ access,
      Semantics.evalPlace fuel prog st access p.toCore = .trapped r st' := by
  induction h with
  | @field base f r st' _ ih =>
    obtain ⟨N, hN⟩ := ih
    refine ⟨N + 1, fun fuel hfuel access => ?_⟩
    obtain ⟨k, rfl⟩ : ∃ k, fuel = k + 1 := ⟨fuel - 1, by omega⟩
    simp only [RPlace.toCore, Semantics.evalPlace, hN k (by omega) .address]
  | @index base index code slot r st' _ ih =>
    obtain ⟨N, hN⟩ := ih
    refine ⟨N + 1, fun fuel hfuel access => ?_⟩
    obtain ⟨k, rfl⟩ : ∃ k, fuel = k + 1 := ⟨fuel - 1, by omega⟩
    simp only [RPlace.toCore, Semantics.evalPlace, hN k (by omega) .read]
  | @indexTraps base index code slot cell path elements r st' hb ha hidx =>
    obtain ⟨N, hN⟩ := resolves hb _ ha
    obtain ⟨M, hM⟩ := hidx
    refine ⟨N + M + 1, fun fuel hfuel access => ?_⟩
    obtain ⟨k, rfl⟩ : ∃ k, fuel = k + 1 := ⟨fuel - 1, by omega⟩
    obtain ⟨rp, hr, -, -, -, hval⟩ := hN k (by omega) .read
    simp only [RPlace.toCore, Semantics.evalPlace, hr, hval, hM k (by omega)]
  | @negative base index code slot cell path iv elements hb ha hidx hi =>
    obtain ⟨N, hN⟩ := resolves hb _ ha
    obtain ⟨M, hM⟩ := hidx
    refine ⟨N + M + 1, fun fuel hfuel access => ?_⟩
    obtain ⟨k, rfl⟩ : ∃ k, fuel = k + 1 := ⟨fuel - 1, by omega⟩
    obtain ⟨rp, hr, -, -, -, hval⟩ := hN k (by omega) .read
    simp only [RPlace.toCore, Semantics.evalPlace, hr, hval, hM k (by omega), hi]
  | @beyond base index code slot cell path iv i elements hb ha hidx hi hlen =>
    obtain ⟨N, hN⟩ := resolves hb _ ha
    obtain ⟨M, hM⟩ := hidx
    refine ⟨N + M + 1, fun fuel hfuel access => ?_⟩
    obtain ⟨k, rfl⟩ : ∃ k, fuel = k + 1 := ⟨fuel - 1, by omega⟩
    obtain ⟨rp, hr, -, -, -, hval⟩ := hN k (by omega) .read
    have hnone : elements[i]? = none := List.getElem?_eq_none hlen
    simp only [RPlace.toCore, Semantics.evalPlace, hr, hval, hM k (by omega), hi, hnone]

end Lanius.Open.CorePlace

/-- Induction on `Resolves` (`CorePlace.resolves`) and on `Traps`
(`CorePlace.traps`): a field evaluates its base for an address, an index
for a read, and both give the value at the path since every prefix of a path
with a value is a struct or an array. -/
theorem Lanius.Open.CorePlace.proof : Lanius.Open.CorePlace := by
  intro prog st p access
  refine ⟨fun cell path v hp hv => ?_, fun r st' ht => ?_⟩
  · obtain ⟨N, hN⟩ := CorePlace.resolves hp v hv
    exact ⟨N, fun fuel hf => hN fuel hf access⟩
  · obtain ⟨N, hN⟩ := CorePlace.traps ht
    exact ⟨N, fun fuel hf => hN fuel hf access⟩
