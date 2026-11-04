module

public import Lanius.Mini.Refs.Model

@[expose] public section

open Lanius.Mini
open Lanius.Core (Value ValueProjection)
open Lanius.Semantics (State)

/-- **A place load in an eval position** (lowering-spec S6b, 4). The place's
code (`RPlace.code`) into slot `t`, then `ty.loadSlots t target`, leaves the
place's value in the slots from `target`, held against all the places (the
current ones, as an eval case's result is), and keeps the heap and every slot
outside the index codes' `scratch`, `t` and the target slots. `LentHomes`
gives the `Homes` here (`LentHomes.homes`), as does P3's invariant. -/
def Lanius.Open.PlaceLoadHeld : Prop :=
  ∀ (sx : Statics) (bud : Budget) (places : List Addressed) (st : State) (hp : Heap) (c : RCtx)
    (p : RPlace) (t : Nat) (code : Stmt) (ty : SrcType) (cell : Lanius.CellId)
    (path : List ValueProjection) (v : Value) (cprog : Lanius.Core.Program) (prog : Program)
    (depth : Nat) (env : Env) (scratch : List Nat) (target : Nat),
    Homes sx bud places st hp → RefsAgree c places st env → p.code c t = some (code, ty) →
    p.Resolves cprog st cell path → p.IndexRuns cprog st prog depth hp env t scratch →
    Semantics.readCellProjection st cell path = .ok v → t ∉ p.slots c → t ∉ scratch →
    (∀ k ∈ p.slots c, k ∉ scratch) → (t < target ∨ target + ty.size ≤ t) →
    ∃ (x : Addressed) (env' : Env), x ∈ places ∧ x.cell = cell ∧
      Exec prog depth env hp (.seq code (ty.loadSlots t target)) (.normal env' hp) ∧
      ty.HoldsAt sx places v env' target ∧
      ∀ k, k ∉ scratch → k ≠ t → (k < target ∨ target + ty.size ≤ k) → env' k = env k
