import Lanius.Mini.Refs.Model

open Lanius.Mini
open Lanius.Core (Value ValueProjection)
open Lanius.Semantics (State)

/-- **Lending a home array as a slice (`ArrayCall` on homes).** A home that
is an `i32` or `u8` array, lent whole, is held as Core's safe slice of its
cell by its pointer (`Addressed.pointer`, its lowest byte) and its length,
with no copy into a frame block. -/
def Lanius.Open.HomesLend : Prop :=
  ∀ (sx : Statics) (bud : Budget) (places : List Addressed) (st : State) (hp : Heap) (x : Addressed)
    (element : SrcType) (length : Nat) (env : Env) (slot : Nat),
    Homes sx bud places st hp → x ∈ places → x.ty = .array element length →
    (element = .i32 ∨ element = .uint .uint8) →
    (env slot).toNat = x.pointer → (env (slot + 1)).toNat = length → length < 2 ^ 31 →
    SrcType.HoldsAt sx places (.slice element) (.slice element.toCore x.cell [] 0 length) env slot
