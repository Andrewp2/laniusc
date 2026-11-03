import Lanius.Faithful.GenB.SelfBModel5
import Lanius.Faithful.SelfPre.HB

open Lanius.Mini
open Lanius.Faithful.Budget
open Lanius.Faithful.SelfBudget
open Lanius.Faithful.SelfPre

/-- `compile_source`'s precondition at height `M` for a program the front end
built from fewer than `2 ^ 31` words (its checks bound the type weights by
`2 ^ 22`, SEMANTIC_DECISIONS "Type weights", which an arbitrary program need
not satisfy), of height at most `M`, with `M` and the budget within `2 ^ 62`.
To be split into the generated lemmas (`pre_certs.py`, root `compile_source`)
that fail, as new statements. -/
def Lanius.Open.PreCompileSource : Prop :=
  ∀ (W : List (BitVec 32)) (p : Lanius.Mini.SrcProgram) (n b : Nat), ∀ M : Nat, W.length < 2 ^ 31 →
    Lanius.Mini.frontEndWords grammar W = some p → hb p ≤ M → M + b ≤ 4611686018427387904 →
    Pre_compile_source n p b
