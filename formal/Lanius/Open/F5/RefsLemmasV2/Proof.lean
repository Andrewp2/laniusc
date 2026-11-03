import Lanius.Open.F5.RefsLemmasV2.Red1
import Lanius.Open.F5.RefLoad.Proof
import Lanius.Open.F5.RefStoreV2.Proof
import Lanius.Open.F5.PlaceAddr.Proof
import Lanius.Open.F5.PlaceAddrTraps.Proof
import Lanius.Open.F5.HomesLend.Proof
import Lanius.Open.F5.FrameCorrHomes.Proof
import Lanius.Open.F5.CorePlace.Proof
import Lanius.Open.F5.CoreRead.Proof
import Lanius.Open.F5.CoreAssign.Proof
import Lanius.Open.F5.CoreAssignOp.Proof
import Lanius.Open.F5.CoreBorrow.Proof
import Lanius.Open.F5.HomesPush.Proof
import Lanius.Open.F5.HomesFrame.Proof
import Lanius.Open.F5.HomesLeave.Proof
import Lanius.Open.F5.HomesCongrV2.Proof

theorem Lanius.Open.RefsLemmasV2.proof : Lanius.Open.RefsLemmasV2 :=
  Lanius.Open.RefsLemmasV2.red1 Lanius.Open.RefLoad.proof Lanius.Open.RefStoreV2.proof Lanius.Open.PlaceAddr.proof
    Lanius.Open.PlaceAddrTraps.proof Lanius.Open.HomesLend.proof Lanius.Open.FrameCorrHomes.proof
    Lanius.Open.CorePlace.proof Lanius.Open.CoreRead.proof Lanius.Open.CoreAssign.proof Lanius.Open.CoreAssignOp.proof
    Lanius.Open.CoreBorrow.proof Lanius.Open.HomesPush.proof Lanius.Open.HomesFrame.proof Lanius.Open.HomesLeave.proof
    Lanius.Open.HomesCongrV2.proof
