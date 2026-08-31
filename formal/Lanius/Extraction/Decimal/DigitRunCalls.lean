import Lanius.Extraction.Decimal.DigitRunEvaluation
import Lanius.Extraction.Decimal.Dependencies
import Lanius.FunctionalViewCoreFreshSimulation
import Lanius.FunctionalViewCoreCallFrame

namespace Lanius.Extraction.Decimal.DigitRunCalls

open Lanius
open Lanius.Core
open Lanius.Semantics
open Lanius.Properties
open Lanius.Separation
open Lanius.CallContracts
open Lanius.Compiler.Lexer
open Lanius.Compiler.Lexer.Program
open Lanius.Extraction
open Lanius.FunctionalView
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.Stateful
open Lanius.FunctionalView.Core.EffectfulStateful
open Lanius.Extraction.Decimal
open Lanius.Extraction.Decimal.Dependencies
open Lanius.Extraction.Decimal.DigitRunModel

private theorem helper_success
    (evaluated : helperCallModel.evaluate world function values =
      .ok (result, afterWorld)) :
    (∃ byte base : Int,
      function = extractedIsDigitForBaseFunction.id ∧
      values = [.signed .i32 byte, .signed .i32 base] ∧
      0 ≤ byte ∧ byte ≤ 255 ∧ 0 ≤ base ∧ base ≤ 2147483647 ∧
      result = .boolean (isDigitInt byte base) ∧ afterWorld = world) ∨
    (∃ offset : Int,
      function = extractedSuccessfulDigitsFunction.id ∧
      values = [.signed .i32 offset] ∧
      0 ≤ offset ∧ offset ≤ 2147483647 ∧
      result = digitValue (.success offset.toNat) ∧
      afterWorld = world) ∨
    (∃ offset : Int,
      function = extractedFailedDigitsFunction.id ∧
      values = [.signed .i32 offset] ∧
      0 ≤ offset ∧ offset ≤ 2147483647 ∧
      result = digitValue (.failure offset.toNat) ∧
      afterWorld = world) := by
  simp only [helperCallModel] at evaluated
  split at evaluated
  next first =>
    split at evaluated
    next byte base =>
      split at evaluated
      next valid =>
        obtain ⟨rfl, rfl⟩ := evaluated
        exact .inl ⟨byte, base, first, rfl, valid.1, valid.2.1,
          valid.2.2.1, valid.2.2.2, rfl, rfl⟩
      next => contradiction
    next => contradiction
  next notFirst =>
    split at evaluated
    next second =>
      split at evaluated
      next offset =>
        split at evaluated
        next valid =>
          obtain ⟨rfl, rfl⟩ := evaluated
          exact .inr (.inl ⟨offset, second, rfl, valid.1, valid.2,
            by simp [digitValue, digitScanValue,
              show digitScanDeclaration.id = 2 by rfl],
            rfl⟩)
        next => contradiction
      next => contradiction
    next notSecond =>
      split at evaluated
      next third =>
        split at evaluated
        next offset =>
          split at evaluated
          next valid =>
            obtain ⟨rfl, rfl⟩ := evaluated
            exact .inr (.inr ⟨offset, third, rfl, valid.1, valid.2,
              by simp [digitValue, digitScanValue,
                show digitScanDeclaration.id = 2 by rfl],
              rfl⟩)
          next => contradiction
        next => contradiction
      next => contradiction

private theorem closeUnchangedCallee
    {arity : Nat} {layout : Layout arity}
    {localCell : Fin arity → CellId} {world : ReadOnly.World}
    {environment : Env arity} {caller callee : State}
    (represented : Representation layout localCell world environment caller)
    (callerWellFormed : StateWellFormed caller)
    (calleeWellFormed : StateWellFormed callee)
    (calleeEq : callee = enterCall caller bindings) :
    let after := restoreLocals caller callee
    StateWellFormed after ∧
      Representation layout localCell world environment after ∧
      ModifiesOnly CellSet.empty caller after := by
  subst callee
  exact represented.restoreFreshCall callerWellFormed
    (enterCall_preserves_wellFormed callerWellFormed)
    (ModifiesOnly.refl _) (by
      intro cell member
      simpa [CellSet.empty] using member)

theorem helperFramePreservingCallSoundness :
    FreshSimulation.FramePreservingCallSoundness verifiedFrontendCore helperCallModel := by
  constructor
  intro arity layout localCell beforeWorld afterWorld environment before
    afterArguments function arguments values result argumentWrites
    afterArgumentsWellFormed represented argumentsExecution argumentsEffect
    evaluated
  rcases helper_success evaluated with digit | successful | failed
  · obtain ⟨byte, base, rfl, rfl, byteNonnegative, byteBound,
        baseNonnegative, baseBound, rfl, rfl⟩ := digit
    let byteValue : Byte := ⟨byte.toNat, by omega⟩
    let baseValue : Nat := base.toNat
    have byteEq : (byteValue.val : Int) = byte := by
      simp [byteValue]
      omega
    have baseEq : (baseValue : Int) = base := by
      simp [baseValue]
      omega
    have bodyExecution := Dependencies.isDigitForBaseBody_executes
      afterArguments afterArgumentsWellFormed byteValue baseValue
    have calleeEq : twoI32CalleeState afterArguments byteValue.val baseValue =
        enterCall afterArguments
          [(0, .signed .i32 byte), (1, .signed .i32 base)] := by
      simp [twoI32CalleeState, enterCall, clearLocals, byteEq, baseEq]
    have callExecution : Evaluates verifiedFrontendCore before
        (.call extractedIsDigitForBaseFunction.id
          (toCoreExprs layout arguments))
        (.boolean (isDigitInt byte base))
        (restoreLocals afterArguments
          (twoI32CalleeState afterArguments byteValue.val baseValue)) := by
      apply evaluatesCallReturned
        (bindings := [(0, .signed .i32 byte), (1, .signed .i32 base)])
        (body := Lanius.Extraction.Lexer.Digits.isDigitForBaseBody)
        argumentsExecution verifiedFrontendCore_finds_isDigitForBase
        (by rfl) (by rfl)
      rw [← calleeEq]
      have resultEq : isDigitInt byte base =
          isDigitForBase byteValue baseValue := by
        rw [← byteEq, ← baseEq]
        exact isDigitInt_of_byte byteValue baseValue
      simpa [resultEq] using bodyExecution
    have calleeWellFormed : StateWellFormed
        (twoI32CalleeState afterArguments byteValue.val baseValue) := by
      rw [calleeEq]
      exact enterCall_preserves_wellFormed afterArgumentsWellFormed
    obtain ⟨afterWellFormed, afterRepresented, callEffect⟩ :=
      closeUnchangedCallee represented afterArgumentsWellFormed
        calleeWellFormed calleeEq
    exact ⟨_, callExecution, afterWellFormed, afterRepresented,
      argumentsEffect.trans_same
        (callEffect.weaken CellSet.empty_subset)⟩
  · obtain ⟨offset, rfl, rfl, offsetNonnegative, offsetBound,
        rfl, rfl⟩ := successful
    let offsetValue := offset.toNat
    have offsetEq : (offsetValue : Int) = offset := by
      simp [offsetValue]
      omega
    have bodyExecution := Dependencies.successfulDigitsBody_executes
      afterArguments afterArgumentsWellFormed offsetValue
    have calleeEq : singleArgumentCalleeState afterArguments
        (.signed .i32 offsetValue) =
        enterCall afterArguments [(0, .signed .i32 offset)] := by
      simp [singleArgumentCalleeState, enterCall, clearLocals,
        State.bindLocals, offsetEq]
    have callExecution : Evaluates verifiedFrontendCore before
        (.call extractedSuccessfulDigitsFunction.id
          (toCoreExprs layout arguments))
        (digitValue (.success offsetValue))
        (restoreLocals afterArguments
          (singleArgumentCalleeState afterArguments (.signed .i32 offsetValue))) := by
      apply evaluatesCallReturned
        (bindings := [(0, .signed .i32 offset)])
        (body := Lanius.Extraction.Lexer.Digits.successfulDigitsBody)
        argumentsExecution verifiedFrontendCore_finds_successfulDigits
        (by rfl) (by rfl)
      rw [← calleeEq]
      exact bodyExecution
    have calleeWellFormed : StateWellFormed
        (singleArgumentCalleeState afterArguments (.signed .i32 offsetValue)) := by
      rw [calleeEq]
      exact enterCall_preserves_wellFormed afterArgumentsWellFormed
    obtain ⟨afterWellFormed, afterRepresented, callEffect⟩ :=
      closeUnchangedCallee represented afterArgumentsWellFormed
        calleeWellFormed calleeEq
    exact ⟨_, callExecution, afterWellFormed, afterRepresented,
      argumentsEffect.trans_same
        (callEffect.weaken CellSet.empty_subset)⟩
  · obtain ⟨offset, rfl, rfl, offsetNonnegative, offsetBound,
        rfl, rfl⟩ := failed
    let offsetValue := offset.toNat
    have offsetEq : (offsetValue : Int) = offset := by
      simp [offsetValue]
      omega
    have bodyExecution := Dependencies.failedDigitsBody_executes
      afterArguments afterArgumentsWellFormed offsetValue
    have calleeEq : singleArgumentCalleeState afterArguments
        (.signed .i32 offsetValue) =
        enterCall afterArguments [(0, .signed .i32 offset)] := by
      simp [singleArgumentCalleeState, enterCall, clearLocals,
        State.bindLocals, offsetEq]
    have callExecution : Evaluates verifiedFrontendCore before
        (.call extractedFailedDigitsFunction.id
          (toCoreExprs layout arguments))
        (digitValue (.failure offsetValue))
        (restoreLocals afterArguments
          (singleArgumentCalleeState afterArguments (.signed .i32 offsetValue))) := by
      apply evaluatesCallReturned
        (bindings := [(0, .signed .i32 offset)])
        (body := Lanius.Extraction.Lexer.Digits.failedDigitsBody)
        argumentsExecution verifiedFrontendCore_finds_failedDigits
        (by rfl) (by rfl)
      rw [← calleeEq]
      exact bodyExecution
    have calleeWellFormed : StateWellFormed
        (singleArgumentCalleeState afterArguments (.signed .i32 offsetValue)) := by
      rw [calleeEq]
      exact enterCall_preserves_wellFormed afterArgumentsWellFormed
    obtain ⟨afterWellFormed, afterRepresented, callEffect⟩ :=
      closeUnchangedCallee represented afterArgumentsWellFormed
        calleeWellFormed calleeEq
    exact ⟨_, callExecution, afterWellFormed, afterRepresented,
      argumentsEffect.trans_same
        (callEffect.weaken CellSet.empty_subset)⟩

theorem helperWorldPreserving : FreshSimulation.WorldPreserving helperCallModel := by
  intro beforeWorld afterWorld function values value evaluated
  rcases helper_success evaluated with digit | successful | failed
  · obtain ⟨byte, base, functionEq, valuesEq, byteNonnegative, byteBound,
        baseNonnegative, baseBound, resultEq, afterEq⟩ := digit
    exact afterEq
  · obtain ⟨offset, functionEq, valuesEq, offsetNonnegative, offsetBound,
        resultEq, afterEq⟩ := successful
    exact afterEq
  · obtain ⟨offset, functionEq, valuesEq, offsetNonnegative, offsetBound,
        resultEq, afterEq⟩ := failed
    exact afterEq

end Lanius.Extraction.Decimal.DigitRunCalls
