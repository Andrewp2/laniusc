module

public import Lanius.Open.F5.RefCodeWithin.Stmt
public import Lanius.Mini.Refs.MachineLemmas

@[expose] public section

open Lanius.Mini

/-- `loadSlots_within`, `storeSlots_within` and `RPlace.code_within`. -/
theorem Lanius.Open.RefCodeWithin.proof : Lanius.Open.RefCodeWithin :=
  ⟨fun ty _ _ _ _ _ lt fits => ty.loadSlots_within lt fits,
    fun ty _ _ _ _ _ lt fits => ty.storeSlots_within lt fits,
    fun _ _ p _ _ _ _ _ hcode tlt slots idx => RPlace.code_within tlt p hcode slots idx⟩
