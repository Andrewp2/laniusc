module

public import Lanius.Faithful.GenB.SelfBModel5
public import Lanius.Faithful.SelfPre.HB

@[expose] public section

open Lanius.Mini
open Lanius.Faithful.Budget
open Lanius.Faithful.SelfBudget
open Lanius.Faithful.SelfPre

/-- `binary_words`'s precondition, at any budget, for the compile of a program
the front end built from fewer than `2 ^ 31` words, which is at most `2 ^ 48`
high (`FrontEndOutputSmall`). Replaces `PreBinaryWords` for the reason
`PreCompileSourceV2` replaces `PreCompileSource`: the binary's numbers (the
rounds' word counts, the image's offsets) depend on the program, not on the
budget, so the bound is stated on the program and needs no height of the
compiled binary (`PostCompileSource`). -/
def Lanius.Open.PreBinaryWordsV2 : Prop :=
  ∀ (W : List (BitVec 32)) (p : Lanius.Mini.SrcProgram) (n b : Nat), W.length < 2 ^ 31 →
    Lanius.Mini.frontEndWords grammar W = some p → hb p ≤ 2 ^ 48 →
    Pre_binary_words n (Lanius.Mini.compileSource p) b
