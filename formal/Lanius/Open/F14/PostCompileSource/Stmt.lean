module

public import Lanius.Faithful.GenB.SelfBModel5
public import Lanius.Faithful.SelfPre.HB

@[expose] public section

open Lanius.Mini
open Lanius.Faithful.Budget
open Lanius.Faithful.SelfBudget
open Lanius.Faithful.SelfPre

/-- The compiled binary is at most as high as the program plus the compile's
cost: the height bound `binary_words`'s precondition starts from. The M-form
post lemma `pre_certs.py` generates. -/
def Lanius.Open.PostCompileSource : Prop :=
  ∀ (n : Nat) (p : Lanius.Mini.SrcProgram) (M : Nat), hb p ≤ M → Cost_compile_source n p < 2 ^ 64 →
    hb (Lanius.Mini.compileSource p) ≤ M + Cost_compile_source n p
