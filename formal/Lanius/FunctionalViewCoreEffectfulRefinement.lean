import Lanius.FunctionalViewCoreEffectful

namespace Lanius.FunctionalView.Core.Effectful

open Lanius
open Lanius.Core
open Lanius.FunctionalView
open Lanius.FunctionalView.Core

/-! # Call-model refinement for FunctionalView terms

Nested compiler commands are often proved against the smallest call registry
that interprets them.  An enclosing command may add unrelated call routes.
The definitions below record the call IDs a term permits and transport its
evaluation whenever two registries agree on those IDs.
-/

/-- Whether one Core operation's source call is accepted by a call policy.
    Non-call operations do not consult a `CallModel`. -/
def operationCallsSatisfy (allowed : FunctionId → Bool) : Operation → Bool
  | .call function _ _ => allowed function
  | _ => true

mutual
  /-- Every source call nested in a term satisfies `allowed`. -/
  def termCallsSatisfy (allowed : FunctionId → Bool) :
      Term Core.signature arity → Bool
    | .reference _ => true
    | .apply operation arguments =>
        operationCallsSatisfy allowed operation &&
          termsCallsSatisfy allowed arguments
    | .logicalAnd left right | .logicalOr left right =>
        termCallsSatisfy allowed left && termCallsSatisfy allowed right

  /-- Every source call nested in a term list satisfies `allowed`. -/
  def termsCallsSatisfy (allowed : FunctionId → Bool) :
      List (Term Core.signature arity) → Bool
    | [] => true
    | term :: terms =>
        termCallsSatisfy allowed term && termsCallsSatisfy allowed terms
end

/-- Two call registries agree on every function admitted by a policy. -/
def CallModel.AgreesWhere (allowed : FunctionId → Bool)
    (first second : CallModel) : Prop :=
  ∀ world function arguments, allowed function = true →
    first.evaluate world function arguments =
      second.evaluate world function arguments

theorem evaluateOperation_eq_of_callsSatisfy
    (agreement : first.AgreesWhere allowed second)
    (supported : operationCallsSatisfy allowed operation = true) :
    evaluateOperation program first world operation arguments =
      evaluateOperation program second world operation arguments := by
  cases operation <;> simp_all [operationCallsSatisfy, evaluateOperation]
  case binary operation _ _ _ =>
    cases operation <;> simp_all [operationCallsSatisfy, evaluateOperation]
  case call function _ _ =>
    exact agreement world function arguments supported

mutual
  theorem term_evaluate_eq_of_callsSatisfy
      (agreement : first.AgreesWhere allowed second)
      (term : Term Core.signature arity)
      (supported : termCallsSatisfy allowed term = true) :
      Term.evaluate (machine program first) world environment term =
        Term.evaluate (machine program second) world environment term := by
    cases term with
    | reference reference => rfl
    | apply operation arguments =>
        have components : operationCallsSatisfy allowed operation = true ∧
            termsCallsSatisfy allowed arguments = true := by
          simpa only [termCallsSatisfy, Bool.and_eq_true] using supported
        simp only [Term.evaluate]
        rw [terms_evaluate_eq_of_callsSatisfy agreement arguments components.2]
        apply bind_congr
        intro result
        exact evaluateOperation_eq_of_callsSatisfy agreement components.1
    | logicalAnd left right =>
        have components : termCallsSatisfy allowed left = true ∧
            termCallsSatisfy allowed right = true := by
          simpa only [termCallsSatisfy, Bool.and_eq_true] using supported
        have rightEq : ∀ nextWorld,
            Term.evaluate (machine program first) nextWorld environment right =
              Term.evaluate (machine program second) nextWorld environment
                right := fun nextWorld =>
          term_evaluate_eq_of_callsSatisfy agreement right components.2
        simp only [Term.evaluate]
        rw [term_evaluate_eq_of_callsSatisfy agreement left components.1]
        apply bind_congr
        intro result
        obtain ⟨value, nextWorld⟩ := result
        cases value <;> try rfl
        case boolean value =>
          cases value
          · rfl
          · exact rightEq nextWorld
    | logicalOr left right =>
        have components : termCallsSatisfy allowed left = true ∧
            termCallsSatisfy allowed right = true := by
          simpa only [termCallsSatisfy, Bool.and_eq_true] using supported
        have rightEq : ∀ nextWorld,
            Term.evaluate (machine program first) nextWorld environment right =
              Term.evaluate (machine program second) nextWorld environment
                right := fun nextWorld =>
          term_evaluate_eq_of_callsSatisfy agreement right components.2
        simp only [Term.evaluate]
        rw [term_evaluate_eq_of_callsSatisfy agreement left components.1]
        apply bind_congr
        intro result
        obtain ⟨value, nextWorld⟩ := result
        cases value <;> try rfl
        case boolean value =>
          cases value
          · exact rightEq nextWorld
          · rfl

  theorem terms_evaluate_eq_of_callsSatisfy
      (agreement : first.AgreesWhere allowed second)
      (terms : List (Term Core.signature arity))
      (supported : termsCallsSatisfy allowed terms = true) :
      evaluateTerms (machine program first) world environment terms =
        evaluateTerms (machine program second) world environment terms := by
    cases terms with
    | nil => rfl
    | cons term terms =>
        have components : termCallsSatisfy allowed term = true ∧
            termsCallsSatisfy allowed terms = true := by
          simpa only [termsCallsSatisfy, Bool.and_eq_true] using supported
        have tailEq : ∀ nextWorld,
            evaluateTerms (machine program first) nextWorld environment terms =
              evaluateTerms (machine program second) nextWorld environment
                terms := fun nextWorld =>
          terms_evaluate_eq_of_callsSatisfy agreement terms components.2
        simp only [evaluateTerms]
        rw [term_evaluate_eq_of_callsSatisfy agreement term components.1]
        apply bind_congr
        intro result
        obtain ⟨value, nextWorld⟩ := result
        rw [tailEq nextWorld]
        rfl
end

namespace Term

theorem evaluate_eq_of_callsSatisfy
    (agreement : first.AgreesWhere allowed second)
    (term : Term Core.signature arity)
    (supported : termCallsSatisfy allowed term = true) :
    Term.evaluate (machine program first) world environment term =
      Term.evaluate (machine program second) world environment term :=
  term_evaluate_eq_of_callsSatisfy agreement term supported

end Term

end Lanius.FunctionalView.Core.Effectful
