module

public import Lanius.Open.F14.FrontEndNumbersSmall.Stmt
public import Lanius.Faithful.SelfPre.Limits

@[expose] public section

/-! # `FrontEndNumbersSmall`: the front end's number check (`SelfPre/Limits.lean`) -/

theorem Lanius.Open.FrontEndNumbersSmall.proof : Lanius.Open.FrontEndNumbersSmall :=
  fun _ _ h => (Lanius.Faithful.SelfPre.Limits.frontEndWords_nums h).2
