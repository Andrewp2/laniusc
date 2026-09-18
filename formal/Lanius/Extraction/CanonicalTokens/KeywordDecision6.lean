import Lanius.Extraction.CanonicalTokens.KeywordSemantics
import Lanius.Extraction.CanonicalTokens.KeywordTable

namespace Lanius.Extraction.CanonicalTokens.KeywordDecision6

open Lanius.Compiler
open Lanius.Compiler.Lexer
open Lanius.Extraction.CanonicalTokens
open Lanius.FunctionalView

theorem decisionValue
    (cell : CellId) (leading trailing : List Int)
    (first second third fourth fifth sixth : Int) :
    KeywordSemantics.decisionValue
      (KeywordSemantics.loaded6Environment cell leading
        [first, second, third, fourth, fifth, sixth] trailing
        first second third fourth fifth sixth)
      KeywordCommand.length6Rules =
    some (.signed .i32
      (Model.keywordKind [first, second, third, fourth, fifth, sixth] 0 6)) := by
  unfold KeywordSemantics.decisionValue
  apply KeywordTable.decision_reference
  · intro bytes constant member
    simp [KeywordCommand.length6Rules] at member
    rcases member with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ <;>
      simp only [KeywordLengthSemantics.ruleMatches, Bool.and_eq_true]
    all_goals simp (disch := decide) only [OfNat.ofNat, Fin.ofNat,
      Nat.mod_eq_of_lt, KeywordSemantics.loaded6Environment,
      KeywordSemantics.loaded5Environment,
      KeywordSemantics.loaded4Environment,
      KeywordSemantics.loaded3Environment,
      KeywordSemantics.loaded2Environment,
      KeywordSemantics.loaded1Environment,
      KeywordSemantics.lengthEnvironment, Env.push_of_lt, Env.push_last,
      beq_iff_eq, and_true,
      List.map, List.cons.injEq]
  · intro bytes constant member
    simp [KeywordCommand.length6Rules] at member
    rcases member with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ <;>
      exact ⟨_, rfl, rfl⟩
  · change (KeywordTable.tableRows KeywordCommand.length6Rules).Perm
      (Dispatch.referenceRows.filter (fun row => row.1.length == 6))
    decide

end Lanius.Extraction.CanonicalTokens.KeywordDecision6
