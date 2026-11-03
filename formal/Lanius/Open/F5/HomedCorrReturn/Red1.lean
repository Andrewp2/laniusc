import Lanius.Open.F5.HomedCorrReturn.Stmt
import Lanius.Open.F5.HomedCorrKeeps.Stmt
import Lanius.Open.F5.HomesLeave.Stmt
import Lanius.Open.F5.HoldsAtDropHomes.Stmt

open Lanius.Mini

/-- The conjunction of the caller's three facts after a return. -/
theorem Lanius.Open.HomedCorrReturn.red1 (hk : Lanius.Open.HomedCorrKeeps) (hl : Lanius.Open.HomesLeave)
    (hd : Lanius.Open.HoldsAtDropHomes) : Lanius.Open.HomedCorrReturn :=
  fun sx bud bud' own places scope frame c st st' hp f env envR ty v slot hc fresh keeps locals homes above room
      ceiling bounded hold no =>
    ⟨hk sx places scope frame c st st' env hc fresh keeps locals,
      hl sx bud bud' own places st' hp f homes above room ceiling bounded,
      hd sx own places ty v envR slot hold no⟩
