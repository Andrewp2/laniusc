module

public import Lanius.Open.F5.HomedCorrOfCorr.Stmt
public import Lanius.Mini.Refs.HomedLemmas

@[expose] public section

open Lanius.Mini

/-- Field by field (`HomedCorr.ofCorr`). -/
theorem Lanius.Open.HomedCorrOfCorr.proof : Lanius.Open.HomedCorrOfCorr :=
  fun _ _ _ _ _ _ _ corr agree hc => HomedCorr.ofCorr corr agree hc
