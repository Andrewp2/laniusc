import Lanius.Extraction.RawLexer.Results.Functions
import Lanius.CallContracts
import Lanius.FunctionalViewCoreEffectfulStateful

namespace Lanius.Extraction.RawLexer.Results.Semantics

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
open Lanius.Extraction.RawLexer.Results.Functions

/-! # Semantics of the checked raw-lexer result functions

The source functions are store-pure.  Their call contracts nevertheless use
the separation-preserving stateful boundary, so callers retain ownership of
every active GPU-slice model and every local cell.
-/

def value (status tokenCount errorOffset : Int) : Value :=
  .structure 4 [
    .signed .i32 status,
    .signed .i32 tokenCount,
    .signed .i32 errorOffset]

def accessorBindings (fields : List Value) : List (VarId × Value) :=
  [(0, .structure 4 fields)]

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
  have localFound : callee.local? 0 = some (.structure 4 fields) := by
    simpa [callee, accessorCallee, accessorBindings] using
      enterCall_local_of_binding state [] [] 0 (.structure 4 fields)
        wellFormed (by simp)
  have localEvaluation : Evaluates verifiedFrontendCore callee (.local 0)
      (.structure 4 fields) callee :=
    ⟨1, evalLocal_of_local 1 verifiedFrontendCore callee 0 _ localFound⟩
  have fieldEvaluation : Evaluates verifiedFrontendCore callee
      (.field (.local 0) field) result callee :=
    evaluatesStructureField localEvaluation found
  exact executesSequenceReturned (executesReturnValue fieldEvaluation)

def accessorCalls (function : FunctionId) (field : FieldId) : CallModel where
  evaluate := fun world candidate arguments =>
    if candidate = function then
      match arguments with
      | [.structure 4 fields] =>
          match fields[field]? with
          | some result => .ok (result, world)
          | none => .error .typeMismatch
      | _ => .error .typeMismatch
    else
      .error .invalidPointer

theorem accessorCalls_success
    (evaluated : (accessorCalls expectedFunction field).evaluate world
      function arguments = .ok (result, afterWorld)) :
    ∃ fields,
      function = expectedFunction ∧
      arguments = [.structure 4 fields] ∧
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

theorem accessorCallSoundnessFor
    (function : Function) (field : FieldId)
    (functionFound : verifiedFrontendCore.function? function.id = some function)
    (parameters : function.parameters = [(0, lexResultType)])
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

def lexStatusCalls : CallModel := accessorCalls lexStatusFunction.id 0
def lexTokenCountCalls : CallModel := accessorCalls lexTokenCountFunction.id 1
def lexErrorOffsetCalls : CallModel :=
  accessorCalls lexErrorOffsetFunction.id 2

theorem lexStatusCalls_at_value (world : World)
    (status tokenCount errorOffset : Int) :
    lexStatusCalls.evaluate world lexStatusFunction.id
        [value status tokenCount errorOffset] =
      .ok (.signed .i32 status, world) := by rfl

theorem lexTokenCountCalls_at_value (world : World)
    (status tokenCount errorOffset : Int) :
    lexTokenCountCalls.evaluate world lexTokenCountFunction.id
        [value status tokenCount errorOffset] =
      .ok (.signed .i32 tokenCount, world) := by rfl

theorem lexErrorOffsetCalls_at_value (world : World)
    (status tokenCount errorOffset : Int) :
    lexErrorOffsetCalls.evaluate world lexErrorOffsetFunction.id
        [value status tokenCount errorOffset] =
      .ok (.signed .i32 errorOffset, world) := by rfl

theorem lexStatusCall_soundness :
    Lanius.FunctionalView.Core.EffectfulStateful.CallSoundness
      verifiedFrontendCore lexStatusCalls := by
  exact accessorCallSoundnessFor lexStatusFunction 0 core_finds_lexStatus
    lexStatus_shape.2.1 lexStatus_shape.2.2.2

theorem lexTokenCountCall_soundness :
    Lanius.FunctionalView.Core.EffectfulStateful.CallSoundness
      verifiedFrontendCore lexTokenCountCalls := by
  exact accessorCallSoundnessFor lexTokenCountFunction 1
    core_finds_lexTokenCount lexTokenCount_shape.2.1
    lexTokenCount_shape.2.2.2

theorem lexErrorOffsetCall_soundness :
    Lanius.FunctionalView.Core.EffectfulStateful.CallSoundness
      verifiedFrontendCore lexErrorOffsetCalls := by
  exact accessorCallSoundnessFor lexErrorOffsetFunction 2
    core_finds_lexErrorOffset lexErrorOffset_shape.2.1
    lexErrorOffset_shape.2.2.2

def completedBindings (tokenCount : Int) : List (VarId × Value) :=
  [(0, .signed .i32 tokenCount)]

def pairBindings (tokenCount errorOffset : Int) : List (VarId × Value) :=
  [(0, .signed .i32 tokenCount), (1, .signed .i32 errorOffset)]

def constructorCallee (state : State) (bindings : List (VarId × Value)) :
    State := enterCall state bindings

def constructorAfter (state : State) (bindings : List (VarId × Value)) :
    State := restoreLocals state (constructorCallee state bindings)

theorem success_constant : verifiedFrontendCore.constant? 89 = some {
    id := 89, type := i32Type, value := .signed .i32 0 } := by rfl

theorem error_constant : verifiedFrontendCore.constant? 90 = some {
    id := 90, type := i32Type, value := .signed .i32 1 } := by rfl

theorem output_full_constant : verifiedFrontendCore.constant? 91 = some {
    id := 91, type := i32Type, value := .signed .i32 2 } := by rfl

private theorem localEvaluation
    (state : State) (id : VarId) (localValue : Value)
    (found : state.local? id = some localValue) :
    Evaluates verifiedFrontendCore state (.local id) localValue state :=
  ⟨1, evalLocal_of_local 1 verifiedFrontendCore state id localValue found⟩

private theorem literalEvaluation (state : State) (literalValue : Value) :
    Evaluates verifiedFrontendCore state (.value literalValue)
      literalValue state := ⟨1, rfl⟩

private theorem constructorExpression_evaluates
    (state : State) (statusExpression tokenCountExpression
      errorOffsetExpression : Expr)
    (status tokenCount errorOffset : Int)
    (statusEvaluation : Evaluates verifiedFrontendCore state statusExpression
      (.signed .i32 status) state)
    (tokenCountEvaluation : Evaluates verifiedFrontendCore state
      tokenCountExpression (.signed .i32 tokenCount) state)
    (errorOffsetEvaluation : Evaluates verifiedFrontendCore state
      errorOffsetExpression (.signed .i32 errorOffset) state) :
    Evaluates verifiedFrontendCore state
      (.structValue 4 [statusExpression, tokenCountExpression,
        errorOffsetExpression])
      (value status tokenCount errorOffset) state := by
  apply evaluatesStructValue
  exact ArgumentsEvaluateTo.cons statusEvaluation
    (ArgumentsEvaluateTo.cons tokenCountEvaluation
      (ArgumentsEvaluateTo.singleton errorOffsetEvaluation))

theorem completedBody_executes
    (state : State) (wellFormed : StateWellFormed state) (tokenCount : Int) :
    let bindings := completedBindings tokenCount
    let callee := constructorCallee state bindings
    Executes verifiedFrontendCore callee completedCoreBody
      (.returned (some (value 0 tokenCount 0))) callee := by
  dsimp only
  let callee := constructorCallee state (completedBindings tokenCount)
  have tokenLocal : callee.local? 0 = some (.signed .i32 tokenCount) := by
    simpa [callee, constructorCallee, completedBindings] using
      enterCall_local_of_binding state [] [] 0 (.signed .i32 tokenCount)
        wellFormed (by simp)
  have expression := constructorExpression_evaluates callee
    (.constant 89) (.local 0) (.value (.signed .i32 0))
    0 tokenCount 0 (evaluatesConstant success_constant)
    (localEvaluation callee 0 _ tokenLocal)
    (literalEvaluation callee (.signed .i32 0))
  exact executesSequenceReturned (executesReturnValue expression)

theorem lexicalFailureBody_executes
    (state : State) (wellFormed : StateWellFormed state)
    (tokenCount errorOffset : Int) :
    let bindings := pairBindings tokenCount errorOffset
    let callee := constructorCallee state bindings
    Executes verifiedFrontendCore callee lexicalFailureCoreBody
      (.returned (some (value 1 tokenCount errorOffset))) callee := by
  dsimp only
  let callee := constructorCallee state (pairBindings tokenCount errorOffset)
  have tokenLocal : callee.local? 0 = some (.signed .i32 tokenCount) := by
    simpa [callee, constructorCallee, pairBindings] using
      enterCall_local_of_binding state []
        [(1, .signed .i32 errorOffset)] 0 (.signed .i32 tokenCount)
        wellFormed (by simp)
  have errorLocal : callee.local? 1 = some (.signed .i32 errorOffset) := by
    simpa [callee, constructorCallee, pairBindings] using
      enterCall_local_of_binding state [(0, .signed .i32 tokenCount)] [] 1
        (.signed .i32 errorOffset) wellFormed (by simp)
  have expression := constructorExpression_evaluates callee
    (.constant 90) (.local 0) (.local 1) 1 tokenCount errorOffset
    (evaluatesConstant error_constant)
    (localEvaluation callee 0 _ tokenLocal)
    (localEvaluation callee 1 _ errorLocal)
  exact executesSequenceReturned (executesReturnValue expression)

theorem outputFullBody_executes
    (state : State) (wellFormed : StateWellFormed state)
    (tokenCount sourceOffset : Int) :
    let bindings := pairBindings tokenCount sourceOffset
    let callee := constructorCallee state bindings
    Executes verifiedFrontendCore callee outputFullCoreBody
      (.returned (some (value 2 tokenCount sourceOffset))) callee := by
  dsimp only
  let callee := constructorCallee state (pairBindings tokenCount sourceOffset)
  have tokenLocal : callee.local? 0 = some (.signed .i32 tokenCount) := by
    simpa [callee, constructorCallee, pairBindings] using
      enterCall_local_of_binding state []
        [(1, .signed .i32 sourceOffset)] 0 (.signed .i32 tokenCount)
        wellFormed (by simp)
  have offsetLocal : callee.local? 1 = some (.signed .i32 sourceOffset) := by
    simpa [callee, constructorCallee, pairBindings] using
      enterCall_local_of_binding state [(0, .signed .i32 tokenCount)] [] 1
        (.signed .i32 sourceOffset) wellFormed (by simp)
  have expression := constructorExpression_evaluates callee
    (.constant 91) (.local 0) (.local 1) 2 tokenCount sourceOffset
    (evaluatesConstant output_full_constant)
    (localEvaluation callee 0 _ tokenLocal)
    (localEvaluation callee 1 _ offsetLocal)
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

theorem completedCall_executes
    (before afterArguments : State) (arguments : List Expr)
    (tokenCount : Int)
    (afterArgumentsWellFormed : StateWellFormed afterArguments)
    (argumentsExecution : ArgumentsEvaluateTo verifiedFrontendCore before
      arguments [.signed .i32 tokenCount] afterArguments) :
    let bindings := completedBindings tokenCount
    let after := constructorAfter afterArguments bindings
    Evaluates verifiedFrontendCore before
      (.call completedFunction.id arguments) (value 0 tokenCount 0) after ∧
    ModifiesOnly CellSet.empty afterArguments after ∧
    StateWellFormed after := by
  apply pureConstructorCall
    (argumentsValues := [.signed .i32 tokenCount])
    completedFunction (completedBindings tokenCount)
    completedCoreBody (value 0 tokenCount 0) core_finds_completed
  · rw [completed_shape.2.1]
    rfl
  · exact completed_shape.2.2.2
  · exact afterArgumentsWellFormed
  · exact argumentsExecution
  · exact completedBody_executes afterArguments afterArgumentsWellFormed
      tokenCount

theorem lexicalFailureCall_executes
    (before afterArguments : State) (arguments : List Expr)
    (tokenCount errorOffset : Int)
    (afterArgumentsWellFormed : StateWellFormed afterArguments)
    (argumentsExecution : ArgumentsEvaluateTo verifiedFrontendCore before
      arguments [.signed .i32 tokenCount, .signed .i32 errorOffset]
      afterArguments) :
    let bindings := pairBindings tokenCount errorOffset
    let after := constructorAfter afterArguments bindings
    Evaluates verifiedFrontendCore before
      (.call lexicalFailureFunction.id arguments)
      (value 1 tokenCount errorOffset) after ∧
    ModifiesOnly CellSet.empty afterArguments after ∧
    StateWellFormed after := by
  apply pureConstructorCall
    (argumentsValues := [.signed .i32 tokenCount, .signed .i32 errorOffset])
    lexicalFailureFunction
    (pairBindings tokenCount errorOffset) lexicalFailureCoreBody
    (value 1 tokenCount errorOffset) core_finds_lexicalFailure
  · rw [lexicalFailure_shape.2.1]
    rfl
  · exact lexicalFailure_shape.2.2.2
  · exact afterArgumentsWellFormed
  · exact argumentsExecution
  · exact lexicalFailureBody_executes afterArguments
      afterArgumentsWellFormed tokenCount errorOffset

theorem outputFullCall_executes
    (before afterArguments : State) (arguments : List Expr)
    (tokenCount sourceOffset : Int)
    (afterArgumentsWellFormed : StateWellFormed afterArguments)
    (argumentsExecution : ArgumentsEvaluateTo verifiedFrontendCore before
      arguments [.signed .i32 tokenCount, .signed .i32 sourceOffset]
      afterArguments) :
    let bindings := pairBindings tokenCount sourceOffset
    let after := constructorAfter afterArguments bindings
    Evaluates verifiedFrontendCore before
      (.call outputFullFunction.id arguments)
      (value 2 tokenCount sourceOffset) after ∧
    ModifiesOnly CellSet.empty afterArguments after ∧
    StateWellFormed after := by
  apply pureConstructorCall
    (argumentsValues := [.signed .i32 tokenCount, .signed .i32 sourceOffset])
    outputFullFunction
    (pairBindings tokenCount sourceOffset) outputFullCoreBody
    (value 2 tokenCount sourceOffset) core_finds_outputFull
  · rw [outputFull_shape.2.1]
    rfl
  · exact outputFull_shape.2.2.2
  · exact afterArgumentsWellFormed
  · exact argumentsExecution
  · exact outputFullBody_executes afterArguments afterArgumentsWellFormed
      tokenCount sourceOffset

def completedCalls : CallModel where
  evaluate := fun world function arguments =>
    if function = completedFunction.id then
      match arguments with
      | [.signed .i32 tokenCount] => .ok (value 0 tokenCount 0, world)
      | _ => .error .typeMismatch
    else .error .invalidPointer

def lexicalFailureCalls : CallModel where
  evaluate := fun world function arguments =>
    if function = lexicalFailureFunction.id then
      match arguments with
      | [.signed .i32 tokenCount, .signed .i32 errorOffset] =>
          .ok (value 1 tokenCount errorOffset, world)
      | _ => .error .typeMismatch
    else .error .invalidPointer

def outputFullCalls : CallModel where
  evaluate := fun world function arguments =>
    if function = outputFullFunction.id then
      match arguments with
      | [.signed .i32 tokenCount, .signed .i32 sourceOffset] =>
          .ok (value 2 tokenCount sourceOffset, world)
      | _ => .error .typeMismatch
    else .error .invalidPointer

theorem completedCalls_at_count (world : World) (tokenCount : Int) :
    completedCalls.evaluate world completedFunction.id
        [.signed .i32 tokenCount] =
      .ok (value 0 tokenCount 0, world) := by rfl

theorem lexicalFailureCalls_at_offsets (world : World)
    (tokenCount errorOffset : Int) :
    lexicalFailureCalls.evaluate world lexicalFailureFunction.id
        [.signed .i32 tokenCount, .signed .i32 errorOffset] =
      .ok (value 1 tokenCount errorOffset, world) := by rfl

theorem outputFullCalls_at_offsets (world : World)
    (tokenCount sourceOffset : Int) :
    outputFullCalls.evaluate world outputFullFunction.id
        [.signed .i32 tokenCount, .signed .i32 sourceOffset] =
      .ok (value 2 tokenCount sourceOffset, world) := by rfl

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

theorem completedCall_soundness :
    Lanius.FunctionalView.Core.EffectfulStateful.CallSoundness
      verifiedFrontendCore completedCalls := by
  constructor
  · intro arity layout localCell beforeWorld afterWorld environment before
      afterArguments function arguments argumentsValues result argumentWrites
      afterArgumentsWellFormed represented argumentsExecution argumentsEffect
      evaluated
    simp only [completedCalls] at evaluated
    split at evaluated
    next functionEq =>
      split at evaluated
      next tokenCount =>
        obtain ⟨rfl, rfl⟩ := evaluated
        subst function
        obtain ⟨callExecution, callEffect, afterWellFormed⟩ :=
          completedCall_executes before afterArguments
            (toCoreExprs layout arguments) tokenCount
            afterArgumentsWellFormed argumentsExecution
        exact ⟨_, CellSet.union argumentWrites CellSet.empty, callExecution,
          afterWellFormed,
          preserveRepresentation afterArgumentsWellFormed represented
            callEffect,
          argumentsEffect.trans callEffect⟩
      next => contradiction
    next => contradiction
  · intro beforeWorld afterWorld function arguments result evaluated cell
    simp only [completedCalls] at evaluated
    split at evaluated
    next =>
      split at evaluated
      next =>
        obtain ⟨rfl, rfl⟩ := evaluated
        rfl
      next => contradiction
    next => contradiction

theorem lexicalFailureCall_soundness :
    Lanius.FunctionalView.Core.EffectfulStateful.CallSoundness
      verifiedFrontendCore lexicalFailureCalls := by
  constructor
  · intro arity layout localCell beforeWorld afterWorld environment before
      afterArguments function arguments argumentsValues result argumentWrites
      afterArgumentsWellFormed represented argumentsExecution argumentsEffect
      evaluated
    simp only [lexicalFailureCalls] at evaluated
    split at evaluated
    next functionEq =>
      split at evaluated
      next tokenCount errorOffset =>
        obtain ⟨rfl, rfl⟩ := evaluated
        subst function
        obtain ⟨callExecution, callEffect, afterWellFormed⟩ :=
          lexicalFailureCall_executes before afterArguments
            (toCoreExprs layout arguments) tokenCount errorOffset
            afterArgumentsWellFormed argumentsExecution
        exact ⟨_, CellSet.union argumentWrites CellSet.empty, callExecution,
          afterWellFormed,
          preserveRepresentation afterArgumentsWellFormed represented
            callEffect,
          argumentsEffect.trans callEffect⟩
      next => contradiction
    next => contradiction
  · intro beforeWorld afterWorld function arguments result evaluated cell
    simp only [lexicalFailureCalls] at evaluated
    split at evaluated
    next =>
      split at evaluated
      next =>
        obtain ⟨rfl, rfl⟩ := evaluated
        rfl
      next => contradiction
    next => contradiction

theorem outputFullCall_soundness :
    Lanius.FunctionalView.Core.EffectfulStateful.CallSoundness
      verifiedFrontendCore outputFullCalls := by
  constructor
  · intro arity layout localCell beforeWorld afterWorld environment before
      afterArguments function arguments argumentsValues result argumentWrites
      afterArgumentsWellFormed represented argumentsExecution argumentsEffect
      evaluated
    simp only [outputFullCalls] at evaluated
    split at evaluated
    next functionEq =>
      split at evaluated
      next tokenCount sourceOffset =>
        obtain ⟨rfl, rfl⟩ := evaluated
        subst function
        obtain ⟨callExecution, callEffect, afterWellFormed⟩ :=
          outputFullCall_executes before afterArguments
            (toCoreExprs layout arguments) tokenCount sourceOffset
            afterArgumentsWellFormed argumentsExecution
        exact ⟨_, CellSet.union argumentWrites CellSet.empty, callExecution,
          afterWellFormed,
          preserveRepresentation afterArgumentsWellFormed represented
            callEffect,
          argumentsEffect.trans callEffect⟩
      next => contradiction
    next => contradiction
  · intro beforeWorld afterWorld function arguments result evaluated cell
    simp only [outputFullCalls] at evaluated
    split at evaluated
    next =>
      split at evaluated
      next =>
        obtain ⟨rfl, rfl⟩ := evaluated
        rfl
      next => contradiction
    next => contradiction

/-- One routed registry for the three constructors used by `lex_into`. -/
def constructorCalls : CallModel :=
  CallModel.route (fun function => function == completedFunction.id)
    completedCalls
    (CallModel.route (fun function => function == lexicalFailureFunction.id)
      lexicalFailureCalls outputFullCalls)

theorem constructorCall_soundness :
    Lanius.FunctionalView.Core.EffectfulStateful.CallSoundness
      verifiedFrontendCore constructorCalls := by
  exact Lanius.FunctionalView.Core.EffectfulStateful.CallSoundness.route
    completedCall_soundness
    (Lanius.FunctionalView.Core.EffectfulStateful.CallSoundness.route
      lexicalFailureCall_soundness outputFullCall_soundness)

theorem constructorCalls_completed (world : World) (tokenCount : Int) :
    constructorCalls.evaluate world completedFunction.id
        [.signed .i32 tokenCount] =
      .ok (value 0 tokenCount 0, world) := by rfl

theorem constructorCalls_lexicalFailure (world : World)
    (tokenCount errorOffset : Int) :
    constructorCalls.evaluate world lexicalFailureFunction.id
        [.signed .i32 tokenCount, .signed .i32 errorOffset] =
      .ok (value 1 tokenCount errorOffset, world) := by rfl

theorem constructorCalls_outputFull (world : World)
    (tokenCount sourceOffset : Int) :
    constructorCalls.evaluate world outputFullFunction.id
        [.signed .i32 tokenCount, .signed .i32 sourceOffset] =
      .ok (value 2 tokenCount sourceOffset, world) := by rfl

end Lanius.Extraction.RawLexer.Results.Semantics
