import Lanius.Extraction.CanonicalTokens.KeywordDispatchSemantics

namespace Lanius.Extraction.CanonicalTokens.KeywordExecution8

open Lanius
open Lanius.Core
open Lanius.Compiler
open Lanius.FunctionalView
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.Stateful
open Lanius.Extraction.CanonicalTokens

abbrev TM := KeywordDispatchSemantics.TM
abbrev SM := KeywordDispatchSemantics.SM

theorem body_evaluates
    (cell : CellId) (leading trailing : List Int)
    (first second third fourth fifth sixth seventh eighth : Int)
    (bounded : (leading ++
      [first, second, third, fourth, fifth, sixth, seventh, eighth] ++
      trailing).length ≤ 2147483647) :
    Lanius.FunctionalView.Stateful.Acyclic.run? TM SM
      (Model.keywordWorld cell (leading ++
        [first, second, third, fourth, fifth, sixth, seventh, eighth] ++ trailing))
      (KeywordSemantics.lengthEnvironment cell leading
        [first, second, third, fourth, fifth, sixth, seventh, eighth] trailing)
      KeywordDispatchSemantics.body =
    some (.returned (some (.signed .i32
        (Model.keywordKind
          [first, second, third, fourth, fifth, sixth, seventh, eighth] 0 8))),
      Model.keywordWorld cell (leading ++
        [first, second, third, fourth, fifth, sixth, seventh, eighth] ++ trailing),
      KeywordSemantics.lengthEnvironment cell leading
        [first, second, third, fourth, fifth, sixth, seventh, eighth] trailing) := by
  let spelling := [first, second, third, fourth, fifth, sixth, seventh, eighth]
  let world := Model.keywordWorld cell (leading ++ spelling ++ trailing)
  let environment := KeywordSemantics.lengthEnvironment cell leading spelling trailing
  let expected : Value := .signed .i32 (Model.keywordKind spelling 0 8)
  have bounded' : (leading ++ spelling ++ trailing).length ≤ 2147483647 := by
    simpa [spelling] using bounded
  have choice : KeywordChoice.Outcome world environment expected
      (KeywordCommand.directLoad8
        (KeywordCommand.directChoices KeywordCommand.length8Rules)) := by
    apply KeywordChoice.of_choices world
      (KeywordSemantics.loaded8Environment cell leading spelling trailing
        first second third fourth fifth sixth seventh eighth)
      environment expected KeywordCommand.length8Rules KeywordCommand.directLoad8
    · simpa [spelling] using
        KeywordSemantics.length8Rules_loaded cell leading trailing
          first second third fourth fifth sixth seventh eighth
    · intro completion bodyResult
      exact KeywordSemantics.directLoad8_evaluates_of_body
        cell leading spelling trailing first second third fourth fifth sixth seventh eighth
        _ completion rfl bounded' bodyResult
    · simpa [spelling, expected] using
        KeywordDecision8.decisionValue cell leading trailing
          first second third fourth fifth sixth seventh eighth
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

theorem command_evaluates
    (cell : CellId) (leading trailing : List Int)
    (first second third fourth fifth sixth seventh eighth : Int)
    (bounded : (leading ++
      [first, second, third, fourth, fifth, sixth, seventh, eighth] ++
      trailing).length ≤ 2147483647) :
    Lanius.FunctionalView.Stateful.Acyclic.run? TM SM
      (Model.keywordWorld cell (leading ++
        [first, second, third, fourth, fifth, sixth, seventh, eighth] ++ trailing))
      (Model.keywordEnvironment cell (leading ++
          [first, second, third, fourth, fifth, sixth, seventh, eighth] ++ trailing)
        leading.length (leading.length + 8)) KeywordCommand.command =
    some (.returned (some (.signed .i32
        (Model.keywordKind
          [first, second, third, fourth, fifth, sixth, seventh, eighth] 0 8))),
      Model.keywordWorld cell (leading ++
        [first, second, third, fourth, fifth, sixth, seventh, eighth] ++ trailing),
      Model.keywordEnvironment cell (leading ++
          [first, second, third, fourth, fifth, sixth, seventh, eighth] ++ trailing)
        leading.length (leading.length + 8)) := by
  let spelling := [first, second, third, fourth, fifth, sixth, seventh, eighth]
  let world := Model.keywordWorld cell (leading ++ spelling ++ trailing)
  let environment := Model.keywordEnvironment cell (leading ++ spelling ++ trailing)
    leading.length (leading.length + spelling.length)
  have lengthBound : spelling.length ≤ 2147483647 := by
    simp [spelling]
  have initializer := KeywordDispatchSemantics.lengthInitializer_evaluates
    cell leading spelling trailing lengthBound
  have body := body_evaluates cell leading trailing first second third fourth fifth
    sixth seventh eighth bounded
  rw [show KeywordCommand.command = KeywordCommand.directCommand by rfl,
    KeywordDispatchSemantics.directCommand_body]
  apply KeywordSemantics.run_letValue_preserving world environment
    KeywordCommand.i32 _ _ (.signed .i32 (Int.ofNat spelling.length))
    (.returned (some (.signed .i32 (Model.keywordKind spelling 0 8))))
  · simpa [world, environment] using initializer
  · simpa [world, environment, spelling, KeywordSemantics.lengthEnvironment]
      using body

end Lanius.Extraction.CanonicalTokens.KeywordExecution8
