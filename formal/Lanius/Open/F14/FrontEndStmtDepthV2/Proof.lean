import Lanius.Open.F14.FrontEndStmtDepthV2.Stmt
import Lanius.Faithful.SelfPre.Limits

/-! # `FrontEndStmtDepthV2`: the front end's depth check (`SelfPre/Limits.lean`) -/

theorem Lanius.Open.FrontEndStmtDepthV2.proof : Lanius.Open.FrontEndStmtDepthV2 :=
  fun _ _ h => (Lanius.Faithful.SelfPre.Limits.frontEndWords_limits h).2
