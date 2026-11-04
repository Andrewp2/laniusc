module

public import Lanius.Open.F5.HomedCorrReturn.Red1
public import Lanius.Open.F5.HomedCorrKeeps.Proof
public import Lanius.Open.F5.HomesLeave.Proof
public import Lanius.Open.F5.HoldsAtDropHomes.Proof

@[expose] public section

theorem Lanius.Open.HomedCorrReturn.proof : Lanius.Open.HomedCorrReturn :=
  Lanius.Open.HomedCorrReturn.red1 Lanius.Open.HomedCorrKeeps.proof Lanius.Open.HomesLeave.proof
    Lanius.Open.HoldsAtDropHomes.proof
