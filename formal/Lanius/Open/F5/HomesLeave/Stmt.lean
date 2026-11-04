module

public import Lanius.Mini.Refs.Model

@[expose] public section

open Lanius.Mini
open Lanius.Core (Value ValueProjection)
open Lanius.Semantics (State)

/-- **A return.** Dropping the callee's own homes, the youngest ones, and
restoring the caller's frame pointer `f` (the call rule) keeps the caller's
homes: they lie above `f`, and by the age order their values name none of
the callee's homes. -/
def Lanius.Open.HomesLeave : Prop :=
  ∀ (sx : Statics) (bud bud' : Budget) (own places : List Addressed) (st : State) (hp : Heap) (f : Nat),
    Homes sx bud' (own ++ places) st hp → (∀ x ∈ places, f ≤ x.address) →
    (0 < bud.room + bud.block → hp.limit + bud.room ≤ f) →
    (0 < bud.room + bud.block → f + bud.block ≤ hp.top) →
    (0 < bud.room + bud.block → hp.top < 2 ^ 62) →
    Homes sx bud places st { hp with fsp := f }
