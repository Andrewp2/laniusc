module

public import Lanius.Open.F5.HoldsAtDropHomes.Stmt
public import Lanius.Mini.Refs.HomedLemmas

@[expose] public section

open Lanius.Mini

/-- `SrcType.HoldsAt.drop`, by induction as `HoldsAt.mono`. -/
theorem Lanius.Open.HoldsAtDropHomes.proof : Lanius.Open.HoldsAtDropHomes :=
  fun _ _ _ _ _ _ _ holds no => SrcType.HoldsAt.drop holds no
