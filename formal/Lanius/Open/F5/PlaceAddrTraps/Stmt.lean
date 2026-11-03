import Lanius.Mini.Refs.Model

open Lanius.Mini
open Lanius.Core (Value ValueProjection)
open Lanius.Semantics (State)

/-- **A place whose resolution traps, traps.** The code of a place whose
resolution traps in Core with a checked trap (`Traps` with
`undefinedTrap r = false`: an index traps so, or is out of range, where
Core traps with `arrayBounds`) stops: it reaches the trap for any
number of ticks. Each index's code runs right after its base's, as Core
evaluates it (`IndexRuns`), so the codes of indices after the trapping one
never run. -/
def Lanius.Open.PlaceAddrTraps : Prop :=
  ∀ (sx : Statics) (bud : Budget) (places : List Addressed) (st st' : State) (hp : Heap) (c : RCtx)
    (p : RPlace) (t : Nat) (code : Stmt) (ty : SrcType) (r : Lanius.Trap) (cprog : Lanius.Core.Program)
    (prog : Program) (depth : Nat) (env : Env) (scratch : List Nat),
    Homes sx bud places st hp → RefsAgree c places st env → p.code c t = some (code, ty) →
    p.Traps cprog st r st' → undefinedTrap r = false →
    p.IndexRuns cprog st prog depth hp env t scratch → t ∉ p.slots c → t ∉ scratch →
    (∀ k ∈ p.slots c, k ∉ scratch) → ∀ n, Stops prog depth env hp code n
