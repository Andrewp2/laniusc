import Lanius.Extraction.CanonicalTokens.KeywordDispatchSemantics

namespace Lanius.Extraction.CanonicalTokens.KeywordExecutionUnsupported

open Lanius
open Lanius.Core
open Lanius.Compiler
open Lanius.Compiler.Lexer
open Lanius.FunctionalView
open Lanius.FunctionalView.Core.Stateful
open Lanius.Extraction.CanonicalTokens

abbrev TM := KeywordDispatchSemantics.TM
abbrev SM := KeywordDispatchSemantics.SM

private theorem length_beq_false (length expected : Nat)
    (different : length ≠ expected) :
    (Int.ofNat length == Int.ofNat expected) = false := by
  apply beq_eq_false_iff_ne.mpr
  intro same
  exact different (Int.ofNat_inj.mp same)

theorem keywordKind_identifier (spelling : List Int)
    (not2 : spelling.length ≠ 2) (not3 : spelling.length ≠ 3)
    (not4 : spelling.length ≠ 4) (not5 : spelling.length ≠ 5)
    (not6 : spelling.length ≠ 6) (not8 : spelling.length ≠ 8) :
    Model.keywordKind spelling 0 spelling.length =
      Int.ofNat TokenKind.identifier.gpuCode := by
  unfold Model.keywordKind Model.keywordSpan
  simp only [List.drop_zero, Nat.sub_zero, List.take_length]
  change Int.ofNat (match exactKeywordKind (spelling.map Int.toNat)
      keywordRules with
    | some kind => kind.gpuCode
    | none => TokenKind.identifier.gpuCode) = _
  have none := KeywordSpecification.exactKeywordKind_none_of_unsupported_length
    (spelling.map Int.toNat) (by simpa using not2) (by simpa using not3)
    (by simpa using not4) (by simpa using not5) (by simpa using not6)
    (by simpa using not8)
  rw [none]

theorem body_evaluates (leading spelling trailing : List Int)
    (not2 : spelling.length ≠ 2) (not3 : spelling.length ≠ 3)
    (not4 : spelling.length ≠ 4) (not5 : spelling.length ≠ 5)
    (not6 : spelling.length ≠ 6) (not8 : spelling.length ≠ 8) :
    Lanius.FunctionalView.Stateful.Acyclic.run? TM SM
      (Model.keywordWorld (leading ++ spelling ++ trailing))
      (KeywordSemantics.lengthEnvironment leading spelling trailing)
      KeywordDispatchSemantics.body =
    some (.returned
      (some (.signed .i32 (Int.ofNat TokenKind.identifier.gpuCode))),
      Model.keywordWorld (leading ++ spelling ++ trailing),
      KeywordSemantics.lengthEnvironment leading spelling trailing) := by
  let world := Model.keywordWorld (leading ++ spelling ++ trailing)
  let environment := KeywordSemantics.lengthEnvironment leading spelling trailing
  have branch2 := KeywordDispatchSemantics.lengthBranch_false leading spelling trailing 2
    (KeywordCommand.directLoad2
      (KeywordCommand.directChoices KeywordCommand.length2Rules))
    (by simpa using length_beq_false spelling.length 2 not2)
  have branch3 := KeywordDispatchSemantics.lengthBranch_false leading spelling trailing 3
    (KeywordCommand.directLoad3
      (KeywordCommand.directChoices KeywordCommand.length3Rules))
    (by simpa using length_beq_false spelling.length 3 not3)
  have branch4 := KeywordDispatchSemantics.lengthBranch_false leading spelling trailing 4
    (KeywordCommand.directLoad4
      (KeywordCommand.directChoices KeywordCommand.length4Rules))
    (by simpa using length_beq_false spelling.length 4 not4)
  have branch5 := KeywordDispatchSemantics.lengthBranch_false leading spelling trailing 5
    (KeywordCommand.directLoad5
      (KeywordCommand.directChoices KeywordCommand.length5Rules))
    (by simpa using length_beq_false spelling.length 5 not5)
  have branch6 := KeywordDispatchSemantics.lengthBranch_false leading spelling trailing 6
    (KeywordCommand.directLoad6
      (KeywordCommand.directChoices KeywordCommand.length6Rules))
    (by simpa using length_beq_false spelling.length 6 not6)
  have branch8 := KeywordDispatchSemantics.lengthBranch_false leading spelling trailing 8
    (KeywordCommand.directLoad8
      (KeywordCommand.directChoices KeywordCommand.length8Rules))
    (by simpa using length_beq_false spelling.length 8 not8)
  have finalResult := KeywordDispatchSemantics.identifier_return_evaluates
    leading spelling trailing
  have tail8 := KeywordDispatchSemantics.sequence_next world environment _ _ _
    branch8 finalResult
  have tail6 := KeywordDispatchSemantics.sequence_next world environment _ _ _
    branch6 tail8
  have tail5 := KeywordDispatchSemantics.sequence_next world environment _ _ _
    branch5 tail6
  have tail4 := KeywordDispatchSemantics.sequence_next world environment _ _ _
    branch4 tail5
  have tail3 := KeywordDispatchSemantics.sequence_next world environment _ _ _
    branch3 tail4
  have all := KeywordDispatchSemantics.sequence_next world environment _ _ _
    branch2 tail3
  simpa [KeywordDispatchSemantics.body, world, environment] using all

theorem command_evaluates (leading spelling trailing : List Int)
    (bounded : spelling.length ≤ 2147483647)
    (not2 : spelling.length ≠ 2) (not3 : spelling.length ≠ 3)
    (not4 : spelling.length ≠ 4) (not5 : spelling.length ≠ 5)
    (not6 : spelling.length ≠ 6) (not8 : spelling.length ≠ 8) :
    Lanius.FunctionalView.Stateful.Acyclic.run? TM SM
      (Model.keywordWorld (leading ++ spelling ++ trailing))
      (Model.keywordEnvironment (leading ++ spelling ++ trailing)
        leading.length (leading.length + spelling.length)) KeywordCommand.command =
    some (.returned (some (.signed .i32
        (Model.keywordKind spelling 0 spelling.length))),
      Model.keywordWorld (leading ++ spelling ++ trailing),
      Model.keywordEnvironment (leading ++ spelling ++ trailing)
        leading.length (leading.length + spelling.length)) := by
  have body := body_evaluates leading spelling trailing not2 not3 not4 not5 not6 not8
  rw [keywordKind_identifier spelling not2 not3 not4 not5 not6 not8]
  exact KeywordDispatchSemantics.command_evaluates_of_body leading spelling trailing
    (Int.ofNat TokenKind.identifier.gpuCode) bounded body

end Lanius.Extraction.CanonicalTokens.KeywordExecutionUnsupported
