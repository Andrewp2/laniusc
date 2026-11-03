import Lanius.Open.F5.HomedCorrKeeps.Stmt
import Lanius.Mini.Refs.HomedLemmas

open Lanius.Mini

/-- `HomedCorr.keeps`, as `Corr.keeps` for the locals without homes. -/
theorem Lanius.Open.HomedCorrKeeps.proof : Lanius.Open.HomedCorrKeeps :=
  fun _ _ _ _ _ _ _ _ hc fresh keeps locals => HomedCorr.keeps hc fresh keeps locals
