module

public import Lanius.Open.F5.CallRefsHeld.Stmt
public import Lanius.Open.F5.CallRefsAgree.Stmt
public import Lanius.Mini.Refs.HomedLemmas

@[expose] public section

open Lanius.Mini

/-- `CallRefsAgree`, its reference hypothesis from `HoldsAt.reference`. -/
theorem Lanius.Open.CallRefsHeld.red1 (h : Lanius.Open.CallRefsAgree) : Lanius.Open.CallRefsHeld :=
  fun _ places st bindings c args below none held =>
    h places st bindings c args below none fun id v mem T cell path hv => by
      subst hv
      obtain ⟨ty, hold, refTy⟩ := held id _ mem
      obtain ⟨referent, rfl, hto, -⟩ := hold.reference
      rw [refTy referent rfl]
      exact hto
