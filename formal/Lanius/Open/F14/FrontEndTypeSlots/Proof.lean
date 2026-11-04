module

public import Lanius.Open.F14.FrontEndTypeSlots.Stmt
public import Lanius.Faithful.SelfPre.Limits

@[expose] public section

/-! # `FrontEndTypeSlots`: the front end's slot check (`SelfPre/Limits.lean`) -/

theorem Lanius.Open.FrontEndTypeSlots.proof : Lanius.Open.FrontEndTypeSlots :=
  fun _ _ h => (Lanius.Faithful.SelfPre.Limits.frontEndWords_limits h).1
