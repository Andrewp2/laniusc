import Lanius.Mini.Refs.Model

open Lanius.Mini
open Lanius.Core (Value ValueProjection)
open Lanius.Semantics (State)

/-- **A place's address.** The code of a place (`RPlace.code`) puts in slot
`t` the lowest byte of the sub-place Core's place names (`Resolves`), when
Core can read it, each index's code running right after its base's
(`IndexRuns`, Core's order). It leaves the heap and every slot outside the
index codes' `scratch` slots as they were. -/
def Lanius.Open.PlaceAddr : Prop :=
  ∀ (sx : Statics) (bud : Budget) (places : List Addressed) (st : State) (hp : Heap) (c : RCtx)
    (p : RPlace) (t : Nat) (code : Stmt) (ty : SrcType) (cell : Lanius.CellId)
    (path : List ValueProjection) (v : Value) (cprog : Lanius.Core.Program) (prog : Program)
    (depth : Nat) (env : Env) (scratch : List Nat),
    Homes sx bud places st hp → RefsAgree c places st env → p.code c t = some (code, ty) →
    p.Resolves cprog st cell path → p.IndexRuns cprog st prog depth hp env t scratch →
    Semantics.readCellProjection st cell path = .ok v → t ∉ p.slots c → t ∉ scratch →
    (∀ k ∈ p.slots c, k ∉ scratch) →
    ∃ x ∈ places, ∃ (address : Nat) (env' : Env), x.cell = cell ∧ x.sub path = some (address, ty) ∧
      Exec prog depth env hp code (.normal env' hp) ∧ env' t = BitVec.ofNat 64 address ∧
      ∀ k, k ∉ scratch → k ≠ t → env' k = env k
