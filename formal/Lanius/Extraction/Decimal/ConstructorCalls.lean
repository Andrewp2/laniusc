import Lanius.Extraction.Decimal.BaseCalls
import Lanius.Extraction.Decimal.Constructors

namespace Lanius.Extraction.Decimal.ConstructorCalls

open Lanius
open Lanius.Core
open Lanius.Semantics
open Lanius.Properties
open Lanius.Separation
open Lanius.CallContracts
open Lanius.Compiler.Lexer.Program
open Lanius.Extraction
open Lanius.FunctionalView
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.Effectful
open Lanius.FunctionalView.Core.Stateful
open Lanius.FunctionalView.FreshSimulation
open Lanius.Extraction.Decimal

def modelFor (function : FunctionId) (resultFor : Nat → Value) : CallModel where
  evaluate := fun world candidate values =>
    if candidate = function then
      match values with
      | [.signed .i32 offset] =>
          if 0 ≤ offset ∧ offset ≤ 2147483647 then
            .ok (resultFor offset.toNat, world)
          else .error .typeMismatch
      | _ => .error .typeMismatch
    else .error .invalidPointer

def integerScanCalls : CallModel := modelFor Functions.integerScanFunction.id
  (fun offset => Lanius.Extraction.TokenScan.Semantics.value true 2 offset 0)

def floatScanCalls : CallModel := modelFor Functions.floatScanFunction.id
  (fun offset => Lanius.Extraction.TokenScan.Semantics.value true 33 offset 0)

def numberFailureCalls : CallModel := modelFor Functions.numberFailureFunction.id
  (fun offset => Lanius.Extraction.TokenScan.Semantics.value false 0 0 offset)

def callModel : CallModel :=
  CallModel.route (fun function => function = Functions.integerScanFunction.id)
    integerScanCalls
    (CallModel.route (fun function => function = Functions.floatScanFunction.id)
      floatScanCalls numberFailureCalls)

private theorem modelFor_success
    (evaluated : (modelFor expected resultFor).evaluate world function values =
      .ok (result, afterWorld)) :
    ∃ offset : Nat,
      function = expected ∧ values = [.signed .i32 offset] ∧
      offset ≤ 2147483647 ∧ result = resultFor offset ∧
      afterWorld = world := by
  simp only [modelFor] at evaluated
  split at evaluated
  next functionEq =>
    split at evaluated
    next offset =>
      split at evaluated
      next valid =>
        obtain ⟨rfl, rfl⟩ := evaluated
        let offsetNat := offset.toNat
        have offsetEq : (offsetNat : Int) = offset := by
          simp [offsetNat]
          omega
        exact ⟨offsetNat, functionEq, by simp [offsetEq], by omega,
          by simp [offsetNat, offsetEq], rfl⟩
      next => contradiction
    next => contradiction
  next => contradiction

private theorem frameExtension_modifiesOnly
    (extension : FrameExtension before after)
    (wellFormed : StateWellFormed before) :
    ModifiesOnly CellSet.empty before after := {
  oldCells := fun cell old _ => extension.oldCells cell old
  nextCell := extension.nextCell
  heap := extension.heap
  world := extension.world
  views := extension.views
  domain := by
    constructor
    intro entry member
    have old := wellFormed.cellIdsBelowNext entry member
    have foundBefore := stateWellFormed_cellEntry_of_mem wellFormed member
    have foundAfter : after.cellEntry? entry.id = some entry := by
      rw [extension.oldCells entry.id old, foundBefore]
    exact ⟨entry, List.mem_of_find?_eq_some foundAfter, rfl⟩
  locals := extension.locals }

private theorem soundnessFor
    (function : Function) (body : Stmt) (resultFor : Nat → Value)
    (found : verifiedFrontendCore.function? function.id = some function)
    (parameters : function.parameters = [(0, i32Type)])
    (hasBody : function.body = some body)
    (completed : State → Nat → State)
    (bodyExecutes : ∀ state, StateWellFormed state → ∀ (offset : Nat),
      Executes verifiedFrontendCore
        (singleArgumentCalleeState state (.signed .i32 offset)) body
        (.returned (some (resultFor offset)))
        (completed (singleArgumentCalleeState state (.signed .i32 offset))
          offset))
    (bodyFrame : ∀ state, StateWellFormed state → ∀ (offset : Nat),
      FrameExtension
        (singleArgumentCalleeState state (.signed .i32 offset))
        (completed (singleArgumentCalleeState state (.signed .i32 offset))
          offset))
    (bodyWellFormed : ∀ state, StateWellFormed state → ∀ (offset : Nat),
      StateWellFormed
        (completed (singleArgumentCalleeState state (.signed .i32 offset))
          offset)) :
    FramePreservingCallSoundness verifiedFrontendCore
      (modelFor function.id resultFor) := by
  constructor
  intro arity layout localCell beforeWorld afterWorld environment before
    afterArguments called arguments values value argumentWrites
    afterArgumentsWellFormed represented argumentsExecution argumentsEffect
    evaluated
  obtain ⟨offset, rfl, rfl, offsetBound, rfl, rfl⟩ :=
    modelFor_success evaluated
  let bindings : List (VarId × Value) := [(0, .signed .i32 offset)]
  let callee := enterCall afterArguments bindings
  let completedState := completed callee offset
  let after := restoreLocals afterArguments completedState
  have calleeEq : singleArgumentCalleeState afterArguments
      (.signed .i32 offset) = callee := by
    simp [callee, bindings, singleArgumentCalleeState, enterCall, clearLocals,
      State.bindLocals]
  have calleeWellFormed : StateWellFormed callee := by
    simpa [callee, bindings] using
      (enterCall_preserves_wellFormed (bindings := bindings)
        afterArgumentsWellFormed)
  have bodyExecution : Executes verifiedFrontendCore callee body
      (.returned (some (resultFor offset))) completedState := by
    rw [← calleeEq]
    simpa [completedState, calleeEq] using
      bodyExecutes afterArguments afterArgumentsWellFormed offset
  have callExecution : Evaluates verifiedFrontendCore before
      (.call function.id (toCoreExprs layout arguments)) (resultFor offset)
      after := by
    apply evaluatesCallReturned argumentsExecution found
    · rw [parameters]
      rfl
    · exact hasBody
    · simpa [after, completedState] using bodyExecution
  have completedWellFormed : StateWellFormed completedState := by
    dsimp only [completedState]
    rw [← calleeEq]
    simpa [calleeEq] using
      bodyWellFormed afterArguments afterArgumentsWellFormed offset
  have bodyEffect : ModifiesOnly CellSet.empty callee completedState :=
    frameExtension_modifiesOnly
      (by
        rw [← calleeEq]
        simpa [completedState, calleeEq] using
          bodyFrame afterArguments afterArgumentsWellFormed offset)
      calleeWellFormed
  obtain ⟨afterWellFormed, afterRepresented, callEffect⟩ :=
    represented.restoreFreshCall afterArgumentsWellFormed completedWellFormed
      (bindings := bindings) bodyEffect (by simp [CellSet.empty])
  exact ⟨after, callExecution, afterWellFormed, afterRepresented,
    argumentsEffect.trans_same
      (callEffect.weaken CellSet.empty_subset)⟩

theorem integerScanFramePreserving : FramePreservingCallSoundness
    verifiedFrontendCore integerScanCalls := by
  apply soundnessFor Functions.integerScanFunction Functions.integerScanBody
    (fun offset => Lanius.Extraction.TokenScan.Semantics.value true 2 offset 0)
    Constructors.verifiedFrontendCore_finds_integerScan (by rfl) (by rfl)
    (fun state offset => twoI32CallState state 2 offset)
  · exact Constructors.integerScanBody_executes
  · intro state wellFormed offset
    exact twoI32CallState_extends _ _ _
  · intro state wellFormed offset
    exact twoI32CallState_well_formed _
      (singleArgumentCalleeState_well_formed _ wellFormed _) _ _

theorem floatScanFramePreserving : FramePreservingCallSoundness
    verifiedFrontendCore floatScanCalls := by
  apply soundnessFor Functions.floatScanFunction Functions.floatScanBody
    (fun offset => Lanius.Extraction.TokenScan.Semantics.value true 33 offset 0)
    Constructors.verifiedFrontendCore_finds_floatScan (by rfl) (by rfl)
    (fun state offset => twoI32CallState state 33 offset)
  · exact Constructors.floatScanBody_executes
  · intro state wellFormed offset
    exact twoI32CallState_extends _ _ _
  · intro state wellFormed offset
    exact twoI32CallState_well_formed _
      (singleArgumentCalleeState_well_formed _ wellFormed _) _ _

theorem numberFailureFramePreserving : FramePreservingCallSoundness
    verifiedFrontendCore numberFailureCalls := by
  apply soundnessFor Functions.numberFailureFunction Functions.numberFailureBody
    (fun offset => Lanius.Extraction.TokenScan.Semantics.value false 0 0 offset)
    Constructors.verifiedFrontendCore_finds_numberFailure (by rfl) (by rfl)
    (fun state offset => singleArgumentCallState state (.signed .i32 offset))
  · exact Constructors.numberFailureBody_executes
  · intro state wellFormed offset
    exact singleArgumentCallState_extends _ _
  · intro state wellFormed offset
    exact singleArgumentCallState_well_formed _
      (singleArgumentCalleeState_well_formed _ wellFormed _) _

theorem framePreservingCallSoundness :
    FramePreservingCallSoundness verifiedFrontendCore callModel := by
  exact FramePreservingCallSoundness.route integerScanFramePreserving
    (FramePreservingCallSoundness.route floatScanFramePreserving
      numberFailureFramePreserving)

theorem worldPreserving : WorldPreserving callModel := by
  apply WorldPreserving.route
  · intro beforeWorld afterWorld function values value evaluated
    exact (modelFor_success evaluated).choose_spec.2.2.2.2
  apply WorldPreserving.route
  · intro beforeWorld afterWorld function values value evaluated
    exact (modelFor_success evaluated).choose_spec.2.2.2.2
  · intro beforeWorld afterWorld function values value evaluated
    exact (modelFor_success evaluated).choose_spec.2.2.2.2

theorem callSoundness : EffectfulStateful.CallSoundness
    verifiedFrontendCore callModel :=
  framePreservingCallSoundness.toCallSoundness worldPreserving

@[simp] theorem integerScan (world : ReadOnly.World) (offset : Nat)
    (bound : offset ≤ 2147483647) :
    callModel.evaluate world Functions.integerScanFunction.id
      [.signed .i32 offset] =
      .ok (Lanius.Extraction.TokenScan.Semantics.value true 2 offset 0, world) := by
  have nonnegative : (0 : Int) ≤ (offset : Int) := by omega
  have intBound : (offset : Int) ≤ 2147483647 := by omega
  simp [callModel, CallModel.route, integerScanCalls, modelFor, bound,
    nonnegative, intBound]

@[simp] theorem floatScan (world : ReadOnly.World) (offset : Nat)
    (bound : offset ≤ 2147483647) :
    callModel.evaluate world Functions.floatScanFunction.id
      [.signed .i32 offset] =
      .ok (Lanius.Extraction.TokenScan.Semantics.value true 33 offset 0, world) := by
  have nonnegative : (0 : Int) ≤ (offset : Int) := by omega
  have intBound : (offset : Int) ≤ 2147483647 := by omega
  have different : Functions.floatScanFunction.id ≠
      Functions.integerScanFunction.id := by native_decide
  simp [callModel, CallModel.route, floatScanCalls, modelFor, bound,
    nonnegative, intBound, different]

@[simp] theorem numberFailure (world : ReadOnly.World) (offset : Nat)
    (bound : offset ≤ 2147483647) :
    callModel.evaluate world Functions.numberFailureFunction.id
      [.signed .i32 offset] =
      .ok (Lanius.Extraction.TokenScan.Semantics.value false 0 0 offset, world) := by
  have nonnegative : (0 : Int) ≤ (offset : Int) := by omega
  have intBound : (offset : Int) ≤ 2147483647 := by omega
  have integerDifferent : Functions.numberFailureFunction.id ≠
      Functions.integerScanFunction.id := by native_decide
  have floatDifferent : Functions.numberFailureFunction.id ≠
      Functions.floatScanFunction.id := by native_decide
  simp [callModel, CallModel.route, numberFailureCalls, modelFor, bound,
    nonnegative, intBound, integerDifferent, floatDifferent]

end Lanius.Extraction.Decimal.ConstructorCalls
