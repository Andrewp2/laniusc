import Lanius.Relational.CheckedProgram
import Lanius.Fuel
import Lanius.CallContracts

namespace Lanius.Relational

open Lanius
open Lanius.Core
open Lanius.Semantics
open Lanius.Separation
open Lanius.CallContracts

/-! # Successful checked-call inversion

Core's public call rule constructs a call evaluation from argument and body
evaluations.  Relational partial correctness needs the converse: an actual
successful call must have evaluated its arguments, selected the checked body,
bound the parameters, and returned a value from that body.  This theorem is
the generic evaluator boundary; algorithm proofs should never unfold the
fuelled call evaluator themselves.
-/

theorem argumentsEvaluateTo_deterministic
    (left : ArgumentsEvaluateTo program state arguments leftValues leftState)
    (right : ArgumentsEvaluateTo program state arguments rightValues rightState) :
    leftValues = rightValues ∧ leftState = rightState := by
  obtain ⟨leftFuel, leftResult⟩ := left
  obtain ⟨rightFuel, rightResult⟩ := right
  let common := max leftFuel rightFuel
  have leftCommon : evalExprs common program state arguments =
      .done leftValues leftState :=
    Lanius.Fuel.evalExprs_done_at_larger_fuel
      (Nat.le_max_left _ _) leftResult
  have rightCommon : evalExprs common program state arguments =
      .done rightValues rightState :=
    Lanius.Fuel.evalExprs_done_at_larger_fuel
      (Nat.le_max_right _ _) rightResult
  have same := leftCommon.symm.trans rightCommon
  injection same with valuesEq stateEq
  exact ⟨valuesEq, stateEq⟩

theorem evaluatesCallReturned_invert
    {program : Program} {before actualAfter : State}
    {function : Function} {arguments : List Expr}
    {body : Stmt} {actualValue : Value}
    (functionFound : program.function? function.id = some function)
    (functionBody : function.body = some body)
    (returnsValue : function.returnType ≠ .unit)
    (actualExecution : Evaluates program before
      (.call function.id arguments) actualValue actualAfter) :
    ∃ values afterArguments bindings completed,
      ArgumentsEvaluateTo program before arguments values afterArguments ∧
      bindParameters function.parameters values = some bindings ∧
      Executes program (enterCall afterArguments bindings) body
        (.returned (some actualValue)) completed ∧
      actualAfter = restoreLocals afterArguments completed := by
  obtain ⟨fuel, evaluated⟩ := actualExecution
  cases fuel with
  | zero => simp [Lanius.Semantics.evalExpr] at evaluated
  | succ fuel =>
      rw [Lanius.Semantics.evalExpr.eq_def] at evaluated
      simp only at evaluated
      generalize argumentsResult : evalExprs fuel program before arguments =
        argumentOutcome at evaluated
      cases argumentOutcome with
      | outOfFuel => simp at evaluated
      | trapped reason state => simp at evaluated
      | exited code state => simp at evaluated
      | done values afterArguments =>
          simp only [functionFound] at evaluated
          rw [functionBody] at evaluated
          generalize bindingResult : bindParameters function.parameters values =
            binding at evaluated
          cases binding with
          | none => simp at evaluated
          | some bindings =>
              simp only at evaluated
              generalize bodyResult : execStmt fuel program
                (({ afterArguments with locals := [] }).bindLocals bindings)
                body = bodyOutcome at evaluated
              cases bodyOutcome with
              | outOfFuel => simp at evaluated
              | trapped reason state => simp at evaluated
              | exited code state => simp at evaluated
              | done completion completed =>
                  cases completion with
                  | next =>
                      simp [returnsValue] at evaluated
                  | breakLoop => simp at evaluated
                  | continueLoop => simp at evaluated
                  | returned value =>
                      cases value with
                      | none =>
                          simp [returnsValue] at evaluated
                      | some returned =>
                          obtain ⟨rfl, rfl⟩ := Outcome.done.inj evaluated
                          refine ⟨values, afterArguments, bindings, completed,
                            ⟨fuel, argumentsResult⟩, bindingResult, ?_, rfl⟩
                          exact ⟨fuel, by simpa [enterCall] using bodyResult⟩

end Lanius.Relational
