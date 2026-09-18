import Lanius.Extraction.Decimal.FinishEvaluation
import Lanius.FunctionalViewCoreCheckedSimulation
import Lanius.FunctionalViewCoreFreshSimulation
import Lanius.FunctionalViewCoreCallFrame

namespace Lanius.Extraction.Decimal.FinishSemantics

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
open Lanius.FunctionalView.Core.Effectful
open Lanius.FunctionalView.Core.EffectfulStateful
open Lanius.FunctionalView.FreshSimulation
open Lanius.Extraction.Decimal
open Lanius.Extraction.Decimal.EvaluationModel

noncomputable def callModel (source : List Byte) : CallModel := by
  classical
  exact { evaluate := fun world function values =>
    if world.i32Slice? 0 = some (sourceIntegers source) then
      if function = Functions.finishDecimalFunction.id then
        match values with
        | [.slice (.scalar (.signed .i32)) cell projections sliceBase length,
            .signed .i32 sourceLength, .signed .i32 integerEnd] =>
            if cell = 0 ∧ projections = [] ∧ sliceBase = 0 ∧
                length = source.length ∧
                sourceLength = Int.ofNat source.length ∧
                0 ≤ integerEnd ∧ integerEnd.toNat ≤ source.length ∧
                source.length ≤ 2147483647 then
              .ok (encoded (finishDecimal source integerEnd.toNat), world)
            else .error .typeMismatch
        | _ => .error .typeMismatch
      else .error .invalidPointer
    else .error .invalidPointer }

@[simp] theorem evaluate
    (world : ReadOnly.World) (source : List Byte) (integerEnd : Nat)
    (sourceFound : world.i32Slice? 0 = some (sourceIntegers source))
    (sourceBound : source.length ≤ 2147483647)
    (startBound : integerEnd ≤ source.length) :
    (callModel source).evaluate world Functions.finishDecimalFunction.id
        (arguments source integerEnd) =
      .ok (encoded (finishDecimal source integerEnd), world) := by
  have integerEndBound : integerEnd ≤ 2147483647 := by omega
  simp [callModel, arguments, EvaluationModel.sourceSlice,
    DigitRunModel.sourceSlice, Program.i32Type, sourceFound, sourceBound,
    startBound, integerEndBound]

private theorem call_success
    (evaluated : (callModel source).evaluate world function values =
      .ok (result, afterWorld)) :
    ∃ integerEnd : Nat,
      world.i32Slice? 0 = some (sourceIntegers source) ∧
      function = Functions.finishDecimalFunction.id ∧
      values = arguments source integerEnd ∧
      source.length ≤ 2147483647 ∧ integerEnd ≤ source.length ∧
      result = encoded (finishDecimal source integerEnd) ∧
      afterWorld = world := by
  simp only [callModel] at evaluated
  split at evaluated
  next sourceFound =>
    split at evaluated
    next functionEq =>
      split at evaluated
      next cell projections sliceBase length sourceLength integerEnd =>
        split at evaluated
        next valid =>
          obtain ⟨rfl, rfl⟩ := evaluated
          let integerEndNat := integerEnd.toNat
          have integerEndEq : (integerEndNat : Int) = integerEnd := by
            simp [integerEndNat]
            omega
          refine ⟨integerEndNat, sourceFound, functionEq, ?_,
            valid.2.2.2.2.2.2.2, valid.2.2.2.2.2.2.1, ?_, rfl⟩
          · simp [arguments, EvaluationModel.sourceSlice,
              DigitRunModel.sourceSlice, Program.i32Type, integerEndNat,
              integerEndEq, valid.1, valid.2.1, valid.2.2.1,
              valid.2.2.2.1, valid.2.2.2.2.1]
          · simp [integerEndNat, integerEndEq]
        next => contradiction
      next => contradiction
    next => contradiction
  next => contradiction

theorem verifiedFrontendCore_finds :
    verifiedFrontendCore.function? Functions.finishDecimalFunction.id =
      some Functions.finishDecimalFunction := by rfl

theorem finishDecimalFunction_parameters :
    Functions.finishDecimalFunction.parameters =
      [(0, .slice Program.i32Type), (1, Program.i32Type),
        (2, Program.i32Type)] := by
  rfl

theorem finishDecimalFunction_has_body :
    Functions.finishDecimalFunction.body =
      some Functions.finishDecimalBody := by
  rfl

theorem framePreservingCallSoundness (source : List Byte) :
    FramePreservingCallSoundness verifiedFrontendCore (callModel source) := by
  constructor
  intro arity layout localCell beforeWorld afterWorld callerEnvironment before
    afterArguments function sourceArguments values result argumentWrites
    afterArgumentsWellFormed represented argumentsExecution argumentsEffect
    evaluated
  obtain ⟨integerEnd, sourceFound, rfl, rfl, sourceBound, startBound,
      rfl, rfl⟩ := call_success evaluated
  have functionalEvaluation :=
    FinishEvaluation.finishDecimal_evaluates source afterWorld integerEnd
      sourceFound sourceBound startBound
  apply CheckedSimulation.callPreservesFrame
    (calleeEnvironment := environment source integerEnd)
    (FinishEvaluationModel.helperCalls_framePreserving source)
    argumentsExecution argumentsEffect verifiedFrontendCore_finds
    (by
      rw [finishDecimalFunction_parameters]
      simp [bindParameters, parameterBindings, environment, arguments,
        EvaluationModel.sourceSlice, DigitRunModel.sourceSlice,
        Program.i32Type, List.finRange])
    finishDecimalFunction_has_body functionalEvaluation (by decide +kernel)
    Commands.finishDecimalReadable_toCore_exactly afterArgumentsWellFormed
    represented

theorem worldPreserving (source : List Byte) :
    WorldPreserving (callModel source) := by
  intro beforeWorld afterWorld function values value evaluated
  obtain ⟨integerEnd, sourceFound, functionEq, valuesEq, sourceBound,
      startBound, resultEq, afterEq⟩ := call_success evaluated
  exact afterEq

theorem callSoundness (source : List Byte) :
    EffectfulStateful.CallSoundness verifiedFrontendCore (callModel source) :=
  (framePreservingCallSoundness source).toCallSoundness
    (worldPreserving source)

end Lanius.Extraction.Decimal.FinishSemantics
