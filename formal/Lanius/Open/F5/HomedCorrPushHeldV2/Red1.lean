import Lanius.Open.F5.HomedCorrPushHeldV2.Stmt
import Lanius.Open.F5.HomedCorrPushPlainV2.Stmt
import Lanius.Mini.Refs.HomedLemmas

open Lanius.Mini

/-- `HomedCorrPushPlainV2`, its reference hypothesis from `HoldsAt.reference`. -/
theorem Lanius.Open.HomedCorrPushHeldV2.red1 (h : Lanius.Open.HomedCorrPushPlainV2) : Lanius.Open.HomedCorrPushHeldV2 :=
  fun sx places scope frame c c' st env env' base next id ty home v hc fr fresh agree holds under nv cframe hframe hnone
      ctx hslots slot refTy =>
    h sx places scope frame c c' st env env' base next id ty home v hc fr fresh agree holds under nv cframe hframe hnone
      ctx hslots fun T cell path hv => by
        subst hv
        obtain ⟨referent, rfl, hto, -⟩ := holds.reference
        rw [refTy referent rfl, slot]
        exact hto
