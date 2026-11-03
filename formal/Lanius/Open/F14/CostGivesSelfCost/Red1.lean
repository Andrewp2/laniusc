import Lanius.Open.F14.CostGivesSelfCost.Stmt
import Lanius.Open.F14.PreFrontEndWords.Stmt
import Lanius.Open.F14.PreCompileWords.Stmt

open Lanius.Mini
open Lanius.Core (Value)
open Lanius.X86.Machine
open Lanius.Faithful
open Lanius.Faithful.Self
open Lanius.Faithful.SelfRep
open Lanius.Faithful.SelfDriver
open Lanius.Faithful.SelfCompiler
open Lanius.Faithful.SelfLive
open Lanius.Faithful.SelfPanics
open Lanius.Faithful.SelfAgree
open Lanius.Faithful.SelfShort
open Lanius.Faithful.Termination
open Lanius.Faithful.SelfBounded
open Lanius.Faithful.SelfTotal
open Lanius.Faithful.Budget
open Lanius.Faithful.SelfBudget

/-- `SelfBounded.selfCost_of_pre` at `T = 2 ^ 61`, with `compile_words`'s
precondition taken after the front end's certificate gives its cost. -/
theorem Lanius.Open.CostGivesSelfCost.red1 (hf : Lanius.Open.PreFrontEndWords)
    (hc : Lanius.Open.PreCompileWords) : Lanius.Open.CostGivesSelfCost := by
  intro W hW N k h lt
  simp only [costW] at h
  cases h8 : qcall progW prims (boxCost prog) N 8 [] with
  | none => rw [h8] at h; cases h
  | some g =>
    rw [h8] at h
    simp only [Option.bind_some] at h
    cases h7 : qcall progW prims (boxCost prog) N 7 [g.1, listVal W] with
    | none => rw [h7] at h; cases h
    | some fe =>
      rw [h7] at h
      simp only [Option.bind_some] at h
      cases h6 : qcall progW prims (boxCost prog) N 6 [fe.1] with
      | none => rw [h6] at h; cases h
      | some cw =>
        rw [h6] at h
        simp only [Option.bind_some, Option.some.injEq] at h
        obtain ⟨k8, u8, l8⟩ := uc_of_box h8
        obtain ⟨k7, u7, l7⟩ := uc_of_box h7
        obtain ⟨k6, u6, l6⟩ := uc_of_box h6
        obtain ⟨p8, c8, r8⟩ := bcert_grammar u8
        obtain ⟨p7, c7, r7⟩ := bcert_front_end_words u7 r8 (listVal_rep W) (b := 2 ^ 61 - Cost_grammar N)
          (by omega) (hf N W _ hW (by omega))
        obtain ⟨p6, c6, r6⟩ := bcert_compile_words u6 r7
          (b := 2 ^ 61 - Cost_grammar N - Cost_front_end_words N grammar W) (by omega) (hc N W _ hW (by omega))
        obtain ⟨b8, q8⟩ := box_of_uc p8
        obtain ⟨b7, q7⟩ := box_of_uc p7
        obtain ⟨b6, q6⟩ := box_of_uc p6
        exact ⟨W.length * consCost + b8 + b7 + b6, by simp [selfCost, q8, q7, q6]⟩
