import Lanius.Faithful.GenB.SelfBModel5
import Lanius.Faithful.SelfPre.HB

open Lanius.Mini
open Lanius.Faithful.Budget
open Lanius.Faithful.SelfBudget
open Lanius.Faithful.SelfPre

/-- `build_files`'s precondition at height `M`: trees of height at most `M`
with `M` and the budget within `2 ^ 62`. The generated lemma
`SelfPre.pre_build_files` (GenP/SelfP07) once every lemma it rests on is
proved. -/
def Lanius.Open.PreBuildFiles : Prop :=
  ∀ (n : Nat) (x0 : Nat) (x1 : List Lanius.Mini.CTree) (b : Nat), ∀ M : Nat, hb x1 ≤ M → M + b ≤ 4611686018427387904 →
    Pre_build_files n x0 x1 b
