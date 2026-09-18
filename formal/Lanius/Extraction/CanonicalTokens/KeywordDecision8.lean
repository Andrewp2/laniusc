import Lanius.Extraction.CanonicalTokens.KeywordSemantics
import Lanius.Extraction.CanonicalTokens.KeywordTable

namespace Lanius.Extraction.CanonicalTokens.KeywordDecision8

open Lanius.Compiler
open Lanius.Compiler.Lexer
open Lanius.Extraction.CanonicalTokens
open Lanius.FunctionalView

theorem decisionValue
    (cell : CellId) (leading trailing : List Int)
    (first second third fourth fifth sixth seventh eighth : Int) :
    KeywordSemantics.decisionValue
      (KeywordSemantics.loaded8Environment cell leading
        [first, second, third, fourth, fifth, sixth, seventh, eighth] trailing
        first second third fourth fifth sixth seventh eighth)
      KeywordCommand.length8Rules =
    some (.signed .i32 (Model.keywordKind
      [first, second, third, fourth, fifth, sixth, seventh, eighth] 0 8)) := by
  unfold KeywordSemantics.decisionValue
  apply KeywordTable.decision_reference
    (query := [first, second, third, fourth, fifth, sixth, seventh, eighth])
  · intro bytes constant member
    simp [KeywordCommand.length8Rules] at member
    rcases member with ⟨rfl, rfl⟩
    simp (disch := decide) only [KeywordLengthSemantics.ruleMatches,
      OfNat.ofNat, Fin.ofNat, Nat.mod_eq_of_lt,
      KeywordSemantics.loaded8Environment,
      KeywordSemantics.loaded7Environment,
      KeywordSemantics.loaded6Environment,
      KeywordSemantics.loaded5Environment,
      KeywordSemantics.loaded4Environment,
      KeywordSemantics.loaded3Environment,
      KeywordSemantics.loaded2Environment,
      KeywordSemantics.loaded1Environment,
      KeywordSemantics.lengthEnvironment, Env.push_of_lt, Env.push_last,
      Bool.and_eq_true,
      List.map, beq_iff_eq, List.cons.injEq, and_true]
  · intro bytes constant member
    simp [KeywordCommand.length8Rules] at member
    rcases member with ⟨rfl, rfl⟩
    exact ⟨_, rfl, rfl⟩
  · simp [KeywordTable.tableRows, KeywordTable.ruleQuery,
      KeywordCommand.length8Rules, Dispatch.referenceRows]
    decide

end Lanius.Extraction.CanonicalTokens.KeywordDecision8
