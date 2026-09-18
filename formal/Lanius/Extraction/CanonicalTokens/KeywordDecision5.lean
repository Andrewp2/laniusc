import Lanius.Extraction.CanonicalTokens.KeywordSemantics
import Lanius.Extraction.CanonicalTokens.KeywordTable

namespace Lanius.Extraction.CanonicalTokens.KeywordDecision5

open Lanius.Compiler.Lexer
open Lanius.Compiler
open Lanius.Extraction.CanonicalTokens
open Lanius.FunctionalView

theorem decisionValue
    (cell : CellId) (leading trailing : List Int)
    (first second third fourth fifth : Int) :
    KeywordSemantics.decisionValue
      (KeywordSemantics.loaded5Environment cell leading
        [first, second, third, fourth, fifth] trailing
        first second third fourth fifth)
      KeywordCommand.length5Rules =
    some (.signed .i32
      (Model.keywordKind [first, second, third, fourth, fifth] 0 5)) := by
  unfold KeywordSemantics.decisionValue
  apply KeywordTable.decision_reference
    (query := [first, second, third, fourth, fifth])
  · intro bytes constant member
    simp [KeywordCommand.length5Rules] at member
    rcases member with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ |
      ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩
    all_goals
      simp (disch := decide) only [KeywordLengthSemantics.ruleMatches,
        OfNat.ofNat, Fin.ofNat, Nat.mod_eq_of_lt,
        KeywordSemantics.loaded5Environment,
        KeywordSemantics.loaded4Environment,
        KeywordSemantics.loaded3Environment,
        KeywordSemantics.loaded2Environment,
        KeywordSemantics.loaded1Environment,
        KeywordSemantics.lengthEnvironment,
        Env.push_of_lt, Env.push_last, Bool.and_eq_true,
        List.map, beq_iff_eq, List.cons.injEq, and_true]
  · intro bytes constant member
    simp [KeywordCommand.length5Rules] at member
    rcases member with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ |
      ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩
    all_goals exact ⟨_, rfl, rfl⟩
  · simp [KeywordTable.tableRows, KeywordTable.ruleQuery,
      KeywordCommand.length5Rules, Dispatch.referenceRows]
    decide

end Lanius.Extraction.CanonicalTokens.KeywordDecision5
