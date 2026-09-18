import Lanius.Extraction.CanonicalTokens.KeywordDispatchSemantics

namespace Lanius.Extraction.CanonicalTokens.KeywordExecution4

open Lanius
open Lanius.Core
open Lanius.Compiler
open Lanius.FunctionalView
open Lanius.FunctionalView.Core.Stateful
open Lanius.Extraction.CanonicalTokens

abbrev TM := KeywordDispatchSemantics.TM
abbrev SM := KeywordDispatchSemantics.SM

theorem body_evaluates (cell : CellId) (leading trailing : List Int)
    (first second third fourth : Int)
    (bounded : (leading ++ [first, second, third, fourth] ++ trailing).length ≤
      2147483647) :
    Lanius.FunctionalView.Stateful.Acyclic.run? TM SM
      (Model.keywordWorld cell (leading ++ [first, second, third, fourth] ++ trailing))
      (KeywordSemantics.lengthEnvironment cell leading [first, second, third, fourth] trailing)
      KeywordDispatchSemantics.body =
    some (.returned (some (.signed .i32
        (Model.keywordKind [first, second, third, fourth] 0 4))),
      Model.keywordWorld cell (leading ++ [first, second, third, fourth] ++ trailing),
      KeywordSemantics.lengthEnvironment cell
        leading [first, second, third, fourth] trailing) := by
  let spelling := [first, second, third, fourth]
  let world := Model.keywordWorld cell (leading ++ spelling ++ trailing)
  let environment := KeywordSemantics.lengthEnvironment cell leading spelling trailing
  let expected : Value := .signed .i32 (Model.keywordKind spelling 0 4)
  have bounded' : (leading ++ spelling ++ trailing).length ≤ 2147483647 := by
    simpa [spelling] using bounded
  have choice : KeywordChoice.Outcome world environment expected
      (KeywordCommand.directLoad4
        (KeywordCommand.directChoices KeywordCommand.length4Rules)) := by
    apply KeywordChoice.of_choices world
      (KeywordSemantics.loaded4Environment cell leading spelling trailing
        first second third fourth)
      environment expected KeywordCommand.length4Rules KeywordCommand.directLoad4
    · simpa [spelling] using
        KeywordSemantics.length4Rules_loaded cell leading trailing first second third fourth
    · intro completion bodyResult
      exact KeywordSemantics.directLoad4_evaluates_of_body
        cell leading spelling trailing first second third fourth _ completion rfl bounded'
        bodyResult
    · simpa [spelling, expected] using
        KeywordSemantics.length4_decisionValue cell leading trailing first second third fourth
  have body := KeywordDispatchSemantics.body_evaluates_of_outcomes
    cell leading spelling trailing expected
    (by
      intro width command member sameLength
      simp [KeywordDispatchSemantics.branchCommands] at member
      rcases member with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ |
        ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩
      all_goals simp [spelling] at sameLength
      exact choice)
    (Or.inl (by simp [KeywordDispatchSemantics.branchCommands, spelling]))
  simpa [spelling, world, environment, expected] using body

theorem command_evaluates (cell : CellId) (leading trailing : List Int)
    (first second third fourth : Int)
    (bounded : (leading ++ [first, second, third, fourth] ++ trailing).length ≤
      2147483647) :
    Lanius.FunctionalView.Stateful.Acyclic.run? TM SM
      (Model.keywordWorld cell (leading ++ [first, second, third, fourth] ++ trailing))
      (Model.keywordEnvironment cell (leading ++ [first, second, third, fourth] ++ trailing)
        leading.length (leading.length + 4)) KeywordCommand.command =
    some (.returned (some (.signed .i32
        (Model.keywordKind [first, second, third, fourth] 0 4))),
      Model.keywordWorld cell (leading ++ [first, second, third, fourth] ++ trailing),
      Model.keywordEnvironment cell (leading ++ [first, second, third, fourth] ++ trailing)
        leading.length (leading.length + 4)) := by
  let spelling := [first, second, third, fourth]
  have body := body_evaluates cell leading trailing first second third fourth bounded
  have command := KeywordDispatchSemantics.command_evaluates_of_body cell leading spelling trailing
    (Model.keywordKind spelling 0 4) (by simp [spelling]) (by simpa [spelling] using body)
  simpa [spelling] using command

end Lanius.Extraction.CanonicalTokens.KeywordExecution4
