import Lanius.Extraction.CanonicalTokens.KeywordSemantics

namespace Lanius.Extraction.CanonicalTokens.KeywordChoice

open Lanius
open Lanius.Core
open Lanius.FunctionalView
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.ReadOnly
open Lanius.FunctionalView.Core.Stateful

abbrev TM := KeywordSemantics.TM
abbrev SM := KeywordSemantics.SM

/-- The two observable outcomes of a keyword choice: returning the selected
value, or falling through as the identifier case.  Both outcomes preserve the
world and environment supplied to the command. -/
def Outcome (world : World) (environment : Env arity) (expected : Value)
    (command : KeywordCommand.C arity) : Prop :=
  Lanius.FunctionalView.Stateful.Acyclic.run? TM SM world environment command =
      some (.returned (some expected), world, environment) ∨
    (expected = .signed .i32 (Int.ofNat Compiler.TokenKind.identifier.gpuCode) ∧
      Lanius.FunctionalView.Stateful.Acyclic.run? TM SM world environment command =
        some (.next, world, environment))

theorem of_choices
    {loadedArity baseArity : Nat}
    (world : World)
    (loadedEnvironment : Env loadedArity)
    (baseEnvironment : Env baseArity)
    (expected : Value)
    (rules : List (List (Fin loadedArity × Int) × ConstantId))
    (load : KeywordCommand.C loadedArity → KeywordCommand.C baseArity)
    (loaded : ∀ bytes constant,
      (bytes, constant) ∈ rules → ∀ position expectedByte,
        (position, expectedByte) ∈ bytes →
          ∃ actual, loadedEnvironment position = .signed .i32 actual)
    (loadPreserving : ∀ completion,
      Lanius.FunctionalView.Stateful.Acyclic.run? TM SM world loadedEnvironment
          (KeywordCommand.directChoices rules) =
        some (completion, world, loadedEnvironment) →
      Lanius.FunctionalView.Stateful.Acyclic.run? TM SM world baseEnvironment
          (load (KeywordCommand.directChoices rules)) =
        some (completion, world, baseEnvironment))
    (decision : KeywordSemantics.decisionValue loadedEnvironment rules =
      some expected) :
    Outcome world baseEnvironment expected
      (load (KeywordCommand.directChoices rules)) := by
  unfold Outcome
  cases selected : KeywordLengthSemantics.firstMatchingConstant
      loadedEnvironment rules with
  | none =>
      have decision' := decision
      unfold KeywordSemantics.decisionValue at decision'
      rw [selected] at decision'
      simp only [Option.getD_none] at decision'
      have fallback : verifiedFrontendCore.constant? 7 = some {
          id := 7, type := KeywordCommand.i32,
          value := .signed .i32
            (Int.ofNat Compiler.TokenKind.identifier.gpuCode) } := by
        rfl
      rw [fallback] at decision'
      simp only [Option.map_some] at decision'
      right
      refine ⟨?_, loadPreserving .next ?_⟩
      · exact (Option.some.inj decision').symm
      · exact KeywordLengthSemantics.directChoices_noMatch_evaluates
          (world := world) loadedEnvironment rules loaded selected
  | some constant =>
      have decision' := decision
      unfold KeywordSemantics.decisionValue at decision'
      rw [selected] at decision'
      simp only [Option.getD_some] at decision'
      cases found : verifiedFrontendCore.constant? constant with
      | none =>
          simp [found] at decision'
      | some declaration =>
          rw [found] at decision'
          simp only [Option.map_some] at decision'
          left
          have loadedResult :=
            KeywordLengthSemantics.directChoices_match_evaluates
              (world := world) loadedEnvironment rules loaded selected
                declaration found
          have baseResult := loadPreserving
            (.returned (some declaration.value)) loadedResult
          simpa [Option.some.inj decision'] using baseResult

end Lanius.Extraction.CanonicalTokens.KeywordChoice
