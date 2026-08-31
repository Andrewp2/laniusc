import Lanius.Extraction.CanonicalTokens.IsTriviaSemantics
import Lanius.Extraction.CanonicalTokens.KeywordSpanSemantics
import Lanius.FunctionalViewCoreFreshSimulation

namespace Lanius.Extraction.CanonicalTokens.CallModelContracts

open Lanius
open Lanius.Core
open Lanius.FunctionalView.FreshSimulation
open Lanius.Extraction.CanonicalTokens.Functions

/-- Every successful abstract helper call has one of the two checked source
function shapes, with all bounds needed by the executable proof exposed. -/
theorem success
    (evaluated : Model.callModel.evaluate beforeWorld function arguments =
      .ok (value, afterWorld)) :
    (∃ kind : Int,
      function = isTriviaFunction.id ∧
      arguments = [.signed .i32 kind] ∧
      value = .boolean (IsTriviaSemantics.isTriviaCode kind) ∧
      afterWorld = beforeWorld) ∨
    (∃ (source : List Int) (cell : CellId) (start finish : Nat),
      beforeWorld.i32Slice? cell = some source ∧
      function = keywordKindFunction.id ∧
      arguments = [
        .slice (.scalar (.signed .i32)) cell [] 0 source.length,
        .signed .i32 start, .signed .i32 finish] ∧
      start ≤ finish ∧ finish ≤ source.length ∧
      source.length ≤ 2147483647 ∧
      value = .signed .i32 (Model.keywordKind source start finish) ∧
      afterWorld = beforeWorld) := by
  simp only [Model.callModel] at evaluated
  split at evaluated
  next functionEq =>
    split at evaluated
    next kind =>
      obtain ⟨rfl, rfl⟩ := evaluated
      exact .inl ⟨kind, functionEq,
        rfl, by simp [IsTriviaSemantics.isTriviaCode], rfl⟩
    next => contradiction
  next notTrivia =>
    split at evaluated
    next functionEq =>
      split at evaluated
      next cell length startInt finishInt =>
        split at evaluated
        next valid =>
          split at evaluated
          next source sourceFound =>
            split at evaluated
            next sourceValid =>
              obtain ⟨rfl, rfl⟩ := evaluated
              let start := startInt.toNat
              let finish := finishInt.toNat
              have startEq : (start : Int) = startInt := by
                simp [start]
                omega
              have finishEq : (finish : Int) = finishInt := by
                simp [finish]
                omega
              exact .inr ⟨source, cell, start, finish, sourceFound,
                functionEq, by simp [sourceValid.1, startEq, finishEq],
                by omega, sourceValid.2.2, sourceValid.2.1, rfl, rfl⟩
            next => contradiction
          next => contradiction
        next => contradiction
      next => contradiction
    next => contradiction

/-- Both checked canonical-token query functions are read-only. -/
theorem worldPreserving : WorldPreserving Model.callModel := by
  intro beforeWorld afterWorld function values value evaluated
  simp only [Model.callModel] at evaluated
  split at evaluated <;> try contradiction
  · split at evaluated <;> try contradiction
    exact (congrArg Prod.snd (Except.ok.inj evaluated)).symm
  · split at evaluated <;> try contradiction
    split at evaluated <;> try contradiction
    split at evaluated <;> try contradiction
    split at evaluated <;> try contradiction
    split at evaluated <;> try contradiction
    exact (congrArg Prod.snd (Except.ok.inj evaluated)).symm

end Lanius.Extraction.CanonicalTokens.CallModelContracts
