import Lanius.Open.F14.PreCompileWords.Stmt
import Lanius.Open.F14.PostFrontEndWords.Stmt
import Lanius.Open.F14.FrontEndTypeSlots.Stmt
import Lanius.Open.F14.FrontEndStmtDepthV2.Stmt
import Lanius.Open.F14.FrontEndParamSlots.Stmt
import Lanius.Open.F14.FrontEndSlotNest.Stmt
import Lanius.Open.F14.FrontEndNumbersSmall.Stmt
import Lanius.Open.F14.PreCompileSourceV5.Stmt
import Lanius.Open.F14.PreBinaryWordsV3.Stmt

open Lanius.Mini
open Lanius.Faithful.Budget
open Lanius.Faithful.SelfBudget
open Lanius.Faithful.SelfPre

theorem Lanius.Open.PreCompileWords.hb_words6 (l : List (BitVec 32)) : hb l = l.length := by
  induction l with
  | nil => rfl
  | cons a l ih => simp only [hb_cons, hb_bitvec, ih, List.length_cons]; omega

/-- red5 with `PreCompileSourceV5` in place of V4. V5's two new premises come
from the front end: its expressions' slot nesting (`FrontEndSlotNest`) and
its numbers, at most `2 ^ 40`, below the height bound `2 ^ 40 + cost` that
`PostFrontEndWords` gives (`FrontEndNumbersSmall`). -/
theorem Lanius.Open.PreCompileWords.red6 (hpf : Lanius.Open.PostFrontEndWords)
    (hts : Lanius.Open.FrontEndTypeSlots) (hsd : Lanius.Open.FrontEndStmtDepthV2)
    (hps : Lanius.Open.FrontEndParamSlots) (hsn : Lanius.Open.FrontEndSlotNest)
    (hnb : Lanius.Open.FrontEndNumbersSmall)
    (hcs : Lanius.Open.PreCompileSourceV5) (hbw : Lanius.Open.PreBinaryWordsV3) :
    Lanius.Open.PreCompileWords := by
  intro N W b hW hle
  rcases N with _ | n
  · trivial
  have hg : hb grammar ≤ 2 ^ 40 := by decide +kernel
  have hpost := hpf (n + 1) grammar W (2 ^ 40) hg (by rw [Lanius.Open.PreCompileWords.hb_words6]; omega) (by omega)
  rw [Pre_compile_words.eq_def]
  dsimp only
  cases hp : Lanius.Mini.frontEndWords grammar W with
  | none => trivial
  | some p =>
    rw [hp, hb_some] at hpost
    have hn := hnb W p hp
    refine ⟨hcs p n b _ (hts W p hp) (fun f hf => ?_) (fun f hf => hps W p hp f hf)
      (fun f hf => hsn W p hp f hf) hpost (by omega) (by omega), fun b1 _ _ => hbw p n b1⟩
    have := hsd W p hp f hf
    omega
