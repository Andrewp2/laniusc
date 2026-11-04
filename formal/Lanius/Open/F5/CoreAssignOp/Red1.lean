module

public import Lanius.Open.F5.CoreAssignOp.Stmt
public import Lanius.Open.F5.CorePlace.Stmt
public import Lanius.Mini.Refs.CoreLemmas

@[expose] public section

open Lanius.Mini
open Lanius.Core (Value ValueProjection)
open Lanius.Semantics (State)

/-- As `CoreAssign.red1`: the place resolves (for a read, since `op ≠ set`;
`CorePlace` holds for either access) to its cell, path and old value, the
right side runs, `evalAssignValue` combines them, and the write and the
views' sync go as for `set`. -/
theorem Lanius.Open.CoreAssignOp.red1 (hplace : Lanius.Open.CorePlace) : Lanius.Open.CoreAssignOp := by
  intro prog st st₁ st' p cell path e op old v result root root' hop hp hold he hcomb hroot hrep hassign
    hviews apart
  obtain ⟨N, hN⟩ := (hplace prog st p .read).1 cell path old hp hold
  obtain ⟨M, hM⟩ := he
  refine ⟨N + M + 1, fun fuel hfuel => ?_⟩
  obtain ⟨k, rfl⟩ : ∃ k, fuel = k + 1 := ⟨fuel - 1, by omega⟩
  obtain ⟨r, hr, hcell, hpath, hraw, hval⟩ := hN k (by omega)
  obtain ⟨rc, rp, value, raw, rawByte⟩ := r
  simp only at hcell hpath hraw hval
  subst hcell hpath hraw hval
  have hold' := hviews.assignCell hassign apart
  have hw := CoreRefs.write_ok (prog := prog) (rawByte := rawByte) (value := some old) hroot hrep hassign
  cases op
  case set => exact absurd rfl hop
  all_goals
    simp only [Semantics.evalExpr, hr, hM k (by omega), hcomb, hw]
    rw [CoreRefs.sync_ok rfl hold']
