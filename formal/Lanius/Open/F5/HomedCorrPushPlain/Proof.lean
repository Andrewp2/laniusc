import Lanius.Open.F5.HomedCorrPushPlain.Stmt
import Lanius.Mini.Refs.HomedLemmas

open Lanius.Mini

/-- `HomedCorr.pushPlain`, as `Corr.push`. -/
theorem Lanius.Open.HomedCorrPushPlain.proof : Lanius.Open.HomedCorrPushPlain :=
  fun _ _ _ _ _ _ _ _ _ _ _ _ _ _ hc fr fresh agree holds under nv cframe hframe hnone ctx hslots href =>
    HomedCorr.pushPlain hc fr fresh agree holds under nv cframe hframe hnone ctx hslots href
