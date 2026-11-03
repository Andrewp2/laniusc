import Lanius.Mini.Refs.Homed
import Lanius.Mini.LowerStmt

open Lanius.Mini
open Lanius.Core (Value ValueProjection)
open Lanius.Semantics (State)

/-- **A home born inside the statement.** A homed `let` creates its home's
cell at the next cell, at or above the statement's `base`; keeping the cells
below `base` apart from `x :: places` is keeping those apart from `places`. -/
def Lanius.Open.KeepsConsAbove : Prop :=
  ∀ (x : Addressed) (places : List Addressed) (base : Nat) (st st' : State),
    Keeps (x :: places) base st st' → base ≤ x.cell → Keeps places base st st'
