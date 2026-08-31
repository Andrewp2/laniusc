import Lanius.Extraction.TokenScan.Functions
import Lanius.CallContracts
import Lanius.FunctionalViewCoreEffectfulStateful
import Lanius.FunctionalViewCoreFreshSimulation

namespace Lanius.Extraction.TokenScan.Semantics

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
open Lanius.Extraction.TokenScan.Functions

/-! # Semantics of the checked `token_scan.lani` functions

All six functions are store-pure.  Their contracts still use the stateful
separation-preserving call boundary, which proves that invoking them cannot
disturb caller-owned slices or locals.
-/

def value (success : Bool) (kind endOffset errorOffset : Int) : Value :=
  .structure 1 [
    .boolean success,
    .signed .i32 kind,
    .signed .i32 endOffset,
    .signed .i32 errorOffset]

def accessorBindings (fields : List Value) : List (VarId × Value) :=
  [(0, .structure 1 fields)]

def accessorCallee (state : State) (fields : List Value) : State :=
  enterCall state (accessorBindings fields)

def accessorAfter (state : State) (fields : List Value) : State :=
  restoreLocals state (accessorCallee state fields)

theorem accessorBody_executes
    (state : State) (wellFormed : StateWellFormed state)
    (fields : List Value) (field : FieldId) (result : Value)
    (found : fields[field]? = some result) :
    Executes verifiedFrontendCore (accessorCallee state fields)
      (accessorBody field) (.returned (some result))
      (accessorCallee state fields) := by
  let callee := accessorCallee state fields
  have localFound : callee.local? 0 = some (.structure 1 fields) := by
    simpa [callee, accessorCallee, accessorBindings] using
      enterCall_local_of_binding state [] [] 0 (.structure 1 fields)
        wellFormed (by simp)
  have localEvaluation : Evaluates verifiedFrontendCore callee (.local 0)
      (.structure 1 fields) callee :=
    ⟨1, evalLocal_of_local 1 verifiedFrontendCore callee 0 _ localFound⟩
  have fieldEvaluation : Evaluates verifiedFrontendCore callee
      (.field (.local 0) field) result callee :=
    evaluatesStructureField localEvaluation found
  exact executesSequenceReturned (executesReturnValue fieldEvaluation)

def accessorCalls (function : FunctionId) (field : FieldId) : CallModel where
  evaluate := fun world candidate arguments =>
    if candidate = function then
      match arguments with
      | [.structure 1 fields] =>
          match fields[field]? with
          | some result => .ok (result, world)
          | none => .error .typeMismatch
      | _ => .error .typeMismatch
    else
      .error .invalidPointer

private theorem accessorCalls_success
    (evaluated : (accessorCalls expectedFunction field).evaluate world
      function arguments = .ok (result, afterWorld)) :
    ∃ fields,
      function = expectedFunction ∧
      arguments = [.structure 1 fields] ∧
      fields[field]? = some result ∧
      afterWorld = world := by
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

private theorem accessorCallSoundnessFor
    (function : Function) (field : FieldId)
    (functionFound : verifiedFrontendCore.function? function.id = some function)
    (parameters : function.parameters = [(0, tokenScanType)])
    (body : function.body = some (accessorBody field)) :
    Lanius.FunctionalView.Core.EffectfulStateful.CallSoundness
      verifiedFrontendCore (accessorCalls function.id field) := by
  constructor
  · intro arity layout localCell beforeWorld afterWorld environment before
      afterArguments calledFunction arguments argumentsValues result
      argumentWrites afterArgumentsWellFormed represented argumentsExecution
      argumentsEffect evaluated
    obtain ⟨fields, functionEq, valuesEq, fieldFound, worldEq⟩ :=
      accessorCalls_success (expectedFunction := function.id) (field := field)
        evaluated
    subst calledFunction
    subst argumentsValues
    subst afterWorld
    let callee := accessorCallee afterArguments fields
    let after := accessorAfter afterArguments fields
    have calleeWellFormed : StateWellFormed callee := by
      simpa [callee, accessorCallee, accessorBindings] using
        (enterCall_preserves_wellFormed
          (bindings := accessorBindings fields) afterArgumentsWellFormed)
    have bodyExecution : Executes verifiedFrontendCore callee
        (accessorBody field) (.returned (some result)) callee := by
      simpa [callee] using accessorBody_executes afterArguments
        afterArgumentsWellFormed fields field result fieldFound
    have callExecution : Evaluates verifiedFrontendCore before
        (.call function.id (toCoreExprs layout arguments)) result after := by
      apply evaluatesCallReturned argumentsExecution functionFound
      · rw [parameters]
        rfl
      · exact body
      · change Executes verifiedFrontendCore callee (accessorBody field)
          (.returned (some result)) callee
        exact bodyExecution
    have entered : StoreEffect CellSet.empty afterArguments callee := by
      simpa [callee, accessorCallee] using
        enterCall_effect afterArguments (accessorBindings fields)
    have callEffect : ModifiesOnly CellSet.empty afterArguments after := by
      simpa [after, accessorAfter, callee] using entered.restoreLocals
    have afterWellFormed : StateWellFormed after :=
      entered.restoreLocals_wellFormed afterArgumentsWellFormed
        calleeWellFormed
    have afterRepresented : Representation layout localCell beforeWorld
        environment after := {
      worldOwned := callEffect.empty_preserves_assertion
        afterArgumentsWellFormed (World.owns beforeWorld)
        represented.worldOwned
      localOwned := fun index => callEffect.empty_preserves_assertion
        afterArgumentsWellFormed
        (Assertion.localPointsTo (layout index) (localCell index)
          (some (environment index))) (represented.localOwned index)
      localCellsInjective := represented.localCellsInjective
      worldLocalsDisjoint := represented.worldLocalsDisjoint
    }
    exact ⟨after, CellSet.union argumentWrites CellSet.empty, callExecution,
      afterWellFormed, afterRepresented, argumentsEffect.trans callEffect⟩
  · intro beforeWorld afterWorld calledFunction arguments result evaluated cell
    obtain ⟨fields, functionEq, valuesEq, fieldFound, worldEq⟩ :=
      accessorCalls_success (expectedFunction := function.id) (field := field)
        evaluated
    exact congrArg (fun currentWorld : World =>
      (currentWorld.i32Slice? cell).map List.length) worldEq

def succeededCalls : CallModel := accessorCalls succeededFunction.id 0
def kindCalls : CallModel := accessorCalls kindFunction.id 1
def endOffsetCalls : CallModel := accessorCalls endOffsetFunction.id 2
def errorOffsetCalls : CallModel := accessorCalls errorOffsetFunction.id 3

theorem succeededCall_soundness :
    Lanius.FunctionalView.Core.EffectfulStateful.CallSoundness
      verifiedFrontendCore succeededCalls := by
  exact accessorCallSoundnessFor succeededFunction 0 core_finds_succeeded
    succeeded_shape.2.1 succeeded_shape.2.2.2

theorem kindCall_soundness :
    Lanius.FunctionalView.Core.EffectfulStateful.CallSoundness
      verifiedFrontendCore kindCalls := by
  exact accessorCallSoundnessFor kindFunction 1 core_finds_kind
    kind_shape.2.1 kind_shape.2.2.2

theorem endOffsetCall_soundness :
    Lanius.FunctionalView.Core.EffectfulStateful.CallSoundness
      verifiedFrontendCore endOffsetCalls := by
  exact accessorCallSoundnessFor endOffsetFunction 2 core_finds_endOffset
    endOffset_shape.2.1 endOffset_shape.2.2.2

theorem errorOffsetCall_soundness :
    Lanius.FunctionalView.Core.EffectfulStateful.CallSoundness
      verifiedFrontendCore errorOffsetCalls := by
  exact accessorCallSoundnessFor errorOffsetFunction 3 core_finds_errorOffset
    errorOffset_shape.2.1 errorOffset_shape.2.2.2

def pairBindings (kind endOffset : Int) : List (VarId × Value) :=
  [(0, .signed .i32 kind), (1, .signed .i32 endOffset)]

def errorBinding (errorOffset : Int) : List (VarId × Value) :=
  [(0, .signed .i32 errorOffset)]

def constructorCallee (state : State) (bindings : List (VarId × Value)) :
    State := enterCall state bindings

def constructorAfter (state : State) (bindings : List (VarId × Value)) :
    State := restoreLocals state (constructorCallee state bindings)

private theorem localEvaluation
    (state : State) (id : VarId) (localValue : Value)
    (found : state.local? id = some localValue) :
    Evaluates verifiedFrontendCore state (.local id) localValue state :=
  ⟨1, evalLocal_of_local 1 verifiedFrontendCore state id localValue found⟩

private theorem literalEvaluation (state : State) (literalValue : Value) :
    Evaluates verifiedFrontendCore state (.value literalValue)
      literalValue state := ⟨1, rfl⟩

private theorem constructorExpression_evaluates
    (state : State)
    (successExpression kindExpression endExpression errorExpression : Expr)
    (success : Bool) (kind endOffset errorOffset : Int)
    (successEvaluation : Evaluates verifiedFrontendCore state
      successExpression (.boolean success) state)
    (kindEvaluation : Evaluates verifiedFrontendCore state kindExpression
      (.signed .i32 kind) state)
    (endEvaluation : Evaluates verifiedFrontendCore state endExpression
      (.signed .i32 endOffset) state)
    (errorEvaluation : Evaluates verifiedFrontendCore state errorExpression
      (.signed .i32 errorOffset) state) :
    Evaluates verifiedFrontendCore state
      (.structValue 1 [successExpression, kindExpression, endExpression,
        errorExpression])
      (value success kind endOffset errorOffset) state := by
  apply evaluatesStructValue
  exact ArgumentsEvaluateTo.cons successEvaluation
    (ArgumentsEvaluateTo.cons kindEvaluation
      (ArgumentsEvaluateTo.cons endEvaluation
        (ArgumentsEvaluateTo.singleton errorEvaluation)))

theorem successfulBody_executes
    (state : State) (wellFormed : StateWellFormed state)
    (kind endOffset : Int) :
    let bindings := pairBindings kind endOffset
    let callee := constructorCallee state bindings
    Executes verifiedFrontendCore callee successfulCoreBody
      (.returned (some (value true kind endOffset 0))) callee := by
  dsimp only
  let callee := constructorCallee state (pairBindings kind endOffset)
  have kindLocal : callee.local? 0 = some (.signed .i32 kind) := by
    simpa [callee, constructorCallee, pairBindings] using
      enterCall_local_of_binding state [] [(1, .signed .i32 endOffset)] 0
        (.signed .i32 kind) wellFormed (by simp)
  have endLocal : callee.local? 1 = some (.signed .i32 endOffset) := by
    simpa [callee, constructorCallee, pairBindings] using
      enterCall_local_of_binding state [(0, .signed .i32 kind)] [] 1
        (.signed .i32 endOffset) wellFormed (by simp)
  have expression := constructorExpression_evaluates callee
    (.value (.boolean true)) (.local 0) (.local 1)
    (.value (.signed .i32 0)) true kind endOffset 0
    (literalEvaluation callee (.boolean true))
    (localEvaluation callee 0 _ kindLocal)
    (localEvaluation callee 1 _ endLocal)
    (literalEvaluation callee (.signed .i32 0))
  exact executesSequenceReturned (executesReturnValue expression)

theorem failedBody_executes
    (state : State) (wellFormed : StateWellFormed state)
    (errorOffset : Int) :
    let bindings := errorBinding errorOffset
    let callee := constructorCallee state bindings
    Executes verifiedFrontendCore callee failedCoreBody
      (.returned (some (value false 0 0 errorOffset))) callee := by
  dsimp only
  let callee := constructorCallee state (errorBinding errorOffset)
  have errorLocal : callee.local? 0 = some (.signed .i32 errorOffset) := by
    simpa [callee, constructorCallee, errorBinding] using
      enterCall_local_of_binding state [] [] 0 (.signed .i32 errorOffset)
        wellFormed (by simp)
  have expression := constructorExpression_evaluates callee
    (.value (.boolean false)) (.value (.signed .i32 0))
    (.value (.signed .i32 0)) (.local 0) false 0 0 errorOffset
    (literalEvaluation callee (.boolean false))
    (literalEvaluation callee (.signed .i32 0))
    (literalEvaluation callee (.signed .i32 0))
    (localEvaluation callee 0 _ errorLocal)
  exact executesSequenceReturned (executesReturnValue expression)

private theorem pureConstructorCall
    (function : Function) (bindings : List (VarId × Value))
    (body : Stmt) (result : Value)
    (functionFound : verifiedFrontendCore.function? function.id = some function)
    (parametersBound : bindParameters function.parameters argumentsValues =
      some bindings)
    (functionBody : function.body = some body)
    (before afterArguments : State) (arguments : List Expr)
    (afterArgumentsWellFormed : StateWellFormed afterArguments)
    (argumentsExecution : ArgumentsEvaluateTo verifiedFrontendCore before
      arguments argumentsValues afterArguments)
    (bodyExecution : Executes verifiedFrontendCore
      (constructorCallee afterArguments bindings) body
      (.returned (some result)) (constructorCallee afterArguments bindings)) :
    let after := constructorAfter afterArguments bindings
    Evaluates verifiedFrontendCore before (.call function.id arguments)
      result after ∧
    ModifiesOnly CellSet.empty afterArguments after ∧
    StateWellFormed after := by
  let callee := constructorCallee afterArguments bindings
  let after := constructorAfter afterArguments bindings
  have calleeWellFormed : StateWellFormed callee := by
    simpa [callee, constructorCallee] using
      (enterCall_preserves_wellFormed (bindings := bindings)
        afterArgumentsWellFormed)
  have callExecution : Evaluates verifiedFrontendCore before
      (.call function.id arguments) result after := by
    apply evaluatesCallReturned argumentsExecution functionFound
      parametersBound functionBody
    change Executes verifiedFrontendCore callee body
      (.returned (some result)) callee
    exact bodyExecution
  have entered : StoreEffect CellSet.empty afterArguments callee := by
    simpa [callee, constructorCallee] using
      enterCall_effect afterArguments bindings
  have callEffect : ModifiesOnly CellSet.empty afterArguments after := by
    simpa [after, constructorAfter, callee] using entered.restoreLocals
  have afterWellFormed : StateWellFormed after :=
    entered.restoreLocals_wellFormed afterArgumentsWellFormed calleeWellFormed
  exact ⟨callExecution, callEffect, afterWellFormed⟩

theorem successfulCall_executes
    (before afterArguments : State) (arguments : List Expr)
    (kind endOffset : Int)
    (afterArgumentsWellFormed : StateWellFormed afterArguments)
    (argumentsExecution : ArgumentsEvaluateTo verifiedFrontendCore before
      arguments [.signed .i32 kind, .signed .i32 endOffset] afterArguments) :
    let bindings := pairBindings kind endOffset
    let after := constructorAfter afterArguments bindings
    Evaluates verifiedFrontendCore before
      (.call successfulFunction.id arguments)
      (value true kind endOffset 0) after ∧
    ModifiesOnly CellSet.empty afterArguments after ∧
    StateWellFormed after := by
  apply pureConstructorCall
    (argumentsValues := [.signed .i32 kind, .signed .i32 endOffset])
    successfulFunction (pairBindings kind endOffset) successfulCoreBody
    (value true kind endOffset 0) core_finds_successful
  · rw [successful_shape.2.1]
    rfl
  · exact successful_shape.2.2.2
  · exact afterArgumentsWellFormed
  · exact argumentsExecution
  · exact successfulBody_executes afterArguments afterArgumentsWellFormed
      kind endOffset

theorem failedCall_executes
    (before afterArguments : State) (arguments : List Expr)
    (errorOffset : Int)
    (afterArgumentsWellFormed : StateWellFormed afterArguments)
    (argumentsExecution : ArgumentsEvaluateTo verifiedFrontendCore before
      arguments [.signed .i32 errorOffset] afterArguments) :
    let bindings := errorBinding errorOffset
    let after := constructorAfter afterArguments bindings
    Evaluates verifiedFrontendCore before (.call failedFunction.id arguments)
      (value false 0 0 errorOffset) after ∧
    ModifiesOnly CellSet.empty afterArguments after ∧
    StateWellFormed after := by
  apply pureConstructorCall
    (argumentsValues := [.signed .i32 errorOffset]) failedFunction
    (errorBinding errorOffset) failedCoreBody (value false 0 0 errorOffset)
    core_finds_failed
  · rw [failed_shape.2.1]
    rfl
  · exact failed_shape.2.2.2
  · exact afterArgumentsWellFormed
  · exact argumentsExecution
  · exact failedBody_executes afterArguments afterArgumentsWellFormed errorOffset

def successfulCalls : CallModel where
  evaluate := fun world function arguments =>
    if function = successfulFunction.id then
      match arguments with
      | [.signed .i32 kind, .signed .i32 endOffset] =>
          .ok (value true kind endOffset 0, world)
      | _ => .error .typeMismatch
    else .error .invalidPointer

def failedCalls : CallModel where
  evaluate := fun world function arguments =>
    if function = failedFunction.id then
      match arguments with
      | [.signed .i32 errorOffset] =>
          .ok (value false 0 0 errorOffset, world)
      | _ => .error .typeMismatch
    else .error .invalidPointer

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
  worldLocalsDisjoint := represented.worldLocalsDisjoint
}

theorem successfulCall_soundness :
    Lanius.FunctionalView.Core.EffectfulStateful.CallSoundness
      verifiedFrontendCore successfulCalls := by
  constructor
  · intro arity layout localCell beforeWorld afterWorld environment before
      afterArguments function arguments argumentsValues result argumentWrites
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
        exact ⟨_, CellSet.union argumentWrites CellSet.empty, callExecution,
          afterWellFormed,
          preserveRepresentation afterArgumentsWellFormed represented
            callEffect,
          argumentsEffect.trans callEffect⟩
      next => contradiction
    next => contradiction
  · intro beforeWorld afterWorld function arguments result evaluated cell
    simp only [successfulCalls] at evaluated
    split at evaluated
    next =>
      split at evaluated
      next =>
        obtain ⟨rfl, rfl⟩ := evaluated
        rfl
      next => contradiction
    next => contradiction

theorem failedCall_soundness :
    Lanius.FunctionalView.Core.EffectfulStateful.CallSoundness
      verifiedFrontendCore failedCalls := by
  constructor
  · intro arity layout localCell beforeWorld afterWorld environment before
      afterArguments function arguments argumentsValues result argumentWrites
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
        exact ⟨_, CellSet.union argumentWrites CellSet.empty, callExecution,
          afterWellFormed,
          preserveRepresentation afterArgumentsWellFormed represented
            callEffect,
          argumentsEffect.trans callEffect⟩
      next => contradiction
    next => contradiction
  · intro beforeWorld afterWorld function arguments result evaluated cell
    simp only [failedCalls] at evaluated
    split at evaluated
    next =>
      split at evaluated
      next =>
        obtain ⟨rfl, rfl⟩ := evaluated
        rfl
      next => contradiction
    next => contradiction

theorem successfulFramePreservingCallSoundness :
    Lanius.FunctionalView.FreshSimulation.FramePreservingCallSoundness
      verifiedFrontendCore successfulCalls := by
  constructor
  intro arity layout localCell beforeWorld afterWorld environment before
    afterArguments function arguments argumentsValues result argumentWrites
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
        argumentsEffect.trans_same
          (callEffect.weaken CellSet.empty_subset)⟩
    next => contradiction
  next => contradiction

theorem failedFramePreservingCallSoundness :
    Lanius.FunctionalView.FreshSimulation.FramePreservingCallSoundness
      verifiedFrontendCore failedCalls := by
  constructor
  intro arity layout localCell beforeWorld afterWorld environment before
    afterArguments function arguments argumentsValues result argumentWrites
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
        argumentsEffect.trans_same
          (callEffect.weaken CellSet.empty_subset)⟩
    next => contradiction
  next => contradiction

def constructorCallModel : CallModel :=
  CallModel.route (fun function => function == successfulFunction.id)
    successfulCalls failedCalls

theorem constructorFramePreservingCallSoundness :
    Lanius.FunctionalView.FreshSimulation.FramePreservingCallSoundness
      verifiedFrontendCore constructorCallModel := by
  exact Lanius.FunctionalView.FreshSimulation.FramePreservingCallSoundness.route
    successfulFramePreservingCallSoundness failedFramePreservingCallSoundness

@[simp] theorem constructorCallModel_successful (world : World)
    (kind endOffset : Int) :
    constructorCallModel.evaluate world successfulFunction.id
        [.signed .i32 kind, .signed .i32 endOffset] =
      .ok (value true kind endOffset 0, world) := by
  rfl

@[simp] theorem constructorCallModel_failed (world : World)
    (errorOffset : Int) :
    constructorCallModel.evaluate world failedFunction.id
        [.signed .i32 errorOffset] =
      .ok (value false 0 0 errorOffset, world) := by
  rfl

/-! The public registry contains exactly the six checked functions. -/

def callModel : CallModel :=
  CallModel.route (fun function => function == succeededFunction.id)
    succeededCalls
    (CallModel.route (fun function => function == kindFunction.id)
      kindCalls
      (CallModel.route (fun function => function == endOffsetFunction.id)
        endOffsetCalls
        (CallModel.route (fun function => function == errorOffsetFunction.id)
          errorOffsetCalls
          (CallModel.route (fun function => function == successfulFunction.id)
            successfulCalls failedCalls))))

theorem callSoundness :
    Lanius.FunctionalView.Core.EffectfulStateful.CallSoundness
      verifiedFrontendCore callModel := by
  exact Lanius.FunctionalView.Core.EffectfulStateful.CallSoundness.route
    succeededCall_soundness
    (Lanius.FunctionalView.Core.EffectfulStateful.CallSoundness.route
      kindCall_soundness
      (Lanius.FunctionalView.Core.EffectfulStateful.CallSoundness.route
        endOffsetCall_soundness
        (Lanius.FunctionalView.Core.EffectfulStateful.CallSoundness.route
          errorOffsetCall_soundness
          (Lanius.FunctionalView.Core.EffectfulStateful.CallSoundness.route
            successfulCall_soundness failedCall_soundness))))

theorem callModel_succeeded (world : World)
    (success : Bool) (kind endOffset errorOffset : Int) :
    callModel.evaluate world succeededFunction.id
        [value success kind endOffset errorOffset] =
      .ok (.boolean success, world) := by rfl

theorem callModel_kind (world : World)
    (success : Bool) (kind endOffset errorOffset : Int) :
    callModel.evaluate world kindFunction.id
        [value success kind endOffset errorOffset] =
      .ok (.signed .i32 kind, world) := by rfl

theorem callModel_end_offset (world : World)
    (success : Bool) (kind endOffset errorOffset : Int) :
    callModel.evaluate world endOffsetFunction.id
        [value success kind endOffset errorOffset] =
      .ok (.signed .i32 endOffset, world) := by rfl

theorem callModel_error_offset (world : World)
    (success : Bool) (kind endOffset errorOffset : Int) :
    callModel.evaluate world errorOffsetFunction.id
        [value success kind endOffset errorOffset] =
      .ok (.signed .i32 errorOffset, world) := by rfl

theorem callModel_successful (world : World) (kind endOffset : Int) :
    callModel.evaluate world successfulFunction.id
        [.signed .i32 kind, .signed .i32 endOffset] =
      .ok (value true kind endOffset 0, world) := by rfl

theorem callModel_failed (world : World) (errorOffset : Int) :
    callModel.evaluate world failedFunction.id [.signed .i32 errorOffset] =
      .ok (value false 0 0 errorOffset, world) := by rfl

end Lanius.Extraction.TokenScan.Semantics
