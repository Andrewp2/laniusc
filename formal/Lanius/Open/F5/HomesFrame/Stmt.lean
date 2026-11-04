module

public import Lanius.Mini.Refs.Model

@[expose] public section

open Lanius.Mini
open Lanius.Core (Value ValueProjection)
open Lanius.Semantics (State)

/-- **A callee's frame block.** Lowering the frame pointer by a callee's block
(`Stmt.frame`) keeps the homes, for a callee whose room and block fit in the
caller's room. -/
def Lanius.Open.HomesFrame : Prop :=
  ∀ (sx : Statics) (bud bud' : Budget) (places : List Addressed) (st : State) (hp : Heap),
    Homes sx bud places st hp → bud'.room + bud'.block ≤ bud.room →
    Homes sx bud' places st { hp with fsp := hp.fsp - bud'.block }
