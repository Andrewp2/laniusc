import Lanius.Open.F14.FrontEndTypeSlots.Stmt
import Lanius.Faithful.SelfPre.Limits

/-! # `FrontEndTypeSlots`: the front end's slot check (`SelfPre/Limits.lean`) -/

theorem Lanius.Open.FrontEndTypeSlots.proof : Lanius.Open.FrontEndTypeSlots :=
  fun _ _ h => (Lanius.Faithful.SelfPre.Limits.frontEndWords_limits h).1
