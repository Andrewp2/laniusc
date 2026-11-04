module

public import Lanius.Open.F5.PlaceLoadHeld.Stmt
public import Lanius.Open.F5.PlaceLoad.Proof
public import Lanius.Mini.Borrowed

@[expose] public section

open Lanius.Mini

/-- `PlaceLoad`, whose value is held against the places older than its home,
which are among the places (`HoldsAt.mono`). -/
theorem Lanius.Open.PlaceLoadHeld.proof : Lanius.Open.PlaceLoadHeld := by
  intro sx bud places st hp c p t code ty cell path v cprog prog depth env scratch target homes agree hcode
    hres hruns hread tslots tout slots apart
  obtain ⟨i, x, env', hi, hcell, run, holds, kept⟩ :=
    Lanius.Open.PlaceLoad.proof sx bud places st hp c p t code ty cell path v cprog prog depth env scratch
      target homes agree hcode hres hruns hread tslots tout slots apart
  exact ⟨x, env', List.mem_of_getElem? hi, hcell, run,
    holds.mono fun y mem => List.mem_of_mem_drop mem, kept⟩
