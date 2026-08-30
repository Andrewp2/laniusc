import Lanius.Extraction.VerifiedParserSymbolic
import Lanius.CallContracts
import Lanius.FunctionalViewCoreReadOnly

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

namespace Proof

open Lanius.FunctionalView
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.ReadOnly

private abbrev RangeTerm := Term signature 3
private abbrev RangeBlock := Block signature 3

private def slot (index : Fin 3) : RangeTerm := reference index
private def i32 (value : Int) : RangeTerm := literal (.signed .i32 value)
private def constant (id : ConstantId) : RangeTerm :=
  apply (.constant id parserI32Type) []
private def binary (operation : BinaryOp) (left right : RangeTerm)
    (result : Ty := parserBoolType) : RangeTerm :=
  apply (.binary operation parserI32Type parserI32Type result) [left, right]
private def conjunction (left right : RangeTerm) : RangeTerm :=
  Lanius.FunctionalView.Core.logicalAnd left right

def rangeValid : RangeTerm :=
  conjunction
    (conjunction
      (conjunction
        (binary .greaterEqual (slot 0) (constant 6))
        (binary .greaterEqual (slot 1) (i32 0)))
      (binary .lessEqual (slot 0) (slot 2)))
    (binary .lessEqual (slot 1)
      (binary .subtract (slot 2) (slot 0) parserI32Type))

def body : RangeBlock :=
  .sequence (.returnValue (some rangeValid)) .skip

def environment (offset count length : Int) : Env 3
  | ⟨0, _⟩ => .signed .i32 offset
  | ⟨1, _⟩ => .signed .i32 count
  | ⟨2, _⟩ => .signed .i32 length

def world : World := { i32Slice? := fun _ => none }

theorem rangeValid_toCore_exactly :
    toCoreExpr (identityLayout (arity := 3)) rangeValid =
      parserRangeValidExpr := by
  rw [parserRangeValidExpr_core_slots]
  rfl

theorem body_toCore_exactly :
    toCoreStmt (identityLayout (arity := 3)) 3 body =
      parserRangeValidBody := by
  simp [body, parserRangeValidBody, toCoreStmt, rangeValid_toCore_exactly]

theorem rangeValid_evaluates (offset count length : Int) :
    Term.evaluate (machine verifiedParserCore) world
        (environment offset count length)
        rangeValid =
      .ok (.boolean (parserRangeValidValue verifiedParserCore.target
        offset count length), world) := by
  have constantFound := verifiedParser_range_valid_constant
  simp only [rangeValid, conjunction, binary, constant, slot, i32,
    Lanius.FunctionalView.Core.apply, Lanius.FunctionalView.Core.reference,
    Lanius.FunctionalView.Core.literal]
  functional_eval

theorem body_evaluates (offset count length : Int) :
    Block.evaluate (machine verifiedParserCore) world
        (environment offset count length) body =
      .done (.returned (some (.boolean
        (parserRangeValidValue verifiedParserCore.target
          offset count length)))) world := by
  apply Block.evaluate_sequence_returned
  apply Block.evaluate_returnValue
  exact rangeValid_evaluates offset count length

end Proof

def parserRangeValidBindings (offset count length : Int) :
    List (VarId × Value) := [
  (verifiedParserRangeValidOffset.coreId, .signed .i32 offset),
  (verifiedParserRangeValidCount.coreId, .signed .i32 count),
  (verifiedParserRangeValidLength.coreId, .signed .i32 length)]

theorem Proof.parameterBindings_eq (offset count length : Int) :
    Lanius.FunctionalView.Core.parameterBindings
        (Proof.environment offset count length) =
      parserRangeValidBindings offset count length := by
  have offsetId : verifiedParserRangeValidOffset.coreId = 0 := by
    native_decide
  have countId : verifiedParserRangeValidCount.coreId = 1 := by
    native_decide
  have lengthId : verifiedParserRangeValidLength.coreId = 2 := by
    native_decide
  apply List.ext_getElem
  · simp [parserRangeValidBindings]
  · intro index leftBound rightBound
    have alternatives : index = 0 ∨ index = 1 ∨ index = 2 := by
      simp [parserRangeValidBindings] at rightBound
      omega
    rcases alternatives with rfl | rfl | rfl <;>
      simp [Lanius.FunctionalView.Core.parameterBindings_getElem,
        parserRangeValidBindings, Proof.environment,
        offsetId, countId, lengthId]

def parserRangeValidCallee
    (caller : State) (offset count length : Int) : State :=
  enterCall caller (parserRangeValidBindings offset count length)

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
    have environmentMatches :
        Lanius.FunctionalView.Core.EnvironmentMatches
          (Lanius.FunctionalView.Core.identityLayout (arity := 3))
          (Proof.environment offset count length) callee := by
      simpa [callee, parserRangeValidCallee,
        Proof.parameterBindings_eq] using
        (Lanius.FunctionalView.Core.enterCall_parameterBindings_matches
          (environment := Proof.environment offset count length)
          afterArgumentsWellFormed)
    have represented : Lanius.FunctionalView.Core.ReadOnly.World.Represents
        Proof.world callee := by
      intro _ _ found
      simp [Proof.world] at found
    have sound := Lanius.FunctionalView.Core.block_executes_without_locals
      (nextLocal := 3)
      (Lanius.FunctionalView.Core.ReadOnly.bridge verifiedParserCore)
      represented environmentMatches (by rfl)
      (Proof.body_evaluates offset count length)
    rw [Proof.body_toCore_exactly] at sound
    simpa [Lanius.FunctionalView.Core.toCoreCompletion] using sound.1
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
