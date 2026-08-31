import Lanius.Extraction.CanonicalTokens.Model

namespace Lanius.Extraction.CanonicalTokens.KeywordLengthSemantics

set_option maxRecDepth 100000

open Lanius
open Lanius.Core
open Lanius.FunctionalView
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.ReadOnly
open Lanius.FunctionalView.Core.Effectful
open Lanius.FunctionalView.Core.Stateful

abbrev TM := termMachine (evaluateOperation verifiedFrontendCore Model.noCalls)
abbrev SM := machineWith verifiedFrontendCore
  (evaluateOperation verifiedFrontendCore Model.noCalls)

/-- Whether every byte test attached to one generated keyword rule succeeds
in the already-loaded FunctionalView environment. -/
def ruleMatches (environment : Env arity) : List (Fin arity × Int) → Bool
  | [] => true
  | (position, expected) :: rest =>
      (match environment position with
        | .signed .i32 actual => actual == expected
        | _ => false) && ruleMatches environment rest

/-- The first generated keyword constant whose byte tests succeed. -/
def firstMatchingConstant (environment : Env arity) :
    List (List (Fin arity × Int) × ConstantId) → Option ConstantId
  | [] => none
  | (bytes, constant) :: rest =>
      if ruleMatches environment bytes then some constant
      else firstMatchingConstant environment rest

theorem directEqual_evaluates
    (environment : Env arity) (position : Fin arity) (actual expected : Int)
    (loaded : environment position = .signed .i32 actual) :
    Term.evaluate TM world environment
        (KeywordCommand.directEqual (KeywordCommand.directSlot position)
          (KeywordCommand.directLiteral expected)) =
      .ok (.boolean (actual == expected), world) := by
  simp only [TM, KeywordCommand.directEqual, KeywordCommand.directSlot,
    KeywordCommand.directLiteral, KeywordCommand.directBinary,
    Term.evaluate, Ref.evaluate, evaluateTerms]
  rw [loaded]
  change Lanius.FunctionalView.Core.Effectful.evaluateOperation
    verifiedFrontendCore Model.noCalls world
      (.binary .equal KeywordCommand.i32 KeywordCommand.i32 KeywordCommand.bool)
      [.signed .i32 actual, .signed .i32 expected] = _
  simp [Lanius.FunctionalView.Core.Effectful.evaluateOperation,
    Lanius.FunctionalView.Core.ReadOnly.evaluateOperation,
    Lanius.Semantics.evalBinaryValue, Lanius.Semantics.scalarEqual,
    bind, Except.bind]
  rfl

private theorem directAllEqual_fold_evaluates
    (environment : Env arity)
    (remaining : List (Fin arity × Int))
    (condition : Term Core.signature arity) (conditionValue : Bool)
    (conditionResult : Term.evaluate TM world environment condition =
      .ok (.boolean conditionValue, world))
    (loaded : ∀ position expected,
      (position, expected) ∈ remaining →
        ∃ actual, environment position = .signed .i32 actual) :
    Term.evaluate TM world environment
        (remaining.foldl
          (fun accumulated next =>
            .logicalAnd accumulated
              (KeywordCommand.directEqual
                (KeywordCommand.directSlot next.1)
                (KeywordCommand.directLiteral next.2)))
          condition) =
      .ok (.boolean (conditionValue && ruleMatches environment remaining),
        world) := by
  induction remaining generalizing condition conditionValue with
  | nil =>
      simpa [ruleMatches] using conditionResult
  | cons head tail inductionHypothesis =>
      obtain ⟨position, expected⟩ := head
      obtain ⟨actual, actualLoaded⟩ := loaded position expected (by simp)
      have equalResult := directEqual_evaluates
        (world := world) environment position actual expected actualLoaded
      have nextLoaded : ∀ nextPosition nextExpected,
          (nextPosition, nextExpected) ∈ tail →
            ∃ nextActual,
              environment nextPosition = .signed .i32 nextActual := by
        intro nextPosition nextExpected member
        exact loaded nextPosition nextExpected (by simp [member])
      have combinedResult : Term.evaluate TM world environment
          (.logicalAnd condition
            (KeywordCommand.directEqual
              (KeywordCommand.directSlot position)
              (KeywordCommand.directLiteral expected))) =
        .ok (.boolean (conditionValue && (actual == expected)), world) := by
        cases conditionValue <;>
          simp [Term.evaluate, conditionResult, equalResult, bind, Except.bind]
      have restResult := inductionHypothesis
        (.logicalAnd condition
          (KeywordCommand.directEqual
            (KeywordCommand.directSlot position)
            (KeywordCommand.directLiteral expected)))
        (conditionValue && (actual == expected)) combinedResult nextLoaded
      simpa [ruleMatches, actualLoaded, Bool.and_assoc] using restResult

theorem directAllEqual_evaluates
    (environment : Env arity) (bytes : List (Fin arity × Int))
    (loaded : ∀ position expected,
      (position, expected) ∈ bytes →
        ∃ actual, environment position = .signed .i32 actual) :
    Term.evaluate TM world environment
        (KeywordCommand.directAllEqual bytes) =
      .ok (.boolean (ruleMatches environment bytes), world) := by
  cases bytes with
  | nil => rfl
  | cons head tail =>
      obtain ⟨position, expected⟩ := head
      obtain ⟨actual, actualLoaded⟩ := loaded position expected (by simp)
      have firstResult := directEqual_evaluates
        (world := world) environment position actual expected actualLoaded
      have tailLoaded : ∀ nextPosition nextExpected,
          (nextPosition, nextExpected) ∈ tail →
            ∃ nextActual,
              environment nextPosition = .signed .i32 nextActual := by
        intro nextPosition nextExpected member
        exact loaded nextPosition nextExpected (by simp [member])
      have folded := directAllEqual_fold_evaluates
        (world := world) environment tail
        (KeywordCommand.directEqual
          (KeywordCommand.directSlot position)
          (KeywordCommand.directLiteral expected))
        (actual == expected) firstResult tailLoaded
      simpa [KeywordCommand.directAllEqual, ruleMatches, actualLoaded] using folded

theorem directConstant_evaluates
    (environment : Env arity) (constant : ConstantId)
    (declaration : Constant)
    (found : verifiedFrontendCore.constant? constant = some declaration) :
    Term.evaluate TM world environment
        (KeywordCommand.directConstant constant) =
      .ok (declaration.value, world) := by
  unfold KeywordCommand.directConstant
  simp only [TM, Term.evaluate, evaluateTerms]
  change Lanius.FunctionalView.Core.Effectful.evaluateOperation
    verifiedFrontendCore Model.noCalls world
      (.constant constant KeywordCommand.i32) [] = _
  simp [Lanius.FunctionalView.Core.Effectful.evaluateOperation,
    Lanius.FunctionalView.Core.ReadOnly.evaluateOperation, found]
  rfl

/-- A decision list with no matching rule falls through without changing its
world or environment. -/
theorem directChoices_noMatch_evaluates
    (environment : Env arity)
    (rules : List (List (Fin arity × Int) × ConstantId))
    (loaded : ∀ bytes constant,
      (bytes, constant) ∈ rules → ∀ position expected,
        (position, expected) ∈ bytes →
          ∃ actual, environment position = .signed .i32 actual)
    (noMatch : firstMatchingConstant environment rules = none) :
    Lanius.FunctionalView.Stateful.Acyclic.run? TM SM world environment
        (KeywordCommand.directChoices rules) =
      some (.next, world, environment) := by
  induction rules with
  | nil => rfl
  | cons head tail inductionHypothesis =>
      obtain ⟨bytes, constant⟩ := head
      have headLoaded : ∀ position expected,
          (position, expected) ∈ bytes →
            ∃ actual, environment position = .signed .i32 actual := by
        intro position expected member
        exact loaded bytes constant (by simp) position expected member
      have conditionResult := directAllEqual_evaluates
        (world := world) environment bytes headLoaded
      have matchesFalse : ruleMatches environment bytes = false := by
        cases matchResult : ruleMatches environment bytes with
        | false => rfl
        | true => simp [firstMatchingConstant, matchResult] at noMatch
      have tailNoMatch : firstMatchingConstant environment tail = none := by
        simpa [firstMatchingConstant, matchesFalse] using noMatch
      have tailLoaded : ∀ nextBytes nextConstant,
          (nextBytes, nextConstant) ∈ tail → ∀ position expected,
            (position, expected) ∈ nextBytes →
              ∃ actual,
                environment position = .signed .i32 actual := by
        intro nextBytes nextConstant member position expected byteMember
        exact loaded nextBytes nextConstant (by simp [member])
          position expected byteMember
      have restResult := inductionHypothesis tailLoaded tailNoMatch
      rw [matchesFalse] at conditionResult
      simp only [KeywordCommand.directChoices,
        Lanius.FunctionalView.Stateful.Acyclic.run?, conditionResult,
        restResult]

/-- `directChoices` returns the checked constant belonging to its first
matching rule.  Only that selected constant needs to be present. -/
theorem directChoices_match_evaluates
    (environment : Env arity)
    (rules : List (List (Fin arity × Int) × ConstantId))
    (loaded : ∀ bytes candidate,
      (bytes, candidate) ∈ rules → ∀ position expected,
        (position, expected) ∈ bytes →
          ∃ actual, environment position = .signed .i32 actual)
    (selected : firstMatchingConstant environment rules = some constant)
    (declaration : Constant)
    (found : verifiedFrontendCore.constant? constant = some declaration) :
    Lanius.FunctionalView.Stateful.Acyclic.run? TM SM world environment
        (KeywordCommand.directChoices rules) =
      some (.returned (some declaration.value), world, environment) := by
  induction rules with
  | nil => simp [firstMatchingConstant] at selected
  | cons head tail inductionHypothesis =>
      obtain ⟨bytes, headConstant⟩ := head
      have headLoaded : ∀ position expected,
          (position, expected) ∈ bytes →
            ∃ actual, environment position = .signed .i32 actual := by
        intro position expected member
        exact loaded bytes headConstant (by simp) position expected member
      have conditionResult := directAllEqual_evaluates
        (world := world) environment bytes headLoaded
      by_cases isMatch : ruleMatches environment bytes = true
      · have sameConstant : headConstant = constant := by
          simpa [firstMatchingConstant, isMatch] using selected
        subst headConstant
        have constantResult := directConstant_evaluates
          (world := world) environment constant declaration found
        rw [isMatch] at conditionResult
        unfold KeywordCommand.directChoices
        simp only [Lanius.FunctionalView.Stateful.Acyclic.run?]
        rw [conditionResult]
        simp only [KeywordCommand.directReturned,
          Lanius.FunctionalView.Stateful.Acyclic.run?]
        rw [constantResult]
      · have matchesFalse : ruleMatches environment bytes = false :=
          by
            cases matchResult : ruleMatches environment bytes with
            | false => rfl
            | true => exact (isMatch matchResult).elim
        have tailSelected :
            firstMatchingConstant environment tail = some constant := by
          simpa [firstMatchingConstant, matchesFalse] using selected
        have tailLoaded : ∀ nextBytes nextConstant,
            (nextBytes, nextConstant) ∈ tail → ∀ position expected,
              (position, expected) ∈ nextBytes →
                ∃ actual,
                  environment position = .signed .i32 actual := by
          intro nextBytes nextConstant member position expected byteMember
          exact loaded nextBytes nextConstant (by simp [member])
            position expected byteMember
        have restResult := inductionHypothesis tailLoaded tailSelected
        rw [matchesFalse] at conditionResult
        simp only [KeywordCommand.directChoices,
          Lanius.FunctionalView.Stateful.Acyclic.run?, conditionResult,
          restResult]

end Lanius.Extraction.CanonicalTokens.KeywordLengthSemantics
