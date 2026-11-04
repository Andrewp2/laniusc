module

public import Lanius.Open.F5.CoreRead.Stmt
public import Lanius.Mini.Refs.CoreLemmas

@[expose] public section

open Lanius.Mini
open Lanius.Core (Value ValueProjection)
open Lanius.Semantics (State)

namespace Lanius.Open.CoreRead

open Lanius.Mini.CoreRefs

/-- A place that resolves, at a path with a value, reads that value with the
state unchanged. -/
theorem resolves {prog : Lanius.Core.Program} {st : State} {p : RPlace} {cell : Lanius.CellId}
    {path : List ValueProjection} (h : p.Resolves prog st cell path) :
    ∀ v, Semantics.readCellProjection st cell path = .ok v →
      ∃ N, ∀ fuel, N ≤ fuel → Semantics.evalExpr fuel prog st p.read = .done v st := by
  induction h with
  | @home id cell hc =>
    intro v hv
    obtain ⟨_, root, he, hroot⟩ := readCell_ok hv
    simp only [Semantics.projectedValue, Except.ok.injEq] at hroot
    subst hroot
    refine ⟨1, fun fuel hf => ?_⟩
    obtain ⟨k, rfl⟩ : ∃ k, fuel = k + 1 := ⟨fuel - 1, by omega⟩
    exact evalExpr_local (by simp [coreLocal, hc, he]) k
  | @deref id T cell path hc =>
    intro v hv
    refine ⟨2, fun fuel hf => ?_⟩
    obtain ⟨k, rfl⟩ : ∃ k, fuel = k + 2 := ⟨fuel - 2, by omega⟩
    have hl := evalExpr_local (prog := prog) hc k
    rw [RPlace.read, Semantics.evalExpr.eq_def]
    simp only [hl, Semantics.dereferenceValue, hv]
  | @field base f cell path _ ih =>
    intro v hv
    obtain ⟨u, hu, hq⟩ := readCell_snoc hv
    obtain ⟨id, fields, rfl, hf⟩ := projectedValue_field hq
    obtain ⟨N, hN⟩ := ih _ hu
    refine ⟨N + 1, fun fuel hfuel => ?_⟩
    obtain ⟨k, rfl⟩ : ∃ k, fuel = k + 1 := ⟨fuel - 1, by omega⟩
    simp only [RPlace.read, Semantics.evalExpr, hN k (by omega), hf]
  | @index base index code slot cell path iv i _ hidx hi ih =>
    intro v hv
    obtain ⟨u, hu, hq⟩ := readCell_snoc hv
    obtain ⟨elements, rfl, hf⟩ := projectedValue_index hq
    obtain ⟨N, hN⟩ := ih _ hu
    obtain ⟨M, hM⟩ := hidx
    refine ⟨N + M + 1, fun fuel hfuel => ?_⟩
    obtain ⟨k, rfl⟩ : ∃ k, fuel = k + 1 := ⟨fuel - 1, by omega⟩
    simp only [RPlace.read, Semantics.evalExpr, hN k (by omega), hM k (by omega), hi, hf]

/-- A place whose resolution traps reads to that trap. -/
theorem traps {prog : Lanius.Core.Program} {st : State} {p : RPlace} {r : Lanius.Trap} {st' : State}
    (h : p.Traps prog st r st') :
    ∃ N, ∀ fuel, N ≤ fuel → Semantics.evalExpr fuel prog st p.read = .trapped r st' := by
  induction h with
  | @field base f r st' _ ih =>
    obtain ⟨N, hN⟩ := ih
    refine ⟨N + 1, fun fuel hfuel => ?_⟩
    obtain ⟨k, rfl⟩ : ∃ k, fuel = k + 1 := ⟨fuel - 1, by omega⟩
    simp only [RPlace.read, Semantics.evalExpr, hN k (by omega)]
  | @index base index code slot r st' _ ih =>
    obtain ⟨N, hN⟩ := ih
    refine ⟨N + 1, fun fuel hfuel => ?_⟩
    obtain ⟨k, rfl⟩ : ∃ k, fuel = k + 1 := ⟨fuel - 1, by omega⟩
    simp only [RPlace.read, Semantics.evalExpr, hN k (by omega)]
  | @indexTraps base index code slot cell path elements r st' hb ha hidx =>
    obtain ⟨N, hN⟩ := resolves hb _ ha
    obtain ⟨M, hM⟩ := hidx
    refine ⟨N + M + 1, fun fuel hfuel => ?_⟩
    obtain ⟨k, rfl⟩ : ∃ k, fuel = k + 1 := ⟨fuel - 1, by omega⟩
    simp only [RPlace.read, Semantics.evalExpr, hN k (by omega), hM k (by omega)]
  | @negative base index code slot cell path iv elements hb ha hidx hi =>
    obtain ⟨N, hN⟩ := resolves hb _ ha
    obtain ⟨M, hM⟩ := hidx
    refine ⟨N + M + 1, fun fuel hfuel => ?_⟩
    obtain ⟨k, rfl⟩ : ∃ k, fuel = k + 1 := ⟨fuel - 1, by omega⟩
    simp only [RPlace.read, Semantics.evalExpr, hN k (by omega), hM k (by omega), hi]
  | @beyond base index code slot cell path iv i elements hb ha hidx hi hlen =>
    obtain ⟨N, hN⟩ := resolves hb _ ha
    obtain ⟨M, hM⟩ := hidx
    refine ⟨N + M + 1, fun fuel hfuel => ?_⟩
    obtain ⟨k, rfl⟩ : ∃ k, fuel = k + 1 := ⟨fuel - 1, by omega⟩
    have hnone : elements[i]? = none := List.getElem?_eq_none hlen
    simp only [RPlace.read, Semantics.evalExpr, hN k (by omega), hM k (by omega), hi, hnone]

end Lanius.Open.CoreRead

/-- CorePlace's induction on values: `.field` and `.index` of the base's
read, `dereference` of a reference local's value. -/
theorem Lanius.Open.CoreRead.proof : Lanius.Open.CoreRead := by
  intro prog st p
  exact ⟨fun cell path v hp hv => CoreRead.resolves hp v hv, fun r st' ht => CoreRead.traps ht⟩
