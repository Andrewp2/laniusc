import Lanius.Open.F5.CoreBorrow.Stmt
import Lanius.Open.F5.CorePlace.Stmt

open Lanius.Mini
open Lanius.Core (Value ValueProjection)
open Lanius.Semantics (State)

/-- `borrow` resolves the place for a read (`CorePlace`): it has a value
and no raw storage, so the result is the reference to its cell and path. -/
theorem Lanius.Open.CoreBorrow.red1 (hplace : Lanius.Open.CorePlace) : Lanius.Open.CoreBorrow := by
  intro prog st p cell path v T hp hv
  obtain ⟨N, hN⟩ := (hplace prog st p .read).1 cell path v hp hv
  refine ⟨N + 1, fun fuel hfuel => ?_⟩
  obtain ⟨k, rfl⟩ : ∃ k, fuel = k + 1 := ⟨fuel - 1, by omega⟩
  obtain ⟨r, hr, hroot, hpath, hraw, hval⟩ := hN k (by omega)
  obtain ⟨root, projections, value, raw, rawByte⟩ := r
  simp only at hroot hpath hraw hval
  subst hroot hpath hraw hval
  simp only [Semantics.evalExpr, hr]
