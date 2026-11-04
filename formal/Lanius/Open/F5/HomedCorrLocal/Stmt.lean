module

public import Lanius.Mini.Refs.Homed

@[expose] public section

open Lanius.Mini
open Lanius.Core (Value ValueProjection)
open Lanius.Semantics (State)

/-- **Corr for homed locals: a local's value.** Under `HomedCorr` and `Homes`,
Core's read of a local in scope (`.local id`, the innermost binding `b`) gives
a value that, for a local without a home, its slots hold (as `Corr.local`),
and for a homed local, its home holds and not its slots: the home the context
finds (`lookup`), at the frame block's address in slot `c.frame` plus its
offset, of the binding's type, whose bytes represent the value against the
older homes. -/
def Lanius.Open.HomedCorrLocal : Prop :=
  ∀ (sx : Statics) (bud : Budget) (places : List Addressed) (scope : List Binding) (frame : Nat → Nat)
    (c : RCtx) (st : State) (env : Env) (hp : Heap) (prog : Lanius.Core.Program) (id : Nat) (b : Binding),
    HomedCorr sx places scope frame c st env → Homes sx bud places st hp → lookup scope id = some b →
    ∃ v, (∀ fuel, Semantics.evalExpr (fuel + 1) prog st (.local id) = .done v st) ∧
      ((c.homes.lookup id = none ∧ b.ty.HoldsAt sx places v env b.slot) ∨
        ∃ (offset i : Nat) (x : Addressed), c.homes.lookup id = some (offset, b.ty) ∧ places[i]? = some x ∧
          x.cell = frame b.slot ∧ x.ty = b.ty ∧ x.address = (env c.frame).toNat + offset ∧
          x.ty.HoldsAt sx (places.drop (i + 1)) v (x.ty.homeView x.address hp) 0)
