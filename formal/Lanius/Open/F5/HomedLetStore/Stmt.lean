module

public import Lanius.Mini.Refs.Homed
public import Lanius.Mini.Refs.Store
public import Lanius.Mini.LowerStmt

@[expose] public section

open Lanius.Mini
open Lanius.Core (Value ValueProjection)
open Lanius.Semantics (State)

/-- **A homed `let`'s first store** (lowering-spec S6b, 3). The `let`'s value
is in the slots from `next` (its code ran), held against the places. Then
`t := frame + offset` (`RPlace.code` of the home) and
`ty.homeInit.storeSlots t next` give the local a home at Core's next cell, at
the frame block's address in slot `c.frame` plus `offset`: the homes then
include it as the youngest (`Homes`), and `HomedCorr` holds for the scope
with the local's binding, homed at `offset`, after Core binds it
(`bindLocal`). Only the home's bytes change.

The home lies in the frame block (`offset + 8 * words ≤ block`, a block's
first byte in `c.frame`), apart from the other places; `t` is a scratch slot
past the value's slots, not the frame slot nor a slot of an unhomed local.
The type is `homeOk` and its enums' tags fit their words (`tagsFit`). -/
def Lanius.Open.HomedLetStore : Prop :=
  ∀ (sx : Statics) (bud : Budget) (places : List Addressed) (scope : List Binding) (frame : Nat → Nat)
    (c : RCtx) (st : State) (hp : Heap) (env : Env) (base next id offset t : Nat) (ty : SrcType) (v : Value)
    (prog : Program) (depth : Nat),
    Homes sx bud places st hp → HomedCorr sx places scope frame c st env → Layout scope frame base next →
    st.Fresh → (∀ y ∈ places, y.cell < st.nextCell) →
    ty.HoldsAt sx places v env next → ty.homeOk = true → ty.tagsFit = true →
    (env c.frame).toNat = hp.fsp → 0 < bud.block → offset + 8 * ty.words ≤ bud.block →
    (∀ y ∈ places, hp.fsp + offset + 8 * ty.words ≤ y.address ∨ y.address + 8 * y.ty.words ≤ hp.fsp + offset) →
    next + ty.size ≤ t → c.frame ≠ t → (∀ id', c.homes.lookup id' = none → c.slotOf id' ≠ t) →
    ∃ hp', Exec prog depth env hp (.seq (.assign t (addOff c.frame offset)) (ty.homeInit.storeSlots t next))
        (.normal (env.set t (BitVec.ofNat 64 (hp.fsp + offset))) hp') ∧
      Homes sx bud (⟨st.nextCell, [], ty, hp.fsp + offset, true⟩ :: places) (st.bindLocal id v) hp' ∧
      HomedCorr sx (⟨st.nextCell, [], ty, hp.fsp + offset, true⟩ :: places) (⟨id, next, ty, some offset⟩ :: scope)
        (upd frame next st.nextCell) { c with homes := (id, offset, ty) :: c.homes } (st.bindLocal id v)
        (env.set t (BitVec.ofNat 64 (hp.fsp + offset))) ∧
      { hp' with bytes := hp.bytes } = hp ∧
      ∀ b, (b < hp.fsp + offset ∨ hp.fsp + offset + 8 * ty.words ≤ b) → hp'.bytes b = hp.bytes b
