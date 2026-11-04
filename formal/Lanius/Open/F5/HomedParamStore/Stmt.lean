module

public import Lanius.Mini.Refs.Homed
public import Lanius.Mini.Refs.Store
public import Lanius.Mini.LowerStmt

@[expose] public section

open Lanius.Mini
open Lanius.Core (Value ValueProjection)
open Lanius.Semantics (State)

/-- **A borrowed parameter's entry store** (lowering-spec S6c, 1). A local of
the scope without a home (a parameter, which Core's call bound), whose slots
from `slot` hold its value, gets a home at its own cell: `t := frame +
offset`, then `ty.homeInit.storeSlots t slot`, as a homed `let`'s first store
(`HomedLetStore`). Then the homes include it as the youngest, and `HomedCorr`
holds for the same scope with the context giving the local that home.
Core's state does not change, and only the home's bytes do.

The local is the scope's binding of `id`; the scope's other ids have other
cells (the parameters' cells are distinct). The home lies in the frame
block, apart from the other places; `t` is no slot of the scope, nor the
frame slot, nor a slot of an unhomed local. -/
def Lanius.Open.HomedParamStore : Prop :=
  ∀ (sx : Statics) (bud : Budget) (places : List Addressed) (scope : List Binding) (frame : Nat → Nat)
    (c : RCtx) (st : State) (hp : Heap) (env : Env) (id slot offset t : Nat) (ty : SrcType)
    (home : Option Nat) (prog : Program) (depth : Nat),
    Homes sx bud places st hp → HomedCorr sx places scope frame c st env →
    lookup scope id = some ⟨id, slot, ty, home⟩ → c.homes.lookup id = none →
    (∀ b ∈ scope, b.id ≠ id → frame b.slot ≠ frame slot) →
    ty.homeOk = true → ty.tagsFit = true →
    (env c.frame).toNat = hp.fsp → 0 < bud.block → offset + 8 * ty.words ≤ bud.block →
    (∀ y ∈ places, hp.fsp + offset + 8 * ty.words ≤ y.address ∨ y.address + 8 * y.ty.words ≤ hp.fsp + offset) →
    (∀ b ∈ scope, ∀ i < b.ty.size, b.slot + i ≠ t) → c.frame ≠ t →
    (∀ id', c.homes.lookup id' = none → c.slotOf id' ≠ t) →
    ∃ hp', Exec prog depth env hp (.seq (.assign t (addOff c.frame offset)) (ty.homeInit.storeSlots t slot))
        (.normal (env.set t (BitVec.ofNat 64 (hp.fsp + offset))) hp') ∧
      Homes sx bud (⟨frame slot, [], ty, hp.fsp + offset, true⟩ :: places) st hp' ∧
      HomedCorr sx (⟨frame slot, [], ty, hp.fsp + offset, true⟩ :: places) scope frame
        { c with homes := (id, offset, ty) :: c.homes } st (env.set t (BitVec.ofNat 64 (hp.fsp + offset))) ∧
      { hp' with bytes := hp.bytes } = hp ∧
      ∀ b, (b < hp.fsp + offset ∨ hp.fsp + offset + 8 * ty.words ≤ b) → hp'.bytes b = hp.bytes b
