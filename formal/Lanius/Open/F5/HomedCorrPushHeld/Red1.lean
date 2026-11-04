module

public import Lanius.Open.F5.HomedCorrPushHeld.Stmt
public import Lanius.Open.F5.HomedCorrPushPlain.Stmt
public import Lanius.Mini.Refs.HomedLemmas

@[expose] public section

open Lanius.Mini

/-- `HomedCorrPushPlain`, its reference hypothesis from `HoldsAt.reference`. -/
theorem Lanius.Open.HomedCorrPushHeld.red1 (h : Lanius.Open.HomedCorrPushPlain) : Lanius.Open.HomedCorrPushHeld :=
  fun sx places scope frame c c' st env env' base next id ty v hc fr fresh agree holds under nv cframe hframe hnone
      ctx hslots slot refTy =>
    h sx places scope frame c c' st env env' base next id ty v hc fr fresh agree holds under nv cframe hframe hnone
      ctx hslots fun T cell path hv => by
        subst hv
        obtain ⟨referent, rfl, hto, -⟩ := holds.reference
        rw [refTy referent rfl, slot]
        exact hto
