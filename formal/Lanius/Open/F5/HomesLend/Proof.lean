import Lanius.Open.F5.HomesLend.Stmt

open Lanius.Mini
open Lanius.Core (Value ValueProjection)
open Lanius.Semantics (State)

/-- `SrcType.HoldsAt.borrowed`, whose side conditions on the place are
`Homes.sliced` and `Homes.roots`. -/
theorem Lanius.Open.HomesLend.proof : Lanius.Open.HomesLend := by
  intro sx bud places st hp x element length env slot homes hx hty helem hptr hlen hsmall
  exact .borrowed hx (homes.sliced x hx) (homes.roots x hx) hty helem hptr hlen hsmall
