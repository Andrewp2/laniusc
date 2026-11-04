module

public import Lanius.Faithful.GenB.SelfBModel5
public import Lanius.Faithful.SelfPre.NB
public import Lanius.Mini.Frontend

@[expose] public section

open Lanius.Mini
open Lanius.Faithful.SelfPre

/-- The program the front end builds has no number above `2 ^ 40` (`nb`, the
largest number anywhere in it: ids, field indices, array lengths, string
offsets): the premise `nb p ≤ M` that `PreCompileSourceV5` adds, at the
height bound `M ≥ 2 ^ 40` that `PreCompileWords` uses. Why it should hold: no
real program comes near; but ids and offsets come from counters that grow
with monomorphization's copies, so the intended route is a front-end check
(`lim_funcs` rejecting a function with a number past `depth_limit()`), as for
the lets' slots (`FrontEndStmtDepthV2`). -/
def Lanius.Open.FrontEndNumbersSmall : Prop :=
  ∀ (W : List (BitVec 32)) (p : Lanius.Mini.SrcProgram),
    Lanius.Mini.frontEndWords grammar W = some p → nb p ≤ 2 ^ 40
