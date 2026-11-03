import Lanius.Faithful.GenB.SelfBModel5
import Lanius.Faithful.SelfPre.HB

open Lanius.Mini
open Lanius.Faithful.Budget
open Lanius.Faithful.SelfBudget
open Lanius.Faithful.SelfPre

/-- The front end's output is at most as high as its inputs plus its cost
(`hb`, `Cost_front_end_words` not truncated): the height bound `compile_words`'s
precondition starts from. The M-form post lemma `pre_certs.py` generates. -/
def Lanius.Open.PostFrontEndWords : Prop :=
  ∀ (n : Nat) (g : List Lanius.Mini.Rule) (W : List (BitVec 32)) (M : Nat), hb g ≤ M → hb W ≤ M →
    Cost_front_end_words n g W < 2 ^ 64 →
    hb (Lanius.Mini.frontEndWords g W) ≤ M + Cost_front_end_words n g W
