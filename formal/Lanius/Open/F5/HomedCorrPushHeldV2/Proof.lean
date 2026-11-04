module

public import Lanius.Open.F5.HomedCorrPushHeldV2.Red1
public import Lanius.Open.F5.HomedCorrPushPlainV2.Proof

@[expose] public section

theorem Lanius.Open.HomedCorrPushHeldV2.proof : Lanius.Open.HomedCorrPushHeldV2 :=
  Lanius.Open.HomedCorrPushHeldV2.red1 Lanius.Open.HomedCorrPushPlainV2.proof
