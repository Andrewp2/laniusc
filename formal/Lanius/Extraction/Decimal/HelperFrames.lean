import Lanius.Extraction.Decimal.DigitRunSemantics
import Lanius.Extraction.Lexer.DigitAccessorContracts
import Lanius.Extraction.TokenScan.Semantics
import Lanius.Extraction.FrontendProgramExtensions

namespace Lanius.Extraction.Decimal.HelperFrames

open Lanius
open Lanius.Core
open Lanius.Semantics
open Lanius.Properties
open Lanius.Separation
open Lanius.CallContracts
open Lanius.Extraction
open Lanius.FunctionalView
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.ReadOnly
open Lanius.FunctionalView.Core.Effectful
open Lanius.FunctionalView.Core.Stateful
open Lanius.FunctionalView.FreshSimulation

namespace Accessors

open Lanius.Extraction.Lexer
open Lanius.Extraction.Lexer.DigitAccessorContracts

private theorem accessorExecutes
    (state : State) (fields : List Value) (field : FieldId) (value : Value)
    (resultLocal : state.local? 0 = some (.structure 2 fields))
    (fieldFound : fields[field]? = some value) :
    Executes verifiedFrontendDigitsCore state (accessorBody field)
      (.returned (some value)) state := by
  have localEvaluation : Evaluates verifiedFrontendDigitsCore state (.local 0)
      (.structure 2 fields) state :=
    ⟨1, evalLocal_of_local 1 verifiedFrontendDigitsCore state 0 _ resultLocal⟩
  have fieldEvaluation : Evaluates verifiedFrontendDigitsCore state
      (.field (.local 0) field) value state :=
    evaluatesStructureField localEvaluation fieldFound
  exact executesSequenceReturned (executesReturnValue fieldEvaluation)

private theorem preserveRepresentation
    (afterArgumentsWellFormed : StateWellFormed afterArguments)
    (represented : Representation layout localCell world environment
      afterArguments)
    (effect : ModifiesOnly CellSet.empty afterArguments after) :
    Representation layout localCell world environment after := {
  worldOwned := effect.empty_preserves_assertion afterArgumentsWellFormed
    (World.owns world) represented.worldOwned
  localOwned := fun index => effect.empty_preserves_assertion
    afterArgumentsWellFormed
    (Assertion.localPointsTo (layout index) (localCell index)
      (some (environment index))) (represented.localOwned index)
  localCellsInjective := represented.localCellsInjective
  worldLocalsDisjoint := represented.worldLocalsDisjoint }

private theorem callsFor_success
    (evaluated : (callsFor expectedFunction field).evaluate world function
      values = .ok (value, afterWorld)) :
    ∃ fields,
      function = expectedFunction ∧ values = [.structure 2 fields] ∧
      fields[field]? = some value ∧ afterWorld = world := by
  simp only [callsFor] at evaluated
  split at evaluated
  next functionEq =>
    split at evaluated
    next fields =>
      split at evaluated
      next found =>
        obtain ⟨rfl, rfl⟩ := evaluated
        exact ⟨fields, functionEq, rfl, found, rfl⟩
      next => contradiction
    next => contradiction
  next => contradiction

private theorem soundnessFor
    (function : Function) (body : Stmt) (field : FieldId)
    (foundFunction : verifiedFrontendDigitsCore.function? function.id =
      some function)
    (parameters : function.parameters = [(0, resultType)])
    (functionBody : function.body = some body)
    (bodyShape : body = accessorBody field) :
    FramePreservingCallSoundness verifiedFrontendCore
      (callsFor function.id field) := by
  constructor
  intro arity layout localCell beforeWorld afterWorld environment before
    afterArguments calledFunction arguments values value argumentWrites
    afterArgumentsWellFormed represented argumentsExecution argumentsEffect
    evaluated
  obtain ⟨fields, rfl, rfl, fieldFound, rfl⟩ := callsFor_success evaluated
  let bindings := accessorBindings fields
  let callee := enterCall afterArguments bindings
  let after := restoreLocals afterArguments callee
  have resultLocal : callee.local? 0 = some (.structure 2 fields) := by
    simpa [callee, bindings, accessorBindings] using
      enterCall_local_of_binding afterArguments [] [] 0
        (.structure 2 fields) afterArgumentsWellFormed (by simp)
  have bodySmall : Executes verifiedFrontendDigitsCore callee body
      (.returned (some value)) callee := by
    rw [bodyShape]
    exact accessorExecutes callee fields field value resultLocal fieldFound
  have bodyMerged : Executes verifiedFrontendCore callee body
      (.returned (some value)) callee :=
    verifiedFrontendCore_extends_verifiedFrontendDigitsCore.executes bodySmall
  have callExecution : Evaluates verifiedFrontendCore before
      (.call function.id (toCoreExprs layout arguments)) value after := by
    apply evaluatesCallReturned argumentsExecution
      (verifiedFrontendCore_extends_verifiedFrontendDigitsCore.function
        foundFunction)
    · rw [parameters]
      rfl
    · exact functionBody
    · change Executes verifiedFrontendCore callee body
        (.returned (some value)) callee
      exact bodyMerged
  have entered : StoreEffect CellSet.empty afterArguments callee := by
    simpa [callee, bindings] using enterCall_effect afterArguments bindings
  have callEffect : ModifiesOnly CellSet.empty afterArguments after := by
    simpa [after, callee] using entered.restoreLocals
  have afterWellFormed : StateWellFormed after :=
    entered.restoreLocals_wellFormed afterArgumentsWellFormed
      (by simpa [callee, bindings] using
        (enterCall_preserves_wellFormed (bindings := bindings)
          afterArgumentsWellFormed))
  have afterRepresented := preserveRepresentation
    afterArgumentsWellFormed represented callEffect
  exact ⟨after, callExecution, afterWellFormed, afterRepresented,
    argumentsEffect.trans_same (callEffect.weaken CellSet.empty_subset)⟩

theorem succeeded : FramePreservingCallSoundness verifiedFrontendCore
    digitScanSucceededCalls := by
  exact soundnessFor Digits.digitScanSucceededFunction
    Digits.digitScanSucceededBody 0
    verifiedFrontendDigitsCore_finds_digitScanSucceeded
    digitScanSucceededFunction_parameters digitScanSucceededFunction_body
    digitScanSucceededBody_eq

theorem endOffset : FramePreservingCallSoundness verifiedFrontendCore
    digitScanEndOffsetCalls := by
  exact soundnessFor Digits.digitScanEndOffsetFunction
    Digits.digitScanEndOffsetBody 1
    verifiedFrontendDigitsCore_finds_digitScanEndOffset
    digitScanEndOffsetFunction_parameters digitScanEndOffsetFunction_body
    digitScanEndOffsetBody_eq

theorem errorOffset : FramePreservingCallSoundness verifiedFrontendCore
    digitScanErrorOffsetCalls := by
  exact soundnessFor Digits.digitScanErrorOffsetFunction
    Digits.digitScanErrorOffsetBody 2
    verifiedFrontendDigitsCore_finds_digitScanErrorOffset
    digitScanErrorOffsetFunction_parameters digitScanErrorOffsetFunction_body
    digitScanErrorOffsetBody_eq

theorem worldPreserving (function : FunctionId) (field : FieldId) :
    WorldPreserving (callsFor function field) := by
  intro beforeWorld afterWorld called values value evaluated
  exact (callsFor_success evaluated).choose_spec.2.2.2

end Accessors

namespace TokenConstructors

open Lanius.Extraction.TokenScan.Semantics

private theorem preserveRepresentation
    (afterArgumentsWellFormed : StateWellFormed afterArguments)
    (represented : Representation layout localCell world environment
      afterArguments)
    (effect : ModifiesOnly CellSet.empty afterArguments after) :
    Representation layout localCell world environment after := {
  worldOwned := effect.empty_preserves_assertion afterArgumentsWellFormed
    (World.owns world) represented.worldOwned
  localOwned := fun index => effect.empty_preserves_assertion
    afterArgumentsWellFormed
    (Assertion.localPointsTo (layout index) (localCell index)
      (some (environment index))) (represented.localOwned index)
  localCellsInjective := represented.localCellsInjective
  worldLocalsDisjoint := represented.worldLocalsDisjoint }

theorem successful : FramePreservingCallSoundness verifiedFrontendCore
    successfulCalls := by
  constructor
  intro arity layout localCell beforeWorld afterWorld environment before
    afterArguments function arguments values result argumentWrites
    afterArgumentsWellFormed represented argumentsExecution argumentsEffect
    evaluated
  simp only [successfulCalls] at evaluated
  split at evaluated
  next functionEq =>
    split at evaluated
    next kind endOffset =>
      obtain ⟨rfl, rfl⟩ := evaluated
      subst function
      obtain ⟨callExecution, callEffect, afterWellFormed⟩ :=
        successfulCall_executes before afterArguments
          (toCoreExprs layout arguments) kind endOffset
          afterArgumentsWellFormed argumentsExecution
      exact ⟨_, callExecution, afterWellFormed,
        preserveRepresentation afterArgumentsWellFormed represented callEffect,
        argumentsEffect.trans_same (callEffect.weaken CellSet.empty_subset)⟩
    next => contradiction
  next => contradiction

theorem failed : FramePreservingCallSoundness verifiedFrontendCore
    failedCalls := by
  constructor
  intro arity layout localCell beforeWorld afterWorld environment before
    afterArguments function arguments values result argumentWrites
    afterArgumentsWellFormed represented argumentsExecution argumentsEffect
    evaluated
  simp only [failedCalls] at evaluated
  split at evaluated
  next functionEq =>
    split at evaluated
    next errorOffset =>
      obtain ⟨rfl, rfl⟩ := evaluated
      subst function
      obtain ⟨callExecution, callEffect, afterWellFormed⟩ :=
        failedCall_executes before afterArguments
          (toCoreExprs layout arguments) errorOffset
          afterArgumentsWellFormed argumentsExecution
      exact ⟨_, callExecution, afterWellFormed,
        preserveRepresentation afterArgumentsWellFormed represented callEffect,
        argumentsEffect.trans_same (callEffect.weaken CellSet.empty_subset)⟩
    next => contradiction
  next => contradiction

theorem successfulWorldPreserving : WorldPreserving successfulCalls := by
  intro beforeWorld afterWorld function values value evaluated
  simp only [successfulCalls] at evaluated
  split at evaluated <;> try contradiction
  split at evaluated <;> try contradiction
  obtain ⟨rfl, rfl⟩ := evaluated
  rfl

theorem failedWorldPreserving : WorldPreserving failedCalls := by
  intro beforeWorld afterWorld function values value evaluated
  simp only [failedCalls] at evaluated
  split at evaluated <;> try contradiction
  split at evaluated <;> try contradiction
  obtain ⟨rfl, rfl⟩ := evaluated
  rfl

end TokenConstructors

end Lanius.Extraction.Decimal.HelperFrames
