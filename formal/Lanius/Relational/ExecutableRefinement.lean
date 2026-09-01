import Lanius.Relational.Semantics
import Lanius.Relational.OperationRegistry
import Lanius.FunctionalViewCoreEffectfulStateful

namespace Lanius.Relational.ExecutableRefinement

open Lanius
open Lanius.Core
open Lanius.FunctionalView
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.Effectful
open Lanius.FunctionalView.Core.Stateful
open Lanius.Relational.Semantics

/-! # Isolated executable-to-relational migration adapter

This module is deliberately one-way.  It lets an existing executable
FunctionalView proof discharge the new relational semantics while callees are
migrated.  Algorithm proofs should depend on the relational result, not on
this adapter or on a `CallModel`.
-/

/-- Pointwise evidence that successful executable primitive operations are
allowed by a relational registry. -/
structure OperationsAgree (program : Program) (calls : CallModel)
    (registry : OperationRegistry) : Prop where
  operation : ∀ {world operation arguments value afterWorld},
    Effectful.evaluateOperation program calls world operation arguments =
      .ok (value, afterWorld) →
    (registry.machine program).operation world operation arguments value
      afterWorld

/-- Reverse pointwise evidence used for deterministic, call-free leaves.  It
is intentionally separate from `OperationsAgree`: a relational function
contract can admit several post-states and therefore need not have an
executable implementation at all. -/
structure OperationsReflect (program : Program) (calls : CallModel)
    (registry : OperationRegistry) : Prop where
  operation : ∀ {world operation arguments value afterWorld},
    Effectful.operationCallFree operation = true →
    (registry.machine program).operation world operation arguments value
      afterWorld →
    Effectful.evaluateOperation program calls world operation arguments =
      .ok (value, afterWorld)

/-- Pointwise evidence for stateful leaves.  The scanner pilot is action-free,
but keeping the action field here makes the conversion reusable. -/
structure MachinesAgree (program : Program) (calls : CallModel)
    (registry : OperationRegistry) : Prop extends
    OperationsAgree program calls registry where
  localUpdate : ∀ {operation left right result},
    Lanius.Semantics.evalAssignValue program.target operation (some left) right =
      .ok result →
    (registry.machine program).localUpdate operation left right result
  action : ∀ {arity world environment}
      {operation : Stateful.actions.Action arity} {afterWorld},
    (machineWith program (Effectful.evaluateOperation program calls)).evalAction
        world environment operation = .ok afterWorld →
    (registry.machine program).action world environment operation afterWorld

mutual

theorem term
    {world afterWorld : ReadOnly.World}
    (agreement : OperationsAgree program calls registry)
    (evaluated : FunctionalView.Term.evaluate
      (Effectful.machine program calls) world environment expression =
        .ok (value, afterWorld)) :
    TermEvaluates (registry.machine program) world environment expression value
      afterWorld := by
  cases expression with
  | reference reference =>
      simp only [FunctionalView.Term.evaluate] at evaluated
      obtain ⟨rfl, rfl⟩ := Except.ok.inj evaluated
      exact .reference reference
  | apply operation arguments =>
      simp only [FunctionalView.Term.evaluate] at evaluated
      generalize argumentsResult : FunctionalView.evaluateTerms
        (Effectful.machine program calls) world environment arguments = result
        at evaluated
      cases result with
      | error reason => simp_all [bind, Except.bind]
      | ok result =>
          obtain ⟨values, argumentsWorld⟩ := result
          simp only [bind, Except.bind] at evaluated
          exact .apply
            (terms agreement argumentsResult)
            (agreement.operation evaluated)
  | logicalAnd left right =>
      simp only [FunctionalView.Term.evaluate] at evaluated
      generalize leftResult : FunctionalView.Term.evaluate
        (Effectful.machine program calls) world environment left = result
        at evaluated
      cases result with
      | error reason => simp_all [bind, Except.bind]
      | ok result =>
          obtain ⟨leftValue, leftWorld⟩ := result
          cases leftValue with
          | boolean decision =>
            cases decision with
            | false =>
                obtain ⟨rfl, rfl⟩ := Except.ok.inj evaluated
                exact .logicalAndFalse (term agreement leftResult)
            | true =>
                exact .logicalAndTrue (term agreement leftResult)
                  (term agreement evaluated)
          | unit | signed | unsigned | f32Bits | f64Bits | character | string |
              pointer | array | slice | «structure» | enumeration | reference =>
              simp_all [bind, Except.bind]
  | logicalOr left right =>
      simp only [FunctionalView.Term.evaluate] at evaluated
      generalize leftResult : FunctionalView.Term.evaluate
        (Effectful.machine program calls) world environment left = result
        at evaluated
      cases result with
      | error reason => simp_all [bind, Except.bind]
      | ok result =>
          obtain ⟨leftValue, leftWorld⟩ := result
          cases leftValue with
          | boolean decision =>
            cases decision with
            | false =>
                exact .logicalOrFalse (term agreement leftResult)
                  (term agreement evaluated)
            | true =>
                obtain ⟨rfl, rfl⟩ := Except.ok.inj evaluated
                exact .logicalOrTrue (term agreement leftResult)
          | unit | signed | unsigned | f32Bits | f64Bits | character | string |
              pointer | array | slice | «structure» | enumeration | reference =>
              simp_all [bind, Except.bind]

theorem terms
    {world afterWorld : ReadOnly.World}
    (agreement : OperationsAgree program calls registry)
    (evaluated : FunctionalView.evaluateTerms
      (Effectful.machine program calls) world environment expressions =
        .ok (values, afterWorld)) :
    TermsEvaluate (registry.machine program) world environment expressions values
      afterWorld := by
  cases expressions with
  | nil =>
      simp only [FunctionalView.evaluateTerms] at evaluated
      obtain ⟨rfl, rfl⟩ := Except.ok.inj evaluated
      exact .nil
  | cons head tail =>
      simp only [FunctionalView.evaluateTerms] at evaluated
      generalize headResult : FunctionalView.Term.evaluate
        (Effectful.machine program calls) world environment head = result
        at evaluated
      cases result with
      | error reason => simp_all [bind, Except.bind]
      | ok result =>
          obtain ⟨headValue, headWorld⟩ := result
          generalize tailResult : FunctionalView.evaluateTerms
            (Effectful.machine program calls) headWorld environment tail = result
            at evaluated
          cases result with
          | error reason => simp_all [bind, Except.bind]
          | ok result =>
              obtain ⟨tailValues, tailWorld⟩ := result
              simp only [tailResult, bind, Except.bind] at evaluated
              obtain ⟨rfl, rfl⟩ := Except.ok.inj evaluated
              exact .cons (term agreement headResult)
                (terms agreement tailResult)

end

mutual

/-- Reconstruct executable evaluation from a relational derivation when every
primitive leaf has a unique executable interpretation.  This is used only for
small call-free leaves; relational caller proofs do not require it. -/
theorem termToExecutable
    {world afterWorld : ReadOnly.World}
    (reflection : OperationsReflect program calls registry)
    (free : Effectful.termCallFree expression = true)
    (evaluated : TermEvaluates (registry.machine program) world environment
      expression value afterWorld) :
    FunctionalView.Term.evaluate (Effectful.machine program calls)
      world environment expression = .ok (value, afterWorld) := by
  cases expression with
  | reference reference =>
      obtain ⟨rfl, rfl⟩ := TermEvaluates.referenceInversion evaluated
      rfl
  | apply operation arguments =>
      have components : Effectful.operationCallFree operation = true ∧
          Effectful.termsCallFree arguments = true := by
        simpa only [Effectful.termCallFree, Bool.and_eq_true] using free
      obtain ⟨values, afterArguments, argumentsResult, operationResult⟩ :=
        TermEvaluates.applyInversion evaluated
      simp only [FunctionalView.Term.evaluate]
      rw [termsToExecutable reflection components.2 argumentsResult]
      exact reflection.operation components.1 operationResult
  | logicalAnd left right =>
      have components : Effectful.termCallFree left = true ∧
          Effectful.termCallFree right = true := by
        simpa only [Effectful.termCallFree, Bool.and_eq_true] using free
      rcases TermEvaluates.logicalAndInversion evaluated with
        ⟨rfl, leftResult⟩ | ⟨afterLeft, leftResult, rightResult⟩
      · simp only [FunctionalView.Term.evaluate]
        rw [termToExecutable reflection components.1 leftResult]
        rfl
      · simp only [FunctionalView.Term.evaluate]
        rw [termToExecutable reflection components.1 leftResult]
        simpa only [bind, Except.bind] using
          termToExecutable reflection components.2 rightResult
  | logicalOr left right =>
      have components : Effectful.termCallFree left = true ∧
          Effectful.termCallFree right = true := by
        simpa only [Effectful.termCallFree, Bool.and_eq_true] using free
      rcases TermEvaluates.logicalOrInversion evaluated with
        ⟨rfl, leftResult⟩ | ⟨afterLeft, leftResult, rightResult⟩
      · simp only [FunctionalView.Term.evaluate]
        rw [termToExecutable reflection components.1 leftResult]
        rfl
      · simp only [FunctionalView.Term.evaluate]
        rw [termToExecutable reflection components.1 leftResult]
        simpa only [bind, Except.bind] using
          termToExecutable reflection components.2 rightResult

theorem termsToExecutable
    {world afterWorld : ReadOnly.World}
    (reflection : OperationsReflect program calls registry)
    (free : Effectful.termsCallFree expressions = true)
    (evaluated : TermsEvaluate (registry.machine program) world environment
      expressions values afterWorld) :
    FunctionalView.evaluateTerms (Effectful.machine program calls)
      world environment expressions = .ok (values, afterWorld) := by
  cases expressions with
  | nil =>
      obtain ⟨rfl, rfl⟩ := TermsEvaluate.nilInversion evaluated
      rfl
  | cons head tail =>
      have components : Effectful.termCallFree head = true ∧
          Effectful.termsCallFree tail = true := by
        simpa only [Effectful.termsCallFree, Bool.and_eq_true] using free
      obtain ⟨value, tailValues, afterHead, rfl, headResult, tailResult⟩ :=
        TermsEvaluate.consInversion evaluated
      change ReadOnly.World at afterHead
      exact FunctionalView.evaluateTerms_cons
        (termToExecutable reflection components.1 headResult)
        (termsToExecutable reflection components.2 tailResult)

end

/-- Every finite successful executable command derivation is also a
relational derivation when its primitive leaves agree pointwise. -/
def command
    (agreement : MachinesAgree program calls registry) :
    ∀ {arity} {world afterWorld : ReadOnly.World}
      {environment : Env arity}
      {statement : Stateful.Command Core.signature Stateful.actions arity}
      {completion} {afterEnvironment},
    Stateful.Command.Evaluates
      (Effectful.machine program calls)
      (machineWith program (Effectful.evaluateOperation program calls))
      world environment statement completion afterWorld afterEnvironment →
    Stateful.CommandEvaluates (registry.machine program) world environment
      statement completion afterWorld afterEnvironment
  | _, _, _, _, _, _, _, .skip => .skip
  | _, _, _, _, _, _, _, .sequenceNext firstResult secondResult =>
      .sequenceNext (command agreement firstResult)
        (command agreement secondResult)
  | _, _, _, _, _, _, _, .sequenceStop firstResult stops =>
      .sequenceStop (command agreement firstResult) stops
  | _, _, _, _, _, _, _, .letValue initializerResult bodyResult =>
      .letValue (term agreement.toOperationsAgree initializerResult)
        (command agreement bodyResult)
  | _, _, _, _, _, _, _, .setLocal valueResult =>
      .setLocal (term agreement.toOperationsAgree valueResult)
  | _, _, _, _, _, _, _, .updateLocal valueResult updateResult =>
      .updateLocal (term agreement.toOperationsAgree valueResult)
        (agreement.localUpdate updateResult)
  | _, _, _, _, _, _, _, .action actionResult =>
      .action (agreement.action actionResult)
  | _, _, _, _, _, _, _, .ifTrue conditionResult branchResult =>
      .ifTrue (term agreement.toOperationsAgree conditionResult)
        (command agreement branchResult)
  | _, _, _, _, _, _, _, .ifFalse conditionResult branchResult =>
      .ifFalse (term agreement.toOperationsAgree conditionResult)
        (command agreement branchResult)
  | _, _, _, _, _, _, _, .whileFalse conditionResult =>
      .whileFalse (term agreement.toOperationsAgree conditionResult)
  | _, _, _, _, _, _, _, .whileNext conditionResult bodyResult restResult =>
      .whileNext (term agreement.toOperationsAgree conditionResult)
        (command agreement bodyResult) (command agreement restResult)
  | _, _, _, _, _, _, _, .whileContinue conditionResult bodyResult restResult =>
      .whileContinue (term agreement.toOperationsAgree conditionResult)
        (command agreement bodyResult) (command agreement restResult)
  | _, _, _, _, _, _, _, .whileBreak conditionResult bodyResult =>
      .whileBreak (term agreement.toOperationsAgree conditionResult)
        (command agreement bodyResult)
  | _, _, _, _, _, _, _, .whileReturn conditionResult bodyResult =>
      .whileReturn (term agreement.toOperationsAgree conditionResult)
        (command agreement bodyResult)
  | _, _, _, _, _, _, _, .returnNone => .returnNone
  | _, _, _, _, _, _, _, .returnSome valueResult =>
      .returnSome (term agreement.toOperationsAgree valueResult)
  | _, _, _, _, _, _, _, .breakLoop => .breakLoop
  | _, _, _, _, _, _, _, .continueLoop => .continueLoop

end Lanius.Relational.ExecutableRefinement
