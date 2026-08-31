import Lanius.Extraction.Decimal.Functions
import Lanius.Extraction.Lexer.Digits
import Lanius.FunctionalViewCoreReadOnly

namespace Lanius.Extraction.Decimal.Dependencies

open Lanius
open Lanius.Core
open Lanius.Semantics
open Lanius.Properties
open Lanius.CallContracts
open Lanius.Separation
open Lanius.Compiler
open Lanius.Compiler.Lexer
open Lanius.Compiler.Lexer.Program
open Lanius.Extraction
open Lanius.FunctionalView
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.ReadOnly
open Lanius.Extraction.Lexer

def emptyWorld : World := { i32Slice? := fun _ => none }

def digitEnvironment (byte base : Nat) : Env 2
  | ⟨0, _⟩ => .signed .i32 byte
  | ⟨1, _⟩ => .signed .i32 base

private abbrev T := Term signature 2
private abbrev B := Block signature 2
private def slot (index : Fin 2) : T := reference index
private def i32 (value : Int) : T := literal (.signed .i32 value)
private def binary (operation : BinaryOp) (left right : T)
    (result : Ty) : T :=
  apply (.binary operation i32Type i32Type result) [left, right]
private def conjunction (left right : T) : T :=
  Lanius.FunctionalView.Core.logicalAnd left right

private def inRange (lower upper : Int) : T :=
  conjunction
    (binary .greaterEqual (slot 0) (i32 lower) (.scalar .bool))
    (binary .lessEqual (slot 0) (i32 upper) (.scalar .bool))

private def decimalValue : T :=
  binary .less (binary .subtract (slot 0) (i32 48) i32Type) (slot 1)
    (.scalar .bool)

private def adjustedValue (lower adjustment : Int) : T :=
  binary .less
    (binary .add (binary .subtract (slot 0) (i32 lower) i32Type)
      (i32 adjustment) i32Type)
    (slot 1) (.scalar .bool)

def isDigitForBaseBlock : B :=
  .sequence
    (.ifThenElse (inRange 48 57) (.returnValue (some decimalValue)) .skip)
    (.sequence
      (.ifThenElse (inRange 97 102)
        (.returnValue (some (adjustedValue 97 10))) .skip)
      (.sequence
        (.ifThenElse (inRange 65 70)
          (.returnValue (some (adjustedValue 65 10))) .skip)
        (.returnValue (some (literal (.boolean false))))))

theorem isDigitForBaseBody_normalizes :
    removeTrailingSkips Digits.isDigitForBaseBody =
      toCoreStmt (identityLayout (arity := 2)) 2 isDigitForBaseBlock := by
  rfl

theorem isDigitForBaseBody_normalization_supported :
    SkipNormalizationSupported Digits.isDigitForBaseBody := by
  native_decide

private theorem decideAnd_eq_false_of_not
    {left right : Prop} [Decidable left] [Decidable right]
    (notBoth : ¬ (left ∧ right)) :
    (decide left && decide right) = false := by
  apply Bool.eq_false_iff.mpr
  intro bothTrue
  have decided := Bool.and_eq_true_iff.mp bothTrue
  exact notBoth ⟨of_decide_eq_true decided.1, of_decide_eq_true decided.2⟩

private theorem inRange_evaluates (byte lower upper base : Nat) :
    Term.evaluate (machine verifiedFrontendCore) emptyWorld
        (digitEnvironment byte base) (inRange lower upper) =
      .ok (.boolean
        (decide (lower ≤ byte) && decide (byte ≤ upper)), emptyWorld) := by
  simpa [Int.ofNat_le] using (show
    Term.evaluate (machine verifiedFrontendCore) emptyWorld
        (digitEnvironment byte base) (inRange lower upper) =
      .ok (.boolean
        (decide ((Int.ofNat lower) ≤ Int.ofNat byte) &&
          decide (Int.ofNat byte ≤ Int.ofNat upper)), emptyWorld) by
    simp only [inRange, conjunction, binary, slot, i32,
      Lanius.FunctionalView.Core.apply, Lanius.FunctionalView.Core.reference,
      Lanius.FunctionalView.Core.literal]
    functional_eval)

private theorem decimalValue_evaluates (byte base : Nat)
    (lower : 48 ≤ byte) (bounded : byte - 48 ≤ 2147483647) :
    Term.evaluate (machine verifiedFrontendCore) emptyWorld
        (digitEnvironment byte base) decimalValue =
      .ok (.boolean (decide (byte - 48 < base)), emptyWorld) := by
  simp only [decimalValue, binary, slot, i32,
    Lanius.FunctionalView.Core.apply, Lanius.FunctionalView.Core.reference,
    Lanius.FunctionalView.Core.literal]
  functional_eval

private theorem adjustedValue_evaluates (byte base lower adjustment : Nat)
    (lowerBound : lower ≤ byte)
    (bounded : byte - lower + adjustment ≤ 2147483647) :
    Term.evaluate (machine verifiedFrontendCore) emptyWorld
        (digitEnvironment byte base) (adjustedValue lower adjustment) =
      .ok (.boolean (decide (byte - lower + adjustment < base)), emptyWorld) := by
  simp only [adjustedValue, binary, slot, i32,
    Lanius.FunctionalView.Core.apply, Lanius.FunctionalView.Core.reference,
    Lanius.FunctionalView.Core.literal]
  functional_eval

theorem isDigitForBaseBlock_evaluates (byte : Byte) (base : Nat) :
    Block.evaluate (machine verifiedFrontendCore) emptyWorld
        (digitEnvironment byte.val base) isDigitForBaseBlock =
      .done (.returned (some (.boolean (isDigitForBase byte base))))
        emptyWorld := by
  have decimalCondition := inRange_evaluates byte.val 48 57 base
  by_cases decimal : 48 ≤ byte.val ∧ byte.val ≤ 57
  · have condition : Term.evaluate (machine verifiedFrontendCore) emptyWorld
        (digitEnvironment byte.val base) (inRange 48 57) =
        .ok (.boolean true, emptyWorld) := by
      simpa [decimal.1, decimal.2] using decimalCondition
    have value := decimalValue_evaluates byte.val base decimal.1 (by omega)
    simp [isDigitForBase, decimal.1, decimal.2]
    rw [isDigitForBaseBlock]
    apply Block.evaluate_sequence_returned
    apply Block.evaluate_if_true condition
    exact Block.evaluate_returnValue value
  · have decimalFalse :
        (decide (48 ≤ byte.val) && decide (byte.val ≤ 57)) = false :=
      decideAnd_eq_false_of_not decimal
    have condition : Term.evaluate (machine verifiedFrontendCore) emptyWorld
        (digitEnvironment byte.val base) (inRange 48 57) =
        .ok (.boolean false, emptyWorld) := by
      simpa [decimalFalse] using decimalCondition
    have lowercaseCondition := inRange_evaluates byte.val 97 102 base
    by_cases lowercase : 97 ≤ byte.val ∧ byte.val ≤ 102
    · have lowerTrue : Term.evaluate (machine verifiedFrontendCore) emptyWorld
          (digitEnvironment byte.val base) (inRange 97 102) =
          .ok (.boolean true, emptyWorld) := by
        simpa [lowercase.1, lowercase.2] using lowercaseCondition
      have value := adjustedValue_evaluates byte.val base 97 10 lowercase.1
        (by omega)
      simp [isDigitForBase, decimal, lowercase.1, lowercase.2]
      rw [isDigitForBaseBlock]
      apply Block.evaluate_sequence_next
      · exact Block.evaluate_if_false condition (Block.evaluate_skip _ _ _)
      apply Block.evaluate_sequence_returned
      apply Block.evaluate_if_true lowerTrue
      exact Block.evaluate_returnValue value
    · have lowercaseFalse :
          (decide (97 ≤ byte.val) && decide (byte.val ≤ 102)) = false :=
        decideAnd_eq_false_of_not lowercase
      have lowerFalse : Term.evaluate (machine verifiedFrontendCore) emptyWorld
          (digitEnvironment byte.val base) (inRange 97 102) =
          .ok (.boolean false, emptyWorld) := by
        simpa [lowercaseFalse] using lowercaseCondition
      have uppercaseCondition := inRange_evaluates byte.val 65 70 base
      by_cases uppercase : 65 ≤ byte.val ∧ byte.val ≤ 70
      · have upperTrue : Term.evaluate (machine verifiedFrontendCore)
            emptyWorld (digitEnvironment byte.val base) (inRange 65 70) =
            .ok (.boolean true, emptyWorld) := by
          simpa [uppercase.1, uppercase.2] using uppercaseCondition
        have value := adjustedValue_evaluates byte.val base 65 10 uppercase.1
          (by omega)
        simp [isDigitForBase, decimal, lowercase, uppercase.1, uppercase.2]
        rw [isDigitForBaseBlock]
        apply Block.evaluate_sequence_next
        · exact Block.evaluate_if_false condition (Block.evaluate_skip _ _ _)
        apply Block.evaluate_sequence_next
        · exact Block.evaluate_if_false lowerFalse (Block.evaluate_skip _ _ _)
        apply Block.evaluate_sequence_returned
        apply Block.evaluate_if_true upperTrue
        exact Block.evaluate_returnValue value
      · have uppercaseFalse :
            (decide (65 ≤ byte.val) && decide (byte.val ≤ 70)) = false :=
          decideAnd_eq_false_of_not uppercase
        have upperFalse : Term.evaluate (machine verifiedFrontendCore)
            emptyWorld (digitEnvironment byte.val base) (inRange 65 70) =
            .ok (.boolean false, emptyWorld) := by
          simpa [uppercaseFalse] using uppercaseCondition
        simp [isDigitForBase, decimal, lowercase, uppercase]
        rw [isDigitForBaseBlock]
        apply Block.evaluate_sequence_next
        · exact Block.evaluate_if_false condition (Block.evaluate_skip _ _ _)
        apply Block.evaluate_sequence_next
        · exact Block.evaluate_if_false lowerFalse (Block.evaluate_skip _ _ _)
        apply Block.evaluate_sequence_next
        · exact Block.evaluate_if_false upperFalse (Block.evaluate_skip _ _ _)
        rfl

theorem isDigitForBaseBody_executes
    (state : State) (wellFormed : StateWellFormed state)
    (byte : Byte) (base : Nat) :
    Executes verifiedFrontendCore
      (twoI32CalleeState state byte.val base) Digits.isDigitForBaseBody
      (.returned (some (.boolean (isDigitForBase byte base))))
      (twoI32CalleeState state byte.val base) := by
  let callee := twoI32CalleeState state byte.val base
  have environmentMatches : EnvironmentMatches
      (identityLayout (arity := 2)) (digitEnvironment byte.val base) callee := by
    intro index
    refine Fin.cases ?_
      (fun second => Fin.cases ?_ (fun impossible => Fin.elim0 impossible)
        second) index
    · simpa [callee, digitEnvironment, identityLayout] using
        twoI32CalleeState_left state wellFormed byte.val base
    · simpa [callee, digitEnvironment, identityLayout] using
        twoI32CalleeState_right state wellFormed byte.val base
  have represented : ReadOnly.World.Represents emptyWorld callee := by
    intro _ _ found
    simp [emptyWorld] at found
  have sound := block_executes_without_locals
    (nextLocal := 2) (ReadOnly.bridge verifiedFrontendCore) represented
    environmentMatches (by rfl) (isDigitForBaseBlock_evaluates byte base)
  rw [← isDigitForBaseBody_normalizes] at sound
  exact removeTrailingSkips_executes_complete
    isDigitForBaseBody_normalization_supported (by
      simpa [callee, toCoreCompletion] using sound.1)

theorem verifiedFrontendCore_finds_isDigitForBase :
    verifiedFrontendCore.function? extractedIsDigitForBaseFunction.id =
      some extractedIsDigitForBaseFunction := by
  rfl

theorem isDigitForBaseCall_executes
    (state : State) (wellFormed : StateWellFormed state)
    (byteExpr baseExpr : Expr) (byte : Byte) (base : Nat)
    (byteResult : Evaluates verifiedFrontendCore state byteExpr
      (.signed .i32 byte.val) state)
    (baseResult : Evaluates verifiedFrontendCore state baseExpr
      (.signed .i32 base) state) :
    Evaluates verifiedFrontendCore state
      (callIsDigitForBase byteExpr baseExpr)
      (.boolean (isDigitForBase byte base))
      (twoI32CallState state byte.val base) := by
  have arguments := Lanius.CallContracts.ArgumentsEvaluateTo.cons byteResult
    (Lanius.CallContracts.ArgumentsEvaluateTo.singleton baseResult)
  have parametersBound :
      bindParameters extractedIsDigitForBaseFunction.parameters
          [.signed .i32 byte.val, .signed .i32 base] =
        some [(0, .signed .i32 byte.val), (1, .signed .i32 base)] := by
    rfl
  have bodyResult : Executes verifiedFrontendCore
      (enterCall state
        [(0, .signed .i32 byte.val), (1, .signed .i32 base)])
      Digits.isDigitForBaseBody
      (.returned (some (.boolean (isDigitForBase byte base))))
      (twoI32CalleeState state byte.val base) := by
    simpa [enterCall, twoI32CalleeState, clearLocals] using
      isDigitForBaseBody_executes state wellFormed byte base
  have evaluated := Lanius.CallContracts.evaluatesCallReturned
    (bindings := [(0, .signed .i32 byte.val), (1, .signed .i32 base)])
    (body := Digits.isDigitForBaseBody) arguments
    verifiedFrontendCore_finds_isDigitForBase parametersBound
    (show extractedIsDigitForBaseFunction.body =
      some Digits.isDigitForBaseBody by rfl) bodyResult
  have sameId : extractedIsDigitForBaseFunction.id =
      isDigitForBaseFunction.id := by native_decide
  rw [sameId] at evaluated
  simpa [callIsDigitForBase, twoI32CallState] using evaluated

def offsetEnvironment (offset : Nat) : Env 1 :=
  fun _ => .signed .i32 offset

def successfulDigitsBlock : Block signature 1 :=
  .returnValue (some (apply (.structValue 2
    [.scalar .bool, i32Type, i32Type])
    [literal (.boolean true), reference 0, literal (.signed .i32 0)]))

def failedDigitsBlock : Block signature 1 :=
  .returnValue (some (apply (.structValue 2
    [.scalar .bool, i32Type, i32Type])
    [literal (.boolean false), literal (.signed .i32 0), reference 0]))

theorem successfulDigitsBody_normalizes :
    removeTrailingSkips Digits.successfulDigitsBody =
      toCoreStmt (identityLayout (arity := 1)) 1 successfulDigitsBlock := by
  rfl

theorem failedDigitsBody_normalizes :
    removeTrailingSkips Digits.failedDigitsBody =
      toCoreStmt (identityLayout (arity := 1)) 1 failedDigitsBlock := by
  rfl

theorem successfulDigitsBody_normalization_supported :
    SkipNormalizationSupported Digits.successfulDigitsBody := by native_decide

theorem failedDigitsBody_normalization_supported :
    SkipNormalizationSupported Digits.failedDigitsBody := by native_decide

theorem successfulDigitsBlock_evaluates (offset : Nat) :
    Block.evaluate (machine verifiedFrontendCore) emptyWorld
        (offsetEnvironment offset) successfulDigitsBlock =
      .done (.returned (some (digitScanValue (.success offset))))
        emptyWorld := by
  rfl

theorem failedDigitsBlock_evaluates (offset : Nat) :
    Block.evaluate (machine verifiedFrontendCore) emptyWorld
        (offsetEnvironment offset) failedDigitsBlock =
      .done (.returned (some (digitScanValue (.failure offset))))
        emptyWorld := by
  rfl

private theorem constructorBody_executes
    (state : State) (wellFormed : StateWellFormed state) (offset : Nat)
    (block : Block signature 1) (body : Stmt) (result : Value)
    (exact : toCoreStmt (identityLayout (arity := 1)) 1 block = body)
    (evaluated : Block.evaluate (machine verifiedFrontendCore) emptyWorld
      (offsetEnvironment offset) block =
        .done (.returned (some result)) emptyWorld)
    (noLocals : localCapacity block = 0) :
    Executes verifiedFrontendCore
      (singleArgumentCalleeState state (.signed .i32 offset)) body
      (.returned (some result))
      (singleArgumentCalleeState state (.signed .i32 offset)) := by
  let callee := singleArgumentCalleeState state (.signed .i32 offset)
  have environmentMatches : EnvironmentMatches
      (identityLayout (arity := 1)) (offsetEnvironment offset) callee := by
    intro index
    have found := singleArgumentCalleeState_local state wellFormed
      (.signed .i32 offset)
    simpa [callee, offsetEnvironment, identityLayout] using found
  have represented : ReadOnly.World.Represents emptyWorld callee := by
    intro _ _ found
    simp [emptyWorld] at found
  have sound := block_executes_without_locals
    (nextLocal := 1) (ReadOnly.bridge verifiedFrontendCore) represented
    environmentMatches noLocals evaluated
  rw [exact] at sound
  simpa [callee, toCoreCompletion] using sound.1

theorem successfulDigitsBody_executes
    (state : State) (wellFormed : StateWellFormed state) (offset : Nat) :
    Executes verifiedFrontendCore
      (singleArgumentCalleeState state (.signed .i32 offset))
      Digits.successfulDigitsBody
      (.returned (some (digitScanValue (.success offset))))
      (singleArgumentCalleeState state (.signed .i32 offset)) := by
  have normalized := constructorBody_executes state wellFormed offset
    successfulDigitsBlock
    (toCoreStmt (identityLayout (arity := 1)) 1 successfulDigitsBlock)
    (digitScanValue (.success offset)) rfl
    (successfulDigitsBlock_evaluates offset) (by native_decide)
  rw [← successfulDigitsBody_normalizes] at normalized
  exact removeTrailingSkips_executes_complete
    successfulDigitsBody_normalization_supported normalized

theorem failedDigitsBody_executes
    (state : State) (wellFormed : StateWellFormed state) (offset : Nat) :
    Executes verifiedFrontendCore
      (singleArgumentCalleeState state (.signed .i32 offset))
      Digits.failedDigitsBody
      (.returned (some (digitScanValue (.failure offset))))
      (singleArgumentCalleeState state (.signed .i32 offset)) := by
  have normalized := constructorBody_executes state wellFormed offset
    failedDigitsBlock
    (toCoreStmt (identityLayout (arity := 1)) 1 failedDigitsBlock)
    (digitScanValue (.failure offset)) rfl
    (failedDigitsBlock_evaluates offset) (by native_decide)
  rw [← failedDigitsBody_normalizes] at normalized
  exact removeTrailingSkips_executes_complete
    failedDigitsBody_normalization_supported normalized

theorem verifiedFrontendCore_finds_successfulDigits :
    verifiedFrontendCore.function? extractedSuccessfulDigitsFunction.id =
      some extractedSuccessfulDigitsFunction := by rfl

theorem verifiedFrontendCore_finds_failedDigits :
    verifiedFrontendCore.function? extractedFailedDigitsFunction.id =
      some extractedFailedDigitsFunction := by rfl

theorem successfulDigitsCall_executes
    (state : State) (wellFormed : StateWellFormed state)
    (argument : Expr) (offset : Nat)
    (argumentResult : Evaluates verifiedFrontendCore state argument
      (.signed .i32 offset) state) :
    Evaluates verifiedFrontendCore state (callSuccessfulDigits argument)
      (digitScanValue (.success offset))
      (singleArgumentCallState state (.signed .i32 offset)) := by
  have arguments := Lanius.CallContracts.ArgumentsEvaluateTo.singleton
    argumentResult
  have body := successfulDigitsBody_executes state wellFormed offset
  have evaluated := Lanius.CallContracts.evaluatesCallReturned
    (bindings := [(0, .signed .i32 offset)])
    (body := Digits.successfulDigitsBody) arguments
    verifiedFrontendCore_finds_successfulDigits (by rfl)
    (show extractedSuccessfulDigitsFunction.body =
      some Digits.successfulDigitsBody by rfl) body
  have sameId : extractedSuccessfulDigitsFunction.id =
      successfulDigitsFunction.id := by native_decide
  rw [sameId] at evaluated
  simpa [callSuccessfulDigits, singleArgumentCallState] using evaluated

theorem failedDigitsCall_executes
    (state : State) (wellFormed : StateWellFormed state)
    (argument : Expr) (offset : Nat)
    (argumentResult : Evaluates verifiedFrontendCore state argument
      (.signed .i32 offset) state) :
    Evaluates verifiedFrontendCore state (callFailedDigits argument)
      (digitScanValue (.failure offset))
      (singleArgumentCallState state (.signed .i32 offset)) := by
  have arguments := Lanius.CallContracts.ArgumentsEvaluateTo.singleton
    argumentResult
  have body := failedDigitsBody_executes state wellFormed offset
  have evaluated := Lanius.CallContracts.evaluatesCallReturned
    (bindings := [(0, .signed .i32 offset)])
    (body := Digits.failedDigitsBody) arguments
    verifiedFrontendCore_finds_failedDigits (by rfl)
    (show extractedFailedDigitsFunction.body =
      some Digits.failedDigitsBody by rfl) body
  have sameId : extractedFailedDigitsFunction.id =
      failedDigitsFunction.id := by native_decide
  rw [sameId] at evaluated
  simpa [callFailedDigits, singleArgumentCallState] using evaluated

instance verifiedFrontendCoreDigitRunCallSemantics :
    DigitRunCallSemantics verifiedFrontendCore where
  target := by native_decide
  isDigitForBaseCall_executes := by
    intro state wellFormed byteExpr baseExpr byte base byteResult baseResult
    exact isDigitForBaseCall_executes state wellFormed byteExpr baseExpr byte
      base byteResult baseResult
  successfulDigitsCall_executes := by
    intro state wellFormed argument offset argumentResult
    exact successfulDigitsCall_executes state wellFormed argument offset
      argumentResult
  failedDigitsCall_executes := by
    intro state wellFormed argument offset argumentResult
    exact failedDigitsCall_executes state wellFormed argument offset
      argumentResult

/-! ## Checked `token_scan` constructors -/

private def successfulTokenScanWire : CoreFunction :=
  artifact_pack_function%
    (include_str ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/token_scan.lani",
    "successful"

private def failedTokenScanWire : CoreFunction :=
  artifact_pack_function%
    (include_str ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/token_scan.lani",
    "failed"

def successfulTokenScanFunction : Function :=
  CoreDecode.function successfulTokenScanWire

def failedTokenScanFunction : Function :=
  CoreDecode.function failedTokenScanWire

theorem successfulTokenScan_body_present :
    successfulTokenScanFunction.body.isSome := by native_decide

theorem failedTokenScan_body_present :
    failedTokenScanFunction.body.isSome := by native_decide

def successfulTokenScanBody : Stmt :=
  successfulTokenScanFunction.body.get successfulTokenScan_body_present

def failedTokenScanBody : Stmt :=
  failedTokenScanFunction.body.get failedTokenScan_body_present

def tokenScanValue (success : Bool) (kind endOffset errorOffset : Int) : Value :=
  .structure 1 [
    .boolean success, .signed .i32 kind, .signed .i32 endOffset,
    .signed .i32 errorOffset]

def successfulTokenScanBlock : Block signature 2 :=
  .returnValue (some (apply (.structValue 1
    [.scalar .bool, i32Type, i32Type, i32Type])
    [literal (.boolean true), reference 0, reference 1,
      literal (.signed .i32 0)]))

def failedTokenScanBlock : Block signature 1 :=
  .returnValue (some (apply (.structValue 1
    [.scalar .bool, i32Type, i32Type, i32Type])
    [literal (.boolean false), literal (.signed .i32 0),
      literal (.signed .i32 0), reference 0]))

theorem successfulTokenScanBody_normalizes :
    removeTrailingSkips successfulTokenScanBody =
      toCoreStmt (identityLayout (arity := 2)) 2
        successfulTokenScanBlock := by rfl

theorem failedTokenScanBody_normalizes :
    removeTrailingSkips failedTokenScanBody =
      toCoreStmt (identityLayout (arity := 1)) 1 failedTokenScanBlock := by rfl

theorem successfulTokenScanBody_normalization_supported :
    SkipNormalizationSupported successfulTokenScanBody := by native_decide

theorem failedTokenScanBody_normalization_supported :
    SkipNormalizationSupported failedTokenScanBody := by native_decide

def twoOffsetEnvironment (left right : Int) : Env 2
  | ⟨0, _⟩ => .signed .i32 left
  | ⟨1, _⟩ => .signed .i32 right

theorem successfulTokenScanBlock_evaluates (kind endOffset : Int) :
    Block.evaluate (machine verifiedFrontendCore) emptyWorld
        (twoOffsetEnvironment kind endOffset) successfulTokenScanBlock =
      .done (.returned (some (tokenScanValue true kind endOffset 0)))
        emptyWorld := by rfl

theorem failedTokenScanBlock_evaluates (errorOffset : Nat) :
    Block.evaluate (machine verifiedFrontendCore) emptyWorld
        (offsetEnvironment errorOffset) failedTokenScanBlock =
      .done (.returned (some (tokenScanValue false 0 0 errorOffset)))
        emptyWorld := by rfl

theorem successfulTokenScanBody_executes
    (state : State) (wellFormed : StateWellFormed state)
    (kind endOffset : Int) :
    Executes verifiedFrontendCore (twoI32CalleeState state kind endOffset)
      successfulTokenScanBody
      (.returned (some (tokenScanValue true kind endOffset 0)))
      (twoI32CalleeState state kind endOffset) := by
  let callee := twoI32CalleeState state kind endOffset
  have environmentMatches : EnvironmentMatches identityLayout
      (twoOffsetEnvironment kind endOffset) callee := by
    intro index
    refine Fin.cases ?_
      (fun second => Fin.cases ?_ (fun impossible => Fin.elim0 impossible)
        second) index
    · simpa [callee, twoOffsetEnvironment, identityLayout] using
        twoI32CalleeState_left state wellFormed kind endOffset
    · simpa [callee, twoOffsetEnvironment, identityLayout] using
        twoI32CalleeState_right state wellFormed kind endOffset
  have represented : ReadOnly.World.Represents emptyWorld callee := by
    intro _ _ found
    simp [emptyWorld] at found
  have sound := block_executes_without_locals
    (nextLocal := 2) (ReadOnly.bridge verifiedFrontendCore) represented
    environmentMatches (by native_decide)
    (successfulTokenScanBlock_evaluates kind endOffset)
  rw [← successfulTokenScanBody_normalizes] at sound
  exact removeTrailingSkips_executes_complete
    successfulTokenScanBody_normalization_supported (by
      simpa [callee, toCoreCompletion] using sound.1)

theorem failedTokenScanBody_executes
    (state : State) (wellFormed : StateWellFormed state)
    (errorOffset : Nat) :
    Executes verifiedFrontendCore
      (singleArgumentCalleeState state (.signed .i32 errorOffset))
      failedTokenScanBody
      (.returned (some (tokenScanValue false 0 0 errorOffset)))
      (singleArgumentCalleeState state (.signed .i32 errorOffset)) := by
  have normalized := constructorBody_executes state wellFormed errorOffset
    failedTokenScanBlock
    (toCoreStmt (identityLayout (arity := 1)) 1 failedTokenScanBlock)
    (tokenScanValue false 0 0 errorOffset) rfl
    (failedTokenScanBlock_evaluates errorOffset) (by native_decide)
  rw [← failedTokenScanBody_normalizes] at normalized
  exact removeTrailingSkips_executes_complete
    failedTokenScanBody_normalization_supported normalized

theorem verifiedFrontendCore_finds_successfulTokenScan :
    verifiedFrontendCore.function? successfulTokenScanFunction.id =
      some successfulTokenScanFunction := by rfl

theorem verifiedFrontendCore_finds_failedTokenScan :
    verifiedFrontendCore.function? failedTokenScanFunction.id =
      some failedTokenScanFunction := by rfl

theorem successfulTokenScanCall_executes
    (state : State) (wellFormed : StateWellFormed state)
    (kindExpr endExpr : Expr) (kind endOffset : Int)
    (kindResult : Evaluates verifiedFrontendCore state kindExpr
      (.signed .i32 kind) state)
    (endResult : Evaluates verifiedFrontendCore state endExpr
      (.signed .i32 endOffset) state) :
    Evaluates verifiedFrontendCore state
      (.call successfulTokenScanFunction.id [kindExpr, endExpr])
      (tokenScanValue true kind endOffset 0)
      (twoI32CallState state kind endOffset) := by
  have arguments := ArgumentsEvaluateTo.cons kindResult
    (ArgumentsEvaluateTo.singleton endResult)
  have body := successfulTokenScanBody_executes state wellFormed kind endOffset
  exact evaluatesCallReturned
    (bindings := [(0, .signed .i32 kind), (1, .signed .i32 endOffset)])
    (body := successfulTokenScanBody) arguments
    verifiedFrontendCore_finds_successfulTokenScan (by rfl) (by rfl) body

theorem failedTokenScanCall_executes
    (state : State) (wellFormed : StateWellFormed state)
    (errorExpr : Expr) (errorOffset : Nat)
    (errorResult : Evaluates verifiedFrontendCore state errorExpr
      (.signed .i32 errorOffset) state) :
    Evaluates verifiedFrontendCore state
      (.call failedTokenScanFunction.id [errorExpr])
      (tokenScanValue false 0 0 errorOffset)
      (singleArgumentCallState state (.signed .i32 errorOffset)) := by
  have arguments := ArgumentsEvaluateTo.singleton errorResult
  have body := failedTokenScanBody_executes state wellFormed errorOffset
  exact evaluatesCallReturned
    (bindings := [(0, .signed .i32 errorOffset)])
    (body := failedTokenScanBody) arguments
    verifiedFrontendCore_finds_failedTokenScan (by rfl) (by rfl) body

end Lanius.Extraction.Decimal.Dependencies
