import Lanius.Open.F14.PreCompileWords.Stmt
import Lanius.Open.F14.PostFrontEndWords.Stmt
import Lanius.Open.F14.FrontEndTypeSlots.Stmt
import Lanius.Open.F14.FrontEndStmtDepthV2.Stmt
import Lanius.Open.F14.PreCompileSourceV3.Stmt
import Lanius.Open.F14.PreBinaryWordsV3.Stmt

open Lanius.Mini
open Lanius.Faithful.Budget
open Lanius.Faithful.SelfBudget
open Lanius.Faithful.SelfPre

theorem Lanius.Open.PreCompileWords.hb_words4 (l : List (BitVec 32)) : hb l = l.length := by
  induction l with
  | nil => rfl
  | cons a l ih => simp only [hb_cons, hb_bitvec, ih, List.length_cons]; omega

/-- The front end's output is lower than its inputs plus its cost
(`PostFrontEndWords`). Its types have at most `2 ^ 22` slots
(`FrontEndTypeSlots`), and its functions' lets need at most `2 ^ 40` slots
(`FrontEndStmtDepthV2`, the front end's check). So `compile_source`'s precondition
holds at that height (`PreCompileSourceV3`), and `binary_words`'s holds at any
budget (`PreBinaryWordsV3`). -/
theorem Lanius.Open.PreCompileWords.red4 (hpf : Lanius.Open.PostFrontEndWords)
    (hts : Lanius.Open.FrontEndTypeSlots) (hsd : Lanius.Open.FrontEndStmtDepthV2)
    (hcs : Lanius.Open.PreCompileSourceV3) (hbw : Lanius.Open.PreBinaryWordsV3) :
    Lanius.Open.PreCompileWords := by
  intro N W b hW hle
  rcases N with _ | n
  · trivial
  have hg : hb grammar ≤ 2 ^ 40 := by decide +kernel
  have hpost := hpf (n + 1) grammar W (2 ^ 40) hg (by rw [Lanius.Open.PreCompileWords.hb_words4]; omega) (by omega)
  rw [Pre_compile_words.eq_def]
  dsimp only
  cases hp : Lanius.Mini.frontEndWords grammar W with
  | none => trivial
  | some p =>
    rw [hp, hb_some] at hpost
    refine ⟨hcs p n b _ (hts W p hp) (fun f hf => ?_) hpost (by omega), fun b1 _ _ => hbw p n b1⟩
    have := hsd W p hp f hf
    omega
