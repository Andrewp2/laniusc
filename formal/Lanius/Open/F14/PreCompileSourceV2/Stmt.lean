import Lanius.Faithful.GenB.SelfBModel5
import Lanius.Faithful.SelfPre.HB

open Lanius.Mini
open Lanius.Faithful.Budget
open Lanius.Faithful.SelfBudget
open Lanius.Faithful.SelfPre

/-- `compile_source`'s precondition, at any budget, for a program the front end
built from fewer than `2 ^ 31` words, which is at most `2 ^ 48` high
(`FrontEndOutputSmall`). Replaces `PreCompileSource`: the compile side's
numbers (slots, temporaries, frame sizes, type sizes, `codeSize` and
`linkedSize`, a call's `14 * args.length + 19 + 14 * count`) are sums and
products of values that depend on the program, not on the budget, and the
M-form bound `M + b ≤ 2 ^ 62` (values at most the potential plus the cost so
far) cannot keep a sum or product of them below `2 ^ 64`. The input words and
the front end's output stay premises, so every fact about that output (its
checks bound the type weights by `2 ^ 22`) is available. -/
def Lanius.Open.PreCompileSourceV2 : Prop :=
  ∀ (W : List (BitVec 32)) (p : Lanius.Mini.SrcProgram) (n b : Nat), W.length < 2 ^ 31 →
    Lanius.Mini.frontEndWords grammar W = some p → hb p ≤ 2 ^ 48 →
    Pre_compile_source n p b
