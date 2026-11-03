import Lanius.Mini.Refs.Homed

open Lanius.Mini
open Lanius.Core (Value ValueProjection)
open Lanius.Semantics (State)

/-- **Homed locals at a callee's entry.** Before any local of the activation
has a home (`c.homes = []`), `Corr` (the parameters' slots hold their values,
apart from the homes' cells) and the context's agreement (`RefsAgree`, from
`CallRefsAgree`) give `HomedCorr`. -/
def Lanius.Open.HomedCorrOfCorr : Prop :=
  ∀ (sx : Statics) (places : List Addressed) (scope : List Binding) (frame : Nat → Nat) (c : RCtx)
    (st : State) (env : Env),
    Corr sx places scope frame st env → RefsAgree c places st env → c.homes = [] →
    HomedCorr sx places scope frame c st env
