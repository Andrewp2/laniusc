import Lanius.Open.F5.HomedCorrReturn.Red1
import Lanius.Open.F5.HomedCorrKeeps.Proof
import Lanius.Open.F5.HomesLeave.Proof
import Lanius.Open.F5.HoldsAtDropHomes.Proof

theorem Lanius.Open.HomedCorrReturn.proof : Lanius.Open.HomedCorrReturn :=
  Lanius.Open.HomedCorrReturn.red1 Lanius.Open.HomedCorrKeeps.proof Lanius.Open.HomesLeave.proof
    Lanius.Open.HoldsAtDropHomes.proof
