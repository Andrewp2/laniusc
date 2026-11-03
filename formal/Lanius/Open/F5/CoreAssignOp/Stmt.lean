import Lanius.Mini.Refs.Model
import Lanius.Mini.Views

open Lanius.Mini
open Lanius.Core (Value ValueProjection)
open Lanius.Semantics (State)

/-- **Compound assignment through a place** (`self.front += 1`). With enough
fuel, Core's `assign op` for `op ≠ set` reads the place's old value in `st`
when it resolves the place, before the right side, evaluates `e` from `st`
to `st₁`, combines the two (`evalAssignValue`), and writes the result at the
path into the cell's value in `st₁`, when `st₁`'s views hold and none roots
at the cell. -/
def Lanius.Open.CoreAssignOp : Prop :=
  ∀ (prog : Lanius.Core.Program) (st st₁ st' : State) (p : RPlace) (cell : Lanius.CellId)
    (path : List ValueProjection) (e : Lanius.Core.Expr) (op : Lanius.Core.AssignOp)
    (old v result root root' : Value),
    op ≠ .set → p.Resolves prog st cell path → Semantics.readCellProjection st cell path = .ok old →
    (∃ N, ∀ fuel, N ≤ fuel → Semantics.evalExpr fuel prog st e = .done v st₁) →
    Semantics.evalAssignValue prog.target op (some old) v = .ok result →
    Semantics.readCellProjection st₁ cell [] = .ok root →
    Semantics.replaceProjectedValue root path result = .ok root' →
    st₁.assignCell cell root' = some st' → Views.ViewsHold st₁ → (∀ w ∈ st₁.i32ArrayViews, w.root ≠ cell) →
    ∃ N, ∀ fuel, N ≤ fuel →
      Semantics.evalExpr fuel prog st (.assign op p.toCore e) = .done .unit st'
