module

public import Lanius.Open.F5.CoreAssign.Stmt
public import Lanius.Open.F5.CorePlace.Stmt
public import Lanius.Mini.Refs.CoreLemmas

@[expose] public section

open Lanius.Mini
open Lanius.Core (Value ValueProjection)
open Lanius.Semantics (State)

/-- `assign set` resolves the place for an address (`CorePlace`: its cell
and path, no raw storage), evaluates the right side, writes it at the path
(`CoreRefs.write_ok`), and the views, which still hold since none roots at
the cell, sync to themselves (`CoreRefs.sync_ok`). -/
theorem Lanius.Open.CoreAssign.red1 (hplace : Lanius.Open.CorePlace) : Lanius.Open.CoreAssign := by
  intro prog st st₁ st' p cell path e old v root root' hp hold he hroot hrep hassign hviews apart
  obtain ⟨N, hN⟩ := (hplace prog st p .address).1 cell path old hp hold
  obtain ⟨M, hM⟩ := he
  refine ⟨N + M + 1, fun fuel hfuel => ?_⟩
  obtain ⟨k, rfl⟩ : ∃ k, fuel = k + 1 := ⟨fuel - 1, by omega⟩
  obtain ⟨r, hr, hcell, hpath, hraw, hval⟩ := hN k (by omega)
  obtain ⟨rc, rp, value, raw, rawByte⟩ := r
  simp only at hcell hpath hraw hval
  subst hcell hpath hraw hval
  have hold' := hviews.assignCell hassign apart
  simp only [Semantics.evalExpr, hr, hM k (by omega), Semantics.evalAssignValue,
    Semantics.assignOpBinary?, CoreRefs.write_ok (prog := prog) (rawByte := rawByte) (value := some old)
      hroot hrep hassign]
  rw [CoreRefs.sync_ok rfl hold']
