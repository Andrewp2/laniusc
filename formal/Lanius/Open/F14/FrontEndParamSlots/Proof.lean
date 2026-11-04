module

public import Lanius.Open.F14.FrontEndParamSlots.Stmt
public import Lanius.Faithful.SelfPre.Limits

@[expose] public section

/-! # `FrontEndParamSlots`: the front end's parameter check (`SelfPre/Limits.lean`) -/

theorem Lanius.Open.FrontEndParamSlots.proof : Lanius.Open.FrontEndParamSlots :=
  fun _ _ h f mem => ((Lanius.Faithful.SelfPre.Limits.frontEndWords_limits h).2 f mem).2
