import Lanius.Open.F5.HomedCorrPopPlainV2.Stmt
import Lanius.Mini.Refs.HomedLemmas

open Lanius.Mini

/-- `HomedCorr.popPlain`: the context from before the `let`, the values from
the block's end. -/
theorem Lanius.Open.HomedCorrPopPlainV2.proof : Lanius.Open.HomedCorrPopPlainV2 :=
  fun _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ hc₀ hc fr ctx locals cells views hframe shadow =>
    HomedCorr.popPlain hc₀ hc fr ctx locals cells views hframe shadow
