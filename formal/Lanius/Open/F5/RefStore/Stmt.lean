import Lanius.Mini.Refs.Model

open Lanius.Mini
open Lanius.Core (Value ValueProjection)
open Lanius.Semantics (State)

/-- **A write through a reference.** Storing slots that hold `v` at the
sub-place at `path` of a home (`storeSlots`, to the lowest byte in slot `r`)
matches Core's write of `v` at that path (`replaceProjectedValue`, then
`assignCell`): the homes still correspond, and only the sub-place's bytes
change. `v`'s slices and references name only older homes (the lifetime
rule's static check). -/
def Lanius.Open.RefStore : Prop :=
  ∀ (sx : Statics) (bud : Budget) (places : List Addressed) (st st' : State) (hp : Heap) (i : Nat)
    (x : Addressed) (path : List ValueProjection) (address : Nat) (ty : SrcType) (v root root' : Value)
    (prog : Program) (depth : Nat) (env : Env) (r slot : Nat),
    Homes sx bud places st hp → places[i]? = some x → x.sub path = some (address, ty) →
    (env r).toNat = address → ty.HoldsAt sx (places.drop (i + 1)) v env slot →
    Semantics.readCellProjection st x.cell [] = .ok root →
    Semantics.replaceProjectedValue root path v = .ok root' →
    st.assignCell x.cell root' = some st' →
    ∃ hp', Exec prog depth env hp (ty.storeSlots r slot) (.normal env hp') ∧
      Homes sx bud places st' hp' ∧ { hp' with bytes := hp.bytes } = hp ∧
      ∀ b, (b < address ∨ address + ty.span ≤ b) → hp'.bytes b = hp.bytes b
