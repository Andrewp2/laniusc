module

public import Lanius.Mini.Refs.Homed
public import Lanius.Mini.LowerStmt

@[expose] public section

open Lanius.Mini
open Lanius.Core (Value ValueProjection)
open Lanius.Semantics (State)

/-- **A return, for the caller.** The caller had `HomedCorr` over its homes
`places` before the call. The callee ran from `st` to `st'`, changing only
the caller's homes' cells below the caller's next cell (`Keeps`), and returns
with the caller's locals restored, `Homes` over its own homes `own` (the
youngest) and the caller's, and its result `v` held in its slots against
both. When `v` names none of the callee's homes (the lifetime rule), then
after the return, with the caller's frame pointer `f` back (the call rule):
the caller's `HomedCorr` holds at `st'`, its homes hold (`HomesLeave`), and
the result is held against its homes alone (`HoldsAtDropHomes`; a returned
reference by `HoldsAt.ref`). -/
def Lanius.Open.HomedCorrReturn : Prop :=
  ∀ (sx : Statics) (bud bud' : Budget) (own places : List Addressed) (scope : List Binding) (frame : Nat → Nat)
    (c : RCtx) (st st' : State) (hp : Heap) (f : Nat) (env envR : Env) (ty : SrcType) (v : Value) (slot : Nat),
    HomedCorr sx places scope frame c st env → st.Fresh → Keeps places st.nextCell st st' →
    st'.locals = st.locals → Homes sx bud' (own ++ places) st' hp → (∀ x ∈ places, f ≤ x.address) →
    (0 < bud.room + bud.block → hp.limit + bud.room ≤ f) →
    (0 < bud.room + bud.block → f + bud.block ≤ hp.top) →
    (0 < bud.room + bud.block → hp.top < 2 ^ 62) →
    ty.HoldsAt sx (own ++ places) v envR slot → (∀ y ∈ own, ¬ v.Names y.cell) →
    HomedCorr sx places scope frame c st' env ∧ Homes sx bud places st' { hp with fsp := f } ∧
      ty.HoldsAt sx places v envR slot
