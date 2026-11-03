import Lanius.Mini.Refs.Model

open Lanius.Mini
open Lanius.Core (Value ValueProjection)
open Lanius.Semantics (State)

/-- **A borrow's word.** The code of a borrowed place (`RPlace.code`, under
`PlaceAddr`'s hypotheses) ends with a word in slot `t` that represents Core's
reference to the place at the code's type `ty` (`RefHeld`: the lowest byte
of the sub-place of a home at the cell and path `Resolves` names), and the
slots outside the index codes' `scratch` and `t` as they were. This is what a
call passing `&p` or `&mut p` puts in the argument's slot. -/
def Lanius.Open.BorrowRefHeld : Prop :=
  ∀ (sx : Statics) (bud : Budget) (places : List Addressed) (st : State) (hp : Heap) (c : RCtx)
    (p : RPlace) (t : Nat) (code : Stmt) (ty : SrcType) (cell : Lanius.CellId)
    (path : List ValueProjection) (v : Value) (cprog : Lanius.Core.Program) (prog : Program)
    (depth : Nat) (env : Env) (scratch : List Nat),
    Homes sx bud places st hp → RefsAgree c places st env → p.code c t = some (code, ty) →
    p.Resolves cprog st cell path → p.IndexRuns cprog st prog depth hp env t scratch →
    Semantics.readCellProjection st cell path = .ok v → t ∉ scratch →
    ∃ env' : Env, Exec prog depth env hp code (.normal env' hp) ∧
      RefHeld places ty (.reference ty.toCore cell path) (env' t) ∧
      ∀ k, k ∉ scratch → k ≠ t → env' k = env k
