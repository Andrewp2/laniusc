module

public import Lanius.Open.F5.HomedCorrLocal.Stmt
public import Lanius.Mini.Refs.HomedLemmas

@[expose] public section

open Lanius.Mini

/-- `HomedCorr.local`: the slots' value, or the home's. -/
theorem Lanius.Open.HomedCorrLocal.proof : Lanius.Open.HomedCorrLocal :=
  fun _ _ _ _ _ _ _ _ _ prog _ _ hc homes found => HomedCorr.local prog hc homes found
