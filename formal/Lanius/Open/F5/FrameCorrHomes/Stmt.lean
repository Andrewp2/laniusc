module

public import Lanius.Mini.Refs.Model

@[expose] public section

open Lanius.Mini
open Lanius.Core (Value ValueProjection)
open Lanius.Semantics (State)

/-- **`FrameCorr`'s places are homes.** The lent arrays `FrameCorr` keeps
(packed, whole, above the activation's block) are homes, so `ArrayCall` and
`Borrowed` can move onto `Homes`, which then replaces `FrameCorr` (one
places list cannot serve both). -/
def Lanius.Open.FrameCorrHomes : Prop :=
  ∀ (sx : Statics) (bud : Budget) (places : List Addressed) (st : State) (hp : Heap),
    FrameCorr sx bud places st hp → places.Nodup → Homes sx bud places st hp
