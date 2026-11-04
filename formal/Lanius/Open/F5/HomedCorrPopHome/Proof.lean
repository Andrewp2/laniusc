module

public import Lanius.Open.F5.HomedCorrPopHome.Stmt
public import Lanius.Mini.Refs.HomedLemmas

@[expose] public section

open Lanius.Mini

/-- `HomedCorr.popHome`: the context from before the `let`, the values from
the block's end, dropping the home (`HoldsAt.drop`, `RefTo.drop`). -/
theorem Lanius.Open.HomedCorrPopHome.proof : Lanius.Open.HomedCorrPopHome :=
  fun _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ hc₀ hc fr apartCell locals cells views hframe noName shadow =>
    HomedCorr.popHome hc₀ hc fr apartCell locals cells views hframe noName shadow
