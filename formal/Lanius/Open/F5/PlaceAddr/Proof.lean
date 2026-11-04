module

public import Lanius.Open.F5.PlaceAddr.Stmt
public import Lanius.Mini.Refs.Place

@[expose] public section

open Lanius.Mini

/-- Induction on the place (`RPlace.addr_exec`): a home's address from
`RefsAgree.homes`, a reference local's from `RefsAgree.refs`, a field adds its
offset, and an element runs its index's code from slots that agree outside
`scratch` and `t`, passes the bounds check (Core's read gives the index below
the length) and adds its offset. -/
theorem Lanius.Open.PlaceAddr.proof : Lanius.Open.PlaceAddr := by
  intro sx bud places st hp c p t code ty cell path v cprog prog depth env scratch homes agree hcode hres hruns
    hread _ tout _
  exact RPlace.addr_exec homes agree tout p hcode hres hruns hread
