import Lanius.Open.F14.PreCompileWords.Stmt
import Lanius.Open.F14.PostFrontEndWords.Stmt
import Lanius.Open.F14.PreCompileSource.Stmt
import Lanius.Open.F14.PostCompileSource.Stmt
import Lanius.Open.F14.PreBinaryWords.Stmt

open Lanius.Mini
open Lanius.Faithful.Budget
open Lanius.Faithful.SelfBudget
open Lanius.Faithful.SelfPre

theorem Lanius.Open.PreCompileWords.hb_words (l : List (BitVec 32)) : hb l = l.length := by
  induction l with
  | nil => rfl
  | cons a l ih => simp only [hb_cons, hb_bitvec, ih, List.length_cons]; omega

/-- The front end's output is lower than its inputs plus its cost
(`PostFrontEndWords`), then `compile_source`'s and `binary_words`'s
preconditions at that height (the grammar's height is a constant). -/
theorem Lanius.Open.PreCompileWords.red1 (hpf : Lanius.Open.PostFrontEndWords)
    (hcs : Lanius.Open.PreCompileSource) (hpc : Lanius.Open.PostCompileSource)
    (hbw : Lanius.Open.PreBinaryWords) : Lanius.Open.PreCompileWords := by
  intro N W b hW hle
  rcases N with _ | n
  · trivial
  have hg : hb grammar ≤ 2 ^ 40 := by decide +kernel
  have hpost := hpf (n + 1) grammar W (2 ^ 40) hg (by rw [Lanius.Open.PreCompileWords.hb_words]; omega) (by omega)
  rw [Pre_compile_words.eq_def]
  dsimp only
  cases hp : Lanius.Mini.frontEndWords grammar W with
  | none => trivial
  | some p =>
    rw [hp, hb_some] at hpost
    refine ⟨hcs W p n b _ hW hp hpost (by omega), fun b1 hlt hb1 => ?_⟩
    have hpost2 := hpc n p _ hpost (by omega)
    exact hbw W p n b1 _ hW hp hpost2 (by omega)
