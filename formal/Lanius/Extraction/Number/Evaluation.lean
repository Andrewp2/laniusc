import Lanius.Extraction.Number.Commands
import Lanius.Extraction.Number.Model
import Lanius.FunctionalViewStatefulAcyclic

namespace Lanius.Extraction.Number.Evaluation

open Lanius
open Lanius.Core
open Lanius.Compiler.Lexer
open Lanius.Compiler.Lexer.Program
open Lanius.Extraction
open Lanius.FunctionalView
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.Effectful
open Lanius.FunctionalView.Core.Stateful

abbrev World := Lanius.FunctionalView.Core.ReadOnly.World

structure HelperContract (calls : CallModel) (source : List Byte) (world : World) : Prop where
  digitRun : ∀ (start base : Nat), start ≤ 2147483647 → base ≤ 2147483647 →
    calls.evaluate world extractedScanDigitRunFunction.id
        [Model.sourceSlice source, .signed .i32 source.length,
          .signed .i32 start, .signed .i32 base] =
      .ok (digitScanValue (scanDigitRun source start base),
        world)
  digitSucceeded : ∀ result,
    (match result with
      | .success offset | .failure offset => offset ≤ 2147483647) →
    calls.evaluate world
        Lexer.Digits.digitScanSucceededFunction.id [digitScanValue result] =
      .ok (.boolean (match result with
        | .success _ => true
        | .failure _ => false), world)
  digitEnd : ∀ (finish : Nat), finish ≤ 2147483647 →
    calls.evaluate world
        Lexer.Digits.digitScanEndOffsetFunction.id
        [digitScanValue (.success finish)] =
      .ok (.signed .i32 finish, world)
  digitError : ∀ (error : Nat), error ≤ 2147483647 →
    calls.evaluate world
        Lexer.Digits.digitScanErrorOffsetFunction.id
        [digitScanValue (.failure error)] =
      .ok (.signed .i32 error, world)
  numberFailure : ∀ (error : Nat), error ≤ 2147483647 →
    calls.evaluate world
        Decimal.Functions.numberFailureFunction.id [.signed .i32 error] =
      .ok (Model.encoded (.failure error), world)
  integerScan : ∀ (finish : Nat), finish ≤ 2147483647 →
    calls.evaluate world
        Decimal.Functions.integerScanFunction.id [.signed .i32 finish] =
      .ok (Model.encoded (.success .integer finish), world)
  floatScan : ∀ (finish : Nat), finish ≤ 2147483647 →
    calls.evaluate world
        Decimal.Functions.floatScanFunction.id [.signed .i32 finish] =
      .ok (Model.encoded (.success .float finish), world)
  scanExponent : ∀ (start : Nat), start < source.length →
    calls.evaluate world
        Decimal.Functions.scanExponentFunction.id
        [Model.sourceSlice source, .signed .i32 source.length,
          .signed .i32 start] =
      .ok (Model.encoded (scanExponent source start), world)
  finishDecimal : ∀ (start : Nat), start ≤ source.length →
    calls.evaluate world
        Decimal.Functions.finishDecimalFunction.id
        [Model.sourceSlice source, .signed .i32 source.length,
          .signed .i32 start] =
      .ok (Model.encoded (finishDecimal source start), world)

private theorem digitTailResult_le
    (scan : DigitTailScan base input offset result) :
    match result with
    | .success finish | .failure finish => finish ≤ offset + input.length := by
  induction scan with
  | eof => simp
  | digit byte rest offset result accepted tail induction =>
      cases result <;> simp_all <;> omega
  | separator underscore next after offset result isSeparator accepted tail
      induction =>
      cases result <;> simp_all <;> omega
  | separatorAtEof => simp
  | separatorBeforeInvalid => simp
  | boundary => simp

private theorem digitRunScanResult_bound
    (scan : DigitRunScan source start base result)
    (sourceBound : source.length ≤ 2147483647)
    (startBound : start ≤ 2147483647) :
    match result with
    | .success finish | .failure finish => finish ≤ 2147483647 := by
  cases scan with
  | missing => exact startBound
  | invalid => exact startBound
  | valid first rest result input accepted tail =>
      have lengths := congrArg List.length input
      simp only [List.length_drop, List.length_cons] at lengths
      have resultBound := digitTailResult_le tail
      cases result <;> simp_all <;> omega

private theorem digitRunResult_bound
    (sourceBound : source.length ≤ 2147483647)
    (startBound : start ≤ 2147483647) :
    match scanDigitRun source start base with
    | .success finish | .failure finish => finish ≤ 2147483647 := by
  cases resultEq : scanDigitRun source start base with
  | success finish =>
      have scan := scanDigitRun_spec source start base
      rw [resultEq] at scan
      exact digitRunScanResult_bound scan sourceBound startBound
  | failure error =>
      have scan := scanDigitRun_spec source start base
      rw [resultEq] at scan
      exact digitRunScanResult_bound scan sourceBound startBound

private theorem digitRunSuccess_le_source
    (result : scanDigitRun source start base = .success finish) :
    finish ≤ source.length := by
  have scan := scanDigitRun_spec source start base
  rw [result] at scan
  cases scan with
  | valid first rest result input accepted tail =>
      have lengths := congrArg List.length input
      simp only [List.length_drop, List.length_cons] at lengths
      have finishBound := digitTailResult_le tail
      simp only at finishBound
      omega

abbrev termMachine (calls : CallModel) : FunctionalView.Machine Core.signature :=
  Effectful.machine verifiedFrontendCore calls

abbrev commandMachine (calls : CallModel) :=
  machineWith verifiedFrontendCore
    (Effectful.evaluateOperation verifiedFrontendCore calls)

@[simp] private theorem setLast_push
    (environment : Env arity) (oldValue newValue : Value) :
    Stateful.Env.set (environment.push oldValue) ⟨arity, by omega⟩ newValue =
      environment.push newValue := by
  funext index
  by_cases last : index = Fin.last arity
  · subst index
    simp [Stateful.Env.set, Env.push, Fin.last]
  · have before : index.val < arity := by
      have bounded : index.val ≤ arity := Nat.lt_succ_iff.mp index.isLt
      have valueNot : index.val ≠ arity := by
        intro equal
        apply last
        apply Fin.ext
        simpa [Fin.last] using equal
      omega
    have different : index ≠ ⟨arity, by omega⟩ := by
      intro equal
      have valueEqual : index.val = arity := by
        simpa using congrArg Fin.val equal
      omega
    simp [Stateful.Env.set, Env.push, different, before]

@[simp] private theorem setSlotFour_push
    (environment : Env 4) (oldValue newValue : Value) :
    Stateful.Env.set (environment.push oldValue) (4 : Fin 5) newValue =
      environment.push newValue := by
  simpa using setLast_push environment oldValue newValue

private theorem digitCall_evaluates
    (contract : HelperContract calls source world)
    (currentEnvironment : Env arity)
    (sourceTerm boundTerm startTerm baseTerm : Term signature arity)
    (start base : Nat)
    (startBound : start ≤ 2147483647)
    (baseBound : base ≤ 2147483647)
    (sourceEvaluation : Term.evaluate (Effectful.machine verifiedFrontendCore calls)
      world currentEnvironment sourceTerm =
        .ok (Model.sourceSlice source, world))
    (boundEvaluation : Term.evaluate (Effectful.machine verifiedFrontendCore calls)
      world currentEnvironment boundTerm =
        .ok (.signed .i32 source.length, world))
    (startEvaluation : Term.evaluate (Effectful.machine verifiedFrontendCore calls)
      world currentEnvironment startTerm =
        .ok (.signed .i32 start, world))
    (baseEvaluation : Term.evaluate (Effectful.machine verifiedFrontendCore calls)
      world currentEnvironment baseTerm =
        .ok (.signed .i32 base, world)) :
    Term.evaluate (Effectful.machine verifiedFrontendCore calls)
        world currentEnvironment
        (Commands.digitCall sourceTerm boundTerm startTerm baseTerm) =
      .ok (digitScanValue (scanDigitRun source start base),
        world) := by
  unfold Commands.digitCall Commands.call
  apply Term.evaluate_apply
  · exact evaluateTerms_cons sourceEvaluation
      (evaluateTerms_cons boundEvaluation
        (evaluateTerms_cons startEvaluation
          (evaluateTerms_cons baseEvaluation (evaluateTerms_nil _ _ _))))
  · change calls.evaluate world
      extractedScanDigitRunFunction.id
      [Model.sourceSlice source, .signed .i32 source.length,
        .signed .i32 start, .signed .i32 base] = _
    exact contract.digitRun start base startBound baseBound

private theorem leadingDigitCall_evaluates
    (contract : HelperContract calls source world)
    (sourceBound : source.length ≤ 2147483647)
    (startInBounds : start < source.length) :
    Term.evaluate (Effectful.machine verifiedFrontendCore calls) world
        (Model.environment source start)
        (Commands.digitCall (Commands.slot 0) (Commands.slot 1)
          (Commands.add (Commands.slot 2) (Commands.i32 1))
          (Commands.i32 10)) =
      .ok (digitScanValue (scanDigitRun source (start + 1) 10),
        world) := by
  have sumBound : start + 1 ≤ 2147483647 := by omega
  have startPlusOne : Term.evaluate (Effectful.machine verifiedFrontendCore calls)
      world (Model.environment source start)
      (Commands.add (Commands.slot 2) (Commands.i32 1)) =
    .ok (.signed .i32 (start + 1), world) := by
    unfold Commands.add Commands.binary
    apply Term.evaluate_apply2 (by rfl) (by rfl)
    change Lanius.FunctionalView.Core.ReadOnly.evaluateOperation
      verifiedFrontendCore world
      (.binary .add i32Type i32Type i32Type)
      [.signed .i32 start, .signed .i32 1] = _
    exact Lanius.FunctionalView.Core.ReadOnly.evaluateOperation_i32_add
      (program := verifiedFrontendCore) (world := world)
      (leftType := i32Type) (rightType := i32Type) (outputType := i32Type)
      start 1 sumBound
  exact digitCall_evaluates contract (Model.environment source start)
    (Commands.slot 0) (Commands.slot 1)
    (Commands.add (Commands.slot 2) (Commands.i32 1)) (Commands.i32 10)
    (start + 1) 10 sumBound (by omega) (by rfl) (by rfl) startPlusOne (by rfl)

private theorem digitSucceeded_evaluates
    (contract : HelperContract calls source world)
    (currentEnvironment : Env arity) (resultTerm : Term signature arity)
    (result : DigitScanResult)
    (resultBound : match result with
      | .success offset | .failure offset => offset ≤ 2147483647)
    (resultEvaluation : Term.evaluate (Effectful.machine verifiedFrontendCore calls)
      world currentEnvironment resultTerm =
        .ok (digitScanValue result, world)) :
    Term.evaluate (Effectful.machine verifiedFrontendCore calls) world
        currentEnvironment (Commands.digitSucceeded resultTerm) =
      .ok (.boolean (match result with
        | .success _ => true
        | .failure _ => false), world) := by
  unfold Commands.digitSucceeded Commands.call
  apply Term.evaluate_apply1 resultEvaluation
  change calls.evaluate world
    Lexer.Digits.digitScanSucceededFunction.id [digitScanValue result] = _
  cases result <;> exact contract.digitSucceeded _ resultBound

private theorem digitEnd_evaluates
    (contract : HelperContract calls source world)
    (currentEnvironment : Env arity) (resultTerm : Term signature arity)
    (finish : Nat)
    (finishBound : finish ≤ 2147483647)
    (resultEvaluation : Term.evaluate (Effectful.machine verifiedFrontendCore calls)
      world currentEnvironment resultTerm =
        .ok (digitScanValue (.success finish), world)) :
    Term.evaluate (Effectful.machine verifiedFrontendCore calls) world
        currentEnvironment (Commands.digitEnd resultTerm) =
      .ok (.signed .i32 finish, world) := by
  unfold Commands.digitEnd Commands.call
  apply Term.evaluate_apply1 resultEvaluation
  change calls.evaluate world
    Lexer.Digits.digitScanEndOffsetFunction.id
      [digitScanValue (.success finish)] = _
  exact contract.digitEnd finish finishBound

private theorem digitError_evaluates
    (contract : HelperContract calls source world)
    (currentEnvironment : Env arity) (resultTerm : Term signature arity)
    (error : Nat)
    (errorBound : error ≤ 2147483647)
    (resultEvaluation : Term.evaluate (Effectful.machine verifiedFrontendCore calls)
      world currentEnvironment resultTerm =
        .ok (digitScanValue (.failure error), world)) :
    Term.evaluate (Effectful.machine verifiedFrontendCore calls) world
        currentEnvironment (Commands.digitError resultTerm) =
      .ok (.signed .i32 error, world) := by
  unfold Commands.digitError Commands.call
  apply Term.evaluate_apply1 resultEvaluation
  change calls.evaluate world
    Lexer.Digits.digitScanErrorOffsetFunction.id
      [digitScanValue (.failure error)] = _
  exact contract.digitError error errorBound

private theorem numberFailure_evaluates
    (contract : HelperContract calls source world)
    (currentEnvironment : Env arity) (offsetTerm : Term signature arity)
    (error : Nat)
    (errorBound : error ≤ 2147483647)
    (offsetEvaluation : Term.evaluate (Effectful.machine verifiedFrontendCore calls)
      world currentEnvironment offsetTerm =
        .ok (.signed .i32 error, world)) :
    Term.evaluate (Effectful.machine verifiedFrontendCore calls) world
        currentEnvironment (Commands.numberFailure offsetTerm) =
      .ok (Model.encoded (.failure error), world) := by
  unfold Commands.numberFailure Commands.call
  apply Term.evaluate_apply1 offsetEvaluation
  change calls.evaluate world
    Decimal.Functions.numberFailureFunction.id [.signed .i32 error] = _
  exact contract.numberFailure error errorBound

private theorem floatScan_evaluates
    (contract : HelperContract calls source world)
    (currentEnvironment : Env arity) (offsetTerm : Term signature arity)
    (finish : Nat)
    (finishBound : finish ≤ 2147483647)
    (offsetEvaluation : Term.evaluate (Effectful.machine verifiedFrontendCore calls)
      world currentEnvironment offsetTerm =
        .ok (.signed .i32 finish, world)) :
    Term.evaluate (Effectful.machine verifiedFrontendCore calls) world
        currentEnvironment (Commands.floatScan offsetTerm) =
      .ok (Model.encoded (.success .float finish), world) := by
  unfold Commands.floatScan Commands.call
  apply Term.evaluate_apply1 offsetEvaluation
  change calls.evaluate world
    Decimal.Functions.floatScanFunction.id [.signed .i32 finish] = _
  exact contract.floatScan finish finishBound

private theorem integerScan_evaluates
    (contract : HelperContract calls source world)
    (currentEnvironment : Env arity) (offsetTerm : Term signature arity)
    (finish : Nat)
    (finishBound : finish ≤ 2147483647)
    (offsetEvaluation : Term.evaluate (Effectful.machine verifiedFrontendCore calls)
      world currentEnvironment offsetTerm =
        .ok (.signed .i32 finish, world)) :
    Term.evaluate (Effectful.machine verifiedFrontendCore calls) world
        currentEnvironment (Commands.integerScan offsetTerm) =
      .ok (Model.encoded (.success .integer finish), world) := by
  unfold Commands.integerScan Commands.call
  apply Term.evaluate_apply1 offsetEvaluation
  change calls.evaluate world
    Decimal.Functions.integerScanFunction.id [.signed .i32 finish] = _
  exact contract.integerScan finish finishBound

private theorem finishDecimal_evaluates
    (contract : HelperContract calls source world)
    (currentEnvironment : Env arity)
    (sourceTerm boundTerm startTerm : Term signature arity)
    (start : Nat)
    (startBound : start ≤ source.length)
    (sourceEvaluation : Term.evaluate (Effectful.machine verifiedFrontendCore calls)
      world currentEnvironment sourceTerm =
        .ok (Model.sourceSlice source, world))
    (boundEvaluation : Term.evaluate (Effectful.machine verifiedFrontendCore calls)
      world currentEnvironment boundTerm =
        .ok (.signed .i32 source.length, world))
    (startEvaluation : Term.evaluate (Effectful.machine verifiedFrontendCore calls)
      world currentEnvironment startTerm =
        .ok (.signed .i32 start, world)) :
    Term.evaluate (Effectful.machine verifiedFrontendCore calls) world
        currentEnvironment (Commands.finishDecimal sourceTerm boundTerm startTerm) =
      .ok (Model.encoded (finishDecimal source start), world) := by
  unfold Commands.finishDecimal Commands.call
  apply Term.evaluate_apply
  · exact evaluateTerms_cons sourceEvaluation
      (evaluateTerms_cons boundEvaluation
        (evaluateTerms_cons startEvaluation (evaluateTerms_nil _ _ _)))
  · change calls.evaluate world
      Decimal.Functions.finishDecimalFunction.id
      [Model.sourceSlice source, .signed .i32 source.length,
        .signed .i32 start] = _
    exact contract.finishDecimal start startBound

private theorem scanExponent_evaluates
    (contract : HelperContract calls source world)
    (currentEnvironment : Env arity)
    (sourceTerm boundTerm startTerm : Term signature arity)
    (start : Nat)
    (startBound : start < source.length)
    (sourceEvaluation : Term.evaluate (Effectful.machine verifiedFrontendCore calls)
      world currentEnvironment sourceTerm =
        .ok (Model.sourceSlice source, world))
    (boundEvaluation : Term.evaluate (Effectful.machine verifiedFrontendCore calls)
      world currentEnvironment boundTerm =
        .ok (.signed .i32 source.length, world))
    (startEvaluation : Term.evaluate (Effectful.machine verifiedFrontendCore calls)
      world currentEnvironment startTerm =
        .ok (.signed .i32 start, world)) :
    Term.evaluate (Effectful.machine verifiedFrontendCore calls) world
        currentEnvironment
        (Commands.scanExponent sourceTerm boundTerm startTerm) =
      .ok (Model.encoded (scanExponent source start),
        world) := by
  unfold Commands.scanExponent Commands.call
  apply Term.evaluate_apply
  · exact evaluateTerms_cons sourceEvaluation
      (evaluateTerms_cons boundEvaluation
        (evaluateTerms_cons startEvaluation (evaluateTerms_nil _ _ _)))
  · change calls.evaluate world
      Decimal.Functions.scanExponentFunction.id
      [Model.sourceSlice source, .signed .i32 source.length,
        .signed .i32 start] = _
    exact contract.scanExponent start startBound

private theorem failedDigitCondition_evaluates
    (contract : HelperContract calls source world)
    (currentEnvironment : Env arity) (resultTerm : Term signature arity)
    (error : Nat)
    (errorBound : error ≤ 2147483647)
    (resultEvaluation : Term.evaluate (Effectful.machine verifiedFrontendCore calls)
      world currentEnvironment resultTerm =
        .ok (digitScanValue (.failure error), world)) :
    Term.evaluate (Effectful.machine verifiedFrontendCore calls) world
        currentEnvironment
        (Commands.unary .logicalNot (Commands.digitSucceeded resultTerm)) =
      .ok (.boolean true, world) := by
  unfold Commands.unary
  apply Term.evaluate_apply1
    (digitSucceeded_evaluates contract currentEnvironment resultTerm
      (.failure error) errorBound resultEvaluation)
  rfl

private theorem successfulDigitCondition_evaluates
    (contract : HelperContract calls source world)
    (currentEnvironment : Env arity) (resultTerm : Term signature arity)
    (finish : Nat)
    (finishBound : finish ≤ 2147483647)
    (resultEvaluation : Term.evaluate (Effectful.machine verifiedFrontendCore calls)
      world currentEnvironment resultTerm =
        .ok (digitScanValue (.success finish), world)) :
    Term.evaluate (Effectful.machine verifiedFrontendCore calls) world
        currentEnvironment
        (Commands.unary .logicalNot (Commands.digitSucceeded resultTerm)) =
      .ok (.boolean false, world) := by
  unfold Commands.unary
  apply Term.evaluate_apply1
    (digitSucceeded_evaluates contract currentEnvironment resultTerm
      (.success finish) finishBound resultEvaluation)
  rfl

private theorem equalLiteral_evaluates
    (calls : CallModel) (world : World) (currentEnvironment : Env arity)
    (value : Nat) (valueTerm : Term signature arity) (literalValue : Nat)
    (valueEvaluation : Term.evaluate
      (Effectful.machine verifiedFrontendCore calls)
      world currentEnvironment valueTerm =
        .ok (.signed .i32 value, world)) :
    Term.evaluate (Effectful.machine verifiedFrontendCore calls)
        world currentEnvironment
        (Commands.comparison .equal valueTerm (Commands.i32 literalValue)) =
      .ok (.boolean (decide (value = literalValue)), world) := by
  unfold Commands.comparison Commands.binary
  apply Term.evaluate_apply2 valueEvaluation (by rfl)
  exact Lanius.FunctionalView.Core.ReadOnly.evaluateOperation_i32_equal
    (program := verifiedFrontendCore) (world := world)
    (leftType := i32Type) (rightType := i32Type)
    (outputType := Commands.boolType) value literalValue

private theorem notEqualLiteral_evaluates
    (calls : CallModel) (world : World) (currentEnvironment : Env arity)
    (value : Nat) (valueTerm : Term signature arity) (literalValue : Nat)
    (valueEvaluation : Term.evaluate
      (Effectful.machine verifiedFrontendCore calls)
      world currentEnvironment valueTerm =
        .ok (.signed .i32 value, world)) :
    Term.evaluate (Effectful.machine verifiedFrontendCore calls)
        world currentEnvironment
        (Commands.comparison .notEqual valueTerm (Commands.i32 literalValue)) =
      .ok (.boolean (decide (value ≠ literalValue)), world) := by
  unfold Commands.comparison Commands.binary
  apply Term.evaluate_apply2 valueEvaluation (by rfl)
  change Lanius.FunctionalView.Core.ReadOnly.evaluateOperation
    verifiedFrontendCore world
    (.binary .notEqual i32Type i32Type Commands.boolType)
    [.signed .i32 value, .signed .i32 literalValue] = _
  rw [Lanius.FunctionalView.Core.ReadOnly.evaluateOperation_i32_notEqual_int]
  congr 2
  congr 1
  apply Bool.eq_iff_iff.mpr
  constructor
  · intro different
    apply decide_eq_true
    intro same
    exact of_decide_eq_true different (congrArg Int.ofNat same)
  · intro different
    apply decide_eq_true
    intro same
    exact of_decide_eq_true different (Int.ofNat_inj.mp same)

private theorem eitherLiteral_evaluates
    (calls : CallModel) (world : World) (currentEnvironment : Env arity)
    (value : Nat) (valueTerm : Term signature arity) (left right : Nat)
    (valueEvaluation : Term.evaluate
      (Effectful.machine verifiedFrontendCore calls)
      world currentEnvironment valueTerm =
        .ok (.signed .i32 value, world)) :
    Term.evaluate (Effectful.machine verifiedFrontendCore calls)
        world currentEnvironment
        ((Commands.comparison .equal valueTerm (Commands.i32 left)).logicalOr
          (Commands.comparison .equal valueTerm (Commands.i32 right))) =
      .ok (.boolean (decide (value = left ∨ value = right)), world) := by
  have leftEvaluation := equalLiteral_evaluates calls world
    currentEnvironment value valueTerm left valueEvaluation
  by_cases isLeft : value = left
  · simpa [isLeft] using Term.evaluate_logicalOr_true
      (by simpa [isLeft] using leftEvaluation)
  · have rightEvaluation := equalLiteral_evaluates calls world
      currentEnvironment value valueTerm right valueEvaluation
    simpa [isLeft] using Term.evaluate_logicalOr_false
      (by simpa [isLeft] using leftEvaluation) rightEvaluation

private theorem addLiteral_evaluates
    (calls : CallModel) (world : World) (currentEnvironment : Env arity)
    (value literalValue : Nat) (valueTerm : Term signature arity)
    (valueEvaluation : Term.evaluate
      (Effectful.machine verifiedFrontendCore calls)
      world currentEnvironment valueTerm =
        .ok (.signed .i32 value, world))
    (sumBound : value + literalValue ≤ 2147483647) :
    Term.evaluate (Effectful.machine verifiedFrontendCore calls)
        world currentEnvironment
        (Commands.add valueTerm (Commands.i32 literalValue)) =
      .ok (.signed .i32 (value + literalValue), world) := by
  unfold Commands.add Commands.binary
  apply Term.evaluate_apply2 valueEvaluation (by rfl)
  exact Lanius.FunctionalView.Core.ReadOnly.evaluateOperation_i32_add
    (program := verifiedFrontendCore) (world := world)
    (leftType := i32Type) (rightType := i32Type)
    (outputType := i32Type) value literalValue sumBound

private theorem lessNat_evaluates
    (calls : CallModel) (world : World) (currentEnvironment : Env arity)
    (left right : Nat) (leftTerm rightTerm : Term signature arity)
    (leftEvaluation : Term.evaluate
      (Effectful.machine verifiedFrontendCore calls)
      world currentEnvironment leftTerm =
        .ok (.signed .i32 left, world))
    (rightEvaluation : Term.evaluate
      (Effectful.machine verifiedFrontendCore calls)
      world currentEnvironment rightTerm =
        .ok (.signed .i32 right, world)) :
    Term.evaluate (Effectful.machine verifiedFrontendCore calls)
        world currentEnvironment
        (Commands.comparison .less leftTerm rightTerm) =
      .ok (.boolean (decide (left < right)), world) := by
  unfold Commands.comparison Commands.binary
  apply Term.evaluate_apply2 leftEvaluation rightEvaluation
  exact Lanius.FunctionalView.Core.ReadOnly.evaluateOperation_i32_less
    (program := verifiedFrontendCore) (world := world)
    (leftType := i32Type) (rightType := i32Type)
    (outputType := Commands.boolType) left right

private theorem sourceIndex_evaluates
    (calls : CallModel) (source : List Byte) (start : Nat)
    (position : Nat) (inBounds : position < source.length)
    (sourceFound : world.i32Slice? 0 = some (Model.sourceIntegers source))
    (currentEnvironment : Env arity)
    (sourceTerm positionTerm : Term signature arity)
    (sourceEvaluation : Term.evaluate
      (Effectful.machine verifiedFrontendCore calls)
      world currentEnvironment sourceTerm =
        .ok (Model.sourceSlice source, world))
    (positionEvaluation : Term.evaluate
      (Effectful.machine verifiedFrontendCore calls)
      world currentEnvironment positionTerm =
        .ok (.signed .i32 position, world)) :
    Term.evaluate (Effectful.machine verifiedFrontendCore calls)
        world currentEnvironment
        (Commands.index sourceTerm positionTerm) =
      .ok (.signed .i32 source[position].val, world) := by
  unfold Commands.index
  apply Term.evaluate_apply2 sourceEvaluation positionEvaluation
  change Lanius.FunctionalView.Core.ReadOnly.evaluateOperation
    verifiedFrontendCore world
    (.index Commands.sliceType i32Type i32Type)
    [Model.sourceSlice source, .signed .i32 position] = _
  have indexResult :=
    Lanius.FunctionalView.Core.ReadOnly.evaluateOperation_i32_index
      (program := verifiedFrontendCore) (world := world)
      (baseType := Commands.sliceType) (indexType := i32Type)
      (elementType := i32Type) (cell := 0)
      (values := Model.sourceIntegers source) (position := position)
      sourceFound (by simpa using inBounds)
  have same : (Model.sourceIntegers source).get
      ⟨position, by simpa using inBounds⟩ =
      Int.ofNat source[position].val := by
    simpa [Model.sourceIntegers]
  change Lanius.FunctionalView.Core.ReadOnly.evaluateOperation
      verifiedFrontendCore world
      (.index Commands.sliceType i32Type i32Type)
      [Model.sourceSlice source, .signed .i32 (Int.ofNat position)] =
    .ok (.signed .i32 (Int.ofNat source[position].val), world)
  simpa only [Model.sourceSlice, Model.sourceIntegers_length, same] using indexResult

private theorem initialCondition_evaluates
    (contract : HelperContract calls source world)
    (sourceBound : source.length ≤ 2147483647)
    (sourceFound : world.i32Slice? 0 = some (Model.sourceIntegers source))
    (startInBounds : start < source.length) :
    Term.evaluate (Effectful.machine verifiedFrontendCore calls)
        world (Model.environment source start)
        ((Commands.comparison .equal
          (Commands.index (Commands.slot 0) (Commands.slot 2))
          (Commands.i32 48)).logicalAnd
        (Commands.comparison .less
          (Commands.add (Commands.slot 2) (Commands.i32 1))
          (Commands.slot 1))) =
      .ok (.boolean (decide
        (source[start].val = 48 ∧ start + 1 < source.length)),
        world) := by
  have indexed := sourceIndex_evaluates calls source start start
    startInBounds sourceFound (Model.environment source start)
    (Commands.slot 0) (Commands.slot 2) (by rfl) (by rfl)
  have equal := equalLiteral_evaluates calls world
    (Model.environment source start) source[start].val
    (Commands.index (Commands.slot 0) (Commands.slot 2)) 48 indexed
  by_cases zero : source[start].val = 48
  · have sumBound : start + 1 ≤ 2147483647 := by omega
    have added := addLiteral_evaluates calls world
      (Model.environment source start) start 1 (Commands.slot 2)
      (by rfl) sumBound
    have less := lessNat_evaluates calls world
      (Model.environment source start) (start + 1) source.length
      (Commands.add (Commands.slot 2) (Commands.i32 1)) (Commands.slot 1)
      added (by rfl)
    simpa [zero] using Term.evaluate_logicalAnd_true
      (by simpa [zero] using equal) less
  · simpa [zero] using Term.evaluate_logicalAnd_false
      (by simpa [zero] using equal)

theorem scanLeadingDotNumber_run
    (contract : HelperContract calls source world)
    (sourceBound : source.length ≤ 2147483647)
    (sourceFound : world.i32Slice? 0 = some (Model.sourceIntegers source))
    (startInBounds : start < source.length) :
    Stateful.Acyclic.run? (Effectful.machine verifiedFrontendCore calls) (commandMachine calls)
        world (Model.environment source start)
        Commands.scanLeadingDotNumber =
      some (.returned (some (Model.encoded
        (scanLeadingDotNumber source start))),
        world, Model.environment source start) := by
  unfold Commands.scanLeadingDotNumber
  simp only [Stateful.Acyclic.run?]
  rw [leadingDigitCall_evaluates contract sourceBound startInBounds]
  have digitBound := digitRunResult_bound (base := 10) sourceBound (by omega :
    start + 1 ≤ 2147483647)
  cases digits : scanDigitRun source (start + 1) 10 with
  | failure error =>
      rw [digits] at digitBound
      have failedCondition := failedDigitCondition_evaluates contract
        ((Model.environment source start).push
          (digitScanValue (.failure error))) (Commands.slot 3)
        error digitBound (by rfl)
      have errorEvaluation := digitError_evaluates contract
        ((Model.environment source start).push
          (digitScanValue (.failure error))) (Commands.slot 3) error
          digitBound (by rfl)
      have failureEvaluation := numberFailure_evaluates contract
        ((Model.environment source start).push
          (digitScanValue (.failure error)))
        (Commands.digitError (Commands.slot 3)) error digitBound errorEvaluation
      simp [failedCondition, Stateful.Acyclic.run?,
        Commands.returned, failureEvaluation]
      simp [scanLeadingDotNumber, digits]
      rfl
  | success finish =>
      rw [digits] at digitBound
      have passedCondition := successfulDigitCondition_evaluates contract
        ((Model.environment source start).push
          (digitScanValue (.success finish))) (Commands.slot 3)
        finish digitBound (by rfl)
      have finishEvaluation := digitEnd_evaluates contract
        ((Model.environment source start).push
          (digitScanValue (.success finish))) (Commands.slot 3) finish
          digitBound (by rfl)
      simp only [passedCondition, Stateful.Acyclic.run?,
        finishEvaluation]
      by_cases finishInBounds : finish < source.length
      · have boundCondition : Term.evaluate (Effectful.machine verifiedFrontendCore calls)
            world
            (((Model.environment source start).push
              (digitScanValue (.success finish))).push (.signed .i32 finish))
            (Commands.comparison .less (Commands.slot 4) (Commands.slot 1)) =
          .ok (.boolean true, world) := by
          unfold Commands.comparison Commands.binary
          apply Term.evaluate_apply2 (by rfl) (by rfl)
          change Lanius.FunctionalView.Core.ReadOnly.evaluateOperation
            verifiedFrontendCore world
            (.binary .less i32Type i32Type Commands.boolType)
            [.signed .i32 finish, .signed .i32 source.length] = _
          simp [Lanius.FunctionalView.Core.ReadOnly.evaluateOperation,
            Lanius.Semantics.evalBinaryValue,
            Lanius.Semantics.evalSignedBinary,
            finishInBounds, bind, Except.bind]
          rfl
        rw [boundCondition]
        simp only [bind, Except.bind]
        have indexEvaluation := sourceIndex_evaluates calls source start finish
          finishInBounds sourceFound
          (((Model.environment source start).push
            (digitScanValue (.success finish))).push (.signed .i32 finish))
          (Commands.slot 0) (Commands.slot 4) (by rfl) (by rfl)
        rw [indexEvaluation]
        simp only [bind, Except.bind]
        let byte : Byte := source[finish]
        by_cases exponent : source[finish].val = 101 ∨ source[finish].val = 69
        · have byteExponent : byte.val = 101 ∨ byte.val = 69 := by
            simpa [byte] using exponent
          have exponentCondition : Term.evaluate (Effectful.machine verifiedFrontendCore calls)
              world
              ((((Model.environment source start).push
                (digitScanValue (.success finish))).push
                  (.signed .i32 finish)).push (.signed .i32 byte.val))
              ((Commands.comparison .equal (Commands.slot 5)
                  (Commands.i32 101)).logicalOr
                (Commands.comparison .equal (Commands.slot 5)
                  (Commands.i32 69))) =
            .ok (.boolean true, world) := by
            rcases byteExponent with left | right
            · rw [left]
              rfl
            · have notFirst : byte.val ≠ 101 := by omega
              apply Term.evaluate_logicalOr_false
              · simpa [notFirst] using equalLiteral_evaluates calls
                  world
                  ((((Model.environment source start).push
                    (digitScanValue (.success finish))).push
                      (.signed .i32 finish)).push (.signed .i32 byte.val))
                  byte.val (Commands.slot 5) 101 (by rfl)
              · simpa [right] using equalLiteral_evaluates calls
                  world
                  ((((Model.environment source start).push
                    (digitScanValue (.success finish))).push
                      (.signed .i32 finish)).push (.signed .i32 byte.val))
                  byte.val (Commands.slot 5) 69 (by rfl)
          simp only [byte] at exponentCondition exponent
          rw [exponentCondition]
          simp only [bind, Except.bind]
          have exponentEvaluation := scanExponent_evaluates contract
            ((((Model.environment source start).push
              (digitScanValue (.success finish))).push
                (.signed .i32 finish)).push (.signed .i32 byte.val))
            (Commands.slot 0) (Commands.slot 1) (Commands.slot 4) finish
            finishInBounds (by rfl) (by rfl) (by rfl)
          simp only [byte] at exponentEvaluation
          simp only [Stateful.Acyclic.run?, Commands.returned]
          rw [exponentEvaluation]
          simp [Stateful.Acyclic.run?, Commands.returned]
          simp [scanLeadingDotNumber, digits, byteValueAt, finishInBounds,
            exponent]
          rfl
        · have byteNotExponent : ¬(byte.val = 101 ∨ byte.val = 69) := by
            simpa [byte] using exponent
          have exponentCondition : Term.evaluate (Effectful.machine verifiedFrontendCore calls)
              world
              ((((Model.environment source start).push
                (digitScanValue (.success finish))).push
                  (.signed .i32 finish)).push (.signed .i32 byte.val))
              ((Commands.comparison .equal (Commands.slot 5)
                  (Commands.i32 101)).logicalOr
                (Commands.comparison .equal (Commands.slot 5)
                  (Commands.i32 69))) =
            .ok (.boolean false, world) := by
            have notFirst : byte.val ≠ 101 := fun equal =>
              byteNotExponent (Or.inl equal)
            have notSecond : byte.val ≠ 69 := fun equal =>
              byteNotExponent (Or.inr equal)
            apply Term.evaluate_logicalOr_false
            · simpa [notFirst] using equalLiteral_evaluates calls
                world
                ((((Model.environment source start).push
                  (digitScanValue (.success finish))).push
                    (.signed .i32 finish)).push (.signed .i32 byte.val))
                byte.val (Commands.slot 5) 101 (by rfl)
            · simpa [notSecond] using equalLiteral_evaluates calls
                world
                ((((Model.environment source start).push
                  (digitScanValue (.success finish))).push
                    (.signed .i32 finish)).push (.signed .i32 byte.val))
                byte.val (Commands.slot 5) 69 (by rfl)
          simp only [byte] at exponentCondition exponent
          rw [exponentCondition]
          simp only [bind, Except.bind]
          have floatEvaluation := floatScan_evaluates contract
            (((Model.environment source start).push
              (digitScanValue (.success finish))).push (.signed .i32 finish))
            (Commands.slot 4) finish digitBound (by rfl)
          simp [Stateful.Acyclic.run?, Commands.returned,
            floatEvaluation]
          simp [scanLeadingDotNumber, digits, byteValueAt, finishInBounds,
            exponent]
          rfl
      · have boundCondition : Term.evaluate (Effectful.machine verifiedFrontendCore calls)
            world
            (((Model.environment source start).push
              (digitScanValue (.success finish))).push (.signed .i32 finish))
            (Commands.comparison .less (Commands.slot 4) (Commands.slot 1)) =
          .ok (.boolean false, world) := by
          unfold Commands.comparison Commands.binary
          apply Term.evaluate_apply2 (by rfl) (by rfl)
          change Lanius.FunctionalView.Core.ReadOnly.evaluateOperation
            verifiedFrontendCore world
            (.binary .less i32Type i32Type Commands.boolType)
            [.signed .i32 finish, .signed .i32 source.length] = _
          simp [Lanius.FunctionalView.Core.ReadOnly.evaluateOperation,
            Lanius.Semantics.evalBinaryValue,
            Lanius.Semantics.evalSignedBinary,
            finishInBounds, bind, Except.bind]
          rfl
        rw [boundCondition]
        simp only [bind, Except.bind]
        have floatEvaluation := floatScan_evaluates contract
          (((Model.environment source start).push
            (digitScanValue (.success finish))).push (.signed .i32 finish))
          (Commands.slot 4) finish digitBound (by rfl)
        simp [Stateful.Acyclic.run?, Commands.returned,
          floatEvaluation]
        simp [scanLeadingDotNumber, digits, byteValueAt, finishInBounds]
        rfl

private theorem decimalBranch_run
    (contract : HelperContract calls source world)
    (sourceBound : source.length ≤ 2147483647)
    (start : Nat) (startBound : start ≤ 2147483647) :
    Stateful.Acyclic.run? (Effectful.machine verifiedFrontendCore calls)
        (commandMachine calls) world
        (Model.environment source start) Commands.decimalBranch =
      some (.returned (some (Model.encoded
        (match scanDigitRun source start 10 with
        | .failure error => .failure error
        | .success finish => finishDecimal source finish))),
        world, Model.environment source start) := by
  unfold Commands.decimalBranch
  simp only [Stateful.Acyclic.run?]
  rw [digitCall_evaluates contract (Model.environment source start)
    (Commands.slot 0) (Commands.slot 1) (Commands.slot 2) (Commands.i32 10)
    start 10 startBound (by omega) (by rfl) (by rfl) (by rfl) (by rfl)]
  have digitBound := digitRunResult_bound (base := 10) sourceBound startBound
  cases digits : scanDigitRun source start 10 with
  | failure error =>
      rw [digits] at digitBound
      have failedCondition := failedDigitCondition_evaluates contract
        ((Model.environment source start).push (digitScanValue (.failure error)))
        (Commands.slot 3) error digitBound (by rfl)
      have errorEvaluation := digitError_evaluates contract
        ((Model.environment source start).push (digitScanValue (.failure error)))
        (Commands.slot 3) error digitBound (by rfl)
      have failureEvaluation := numberFailure_evaluates contract
        ((Model.environment source start).push (digitScanValue (.failure error)))
        (Commands.digitError (Commands.slot 3)) error digitBound errorEvaluation
      simp [failedCondition, Stateful.Acyclic.run?, Commands.returned,
        failureEvaluation, digits]
      rfl
  | success finish =>
      rw [digits] at digitBound
      have passedCondition := successfulDigitCondition_evaluates contract
        ((Model.environment source start).push (digitScanValue (.success finish)))
        (Commands.slot 3) finish digitBound (by rfl)
      have finishEvaluation := digitEnd_evaluates contract
        ((Model.environment source start).push (digitScanValue (.success finish)))
        (Commands.slot 3) finish digitBound (by rfl)
      have decimalEvaluation := finishDecimal_evaluates contract
        ((Model.environment source start).push (digitScanValue (.success finish)))
        (Commands.slot 0) (Commands.slot 1)
        (Commands.digitEnd (Commands.slot 3)) finish
        (digitRunSuccess_le_source digits)
        (by rfl) (by rfl) finishEvaluation
      simp [passedCondition, Stateful.Acyclic.run?, Commands.returned,
        decimalEvaluation, digits]
      rfl

private def selectedPrefixBase (prefixValue : Nat) : Nat :=
  if prefixValue = 120 ∨ prefixValue = 88 then 16
  else if prefixValue = 98 ∨ prefixValue = 66 then 2
  else if prefixValue = 111 ∨ prefixValue = 79 then 8
  else 0

private theorem selectedPrefixBase_bound (prefixValue : Nat) :
    selectedPrefixBase prefixValue ≤ 16 := by
  unfold selectedPrefixBase
  by_cases hexadecimal : prefixValue = 120 ∨ prefixValue = 88
  · simp [hexadecimal]
  · by_cases binary : prefixValue = 98 ∨ prefixValue = 66
    · simp [hexadecimal, binary]
    · by_cases octal : prefixValue = 111 ∨ prefixValue = 79
      · simp [hexadecimal, binary, octal]
      · simp [hexadecimal, binary, octal]

private theorem chooseBase_run
    (calls : CallModel) (source : List Byte) (start prefixValue : Nat) :
    Stateful.Acyclic.run? (Effectful.machine verifiedFrontendCore calls)
        (commandMachine calls) world
        (((Model.environment source start).push (.signed .i32 prefixValue)).push
          (.signed .i32 0)) Commands.chooseBase =
      some (.next, world,
        ((Model.environment source start).push (.signed .i32 prefixValue)).push
          (.signed .i32 (selectedPrefixBase prefixValue))) := by
  unfold Commands.chooseBase
  simp only [Stateful.Acyclic.run?]
  have hexadecimal := eitherLiteral_evaluates calls world
    (((Model.environment source start).push (.signed .i32 prefixValue)).push
      (.signed .i32 0)) prefixValue (Commands.slot 3) 120 88 (by rfl)
  have hexadecimal' : Term.evaluate (Effectful.machine verifiedFrontendCore calls)
      world
      (((Model.environment source start).push (.signed .i32 prefixValue)).push
        (.signed .i32 0))
      ((Commands.comparison .equal (Commands.slot 3) (Commands.i32 120)).logicalOr
        (Commands.comparison .equal (Commands.slot 3) (Commands.i32 88))) =
    .ok (.boolean (decide (prefixValue = 120 ∨ prefixValue = 88)),
      world) := by simpa using hexadecimal
  rw [hexadecimal']
  by_cases isHex : prefixValue = 120 ∨ prefixValue = 88
  · have decided : decide (prefixValue = 120 ∨ prefixValue = 88) = true :=
      decide_eq_true isHex
    rw [decided]
    simp only [bind, Except.bind]
    simp only [Commands.statement, Stateful.Acyclic.run?]
    rw [show Term.evaluate (Effectful.machine verifiedFrontendCore calls)
        world
        (((Model.environment source start).push (.signed .i32 prefixValue)).push
          (.signed .i32 0)) (Commands.i32 16) =
      .ok (.signed .i32 16, world) by rfl]
    simp [Stateful.Acyclic.run?, selectedPrefixBase, isHex]
    rfl
  · have decided : decide (prefixValue = 120 ∨ prefixValue = 88) = false :=
      decide_eq_false isHex
    rw [decided]
    simp only [bind, Except.bind, Commands.statement, Stateful.Acyclic.run?]
    have binary := eitherLiteral_evaluates calls world
      (((Model.environment source start).push (.signed .i32 prefixValue)).push
        (.signed .i32 0)) prefixValue (Commands.slot 3) 98 66 (by rfl)
    have binary' : Term.evaluate (Effectful.machine verifiedFrontendCore calls)
        world
        (((Model.environment source start).push (.signed .i32 prefixValue)).push
          (.signed .i32 0))
        ((Commands.comparison .equal (Commands.slot 3) (Commands.i32 98)).logicalOr
          (Commands.comparison .equal (Commands.slot 3) (Commands.i32 66))) =
      .ok (.boolean (decide (prefixValue = 98 ∨ prefixValue = 66)),
        world) := by simpa using binary
    rw [binary']
    by_cases isBinary : prefixValue = 98 ∨ prefixValue = 66
    · have binaryDecided : decide (prefixValue = 98 ∨ prefixValue = 66) = true :=
        decide_eq_true isBinary
      rw [binaryDecided]
      simp only [bind, Except.bind]
      rw [show Term.evaluate (Effectful.machine verifiedFrontendCore calls)
          world
          (((Model.environment source start).push (.signed .i32 prefixValue)).push
            (.signed .i32 0)) (Commands.i32 2) =
        .ok (.signed .i32 2, world) by rfl]
      simp [Stateful.Acyclic.run?, selectedPrefixBase, isHex, isBinary]
      rfl
    · have binaryDecided : decide (prefixValue = 98 ∨ prefixValue = 66) = false :=
        decide_eq_false isBinary
      rw [binaryDecided]
      simp only [bind, Except.bind, Commands.statement, Stateful.Acyclic.run?]
      have octal := eitherLiteral_evaluates calls world
        (((Model.environment source start).push (.signed .i32 prefixValue)).push
          (.signed .i32 0)) prefixValue (Commands.slot 3) 111 79 (by rfl)
      have octal' : Term.evaluate (Effectful.machine verifiedFrontendCore calls)
          world
          (((Model.environment source start).push (.signed .i32 prefixValue)).push
            (.signed .i32 0))
          ((Commands.comparison .equal (Commands.slot 3) (Commands.i32 111)).logicalOr
            (Commands.comparison .equal (Commands.slot 3) (Commands.i32 79))) =
        .ok (.boolean (decide (prefixValue = 111 ∨ prefixValue = 79)),
          world) := by simpa using octal
      rw [octal']
      by_cases isOctal : prefixValue = 111 ∨ prefixValue = 79
      · have octalDecided :
            decide (prefixValue = 111 ∨ prefixValue = 79) = true :=
          decide_eq_true isOctal
        rw [octalDecided]
        simp only [bind, Except.bind]
        rw [show Term.evaluate (Effectful.machine verifiedFrontendCore calls)
            world
            (((Model.environment source start).push (.signed .i32 prefixValue)).push
              (.signed .i32 0)) (Commands.i32 8) =
          .ok (.signed .i32 8, world) by rfl]
        simp [Stateful.Acyclic.run?, selectedPrefixBase,
          isHex, isBinary, isOctal]
        rfl
      · have octalDecided : decide (prefixValue = 111 ∨ prefixValue = 79) = false :=
          decide_eq_false isOctal
        rw [octalDecided]
        simp [Stateful.Acyclic.run?, Commands.statement, Commands.i32, selectedPrefixBase,
          isHex, isBinary, isOctal]
        rfl

private theorem prefixedReturn_run
    (contract : HelperContract calls source world)
    (sourceBound : source.length ≤ 2147483647)
    (nextInBounds : start + 1 < source.length)
    (prefixValue base : Nat) (baseNonzero : base ≠ 0)
    (baseBound : base ≤ 2147483647) :
    Stateful.Acyclic.run? (Effectful.machine verifiedFrontendCore calls)
        (commandMachine calls) world
        (((Model.environment source start).push (.signed .i32 prefixValue)).push
          (.signed .i32 base)) Commands.prefixedReturn =
      some (.returned (some (Model.encoded
        (match scanDigitRun source (start + 2) base with
        | .failure error => .failure error
        | .success finish => .success .integer finish))),
        world,
        (((Model.environment source start).push (.signed .i32 prefixValue)).push
          (.signed .i32 base))) := by
  unfold Commands.prefixedReturn
  simp only [Stateful.Acyclic.run?]
  have nonzeroEvaluation := notEqualLiteral_evaluates calls
    world
    (((Model.environment source start).push (.signed .i32 prefixValue)).push
      (.signed .i32 base)) base (Commands.slot 4) 0 (by rfl)
  have nonzeroEvaluation' : Term.evaluate
      (Effectful.machine verifiedFrontendCore calls) world
      (((Model.environment source start).push (.signed .i32 prefixValue)).push
        (.signed .i32 base))
      (Commands.comparison .notEqual (Commands.slot 4) (Commands.i32 0)) =
    .ok (.boolean (decide (base ≠ 0)), world) := by
    simpa using nonzeroEvaluation
  rw [nonzeroEvaluation']
  have decidedNonzero : decide (base ≠ 0) = true := decide_eq_true baseNonzero
  rw [decidedNonzero]
  simp only [bind, Except.bind]
  have sumBound : start + 2 ≤ 2147483647 := by omega
  have startEvaluation := addLiteral_evaluates calls
    world
    (((Model.environment source start).push (.signed .i32 prefixValue)).push
      (.signed .i32 base)) start 2 (Commands.slot 2) (by rfl) sumBound
  rw [digitCall_evaluates contract
    (((Model.environment source start).push (.signed .i32 prefixValue)).push
      (.signed .i32 base))
    (Commands.slot 0) (Commands.slot 1)
    (Commands.add (Commands.slot 2) (Commands.i32 2)) (Commands.slot 4)
    (start + 2) base sumBound baseBound (by rfl) (by rfl) startEvaluation
    (by rfl)]
  have digitBound := digitRunResult_bound (base := base) sourceBound sumBound
  cases digits : scanDigitRun source (start + 2) base with
  | failure error =>
      rw [digits] at digitBound
      have failedCondition := failedDigitCondition_evaluates contract
        ((((Model.environment source start).push (.signed .i32 prefixValue)).push
          (.signed .i32 base)).push (digitScanValue (.failure error)))
        (Commands.slot 5) error digitBound (by rfl)
      have errorEvaluation := digitError_evaluates contract
        ((((Model.environment source start).push (.signed .i32 prefixValue)).push
          (.signed .i32 base)).push (digitScanValue (.failure error)))
        (Commands.slot 5) error digitBound (by rfl)
      have failureEvaluation := numberFailure_evaluates contract
        ((((Model.environment source start).push (.signed .i32 prefixValue)).push
          (.signed .i32 base)).push (digitScanValue (.failure error)))
        (Commands.digitError (Commands.slot 5)) error digitBound errorEvaluation
      simp [failedCondition, Stateful.Acyclic.run?, Commands.returned,
        failureEvaluation, digits]
      rfl
  | success finish =>
      rw [digits] at digitBound
      have passedCondition := successfulDigitCondition_evaluates contract
        ((((Model.environment source start).push (.signed .i32 prefixValue)).push
          (.signed .i32 base)).push (digitScanValue (.success finish)))
        (Commands.slot 5) finish digitBound (by rfl)
      have finishEvaluation := digitEnd_evaluates contract
        ((((Model.environment source start).push (.signed .i32 prefixValue)).push
          (.signed .i32 base)).push (digitScanValue (.success finish)))
        (Commands.slot 5) finish digitBound (by rfl)
      have integerEvaluation := integerScan_evaluates contract
        ((((Model.environment source start).push (.signed .i32 prefixValue)).push
          (.signed .i32 base)).push (digitScanValue (.success finish)))
        (Commands.digitEnd (Commands.slot 5)) finish digitBound finishEvaluation
      simp [passedCondition, Stateful.Acyclic.run?, Commands.returned,
        integerEvaluation, digits]
      rfl

private theorem prefixedBranch_run
    (contract : HelperContract calls source world)
    (sourceBound : source.length ≤ 2147483647)
    (sourceFound : world.i32Slice? 0 = some (Model.sourceIntegers source))
    (nextInBounds : start + 1 < source.length) :
    let prefixValue := source[start + 1].val
    let base := selectedPrefixBase prefixValue
    Stateful.Acyclic.run? (Effectful.machine verifiedFrontendCore calls)
        (commandMachine calls) world
        (Model.environment source start) Commands.prefixedBranch =
      if base = 0 then
        some (.next, world, Model.environment source start)
      else
        some (.returned (some (Model.encoded
          (match scanDigitRun source (start + 2) base with
          | .failure error => .failure error
          | .success finish => .success .integer finish))),
          world, Model.environment source start) := by
  dsimp only
  unfold Commands.prefixedBranch
  simp only [Stateful.Acyclic.run?]
  have sumBound : start + 1 ≤ 2147483647 := by omega
  have added := addLiteral_evaluates calls world
    (Model.environment source start) start 1 (Commands.slot 2)
    (by rfl) sumBound
  rw [sourceIndex_evaluates calls source start (start + 1) nextInBounds
    sourceFound (Model.environment source start) (Commands.slot 0)
    (Commands.add (Commands.slot 2) (Commands.i32 1))
    (by rfl) added]
  simp only [bind, Except.bind]
  rw [show Term.evaluate (Effectful.machine verifiedFrontendCore calls)
      world
      ((Model.environment source start).push
        (.signed .i32 source[start + 1].val)) (Commands.i32 0) =
    .ok (.signed .i32 0, world) by rfl]
  simp only [bind, Except.bind]
  rw [chooseBase_run calls source start source[start + 1].val]
  simp only [bind, Except.bind]
  let base := selectedPrefixBase source[start + 1].val
  by_cases baseZero : base = 0
  · have notEqual := notEqualLiteral_evaluates calls world
      (((Model.environment source start).push (.signed .i32 source[start + 1].val)).push
        (.signed .i32 base)) base (Commands.slot 4) 0 (by rfl)
    have notEqual' : Term.evaluate (Effectful.machine verifiedFrontendCore calls)
        world
        (((Model.environment source start).push (.signed .i32 source[start + 1].val)).push
          (.signed .i32 base))
        (Commands.comparison .notEqual (Commands.slot 4) (Commands.i32 0)) =
      .ok (.boolean (decide (base ≠ 0)), world) := by
      simpa using notEqual
    unfold Commands.prefixedReturn
    simp only [Stateful.Acyclic.run?]
    rw [notEqual']
    have decided : decide (base ≠ 0) = false := decide_eq_false (by omega)
    rw [decided]
    simp [Stateful.Acyclic.run?, base, baseZero]
    rfl
  · rw [prefixedReturn_run contract sourceBound nextInBounds
      source[start + 1].val base baseZero
      (Nat.le_trans (selectedPrefixBase_bound source[start + 1].val) (by omega))]
    simp [Stateful.Acyclic.run?, base, baseZero]
    rfl

private theorem prefixedBase_eq_selected
    (source : List Byte) (start : Nat)
    (startInBounds : start < source.length)
    (nextInBounds : start + 1 < source.length)
    (startsZero : source[start].val = 48) :
    let base := selectedPrefixBase source[start + 1].val
    prefixedBase source start = if base = 0 then none else some base := by
  dsimp only
  unfold prefixedBase
  simp [byteValueAt, startInBounds, nextInBounds, startsZero,
    selectedPrefixBase]
  by_cases isHex : source[start + 1].val = 120 ∨
      source[start + 1].val = 88
  · rcases isHex with isX | isUpperX
    · simp [isX]
    · simp [isUpperX]
  · have notX : source[start + 1].val ≠ 120 := fun equal =>
      isHex (.inl equal)
    have notUpperX : source[start + 1].val ≠ 88 := fun equal =>
      isHex (.inr equal)
    simp [notX, notUpperX]
    by_cases isBinary : source[start + 1].val = 98 ∨
        source[start + 1].val = 66
    · rcases isBinary with isB | isUpperB
      · simp [isB]
      · simp [isUpperB]
    · have notB : source[start + 1].val ≠ 98 := fun equal =>
        isBinary (.inl equal)
      have notUpperB : source[start + 1].val ≠ 66 := fun equal =>
        isBinary (.inr equal)
      simp [notB, notUpperB]
      by_cases isOctal : source[start + 1].val = 111 ∨
          source[start + 1].val = 79
      · rcases isOctal with isO | isUpperO
        · simp [isO]
        · simp [isUpperO]
      · have notO : source[start + 1].val ≠ 111 := fun equal =>
          isOctal (.inl equal)
        have notUpperO : source[start + 1].val ≠ 79 := fun equal =>
          isOctal (.inr equal)
        simp [notO, notUpperO]

private theorem prefixedBase_none_of_not_initial
    (source : List Byte) (start : Nat)
    (startInBounds : start < source.length)
    (notInitial : ¬(source[start].val = 48 ∧ start + 1 < source.length)) :
    prefixedBase source start = none := by
  unfold prefixedBase
  by_cases startsZero : source[start].val = 48
  · have nextOutOfBounds : ¬start + 1 < source.length := fun inBounds =>
      notInitial ⟨startsZero, inBounds⟩
    simp [byteValueAt, startInBounds, nextOutOfBounds, startsZero]
  · simp [byteValueAt, startInBounds, startsZero]

theorem scanNumber_run
    (contract : HelperContract calls source world)
    (sourceBound : source.length ≤ 2147483647)
    (sourceFound : world.i32Slice? 0 = some (Model.sourceIntegers source))
    (startInBounds : start < source.length) :
    Stateful.Acyclic.run? (Effectful.machine verifiedFrontendCore calls)
        (commandMachine calls) world
        (Model.environment source start) Commands.scanNumber =
      some (.returned (some (Model.encoded (scanNumber source start))),
        world, Model.environment source start) := by
  unfold Commands.scanNumber
  simp only [Stateful.Acyclic.run?]
  rw [initialCondition_evaluates contract sourceBound sourceFound startInBounds]
  by_cases initial : source[start].val = 48 ∧ start + 1 < source.length
  · have decided : decide
        (source[start].val = 48 ∧ start + 1 < source.length) = true :=
      decide_eq_true initial
    rw [decided]
    simp only [bind, Except.bind]
    rw [prefixedBranch_run contract sourceBound sourceFound initial.2]
    let base := selectedPrefixBase source[start + 1].val
    have selected := prefixedBase_eq_selected source start startInBounds
      initial.2 initial.1
    by_cases baseZero : base = 0
    · dsimp [base] at baseZero selected
      simp only [baseZero, if_pos] at selected ⊢
      rw [decimalBranch_run contract sourceBound start (by omega)]
      simp [scanNumber, selected, base, baseZero,
        Stateful.Acyclic.run?]
      cases scanDigitRun source start 10 <;> rfl
    · dsimp [base] at baseZero selected
      simp only [baseZero, if_neg] at selected ⊢
      simp [scanNumber, selected, base, baseZero,
        Stateful.Acyclic.run?]
      cases scanDigitRun source (start + 2)
        (selectedPrefixBase source[start + 1].val) <;> rfl
  · have decided : decide
        (source[start].val = 48 ∧ start + 1 < source.length) = false :=
      decide_eq_false initial
    rw [decided]
    simp only [bind, Except.bind]
    rw [decimalBranch_run contract sourceBound start (by omega)]
    have selected := prefixedBase_none_of_not_initial source start
      startInBounds initial
    simp [scanNumber, selected, Stateful.Acyclic.run?]
    cases scanDigitRun source start 10 <;> rfl

end Lanius.Extraction.Number.Evaluation
