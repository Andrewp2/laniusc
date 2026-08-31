import Lanius.Extraction.Decimal.FinishEvaluationModel

namespace Lanius.Extraction.Decimal.FinishEvaluationTerms

open Lanius
open Lanius.Core
open Lanius.Compiler.Lexer
open Lanius.Compiler.Lexer.Program
open Lanius.Extraction
open Lanius.FunctionalView
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.ReadOnly
open Lanius.FunctionalView.Core.Effectful
open Lanius.Extraction.Decimal
open Lanius.Extraction.Decimal.EvaluationModel
open Lanius.Extraction.Decimal.FinishEvaluationModel

local notation "termMachine" => FinishEvaluationModel.termMachine

theorem add_evaluates
    (environment : Env arity) (left right : Term signature arity)
    (leftValue rightValue : Nat)
    (bound : leftValue + rightValue ≤ 2147483647)
    (leftResult : Term.evaluate (termMachine source) world environment left =
      .ok (.signed .i32 leftValue, world))
    (rightResult : Term.evaluate (termMachine source) world environment right =
      .ok (.signed .i32 rightValue, world)) :
    Term.evaluate (termMachine source) world environment
      (Commands.add left right) =
      .ok (.signed .i32 (leftValue + rightValue), world) := by
  apply Term.evaluate_apply2 leftResult rightResult
  exact ReadOnly.evaluateOperation_i32_add
    (program := verifiedFrontendCore) (world := world)
    (leftType := i32Type) (rightType := i32Type) (outputType := i32Type)
    leftValue rightValue bound

theorem equal_evaluates
    (environment : Env arity) (left right : Term signature arity)
    (leftValue rightValue : Nat)
    (leftResult : Term.evaluate (termMachine source) world environment left =
      .ok (.signed .i32 leftValue, world))
    (rightResult : Term.evaluate (termMachine source) world environment right =
      .ok (.signed .i32 rightValue, world)) :
    Term.evaluate (termMachine source) world environment
      (Commands.comparison .equal left right) =
      .ok (.boolean (decide (leftValue = rightValue)), world) := by
  apply Term.evaluate_apply2 leftResult rightResult
  exact ReadOnly.evaluateOperation_i32_equal
    (program := verifiedFrontendCore) (world := world)
    (leftType := i32Type) (rightType := i32Type)
    (outputType := Commands.boolType) leftValue rightValue

theorem notEqual_evaluates
    (environment : Env arity) (left right : Term signature arity)
    (leftValue rightValue : Nat)
    (leftResult : Term.evaluate (termMachine source) world environment left =
      .ok (.signed .i32 leftValue, world))
    (rightResult : Term.evaluate (termMachine source) world environment right =
      .ok (.signed .i32 rightValue, world)) :
    Term.evaluate (termMachine source) world environment
      (Commands.comparison .notEqual left right) =
      .ok (.boolean (decide (leftValue ≠ rightValue)), world) := by
  apply Term.evaluate_apply2 leftResult rightResult
  change ReadOnly.evaluateOperation verifiedFrontendCore world
    (.binary .notEqual i32Type i32Type Commands.boolType)
    [.signed .i32 leftValue, .signed .i32 rightValue] = _
  calc
    _ = .ok (.boolean (decide
        ((Int.ofNat leftValue) ≠ Int.ofNat rightValue)), world) :=
      ReadOnly.evaluateOperation_i32_notEqual_int
        (program := verifiedFrontendCore) (world := world)
        (leftType := i32Type) (rightType := i32Type)
        (outputType := Commands.boolType)
        (Int.ofNat leftValue) (Int.ofNat rightValue)
    _ = _ := by
      apply congrArg (fun flag : Bool =>
        (Except.ok (.boolean flag, (world : ReadOnly.World)) :
          Except Trap (Value × ReadOnly.World)))
      by_cases same : leftValue = rightValue
      · subst rightValue
        simp
      · have castDifferent : (Int.ofNat leftValue) ≠ Int.ofNat rightValue :=
          fun equal => same (Int.ofNat_inj.mp equal)
        simp [same]
        exact castDifferent

theorem less_evaluates
    (environment : Env arity) (left right : Term signature arity)
    (leftValue rightValue : Nat)
    (leftResult : Term.evaluate (termMachine source) world environment left =
      .ok (.signed .i32 leftValue, world))
    (rightResult : Term.evaluate (termMachine source) world environment right =
      .ok (.signed .i32 rightValue, world)) :
    Term.evaluate (termMachine source) world environment
      (Commands.comparison .less left right) =
      .ok (.boolean (decide (leftValue < rightValue)), world) := by
  apply Term.evaluate_apply2 leftResult rightResult
  exact ReadOnly.evaluateOperation_i32_less
    (program := verifiedFrontendCore) (world := world)
    (leftType := i32Type) (rightType := i32Type)
    (outputType := Commands.boolType) leftValue rightValue

theorem greaterEqual_evaluates
    (environment : Env arity) (left right : Term signature arity)
    (leftValue rightValue : Nat)
    (leftResult : Term.evaluate (termMachine source) world environment left =
      .ok (.signed .i32 leftValue, world))
    (rightResult : Term.evaluate (termMachine source) world environment right =
      .ok (.signed .i32 rightValue, world)) :
    Term.evaluate (termMachine source) world environment
      (Commands.comparison .greaterEqual left right) =
      .ok (.boolean (decide (rightValue ≤ leftValue)), world) := by
  apply Term.evaluate_apply2 leftResult rightResult
  exact ReadOnly.evaluateOperation_i32_greaterEqual
    (program := verifiedFrontendCore) (world := world)
    (leftType := i32Type) (rightType := i32Type)
    (outputType := Commands.boolType) leftValue rightValue

theorem index_evaluates
    (environment : Env arity) (sourceTerm positionTerm : Term signature arity)
    (position : Nat) (inBounds : position < source.length)
    (sourceFound : world.i32Slice? 0 = some (sourceIntegers source))
    (sourceResult : Term.evaluate (termMachine source) world environment
      sourceTerm = .ok (EvaluationModel.sourceSlice source, world))
    (positionResult : Term.evaluate (termMachine source) world environment
      positionTerm = .ok (.signed .i32 position, world)) :
    Term.evaluate (termMachine source) world environment
      (Commands.index sourceTerm positionTerm) =
      .ok (.signed .i32 (source.get ⟨position, inBounds⟩).val, world) := by
  apply Term.evaluate_apply2 sourceResult positionResult
  change ReadOnly.evaluateOperation verifiedFrontendCore world
    (.index Commands.sliceType i32Type i32Type)
    [EvaluationModel.sourceSlice source, .signed .i32 position] = _
  have operation := ReadOnly.evaluateOperation_i32_index
    (program := verifiedFrontendCore) (world := world) (cell := 0)
    (values := sourceIntegers source) (position := position)
    (baseType := Commands.sliceType) (indexType := i32Type)
    (elementType := i32Type) sourceFound (by
      simpa [sourceIntegers, DigitRunModel.sourceIntegers] using inBounds)
  let sourcePosition : Fin (sourceIntegers source).length :=
    ⟨position, by
      simpa [sourceIntegers, DigitRunModel.sourceIntegers] using inBounds⟩
  have operation' : ReadOnly.evaluateOperation verifiedFrontendCore world
      (.index Commands.sliceType i32Type i32Type)
      [EvaluationModel.sourceSlice source, .signed .i32 position] =
    .ok (.signed .i32 ((sourceIntegers source).get sourcePosition), world) := by
    simpa [EvaluationModel.sourceSlice, sourceIntegers,
      DigitRunModel.sourceSlice, DigitRunModel.sourceIntegers, Program.i32Type,
      sourcePosition] using operation
  rw [operation']
  congr 3
  simp [sourceIntegers, DigitRunModel.sourceIntegers, sourcePosition]

theorem logicalNot_evaluates
    (environment : Env arity) (term : Term signature arity) (value : Bool)
    (termResult : Term.evaluate (termMachine source) world environment term =
      .ok (.boolean value, world)) :
    Term.evaluate (termMachine source) world environment
      (Commands.unary .logicalNot term) = .ok (.boolean (!value), world) := by
  apply Term.evaluate_apply1 termResult
  rfl

theorem logicalOr_evaluates
    (environment : Env arity) (left right : Term signature arity)
    (leftValue rightValue : Bool)
    (leftResult : Term.evaluate (termMachine source) world environment left =
      .ok (.boolean leftValue, world))
    (rightResult : Term.evaluate (termMachine source) world environment right =
      .ok (.boolean rightValue, world)) :
    Term.evaluate (termMachine source) world environment (.logicalOr left right) =
      .ok (.boolean (leftValue || rightValue), world) := by
  cases leftValue
  · exact Term.evaluate_logicalOr_false leftResult rightResult
  · exact Term.evaluate_logicalOr_true leftResult

theorem isDigit_evaluates
    (environment : Env arity) (byteTerm radixTerm : Term signature arity)
    (byte : Byte) (radix : Nat) (radixBound : radix ≤ 2147483647)
    (byteResult : Term.evaluate (termMachine source) world environment byteTerm =
      .ok (.signed .i32 byte.val, world))
    (radixResult : Term.evaluate (termMachine source) world environment radixTerm =
      .ok (.signed .i32 radix, world)) :
    Term.evaluate (termMachine source) world environment
      (Commands.isDigit byteTerm radixTerm) =
      .ok (.boolean (isDigitForBase byte radix), world) := by
  unfold Commands.isDigit Commands.call
  apply Term.evaluate_apply2 byteResult radixResult
  exact FinishEvaluationModel.isDigit source world byte radix radixBound

theorem digitRun_evaluates
    (environment : Env arity)
    (sourceTerm boundTerm startTerm radixTerm : Term signature arity)
    (start radix : Nat)
    (sourceFound : world.i32Slice? 0 = some (sourceIntegers source))
    (sourceBound : source.length ≤ 2147483647)
    (startBound : start ≤ 2147483647) (radixBound : radix ≤ 2147483647)
    (sourceResult : Term.evaluate (termMachine source) world environment
      sourceTerm = .ok (EvaluationModel.sourceSlice source, world))
    (boundResult : Term.evaluate (termMachine source) world environment
      boundTerm = .ok (.signed .i32 source.length, world))
    (startResult : Term.evaluate (termMachine source) world environment
      startTerm = .ok (.signed .i32 start, world))
    (radixResult : Term.evaluate (termMachine source) world environment
      radixTerm = .ok (.signed .i32 radix, world)) :
    Term.evaluate (termMachine source) world environment
      (Commands.digitCall sourceTerm boundTerm startTerm radixTerm) =
      .ok (digitScanValue (scanDigitRun source start radix), world) := by
  unfold Commands.digitCall Commands.call
  apply Term.evaluate_apply
  · exact evaluateTerms_cons sourceResult (evaluateTerms_cons boundResult
      (evaluateTerms_cons startResult
        (evaluateTerms_cons radixResult (evaluateTerms_nil _ _ _))))
  · exact FinishEvaluationModel.scanDigitRun source world start radix
      sourceFound sourceBound startBound radixBound

theorem digitSucceeded_evaluates
    (environment : Env arity) (term : Term signature arity)
    (result : DigitScanResult)
    (resultBound : match result with
      | .success offset | .failure offset => offset ≤ 2147483647)
    (termResult : Term.evaluate (termMachine source) world environment term =
      .ok (digitScanValue result, world)) :
    Term.evaluate (termMachine source) world environment
      (Commands.digitSucceeded term) =
      .ok (.boolean (match result with
        | .success _ => true | .failure _ => false), world) := by
  cases result with
  | success finish =>
      unfold Commands.digitSucceeded Commands.call
      apply Term.evaluate_apply1 termResult
      exact FinishEvaluationModel.digitSucceeded source world
        (.success finish) resultBound
  | failure error =>
      unfold Commands.digitSucceeded Commands.call
      apply Term.evaluate_apply1 termResult
      exact FinishEvaluationModel.digitSucceeded source world
        (.failure error) resultBound

theorem digitEnd_evaluates
    (environment : Env arity) (term : Term signature arity)
    (finish : Nat) (finishBound : finish ≤ 2147483647)
    (termResult : Term.evaluate (termMachine source) world environment term =
      .ok (digitScanValue (.success finish), world)) :
    Term.evaluate (termMachine source) world environment
      (Commands.digitEnd term) = .ok (.signed .i32 finish, world) := by
  unfold Commands.digitEnd Commands.call
  apply Term.evaluate_apply1 termResult
  exact FinishEvaluationModel.digitEnd source world finish finishBound

theorem digitError_evaluates
    (environment : Env arity) (term : Term signature arity)
    (error : Nat) (errorBound : error ≤ 2147483647)
    (termResult : Term.evaluate (termMachine source) world environment term =
      .ok (digitScanValue (.failure error), world)) :
    Term.evaluate (termMachine source) world environment
      (Commands.digitError term) = .ok (.signed .i32 error, world) := by
  unfold Commands.digitError Commands.call
  apply Term.evaluate_apply1 termResult
  exact FinishEvaluationModel.digitError source world error errorBound

theorem integerScan_evaluates
    (environment : Env arity) (term : Term signature arity)
    (offset : Nat) (bound : offset ≤ 2147483647)
    (termResult : Term.evaluate (termMachine source) world environment term =
      .ok (.signed .i32 offset, world)) :
    Term.evaluate (termMachine source) world environment
      (Commands.integerScan term) =
      .ok (encoded (.success .integer offset), world) := by
  unfold Commands.integerScan Commands.call
  apply Term.evaluate_apply1 termResult
  exact FinishEvaluationModel.integerScan source world offset bound

theorem floatScan_evaluates
    (environment : Env arity) (term : Term signature arity)
    (offset : Nat) (bound : offset ≤ 2147483647)
    (termResult : Term.evaluate (termMachine source) world environment term =
      .ok (.signed .i32 offset, world)) :
    Term.evaluate (termMachine source) world environment
      (Commands.floatScan term) =
      .ok (encoded (.success .float offset), world) := by
  unfold Commands.floatScan Commands.call
  apply Term.evaluate_apply1 termResult
  exact FinishEvaluationModel.floatScan source world offset bound

theorem numberFailure_evaluates
    (environment : Env arity) (term : Term signature arity)
    (offset : Nat) (bound : offset ≤ 2147483647)
    (termResult : Term.evaluate (termMachine source) world environment term =
      .ok (.signed .i32 offset, world)) :
    Term.evaluate (termMachine source) world environment
      (Commands.numberFailure term) = .ok (encoded (.failure offset), world) := by
  unfold Commands.numberFailure Commands.call
  apply Term.evaluate_apply1 termResult
  exact FinishEvaluationModel.numberFailure source world offset bound

theorem scanExponent_evaluates
    (environment : Env arity) (sourceTerm boundTerm startTerm : Term signature arity)
    (start : Nat)
    (sourceFound : world.i32Slice? 0 = some (sourceIntegers source))
    (sourceBound : source.length ≤ 2147483647)
    (startInBounds : start < source.length)
    (sourceResult : Term.evaluate (termMachine source) world environment
      sourceTerm = .ok (EvaluationModel.sourceSlice source, world))
    (boundResult : Term.evaluate (termMachine source) world environment
      boundTerm = .ok (.signed .i32 source.length, world))
    (startResult : Term.evaluate (termMachine source) world environment
      startTerm = .ok (.signed .i32 start, world)) :
    Term.evaluate (termMachine source) world environment
      (Commands.scanExponentCall sourceTerm boundTerm startTerm) =
      .ok (encoded (scanExponent source start), world) := by
  unfold Commands.scanExponentCall Commands.call
  apply Term.evaluate_apply
  · exact evaluateTerms_cons sourceResult (evaluateTerms_cons boundResult
      (evaluateTerms_cons startResult (evaluateTerms_nil _ _ _)))
  · exact FinishEvaluationModel.scanExponent source world start sourceFound
      sourceBound startInBounds

end Lanius.Extraction.Decimal.FinishEvaluationTerms
