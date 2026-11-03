import Lanius.Mini.Refs.Model

open Lanius.Mini
open Lanius.Core (Value ValueProjection)
open Lanius.Semantics (State)

/-- **Core borrows a place.** With enough fuel, Core's `borrow` of the place
is the reference to the cell and path `Resolves` names, and the state does
not change. -/
def Lanius.Open.CoreBorrow : Prop :=
  ∀ (prog : Lanius.Core.Program) (st : State) (p : RPlace) (cell : Lanius.CellId)
    (path : List ValueProjection) (v : Value) (T : Lanius.Core.Ty),
    p.Resolves prog st cell path → Semantics.readCellProjection st cell path = .ok v →
    ∃ N, ∀ fuel, N ≤ fuel →
      Semantics.evalExpr fuel prog st (.borrow T p.toCore) = .done (.reference T cell path) st
