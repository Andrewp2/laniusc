module

public import Lanius.Open.F5.CorePlace.Stmt
public import Lanius.Mini.Refs.CoreLemmas

@[expose] public section

open Lanius.Mini
open Lanius.Core (Value ValueProjection)
open Lanius.Semantics (State)

namespace Lanius.Open.CorePlace

open Lanius.Mini.CoreRefs

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
