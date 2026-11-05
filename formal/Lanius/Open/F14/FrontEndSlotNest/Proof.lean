module

public import Lanius.Open.F14.FrontEndSlotNest.Stmt
public import Lanius.Faithful.SelfPre.Limits

@[expose] public section

/-! # `FrontEndSlotNest`: the front end's nesting check (`SelfPre/Limits.lean`) -/

theorem Lanius.Open.FrontEndSlotNest.proof : Lanius.Open.FrontEndSlotNest :=
  fun _ _ h f mem => Nat.le_trans ((Lanius.Faithful.SelfPre.Limits.frontEndWords_nums h).1 f mem) (by decide)
