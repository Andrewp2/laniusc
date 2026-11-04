module

public import Lanius.Mini.Refs.Model

@[expose] public section

open Lanius.Mini
open Lanius.Core (Value ValueProjection)
open Lanius.Semantics (State)

/-- **A home array lent with no copy** (lowering-spec S6b, 6). A call that
passes a homed `i32` or `u8` array as a slice passes two words: the home's
address, `frame + offset` (`addOff`), and its length. The callee's entry
slots there hold Core's slice of the home's cell, from 0 for the whole
length, against the caller's places. This is the view the copy into the
call's block gave (`arrayCall_setup`), with the home in place of the copy's
place. The arguments before and after are any. -/
def Lanius.Open.HomeLendArgs : Prop :=
  ∀ (sx : Statics) (bud : Budget) (places : List Addressed) (st : State) (hp : Heap) (x : Addressed)
    (element : SrcType) (length : Nat) (env : Env) (r offset : Nat) (before after : List Expr),
    Homes sx bud places st hp → x ∈ places → x.ty = .array element length →
    (element = .i32 ∨ element = .uint .uint8) → (env r).toNat + offset = x.address → length < 2 ^ 31 →
    SrcType.HoldsAt sx places (.slice element) (.slice element.toCore x.cell [] 0 length)
      (Func.entry (Expr.evalAll env (before ++ addOff r offset :: .lit (BitVec.ofNat 64 length) :: after)))
      before.length
