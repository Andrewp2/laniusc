import Lanius.Extraction.Decimal.EvaluationModel
import Lanius.FunctionalViewStatefulAcyclic

namespace Lanius.Extraction.Decimal.EvaluationTerms

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

@[simp] theorem setLast_push
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

theorem add_evaluates
    (currentEnvironment : Env arity) (left right : Term signature arity)
    (leftValue rightValue : Nat)
    (bound : leftValue + rightValue ≤ 2147483647)
    (leftResult : Term.evaluate (termMachine source) world currentEnvironment left =
      .ok (.signed .i32 leftValue, world))
    (rightResult : Term.evaluate (termMachine source) world currentEnvironment right =
      .ok (.signed .i32 rightValue, world)) :
    Term.evaluate (termMachine source) world currentEnvironment
        (Commands.add left right) =
      .ok (.signed .i32 (leftValue + rightValue), world) := by
  apply Term.evaluate_apply2 leftResult rightResult
  change ReadOnly.evaluateOperation verifiedFrontendCore world
    (.binary .add i32Type i32Type i32Type)
    [.signed .i32 leftValue, .signed .i32 rightValue] = _
  exact ReadOnly.evaluateOperation_i32_add
    (program := verifiedFrontendCore) (world := world)
    (leftType := i32Type) (rightType := i32Type) (outputType := i32Type)
    leftValue rightValue bound

theorem equal_evaluates
    (currentEnvironment : Env arity) (left right : Term signature arity)
    (leftValue rightValue : Nat)
    (leftResult : Term.evaluate (termMachine source) world currentEnvironment left =
      .ok (.signed .i32 leftValue, world))
    (rightResult : Term.evaluate (termMachine source) world currentEnvironment right =
      .ok (.signed .i32 rightValue, world)) :
    Term.evaluate (termMachine source) world currentEnvironment
        (Commands.comparison .equal left right) =
      .ok (.boolean (decide (leftValue = rightValue)), world) := by
  apply Term.evaluate_apply2 leftResult rightResult
  change ReadOnly.evaluateOperation verifiedFrontendCore world
    (.binary .equal i32Type i32Type Commands.boolType)
    [.signed .i32 leftValue, .signed .i32 rightValue] = _
  exact ReadOnly.evaluateOperation_i32_equal
    (program := verifiedFrontendCore) (world := world)
    (leftType := i32Type) (rightType := i32Type)
    (outputType := Commands.boolType) leftValue rightValue

theorem notEqual_evaluates
    (world : ReadOnly.World) (currentEnvironment : Env arity)
    (left right : Term signature arity)
    (leftValue rightValue : Nat)
    (leftResult : Term.evaluate (termMachine source) world currentEnvironment left =
      .ok (.signed .i32 leftValue, world))
    (rightResult : Term.evaluate (termMachine source) world currentEnvironment right =
      .ok (.signed .i32 rightValue, world)) :
    Term.evaluate (termMachine source) world currentEnvironment
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
    (currentEnvironment : Env arity) (left right : Term signature arity)
    (leftValue rightValue : Nat)
    (leftResult : Term.evaluate (termMachine source) world currentEnvironment left =
      .ok (.signed .i32 leftValue, world))
    (rightResult : Term.evaluate (termMachine source) world currentEnvironment right =
      .ok (.signed .i32 rightValue, world)) :
    Term.evaluate (termMachine source) world currentEnvironment
        (Commands.comparison .less left right) =
      .ok (.boolean (decide (leftValue < rightValue)), world) := by
  apply Term.evaluate_apply2 leftResult rightResult
  change ReadOnly.evaluateOperation verifiedFrontendCore world
    (.binary .less i32Type i32Type Commands.boolType)
    [.signed .i32 leftValue, .signed .i32 rightValue] = _
  exact ReadOnly.evaluateOperation_i32_less
    (program := verifiedFrontendCore) (world := world)
    (leftType := i32Type) (rightType := i32Type)
    (outputType := Commands.boolType) leftValue rightValue

theorem greaterEqual_evaluates
    (currentEnvironment : Env arity) (left right : Term signature arity)
    (leftValue rightValue : Nat)
    (leftResult : Term.evaluate (termMachine source) world currentEnvironment left =
      .ok (.signed .i32 leftValue, world))
    (rightResult : Term.evaluate (termMachine source) world currentEnvironment right =
      .ok (.signed .i32 rightValue, world)) :
    Term.evaluate (termMachine source) world currentEnvironment
        (Commands.comparison .greaterEqual left right) =
      .ok (.boolean (decide (rightValue ≤ leftValue)), world) := by
  apply Term.evaluate_apply2 leftResult rightResult
  change ReadOnly.evaluateOperation verifiedFrontendCore world
    (.binary .greaterEqual i32Type i32Type Commands.boolType)
    [.signed .i32 leftValue, .signed .i32 rightValue] = _
  exact ReadOnly.evaluateOperation_i32_greaterEqual
    (program := verifiedFrontendCore) (world := world)
    (leftType := i32Type) (rightType := i32Type)
    (outputType := Commands.boolType) leftValue rightValue

theorem index_evaluates
    (world : ReadOnly.World) (currentEnvironment : Env arity)
    (sourceTerm positionTerm : Term signature arity)
    (position : Nat) (inBounds : position < source.length)
    (sourceFound : world.i32Slice? 0 = some (sourceIntegers source))
    (sourceResult : Term.evaluate (termMachine source) world currentEnvironment
      sourceTerm = .ok (EvaluationModel.sourceSlice source, world))
    (positionResult : Term.evaluate (termMachine source) world currentEnvironment
      positionTerm = .ok (.signed .i32 position, world)) :
    Term.evaluate (termMachine source) world currentEnvironment
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
    (currentEnvironment : Env arity) (term : Term signature arity)
    (value : Bool)
    (termResult : Term.evaluate (termMachine source) world currentEnvironment term =
      .ok (.boolean value, world)) :
    Term.evaluate (termMachine source) world currentEnvironment
        (Commands.unary .logicalNot term) =
      .ok (.boolean (!value), world) := by
  apply Term.evaluate_apply1 termResult
  rfl

theorem logicalOr_evaluates
    (currentEnvironment : Env arity) (left right : Term signature arity)
    (leftValue rightValue : Bool)
    (leftResult : Term.evaluate (termMachine source) world currentEnvironment left =
      .ok (.boolean leftValue, world))
    (rightResult : Term.evaluate (termMachine source) world currentEnvironment right =
      .ok (.boolean rightValue, world)) :
    Term.evaluate (termMachine source) world currentEnvironment
        (.logicalOr left right) =
      .ok (.boolean (leftValue || rightValue), world) := by
  cases leftValue <;> simp only [Bool.false_or, Bool.true_or]
  · exact Term.evaluate_logicalOr_false leftResult rightResult
  · exact Term.evaluate_logicalOr_true leftResult

theorem digitRun_evaluates
    (currentEnvironment : Env arity)
    (sourceTerm boundTerm startTerm baseTerm : Term signature arity)
    (start base : Nat)
    (sourceFound : world.i32Slice? 0 = some (sourceIntegers source))
    (sourceBound : source.length ≤ 2147483647)
    (startBound : start ≤ 2147483647) (baseBound : base ≤ 2147483647)
    (sourceResult : Term.evaluate (termMachine source) world currentEnvironment
      sourceTerm = .ok (EvaluationModel.sourceSlice source, world))
    (boundResult : Term.evaluate (termMachine source) world currentEnvironment
      boundTerm = .ok (.signed .i32 source.length, world))
    (startResult : Term.evaluate (termMachine source) world currentEnvironment
      startTerm = .ok (.signed .i32 start, world))
    (baseResult : Term.evaluate (termMachine source) world currentEnvironment
      baseTerm = .ok (.signed .i32 base, world)) :
    Term.evaluate (termMachine source) world currentEnvironment
        (Commands.digitCall sourceTerm boundTerm startTerm baseTerm) =
      .ok (digitScanValue (scanDigitRun source start base), world) := by
  unfold Commands.digitCall Commands.call
  apply Term.evaluate_apply
  · exact evaluateTerms_cons sourceResult
      (evaluateTerms_cons boundResult
        (evaluateTerms_cons startResult
          (evaluateTerms_cons baseResult (evaluateTerms_nil _ _ _))))
  · exact EvaluationModel.scanDigitRun source world start base sourceFound
      sourceBound startBound baseBound

theorem digitSucceeded_evaluates
    (currentEnvironment : Env arity) (term : Term signature arity)
    (result : DigitScanResult)
    (resultBound : match result with
      | .success offset | .failure offset => offset ≤ 2147483647)
    (termResult : Term.evaluate (termMachine source) world currentEnvironment term =
      .ok (digitScanValue result, world)) :
    Term.evaluate (termMachine source) world currentEnvironment
        (Commands.digitSucceeded term) =
      .ok (.boolean (match result with
        | .success _ => true | .failure _ => false), world) := by
  cases result with
  | success finish =>
    unfold Commands.digitSucceeded Commands.call
    apply Term.evaluate_apply1 termResult
    change (helperCalls source).evaluate world
      Lexer.Digits.digitScanSucceededFunction.id
        [digitScanValue (.success finish)] = _
    exact EvaluationModel.digitSucceeded source world (.success finish)
      resultBound
  | failure error =>
    unfold Commands.digitSucceeded Commands.call
    apply Term.evaluate_apply1 termResult
    change (helperCalls source).evaluate world
      Lexer.Digits.digitScanSucceededFunction.id
        [digitScanValue (.failure error)] = _
    exact EvaluationModel.digitSucceeded source world (.failure error)
      resultBound

theorem digitEnd_evaluates
    (currentEnvironment : Env arity) (term : Term signature arity)
    (finish : Nat) (finishBound : finish ≤ 2147483647)
    (termResult : Term.evaluate (termMachine source) world currentEnvironment term =
      .ok (digitScanValue (.success finish), world)) :
    Term.evaluate (termMachine source) world currentEnvironment
        (Commands.digitEnd term) = .ok (.signed .i32 finish, world) := by
  unfold Commands.digitEnd Commands.call
  apply Term.evaluate_apply1 termResult
  change (helperCalls source).evaluate world
    Lexer.Digits.digitScanEndOffsetFunction.id
      [digitScanValue (.success finish)] = _
  exact EvaluationModel.digitEnd source world finish finishBound

theorem digitError_evaluates
    (currentEnvironment : Env arity) (term : Term signature arity)
    (error : Nat) (errorBound : error ≤ 2147483647)
    (termResult : Term.evaluate (termMachine source) world currentEnvironment term =
      .ok (digitScanValue (.failure error), world)) :
    Term.evaluate (termMachine source) world currentEnvironment
        (Commands.digitError term) = .ok (.signed .i32 error, world) := by
  unfold Commands.digitError Commands.call
  apply Term.evaluate_apply1 termResult
  change (helperCalls source).evaluate world
    Lexer.Digits.digitScanErrorOffsetFunction.id
      [digitScanValue (.failure error)] = _
  exact EvaluationModel.digitError source world error errorBound

theorem integerScan_evaluates
    (currentEnvironment : Env arity) (offsetTerm : Term signature arity)
    (offset : Nat) (offsetBound : offset ≤ 2147483647)
    (offsetResult : Term.evaluate (termMachine source) world currentEnvironment
      offsetTerm = .ok (.signed .i32 offset, world)) :
    Term.evaluate (termMachine source) world currentEnvironment
        (Commands.integerScan offsetTerm) =
      .ok (encoded (.success .integer offset), world) := by
  unfold Commands.integerScan Commands.call
  apply Term.evaluate_apply1 offsetResult
  exact EvaluationModel.integerScan source world offset offsetBound

theorem floatScan_evaluates
    (currentEnvironment : Env arity) (offsetTerm : Term signature arity)
    (offset : Nat) (offsetBound : offset ≤ 2147483647)
    (offsetResult : Term.evaluate (termMachine source) world currentEnvironment
      offsetTerm = .ok (.signed .i32 offset, world)) :
    Term.evaluate (termMachine source) world currentEnvironment
        (Commands.floatScan offsetTerm) =
      .ok (encoded (.success .float offset), world) := by
  unfold Commands.floatScan Commands.call
  apply Term.evaluate_apply1 offsetResult
  exact EvaluationModel.floatScan source world offset offsetBound

theorem numberFailure_evaluates
    (currentEnvironment : Env arity) (offsetTerm : Term signature arity)
    (offset : Nat) (offsetBound : offset ≤ 2147483647)
    (offsetResult : Term.evaluate (termMachine source) world currentEnvironment
      offsetTerm = .ok (.signed .i32 offset, world)) :
    Term.evaluate (termMachine source) world currentEnvironment
        (Commands.numberFailure offsetTerm) =
      .ok (encoded (.failure offset), world) := by
  unfold Commands.numberFailure Commands.call
  apply Term.evaluate_apply1 offsetResult
  exact EvaluationModel.numberFailure source world offset offsetBound

end Lanius.Extraction.Decimal.EvaluationTerms
