import Lanius.Open.F5.HomedCorrPushPlainV2.Stmt
import Lanius.Mini.Refs.HomedLemmas

open Lanius.Mini

/-- `HomedCorr.pushPlain`, as `Corr.push`. -/
theorem Lanius.Open.HomedCorrPushPlainV2.proof : Lanius.Open.HomedCorrPushPlainV2 :=
  fun _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ hc fr fresh agree holds under nv cframe hframe hnone ctx hslots href =>
    HomedCorr.pushPlain hc fr fresh agree holds under nv cframe hframe hnone ctx hslots href
