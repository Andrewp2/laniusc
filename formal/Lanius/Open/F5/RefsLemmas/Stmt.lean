import Lanius.Open.F5.RefLoad.Stmt
import Lanius.Open.F5.RefStore.Stmt
import Lanius.Open.F5.PlaceAddr.Stmt
import Lanius.Open.F5.PlaceAddrTraps.Stmt
import Lanius.Open.F5.HomesLend.Stmt
import Lanius.Open.F5.FrameCorrHomes.Stmt
import Lanius.Open.F5.CorePlace.Stmt
import Lanius.Open.F5.CoreRead.Stmt
import Lanius.Open.F5.CoreAssign.Stmt
import Lanius.Open.F5.CoreAssignOp.Stmt
import Lanius.Open.F5.CoreBorrow.Stmt
import Lanius.Open.F5.HomesPush.Stmt
import Lanius.Open.F5.HomesFrame.Stmt
import Lanius.Open.F5.HomesLeave.Stmt
import Lanius.Open.F5.HomesCongr.Stmt

/-- **F5's construct lemmas.** The conjunction of the lowering facts for each
reference construct, in the memory model of SEMANTIC_DECISIONS "References:
the memory model" (`Mini/Refs/Model.lean`): a place's address and its
out-of-range trap (`PlaceAddr`, `PlaceAddrTraps`), a borrow (`CoreBorrow`),
a read and a write through a reference (`RefLoad`, `CoreRead`, `RefStore`,
`CoreAssign`, `CoreAssignOp`, `CorePlace`), lending a home array
(`HomesLend`), moving `FrameCorr` onto homes (`FrameCorrHomes`), a home's
start (`HomesPush`), a call's frame and return (`HomesFrame`,
`HomesLeave`), and every other step (`HomesCongr`).

This is not F5's top theorem. That one, `compileSource` correct for programs
with references, is stated in stage 2, once stage 1 gives Source its
reference type, and needs besides these: a call passing a reference (the
callee's `RefsAgree` at entry, from the caller's borrow), `Corr` for homed
locals (their slots are not their values), `Keeps` letting a callee change
the caller's cells through references, and right-hand sides with effects
(SEMANTIC_DECISIONS, "Stage 2's root"). -/
def Lanius.Open.RefsLemmas : Prop :=
  Lanius.Open.RefLoad ∧
    Lanius.Open.RefStore ∧
    Lanius.Open.PlaceAddr ∧
    Lanius.Open.PlaceAddrTraps ∧
    Lanius.Open.HomesLend ∧
    Lanius.Open.FrameCorrHomes ∧
    Lanius.Open.CorePlace ∧
    Lanius.Open.CoreRead ∧
    Lanius.Open.CoreAssign ∧
    Lanius.Open.CoreAssignOp ∧
    Lanius.Open.CoreBorrow ∧
    Lanius.Open.HomesPush ∧
    Lanius.Open.HomesFrame ∧
    Lanius.Open.HomesLeave ∧
    Lanius.Open.HomesCongr
