module

public import Lanius.Mini.Refs.Homed
public import Lanius.Mini.LowerStmt

@[expose] public section

open Lanius.Mini
open Lanius.Core (Value ValueProjection)
open Lanius.Semantics (State)

/-- **No homes in the scope.** `HomedCorr` whose scope's cells are none of the
places' is `Corr`: every binding is unhomed, so its value is in its slots.
The bridge for stage 2's first step, while no function has a home
(stage2-plan.md, P2). -/
def Lanius.Open.HomedCorrToCorr : Prop :=
  ∀ (sx : Statics) (places : List Addressed) (scope : List Binding) (frame : Nat → Nat) (c : RCtx)
    (st : State) (env : Env),
    HomedCorr sx places scope frame c st env → (∀ x ∈ places, ∀ b ∈ scope, x.cell ≠ frame b.slot) →
    Corr sx places scope frame st env
