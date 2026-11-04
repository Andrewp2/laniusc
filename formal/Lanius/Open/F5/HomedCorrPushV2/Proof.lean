module

public import Lanius.Open.F5.HomedCorrPushV2.Stmt
public import Lanius.Mini.Refs.HomedLemmas

@[expose] public section

open Lanius.Mini

/-- `HomedCorr.pushHome`, as `Corr.push` for the old bindings. -/
theorem Lanius.Open.HomedCorrPushV2.proof : Lanius.Open.HomedCorrPushV2 :=
  fun _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ hc fr fresh agree under hframe hslots hxcell hxty hxaddr =>
    HomedCorr.pushHome hc fr fresh agree under hframe hslots hxcell hxty hxaddr
