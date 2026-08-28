import Lanius.Extraction.VerifiedParserSymbolic
import Lanius.CallContracts

namespace Lanius.Extraction.ParserBasics

open Lanius.Core
open Lanius.Semantics
open Lanius.Separation
open Lanius.CallContracts
open Lanius.Extraction
open Lanius.Properties
open Lanius.SymbolicCore

def parserBoolType : Ty :=
  .scalar .bool

def parserRangeValidExpr : Expr :=
  .binary .logicalAnd
    (.binary .logicalAnd
      (.binary .logicalAnd
        (.binary .greaterEqual verifiedParserRangeValidOffset.expr (.constant 6))
        (.binary .greaterEqual verifiedParserRangeValidCount.expr
          (.value (.signed .i32 0))))
      (.binary .lessEqual verifiedParserRangeValidOffset.expr
        verifiedParserRangeValidLength.expr))
    (.binary .lessEqual verifiedParserRangeValidCount.expr
      (.binary .subtract verifiedParserRangeValidLength.expr
        verifiedParserRangeValidOffset.expr))

def parserRangeValidBody : Stmt :=
  .sequence (.returnValue (some parserRangeValidExpr)) .skip

private theorem parserRangeValidExpr_core_slots :
    parserRangeValidExpr =
      .binary .logicalAnd
        (.binary .logicalAnd
          (.binary .logicalAnd
            (.binary .greaterEqual (.local 0) (.constant 6))
            (.binary .greaterEqual (.local 1) (.value (.signed .i32 0))))
          (.binary .lessEqual (.local 0) (.local 2)))
        (.binary .lessEqual (.local 1)
          (.binary .subtract (.local 2) (.local 0))) := by
  simp [parserRangeValidExpr, LocalRef.expr]

def extractedParserRangeValidBody : Stmt :=
  extractedParserRangeValidFunction.body.getD .skip

theorem extractedParserRangeValid_function_shape :
    extractedParserRangeValidFunction.parameters =
        [(0, parserI32Type), (1, parserI32Type), (2, parserI32Type)] ∧
      extractedParserRangeValidFunction.returnType = parserBoolType ∧
      extractedParserRangeValidFunction.body = some parserRangeValidBody ∧
      extractedParserRangeValidFunction.external = none := by
  rw [parserRangeValidBody, parserRangeValidExpr_core_slots]
  exact ⟨rfl, rfl, rfl, rfl⟩

theorem extractedParserRangeValidBody_eq :
    extractedParserRangeValidBody = parserRangeValidBody := by
  rw [parserRangeValidBody, parserRangeValidExpr_core_slots]
  rfl

theorem verifiedParser_range_valid_constant :
    verifiedParserCore.constant? 6 = some {
      id := 6
      type := parserI32Type
      value := .signed .i32 17
    } := by
  have evidence :
      (verifiedParserCore.constant? 6).map (fun declaration =>
        (declaration.id, declaration.type,
          signedI32ConstantValue? declaration.value)) =
        some (6, parserI32Type, some 17) := by
    native_decide
  exact constant_eq_of_signed_i32_evidence verifiedParserCore 6 17 evidence

/-- The exact machine-integer predicate computed by extracted `range_valid`.
    Keeping the wrapped subtraction visible makes this theorem valid for every
    possible i32 input; `grammar_is_valid` will later establish the stronger
    bounds under which it agrees with ordinary mathematical subtraction. -/
def parserRangeValidValue
    (target : Target) (offset count length : Int) : Bool :=
  (((decide (offset ≥ 17)) && decide (count ≥ 0)) &&
      decide (offset ≤ length)) &&
    decide (count ≤ wrapSigned target .i32 (length - offset))

/-- Under the ordinary i32 bound supplied by a well-typed caller, the exact
    machine predicate is equivalent to the intended half-open range check.
    This is the bridge used by packed-grammar safety proofs. -/
theorem parserRangeValidValue_eq_true_iff
    (target : Target) (offset count length : Int)
    (lengthBound : length ≤ 2147483647) :
    parserRangeValidValue target offset count length = true ↔
      17 ≤ offset ∧ 0 ≤ count ∧ offset ≤ length ∧
        count ≤ length - offset := by
  constructor
  · intro accepted
    have nested :
        ((17 ≤ offset ∧ 0 ≤ count) ∧ offset ≤ length) ∧
          count ≤ wrapSigned target .i32 (length - offset) := by
      simpa [parserRangeValidValue] using accepted
    rcases nested with ⟨⟨⟨offsetLower, countLower⟩, offsetUpper⟩,
      countUpper⟩
    have remainingNonnegative : 0 ≤ length - offset := by omega
    have remainingBound : length - offset ≤ 2147483647 := by omega
    have wrapped := wrapSigned_i32_of_nonnegative target (length - offset)
      remainingNonnegative remainingBound
    exact ⟨offsetLower, countLower, offsetUpper, by simpa [wrapped] using countUpper⟩
  · rintro ⟨offsetLower, countLower, offsetUpper, countUpper⟩
    have remainingNonnegative : 0 ≤ length - offset := by omega
    have remainingBound : length - offset ≤ 2147483647 := by omega
    have wrapped := wrapSigned_i32_of_nonnegative target (length - offset)
      remainingNonnegative remainingBound
    simp [parserRangeValidValue, offsetLower, countLower, offsetUpper,
      countUpper, wrapped]

private theorem evaluatesRangeOffsetLowerBound
    (state : State) (offset : Int)
    (offsetLocal : state.local? verifiedParserRangeValidOffset.coreId =
      some (.signed .i32 offset)) :
    Evaluates verifiedParserCore state
      (.binary .greaterEqual verifiedParserRangeValidOffset.expr (.constant 6))
      (.boolean (decide (offset ≥ 17))) state := by
  have left : Evaluates verifiedParserCore state
      verifiedParserRangeValidOffset.expr
      (.signed .i32 offset) state :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore state
      verifiedParserRangeValidOffset.coreId
      (.signed .i32 offset) offsetLocal⟩
  have right : Evaluates verifiedParserCore state (.constant 6)
      (.signed .i32 17) state :=
    evaluatesConstant verifiedParser_range_valid_constant
  apply evaluatesEagerBinary (by decide) (by decide) left right
  simp [evalBinaryValue, evalSignedBinary]

private theorem evaluatesRangeCountLowerBound
    (state : State) (count : Int)
    (countLocal : state.local? verifiedParserRangeValidCount.coreId =
      some (.signed .i32 count)) :
    Evaluates verifiedParserCore state
      (.binary .greaterEqual verifiedParserRangeValidCount.expr
        (.value (.signed .i32 0)))
      (.boolean (decide (count ≥ 0))) state := by
  have left : Evaluates verifiedParserCore state
      verifiedParserRangeValidCount.expr
      (.signed .i32 count) state :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore state
      verifiedParserRangeValidCount.coreId
      (.signed .i32 count) countLocal⟩
  have right : Evaluates verifiedParserCore state
      (.value (.signed .i32 0)) (.signed .i32 0) state := ⟨1, rfl⟩
  apply evaluatesEagerBinary (by decide) (by decide) left right
  simp [evalBinaryValue, evalSignedBinary]

private theorem evaluatesRangeOffsetUpperBound
    (state : State) (offset length : Int)
    (offsetLocal : state.local? verifiedParserRangeValidOffset.coreId =
      some (.signed .i32 offset))
    (lengthLocal : state.local? verifiedParserRangeValidLength.coreId =
      some (.signed .i32 length)) :
    Evaluates verifiedParserCore state
      (.binary .lessEqual verifiedParserRangeValidOffset.expr
        verifiedParserRangeValidLength.expr)
      (.boolean (decide (offset ≤ length))) state := by
  have left : Evaluates verifiedParserCore state
      verifiedParserRangeValidOffset.expr
      (.signed .i32 offset) state :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore state
      verifiedParserRangeValidOffset.coreId
      (.signed .i32 offset) offsetLocal⟩
  have right : Evaluates verifiedParserCore state
      verifiedParserRangeValidLength.expr
      (.signed .i32 length) state :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore state
      verifiedParserRangeValidLength.coreId
      (.signed .i32 length) lengthLocal⟩
  apply evaluatesEagerBinary (by decide) (by decide) left right
  simp [evalBinaryValue, evalSignedBinary]

private theorem evaluatesRangeRemaining
    (state : State) (offset length : Int)
    (offsetLocal : state.local? verifiedParserRangeValidOffset.coreId =
      some (.signed .i32 offset))
    (lengthLocal : state.local? verifiedParserRangeValidLength.coreId =
      some (.signed .i32 length)) :
    Evaluates verifiedParserCore state
      (.binary .subtract verifiedParserRangeValidLength.expr
        verifiedParserRangeValidOffset.expr)
      (.signed .i32
        (wrapSigned verifiedParserCore.target .i32 (length - offset))) state := by
  have left : Evaluates verifiedParserCore state
      verifiedParserRangeValidLength.expr
      (.signed .i32 length) state :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore state
      verifiedParserRangeValidLength.coreId
      (.signed .i32 length) lengthLocal⟩
  have right : Evaluates verifiedParserCore state
      verifiedParserRangeValidOffset.expr
      (.signed .i32 offset) state :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore state
      verifiedParserRangeValidOffset.coreId
      (.signed .i32 offset) offsetLocal⟩
  apply evaluatesEagerBinary (by decide) (by decide) left right
  simp [evalBinaryValue, evalSignedBinary]

private theorem evaluatesRangeCountUpperBound
    (state : State) (offset count length : Int)
    (offsetLocal : state.local? verifiedParserRangeValidOffset.coreId =
      some (.signed .i32 offset))
    (countLocal : state.local? verifiedParserRangeValidCount.coreId =
      some (.signed .i32 count))
    (lengthLocal : state.local? verifiedParserRangeValidLength.coreId =
      some (.signed .i32 length)) :
    Evaluates verifiedParserCore state
      (.binary .lessEqual verifiedParserRangeValidCount.expr
        (.binary .subtract verifiedParserRangeValidLength.expr
          verifiedParserRangeValidOffset.expr))
      (.boolean (decide (count ≤
        wrapSigned verifiedParserCore.target .i32 (length - offset)))) state := by
  have left : Evaluates verifiedParserCore state
      verifiedParserRangeValidCount.expr
      (.signed .i32 count) state :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore state
      verifiedParserRangeValidCount.coreId
      (.signed .i32 count) countLocal⟩
  have right := evaluatesRangeRemaining state offset length offsetLocal
    lengthLocal
  apply evaluatesEagerBinary (by decide) (by decide) left right
  simp [evalBinaryValue, evalSignedBinary]

theorem parserRangeValidExpr_evaluates
    (state : State) (offset count length : Int)
    (offsetLocal : state.local? verifiedParserRangeValidOffset.coreId =
      some (.signed .i32 offset))
    (countLocal : state.local? verifiedParserRangeValidCount.coreId =
      some (.signed .i32 count))
    (lengthLocal : state.local? verifiedParserRangeValidLength.coreId =
      some (.signed .i32 length)) :
    Evaluates verifiedParserCore state parserRangeValidExpr
      (.boolean (parserRangeValidValue verifiedParserCore.target
        offset count length)) state := by
  have offsetLower := evaluatesRangeOffsetLowerBound state offset offsetLocal
  have countLower := evaluatesRangeCountLowerBound state count countLocal
  have offsetUpper := evaluatesRangeOffsetUpperBound state offset length
    offsetLocal lengthLocal
  have countUpper := evaluatesRangeCountUpperBound state offset count length
    offsetLocal countLocal lengthLocal
  have first := evaluatesPureLogicalAnd offsetLower countLower
  have second := evaluatesPureLogicalAnd first offsetUpper
  have third := evaluatesPureLogicalAnd second countUpper
  simpa [parserRangeValidExpr, parserRangeValidValue] using third

theorem extractedParserRangeValidBody_executes
    (state : State) (offset count length : Int)
    (offsetLocal : state.local? verifiedParserRangeValidOffset.coreId =
      some (.signed .i32 offset))
    (countLocal : state.local? verifiedParserRangeValidCount.coreId =
      some (.signed .i32 count))
    (lengthLocal : state.local? verifiedParserRangeValidLength.coreId =
      some (.signed .i32 length)) :
    Executes verifiedParserCore state extractedParserRangeValidBody
      (.returned (some (.boolean
        (parserRangeValidValue verifiedParserCore.target offset count length))))
      state := by
  rw [extractedParserRangeValidBody_eq]
  apply executesSequenceReturned
  apply executesReturnValue
  exact parserRangeValidExpr_evaluates state offset count length offsetLocal
    countLocal lengthLocal

def parserRangeValidBindings (offset count length : Int) :
    List (VarId × Value) := [
  (verifiedParserRangeValidOffset.coreId, .signed .i32 offset),
  (verifiedParserRangeValidCount.coreId, .signed .i32 count),
  (verifiedParserRangeValidLength.coreId, .signed .i32 length)]

def parserRangeValidCallee
    (caller : State) (offset count length : Int) : State :=
  enterCall caller (parserRangeValidBindings offset count length)

private theorem parserRangeValidCallee_offset
    (wellFormed : StateWellFormed caller) :
    (parserRangeValidCallee caller offset count length).local?
        verifiedParserRangeValidOffset.coreId =
      some (.signed .i32 offset) := by
  simpa [parserRangeValidCallee, parserRangeValidBindings] using
    (enterCall_local_of_binding caller [] [
      (verifiedParserRangeValidCount.coreId, .signed .i32 count),
      (verifiedParserRangeValidLength.coreId, .signed .i32 length)]
      verifiedParserRangeValidOffset.coreId (.signed .i32 offset)
      wellFormed (by simp))

private theorem parserRangeValidCallee_count
    (wellFormed : StateWellFormed caller) :
    (parserRangeValidCallee caller offset count length).local?
        verifiedParserRangeValidCount.coreId =
      some (.signed .i32 count) := by
  simpa [parserRangeValidCallee, parserRangeValidBindings] using
    (enterCall_local_of_binding caller [
      (verifiedParserRangeValidOffset.coreId, .signed .i32 offset)] [
      (verifiedParserRangeValidLength.coreId, .signed .i32 length)]
      verifiedParserRangeValidCount.coreId (.signed .i32 count)
      wellFormed (by simp))

private theorem parserRangeValidCallee_length
    (wellFormed : StateWellFormed caller) :
    (parserRangeValidCallee caller offset count length).local?
        verifiedParserRangeValidLength.coreId =
      some (.signed .i32 length) := by
  simpa [parserRangeValidCallee, parserRangeValidBindings] using
    (enterCall_local_of_binding caller [
      (verifiedParserRangeValidOffset.coreId, .signed .i32 offset),
      (verifiedParserRangeValidCount.coreId, .signed .i32 count)] []
      verifiedParserRangeValidLength.coreId (.signed .i32 length)
      wellFormed (by simp))

theorem verifiedParserCore_finds_rangeValid :
    verifiedParserCore.function? extractedParserRangeValidFunction.id =
      some extractedParserRangeValidFunction := by
  unfold verifiedParserCore extractedParserRangeValidFunction
    extractedParserRangeValidWire
  rfl

/-- Full source-call contract for the extracted `range_valid`. Argument
    evaluation may be effectful; the function body itself is pure and caller
    locals are restored at return. -/
theorem extractedParserRangeValidCall_evaluates
    (before afterArguments : State) (arguments : List Expr)
    (offset count length : Int)
    (afterArgumentsWellFormed : StateWellFormed afterArguments)
    (argumentsResult : ArgumentsEvaluateTo verifiedParserCore before arguments [
      .signed .i32 offset, .signed .i32 count,
      .signed .i32 length] afterArguments) :
    let callee := parserRangeValidCallee afterArguments offset count length
    let after := restoreLocals afterArguments callee
    Evaluates verifiedParserCore before
        (.call extractedParserRangeValidFunction.id arguments)
        (.boolean (parserRangeValidValue verifiedParserCore.target
          offset count length)) after ∧
      ModifiesOnly CellSet.empty afterArguments after ∧
      StateWellFormed after := by
  dsimp only
  let callee := parserRangeValidCallee afterArguments offset count length
  let after := restoreLocals afterArguments callee
  have body : Executes verifiedParserCore callee parserRangeValidBody
      (.returned (some (.boolean
        (parserRangeValidValue verifiedParserCore.target offset count length))))
      callee := by
    rw [← extractedParserRangeValidBody_eq]
    exact extractedParserRangeValidBody_executes callee offset count length
      (parserRangeValidCallee_offset afterArgumentsWellFormed)
      (parserRangeValidCallee_count afterArgumentsWellFormed)
      (parserRangeValidCallee_length afterArgumentsWellFormed)
  have evaluation : Evaluates verifiedParserCore before
      (.call extractedParserRangeValidFunction.id arguments)
      (.boolean (parserRangeValidValue verifiedParserCore.target
        offset count length)) after := by
    apply evaluatesCallReturned argumentsResult
      verifiedParserCore_finds_rangeValid
    · rw [extractedParserRangeValid_function_shape.1]
      rfl
    · exact extractedParserRangeValid_function_shape.2.2.1
    · simpa [callee, parserRangeValidCallee, parserRangeValidBindings,
        after] using body
  have effect : ModifiesOnly CellSet.empty afterArguments after := by
    simpa [callee, after, parserRangeValidCallee] using
      (enterCall_effect afterArguments
        (parserRangeValidBindings offset count length)).restoreLocals
  have calleeWellFormed : StateWellFormed callee := by
    exact enterCall_preserves_wellFormed afterArgumentsWellFormed
  have afterWellFormed : StateWellFormed after := by
    exact (enterCall_effect afterArguments
      (parserRangeValidBindings offset count length))
      |>.restoreLocals_wellFormed afterArgumentsWellFormed calleeWellFormed
  exact ⟨evaluation, effect, afterWellFormed⟩

end Lanius.Extraction.ParserBasics
