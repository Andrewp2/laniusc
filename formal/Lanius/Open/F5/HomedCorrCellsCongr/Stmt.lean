module

public import Lanius.Mini.Refs.Homed
public import Lanius.Mini.LowerStmt

@[expose] public section

open Lanius.Mini
open Lanius.Core (Value ValueProjection)
open Lanius.Semantics (State)

/-- **Other cells change.** `HomedCorr` holds in a state with the same locals
and views whose views hold, when the cells of the scope's unhomed bindings
that are not viewed arrays are as they were (`Corr.cells_congr`'s analogue).
A write through a reference changes only a home's cell, so `HomedCorr` holds
after it. -/
def Lanius.Open.HomedCorrCellsCongr : Prop :=
  ∀ (sx : Statics) (places : List Addressed) (scope : List Binding) (frame : Nat → Nat) (c : RCtx)
    (st st' : State) (env : Env),
    HomedCorr sx places scope frame c st env → st'.locals = st.locals →
    (∀ b ∈ scope, Unhomed places frame b → viewedType b.ty = false →
      st'.cellEntry? (frame b.slot) = st.cellEntry? (frame b.slot)) →
    Views.ViewsHold st' → st'.i32ArrayViews = st.i32ArrayViews →
    HomedCorr sx places scope frame c st' env
