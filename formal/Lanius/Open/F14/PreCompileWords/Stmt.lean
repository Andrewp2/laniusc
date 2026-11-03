import Lanius.Faithful.GenB.SelfBModel5
import Lanius.Faithful.SelfPre.HB

open Lanius.Mini
open Lanius.Faithful.Budget
open Lanius.Faithful.SelfBudget
open Lanius.Faithful.SelfPre

/-- `compile_words`'s precondition holds for the front end's output on input
words fewer than `2 ^ 31`, at a budget that with the front end's cost stays
within `2 ^ 61`: the compile half of the root preconditions. -/
def Lanius.Open.PreCompileWords : Prop :=
  ∀ (N : Nat) (W : List (BitVec 32)) (b : Nat), W.length < 2 ^ 31 →
    Cost_front_end_words N grammar W + b ≤ 2 ^ 61 →
    Pre_compile_words N (Lanius.Mini.frontEndWords grammar W) b
