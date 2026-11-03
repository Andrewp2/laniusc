import Lanius.Open.F5.PlaceAddrTraps.Stmt
import Lanius.Mini.Refs.Place

open Lanius.Mini

/-- Induction on the trap (`RPlace.traps_stop`): a trap in the base stops the
base's code; at the trapping index the base's code runs (`RPlace.addr_exec`)
and then the index's code stops, or its word fails the bounds check and the
code reaches `refTrap`'s division by zero. -/
theorem Lanius.Open.PlaceAddrTraps.proof : Lanius.Open.PlaceAddrTraps := by
  intro sx bud places st st' hp c p t code ty r cprog prog depth env scratch homes agree hcode htraps undef hruns
    _ tout _
  exact RPlace.traps_stop homes agree tout p hcode htraps undef hruns
