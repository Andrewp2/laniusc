module

public import Lanius.Mini.Refs.Model

@[expose] public section

open Lanius.Mini
open Lanius.Core (Value ValueProjection)
open Lanius.Semantics (State)

/-- **Core reads a place.** With enough fuel, Core's read of the place as the
front end writes it (`RPlace.read`: `dereference`, then value-level fields
and elements) gives the value at the cell and path `Resolves` names, without
changing the state; where the place's resolution traps (`Traps`) it traps
with that reason and state. -/
def Lanius.Open.CoreRead : Prop :=
  ∀ (prog : Lanius.Core.Program) (st : State) (p : RPlace),
    (∀ (cell : Lanius.CellId) (path : List ValueProjection) (v : Value),
      p.Resolves prog st cell path → Semantics.readCellProjection st cell path = .ok v →
      ∃ N, ∀ fuel, N ≤ fuel → Semantics.evalExpr fuel prog st p.read = .done v st) ∧
    (∀ (r : Lanius.Trap) (st' : State), p.Traps prog st r st' →
      ∃ N, ∀ fuel, N ≤ fuel → Semantics.evalExpr fuel prog st p.read = .trapped r st')
