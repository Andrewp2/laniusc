import Lanius.Extraction.CanonicalTokens.KeywordDispatchSemantics

namespace Lanius.Extraction.CanonicalTokens.KeywordExecution2

open Lanius
open Lanius.Core
open Lanius.Compiler
open Lanius.FunctionalView
open Lanius.FunctionalView.Core.Stateful
open Lanius.Extraction.CanonicalTokens

abbrev TM := KeywordDispatchSemantics.TM
abbrev SM := KeywordDispatchSemantics.SM

theorem body_evaluates (cell : CellId) (leading trailing : List Int) (first second : Int)
    (bounded : (leading ++ [first, second] ++ trailing).length ≤ 2147483647) :
    Lanius.FunctionalView.Stateful.Acyclic.run? TM SM
      (Model.keywordWorld cell (leading ++ [first, second] ++ trailing))
      (KeywordSemantics.lengthEnvironment cell leading [first, second] trailing)
      KeywordDispatchSemantics.body =
    some (.returned (some (.signed .i32
        (Model.keywordKind [first, second] 0 2))),
      Model.keywordWorld cell (leading ++ [first, second] ++ trailing),
      KeywordSemantics.lengthEnvironment cell leading [first, second] trailing) := by
  let spelling := [first, second]
  let world := Model.keywordWorld cell (leading ++ spelling ++ trailing)
  let environment := KeywordSemantics.lengthEnvironment cell leading spelling trailing
  let expected : Value := .signed .i32 (Model.keywordKind spelling 0 2)
  have length2 : spelling.length = 2 := by simp [spelling]
  have bounded' : (leading ++ spelling ++ trailing).length ≤ 2147483647 := by
    simpa [spelling] using bounded
  have choice : KeywordChoice.Outcome world environment expected
      (KeywordCommand.directLoad2
        (KeywordCommand.directChoices KeywordCommand.length2Rules)) := by
    apply KeywordChoice.of_choices world
      (KeywordSemantics.loaded2Environment cell leading spelling trailing first second)
      environment expected KeywordCommand.length2Rules KeywordCommand.directLoad2
    · simpa [spelling] using
        KeywordSemantics.length2Rules_loaded cell leading trailing first second
    · intro completion bodyResult
      exact KeywordSemantics.directLoad2_evaluates_of_body
        cell leading spelling trailing first second _ completion rfl bounded' bodyResult
    · simpa [spelling, expected] using
        KeywordSemantics.length2_decisionValue cell leading trailing first second
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

theorem command_evaluates (cell : CellId) (leading trailing : List Int) (first second : Int)
    (bounded : (leading ++ [first, second] ++ trailing).length ≤ 2147483647) :
    Lanius.FunctionalView.Stateful.Acyclic.run? TM SM
      (Model.keywordWorld cell (leading ++ [first, second] ++ trailing))
      (Model.keywordEnvironment cell (leading ++ [first, second] ++ trailing)
        leading.length (leading.length + 2)) KeywordCommand.command =
    some (.returned (some (.signed .i32 (Model.keywordKind [first, second] 0 2))),
      Model.keywordWorld cell (leading ++ [first, second] ++ trailing),
      Model.keywordEnvironment cell (leading ++ [first, second] ++ trailing)
        leading.length (leading.length + 2)) := by
  let spelling := [first, second]
  have body := body_evaluates cell leading trailing first second bounded
  have command := KeywordDispatchSemantics.command_evaluates_of_body cell leading spelling trailing
    (Model.keywordKind spelling 0 2) (by simp [spelling]) (by simpa [spelling] using body)
  simpa [spelling] using command

end Lanius.Extraction.CanonicalTokens.KeywordExecution2
