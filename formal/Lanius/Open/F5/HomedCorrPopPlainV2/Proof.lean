module

public import Lanius.Open.F5.HomedCorrPopPlainV2.Stmt
public import Lanius.Mini.Refs.HomedLemmas

@[expose] public section

open Lanius.Mini

/-- `HomedCorr.popPlain`: the context from before the `let`, the values from
the block's end. -/
theorem Lanius.Open.HomedCorrPopPlainV2.proof : Lanius.Open.HomedCorrPopPlainV2 :=
  fun _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ hc₀ hc fr ctx locals cells views hframe shadow =>
    HomedCorr.popPlain hc₀ hc fr ctx locals cells views hframe shadow
