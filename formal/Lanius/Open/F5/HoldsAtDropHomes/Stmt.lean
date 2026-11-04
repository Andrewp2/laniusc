module

public import Lanius.Mini.Refs.Homed

@[expose] public section

open Lanius.Mini
open Lanius.Core (Value ValueProjection)
open Lanius.Semantics (State)

/-- **A value outlives the homes it does not name.** A value held against the
homes `own ++ places` that names none of `own`'s cells (`Value.Names`) is
held against `places`. A callee's return value must name none of the
callee's homes, which die at the return (`HomesLeave`), to be held against
the caller's; this is the lifetime rule's dynamic side, which its static check
gives. -/
def Lanius.Open.HoldsAtDropHomes : Prop :=
  ∀ (sx : Statics) (own places : List Addressed) (ty : SrcType) (v : Value) (env : Env) (slot : Nat),
    ty.HoldsAt sx (own ++ places) v env slot → (∀ y ∈ own, ¬ v.Names y.cell) → ty.HoldsAt sx places v env slot
