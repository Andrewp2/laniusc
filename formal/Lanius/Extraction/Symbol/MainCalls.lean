import Lanius.Extraction.Symbol.Model
import Lanius.FunctionalViewCoreFreshSimulation
import Lanius.FunctionalViewCoreCallFrame

namespace Lanius.Extraction.Symbol.MainCalls

open Lanius
open Lanius.Core
open Lanius.Semantics
open Lanius.Properties
open Lanius.Separation
open Lanius.CallContracts
open Lanius.Compiler.Lexer
open Lanius.FunctionalView
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.Stateful
open Lanius.FunctionalView.Core.Effectful
open Lanius.FunctionalView.Core.EffectfulStateful
open Lanius.FunctionalView.FreshSimulation

private theorem function_parameters :
    Functions.matchSymbolHeadFunction.parameters =
      [(0, .slice Structure.i32), (1, Structure.i32), (2, Structure.i32)] := by
  native_decide

private theorem parameterBindings_match (source : List Byte) (start : Nat) :
    bindParameters Functions.matchSymbolHeadFunction.parameters
        (Model.argumentValues source start) =
      some (Core.parameterBindings (Model.environment source start)) := by
  rw [function_parameters]
  simp [bindParameters, Model.argumentValues, Model.environment,
    Model.sourceSlice,
    Lanius.FunctionalView.Core.parameterBindings, List.finRange]

private theorem environment_match (source : List Byte) (start : Nat) :
    Model.environment source start =
      Execution.sourceEnvironment (Model.sourceIntegers source)
        (Model.sourceIntegers source).length start := by
  funext index
  match index with
  | ⟨0, _⟩ =>
      simp [Model.environment, Execution.sourceEnvironment, Model.sourceSlice,
        Execution.sourceSlice, Model.sourceIntegers]
  | ⟨1, _⟩ =>
      simp [Model.environment, Execution.sourceEnvironment,
        Model.sourceIntegers]
  | ⟨2, _⟩ =>
      simp [Model.environment, Execution.sourceEnvironment]
  | ⟨Nat.succ (Nat.succ (Nat.succ n)), bound⟩ => omega

theorem mainFramePreservingCallSoundness (source : List Byte) :
    FramePreservingCallSoundness verifiedFrontendCore
      (Model.callModel source) := by
  constructor
  intro arity layout localCell beforeWorld afterWorld callerEnvironment before
    afterArguments function sourceArguments values result argumentWrites
    afterArgumentsWellFormed represented argumentsExecution argumentsEffect
    evaluated
  obtain ⟨startInt, rfl, rfl, sourceBound, startNonnegative,
      startInBounds, sourceFound, rfl, afterWorldEq⟩ :=
    Model.callModel_success evaluated
  subst afterWorld
  let start := startInt.toNat
  have startEq : (start : Int) = startInt := by
    simp [start]
    omega
  have startInBounds' : start < source.length := by
    exact startInBounds
  let calleeEnvironment := Model.environment source start
  let bindings := Core.parameterBindings calleeEnvironment
  let callee := enterCall afterArguments bindings
  have calleeRepresented : Representation identityLayout
      (callLocalCells afterArguments) beforeWorld calleeEnvironment callee := by
    simpa [callee, bindings] using
      represented.enterCallParameters afterArgumentsWellFormed
        (environment := calleeEnvironment)
  have calleeWellFormed : StateWellFormed callee := by
    simpa [callee, bindings] using
      enterCall_preserves_wellFormed afterArgumentsWellFormed
  have functionalRun := Execution.matchSymbolHeadCommand_run beforeWorld
    (Model.sourceIntegers source) start sourceFound
    (by simpa using sourceBound) (by simpa using startInBounds')
  rw [← Structure.matchSymbolHead_command_exact] at functionalRun
  rw [← Model.logicalMatch_eq_execution source start startInBounds'] at functionalRun
  have functionalEvaluation :=
    Lanius.FunctionalView.Stateful.Acyclic.run?_sound functionalRun
  rw [← environment_match source start] at functionalEvaluation
  let operations := operationSoundness verifiedFrontendCore Calls.helperCalls
    Calls.helperFramePreservingCallSoundness
  have simulation := commandSoundness operations functionalEvaluation
    (by native_decide) calleeRepresented
    (LayoutBelow.identity (arity := 3)) calleeWellFormed
    (frontier := afterArguments.nextCell)
    (by intro index; simp [callLocalCells])
    (by
      simpa [callee, bindings] using
        (enterCall_effect afterArguments bindings).nextCell)
  obtain ⟨completed, bodyExecution, completedWellFormed,
      completedRepresented, bodyEffect⟩ := simulation
  rw [Functions.matchSymbolHead_toCore_exactly] at bodyExecution
  change Executes verifiedFrontendCore callee Functions.matchSymbolHeadBody
    (.returned (some (Model.encoded source start))) completed at bodyExecution
  have callExecution : Evaluates verifiedFrontendCore before
      (.call Functions.matchSymbolHeadFunction.id
        (toCoreExprs layout sourceArguments))
      (Model.encoded source start) (restoreLocals afterArguments completed) := by
    apply evaluatesCallReturned
      (bindings := bindings) (body := Functions.matchSymbolHeadBody)
      argumentsExecution Functions.verifiedFrontendCore_finds_matchSymbolHead
    · rw [show [Model.sourceSlice source,
          .signed .i32 source.length, .signed .i32 startInt] =
          Model.argumentValues source start by
        simp [Model.argumentValues, startEq]]
      simpa [bindings, calleeEnvironment] using
        parameterBindings_match source start
    · exact Functions.matchSymbolHead_has_body
    · simpa [callee, bindings] using bodyExecution
  obtain ⟨afterWellFormed, afterRepresented, callEffect⟩ :=
    represented.restoreFreshCall afterArgumentsWellFormed
      completedWellFormed (bindings := bindings) bodyEffect
      (by intro cell written; exact written)
  exact ⟨restoreLocals afterArguments completed, callExecution,
    afterWellFormed, afterRepresented,
    argumentsEffect.trans_same
      (callEffect.weaken CellSet.empty_subset)⟩

def callModel (source : List Byte) : CallModel :=
  CallModel.route
    (fun function => function == Functions.matchSymbolHeadFunction.id)
    (Model.callModel source) Calls.helperCalls

theorem framePreservingCallSoundness (source : List Byte) :
    FramePreservingCallSoundness verifiedFrontendCore (callModel source) := by
  exact FramePreservingCallSoundness.route
    (mainFramePreservingCallSoundness source)
    Calls.helperFramePreservingCallSoundness

theorem worldPreserving (source : List Byte) : WorldPreserving (callModel source) := by
  apply WorldPreserving.route
  · intro beforeWorld afterWorld function values value evaluated
    obtain ⟨start, functionEq, argumentsEq, sourceBound, startNonnegative,
      startInBounds, sourceFound, resultEq, afterWorldEq⟩ :=
        Model.callModel_success evaluated
    exact afterWorldEq
  · exact Calls.helperWorldPreserving

theorem callSoundness (source : List Byte) :
    EffectfulStateful.CallSoundness verifiedFrontendCore (callModel source) := by
  exact (framePreservingCallSoundness source).toCallSoundness
    (worldPreserving source)

theorem callModel_matchSymbolHead
    (source : List Byte) (world : ReadOnly.World) (start : Nat)
    (sourceBound : source.length ≤ 2147483646)
    (startInBounds : start < source.length)
    (sourceFound : world.i32Slice? 0 = some (Model.sourceIntegers source)) :
    (callModel source).evaluate world Functions.matchSymbolHeadFunction.id
        (Model.argumentValues source start) =
      .ok (Model.encoded source start, world) := by
  simp only [callModel, CallModel.route]
  rw [if_pos (by native_decide)]
  exact Model.callModel_at source world start sourceBound startInBounds sourceFound

theorem callModel_tokenMatchKind (source : List Byte)
    (world : ReadOnly.World) (kind length : Int) :
    (callModel source).evaluate world Functions.tokenMatchKindFunction.id
        [Semantics.value kind length] = .ok (.signed .i32 kind, world) := by
  rfl

theorem callModel_tokenMatchLength (source : List Byte)
    (world : ReadOnly.World) (kind length : Int) :
    (callModel source).evaluate world Functions.tokenMatchLengthFunction.id
        [Semantics.value kind length] = .ok (.signed .i32 length, world) := by
  rfl

theorem callModel_tokenMatch (source : List Byte)
    (world : ReadOnly.World) (kind length : Int) :
    (callModel source).evaluate world Functions.tokenMatchFunction.id
        [.signed .i32 kind, .signed .i32 length] =
      .ok (Semantics.value kind length, world) := by
  rfl

end Lanius.Extraction.Symbol.MainCalls
