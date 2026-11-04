module

public import Lanius.Open.F5.HomesPush.Stmt

@[expose] public section

open Lanius.Mini
open Lanius.Core (Value ValueProjection)
open Lanius.Semantics (State)

/-- The new home is home 0, holding over the older homes (`(x :: places).drop
1 = places`); home `i + 1` is the old home `i`, with the same older homes and
the same cell value. -/
theorem Lanius.Open.HomesPush.proof : Lanius.Open.HomesPush := by
  intro sx bud places st st' hp x v homes cells views hx hold proj sliced layout fsp limit top small
    apartx unviewedx
  refine
    { holds := fun i y hy => ?_
      roots := fun y hy => ?_
      sliced := fun y hy => ?_
      layout := fun y hy => ?_
      inside := fun y hy => ?_
      small := fun y hy => ?_
      apart := fun i j y z hy hz ne => ?_
      unviewed := fun w hw y hy => ?_
      room := homes.room
      ceiling := homes.ceiling
      bounded := homes.bounded
      statics := homes.statics }
  · cases i with
    | zero =>
      simp only [List.getElem?_cons_zero, Option.some.injEq] at hy
      subst hy
      exact ⟨v, hx, by simpa using hold⟩
    | succ i =>
      simp only [List.getElem?_cons_succ] at hy
      obtain ⟨u, hu, holdu⟩ := homes.holds i y hy
      have mem : y ∈ places := List.mem_of_getElem? hy
      exact ⟨u, by rw [cells y mem]; exact hu, by simpa using holdu⟩
  · rcases List.mem_cons.1 hy with rfl | hy
    · exact proj
    · exact homes.roots y hy
  · rcases List.mem_cons.1 hy with rfl | hy
    · exact sliced
    · exact homes.sliced y hy
  · rcases List.mem_cons.1 hy with rfl | hy
    · exact layout
    · exact homes.layout y hy
  · rcases List.mem_cons.1 hy with rfl | hy
    · exact ⟨fsp, limit, top⟩
    · exact homes.inside y hy
  · rcases List.mem_cons.1 hy with rfl | hy
    · exact small
    · exact homes.small y hy
  · cases i with
    | zero =>
      cases j with
      | zero => exact absurd rfl ne
      | succ j =>
        simp only [List.getElem?_cons_zero, Option.some.injEq] at hy
        simp only [List.getElem?_cons_succ] at hz
        subst hy
        exact apartx z (List.mem_of_getElem? hz)
    | succ i =>
      cases j with
      | zero =>
        simp only [List.getElem?_cons_succ] at hy
        simp only [List.getElem?_cons_zero, Option.some.injEq] at hz
        subst hz
        obtain ⟨c, d⟩ := apartx y (List.mem_of_getElem? hy)
        exact ⟨Ne.symm c, d.symm⟩
      | succ j =>
        simp only [List.getElem?_cons_succ] at hy hz
        exact homes.apart i j y z hy hz (by omega)
  · rw [views] at hw
    rcases List.mem_cons.1 hy with rfl | hy
    · exact unviewedx w hw
    · exact homes.unviewed w hw y hy
