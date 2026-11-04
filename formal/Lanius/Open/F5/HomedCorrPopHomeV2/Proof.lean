import Lanius.Open.F5.HomedCorrPopHomeV2.Stmt
import Lanius.Mini.Refs.HomedLemmas

open Lanius.Mini

/-- `HomedCorr.popHome`: the context from before the `let`, the values from
the block's end, dropping the home (`HoldsAt.drop`, `RefTo.drop`). -/
theorem Lanius.Open.HomedCorrPopHomeV2.proof : Lanius.Open.HomedCorrPopHomeV2 :=
  fun _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ hc₀ hc fr apartCell locals cells views hframe noName shadow =>
    HomedCorr.popHome hc₀ hc fr apartCell locals cells views hframe noName shadow
