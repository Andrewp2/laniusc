module

public import Lanius.Open.F5.RefsLemmasV2.Stmt

@[expose] public section

/-- The conjunction of its leaves. -/
theorem Lanius.Open.RefsLemmasV2.red1 (h0 : Lanius.Open.RefLoad) (h1 : Lanius.Open.RefStoreV2) (h2 : Lanius.Open.PlaceAddr) (h3 : Lanius.Open.PlaceAddrTraps) (h4 : Lanius.Open.HomesLend) (h5 : Lanius.Open.FrameCorrHomes) (h6 : Lanius.Open.CorePlace) (h7 : Lanius.Open.CoreRead) (h8 : Lanius.Open.CoreAssign) (h9 : Lanius.Open.CoreAssignOp) (h10 : Lanius.Open.CoreBorrow) (h11 : Lanius.Open.HomesPush) (h12 : Lanius.Open.HomesFrame) (h13 : Lanius.Open.HomesLeave) (h14 : Lanius.Open.HomesCongrV2) :
    Lanius.Open.RefsLemmasV2 :=
  ⟨h0, h1, h2, h3, h4, h5, h6, h7, h8, h9, h10, h11, h12, h13, h14⟩
