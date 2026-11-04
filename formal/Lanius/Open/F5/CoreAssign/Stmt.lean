module

public import Lanius.Mini.Refs.Model
public import Lanius.Mini.Views

@[expose] public section

open Lanius.Mini
open Lanius.Core (Value ValueProjection)
open Lanius.Semantics (State)

/-- **Core writes through a place.** With enough fuel, Core's `assign set` of
`e` to the place resolves the place in `st`, evaluates `e` from `st` to
`st₁`, and writes at the path resolved in `st` into the cell's value in
`st₁` (`replaceProjectedValue`, then `assignCell`, as `writeResolvedPlace`
does), when `st₁`'s views hold and none roots at the cell. -/
def Lanius.Open.CoreAssign : Prop :=
  ∀ (prog : Lanius.Core.Program) (st st₁ st' : State) (p : RPlace) (cell : Lanius.CellId)
    (path : List ValueProjection) (e : Lanius.Core.Expr) (old v root root' : Value),
    p.Resolves prog st cell path → Semantics.readCellProjection st cell path = .ok old →
    (∃ N, ∀ fuel, N ≤ fuel → Semantics.evalExpr fuel prog st e = .done v st₁) →
    Semantics.readCellProjection st₁ cell [] = .ok root →
    Semantics.replaceProjectedValue root path v = .ok root' →
    st₁.assignCell cell root' = some st' → Views.ViewsHold st₁ → (∀ w ∈ st₁.i32ArrayViews, w.root ≠ cell) →
    ∃ N, ∀ fuel, N ≤ fuel →
      Semantics.evalExpr fuel prog st (.assign .set p.toCore e) = .done .unit st'
