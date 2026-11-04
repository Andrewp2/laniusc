import Lanius.Mini.Refs.Homed
import Lanius.Mini.LowerStmt

open Lanius.Mini
open Lanius.Core (Value ValueProjection)
open Lanius.Semantics (State)

/-- **A homed `let`.** A `let` whose local the program borrows binds it in
Core to the next cell (`bindLocal`), at slot `next` past the scope's slots,
and gives it a home `x` at that cell: the frame block's address in slot
`c.frame` plus `offset`, of the local's type. Its value is in the home
(`HomesPush` adds the home to `Homes`), not its slots. Then `HomedCorr` holds
for the longer scope, with the home youngest among the places and the
context's homes, when the code kept the scope's slots, the frame slot, and
the slots of the reference locals without homes.

Replaces `HomedCorrPush`, which stopped elaborating when `Binding` gained `home`
(F5 S6a-2): the `let`'s binding has any home (`OPEN_STATEMENTS.md`, "Deleting a
statement"). -/
def Lanius.Open.HomedCorrPushV2 : Prop :=
  ∀ (sx : Statics) (places : List Addressed) (scope : List Binding) (frame : Nat → Nat) (c : RCtx)
    (st : State) (env env' : Env) (base next id offset : Nat) (ty : SrcType) (home : Option Nat) (v : Value) (x : Addressed),
    HomedCorr sx places scope frame c st env → Layout scope frame base next → st.Fresh →
    ScopeAgree scope env env' → (∀ y ∈ places, y.cell < st.nextCell) → env' c.frame = env c.frame →
    (∀ id', c.homes.lookup id' = none → env' (c.slotOf id') = env (c.slotOf id')) →
    x.cell = st.nextCell → x.ty = ty → x.address = (env c.frame).toNat + offset →
    HomedCorr sx (x :: places) (⟨id, next, ty, home⟩ :: scope) (upd frame next st.nextCell)
      { c with homes := (id, offset, ty) :: c.homes } (st.bindLocal id v) env'
