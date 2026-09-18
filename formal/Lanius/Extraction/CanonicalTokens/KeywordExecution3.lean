import Lanius.Extraction.CanonicalTokens.KeywordDispatchSemantics

namespace Lanius.Extraction.CanonicalTokens.KeywordExecution3

open Lanius
open Lanius.Core
open Lanius.Compiler
open Lanius.FunctionalView
open Lanius.FunctionalView.Core.Stateful
open Lanius.Extraction.CanonicalTokens

abbrev TM := KeywordDispatchSemantics.TM
abbrev SM := KeywordDispatchSemantics.SM

theorem body_evaluates (cell : CellId) (leading trailing : List Int) (first second third : Int)
    (bounded : (leading ++ [first, second, third] ++ trailing).length ≤ 2147483647) :
    Lanius.FunctionalView.Stateful.Acyclic.run? TM SM
      (Model.keywordWorld cell (leading ++ [first, second, third] ++ trailing))
      (KeywordSemantics.lengthEnvironment cell leading [first, second, third] trailing)
      KeywordDispatchSemantics.body =
    some (.returned (some (.signed .i32
        (Model.keywordKind [first, second, third] 0 3))),
      Model.keywordWorld cell (leading ++ [first, second, third] ++ trailing),
      KeywordSemantics.lengthEnvironment cell leading [first, second, third] trailing) := by
  let spelling := [first, second, third]
  let world := Model.keywordWorld cell (leading ++ spelling ++ trailing)
  let environment := KeywordSemantics.lengthEnvironment cell leading spelling trailing
  let expected : Value := .signed .i32 (Model.keywordKind spelling 0 3)
  have length3 : spelling.length = 3 := by simp [spelling]
  have bounded' : (leading ++ spelling ++ trailing).length ≤ 2147483647 := by
    simpa [spelling] using bounded
  have choice : KeywordChoice.Outcome world environment expected
      (KeywordCommand.directLoad3
        (KeywordCommand.directChoices KeywordCommand.length3Rules)) := by
    apply KeywordChoice.of_choices world
      (KeywordSemantics.loaded3Environment cell leading spelling trailing first second third)
      environment expected KeywordCommand.length3Rules KeywordCommand.directLoad3
    · simpa [spelling] using
        KeywordSemantics.length3Rules_loaded cell leading trailing first second third
    · intro completion bodyResult
      exact KeywordSemantics.directLoad3_evaluates_of_body
        cell leading spelling trailing first second third _ completion rfl bounded' bodyResult
    · simpa [spelling, expected] using
        KeywordSemantics.length3_decisionValue cell leading trailing first second third
  have body := KeywordDispatchSemantics.body_evaluates_of_outcomes
    cell leading spelling trailing expected
    (by
      intro width command member sameLength
      simp [KeywordDispatchSemantics.branchCommands] at member
      rcases member with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ |
        ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩
      all_goals first | omega | exact choice)
    (Or.inl (by simp [KeywordDispatchSemantics.branchCommands, spelling]))
  simpa [spelling, world, environment, expected] using body

theorem command_evaluates (cell : CellId) (leading trailing : List Int) (first second third : Int)
    (bounded : (leading ++ [first, second, third] ++ trailing).length ≤ 2147483647) :
    Lanius.FunctionalView.Stateful.Acyclic.run? TM SM
      (Model.keywordWorld cell (leading ++ [first, second, third] ++ trailing))
      (Model.keywordEnvironment cell (leading ++ [first, second, third] ++ trailing)
        leading.length (leading.length + 3)) KeywordCommand.command =
    some (.returned (some (.signed .i32
        (Model.keywordKind [first, second, third] 0 3))),
      Model.keywordWorld cell (leading ++ [first, second, third] ++ trailing),
      Model.keywordEnvironment cell (leading ++ [first, second, third] ++ trailing)
        leading.length (leading.length + 3)) := by
  let spelling := [first, second, third]
  have body := body_evaluates cell leading trailing first second third bounded
  have command := KeywordDispatchSemantics.command_evaluates_of_body cell leading spelling trailing
    (Model.keywordKind spelling 0 3) (by simp [spelling]) (by simpa [spelling] using body)
  simpa [spelling] using command

end Lanius.Extraction.CanonicalTokens.KeywordExecution3
