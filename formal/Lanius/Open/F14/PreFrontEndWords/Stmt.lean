module

public import Lanius.Faithful.GenB.SelfBModel5
public import Lanius.Faithful.SelfPre.HB

@[expose] public section

open Lanius.Mini
open Lanius.Faithful.Budget
open Lanius.Faithful.SelfBudget
open Lanius.Faithful.SelfPre

/-- `front_end_words`'s precondition (no `plus` or `times` passes `2 ^ 64`) holds
for the self program's grammar, input words fewer than `2 ^ 31` and any budget
up to `2 ^ 61`: the front-end half of the root preconditions. -/
def Lanius.Open.PreFrontEndWords : Prop :=
  ∀ (N : Nat) (W : List (BitVec 32)) (b : Nat), W.length < 2 ^ 31 → b ≤ 2 ^ 61 →
    Pre_front_end_words N grammar W b
