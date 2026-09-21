import Lanius.Semantics.WellFormed

namespace Lanius.Semantics

open Lanius.Core

/-- A well-formed, caller-frame-preserving Core expression execution. -/
def PureExecution (program : Program) (before : State) (expression : Expr)
    (value : Value) (after : State) : Prop :=
  Evaluates program before expression value after ∧
    before.CellsWellFormed ∧
    after.CellsWellFormed ∧
    after.locals = before.locals ∧
    after.heap = before.heap ∧
    after.world = before.world ∧
    after.i32ArrayViews = before.i32ArrayViews

/-- Existential form that hides the evaluator's final bookkeeping state. -/
def PurelyEvaluates (program : Program) (before : State) (expression : Expr)
    (value : Value) : Prop :=
  ∃ after, PureExecution program before expression value after

end Lanius.Semantics
