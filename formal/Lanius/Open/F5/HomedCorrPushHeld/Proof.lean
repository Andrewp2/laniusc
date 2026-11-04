module

public import Lanius.Open.F5.HomedCorrPushHeld.Red1
public import Lanius.Open.F5.HomedCorrPushPlain.Proof

@[expose] public section

theorem Lanius.Open.HomedCorrPushHeld.proof : Lanius.Open.HomedCorrPushHeld :=
  Lanius.Open.HomedCorrPushHeld.red1 Lanius.Open.HomedCorrPushPlain.proof
