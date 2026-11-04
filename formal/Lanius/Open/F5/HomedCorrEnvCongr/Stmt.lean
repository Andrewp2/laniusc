module

public import Lanius.Mini.Refs.Homed
public import Lanius.Mini.LowerStmt

@[expose] public section

open Lanius.Mini
open Lanius.Core (Value ValueProjection)
open Lanius.Semantics (State)

/-- **Other slots change.** `HomedCorr` holds at an `env'` that agrees with
`env` on the scope's slots, the frame slot and the slots of the reference
locals without homes (`Corr.env_congr`'s analogue: a temporary's code keeps
it). -/
def Lanius.Open.HomedCorrEnvCongr : Prop :=
  ∀ (sx : Statics) (places : List Addressed) (scope : List Binding) (frame : Nat → Nat) (c : RCtx)
    (st : State) (env env' : Env),
    HomedCorr sx places scope frame c st env → ScopeAgree scope env env' → env' c.frame = env c.frame →
    (∀ id, c.homes.lookup id = none → env' (c.slotOf id) = env (c.slotOf id)) →
    HomedCorr sx places scope frame c st env'
