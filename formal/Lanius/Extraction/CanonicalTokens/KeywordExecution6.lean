import Lanius.Extraction.CanonicalTokens.KeywordDispatchSemantics

namespace Lanius.Extraction.CanonicalTokens.KeywordExecution6

open Lanius
open Lanius.Core
open Lanius.Compiler
open Lanius.FunctionalView
open Lanius.FunctionalView.Core.Stateful
open Lanius.Extraction.CanonicalTokens

abbrev TM := KeywordDispatchSemantics.TM
abbrev SM := KeywordDispatchSemantics.SM

theorem body_evaluates
    (cell : CellId) (leading trailing : List Int)
    (first second third fourth fifth sixth : Int)
    (bounded : (leading ++ [first, second, third, fourth, fifth, sixth] ++
      trailing).length ≤ 2147483647) :
    Lanius.FunctionalView.Stateful.Acyclic.run? TM SM
      (Model.keywordWorld cell (leading ++
        [first, second, third, fourth, fifth, sixth] ++ trailing))
      (KeywordSemantics.lengthEnvironment cell leading
        [first, second, third, fourth, fifth, sixth] trailing)
      KeywordDispatchSemantics.body =
    some (.returned (some (.signed .i32
        (Model.keywordKind [first, second, third, fourth, fifth, sixth] 0 6))),
      Model.keywordWorld cell (leading ++
        [first, second, third, fourth, fifth, sixth] ++ trailing),
      KeywordSemantics.lengthEnvironment cell leading
        [first, second, third, fourth, fifth, sixth] trailing) := by
  let spelling := [first, second, third, fourth, fifth, sixth]
  let world := Model.keywordWorld cell (leading ++ spelling ++ trailing)
  let environment := KeywordSemantics.lengthEnvironment cell leading spelling trailing
  let expected : Value := .signed .i32 (Model.keywordKind spelling 0 6)
  have length6 : spelling.length = 6 := by simp [spelling]
  have bounded' : (leading ++ spelling ++ trailing).length ≤ 2147483647 := by
    simpa [spelling] using bounded
  have choice : KeywordChoice.Outcome world environment expected
      (KeywordCommand.directLoad6
        (KeywordCommand.directChoices KeywordCommand.length6Rules)) := by
    apply KeywordChoice.of_choices world
      (KeywordSemantics.loaded6Environment cell leading spelling trailing
        first second third fourth fifth sixth)
      environment expected KeywordCommand.length6Rules KeywordCommand.directLoad6
    · simpa [spelling] using
        KeywordSemantics.length6Rules_loaded cell leading trailing first second third fourth fifth sixth
    · intro completion bodyResult
      exact KeywordSemantics.directLoad6_evaluates_of_body
        cell leading spelling trailing first second third fourth fifth sixth _ completion rfl bounded'
        bodyResult
    · simpa [spelling, expected] using
        KeywordDecision6.decisionValue cell leading trailing first second third fourth fifth sixth
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

theorem command_evaluates
    (cell : CellId) (leading trailing : List Int)
    (first second third fourth fifth sixth : Int)
    (bounded : (leading ++ [first, second, third, fourth, fifth, sixth] ++
      trailing).length ≤ 2147483647) :
    Lanius.FunctionalView.Stateful.Acyclic.run? TM SM
      (Model.keywordWorld cell (leading ++
        [first, second, third, fourth, fifth, sixth] ++ trailing))
      (Model.keywordEnvironment cell (leading ++
          [first, second, third, fourth, fifth, sixth] ++ trailing)
        leading.length (leading.length + 6)) KeywordCommand.command =
    some (.returned (some (.signed .i32
        (Model.keywordKind [first, second, third, fourth, fifth, sixth] 0 6))),
      Model.keywordWorld cell (leading ++
        [first, second, third, fourth, fifth, sixth] ++ trailing),
      Model.keywordEnvironment cell (leading ++
          [first, second, third, fourth, fifth, sixth] ++ trailing)
        leading.length (leading.length + 6)) := by
  let spelling := [first, second, third, fourth, fifth, sixth]
  have body := body_evaluates cell leading trailing first second third fourth fifth
    sixth bounded
  have command := KeywordDispatchSemantics.command_evaluates_of_body
    cell leading spelling trailing (Model.keywordKind spelling 0 6)
    (by simp [spelling]) (by simpa [spelling] using body)
  simpa [spelling] using command

end Lanius.Extraction.CanonicalTokens.KeywordExecution6
