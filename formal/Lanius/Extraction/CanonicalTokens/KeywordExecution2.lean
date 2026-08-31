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

theorem body_evaluates (leading trailing : List Int) (first second : Int)
    (bounded : (leading ++ [first, second] ++ trailing).length ≤ 2147483647) :
    Lanius.FunctionalView.Stateful.Acyclic.run? TM SM
      (Model.keywordWorld (leading ++ [first, second] ++ trailing))
      (KeywordSemantics.lengthEnvironment leading [first, second] trailing)
      KeywordDispatchSemantics.body =
    some (.returned (some (.signed .i32
        (Model.keywordKind [first, second] 0 2))),
      Model.keywordWorld (leading ++ [first, second] ++ trailing),
      KeywordSemantics.lengthEnvironment leading [first, second] trailing) := by
  let spelling := [first, second]
  let world := Model.keywordWorld (leading ++ spelling ++ trailing)
  let environment := KeywordSemantics.lengthEnvironment leading spelling trailing
  have branch3 := KeywordDispatchSemantics.lengthBranch_false leading spelling trailing 3
    (KeywordCommand.directLoad3
      (KeywordCommand.directChoices KeywordCommand.length3Rules)) (by simp [spelling])
  have branch4 := KeywordDispatchSemantics.lengthBranch_false leading spelling trailing 4
    (KeywordCommand.directLoad4
      (KeywordCommand.directChoices KeywordCommand.length4Rules)) (by simp [spelling])
  have branch5 := KeywordDispatchSemantics.lengthBranch_false leading spelling trailing 5
    (KeywordCommand.directLoad5
      (KeywordCommand.directChoices KeywordCommand.length5Rules)) (by simp [spelling])
  have branch6 := KeywordDispatchSemantics.lengthBranch_false leading spelling trailing 6
    (KeywordCommand.directLoad6
      (KeywordCommand.directChoices KeywordCommand.length6Rules)) (by simp [spelling])
  have branch8 := KeywordDispatchSemantics.lengthBranch_false leading spelling trailing 8
    (KeywordCommand.directLoad8
      (KeywordCommand.directChoices KeywordCommand.length8Rules)) (by simp [spelling])
  have finalResult := KeywordDispatchSemantics.identifier_return_evaluates leading spelling trailing
  have tail8 := KeywordDispatchSemantics.sequence_next world environment _ _ _ branch8 finalResult
  have tail6 := KeywordDispatchSemantics.sequence_next world environment _ _ _ branch6 tail8
  have tail5 := KeywordDispatchSemantics.sequence_next world environment _ _ _ branch5 tail6
  have tail4 := KeywordDispatchSemantics.sequence_next world environment _ _ _ branch4 tail5
  have tail3 := KeywordDispatchSemantics.sequence_next world environment _ _ _ branch3 tail4
  cases selected : KeywordLengthSemantics.firstMatchingConstant
      (KeywordSemantics.loaded2Environment leading spelling trailing first second)
      KeywordCommand.length2Rules with
  | none =>
      have loadResult := KeywordSemantics.directLoad2_noMatch_evaluates leading spelling
        trailing first second rfl bounded selected
      have branch2 := KeywordDispatchSemantics.lengthBranch_true leading spelling trailing 2
        (KeywordCommand.directLoad2
          (KeywordCommand.directChoices KeywordCommand.length2Rules))
        .next (by simp [spelling]) loadResult
      have all := KeywordDispatchSemantics.sequence_next world environment _ _ _ branch2 tail3
      have decision := KeywordSemantics.length2_decisionValue leading trailing first second
      unfold KeywordSemantics.decisionValue at decision
      rw [selected] at decision
      simp only [Option.getD_none] at decision
      have constant7 : verifiedFrontendCore.constant? 7 = some {
          id := 7, type := KeywordCommand.i32,
          value := .signed .i32 (Int.ofNat Compiler.TokenKind.identifier.gpuCode) } := by rfl
      rw [constant7] at decision
      simp only [Option.map_some] at decision
      have valueEq := Option.some.inj decision
      have identifierResult : Model.keywordKind spelling 0 2 =
          Int.ofNat Compiler.TokenKind.identifier.gpuCode := by
        simpa [spelling] using Value.signed.inj valueEq.symm
      simpa [KeywordDispatchSemantics.body, spelling, world, environment,
        identifierResult] using all
  | some constant =>
      have decision := KeywordSemantics.length2_decisionValue leading trailing first second
      unfold KeywordSemantics.decisionValue at decision
      rw [selected] at decision
      simp only [Option.getD_some] at decision
      cases found : verifiedFrontendCore.constant? constant with
      | none => simp [found] at decision
      | some declaration =>
          rw [found] at decision
          simp only [Option.map_some] at decision
          have valueEq : declaration.value = .signed .i32
              (Model.keywordKind spelling 0 2) := by
            simpa [spelling] using Option.some.inj decision
          have loadResult := KeywordSemantics.directLoad2_match_evaluates leading spelling
            trailing first second constant declaration rfl bounded selected found
          have branch2 := KeywordDispatchSemantics.lengthBranch_true leading spelling trailing 2
            (KeywordCommand.directLoad2
              (KeywordCommand.directChoices KeywordCommand.length2Rules))
            (.returned (some declaration.value)) (by simp [spelling]) loadResult
          have all := KeywordDispatchSemantics.sequence_stop world environment
            (KeywordCommand.directLengthBranch 2
              (KeywordCommand.directLoad2
                (KeywordCommand.directChoices KeywordCommand.length2Rules)))
            (.sequence (KeywordCommand.directLengthBranch 3
                (KeywordCommand.directLoad3
                  (KeywordCommand.directChoices KeywordCommand.length3Rules)))
              (.sequence (KeywordCommand.directLengthBranch 4
                  (KeywordCommand.directLoad4
                    (KeywordCommand.directChoices KeywordCommand.length4Rules)))
                (.sequence (KeywordCommand.directLengthBranch 5
                    (KeywordCommand.directLoad5
                      (KeywordCommand.directChoices KeywordCommand.length5Rules)))
                  (.sequence (KeywordCommand.directLengthBranch 6
                      (KeywordCommand.directLoad6
                        (KeywordCommand.directChoices KeywordCommand.length6Rules)))
                    (.sequence (KeywordCommand.directLengthBranch 8
                        (KeywordCommand.directLoad8
                          (KeywordCommand.directChoices KeywordCommand.length8Rules)))
                      (KeywordCommand.directReturned (KeywordCommand.directConstant 7)))))))
            (some declaration.value) branch2
          simpa [KeywordDispatchSemantics.body, spelling, world, environment, valueEq] using all

theorem command_evaluates (leading trailing : List Int) (first second : Int)
    (bounded : (leading ++ [first, second] ++ trailing).length ≤ 2147483647) :
    Lanius.FunctionalView.Stateful.Acyclic.run? TM SM
      (Model.keywordWorld (leading ++ [first, second] ++ trailing))
      (Model.keywordEnvironment (leading ++ [first, second] ++ trailing)
        leading.length (leading.length + 2)) KeywordCommand.command =
    some (.returned (some (.signed .i32 (Model.keywordKind [first, second] 0 2))),
      Model.keywordWorld (leading ++ [first, second] ++ trailing),
      Model.keywordEnvironment (leading ++ [first, second] ++ trailing)
        leading.length (leading.length + 2)) := by
  let spelling := [first, second]
  have body := body_evaluates leading trailing first second bounded
  have command := KeywordDispatchSemantics.command_evaluates_of_body leading spelling trailing
    (Model.keywordKind spelling 0 2) (by simp [spelling]) (by simpa [spelling] using body)
  simpa [spelling] using command

end Lanius.Extraction.CanonicalTokens.KeywordExecution2
