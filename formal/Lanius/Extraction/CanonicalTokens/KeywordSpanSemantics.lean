import Lanius.Extraction.CanonicalTokens.KeywordExecution

namespace Lanius.Extraction.CanonicalTokens.KeywordSpanSemantics

open Lanius
open Lanius.Core
open Lanius.FunctionalView
open Lanius.FunctionalView.Core.Stateful
open Lanius.Extraction.CanonicalTokens

abbrev TM := KeywordDispatchSemantics.TM
abbrev SM := KeywordDispatchSemantics.SM

/-- The exact checked keyword command implements the logical classifier on
every valid bounded half-open source span, including non-keywords and keyword
prefixes embedded in a larger source slice. -/
theorem command_evaluates (source : List Int) (start finish : Nat)
    (ordered : start ≤ finish) (inBounds : finish ≤ source.length)
    (sourceFitsI32 : source.length ≤ 2147483647) :
    Lanius.FunctionalView.Stateful.Acyclic.run? TM SM
      (Model.keywordWorld source) (Model.keywordEnvironment source start finish)
      KeywordCommand.command =
    some (.returned (some (.signed .i32
        (Model.keywordKind source start finish))),
      Model.keywordWorld source, Model.keywordEnvironment source start finish) := by
  let leading := source.take start
  let spelling := Model.keywordSpan source start finish
  let trailing := source.drop finish
  have startInBounds : start ≤ source.length := Nat.le_trans ordered inBounds
  have leadingLength : leading.length = start := by
    simp [leading, List.length_take, Nat.min_eq_left startInBounds]
  have spellingLength : spelling.length = finish - start := by
    simp [spelling, Model.keywordSpan, List.length_take, List.length_drop]
    omega
  have dropSplit : source.drop start = spelling ++ trailing := by
    unfold spelling trailing Model.keywordSpan
    have dropFinish : source.drop finish =
        (source.drop start).drop (finish - start) := by
      rw [List.drop_drop]
      rw [show start + (finish - start) = finish by omega]
    rw [dropFinish]
    exact (List.take_append_drop (finish - start) (source.drop start)).symm
  have sourceSplit : leading ++ spelling ++ trailing = source := by
    rw [List.append_assoc, ← dropSplit]
    exact List.take_append_drop start source
  have finishLength : start + spelling.length = finish := by
    rw [spellingLength]
    omega
  have embedded := KeywordExecution.command_evaluates leading spelling trailing
    (by simpa [sourceSplit] using sourceFitsI32)
  have logicalResult :
      Model.keywordKind spelling 0 spelling.length =
        Model.keywordKind source start finish := by
    have spellingSpan :
        Model.keywordSpan spelling 0 spelling.length = spelling := by
      simp [Model.keywordSpan]
    have sourceSpan : Model.keywordSpan source start finish = spelling := by
      rfl
    unfold Model.keywordKind
    rw [spellingSpan, sourceSpan]
  rw [sourceSplit, leadingLength, finishLength, logicalResult] at embedded
  exact embedded

end Lanius.Extraction.CanonicalTokens.KeywordSpanSemantics
