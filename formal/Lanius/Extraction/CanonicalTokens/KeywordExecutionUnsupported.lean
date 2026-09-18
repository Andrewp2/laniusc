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

theorem body_evaluates (cell : CellId) (leading spelling trailing : List Int)
    (not2 : spelling.length ≠ 2) (not3 : spelling.length ≠ 3)
    (not4 : spelling.length ≠ 4) (not5 : spelling.length ≠ 5)
    (not6 : spelling.length ≠ 6) (not8 : spelling.length ≠ 8) :
    Lanius.FunctionalView.Stateful.Acyclic.run? TM SM
      (Model.keywordWorld cell (leading ++ spelling ++ trailing))
      (KeywordSemantics.lengthEnvironment cell leading spelling trailing)
      KeywordDispatchSemantics.body =
    some (.returned
      (some (.signed .i32 (Int.ofNat TokenKind.identifier.gpuCode))),
      Model.keywordWorld cell (leading ++ spelling ++ trailing),
      KeywordSemantics.lengthEnvironment cell leading spelling trailing) := by
  apply KeywordDispatchSemantics.body_evaluates_of_outcomes
    cell
    (expected := .signed .i32 (Int.ofNat TokenKind.identifier.gpuCode))
  · intro width command member sameLength
    simp [KeywordDispatchSemantics.branchCommands] at member
    rcases member with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ |
      ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩
    all_goals omega
  · exact Or.inr rfl

theorem command_evaluates (cell : CellId) (leading spelling trailing : List Int)
    (bounded : spelling.length ≤ 2147483647)
    (not2 : spelling.length ≠ 2) (not3 : spelling.length ≠ 3)
    (not4 : spelling.length ≠ 4) (not5 : spelling.length ≠ 5)
    (not6 : spelling.length ≠ 6) (not8 : spelling.length ≠ 8) :
    Lanius.FunctionalView.Stateful.Acyclic.run? TM SM
      (Model.keywordWorld cell (leading ++ spelling ++ trailing))
      (Model.keywordEnvironment cell (leading ++ spelling ++ trailing)
        leading.length (leading.length + spelling.length)) KeywordCommand.command =
    some (.returned (some (.signed .i32
        (Model.keywordKind spelling 0 spelling.length))),
      Model.keywordWorld cell (leading ++ spelling ++ trailing),
      Model.keywordEnvironment cell (leading ++ spelling ++ trailing)
        leading.length (leading.length + spelling.length)) := by
  have body := body_evaluates cell leading spelling trailing not2 not3 not4 not5 not6 not8
  rw [keywordKind_identifier spelling not2 not3 not4 not5 not6 not8]
  exact KeywordDispatchSemantics.command_evaluates_of_body cell leading spelling trailing
    (Int.ofNat TokenKind.identifier.gpuCode) bounded body

end Lanius.Extraction.CanonicalTokens.KeywordExecutionUnsupported
