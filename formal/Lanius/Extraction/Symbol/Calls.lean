import Lanius.Extraction.Symbol.Functions
import Lanius.Extraction.Symbol.Value
import Lanius.FunctionalViewCoreFreshSimulation

namespace Lanius.Extraction.Symbol.Calls

open Lanius
open Lanius.Core
open Lanius.Semantics
open Lanius.Properties
open Lanius.Separation
open Lanius.CallContracts
open Lanius.FunctionalView
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.ReadOnly
open Lanius.FunctionalView.Core.Effectful
open Lanius.FunctionalView.Core.Stateful
open Lanius.FunctionalView.FreshSimulation
open Lanius.Extraction.Symbol.Functions
open Lanius.Extraction.Symbol.Semantics

def accessorCalls (function : FunctionId) (field : FieldId) : CallModel where
  evaluate := fun world candidate arguments =>
    if candidate = function then
      match arguments with
      | [.structure 3 fields] =>
          match fields[field]? with
          | some result => .ok (result, world)
          | none => .error .typeMismatch
      | _ => .error .typeMismatch
    else .error .invalidPointer

private theorem accessorCalls_success
    (evaluated : (accessorCalls expectedFunction field).evaluate world
      function arguments = .ok (result, afterWorld)) :
    ∃ fields,
      function = expectedFunction ∧
      arguments = [.structure 3 fields] ∧
      fields[field]? = some result ∧ afterWorld = world := by
  simp only [accessorCalls] at evaluated
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

private def accessorBindings (fields : List Value) : List (VarId × Value) :=
  [(0, .structure 3 fields)]

def tokenMatchKindCalls : CallModel :=
  accessorCalls tokenMatchKindFunction.id 0

def tokenMatchLengthCalls : CallModel :=
  accessorCalls tokenMatchLengthFunction.id 1

private theorem accessorFramePreservingSoundness
    (function : Function) (field : FieldId)
    (functionFound : verifiedFrontendCore.function? function.id = some function)
    (parameters : function.parameters = [(0, tokenMatchType)])
    (body : function.body = some (accessorBody field)) :
    FramePreservingCallSoundness verifiedFrontendCore
      (accessorCalls function.id field) := by
  constructor
  intro arity layout localCell beforeWorld afterWorld callerEnvironment before
    afterArguments calledFunction arguments values result argumentWrites
    afterArgumentsWellFormed represented argumentsExecution argumentsEffect
    evaluated
  obtain ⟨fields, functionEq, valuesEq, fieldFound, worldEq⟩ :=
    accessorCalls_success (expectedFunction := function.id) (field := field)
      evaluated
  subst calledFunction
  subst values
  subst afterWorld
  let callee := enterCall afterArguments (accessorBindings fields)
  let after := restoreLocals afterArguments callee
  have calleeWellFormed : StateWellFormed callee := by
    simpa [callee] using enterCall_preserves_wellFormed
      (bindings := accessorBindings fields) afterArgumentsWellFormed
  have localFound : callee.local? 0 = some (.structure 3 fields) := by
    simpa [callee, accessorBindings] using
      enterCall_local_of_binding afterArguments [] [] 0
        (.structure 3 fields) afterArgumentsWellFormed (by simp)
  have localEvaluation : Evaluates verifiedFrontendCore callee (.local 0)
      (.structure 3 fields) callee :=
    ⟨1, evalLocal_of_local 1 verifiedFrontendCore callee 0 _ localFound⟩
  have fieldEvaluation : Evaluates verifiedFrontendCore callee
      (.field (.local 0) field) result callee :=
    evaluatesStructureField localEvaluation fieldFound
  have bodyExecution : Executes verifiedFrontendCore callee
      (accessorBody field) (.returned (some result)) callee :=
    executesSequenceReturned (executesReturnValue fieldEvaluation)
  have callExecution : Evaluates verifiedFrontendCore before
      (.call function.id (toCoreExprs layout arguments)) result after := by
    apply evaluatesCallReturned argumentsExecution functionFound
    · rw [parameters]
      rfl
    · exact body
    · simpa [callee, after, accessorBindings] using bodyExecution
  have entered : StoreEffect CellSet.empty afterArguments callee := by
    simpa [callee] using enterCall_effect afterArguments
      (accessorBindings fields)
  have callEffect : ModifiesOnly CellSet.empty afterArguments after := by
    simpa [after] using entered.restoreLocals
  have afterWellFormed : StateWellFormed after :=
    entered.restoreLocals_wellFormed afterArgumentsWellFormed calleeWellFormed
  have afterRepresented : Representation layout localCell beforeWorld
      callerEnvironment after := {
    worldOwned := callEffect.empty_preserves_assertion
      afterArgumentsWellFormed (World.owns beforeWorld) represented.worldOwned
    localOwned := fun index => callEffect.empty_preserves_assertion
      afterArgumentsWellFormed
      (Assertion.localPointsTo (layout index) (localCell index)
        (some (callerEnvironment index))) (represented.localOwned index)
    localCellsInjective := represented.localCellsInjective
    worldLocalsDisjoint := represented.worldLocalsDisjoint }
  exact ⟨after, callExecution, afterWellFormed, afterRepresented,
    argumentsEffect.trans_same (callEffect.weaken CellSet.empty_subset)⟩

theorem tokenMatchKindFramePreservingCallSoundness :
    FramePreservingCallSoundness verifiedFrontendCore tokenMatchKindCalls := by
  exact accessorFramePreservingSoundness tokenMatchKindFunction 0
    verifiedFrontendCore_finds_tokenMatchKind tokenMatchKind_shape.2.1
    tokenMatchKind_shape.2.2.2

theorem tokenMatchLengthFramePreservingCallSoundness :
    FramePreservingCallSoundness verifiedFrontendCore tokenMatchLengthCalls := by
  exact accessorFramePreservingSoundness tokenMatchLengthFunction 1
    verifiedFrontendCore_finds_tokenMatchLength tokenMatchLength_shape.2.1
    tokenMatchLength_shape.2.2.2

def tokenMatchCalls : CallModel where
  evaluate := fun world function arguments =>
    if function = tokenMatchFunction.id then
      match arguments with
      | [.signed .i32 kind, .signed .i32 length] =>
          .ok (value kind length, world)
      | _ => .error .typeMismatch
    else .error .invalidPointer

private def tokenMatchBindings (kind length : Int) : List (VarId × Value) :=
  [(0, .signed .i32 kind), (1, .signed .i32 length)]

private theorem tokenMatchBody_executes (state : State)
    (wellFormed : StateWellFormed state) (kind length : Int) :
    Executes verifiedFrontendCore
      (enterCall state (tokenMatchBindings kind length)) tokenMatchCoreBody
      (.returned (some (value kind length)))
      (enterCall state (tokenMatchBindings kind length)) := by
  let callee := enterCall state (tokenMatchBindings kind length)
  have kindFound : callee.local? 0 = some (.signed .i32 kind) := by
    simpa [callee, tokenMatchBindings] using
      enterCall_local_of_binding state []
        [(1, .signed .i32 length)] 0 (.signed .i32 kind) wellFormed (by simp)
  have lengthFound : callee.local? 1 = some (.signed .i32 length) := by
    simpa [callee, tokenMatchBindings] using
      enterCall_local_of_binding state [(0, .signed .i32 kind)] [] 1
        (.signed .i32 length) wellFormed (by simp)
  have kindEvaluation : Evaluates verifiedFrontendCore callee (.local 0)
      (.signed .i32 kind) callee :=
    ⟨1, evalLocal_of_local 1 verifiedFrontendCore callee 0 _ kindFound⟩
  have lengthEvaluation : Evaluates verifiedFrontendCore callee (.local 1)
      (.signed .i32 length) callee :=
    ⟨1, evalLocal_of_local 1 verifiedFrontendCore callee 1 _ lengthFound⟩
  have fieldsEvaluation : ArgumentsEvaluateTo verifiedFrontendCore callee
      [.local 0, .local 1]
      [.signed .i32 kind, .signed .i32 length] callee :=
    ArgumentsEvaluateTo.cons kindEvaluation
      (ArgumentsEvaluateTo.singleton lengthEvaluation)
  exact executesSequenceReturned
    (executesReturnValue (evaluatesStructValue fieldsEvaluation))

private theorem preserveRepresentation
    (wellFormed : StateWellFormed before)
    (represented : Representation layout localCell world environment before)
    (effect : ModifiesOnly CellSet.empty before after) :
    Representation layout localCell world environment after := {
  worldOwned := effect.empty_preserves_assertion wellFormed
    (World.owns world) represented.worldOwned
  localOwned := fun index => effect.empty_preserves_assertion wellFormed
    (Assertion.localPointsTo (layout index) (localCell index)
      (some (environment index))) (represented.localOwned index)
  localCellsInjective := represented.localCellsInjective
  worldLocalsDisjoint := represented.worldLocalsDisjoint
}

theorem tokenMatchFramePreservingCallSoundness :
    FramePreservingCallSoundness verifiedFrontendCore tokenMatchCalls := by
  constructor
  intro arity layout localCell beforeWorld afterWorld environment before
    afterArguments function arguments values result argumentWrites
    afterArgumentsWellFormed represented argumentsExecution argumentsEffect
    evaluated
  simp only [tokenMatchCalls] at evaluated
  split at evaluated
  next functionEq =>
    split at evaluated
    next kind length =>
      obtain ⟨rfl, rfl⟩ := evaluated
      subst function
      let callee := enterCall afterArguments
        (tokenMatchBindings kind length)
      let after := restoreLocals afterArguments callee
      have calleeWellFormed : StateWellFormed callee := by
        simpa [callee] using enterCall_preserves_wellFormed
          (bindings := tokenMatchBindings kind length)
          afterArgumentsWellFormed
      have bodyExecution : Executes verifiedFrontendCore callee
          tokenMatchCoreBody (.returned (some (value kind length))) callee := by
        simpa [callee] using tokenMatchBody_executes
          afterArguments afterArgumentsWellFormed kind length
      dsimp [callee] at bodyExecution
      have callExecution : Evaluates verifiedFrontendCore before
          (.call tokenMatchFunction.id (toCoreExprs layout arguments))
          (value kind length) after := by
        apply evaluatesCallReturned argumentsExecution
          verifiedFrontendCore_finds_tokenMatch
        · rw [tokenMatch_shape.2.1]
          rfl
        · exact tokenMatch_shape.2.2.2
        · exact bodyExecution
      have entered : StoreEffect CellSet.empty afterArguments callee := by
        simpa [callee] using enterCall_effect afterArguments
          (tokenMatchBindings kind length)
      have callEffect : ModifiesOnly CellSet.empty afterArguments after := by
        simpa [after] using entered.restoreLocals
      exact ⟨after, callExecution,
        entered.restoreLocals_wellFormed afterArgumentsWellFormed
          calleeWellFormed,
        preserveRepresentation afterArgumentsWellFormed represented callEffect,
        argumentsEffect.trans_same
          (callEffect.weaken CellSet.empty_subset)⟩
    next => contradiction
  next => contradiction

def helperCalls : CallModel :=
  CallModel.route (fun function => function == tokenMatchKindFunction.id)
    tokenMatchKindCalls
    (CallModel.route (fun function => function == tokenMatchLengthFunction.id)
      tokenMatchLengthCalls tokenMatchCalls)

theorem helperFramePreservingCallSoundness :
    FramePreservingCallSoundness verifiedFrontendCore helperCalls := by
  exact FramePreservingCallSoundness.route
    tokenMatchKindFramePreservingCallSoundness
    (FramePreservingCallSoundness.route
      tokenMatchLengthFramePreservingCallSoundness
      tokenMatchFramePreservingCallSoundness)

theorem helperWorldPreserving : WorldPreserving helperCalls := by
  apply WorldPreserving.route
  · intro beforeWorld afterWorld function arguments result evaluated
    obtain ⟨_, _, _, _, worldEq⟩ := accessorCalls_success evaluated
    exact worldEq
  · apply WorldPreserving.route
    · intro beforeWorld afterWorld function arguments result evaluated
      obtain ⟨_, _, _, _, worldEq⟩ := accessorCalls_success evaluated
      exact worldEq
    · intro beforeWorld afterWorld function arguments result evaluated
      simp only [tokenMatchCalls] at evaluated
      split at evaluated
      next =>
        split at evaluated
        next =>
          obtain ⟨rfl, rfl⟩ := evaluated
          rfl
        next => contradiction
      next => contradiction

theorem helperCalls_tokenMatchKind (world : World) (kind length : Int) :
    helperCalls.evaluate world tokenMatchKindFunction.id [value kind length] =
      .ok (.signed .i32 kind, world) := by rfl

theorem helperCalls_tokenMatchLength (world : World) (kind length : Int) :
    helperCalls.evaluate world tokenMatchLengthFunction.id [value kind length] =
      .ok (.signed .i32 length, world) := by rfl

theorem helperCalls_tokenMatch (world : World) (kind length : Int) :
    helperCalls.evaluate world tokenMatchFunction.id
        [.signed .i32 kind, .signed .i32 length] =
      .ok (value kind length, world) := by rfl

end Lanius.Extraction.Symbol.Calls
