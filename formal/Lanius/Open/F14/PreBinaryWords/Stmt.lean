import Lanius.Faithful.GenB.SelfBModel5
import Lanius.Faithful.SelfPre.HB

open Lanius.Mini
open Lanius.Faithful.Budget
open Lanius.Faithful.SelfBudget
open Lanius.Faithful.SelfPre

/-- `binary_words`'s precondition at height `M` for the compile of a program the
front end built from fewer than `2 ^ 31` words, the binary of height at most
`M`, with `M` and the budget within `2 ^ 62`. The M-form pre lemma
`pre_certs.py` generates with root `binary_words`. -/
def Lanius.Open.PreBinaryWords : Prop :=
  ∀ (W : List (BitVec 32)) (p : Lanius.Mini.SrcProgram) (n b : Nat), ∀ M : Nat, W.length < 2 ^ 31 →
    Lanius.Mini.frontEndWords grammar W = some p → hb (Lanius.Mini.compileSource p) ≤ M → M + b ≤ 4611686018427387904 →
    Pre_binary_words n (Lanius.Mini.compileSource p) b
