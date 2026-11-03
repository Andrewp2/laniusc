import Lanius.Open.F5.HomedCorrOfCorr.Stmt
import Lanius.Mini.Refs.HomedLemmas

open Lanius.Mini

/-- Field by field (`HomedCorr.ofCorr`). -/
theorem Lanius.Open.HomedCorrOfCorr.proof : Lanius.Open.HomedCorrOfCorr :=
  fun _ _ _ _ _ _ _ corr agree hc => HomedCorr.ofCorr corr agree hc
