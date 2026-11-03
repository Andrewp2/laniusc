import Lanius.Faithful.GenB.SelfBModel5
import Lanius.Faithful.SelfPre.HB

open Lanius.Mini
open Lanius.Faithful.Budget
open Lanius.Faithful.SelfBudget
open Lanius.Faithful.SelfPre

/-- The program the front end builds from fewer than `2 ^ 31` words is at most
`2 ^ 48` high, whatever the front end's cost. It should hold: the files read
are lower than `2 ^ 40` (`ReadFilesHeight`), a validated tree is at most
`5 * hb + 5` high, lowering a tree to the source program does not raise its
height, and monomorphization keeps the types' nesting within their weights,
which the front end's checks bound by `2 ^ 22`. Needed by the compile side's
preconditions (`PreCompileSourceV2`, `PreBinaryWordsV2`), whose values depend
on the program and not on the budget. -/
def Lanius.Open.FrontEndOutputSmall : Prop :=
  ∀ (W : List (BitVec 32)) (p : Lanius.Mini.SrcProgram), W.length < 2 ^ 31 →
    Lanius.Mini.frontEndWords grammar W = some p → hb p ≤ 2 ^ 48
