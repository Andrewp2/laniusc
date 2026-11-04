module

public import Lanius.Open.F5.HomesPopHome.Stmt
public import Lanius.Mini.Refs.HomedLemmas

@[expose] public section

open Lanius.Mini

/-- `Homes.popHome`: reindex the older homes; the reuse is the home's own block. -/
theorem Lanius.Open.HomesPopHome.proof : Lanius.Open.HomesPopHome :=
  fun _ _ _ _ _ _ _ homes same views => Homes.popHome homes same views
