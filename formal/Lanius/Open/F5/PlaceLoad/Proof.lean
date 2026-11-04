module

public import Lanius.Open.F5.PlaceLoad.Stmt
public import Lanius.Open.F5.PlaceAddr.Proof
public import Lanius.Open.F5.RefLoad.Proof
public import Lanius.Mini.Refs.HomedLemmas

@[expose] public section

open Lanius.Mini

/-- `PlaceAddr`, then `RefLoad` at `r = t` (the address is below `2 ^ 62`,
`Homes.sub_lt`), joined by `Exec.seq`. -/
theorem Lanius.Open.PlaceLoad.proof : Lanius.Open.PlaceLoad := by
  intro sx bud places st hp c p t code ty cell path v cprog prog depth env scratch target homes agree hcode
    hres hruns hread tslots tout slots apart
  obtain ⟨x, mem, address, env₁, hcell, hsub, run, ht, same⟩ :=
    Lanius.Open.PlaceAddr.proof sx bud places st hp c p t code ty cell path v cprog prog depth env scratch
      homes agree hcode hres hruns hread tslots tout slots
  obtain ⟨i, hi⟩ := List.mem_iff_getElem?.mp mem
  have hr : (env₁ t).toNat = address := by rw [ht]; exact toNat_ofNat_small (homes.sub_lt mem hsub)
  obtain ⟨env', load, holds, kept⟩ :=
    Lanius.Open.RefLoad.proof sx bud places st hp i x path address ty v prog depth env₁ t target homes hi hsub
      (by rw [hcell]; exact hread) hr apart
  exact ⟨i, x, env', hi, hcell, .seq run load, holds, fun k ks kt kout => by
    rw [kept k kout]; exact same k ks kt⟩
