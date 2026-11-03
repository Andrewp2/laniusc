import Lanius.Mini.Refs.Model

open Lanius.Mini
open Lanius.Core (Value ValueProjection)
open Lanius.Semantics (State)

/-- **A borrow's word, as a held value.** `BorrowRefHeld`'s conclusion at the
reference type: the word the place's code leaves in `t` holds Core's
reference at `.ref ty` (`HoldsAt.ref`), the form a let or an argument of
reference type needs. -/
def Lanius.Open.BorrowHoldsAt : Prop :=
  ∀ (sx : Statics) (bud : Budget) (places : List Addressed) (st : State) (hp : Heap) (c : RCtx)
    (p : RPlace) (t : Nat) (code : Stmt) (ty : SrcType) (cell : Lanius.CellId)
    (path : List ValueProjection) (v : Value) (cprog : Lanius.Core.Program) (prog : Program)
    (depth : Nat) (env : Env) (scratch : List Nat),
    Homes sx bud places st hp → RefsAgree c places st env → p.code c t = some (code, ty) →
    p.Resolves cprog st cell path → p.IndexRuns cprog st prog depth hp env t scratch →
    Semantics.readCellProjection st cell path = .ok v → t ∉ scratch →
    ∃ env' : Env, Exec prog depth env hp code (.normal env' hp) ∧
      (SrcType.ref ty).HoldsAt sx places (.reference ty.toCore cell path) env' t ∧
      ∀ k, k ∉ scratch → k ≠ t → env' k = env k
