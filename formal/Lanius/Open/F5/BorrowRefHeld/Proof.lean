import Lanius.Open.F5.BorrowRefHeld.Stmt
import Lanius.Mini.Refs.HomedLemmas

open Lanius.Mini

/-- `RPlace.addr_exec`, and the address is below `2 ^ 62` (`Homes.sub_lt`), so
the word's value is it. -/
theorem Lanius.Open.BorrowRefHeld.proof : Lanius.Open.BorrowRefHeld := by
  intro sx bud places st hp c p t code ty cell path v cprog prog depth env scratch homes agree hcode hres hruns
    hread tout
  obtain ⟨x, mem, a, env', xcell, xsub, run, envT, same⟩ := RPlace.addr_exec homes agree tout p hcode hres hruns hread
  refine ⟨env', run, ⟨cell, path, rfl, x, mem, xcell, ?_⟩, same⟩
  rw [envT, toNat_ofNat_small (homes.sub_lt mem xsub)]
  exact xsub
