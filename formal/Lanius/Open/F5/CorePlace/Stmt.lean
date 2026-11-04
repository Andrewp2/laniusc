module

public import Lanius.Mini.Refs.Model

@[expose] public section

open Lanius.Mini
open Lanius.Core (Value ValueProjection)
open Lanius.Semantics (State)

/-- **Core resolves a place.** With enough fuel, Core's `evalPlace` of the
place (for a read or an address) gives the cell and path `Resolves` names,
no raw storage, and the value there, without changing the state; where the
place's resolution traps (`Traps`, in Core's order) it traps with that
reason and state. -/
def Lanius.Open.CorePlace : Prop :=
  ∀ (prog : Lanius.Core.Program) (st : State) (p : RPlace) (access : Semantics.PlaceAccess),
    (∀ (cell : Lanius.CellId) (path : List ValueProjection) (v : Value),
      p.Resolves prog st cell path → Semantics.readCellProjection st cell path = .ok v →
      ∃ N, ∀ fuel, N ≤ fuel → ∃ r : Semantics.ResolvedPlace,
        Semantics.evalPlace fuel prog st access p.toCore = .done r st ∧
        r.root = cell ∧ r.projections = path ∧ r.raw = none ∧ r.value = some v) ∧
    (∀ (r : Lanius.Trap) (st' : State), p.Traps prog st r st' → ∃ N, ∀ fuel, N ≤ fuel →
      Semantics.evalPlace fuel prog st access p.toCore = .trapped r st')
