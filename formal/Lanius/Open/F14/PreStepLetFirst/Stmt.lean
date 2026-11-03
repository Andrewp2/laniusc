import Lanius.Faithful.GenB.SelfBModel5
import Lanius.Faithful.SelfPre.HB

open Lanius.Mini
open Lanius.Faithful.Budget
open Lanius.Faithful.SelfBudget
open Lanius.Faithful.SelfPre

/-- The step of `let_first`'s precondition lemma in the `block_of` group: from
the group's M-form lemmas at fuel `n`, `let_first`'s at `n + 1`. Exactly the
statement of the generated `SelfPre.pre_step_let_first` (GenP/SelfP07), whose
`pre_auto` proof runs out of heartbeats (1,000,000) after about 70 s of steady
work over `Pre_let_first`'s many branches. The only lemma `build_files`'s
precondition still lacks. -/
def Lanius.Open.PreStepLetFirst : Prop :=
  ∀ (n : Nat), ((∀ (x0 : Nat) (x1 : Lanius.Mini.FrontEnv) (x2 : List Lanius.Mini.Local) (x3 : Lanius.Mini.CTree) (b : Nat), ∀ M : Nat, hb x1 ≤ M → hb x2 ≤ M → hb x3 ≤ M → M + b ≤ 4611686018427387904 → Pre_block_of n x0 x1 x2 x3 b) ∧
    (∀ (x0 : Nat) (x1 : Lanius.Mini.FrontEnv) (x2 : List Lanius.Mini.Local) (x3 : List Lanius.Mini.CTree) (b : Nat), ∀ M : Nat, hb x1 ≤ M → hb x2 ≤ M → hb x3 ≤ M → M + b ≤ 4611686018427387904 → Pre_stmts_of n x0 x1 x2 x3 b) ∧
    (∀ (x0 : Nat) (x1 : Lanius.Mini.FrontEnv) (x2 : List Lanius.Mini.Local) (x3 : Lanius.Mini.CTree) (x4 : List Lanius.Mini.CTree) (b : Nat), ∀ M : Nat, hb x1 ≤ M → hb x2 ≤ M → hb x3 ≤ M → hb x4 ≤ M → M + b ≤ 4611686018427387904 → Pre_stmt_first n x0 x1 x2 x3 x4 b) ∧
    (∀ (x0 : Nat) (x1 : Lanius.Mini.FrontEnv) (x2 : List Lanius.Mini.Local) (x3 : Lanius.Mini.CTree) (x4 : List Lanius.Mini.CTree) (b : Nat), ∀ M : Nat, hb x1 ≤ M → hb x2 ≤ M → hb x3 ≤ M → hb x4 ≤ M → M + b ≤ 4611686018427387904 → Pre_let_first n x0 x1 x2 x3 x4 b) ∧
    (∀ (x0 : Nat) (x1 : Lanius.Mini.FrontEnv) (x2 : List Lanius.Mini.Local) (x3 : Lanius.Mini.CTree) (b : Nat), ∀ M : Nat, hb x1 ≤ M → hb x2 ≤ M → hb x3 ≤ M → M + b ≤ 4611686018427387904 → Pre_stmt_of n x0 x1 x2 x3 b) ∧
    (∀ (x0 : Nat) (x1 : Lanius.Mini.FrontEnv) (x2 : List Lanius.Mini.Local) (x3 : Lanius.Mini.Local) (x4 : Lanius.Mini.CTree) (x5 : Option Lanius.Mini.MStmt) (b : Nat), ∀ M : Nat, hb x1 ≤ M → hb x2 ≤ M → hb x3 ≤ M → hb x4 ≤ M → hb x5 ≤ M → M + b ≤ 4611686018427387904 → Pre_lit_let_of n x0 x1 x2 x3 x4 x5 b) ∧
    (∀ (x0 : Nat) (x1 : Lanius.Mini.FrontEnv) (x2 : List Lanius.Mini.Local) (x3 : Lanius.Mini.Local) (x4 : Lanius.Mini.CTree) (x5 : Option Lanius.Mini.MStmt) (b : Nat), ∀ M : Nat, hb x1 ≤ M → hb x2 ≤ M → hb x3 ≤ M → hb x4 ≤ M → hb x5 ≤ M → M + b ≤ 4611686018427387904 → Pre_let_match_of n x0 x1 x2 x3 x4 x5 b) ∧
    (∀ (x0 : Nat) (x1 : Lanius.Mini.FrontEnv) (x2 : List Lanius.Mini.Local) (x3 : Lanius.Mini.CTree) (x4 : Lanius.Mini.LitForm) (b : Nat), ∀ M : Nat, hb x1 ≤ M → hb x2 ≤ M → hb x3 ≤ M → hb x4 ≤ M → M + b ≤ 4611686018427387904 → Pre_lit_match_of n x0 x1 x2 x3 x4 b) ∧
    (∀ (x0 : Nat) (x1 : Lanius.Mini.FrontEnv) (x2 : List Lanius.Mini.Local) (x3 : Lanius.Mini.CTree) (b : Nat), ∀ M : Nat, hb x1 ≤ M → hb x2 ≤ M → hb x3 ≤ M → M + b ≤ 4611686018427387904 → Pre_nested_of n x0 x1 x2 x3 b) ∧
    (∀ (x0 : Nat) (x1 : Lanius.Mini.FrontEnv) (x2 : List Lanius.Mini.Local) (x3 : Lanius.Mini.CTree) (b : Nat), ∀ M : Nat, hb x1 ≤ M → hb x2 ≤ M → hb x3 ≤ M → M + b ≤ 4611686018427387904 → Pre_match_stmt_of n x0 x1 x2 x3 b) ∧
    (∀ (x0 : Nat) (x1 : Lanius.Mini.FrontEnv) (x2 : List Lanius.Mini.Local) (x3 : Lanius.Mini.MatchStmt) (x4 : Lanius.Mini.Local) (x5 : Lanius.Mini.MStmt) (x6 : Nat) (x7 : List Lanius.Mini.VariantTy) (x8 : List Lanius.Mini.CTree) (b : Nat), ∀ M : Nat, hb x1 ≤ M → hb x2 ≤ M → hb x3 ≤ M → hb x4 ≤ M → hb x5 ≤ M → hb x7 ≤ M → hb x8 ≤ M → M + b ≤ 4611686018427387904 → x6 + hb x7 + b ≤ 4611686018427387904 → Pre_let_arms_of n x0 x1 x2 x3 x4 x5 x6 x7 x8 b) ∧
    (∀ (x0 : Nat) (x1 : Lanius.Mini.FrontEnv) (x2 : List Lanius.Mini.Local) (x3 : Lanius.Mini.LitMatch) (x4 : Lanius.Mini.LitForm) (x5 : Bool) (x6 : Bool) (x7 : List Lanius.Mini.CTree) (b : Nat), ∀ M : Nat, hb x1 ≤ M → hb x2 ≤ M → hb x3 ≤ M → hb x4 ≤ M → hb x7 ≤ M → M + b ≤ 4611686018427387904 → Pre_lit_arms_of n x0 x1 x2 x3 x4 x5 x6 x7 b) ∧
    (∀ (x0 : Nat) (x1 : Lanius.Mini.FrontEnv) (x2 : List Lanius.Mini.Local) (x3 : Lanius.Mini.CTree) (b : Nat), ∀ M : Nat, hb x1 ≤ M → hb x2 ≤ M → hb x3 ≤ M → M + b ≤ 4611686018427387904 → Pre_for_of n x0 x1 x2 x3 b) ∧
    (∀ (x0 : Nat) (x1 : Lanius.Mini.FrontEnv) (x2 : List Lanius.Mini.Local) (x3 : Lanius.Mini.MatchStmt) (x4 : Nat) (x5 : List Lanius.Mini.VariantTy) (x6 : List Lanius.Mini.CTree) (b : Nat), ∀ M : Nat, hb x1 ≤ M → hb x2 ≤ M → hb x3 ≤ M → hb x5 ≤ M → hb x6 ≤ M → M + b ≤ 4611686018427387904 → x4 + hb x5 + b ≤ 4611686018427387904 → Pre_match_arms_of n x0 x1 x2 x3 x4 x5 x6 b) ∧
    (∀ (x0 : Nat) (x1 : Lanius.Mini.FrontEnv) (x2 : List Lanius.Mini.Local) (x3 : Lanius.Mini.MatchStmt) (x4 : Lanius.Mini.Local) (x5 : Lanius.Mini.MStmt) (x6 : Nat) (x7 : Lanius.Mini.VariantTy) (x8 : Lanius.Mini.CTree) (x9 : Option Lanius.Mini.MStmt) (b : Nat), ∀ M : Nat, hb x1 ≤ M → hb x2 ≤ M → hb x3 ≤ M → hb x4 ≤ M → hb x5 ≤ M → hb x7 ≤ M → hb x8 ≤ M → hb x9 ≤ M → M + b ≤ 4611686018427387904 → Pre_let_arm_of n x0 x1 x2 x3 x4 x5 x6 x7 x8 x9 b) ∧
    (∀ (x0 : Nat) (x1 : Lanius.Mini.FrontEnv) (x2 : List Lanius.Mini.Local) (x3 : Lanius.Mini.LitMatch) (x4 : Lanius.Mini.LitForm) (x5 : Bool) (x6 : Bool) (x7 : Lanius.Mini.CTree) (x8 : List Lanius.Mini.CTree) (b : Nat), ∀ M : Nat, hb x1 ≤ M → hb x2 ≤ M → hb x3 ≤ M → hb x4 ≤ M → hb x7 ≤ M → hb x8 ≤ M → M + b ≤ 4611686018427387904 → Pre_lit_arm_of n x0 x1 x2 x3 x4 x5 x6 x7 x8 b) ∧
    (∀ (x0 : Nat) (x1 : Lanius.Mini.FrontEnv) (x2 : List Lanius.Mini.Local) (x3 : Lanius.Mini.MatchStmt) (x4 : Nat) (x5 : Lanius.Mini.VariantTy) (x6 : Lanius.Mini.CTree) (x7 : Option Lanius.Mini.MStmt) (b : Nat), ∀ M : Nat, hb x1 ≤ M → hb x2 ≤ M → hb x3 ≤ M → hb x5 ≤ M → hb x6 ≤ M → hb x7 ≤ M → M + b ≤ 4611686018427387904 → Pre_match_arm_of n x0 x1 x2 x3 x4 x5 x6 x7 b) ∧
    (∀ (x0 : Nat) (x1 : Lanius.Mini.FrontEnv) (x2 : List Lanius.Mini.Local) (x3 : Lanius.Mini.Local) (x4 : Lanius.Mini.MStmt) (x5 : Lanius.Mini.CTree) (b : Nat), ∀ M : Nat, hb x1 ≤ M → hb x2 ≤ M → hb x3 ≤ M → hb x4 ≤ M → hb x5 ≤ M → M + b ≤ 4611686018427387904 → Pre_let_body_of n x0 x1 x2 x3 x4 x5 b) ∧
    (∀ (x0 : Nat) (x1 : Lanius.Mini.FrontEnv) (x2 : List Lanius.Mini.Local) (x3 : Lanius.Mini.LitForm) (x4 : Lanius.Mini.CTree) (b : Nat), ∀ M : Nat, hb x1 ≤ M → hb x2 ≤ M → hb x3 ≤ M → hb x4 ≤ M → M + b ≤ 4611686018427387904 → Pre_lit_body_of n x0 x1 x2 x3 x4 b) ∧
    (∀ (x0 : Nat) (x1 : Lanius.Mini.FrontEnv) (x2 : List Lanius.Mini.Local) (x3 : Lanius.Mini.CTree) (b : Nat), ∀ M : Nat, hb x1 ≤ M → hb x2 ≤ M → hb x3 ≤ M → M + b ≤ 4611686018427387904 → Pre_arm_body_of n x0 x1 x2 x3 b) ∧
    (∀ (x0 : Nat) (x1 : Lanius.Mini.FrontEnv) (x2 : List Lanius.Mini.Local) (x3 : Lanius.Mini.Local) (x4 : Lanius.Mini.MStmt) (x5 : Lanius.Mini.CTree) (b : Nat), ∀ M : Nat, hb x1 ≤ M → hb x2 ≤ M → hb x3 ≤ M → hb x4 ≤ M → hb x5 ≤ M → M + b ≤ 4611686018427387904 → Pre_inner_let_of n x0 x1 x2 x3 x4 x5 b) ∧
    (∀ (x0 : Nat) (x1 : Lanius.Mini.FrontEnv) (x2 : List Lanius.Mini.Local) (x3 : Lanius.Mini.CTree) (b : Nat), ∀ M : Nat, hb x1 ≤ M → hb x2 ≤ M → hb x3 ≤ M → M + b ≤ 4611686018427387904 → Pre_inner_match_of n x0 x1 x2 x3 b)) →
    ∀ (x0 : Nat) (x1 : Lanius.Mini.FrontEnv) (x2 : List Lanius.Mini.Local) (x3 : Lanius.Mini.CTree) (x4 : List Lanius.Mini.CTree) (b : Nat), ∀ M : Nat, hb x1 ≤ M → hb x2 ≤ M → hb x3 ≤ M → hb x4 ≤ M → M + b ≤ 4611686018427387904 → Pre_let_first (n + 1) x0 x1 x2 x3 x4 b
