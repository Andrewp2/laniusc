import Lanius.Faithful.GenB.SelfBModel5
import Lanius.Mini.Compiler

open Lanius.Mini
open Lanius.Faithful.Budget
open Lanius.Faithful.SelfBudget

/-- Every function the front end builds has parameters that need at most
`2 ^ 40` slots together (`paramsSize`, lowering's `params_size`, which adds
the parameters' type sizes with no check between them). Why it holds: the
front end rejects a program whose function's parameters need more than
`depth_limit()` (`2 ^ 40`) slots (`untyped_rejected`'s `lim_funcs`, with
`lim_param_slots`; SEMANTIC_DECISIONS "The front end's implementation
limits"). A struct's fields together need its slot count, which
`FrontEndTypeSlots` bounds. Needed by `PreCompileSourceV3`'s successor:
`params_size` stays far below `2 ^ 64` whatever the budget. -/
def Lanius.Open.FrontEndParamSlots : Prop :=
  ∀ (W : List (BitVec 32)) (p : Lanius.Mini.SrcProgram),
    Lanius.Mini.frontEndWords grammar W = some p →
    ∀ f ∈ p.funcs, Lanius.Mini.paramsSize f.params ≤ 2 ^ 40
