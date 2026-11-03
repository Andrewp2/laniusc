import Lanius.Mini.Refs.Homed
import Lanius.Mini.LowerStmt

open Lanius.Mini
open Lanius.Core (Value ValueProjection)
open Lanius.Semantics (State)

/-- **A held value names only the places.** A value held against `places`
names (`Value.Names`: holds a reference or slice into) only the places' cells:
a borrowed slice is of a place, a reference's `RefTo` is into one, and no
other form names a cell. With the lifetime rule's static check that a result
names none of a function's own homes, this gives `HoldsAtDropHomes`'s
hypothesis (stage2-plan.md, 8a). -/
def Lanius.Open.HoldsAtNamesPlaces : Prop :=
  ∀ (sx : Statics) (places : List Addressed) (ty : SrcType) (v : Value) (env : Env) (slot : Nat)
    (cell : Lanius.CellId),
    ty.HoldsAt sx places v env slot → v.Names cell → ∃ x ∈ places, x.cell = cell
