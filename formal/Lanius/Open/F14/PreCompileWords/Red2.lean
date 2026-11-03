import Lanius.Open.F14.PreCompileWords.Stmt
import Lanius.Open.F14.FrontEndOutputSmall.Stmt
import Lanius.Open.F14.PreCompileSourceV2.Stmt
import Lanius.Open.F14.PreBinaryWordsV2.Stmt

open Lanius.Mini
open Lanius.Faithful.Budget
open Lanius.Faithful.SelfBudget
open Lanius.Faithful.SelfPre

/-- The front end's output is small whatever its cost (`FrontEndOutputSmall`),
then `compile_source`'s and `binary_words`'s preconditions at any budget
(`PreCompileSourceV2`, `PreBinaryWordsV2`): no height of the output in terms
of the front end's cost, and none of the binary. -/
theorem Lanius.Open.PreCompileWords.red2 (hs : Lanius.Open.FrontEndOutputSmall)
    (hcs : Lanius.Open.PreCompileSourceV2) (hbw : Lanius.Open.PreBinaryWordsV2) :
    Lanius.Open.PreCompileWords := by
  intro N W b hW _
  rcases N with _ | n
  · trivial
  rw [Pre_compile_words.eq_def]
  dsimp only
  cases hp : Lanius.Mini.frontEndWords grammar W with
  | none => trivial
  | some p =>
    have hsm := hs W p hW hp
    exact ⟨hcs W p n b hW hp hsm, fun b1 _ _ => hbw W p n b1 hW hp hsm⟩
