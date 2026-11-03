import Lanius.Mini.Refs.Model

open Lanius.Mini
open Lanius.Core (Value ValueProjection)
open Lanius.Semantics (State)

/-- **A read of a place.** The lowering of a read of a place through a home
or a reference (lowering-spec "Deref load"): the place's code
(`RPlace.code`) into slot `t`, then `ty.loadSlots t target`. When Core can
read the place, the slots from `target` hold its value (`HoldsAt`, for the
homes below the one it is in), and the heap and every slot outside the
index codes' `scratch`, `t` and the target slots are as they were. -/
def Lanius.Open.PlaceLoad : Prop :=
  ∀ (sx : Statics) (bud : Budget) (places : List Addressed) (st : State) (hp : Heap) (c : RCtx)
    (p : RPlace) (t : Nat) (code : Stmt) (ty : SrcType) (cell : Lanius.CellId)
    (path : List ValueProjection) (v : Value) (cprog : Lanius.Core.Program) (prog : Program)
    (depth : Nat) (env : Env) (scratch : List Nat) (target : Nat),
    Homes sx bud places st hp → RefsAgree c places st env → p.code c t = some (code, ty) →
    p.Resolves cprog st cell path → p.IndexRuns cprog st prog depth hp env t scratch →
    Semantics.readCellProjection st cell path = .ok v → t ∉ p.slots c → t ∉ scratch →
    (∀ k ∈ p.slots c, k ∉ scratch) → (t < target ∨ target + ty.size ≤ t) →
    ∃ (i : Nat) (x : Addressed) (env' : Env), places[i]? = some x ∧ x.cell = cell ∧
      Exec prog depth env hp (.seq code (ty.loadSlots t target)) (.normal env' hp) ∧
      ty.HoldsAt sx (places.drop (i + 1)) v env' target ∧
      ∀ k, k ∉ scratch → k ≠ t → (k < target ∨ target + ty.size ≤ k) → env' k = env k
