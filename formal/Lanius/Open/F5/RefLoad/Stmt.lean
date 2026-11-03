import Lanius.Mini.Refs.Model

open Lanius.Mini
open Lanius.Core (Value ValueProjection)
open Lanius.Semantics (State)

/-- **A read through a reference.** Loading the sub-place at `path` of a home
(`loadSlots`, from the lowest byte in slot `r`) gives slots from `target`
that hold Core's value at that path, its slices and references naming only
homes older than this one, and changes no other slot or the heap. -/
def Lanius.Open.RefLoad : Prop :=
  ∀ (sx : Statics) (bud : Budget) (places : List Addressed) (st : State) (hp : Heap) (i : Nat)
    (x : Addressed) (path : List ValueProjection) (address : Nat) (ty : SrcType) (v : Value)
    (prog : Program) (depth : Nat) (env : Env) (r target : Nat),
    Homes sx bud places st hp → places[i]? = some x → x.sub path = some (address, ty) →
    Semantics.readCellProjection st x.cell path = .ok v →
    (env r).toNat = address → (r < target ∨ target + ty.size ≤ r) →
    ∃ env', Exec prog depth env hp (ty.loadSlots r target) (.normal env' hp) ∧
      ty.HoldsAt sx (places.drop (i + 1)) v env' target ∧
      ∀ s, (s < target ∨ target + ty.size ≤ s) → env' s = env s
