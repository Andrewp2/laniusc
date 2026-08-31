import Lanius.Extraction.Number.Evaluation
import Lanius.Extraction.Decimal.ConcreteSemantics
import Lanius.FunctionalViewCoreFreshSimulation
import Lanius.FunctionalViewCoreCallFrame

namespace Lanius.Extraction.Number.Calls

open Lanius
open Lanius.Core
open Lanius.Semantics
open Lanius.Properties
open Lanius.Separation
open Lanius.CallContracts
open Lanius.Extraction
open Lanius.FunctionalView
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.Stateful
open Lanius.FunctionalView.Core.Effectful
open Lanius.FunctionalView.Core.EffectfulStateful
open Lanius.FunctionalView.FreshSimulation

/-! # Checked calls for `number.lani`

The main number-scanner registry is useful only when its decimal and digit
helpers are backed by checked source functions.  This module proves that
boundary once, parametrically over the concrete helper registry.  The final
frontend registry below instantiates the parameters with Decimal's checked
registry; no helper is replaced by a handwritten Core body.
-/

private theorem scanNumberFunction_parameters :
    Functions.scanNumberFunction.parameters =
      [(0, .slice Compiler.Lexer.Program.i32Type),
        (1, Compiler.Lexer.Program.i32Type),
        (2, Compiler.Lexer.Program.i32Type)] := by
  native_decide

private theorem scanLeadingDotNumberFunction_parameters :
    Functions.scanLeadingDotNumberFunction.parameters =
      [(0, .slice Compiler.Lexer.Program.i32Type),
        (1, Compiler.Lexer.Program.i32Type),
        (2, Compiler.Lexer.Program.i32Type)] := by
  native_decide

private theorem parameterBindings_match
    (source : List Compiler.Lexer.Byte) (start : Nat) (function : Function)
    (parameters : function.parameters =
      [(0, .slice Compiler.Lexer.Program.i32Type),
        (1, Compiler.Lexer.Program.i32Type),
        (2, Compiler.Lexer.Program.i32Type)]) :
    bindParameters function.parameters (Model.argumentValues source start) =
      some (parameterBindings (Model.environment source start)) := by
  rw [parameters]
  simp [bindParameters, Model.argumentValues, Model.environment,
    parameterBindings, List.finRange]

/-- The two checked number bodies preserve every cell visible to their caller,
provided every nested digit/decimal helper call does the same. -/
theorem mainFramePreservingCallSoundness
    (source : List Compiler.Lexer.Byte) (helpers : CallModel)
    (helperContract : source.length ≤ 2147483647 → ∀ world,
      world.i32Slice? 0 = some (Model.sourceIntegers source) →
        Evaluation.HelperContract helpers source world)
    (helperSoundness :
      FramePreservingCallSoundness verifiedFrontendCore helpers) :
    FramePreservingCallSoundness verifiedFrontendCore
      (Model.numberCalls source) := by
  constructor
  intro arity layout localCell beforeWorld afterWorld callerEnvironment before
    afterArguments function sourceArguments values result argumentWrites
    afterArgumentsWellFormed represented argumentsExecution argumentsEffect
    evaluated
  obtain ⟨startInt, rfl, startNonnegative, sourceBound, startInBounds,
      sourceFound, selected, afterWorldEq⟩ := Model.numberCalls_success evaluated
  subst afterWorld
  let start := startInt.toNat
  have startEq : (start : Int) = startInt := by
    simp [start]
    omega
  let calleeEnvironment := Model.environment source start
  let bindings := parameterBindings calleeEnvironment
  let callee := enterCall afterArguments bindings
  have calleeRepresented : Representation identityLayout
      (callLocalCells afterArguments) beforeWorld calleeEnvironment callee := by
    simpa [callee, bindings] using
      represented.enterCallParameters afterArgumentsWellFormed
        (environment := calleeEnvironment)
  have calleeWellFormed : StateWellFormed callee := by
    simpa [callee, bindings] using
      enterCall_preserves_wellFormed afterArgumentsWellFormed
  let operations := operationSoundness verifiedFrontendCore helpers
    helperSoundness
  rcases selected with selected | selected
  · obtain ⟨rfl, rfl⟩ := selected
    have functionalRun := Evaluation.scanNumber_run
      (helperContract sourceBound beforeWorld sourceFound) sourceBound sourceFound
      startInBounds
    have functionalEvaluation := Stateful.Acyclic.run?_sound functionalRun
    have simulation := commandSoundness operations functionalEvaluation
      (by native_decide)
      calleeRepresented (LayoutBelow.identity (arity := 3)) calleeWellFormed
      (frontier := afterArguments.nextCell)
      (by
        intro index
        simp [callLocalCells])
      (by
        simpa [callee] using
          (enterCall_effect afterArguments bindings).nextCell)
    obtain ⟨completed, bodyExecution, completedWellFormed,
        completedRepresented, bodyEffect⟩ := simulation
    rw [Commands.scanNumber_toCore_exactly] at bodyExecution
    change Executes verifiedFrontendCore callee Functions.scanNumberBody
      (.returned (some (Model.encoded (Compiler.Lexer.scanNumber source start))))
      completed at bodyExecution
    have callExecution : Evaluates verifiedFrontendCore before
        (.call Functions.scanNumberFunction.id
          (toCoreExprs layout sourceArguments))
        (Model.encoded (Compiler.Lexer.scanNumber source start))
        (restoreLocals afterArguments completed) := by
      apply evaluatesCallReturned
        (bindings := bindings) (body := Functions.scanNumberBody)
        argumentsExecution (by rfl)
      · rw [show [Model.sourceSlice source,
            .signed .i32 source.length, .signed .i32 startInt] =
            Model.argumentValues source start by
          simp [Model.argumentValues, startEq]]
        simpa [bindings, calleeEnvironment] using
          parameterBindings_match source start Functions.scanNumberFunction
            scanNumberFunction_parameters
      · rfl
      · simpa [callee, bindings] using bodyExecution
    obtain ⟨afterWellFormed, afterRepresented, callEffect⟩ :=
      represented.restoreFreshCall afterArgumentsWellFormed
        completedWellFormed (bindings := bindings) bodyEffect (by
          intro cell written
          exact written)
    exact ⟨restoreLocals afterArguments completed, callExecution,
      afterWellFormed, afterRepresented,
      argumentsEffect.trans_same
        (callEffect.weaken CellSet.empty_subset)⟩
  · obtain ⟨rfl, rfl⟩ := selected
    have functionalRun := Evaluation.scanLeadingDotNumber_run
      (helperContract sourceBound beforeWorld sourceFound) sourceBound sourceFound
      startInBounds
    have functionalEvaluation := Stateful.Acyclic.run?_sound functionalRun
    have simulation := commandSoundness operations functionalEvaluation
      (by native_decide)
      calleeRepresented (LayoutBelow.identity (arity := 3)) calleeWellFormed
      (frontier := afterArguments.nextCell)
      (by
        intro index
        simp [callLocalCells])
      (by
        simpa [callee] using
          (enterCall_effect afterArguments bindings).nextCell)
    obtain ⟨completed, bodyExecution, completedWellFormed,
        completedRepresented, bodyEffect⟩ := simulation
    rw [Commands.scanLeadingDotNumber_toCore_exactly] at bodyExecution
    change Executes verifiedFrontendCore callee
      Functions.scanLeadingDotNumberBody
      (.returned (some
        (Model.encoded (Compiler.Lexer.scanLeadingDotNumber source start))))
      completed at bodyExecution
    have callExecution : Evaluates verifiedFrontendCore before
        (.call Functions.scanLeadingDotNumberFunction.id
          (toCoreExprs layout sourceArguments))
        (Model.encoded (Compiler.Lexer.scanLeadingDotNumber source start))
        (restoreLocals afterArguments completed) := by
      apply evaluatesCallReturned
        (bindings := bindings) (body := Functions.scanLeadingDotNumberBody)
        argumentsExecution (by rfl)
      · rw [show [Model.sourceSlice source,
            .signed .i32 source.length, .signed .i32 startInt] =
            Model.argumentValues source start by
          simp [Model.argumentValues, startEq]]
        simpa [bindings, calleeEnvironment] using
          parameterBindings_match source start
            Functions.scanLeadingDotNumberFunction
            scanLeadingDotNumberFunction_parameters
      · rfl
      · simpa [callee, bindings] using bodyExecution
    obtain ⟨afterWellFormed, afterRepresented, callEffect⟩ :=
      represented.restoreFreshCall afterArgumentsWellFormed
        completedWellFormed (bindings := bindings) bodyEffect (by
          intro cell written
          exact written)
    exact ⟨restoreLocals afterArguments completed, callExecution,
      afterWellFormed, afterRepresented,
      argumentsEffect.trans_same
        (callEffect.weaken CellSet.empty_subset)⟩

/-- Ordinary checked-call soundness follows from the stronger caller-frame
preservation theorem. -/
theorem mainCallSoundness
    (source : List Compiler.Lexer.Byte) (helpers : CallModel)
    (helperContract : source.length ≤ 2147483647 → ∀ world,
      world.i32Slice? 0 = some (Model.sourceIntegers source) →
        Evaluation.HelperContract helpers source world)
    (helperSoundness :
      FramePreservingCallSoundness verifiedFrontendCore helpers) :
    EffectfulStateful.CallSoundness verifiedFrontendCore
      (Model.numberCalls source) := by
  constructor
  · intro arity layout localCell beforeWorld afterWorld environment before
      afterArguments function arguments values result argumentWrites
      afterArgumentsWellFormed represented argumentsExecution argumentsEffect
      evaluated
    obtain ⟨after, callExecution, afterWellFormed, afterRepresented,
        callEffect⟩ :=
      (mainFramePreservingCallSoundness source helpers helperContract
        helperSoundness).call afterArgumentsWellFormed represented
          argumentsExecution argumentsEffect evaluated
    exact ⟨after, argumentWrites, callExecution, afterWellFormed,
      afterRepresented, callEffect⟩
  · intro beforeWorld afterWorld function values result evaluated cell
    obtain ⟨start, valuesEq, startNonnegative, sourceBound, startInBounds,
        sourceFound, selected, rfl⟩ := Model.numberCalls_success evaluated
    rfl

/-! ## Concrete frontend registry -/

def isNumberEntry (function : FunctionId) : Bool :=
  function = Functions.scanNumberFunction.id ∨
    function = Functions.scanLeadingDotNumberFunction.id

noncomputable def numberCalls
    (source : List Compiler.Lexer.Byte) : CallModel :=
  CallModel.route isNumberEntry (Model.numberCalls source)
    (Decimal.ConcreteSemantics.callModel source)

private theorem encoded_eq_decimal (result : Compiler.Lexer.NumberScanResult) :
    Model.encoded result = Decimal.EvaluationModel.encoded result := by
  cases result with
  | failure => rfl
  | success kind => cases kind <;> rfl

private theorem concreteHelperContract
    (source : List Compiler.Lexer.Byte)
    (world : ReadOnly.World)
    (sourceFound : world.i32Slice? 0 = some (Model.sourceIntegers source))
    (sourceBound : source.length ≤ 2147483647) :
    Evaluation.HelperContract
      (Decimal.ConcreteSemantics.callModel source) source world := by
  have decimalSourceFound : world.i32Slice? 0 = some
      (Decimal.EvaluationModel.sourceIntegers source) := by
    simpa [Model.sourceIntegers, Decimal.EvaluationModel.sourceIntegers,
      Decimal.DigitRunModel.sourceIntegers] using sourceFound
  constructor
  · intro start base startBound baseBound
    simpa [Model.sourceSlice, Decimal.EvaluationModel.sourceSlice,
      Decimal.DigitRunModel.sourceSlice, Compiler.Lexer.Program.i32Type]
      using Decimal.ConcreteSemantics.scanDigitRun source world start base
        decimalSourceFound sourceBound startBound baseBound
  · intro result resultBound
    cases result with
    | success finish =>
        exact Decimal.ConcreteSemantics.digitSucceeded source world
          (.success finish) resultBound
    | failure error =>
        exact Decimal.ConcreteSemantics.digitSucceeded source world
          (.failure error) resultBound
  · intro finish finishBound
    exact Decimal.ConcreteSemantics.digitEnd source world finish finishBound
  · intro error errorBound
    exact Decimal.ConcreteSemantics.digitError source world error errorBound
  · intro error errorBound
    rw [encoded_eq_decimal]
    exact Decimal.ConcreteSemantics.numberFailure source world error errorBound
  · intro finish finishBound
    rw [encoded_eq_decimal]
    exact Decimal.ConcreteSemantics.integerScan source world finish finishBound
  · intro finish finishBound
    rw [encoded_eq_decimal]
    exact Decimal.ConcreteSemantics.floatScan source world finish finishBound
  · intro start startInBounds
    rw [encoded_eq_decimal]
    simpa [Model.sourceSlice,
      Decimal.EvaluationModel.arguments,
      Decimal.EvaluationModel.sourceSlice,
      Decimal.DigitRunModel.sourceSlice,
      Compiler.Lexer.Program.i32Type]
      using Decimal.ConcreteSemantics.scanExponent source world start
        decimalSourceFound sourceBound startInBounds
  · intro start startBound
    rw [encoded_eq_decimal]
    simpa [Model.sourceSlice,
      Decimal.EvaluationModel.arguments,
      Decimal.EvaluationModel.sourceSlice,
      Decimal.DigitRunModel.sourceSlice,
      Compiler.Lexer.Program.i32Type]
      using Decimal.ConcreteSemantics.finishDecimal source world start
        decimalSourceFound sourceBound startBound

/-- Concrete checked Number calls preserve every caller-visible cell. -/
theorem numberFramePreservingCallSoundness
    (source : List Compiler.Lexer.Byte) :
    FramePreservingCallSoundness verifiedFrontendCore
      (numberCalls source) := by
  apply FramePreservingCallSoundness.route
  · apply mainFramePreservingCallSoundness source
      (Decimal.ConcreteSemantics.callModel source)
    · intro sourceBound world sourceFound
      exact concreteHelperContract source world sourceFound sourceBound
    · exact Decimal.ConcreteSemantics.framePreservingCallSoundness source
  · exact Decimal.ConcreteSemantics.framePreservingCallSoundness source

theorem numberCall_soundness
    (source : List Compiler.Lexer.Byte) :
    EffectfulStateful.CallSoundness verifiedFrontendCore
      (numberCalls source) := by
  apply EffectfulStateful.CallSoundness.route
  · apply mainCallSoundness source
      (Decimal.ConcreteSemantics.callModel source)
    · intro sourceBound world sourceFound
      exact concreteHelperContract source world sourceFound sourceBound
    · exact Decimal.ConcreteSemantics.framePreservingCallSoundness source
  · exact Decimal.ConcreteSemantics.callSoundness source

@[simp] theorem numberCalls_scanNumber
    (source : List Compiler.Lexer.Byte) (world : ReadOnly.World) (start : Nat)
    (sourceFound : world.i32Slice? 0 = some (Model.sourceIntegers source))
    (sourceBound : source.length ≤ 2147483647)
    (startInBounds : start < source.length) :
    (numberCalls source).evaluate world Functions.scanNumberFunction.id
        (Model.argumentValues source start) =
      .ok (Model.encoded (Compiler.Lexer.scanNumber source start), world) := by
  simp only [numberCalls, CallModel.route]
  rw [if_pos (by native_decide)]
  exact Model.numberCalls_scanNumber source world start sourceFound sourceBound
    startInBounds

@[simp] theorem numberCalls_scanLeadingDotNumber
    (source : List Compiler.Lexer.Byte) (world : ReadOnly.World) (start : Nat)
    (sourceFound : world.i32Slice? 0 = some (Model.sourceIntegers source))
    (sourceBound : source.length ≤ 2147483647)
    (startInBounds : start < source.length) :
    (numberCalls source).evaluate world
        Functions.scanLeadingDotNumberFunction.id
        (Model.argumentValues source start) =
      .ok (Model.encoded
        (Compiler.Lexer.scanLeadingDotNumber source start), world) := by
  simp only [numberCalls, CallModel.route]
  rw [if_pos (by native_decide)]
  exact Model.numberCalls_scanLeadingDotNumber source world start sourceFound
    sourceBound startInBounds

end Lanius.Extraction.Number.Calls
