module

public import Lanius.Open.F5.RefsLemmasV2.Red1
public import Lanius.Open.F5.RefLoad.Proof
public import Lanius.Open.F5.RefStoreV2.Proof
public import Lanius.Open.F5.PlaceAddr.Proof
public import Lanius.Open.F5.PlaceAddrTraps.Proof
public import Lanius.Open.F5.HomesLend.Proof
public import Lanius.Open.F5.FrameCorrHomes.Proof
public import Lanius.Open.F5.CorePlace.Proof
public import Lanius.Open.F5.CoreRead.Proof
public import Lanius.Open.F5.CoreAssign.Proof
public import Lanius.Open.F5.CoreAssignOp.Proof
public import Lanius.Open.F5.CoreBorrow.Proof
public import Lanius.Open.F5.HomesPush.Proof
public import Lanius.Open.F5.HomesFrame.Proof
public import Lanius.Open.F5.HomesLeave.Proof
public import Lanius.Open.F5.HomesCongrV2.Proof

@[expose] public section

theorem Lanius.Open.RefsLemmasV2.proof : Lanius.Open.RefsLemmasV2 :=
  Lanius.Open.RefsLemmasV2.red1 Lanius.Open.RefLoad.proof Lanius.Open.RefStoreV2.proof Lanius.Open.PlaceAddr.proof
    Lanius.Open.PlaceAddrTraps.proof Lanius.Open.HomesLend.proof Lanius.Open.FrameCorrHomes.proof
    Lanius.Open.CorePlace.proof Lanius.Open.CoreRead.proof Lanius.Open.CoreAssign.proof Lanius.Open.CoreAssignOp.proof
    Lanius.Open.CoreBorrow.proof Lanius.Open.HomesPush.proof Lanius.Open.HomesFrame.proof Lanius.Open.HomesLeave.proof
    Lanius.Open.HomesCongrV2.proof
