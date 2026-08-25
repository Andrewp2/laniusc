import Lanius.Typing
import Lanius.Semantics
import Lanius.Execution
import Lean.Elab.Tactic.Omega

namespace Lanius.Properties

open Lanius
open Lanius.Core
open Lanius.Memory
open Lanius.Semantics
open Lanius.Typing

theorem context_bind_same (context : Context) (id : VarId) (type : Ty) :
    (context.bind id type) id = some type := by
  simp [Context.bind]

theorem context_bind_different
    (context : Context) (bound other : VarId) (type : Ty)
    (different : other ≠ bound) :
    (context.bind bound type) other = context other := by
  simp [Context.bind, different]

/-- The executable dynamic semantics chooses at most one result for a fixed
    program, state, term, and fuel budget. Fuel-independence is a later
    metatheory obligation. -/
theorem evalExpr_deterministic_at_fuel
    (fuel : Nat) (program : Program) (state : State) (expression : Expr)
    (left right : Outcome Value)
    (leftResult : evalExpr fuel program state expression = left)
    (rightResult : evalExpr fuel program state expression = right) :
    left = right := by
  exact leftResult.symm.trans rightResult

theorem execStmt_deterministic_at_fuel
    (fuel : Nat) (program : Program) (state : State) (statement : Stmt)
    (left right : Outcome Completion)
    (leftResult : execStmt fuel program state statement = left)
    (rightResult : execStmt fuel program state statement = right) :
    left = right := by
  exact leftResult.symm.trans rightResult

theorem deallocating_null_is_a_noop
    (heap : Heap) (size alignment : Nat) :
    heap.deallocate null size alignment = .ok heap := by
  simp [Heap.deallocate, null]

theorem valid_alignment_is_nonzero
    (alignment : Nat) (valid : validAlignment alignment = true) :
    alignment ≠ 0 := by
  intro zero
  subst zero
  simp [validAlignment] at valid

theorem alignUp_ge
    (address alignment : Nat) (nonzero : alignment ≠ 0) :
    address ≤ alignUp address alignment := by
  have positive := Nat.pos_of_ne_zero nonzero
  have remainderBound :
      (address + alignment - 1) % alignment < alignment :=
    Nat.mod_lt _ positive
  have division := Nat.div_add_mod (address + alignment - 1) alignment
  have commute : alignment * ((address + alignment - 1) / alignment) =
      ((address + alignment - 1) / alignment) * alignment := Nat.mul_comm _ _
  simp only [alignUp]
  omega

theorem alignUp_mod
    (address alignment : Nat) :
    alignUp address alignment % alignment = 0 := by
  simp [alignUp]

theorem wrapUnsigned_le_max
    (target : Target) (type : UnsignedIntTy) (value : Nat) :
    wrapUnsigned target type value ≤ unsignedMax target type := by
  have bounded := Nat.mod_lt value (Nat.two_pow_pos (type.bits target))
  simp only [wrapUnsigned, unsignedModulus, unsignedMax]
  omega

theorem wrapUnsignedInt_le_max
    (target : Target) (type : UnsignedIntTy) (value : Int) :
    wrapUnsignedInt target type value ≤ unsignedMax target type := by
  have natModulusPositive : 0 < unsignedModulus target type := by
    exact Nat.two_pow_pos (type.bits target)
  have modulusPositive : 0 < Int.ofNat (unsignedModulus target type) := by
    exact Int.natCast_pos.mpr natModulusPositive
  have nonnegative := Int.emod_nonneg value (Int.ne_of_gt modulusPositive)
  have below := Int.emod_lt_of_pos value modulusPositive
  have boundedNat :
      (value % Int.ofNat (unsignedModulus target type)).toNat <
        unsignedModulus target type :=
    (Int.toNat_lt nonnegative).2 below
  simp only [wrapUnsignedInt, unsignedMax, unsignedModulus] at boundedNat ⊢
  omega

theorem wrapSigned_in_range
    (target : Target) (type : SignedIntTy) (value : Int) :
    signedMin target type ≤ wrapSigned target type value ∧
      wrapSigned target type value ≤ signedMax target type := by
  by_cases branch :
      value % signedModulus target type ≥ signedSignBit target type
  · simp only [wrapSigned]
    rw [if_pos branch]
    have modulusPositive : 0 < signedModulus target type := by
      exact Int.pow_pos (by decide)
    have nonnegative := Int.emod_nonneg value (Int.ne_of_gt modulusPositive)
    have below := Int.emod_lt_of_pos value modulusPositive
    rcases target with ⟨pointerWidth⟩
    cases pointerWidth <;> cases type <;>
      simp only [signedMin, signedMax, signedModulus, signedSignBit,
        SignedIntTy.bits, PointerWidth.bits] at branch nonnegative below ⊢ <;>
      constructor <;> omega

  · simp only [wrapSigned]
    rw [if_neg branch]
    have modulusPositive : 0 < signedModulus target type := by
      exact Int.pow_pos (by decide)
    have nonnegative := Int.emod_nonneg value (Int.ne_of_gt modulusPositive)
    have below := Int.emod_lt_of_pos value modulusPositive
    rcases target with ⟨pointerWidth⟩
    cases pointerWidth <;> cases type <;>
      simp only [signedMin, signedMax, signedModulus, signedSignBit,
        SignedIntTy.bits, PointerWidth.bits] at branch nonnegative below ⊢ <;>
      constructor <;> omega

theorem World.wrapI32_in_range (value : Int) :
    -(2 ^ 31) ≤ World.wrapI32 value ∧ World.wrapI32 value ≤ 2 ^ 31 - 1 := by
  have modulusPositive : (0 : Int) < 2 ^ 32 := Int.pow_pos (by decide)
  have nonnegative := Int.emod_nonneg value (Int.ne_of_gt modulusPositive)
  have below := Int.emod_lt_of_pos value modulusPositive
  by_cases high : value % (2 ^ 32) ≥ 2 ^ 31
  · simp only [World.wrapI32]
    rw [if_pos high]
    constructor <;> omega
  · simp only [World.wrapI32]
    rw [if_neg high]
    constructor <;> omega

theorem World.i32Result_has_type (program : Program) (value : Int) :
    ValueHasType program (World.i32Result value)
      (.scalar (.signed .i32)) := by
  have range := World.wrapI32_in_range value
  exact .signed .i32 (World.wrapI32 value)
    (by simpa [signedMin, SignedIntTy.bits] using range.1)
    (by simpa [signedMax, SignedIntTy.bits] using range.2)

theorem evalScalarCast_preserves_type
    (conversion : ScalarCast source destination)
    (inputTyped : ValueHasType program input (.scalar source))
    (evaluated : evalScalarCast program.target destination input = .ok result) :
    ValueHasType program result (.scalar destination) := by
  cases conversion with
  | signedToSigned sourceType targetType =>
      cases inputTyped with
      | signed _ value lower upper =>
          simp [evalScalarCast] at evaluated
          subst result
          exact .signed targetType _
            (wrapSigned_in_range program.target targetType value).1
            (wrapSigned_in_range program.target targetType value).2
  | signedToUnsigned sourceType targetType =>
      cases inputTyped with
      | signed _ value lower upper =>
          simp [evalScalarCast] at evaluated
          subst result
          exact .unsigned targetType _
            (wrapUnsignedInt_le_max program.target targetType value)
  | unsignedToSigned sourceType targetType =>
      cases inputTyped with
      | unsigned _ value upper =>
          simp [evalScalarCast] at evaluated
          subst result
          exact .signed targetType _
            (wrapSigned_in_range program.target targetType (Int.ofNat value)).1
            (wrapSigned_in_range program.target targetType (Int.ofNat value)).2
  | unsignedToUnsigned sourceType targetType =>
      cases inputTyped with
      | unsigned _ value upper =>
          simp [evalScalarCast] at evaluated
          subst result
          exact .unsigned targetType _
            (wrapUnsigned_le_max program.target targetType value)
  | signedToF32 sourceType =>
      cases inputTyped with
      | signed _ value lower upper =>
          simp [evalScalarCast] at evaluated
          subst result
          exact .f32Bits _

  | signedToF64 sourceType =>
      cases inputTyped with
      | signed _ value lower upper =>
          simp [evalScalarCast] at evaluated
          subst result
          exact .f64Bits _
  | unsignedToF32 sourceType =>
      cases inputTyped with
      | unsigned _ value upper =>
          simp [evalScalarCast] at evaluated
          subst result
          exact .f32Bits _
  | unsignedToF64 sourceType =>
      cases inputTyped with
      | unsigned _ value upper =>
          simp [evalScalarCast] at evaluated
          subst result
          exact .f64Bits _
  | charToSigned targetType =>
      cases inputTyped with
      | character value =>
          simp [evalScalarCast] at evaluated
          subst result
          exact .signed targetType _
            (wrapSigned_in_range program.target targetType
              (Int.ofNat value.toNat)).1
            (wrapSigned_in_range program.target targetType
              (Int.ofNat value.toNat)).2
  | charToUnsigned targetType =>
      cases inputTyped with
      | character value =>
          simp [evalScalarCast] at evaluated
          subst result
          exact .unsigned targetType _
            (wrapUnsigned_le_max program.target targetType value.toNat)
  | charToF32 =>
      cases inputTyped with
      | character value =>
          simp [evalScalarCast] at evaluated
          subst result
          exact .f32Bits _
  | charToF64 =>
      cases inputTyped with
      | character value =>
          simp [evalScalarCast] at evaluated
          subst result
          exact .f64Bits _
  | f32ToF64 =>
      cases inputTyped with
      | f32Bits bits =>
          simp [evalScalarCast] at evaluated
          subst result
          exact .f64Bits _
  | f64ToF32 =>
      cases inputTyped with
      | f64Bits bits =>
          simp [evalScalarCast] at evaluated
          subst result
          exact .f32Bits _

theorem evalUnaryValue_preserves_type
    (operation : UnaryOpHasType op inputType outputType)
    (inputTyped : ValueHasType program input inputType)
    (evaluated : evalUnaryValue program.target op input = .ok result) :
    ValueHasType program result outputType := by
  cases operation with
  | positive arithmetic =>
      cases arithmetic with
      | signed type =>
          cases inputTyped with
          | signed _ value lower upper =>
              simp [evalUnaryValue] at evaluated
              subst result
              exact .signed type value lower upper
      | unsigned type =>
          cases inputTyped with
          | unsigned _ value upper =>
              simp [evalUnaryValue] at evaluated
              subst result
              exact .unsigned type value upper
      | f32 =>
          cases inputTyped with
          | f32Bits bits =>
              simp [evalUnaryValue] at evaluated
              subst result
              exact .f32Bits bits
      | f64 =>
          cases inputTyped with
          | f64Bits bits =>
              simp [evalUnaryValue] at evaluated
              subst result
              exact .f64Bits bits
      | character =>
          cases inputTyped with
          | character value =>
              simp [evalUnaryValue] at evaluated
              subst result
              exact .character value
  | logicalNot =>
      cases inputTyped with
      | boolean value =>
          simp [evalUnaryValue] at evaluated
          subst result
          exact .boolean _
  | negate negatable =>
      cases negatable with
      | signed type =>
          cases inputTyped with
          | signed _ value lower upper =>
              simp [evalUnaryValue] at evaluated
              subst result
              exact .signed type _
                (wrapSigned_in_range program.target type (-value)).1
                (wrapSigned_in_range program.target type (-value)).2
      | unsigned type =>
          cases inputTyped with
          | unsigned _ value upper =>
              simp [evalUnaryValue] at evaluated
              subst result
              exact .unsigned type _
                (wrapUnsignedInt_le_max program.target type (-(Int.ofNat value)))
      | f32 =>
          cases inputTyped with
          | f32Bits bits =>
              simp [evalUnaryValue] at evaluated
              subst result
              exact .f32Bits _
      | f64 =>
          cases inputTyped with
          | f64Bits bits =>
              simp [evalUnaryValue] at evaluated
              subst result
              exact .f64Bits _
      | character =>
          cases inputTyped with
          | character value =>
              simp [evalUnaryValue] at evaluated
              subst result
              exact .character _

theorem UnaryOpHasType.output_is_scalar
    (operation : UnaryOpHasType op inputType outputType) :
    ∃ scalar, outputType = .scalar scalar := by
  cases operation with
  | positive arithmetic =>
      cases arithmetic <;> exact ⟨_, rfl⟩
  | logicalNot => exact ⟨.bool, rfl⟩
  | negate negatable =>
      cases negatable <;> exact ⟨_, rfl⟩

theorem evalBinaryValue_equality_preserves_type
    (equality : EqualityTy operandType)
    (operator : op = .equal ∨ op = .notEqual)
    (leftTyped : ValueHasType program left operandType)
    (rightTyped : ValueHasType program right operandType)
    (evaluated : evalBinaryValue program.target op left right = .ok result) :
    ValueHasType program result (.scalar .bool) := by
  rcases operator with rfl | rfl <;>
    cases equality <;> cases leftTyped <;> cases rightTyped <;>
    simp [evalBinaryValue, scalarEqual] at evaluated <;>
    subst result <;> exact .boolean _

theorem evalBinaryValue_ordering_preserves_type
    (ordered : OrderedTy operandType)
    (operator : op = .less ∨ op = .lessEqual ∨ op = .greater ∨
      op = .greaterEqual)
    (leftTyped : ValueHasType program left operandType)
    (rightTyped : ValueHasType program right operandType)
    (evaluated : evalBinaryValue program.target op left right = .ok result) :
    ValueHasType program result (.scalar .bool) := by
  rcases operator with rfl | rfl | rfl | rfl <;>
    cases ordered <;> cases leftTyped <;> cases rightTyped <;>
    simp [evalBinaryValue, evalSignedBinary, evalUnsignedBinary,
      evalF32Binary, evalF64Binary, evalCharBinary] at evaluated <;>
    subst result <;> exact .boolean _

theorem evalSignedBinary_arithmetic_preserves_type
    (operator : op = .add ∨ op = .subtract ∨ op = .multiply ∨ op = .divide)
    (evaluated : evalSignedBinary program.target op type left right = .ok result) :
    ValueHasType program result (.scalar (.signed type)) := by
  rcases operator with rfl | rfl | rfl | rfl
  · simp [evalSignedBinary] at evaluated
    subst result
    exact .signed type _
      (wrapSigned_in_range program.target type (left + right)).1
      (wrapSigned_in_range program.target type (left + right)).2
  · simp [evalSignedBinary] at evaluated
    subst result
    exact .signed type _
      (wrapSigned_in_range program.target type (left - right)).1
      (wrapSigned_in_range program.target type (left - right)).2
  · simp [evalSignedBinary] at evaluated
    subst result
    exact .signed type _
      (wrapSigned_in_range program.target type (left * right)).1
      (wrapSigned_in_range program.target type (left * right)).2
  · simp only [evalSignedBinary] at evaluated
    split at evaluated
    · cases evaluated
    · split at evaluated
      · cases evaluated
      · simp at evaluated
        subst result
        exact .signed type _
          (wrapSigned_in_range program.target type (truncDiv left right)).1
          (wrapSigned_in_range program.target type (truncDiv left right)).2

theorem evalUnsignedBinary_arithmetic_preserves_type
    (operator : op = .add ∨ op = .subtract ∨ op = .multiply ∨ op = .divide)
    (evaluated : evalUnsignedBinary program.target op type left right = .ok result) :
    ValueHasType program result (.scalar (.unsigned type)) := by
  rcases operator with rfl | rfl | rfl | rfl
  · simp [evalUnsignedBinary] at evaluated
    subst result
    exact .unsigned type _
      (wrapUnsigned_le_max program.target type (left + right))
  · simp [evalUnsignedBinary] at evaluated
    subst result
    exact .unsigned type _
      (wrapUnsigned_le_max program.target type
        (left + unsignedModulus program.target type - right %
          unsignedModulus program.target type))
  · simp [evalUnsignedBinary] at evaluated
    subst result
    exact .unsigned type _
      (wrapUnsigned_le_max program.target type (left * right))
  · simp only [evalUnsignedBinary] at evaluated
    split at evaluated
    · cases evaluated
    · simp at evaluated
      subst result
      exact .unsigned type _
        (wrapUnsigned_le_max program.target type (left / right))

theorem evalF32Binary_arithmetic_preserves_type
    (operator : op = .add ∨ op = .subtract ∨ op = .multiply ∨ op = .divide)
    (evaluated : evalF32Binary op left right = .ok result) :
    ValueHasType program result (.scalar .f32) := by
  rcases operator with rfl | rfl | rfl | rfl <;>
    simp [evalF32Binary] at evaluated <;>
    subst result <;> exact .f32Bits _

theorem evalF64Binary_arithmetic_preserves_type
    (operator : op = .add ∨ op = .subtract ∨ op = .multiply ∨ op = .divide)
    (evaluated : evalF64Binary op left right = .ok result) :
    ValueHasType program result (.scalar .f64) := by
  rcases operator with rfl | rfl | rfl | rfl <;>
    simp [evalF64Binary] at evaluated <;>
    subst result <;> exact .f64Bits _

theorem evalCharBinary_arithmetic_preserves_type
    (operator : op = .add ∨ op = .subtract ∨ op = .multiply ∨ op = .divide)
    (evaluated : evalCharBinary op left right = .ok result) :
    ValueHasType program result (.scalar .char) := by
  rcases operator with rfl | rfl | rfl | rfl
  · simp [evalCharBinary] at evaluated
    subst result
    exact .character _
  · simp [evalCharBinary] at evaluated
    subst result
    exact .character _
  · simp [evalCharBinary] at evaluated
    subst result
    exact .character _
  · simp only [evalCharBinary] at evaluated
    split at evaluated
    · cases evaluated
    · simp at evaluated
      subst result
      exact .character _

theorem evalBinaryValue_arithmetic_preserves_type
    (arithmetic : ArithmeticTy operandType)
    (operator : op = .add ∨ op = .subtract ∨ op = .multiply ∨ op = .divide)
    (leftTyped : ValueHasType program left operandType)
    (rightTyped : ValueHasType program right operandType)
    (evaluated : evalBinaryValue program.target op left right = .ok result) :
    ValueHasType program result operandType := by
  cases arithmetic with
  | signed type =>
      cases leftTyped with
      | signed _ leftValue leftLower leftUpper =>
          cases rightTyped with
          | signed _ rightValue rightLower rightUpper =>
              rcases operator with rfl | rfl | rfl | rfl <;>
                simp [evalBinaryValue] at evaluated <;>
                exact evalSignedBinary_arithmetic_preserves_type (by simp)
                  evaluated
  | unsigned type =>
      cases leftTyped with
      | unsigned _ leftValue leftUpper =>
          cases rightTyped with
          | unsigned _ rightValue rightUpper =>
              rcases operator with rfl | rfl | rfl | rfl <;>
                simp [evalBinaryValue] at evaluated <;>
                exact evalUnsignedBinary_arithmetic_preserves_type (by simp)
                  evaluated
  | f32 =>
      cases leftTyped with
      | f32Bits leftBits =>
          cases rightTyped with
          | f32Bits rightBits =>
              rcases operator with rfl | rfl | rfl | rfl <;>
                simp [evalBinaryValue] at evaluated <;>
                exact evalF32Binary_arithmetic_preserves_type (by simp) evaluated
  | f64 =>
      cases leftTyped with
      | f64Bits leftBits =>
          cases rightTyped with
          | f64Bits rightBits =>
              rcases operator with rfl | rfl | rfl | rfl <;>
                simp [evalBinaryValue] at evaluated <;>
                exact evalF64Binary_arithmetic_preserves_type (by simp) evaluated
  | character =>
      cases leftTyped with
      | character leftCode =>
          cases rightTyped with
          | character rightCode =>
              rcases operator with rfl | rfl | rfl | rfl <;>
                simp [evalBinaryValue] at evaluated <;>
                exact evalCharBinary_arithmetic_preserves_type (by simp) evaluated

theorem evalSignedBinary_integer_preserves_type
    (operator : op = .remainder ∨ op = .bitAnd ∨ op = .bitOr ∨
      op = .bitXor ∨ op = .shiftLeft ∨ op = .shiftRight)
    (evaluated : evalSignedBinary program.target op type left right = .ok result) :
    ValueHasType program result (.scalar (.signed type)) := by
  rcases operator with rfl | rfl | rfl | rfl | rfl | rfl
  · simp only [evalSignedBinary] at evaluated
    split at evaluated
    · cases evaluated
    · split at evaluated
      · cases evaluated
      · simp at evaluated
        subst result
        exact .signed type _
          (wrapSigned_in_range program.target type _).1
          (wrapSigned_in_range program.target type _).2
  · simp [evalSignedBinary] at evaluated
    subst result
    exact .signed type _
      (wrapSigned_in_range program.target type _).1
      (wrapSigned_in_range program.target type _).2
  · simp [evalSignedBinary] at evaluated
    subst result
    exact .signed type _
      (wrapSigned_in_range program.target type _).1
      (wrapSigned_in_range program.target type _).2
  · simp [evalSignedBinary] at evaluated
    subst result
    exact .signed type _
      (wrapSigned_in_range program.target type _).1
      (wrapSigned_in_range program.target type _).2
  · simp only [evalSignedBinary] at evaluated
    split at evaluated
    · cases evaluated
    · simp at evaluated
      subst result
      exact .signed type _
        (wrapSigned_in_range program.target type _).1
        (wrapSigned_in_range program.target type _).2
  · simp only [evalSignedBinary] at evaluated
    split at evaluated
    · cases evaluated
    · simp at evaluated
      subst result
      exact .signed type _
        (wrapSigned_in_range program.target type _).1
        (wrapSigned_in_range program.target type _).2

theorem evalUnsignedBinary_integer_preserves_type
    (operator : op = .remainder ∨ op = .bitAnd ∨ op = .bitOr ∨
      op = .bitXor ∨ op = .shiftLeft ∨ op = .shiftRight)
    (evaluated : evalUnsignedBinary program.target op type left right = .ok result) :
    ValueHasType program result (.scalar (.unsigned type)) := by
  rcases operator with rfl | rfl | rfl | rfl | rfl | rfl
  · simp only [evalUnsignedBinary] at evaluated
    split at evaluated
    · cases evaluated
    · simp at evaluated
      subst result
      exact .unsigned type _
        (wrapUnsigned_le_max program.target type _)
  · simp [evalUnsignedBinary] at evaluated
    subst result
    exact .unsigned type _ (wrapUnsigned_le_max program.target type _)
  · simp [evalUnsignedBinary] at evaluated
    subst result
    exact .unsigned type _ (wrapUnsigned_le_max program.target type _)
  · simp [evalUnsignedBinary] at evaluated
    subst result
    exact .unsigned type _ (wrapUnsigned_le_max program.target type _)
  · simp only [evalUnsignedBinary] at evaluated
    split at evaluated
    · cases evaluated
    · simp at evaluated
      subst result
      exact .unsigned type _ (wrapUnsigned_le_max program.target type _)
  · simp only [evalUnsignedBinary] at evaluated
    split at evaluated
    · cases evaluated
    · simp at evaluated
      subst result
      exact .unsigned type _ (wrapUnsigned_le_max program.target type _)

theorem evalCharBinary_integer_preserves_type
    (operator : op = .remainder ∨ op = .bitAnd ∨ op = .bitOr ∨
      op = .bitXor ∨ op = .shiftLeft ∨ op = .shiftRight)
    (evaluated : evalCharBinary op left right = .ok result) :
    ValueHasType program result (.scalar .char) := by
  rcases operator with rfl | rfl | rfl | rfl | rfl | rfl
  · simp only [evalCharBinary] at evaluated
    split at evaluated
    · cases evaluated
    · simp at evaluated
      subst result
      exact .character _
  · simp [evalCharBinary] at evaluated
    subst result
    exact .character _
  · simp [evalCharBinary] at evaluated
    subst result
    exact .character _
  · simp [evalCharBinary] at evaluated
    subst result
    exact .character _
  · simp only [evalCharBinary] at evaluated
    split at evaluated
    · cases evaluated
    · simp at evaluated
      subst result
      exact .character _
  · simp only [evalCharBinary] at evaluated
    split at evaluated
    · cases evaluated
    · simp at evaluated
      subst result
      exact .character _

theorem evalBinaryValue_integer_preserves_type
    (integer : IntegerTy operandType)
    (operator : op = .remainder ∨ op = .bitAnd ∨ op = .bitOr ∨
      op = .bitXor ∨ op = .shiftLeft ∨ op = .shiftRight)
    (leftTyped : ValueHasType program left operandType)
    (rightTyped : ValueHasType program right operandType)
    (evaluated : evalBinaryValue program.target op left right = .ok result) :
    ValueHasType program result operandType := by
  cases integer with
  | signed type =>
      cases leftTyped with
      | signed _ leftValue leftLower leftUpper =>
          cases rightTyped with
          | signed _ rightValue rightLower rightUpper =>
              rcases operator with rfl | rfl | rfl | rfl | rfl | rfl <;>
                simp [evalBinaryValue] at evaluated <;>
                exact evalSignedBinary_integer_preserves_type (by simp) evaluated
  | unsigned type =>
      cases leftTyped with
      | unsigned _ leftValue leftUpper =>
          cases rightTyped with
          | unsigned _ rightValue rightUpper =>
              rcases operator with rfl | rfl | rfl | rfl | rfl | rfl <;>
                simp [evalBinaryValue] at evaluated <;>
                exact evalUnsignedBinary_integer_preserves_type (by simp) evaluated
  | character =>
      cases leftTyped with
      | character leftCode =>
          cases rightTyped with
          | character rightCode =>
              rcases operator with rfl | rfl | rfl | rfl | rfl | rfl <;>
                simp [evalBinaryValue] at evaluated <;>
                exact evalCharBinary_integer_preserves_type (by simp) evaluated

theorem evalBinaryValue_pointer_offset_preserves_type
    (offset : PointerOffsetTy offsetType)
    (operator : op = .add ∨ op = .subtract)
    (pointerTyped : ValueHasType program pointer (.scalar .rawPtr))
    (offsetTyped : ValueHasType program amount offsetType)
    (evaluated : evalBinaryValue program.target op pointer amount = .ok result) :
    ValueHasType program result (.scalar .rawPtr) := by
  cases pointerTyped with
  | pointer address =>
      rcases operator with rfl | rfl <;> cases offset <;>
        cases offsetTyped <;> simp [evalBinaryValue] at evaluated <;>
        subst result <;> exact .pointer _

theorem evalBinaryValue_preserves_type
    (operation : BinaryOpHasType op leftType rightType resultType)
    (leftTyped : ValueHasType program left leftType)
    (rightTyped : ValueHasType program right rightType)
    (evaluated : evalBinaryValue program.target op left right = .ok result) :
    ValueHasType program result resultType := by
  cases operation with
  | logicalAnd =>
      cases leftTyped with
      | boolean leftValue =>
          cases rightTyped with
          | boolean rightValue =>
              simp [evalBinaryValue] at evaluated
              subst result
              exact .boolean _
  | logicalOr =>
      cases leftTyped with
      | boolean leftValue =>
          cases rightTyped with
          | boolean rightValue =>
              simp [evalBinaryValue] at evaluated
              subst result
              exact .boolean _
  | equal equality =>
      exact evalBinaryValue_equality_preserves_type equality (.inl rfl)
        leftTyped rightTyped evaluated
  | notEqual equality =>
      exact evalBinaryValue_equality_preserves_type equality (.inr rfl)
        leftTyped rightTyped evaluated
  | less ordered =>
      exact evalBinaryValue_ordering_preserves_type ordered (.inl rfl)
        leftTyped rightTyped evaluated
  | lessEqual ordered =>
      exact evalBinaryValue_ordering_preserves_type ordered (.inr (.inl rfl))
        leftTyped rightTyped evaluated
  | greater ordered =>
      exact evalBinaryValue_ordering_preserves_type ordered
        (.inr (.inr (.inl rfl))) leftTyped rightTyped evaluated
  | greaterEqual ordered =>
      exact evalBinaryValue_ordering_preserves_type ordered
        (.inr (.inr (.inr rfl))) leftTyped rightTyped evaluated
  | add arithmetic =>
      exact evalBinaryValue_arithmetic_preserves_type arithmetic (.inl rfl)
        leftTyped rightTyped evaluated
  | pointerAdd offset =>
      exact evalBinaryValue_pointer_offset_preserves_type offset (.inl rfl)
        leftTyped rightTyped evaluated
  | subtract arithmetic =>
      exact evalBinaryValue_arithmetic_preserves_type arithmetic
        (.inr (.inl rfl)) leftTyped rightTyped evaluated
  | pointerSubtract offset =>
      exact evalBinaryValue_pointer_offset_preserves_type offset (.inr rfl)
        leftTyped rightTyped evaluated
  | multiply arithmetic =>
      exact evalBinaryValue_arithmetic_preserves_type arithmetic
        (.inr (.inr (.inl rfl))) leftTyped rightTyped evaluated
  | divide arithmetic =>
      exact evalBinaryValue_arithmetic_preserves_type arithmetic
        (.inr (.inr (.inr rfl))) leftTyped rightTyped evaluated
  | remainder integer =>
      exact evalBinaryValue_integer_preserves_type integer (.inl rfl)
        leftTyped rightTyped evaluated
  | bitAnd integer =>
      exact evalBinaryValue_integer_preserves_type integer (.inr (.inl rfl))
        leftTyped rightTyped evaluated
  | bitOr integer =>
      exact evalBinaryValue_integer_preserves_type integer
        (.inr (.inr (.inl rfl))) leftTyped rightTyped evaluated
  | bitXor integer =>
      exact evalBinaryValue_integer_preserves_type integer
        (.inr (.inr (.inr (.inl rfl)))) leftTyped rightTyped evaluated
  | shiftLeft integer =>
      exact evalBinaryValue_integer_preserves_type integer
        (.inr (.inr (.inr (.inr (.inl rfl))))) leftTyped rightTyped evaluated
  | shiftRight integer =>
      exact evalBinaryValue_integer_preserves_type integer
        (.inr (.inr (.inr (.inr (.inr rfl))))) leftTyped rightTyped evaluated

theorem BinaryOpHasType.output_is_scalar
    (operation : BinaryOpHasType op leftType rightType resultType) :
    ∃ scalar, resultType = .scalar scalar := by
  cases operation with
  | logicalAnd => exact ⟨_, rfl⟩
  | logicalOr => exact ⟨_, rfl⟩
  | equal equality => exact ⟨_, rfl⟩
  | notEqual equality => exact ⟨_, rfl⟩
  | less ordered => exact ⟨_, rfl⟩
  | lessEqual ordered => exact ⟨_, rfl⟩
  | greater ordered => exact ⟨_, rfl⟩
  | greaterEqual ordered => exact ⟨_, rfl⟩
  | add arithmetic => cases arithmetic <;> exact ⟨_, rfl⟩
  | pointerAdd offset => exact ⟨_, rfl⟩
  | subtract arithmetic => cases arithmetic <;> exact ⟨_, rfl⟩
  | pointerSubtract offset => exact ⟨_, rfl⟩
  | multiply arithmetic => cases arithmetic <;> exact ⟨_, rfl⟩
  | divide arithmetic => cases arithmetic <;> exact ⟨_, rfl⟩
  | remainder integer => cases integer <;> exact ⟨_, rfl⟩
  | bitAnd integer => cases integer <;> exact ⟨_, rfl⟩
  | bitOr integer => cases integer <;> exact ⟨_, rfl⟩
  | bitXor integer => cases integer <;> exact ⟨_, rfl⟩
  | shiftLeft integer => cases integer <;> exact ⟨_, rfl⟩
  | shiftRight integer => cases integer <;> exact ⟨_, rfl⟩

theorem evalAssignValue_preserves_type
    (operation : AssignOpHasType op type)
    (currentTyped : ∀ currentValue, current = some currentValue →
      ValueHasType program currentValue type)
    (rightTyped : ValueHasType program right type)
    (evaluated : evalAssignValue program.target op current right = .ok result) :
    ValueHasType program result type := by
  cases operation with
  | set =>
      simp [evalAssignValue, assignOpBinary?] at evaluated
      subst result
      exact rightTyped
  | add arithmetic =>
      cases current with
      | none => simp [evalAssignValue, assignOpBinary?] at evaluated
      | some left =>
          exact evalBinaryValue_preserves_type (.add arithmetic)
            (currentTyped left rfl) rightTyped (by
              simpa [evalAssignValue, assignOpBinary?] using evaluated)
  | subtract arithmetic =>
      cases current with
      | none => simp [evalAssignValue, assignOpBinary?] at evaluated
      | some left =>
          exact evalBinaryValue_preserves_type (.subtract arithmetic)
            (currentTyped left rfl) rightTyped (by
              simpa [evalAssignValue, assignOpBinary?] using evaluated)
  | multiply arithmetic =>
      cases current with
      | none => simp [evalAssignValue, assignOpBinary?] at evaluated
      | some left =>
          exact evalBinaryValue_preserves_type (.multiply arithmetic)
            (currentTyped left rfl) rightTyped (by
              simpa [evalAssignValue, assignOpBinary?] using evaluated)
  | divide arithmetic =>
      cases current with
      | none => simp [evalAssignValue, assignOpBinary?] at evaluated
      | some left =>
          exact evalBinaryValue_preserves_type (.divide arithmetic)
            (currentTyped left rfl) rightTyped (by
              simpa [evalAssignValue, assignOpBinary?] using evaluated)
  | remainder integer =>
      cases current with
      | none => simp [evalAssignValue, assignOpBinary?] at evaluated
      | some left =>
          exact evalBinaryValue_preserves_type (.remainder integer)
            (currentTyped left rfl) rightTyped (by
              simpa [evalAssignValue, assignOpBinary?] using evaluated)
  | bitXor integer =>
      cases current with
      | none => simp [evalAssignValue, assignOpBinary?] at evaluated
      | some left =>
          exact evalBinaryValue_preserves_type (.bitXor integer)
            (currentTyped left rfl) rightTyped (by
              simpa [evalAssignValue, assignOpBinary?] using evaluated)
  | shiftLeft integer =>
      cases current with
      | none => simp [evalAssignValue, assignOpBinary?] at evaluated
      | some left =>
          exact evalBinaryValue_preserves_type (.shiftLeft integer)
            (currentTyped left rfl) rightTyped (by
              simpa [evalAssignValue, assignOpBinary?] using evaluated)
  | shiftRight integer =>
      cases current with
      | none => simp [evalAssignValue, assignOpBinary?] at evaluated
      | some left =>
          exact evalBinaryValue_preserves_type (.shiftRight integer)
            (currentTyped left rfl) rightTyped (by
              simpa [evalAssignValue, assignOpBinary?] using evaluated)
  | bitAnd integer =>
      cases current with
      | none => simp [evalAssignValue, assignOpBinary?] at evaluated
      | some left =>
          exact evalBinaryValue_preserves_type (.bitAnd integer)
            (currentTyped left rfl) rightTyped (by
              simpa [evalAssignValue, assignOpBinary?] using evaluated)
  | bitOr integer =>
      cases current with
      | none => simp [evalAssignValue, assignOpBinary?] at evaluated
      | some left =>
          exact evalBinaryValue_preserves_type (.bitOr integer)
            (currentTyped left rfl) rightTyped (by
              simpa [evalAssignValue, assignOpBinary?] using evaluated)

/-- Raw blocks use abstract, nonzero base identities but retain the size,
    alignment, byte extent, and non-overlap obligations that native and Wasm
    implementations must respect. -/
def BlockWellFormed (block : Block) : Prop :=
  block.base ≠ null ∧
    validAlignment block.alignment = true ∧
    block.bytes.length = block.size ∧
    block.base % block.alignment = 0

def BlockIntervalsDisjoint (left right : Block) : Prop :=
  left.base + left.size ≤ right.base ∨
    right.base + right.size ≤ left.base

def HeapBlockBasesUnique (heap : Heap) : Prop :=
  ∀ left, left ∈ heap.blocks →
    ∀ right, right ∈ heap.blocks → left.base = right.base → left = right

def HeapBlocksDisjoint (heap : Heap) : Prop :=
  ∀ left, left ∈ heap.blocks →
    ∀ right, right ∈ heap.blocks → left ≠ right →
      BlockIntervalsDisjoint left right

/-- `nextAddress` is an allocation frontier, not merely a positive hint.  The
    `max size 1` term reserves a distinct address even for a zero-byte block,
    whose half-open byte interval is otherwise empty. -/
def HeapBlocksBelowNext (heap : Heap) : Prop :=
  ∀ block, block ∈ heap.blocks →
    block.base + max block.size 1 ≤ heap.nextAddress

structure HeapWellFormed (heap : Heap) : Prop where
  nextAddressPositive : null < heap.nextAddress
  blockBasesUnique : HeapBlockBasesUnique heap
  blocksWellFormed : ∀ block, block ∈ heap.blocks → BlockWellFormed block
  blocksDisjoint : HeapBlocksDisjoint heap
  blocksBelowNext : HeapBlocksBelowNext heap

theorem empty_heap_well_formed : HeapWellFormed ({} : Heap) := by
  constructor <;>
    simp [null, HeapBlockBasesUnique, HeapBlocksDisjoint, HeapBlocksBelowNext,
      BlockWellFormed]

theorem replaceBlock_find_same
    (blocks : List Block) (replacement foundBlock : Block)
    (found : blocks.find? (fun block => block.base == replacement.base) =
      some foundBlock) :
    (replaceBlock blocks replacement).find?
        (fun block => block.base == replacement.base) = some replacement := by
  induction blocks with
  | nil => simp at found
  | cons head tail induction =>
      by_cases same : head.base = replacement.base
      · simp [replaceBlock, same]
      · simp [replaceBlock, same] at found ⊢
        exact induction found

theorem replaceBlock_find_other
    (blocks : List Block) (replacement : Block) (queried : Address)
    (different : queried ≠ replacement.base) :
    (replaceBlock blocks replacement).find? (fun block => block.base == queried) =
      blocks.find? (fun block => block.base == queried) := by
  induction blocks with
  | nil => rfl
  | cons head tail induction =>
      by_cases replaced : head.base = replacement.base
      · by_cases queriedHead : head.base = queried
        · exact False.elim (different (queriedHead.symm.trans replaced))
        · have replacementNotQueried : replacement.base ≠ queried :=
            Ne.symm different
          simp [replaceBlock, replaced, replacementNotQueried, induction]
      · by_cases queriedHead : head.base = queried
        · simp [replaceBlock, queriedHead, different]
        · simp [replaceBlock, replaced, queriedHead, induction]

/-- Heap structure depends on block identity and extent, not on the bytes or
    liveness metadata stored inside each block.  Any pointwise transformation
    preserving base and size therefore preserves the global heap geometry. -/
theorem mapBlocks_preserves_heap_well_formed
    (wellFormed : HeapWellFormed heap)
    (baseSame : ∀ block, block ∈ heap.blocks →
      (transform block).base = block.base)
    (sizeSame : ∀ block, block ∈ heap.blocks →
      (transform block).size = block.size)
    (blocksWellFormed : ∀ block, block ∈ heap.blocks →
      BlockWellFormed (transform block))
    (remaining : Option Nat) :
    HeapWellFormed { heap with
      blocks := heap.blocks.map transform
      remaining
    } := by
  constructor
  · exact wellFormed.nextAddressPositive
  · intro left leftMember right rightMember sameBase
    obtain ⟨leftSource, leftSourceMember, rfl⟩ := List.mem_map.mp leftMember
    obtain ⟨rightSource, rightSourceMember, rfl⟩ := List.mem_map.mp rightMember
    have sourceBaseSame : leftSource.base = rightSource.base := by
      calc
        leftSource.base = (transform leftSource).base :=
          (baseSame leftSource leftSourceMember).symm
        _ = (transform rightSource).base := sameBase
        _ = rightSource.base := baseSame rightSource rightSourceMember
    have sourceSame := wellFormed.blockBasesUnique leftSource leftSourceMember
      rightSource rightSourceMember sourceBaseSame
    subst rightSource
    rfl
  · intro block member
    obtain ⟨source, sourceMember, rfl⟩ := List.mem_map.mp member
    exact blocksWellFormed source sourceMember
  · intro left leftMember right rightMember different
    obtain ⟨leftSource, leftSourceMember, rfl⟩ := List.mem_map.mp leftMember
    obtain ⟨rightSource, rightSourceMember, rfl⟩ := List.mem_map.mp rightMember
    have sourceDifferent : leftSource ≠ rightSource := by
      intro same
      subst rightSource
      exact different rfl
    have disjoint := wellFormed.blocksDisjoint leftSource leftSourceMember
      rightSource rightSourceMember sourceDifferent
    unfold BlockIntervalsDisjoint at disjoint ⊢
    rw [baseSame leftSource leftSourceMember,
      sizeSame leftSource leftSourceMember,
      baseSame rightSource rightSourceMember,
      sizeSame rightSource rightSourceMember]
    exact disjoint
  · intro block member
    obtain ⟨source, sourceMember, rfl⟩ := List.mem_map.mp member
    have below := wellFormed.blocksBelowNext source sourceMember
    rw [baseSame source sourceMember, sizeSame source sourceMember]
    exact below

theorem replaceBlock_eq_map (blocks : List Block) (replacement : Block) :
    replaceBlock blocks replacement = blocks.map (fun block =>
      if block.base == replacement.base then replacement else block) := by
  induction blocks with
  | nil => rfl
  | cons head tail induction =>
      simp only [replaceBlock, List.map_cons]
      rw [induction]

/-- Replacing a known block with another well-formed block of the same base
    and size may change bytes, ownership, liveness, or alignment metadata, but
    cannot disturb the heap's global address geometry. -/
theorem replaceBlock_preserves_heap_well_formed
    (wellFormed : HeapWellFormed heap)
    (originalMember : original ∈ heap.blocks)
    (replacementWellFormed : BlockWellFormed replacement)
    (replacementBase : replacement.base = original.base)
    (replacementSize : replacement.size = original.size)
    (remaining : Option Nat) :
    HeapWellFormed { heap with
      blocks := replaceBlock heap.blocks replacement
      remaining
    } := by
  let transform := fun block : Block =>
    if block.base == replacement.base then replacement else block
  rw [replaceBlock_eq_map]
  apply mapBlocks_preserves_heap_well_formed wellFormed
  · intro block member
    split
    · rename_i same
      have equalBase : block.base = replacement.base := by
        simpa using same
      exact equalBase.symm
    · rfl
  · intro block member
    split
    · rename_i same
      have blockIsOriginal := wellFormed.blockBasesUnique block member original
        originalMember (by simpa [replacementBase] using same)
      simpa [blockIsOriginal] using replacementSize
    · rfl
  · intro block member
    split
    · exact replacementWellFormed
    · exact wellFormed.blocksWellFormed block member

def AllocationResultWellFormed (result : AllocationResult) : Prop :=
  match result with
  | .allocated _ heap | .exhausted heap | .trapped _ heap =>
      HeapWellFormed heap

/-- Appending a well-formed block at or beyond the allocation frontier is the
    common structural fact behind owned allocation and borrowed mappings.  It
    is stated independently of allocator budgeting so both operations share
    one proof of identity uniqueness and interval disjointness. -/
theorem appendBlock_preserves_heap_well_formed
    (wellFormed : HeapWellFormed heap)
    (blockWellFormed : BlockWellFormed block)
    (frontierLeBase : heap.nextAddress ≤ block.base)
    (remaining : Option Nat) :
    HeapWellFormed {
      heap with
      blocks := heap.blocks ++ [block]
      nextAddress := block.base + max block.size 1
      remaining
    } := by
  have blockBasePositive : 0 < block.base :=
    Nat.pos_of_ne_zero blockWellFormed.1
  constructor
  · simp only [null]
    exact Nat.lt_of_lt_of_le blockBasePositive
      (Nat.le_add_right block.base (max block.size 1))
  · intro left leftMember right rightMember sameBase
    simp only [List.mem_append, List.mem_singleton] at leftMember rightMember
    rcases leftMember with leftOld | leftNew
    · rcases rightMember with rightOld | rightNew
      · exact wellFormed.blockBasesUnique left leftOld right rightOld sameBase
      · subst right
        have leftBelow := wellFormed.blocksBelowNext left leftOld
        have leftBefore : left.base < block.base := by
          calc
            left.base < left.base + max left.size 1 :=
              Nat.lt_add_of_pos_right
                (Nat.lt_of_lt_of_le Nat.zero_lt_one
                  (Nat.le_max_right left.size 1))
            _ ≤ heap.nextAddress := leftBelow
            _ ≤ block.base := frontierLeBase
        exact False.elim ((Nat.ne_of_lt leftBefore) sameBase)
    · subst left
      rcases rightMember with rightOld | rightNew
      · have rightBelow := wellFormed.blocksBelowNext right rightOld
        have rightBefore : right.base < block.base := by
          calc
            right.base < right.base + max right.size 1 :=
              Nat.lt_add_of_pos_right
                (Nat.lt_of_lt_of_le Nat.zero_lt_one
                  (Nat.le_max_right right.size 1))
            _ ≤ heap.nextAddress := rightBelow
            _ ≤ block.base := frontierLeBase
        exact False.elim ((Nat.ne_of_gt rightBefore) sameBase)
      · subst right
        rfl
  · intro candidate member
    simp only [List.mem_append, List.mem_singleton] at member
    rcases member with old | added
    · exact wellFormed.blocksWellFormed candidate old
    · subst candidate
      exact blockWellFormed
  · intro left leftMember right rightMember different
    simp only [List.mem_append, List.mem_singleton] at leftMember rightMember
    rcases leftMember with leftOld | leftNew
    · rcases rightMember with rightOld | rightNew
      · exact wellFormed.blocksDisjoint left leftOld right rightOld different
      · subst right
        have leftBelow := wellFormed.blocksBelowNext left leftOld
        simp only [BlockIntervalsDisjoint]
        exact Or.inl (Nat.le_trans
          (Nat.add_le_add_left (Nat.le_max_left left.size 1) left.base)
          (Nat.le_trans leftBelow frontierLeBase))
    · subst left
      rcases rightMember with rightOld | rightNew
      · have rightBelow := wellFormed.blocksBelowNext right rightOld
        simp only [BlockIntervalsDisjoint]
        exact Or.inr (Nat.le_trans
          (Nat.add_le_add_left (Nat.le_max_left right.size 1) right.base)
          (Nat.le_trans rightBelow frontierLeBase))
      · subst right
        exact False.elim (different rfl)
  · intro candidate member
    simp only [List.mem_append, List.mem_singleton] at member
    rcases member with old | added
    · have oldBelow := wellFormed.blocksBelowNext candidate old
      exact Nat.le_trans oldBelow (Nat.le_trans frontierLeBase
        (Nat.le_add_right block.base (max block.size 1)))
    · subst candidate
      exact Nat.le_refl _

theorem allocate_preserves_heap_well_formed
    (wellFormed : HeapWellFormed heap) :
    AllocationResultWellFormed (heap.allocate size alignment) := by
  by_cases alignmentValid : validAlignment alignment = true
  · cases budget : consumeBudget heap.remaining size with
    | none =>
        simp [Heap.allocate, alignmentValid, budget,
          AllocationResultWellFormed, wellFormed]
    | some remaining =>
        simp only [Heap.allocate, alignmentValid, Bool.not_true, budget]
        let base := alignUp (max heap.nextAddress 1) alignment
        let block : Block := {
          base
          size
          alignment
          bytes := List.replicate size 0
        }
        let nextHeap : Heap := {
          heap with
          blocks := heap.blocks ++ [block]
          nextAddress := base + max size 1
          remaining
        }
        change HeapWellFormed nextHeap
        have alignmentNonzero :=
          valid_alignment_is_nonzero alignment alignmentValid
        have frontierLeBase : heap.nextAddress ≤ base := by
          have aligned := alignUp_ge (max heap.nextAddress 1) alignment
            alignmentNonzero
          exact Nat.le_trans (Nat.le_max_left _ _) aligned
        have blockWellFormed : BlockWellFormed block := by
          refine ⟨?_, alignmentValid, ?_, ?_⟩
          · simp only [block, base, null]
            have aligned := alignUp_ge (max heap.nextAddress 1) alignment
              alignmentNonzero
            have oneLe : 1 ≤ max heap.nextAddress 1 := Nat.le_max_right _ _
            exact Nat.ne_of_gt (Nat.lt_of_lt_of_le Nat.zero_lt_one
              (Nat.le_trans oneLe aligned))
          · simp [block]
          · simp only [block, base]
            exact alignUp_mod (max heap.nextAddress 1) alignment
        simpa only [nextHeap, block] using
          appendBlock_preserves_heap_well_formed wellFormed blockWellFormed
            frontierLeBase remaining
  · simp [Heap.allocate, alignmentValid, AllocationResultWellFormed,
      wellFormed]

theorem mapBorrowed_preserves_heap_well_formed
    (wellFormed : HeapWellFormed heap) :
    AllocationResultWellFormed (heap.mapBorrowed bytes alignment) := by
  by_cases alignmentValid : validAlignment alignment = true
  · simp only [Heap.mapBorrowed, alignmentValid, Bool.not_true]
    let base := alignUp (max heap.nextAddress 1) alignment
    let block : Block := {
      base
      size := bytes.length
      alignment
      bytes
      owned := false
    }
    let nextHeap : Heap := {
      heap with
      blocks := heap.blocks ++ [block]
      nextAddress := base + max bytes.length 1
    }
    change HeapWellFormed nextHeap
    have alignmentNonzero :=
      valid_alignment_is_nonzero alignment alignmentValid
    have frontierLeBase : heap.nextAddress ≤ base := by
      have aligned := alignUp_ge (max heap.nextAddress 1) alignment
        alignmentNonzero
      exact Nat.le_trans (Nat.le_max_left _ _) aligned
    have blockWellFormed : BlockWellFormed block := by
      refine ⟨?_, alignmentValid, rfl, ?_⟩
      · simp only [block, base, null]
        have aligned := alignUp_ge (max heap.nextAddress 1) alignment
          alignmentNonzero
        have oneLe : 1 ≤ max heap.nextAddress 1 := Nat.le_max_right _ _
        exact Nat.ne_of_gt (Nat.lt_of_lt_of_le Nat.zero_lt_one
          (Nat.le_trans oneLe aligned))
      · simp only [block, base]
        exact alignUp_mod (max heap.nextAddress 1) alignment
    simpa only [nextHeap, block] using
      appendBlock_preserves_heap_well_formed wellFormed blockWellFormed
        frontierLeBase heap.remaining
  · simp [Heap.mapBorrowed, alignmentValid, AllocationResultWellFormed,
      wellFormed]

theorem deallocate_preserves_heap_well_formed
    (wellFormed : HeapWellFormed heap)
    (deallocated : heap.deallocate pointer size alignment = .ok afterHeap) :
    HeapWellFormed afterHeap := by
  by_cases nullPointer : pointer = null
  · subst pointer
    simp only [Heap.deallocate, BEq.rfl, ↓reduceIte, Except.ok.injEq] at deallocated
    subst afterHeap
    exact wellFormed
  · have notNull : (pointer == null) = false := by
      simpa using nullPointer
    simp only [Heap.deallocate, notNull, Bool.false_eq_true, ↓reduceIte] at deallocated
    cases found : heap.block? pointer with
    | none => simp [found] at deallocated
    | some block =>
        simp only [found] at deallocated
        split at deallocated
        · cases deallocated
        · split at deallocated
          · cases deallocated
          · split at deallocated
            · cases deallocated
            · let released : Block := { block with live := false }
              have blockMember : block ∈ heap.blocks :=
                List.mem_of_find?_eq_some found
              have releasedWellFormed : BlockWellFormed released := by
                simpa only [released, BlockWellFormed] using
                  wellFormed.blocksWellFormed block blockMember
              cases deallocated
              exact replaceBlock_preserves_heap_well_formed wellFormed
                blockMember releasedWellFormed rfl rfl
                (refundBudget heap.remaining block.size)

theorem resizeBytes_length (bytes : List UInt8) (size : Nat) :
    (resizeBytes bytes size).length = size := by
  simp only [resizeBytes, List.length_append, List.length_take,
    List.length_replicate]
  omega

theorem i32Bytes_length (value : Int) : (i32Bytes value).length = 4 := by
  simp [i32Bytes]

theorem encodeI32Array_length
    (encoded : encodeI32Array elements = .ok bytes) :
    bytes.length = elements.length * 4 := by
  induction elements generalizing bytes with
  | nil =>
      simp only [encodeI32Array, Except.ok.injEq] at encoded
      subst bytes
      rfl
  | cons head tail induction =>
      cases head <;> try simp [encodeI32Array] at encoded
      rename_i type value
      cases type <;> try simp [encodeI32Array] at encoded
      cases tailEncoded : encodeI32Array tail with
      | error reason => simp [tailEncoded] at encoded
      | ok tailBytes =>
          rw [tailEncoded] at encoded
          cases encoded
          simp only [List.length_append, i32Bytes_length, List.length_cons]
          have tailLength := induction tailEncoded
          omega

theorem ValuesHaveTypes.length_eq
    (typed : ValuesHaveTypes program values types) :
    values.length = types.length := by
  cases typed with
  | nil => rfl
  | cons head tail =>
      simp [Lanius.Properties.ValuesHaveTypes.length_eq tail]
termination_by values.length

theorem decodeI32_in_range (target : Target) (bytes : List UInt8) :
    signedMin target .i32 ≤ decodeI32 bytes ∧
      decodeI32 bytes ≤ signedMax target .i32 := by
  rcases bytes with _ | ⟨⟩
  · simp [decodeI32, signedMin, signedMax, SignedIntTy.bits]
  rename_i byte0 rest
  rcases rest with _ | ⟨⟩
  · simp [decodeI32, signedMin, signedMax, SignedIntTy.bits]
  rename_i byte1 rest
  rcases rest with _ | ⟨⟩
  · simp [decodeI32, signedMin, signedMax, SignedIntTy.bits]
  rename_i byte2 rest
  rcases rest with _ | ⟨⟩
  · simp [decodeI32, signedMin, signedMax, SignedIntTy.bits]
  rename_i byte3 rest
  have byte0Bound := UInt8.toNat_lt byte0
  have byte1Bound := UInt8.toNat_lt byte1
  have byte2Bound := UInt8.toNat_lt byte2
  have byte3Bound := UInt8.toNat_lt byte3
  let bits := byte0.toNat + byte1.toNat * 2 ^ 8 +
    byte2.toNat * 2 ^ 16 + byte3.toNat * 2 ^ 24
  have bitsBound : bits < 2 ^ 32 := by
    simp only [bits]
    omega
  have bitsNonnegative : 0 ≤ Int.ofNat bits := Int.natCast_nonneg bits
  have bitsUpperInt : Int.ofNat bits < Int.ofNat (2 ^ 32) :=
    Int.ofNat_lt.mpr bitsBound
  change -(2 ^ (32 - 1)) ≤
      (if bits ≥ 2 ^ 31 then Int.ofNat bits - 2 ^ 32 else Int.ofNat bits) ∧
    (if bits ≥ 2 ^ 31 then Int.ofNat bits - 2 ^ 32 else Int.ofNat bits) ≤
      2 ^ (32 - 1) - 1
  split
  · rename_i atLeastSignBit
    have lowerInt : Int.ofNat (2 ^ 31) ≤ Int.ofNat bits :=
      Int.ofNat_le.mpr atLeastSignBit
    have upperConcrete : Int.ofNat bits < 4294967296 := by
      simpa using bitsUpperInt
    have lowerConcrete : 2147483648 ≤ Int.ofNat bits := by
      simpa using lowerInt
    change (-2147483648 : Int) ≤ Int.ofNat bits - 4294967296 ∧
      Int.ofNat bits - 4294967296 ≤ 2147483647
    omega
  · rename_i belowSignBit
    have upperNat : bits < 2 ^ 31 := by omega
    have upperInt : Int.ofNat bits < Int.ofNat (2 ^ 31) :=
      Int.ofNat_lt.mpr upperNat
    have upperConcrete : Int.ofNat bits < 2147483648 := by
      simpa using upperInt
    change (-2147483648 : Int) ≤ Int.ofNat bits ∧
      Int.ofNat bits ≤ 2147483647
    omega

theorem decodeI32Array_values_have_types
    (decoded : decodeI32Array length bytes = .ok values) :
    ValuesHaveTypes program values
      (List.replicate length (.scalar (.signed .i32))) := by
  induction length generalizing bytes values with
  | zero =>
      simp only [decodeI32Array] at decoded
      split at decoded
      · cases decoded
        exact .nil
      · cases decoded
  | succ length induction =>
      simp only [decodeI32Array] at decoded
      split at decoded
      · cases decoded
      · cases tailDecoded : decodeI32Array length (bytes.drop 4) with
        | error reason => simp [tailDecoded] at decoded
        | ok tail =>
            rw [tailDecoded] at decoded
            cases decoded
            exact .cons
              (.signed .i32 (decodeI32 (bytes.take 4))
                (decodeI32_in_range program.target (bytes.take 4)).1
                (decodeI32_in_range program.target (bytes.take 4)).2)
              (induction tailDecoded)

theorem decodeI32Array_has_type
    (decoded : decodeI32Array length bytes = .ok values) :
    ValueHasType program (.array values)
      (.array (.scalar (.signed .i32)) length) := by
  have elements := decodeI32Array_values_have_types
    (program := program) decoded
  exact .array values (.scalar (.signed .i32))
    (by simpa using (ValuesHaveTypes.length_eq elements)) elements

theorem allocate_success_block_size
    (wellFormed : HeapWellFormed heap)
    (allocated : heap.allocate size alignment = .allocated pointer afterHeap)
    (found : afterHeap.block? pointer = some block) :
    block.size = size := by
  by_cases alignmentValid : validAlignment alignment = true
  · cases budget : consumeBudget heap.remaining size with
    | none =>
        simp [Heap.allocate, alignmentValid, budget] at allocated
    | some remaining =>
        let base := alignUp (max heap.nextAddress 1) alignment
        let fresh : Block := {
          base
          size
          alignment
          bytes := List.replicate size 0
        }
        let allocatedHeap : Heap := {
          heap with
          blocks := heap.blocks ++ [fresh]
          nextAddress := base + max size 1
          remaining
        }
        have shape : heap.allocate size alignment =
            .allocated base allocatedHeap := by
          simp [Heap.allocate, alignmentValid, budget, allocatedHeap, fresh,
            base]
        rw [shape] at allocated
        have pointerEq : base = pointer := by injection allocated
        have heapEq : allocatedHeap = afterHeap := by injection allocated
        subst pointer
        subst afterHeap
        have allocatedWellFormed : HeapWellFormed allocatedHeap := by
          simpa only [AllocationResultWellFormed, shape] using
            allocate_preserves_heap_well_formed wellFormed
              (size := size) (alignment := alignment)
        have blockMember : block ∈ allocatedHeap.blocks :=
          List.mem_of_find?_eq_some found
        have freshMember : fresh ∈ allocatedHeap.blocks := by
          simp [allocatedHeap]
        have blockBase : block.base = base := by
          have predicate := List.find?_some found
          exact beq_iff_eq.mp predicate
        have same := allocatedWellFormed.blockBasesUnique block blockMember
          fresh freshMember (by simpa only [fresh] using blockBase)
        subst block
        rfl
  · simp [Heap.allocate, alignmentValid] at allocated

theorem reallocate_preserves_heap_well_formed
    (wellFormed : HeapWellFormed heap) :
    AllocationResultWellFormed
      (heap.reallocate pointer oldSize newSize alignment) := by
  by_cases nullPointer : pointer = null
  · subst pointer
    simp only [Heap.reallocate, BEq.rfl, ↓reduceIte]
    exact allocate_preserves_heap_well_formed wellFormed
  · have notNull : (pointer == null) = false := by simpa using nullPointer
    simp only [Heap.reallocate, notNull, Bool.false_eq_true, ↓reduceIte]
    by_cases zeroSize : newSize = 0
    · have isZero : (newSize == 0) = true := by simpa using zeroSize
      simp only [isZero, ↓reduceIte]
      cases released : heap.deallocate pointer oldSize alignment with
      | error reason =>
          simp [released, AllocationResultWellFormed, wellFormed]
      | ok releasedHeap =>
          have releasedWellFormed := deallocate_preserves_heap_well_formed
            wellFormed released
          simp [released, AllocationResultWellFormed, releasedWellFormed]
    · have notZero : (newSize == 0) = false := by simpa using zeroSize
      simp only [notZero, Bool.false_eq_true, ↓reduceIte]
      cases found : heap.block? pointer with
      | none => simp [found, AllocationResultWellFormed, wellFormed]
      | some oldBlock =>
          simp only [found]
          split
          · simp [AllocationResultWellFormed, wellFormed]
          · split
            · simp [AllocationResultWellFormed, wellFormed]
            · split
              · simp [AllocationResultWellFormed, wellFormed]
              · cases released : heap.deallocate pointer oldSize alignment with
                | error reason =>
                    simp [released, AllocationResultWellFormed, wellFormed]
                | ok credited =>
                    have creditedWellFormed :=
                      deallocate_preserves_heap_well_formed wellFormed released
                    simp only [released]
                    cases allocatedResult : credited.allocate newSize alignment with
                    | exhausted exhausted =>
                        simp [allocatedResult, AllocationResultWellFormed,
                          wellFormed]
                    | trapped reason trapped =>
                        simp [allocatedResult, AllocationResultWellFormed,
                          wellFormed]
                    | allocated replacement allocated =>
                        have allocatedResultWellFormed :=
                          allocate_preserves_heap_well_formed creditedWellFormed
                            (size := newSize) (alignment := alignment)
                        rw [allocatedResult] at allocatedResultWellFormed
                        simp only [AllocationResultWellFormed] at allocatedResultWellFormed
                        simp only [allocatedResult]
                        cases replacementFound : allocated.block? replacement with
                        | none =>
                            simp [replacementFound, AllocationResultWellFormed,
                              wellFormed]
                        | some newBlock =>
                            simp only [replacementFound]
                            let copied : Block := {
                              newBlock with
                              bytes := resizeBytes oldBlock.bytes newSize
                            }
                            have newBlockMember : newBlock ∈ allocated.blocks :=
                              List.mem_of_find?_eq_some replacementFound
                            have newBlockWellFormed :=
                              allocatedResultWellFormed.blocksWellFormed
                                newBlock newBlockMember
                            have copiedWellFormed : BlockWellFormed copied := by
                              refine ⟨newBlockWellFormed.1,
                                newBlockWellFormed.2.1, ?_,
                                newBlockWellFormed.2.2.2⟩
                              have allocatedSize : newBlock.size = newSize :=
                                allocate_success_block_size creditedWellFormed
                                  allocatedResult replacementFound
                              simpa only [copied, resizeBytes_length,
                                allocatedSize]
                            exact replaceBlock_preserves_heap_well_formed
                              allocatedResultWellFormed newBlockMember
                              copiedWellFormed rfl rfl allocated.remaining

/-- Appending a fresh block cannot change a successful lookup in the old
    prefix of the heap's block table. -/
theorem block?_append_preserves_found
    (heap : Heap) (address : Address) (foundBlock block : Block)
    (found : heap.block? address = some foundBlock) :
    ({ heap with blocks := heap.blocks ++ [block] } : Heap).block? address =
      some foundBlock := by
  simp only [Heap.block?] at found ⊢
  rw [List.find?_append, found]
  rfl

theorem block?_append_fresh
    (wellFormed : HeapWellFormed heap)
    (frontierLeBase : heap.nextAddress ≤ block.base) :
    ({ heap with blocks := heap.blocks ++ [block] } : Heap).block? block.base =
      some block := by
  simp only [Heap.block?, List.find?_append]
  have oldNone : heap.blocks.find? (fun candidate =>
      candidate.base == block.base) = none := by
    apply List.find?_eq_none.mpr
    intro candidate member same
    have sameBase : candidate.base = block.base := beq_iff_eq.mp same
    have below := wellFormed.blocksBelowNext candidate member
    have before : candidate.base < block.base := by
      calc
        candidate.base < candidate.base + max candidate.size 1 :=
          Nat.lt_add_of_pos_right
            (Nat.lt_of_lt_of_le Nat.zero_lt_one
              (Nat.le_max_right candidate.size 1))
        _ ≤ heap.nextAddress := below
        _ ≤ block.base := frontierLeBase
    exact (Nat.ne_of_lt before) sameBase
  rw [oldNone]
  simp

/-- Stable semantic cells are allocated monotonically and never reused.  This
    is stronger than an implementation's physical allocation policy: an
    implementation may reclaim an unreachable cell, but it may not recycle an
    identity while a value can still name it. -/
def CellIdsUnique (state : State) : Prop :=
  ∀ left, left ∈ state.cells →
    ∀ right, right ∈ state.cells → left.id = right.id → left = right

def CellIdsBelowNext (state : State) : Prop :=
  ∀ cell, cell ∈ state.cells → cell.id < state.nextCell

/-- Lexical environments contain cell identities, not values.  Every live
    binding therefore names a cell in the stable cell store. -/
def LocalsReferenceCells (state : State) : Prop :=
  ∀ binding, binding ∈ state.locals →
    ∃ cell, cell ∈ state.cells ∧ cell.id = binding.2

structure StateWellFormed (state : State) : Prop where
  heapWellFormed : HeapWellFormed state.heap
  cellIdsUnique : CellIdsUnique state
  cellIdsBelowNext : CellIdsBelowNext state
  localsReferenceCells : LocalsReferenceCells state

theorem empty_state_well_formed : StateWellFormed ({} : State) := by
  constructor
  · exact empty_heap_well_formed
  · simp [CellIdsUnique]
  · simp [CellIdsBelowNext]
  · simp [LocalsReferenceCells]

/-- Binding initialized and uninitialized locals is the same allocation
    operation at the memory-model level. -/
theorem bindCell_preserves_well_formed
    (state : State) (id : VarId) (value : Option Value)
    (wellFormed : StateWellFormed state) :
    StateWellFormed (state.bindCell id value) := by
  constructor
  · exact wellFormed.heapWellFormed
  · intro left leftMember right rightMember sameId
    simp [State.bindCell] at leftMember rightMember
    rcases leftMember with leftMember | leftNew
    · rcases rightMember with rightMember | rightNew
      · exact wellFormed.cellIdsUnique left leftMember right rightMember sameId
      · subst right
        exfalso
        exact (Nat.ne_of_lt
          (wellFormed.cellIdsBelowNext left leftMember)) sameId
    · subst left
      rcases rightMember with rightMember | rightNew
      · exfalso
        exact (Nat.ne_of_lt
          (wellFormed.cellIdsBelowNext right rightMember)) sameId.symm
      · subst right
        rfl
  · intro cell member
    simp [State.bindCell] at member
    rcases member with old | new
    · exact Nat.lt_succ_of_lt (wellFormed.cellIdsBelowNext cell old)
    · subst cell
      exact Nat.lt_add_one state.nextCell
  · intro binding member
    simp [State.bindCell] at member
    rcases member with new | old
    · subst binding
      refine ⟨{ id := state.nextCell, value }, ?_, rfl⟩
      change { id := state.nextCell, value } ∈
        state.cells ++ [{ id := state.nextCell, value }]
      exact List.mem_append_right state.cells (by simp)
    · obtain ⟨cell, cellMember, cellId⟩ :=
        wellFormed.localsReferenceCells binding old
      refine ⟨cell, ?_, cellId⟩
      change cell ∈ state.cells ++ [{ id := state.nextCell, value }]
      exact List.mem_append_left _ cellMember

theorem bindLocal_preserves_well_formed
    (state : State) (id : VarId) (value : Value)
    (wellFormed : StateWellFormed state) :
    StateWellFormed (state.bindLocal id value) := by
  exact bindCell_preserves_well_formed state id (some value) wellFormed

theorem bindUninitialized_preserves_well_formed
    (state : State) (id : VarId)
    (wellFormed : StateWellFormed state) :
    StateWellFormed (state.bindUninitialized id) := by
  exact bindCell_preserves_well_formed state id none wellFormed

theorem replaceCell_find_same
    (cells : List Cell) (id : CellId) (value : Value) (entry : Cell)
    (found : cells.find? (fun cell => cell.id == id) = some entry) :
    (replaceCell cells id value).find? (fun cell => cell.id == id) =
      some { entry with value := some value } := by
  induction cells with
  | nil => simp at found
  | cons head tail inductionHypothesis =>
      by_cases same : head.id = id
      · simp [replaceCell, same] at found ⊢
        subst entry
        exact same.symm
      · simp [replaceCell, same] at found ⊢
        exact inductionHypothesis found

theorem replaceCell_find_other
    (cells : List Cell) (assigned queried : CellId) (value : Value)
    (different : queried ≠ assigned) :
    (replaceCell cells assigned value).find?
        (fun cell => cell.id == queried) =
      cells.find? (fun cell => cell.id == queried) := by
  induction cells with
  | nil => rfl
  | cons head tail inductionHypothesis =>
      by_cases assignedHead : head.id = assigned
      · subst assigned
        have notQueried : head.id ≠ queried := Ne.symm different
        simp [replaceCell, notQueried, inductionHypothesis]
      · by_cases queriedHead : head.id = queried
        · simp [replaceCell, queriedHead, different]
        · simp [replaceCell, assignedHead, queriedHead, inductionHypothesis]

theorem assignCell_state
    {state next : State} {cell : CellId} {value : Value}
    (assigned : state.assignCell cell value = some next) :
    next = { state with cells := replaceCell state.cells cell value } := by
  simp only [State.assignCell] at assigned
  split at assigned
  · exact Option.some.inj assigned.symm
  · cases assigned

theorem assignCell_finds_assigned
    {state next : State} {cell : CellId} {value : Value}
    (assigned : state.assignCell cell value = some next) :
    next.cellEntry? cell = some { id := cell, value := some value } := by
  have presentWitness : ∃ entry, state.cellEntry? cell = some entry := by
    simp only [State.assignCell] at assigned
    split at assigned <;> rename_i present
    · cases found : state.cellEntry? cell with
      | none => simp [found] at present
      | some entry => exact ⟨entry, rfl⟩
    · cases assigned
  obtain ⟨entry, found⟩ := presentWitness
  have entryId : entry.id = cell := by
    simpa using List.find?_some found
  rw [assignCell_state assigned]
  change (replaceCell state.cells cell value).find?
      (fun candidate => candidate.id == cell) = _
  rw [replaceCell_find_same state.cells cell value entry found]
  subst entryId
  rfl

theorem assignCell_preserves_other
    {state next : State} {cell queried : CellId} {value : Value}
    (assigned : state.assignCell cell value = some next)
    (different : queried ≠ cell) :
    next.cellEntry? queried = state.cellEntry? queried := by
  rw [assignCell_state assigned]
  exact replaceCell_find_other state.cells cell queried value different

theorem replaceCell_eq_map
    (cells : List Cell) (id : CellId) (value : Value) :
    replaceCell cells id value = cells.map fun cell =>
      if cell.id == id then { cell with value := some value } else cell := by
  induction cells with
  | nil => rfl
  | cons head tail inductionHypothesis =>
      by_cases same : head.id = id <;>
        simp [replaceCell, same, inductionHypothesis]

@[simp] theorem updatedCell_id
    (entry : Cell) (id : CellId) (value : Value) :
    (if entry.id == id then { entry with value := some value } else entry).id =
      entry.id := by
  split <;> rfl

theorem assignCell_preserves_well_formed
    (typed : StateWellFormed state)
    (assigned : state.assignCell cell value = some next) :
    StateWellFormed next := by
  rw [assignCell_state assigned]
  constructor
  · exact typed.heapWellFormed
  · intro left leftMember right rightMember sameId
    rw [replaceCell_eq_map] at leftMember rightMember
    obtain ⟨oldLeft, oldLeftMember, leftEq⟩ := List.mem_map.1 leftMember
    obtain ⟨oldRight, oldRightMember, rightEq⟩ := List.mem_map.1 rightMember
    subst left
    subst right
    have oldSameId : oldLeft.id = oldRight.id := by
      calc
        oldLeft.id =
            (if oldLeft.id == cell then
              { oldLeft with value := some value } else oldLeft).id :=
          (updatedCell_id oldLeft cell value).symm
        _ = (if oldRight.id == cell then
              { oldRight with value := some value } else oldRight).id := sameId
        _ = oldRight.id := updatedCell_id oldRight cell value
    have oldSame := typed.cellIdsUnique oldLeft oldLeftMember oldRight
      oldRightMember oldSameId
    subst oldRight
    rfl
  · intro entry member
    rw [replaceCell_eq_map] at member
    obtain ⟨oldEntry, oldMember, entryEq⟩ := List.mem_map.1 member
    subst entry
    rw [updatedCell_id]
    exact typed.cellIdsBelowNext oldEntry oldMember
  · intro binding member
    obtain ⟨oldEntry, oldMember, sameId⟩ :=
      typed.localsReferenceCells binding member
    refine ⟨if oldEntry.id == cell then
        { oldEntry with value := some value } else oldEntry, ?_, ?_⟩
    · rw [replaceCell_eq_map]
      exact List.mem_map.2 ⟨oldEntry, oldMember, rfl⟩
    · rw [updatedCell_id]
      exact sameId

theorem allocateTemporary_returns_fresh_cell
    (state : State) (value : Value) :
    (state.allocateTemporary value).1 = state.nextCell := by
  rfl

theorem allocateTemporary_cell_is_retained
    (state : State) (value : Value) :
    ∃ cell, cell ∈ (state.allocateTemporary value).2.cells ∧
      cell.id = (state.allocateTemporary value).1 ∧
      cell.value = some value := by
  refine ⟨{ id := state.nextCell, value := some value }, ?_, rfl, rfl⟩
  simp [State.allocateTemporary]

theorem nextCell_is_not_allocated
    (state : State) (wellFormed : StateWellFormed state) :
    state.cellEntry? state.nextCell = none := by
  apply List.find?_eq_none.2
  intro cell member
  simp only [Bool.not_eq_true]
  simpa using Nat.ne_of_lt (wellFormed.cellIdsBelowNext cell member)

theorem found_cell_is_below_next
    (state : State) (cell : CellId) (entry : Cell)
    (wellFormed : StateWellFormed state)
    (found : state.cellEntry? cell = some entry) :
    cell < state.nextCell := by
  have member : entry ∈ state.cells := by
    exact List.mem_of_find?_eq_some found
  have identified : entry.id = cell := by
    have matched := List.find?_some found
    simpa using matched
  rw [← identified]
  exact wellFormed.cellIdsBelowNext entry member

theorem allocateTemporary_finds_fresh_cell
    (state : State) (value : Value)
    (wellFormed : StateWellFormed state) :
    (state.allocateTemporary value).2.cellEntry?
      (state.allocateTemporary value).1 =
      some { id := state.nextCell, value := some value } := by
  simp only [State.allocateTemporary, State.cellEntry?, List.find?_append]
  rw [show state.cells.find? (fun cell => cell.id == state.nextCell) = none from
    nextCell_is_not_allocated state wellFormed]
  simp

theorem allocateTemporary_preserves_old_cell
    (state : State) (value : Value) (cell : CellId)
    (old : cell < state.nextCell) :
    (state.allocateTemporary value).2.cellEntry? cell = state.cellEntry? cell := by
  simp [State.allocateTemporary, State.cellEntry?, List.find?_append,
    Nat.ne_of_gt old]

theorem allocateTemporary_preserves_other_cell
    (state : State) (value : Value) (cell : CellId)
    (different : cell ≠ state.nextCell) :
    (state.allocateTemporary value).2.cellEntry? cell = state.cellEntry? cell := by
  simp [State.allocateTemporary, State.cellEntry?, List.find?_append,
    Ne.symm different]

theorem bindCell_finds_fresh_cell
    (state : State) (id : VarId) (value : Option Value)
    (wellFormed : StateWellFormed state) :
    (state.bindCell id value).cellEntry? state.nextCell =
      some { id := state.nextCell, value } := by
  simp only [State.bindCell, State.cellEntry?, List.find?_append]
  rw [show state.cells.find? (fun cell => cell.id == state.nextCell) = none from
    nextCell_is_not_allocated state wellFormed]
  simp

theorem bindCell_preserves_old_cell
    (state : State) (id : VarId) (value : Option Value) (cell : CellId)
    (old : cell < state.nextCell) :
    (state.bindCell id value).cellEntry? cell = state.cellEntry? cell := by
  simp [State.bindCell, State.cellEntry?, List.find?_append,
    Nat.ne_of_gt old]

theorem bindCell_preserves_other_cell
    (state : State) (id : VarId) (value : Option Value) (cell : CellId)
    (different : cell ≠ state.nextCell) :
    (state.bindCell id value).cellEntry? cell = state.cellEntry? cell := by
  simp [State.bindCell, State.cellEntry?, List.find?_append,
    Ne.symm different]

/-- Leaving lexical scope removes a name but deliberately retains its stable
    cell, so a reference or slice that escaped the scope does not dangle. -/
theorem unbindLocal_preserves_cells
    (state : State) (id : VarId) :
    (state.unbindLocal id).cells = state.cells := by
  rfl

theorem unbindLocal_preserves_cell
    (state : State) (localId : VarId) (cell : CellId) :
    (state.unbindLocal localId).cellEntry? cell = state.cellEntry? cell := by
  rfl

theorem unbindLocal_preserves_well_formed
    (state : State) (id : VarId) (wellFormed : StateWellFormed state) :
    StateWellFormed (state.unbindLocal id) := by
  constructor
  · exact wellFormed.heapWellFormed
  · exact wellFormed.cellIdsUnique
  · exact wellFormed.cellIdsBelowNext
  · intro binding member
    exact wellFormed.localsReferenceCells binding
      (state.mem_of_mem_unbindLocal id binding member)

/-- Temporary aggregate storage uses the same monotone cell allocation as a
    local binding but introduces no lexical name. This is the storage used by
    escaping slices and borrowed raw-array views of non-place expressions. -/
theorem allocateTemporary_preserves_well_formed
    (state : State) (value : Value)
    (wellFormed : StateWellFormed state) :
    StateWellFormed (state.allocateTemporary value).2 := by
  change StateWellFormed ((state.bindLocal 0 value).unbindLocal 0)
  exact unbindLocal_preserves_well_formed
    (state.bindLocal 0 value) 0
    (bindLocal_preserves_well_formed state 0 value wellFormed)

abbrev StoreTyping := CellId → Option Ty

def StoreTyping.extend
    (store : StoreTyping) (cell : CellId) (type : Ty) : StoreTyping :=
  fun candidate => if candidate == cell then some type else store candidate

def StoreExtends (before after : StoreTyping) : Prop :=
  ∀ cell type, before cell = some type → after cell = some type

theorem StoreExtends.refl (store : StoreTyping) : StoreExtends store store := by
  intro cell type found
  exact found

theorem StoreExtends.trans
    (left : StoreExtends first second) (right : StoreExtends second third) :
    StoreExtends first third := by
  intro cell type found
  exact right cell type (left cell type found)

@[simp] theorem StoreTyping.extend_same
    (store : StoreTyping) (cell : CellId) (type : Ty) :
    (store.extend cell type) cell = some type := by
  simp [StoreTyping.extend]

theorem StoreTyping.extend_other
    (store : StoreTyping) (fresh cell : CellId) (type : Ty)
    (different : cell ≠ fresh) :
    (store.extend fresh type) cell = store cell := by
  simp [StoreTyping.extend, different]

theorem StoreTyping.extends_extend
    (store : StoreTyping) (cell : CellId) (type : Ty)
    (fresh : store cell = none) :
    StoreExtends store (store.extend cell type) := by
  intro oldCell oldType found
  by_cases same : oldCell = cell
  · subst oldCell
    rw [fresh] at found
    cases found
  · simpa [StoreTyping.extend_other store cell oldCell type same] using found

/-- Projection typing is independent of a particular value. Array indices are
    dynamically bounds-checked; their static effect is always to select the
    element type. -/
inductive ProjectionHasType (program : Program) :
    Ty → List ValueProjection → Ty → Prop where
  | nil : ProjectionHasType program type [] type
  | field
      (declaration : StructDecl)
      (found : program.structure? typeId = some declaration)
      (fieldFound : declaration.fields[field]? = some fieldType)
      (tail : ProjectionHasType program fieldType projections resultType) :
      ProjectionHasType program (.structure typeId)
        (.field field :: projections) resultType
  | arrayIndex
      (tail : ProjectionHasType program elementType projections resultType) :
      ProjectionHasType program (.array elementType length)
        (.index index :: projections) resultType
  | sliceIndex
      (tail : ProjectionHasType program elementType projections resultType) :
      ProjectionHasType program (.slice elementType)
        (.index index :: projections) resultType

theorem ProjectionHasType.trans
    (prefixTyped : ProjectionHasType program rootType prefixPath middleType)
    (suffixTyped : ProjectionHasType program middleType suffixPath resultType) :
    ProjectionHasType program rootType (prefixPath ++ suffixPath) resultType := by
  induction prefixTyped with
  | nil => simpa using suffixTyped
  | field declaration found fieldFound tail inductionHypothesis =>
      simpa using ProjectionHasType.field declaration found fieldFound
        (inductionHypothesis suffixTyped)
  | arrayIndex tail inductionHypothesis =>
      simpa using ProjectionHasType.arrayIndex
        (inductionHypothesis suffixTyped)
  | sliceIndex tail inductionHypothesis =>
      simpa using ProjectionHasType.sliceIndex
        (inductionHypothesis suffixTyped)

inductive BorrowDescriptor where
  | reference (referent : Ty) (cell : CellId) (projections : List ValueProjection)
  | slice (elementType : Ty) (cell : CellId) (projections : List ValueProjection)
      (start length : Nat)

mutual
  def valueBorrows : Value → List BorrowDescriptor
    | .array values => valueListBorrows values
    | .structure _ fields => valueListBorrows fields
    | .enumeration _ _ payload => valueListBorrows payload
    | .slice elementType cell projections start length =>
        [.slice elementType cell projections start length]
    | .reference referent cell projections => [.reference referent cell projections]
    | _ => []

  def valueListBorrows : List Value → List BorrowDescriptor
    | [] => []
    | head :: tail => valueBorrows head ++ valueListBorrows tail
end

inductive BorrowValid
    (program : Program) (state : State) (store : StoreTyping) :
    BorrowDescriptor → Prop where
  | reference
      (storedType : store cell = some rootType)
      (cellFound : state.cellEntry? cell = some entry)
      (initialized : entry.value = some rootValue)
      (rootTyped : ValueHasType program rootValue rootType)
      (projected : ProjectionHasType program rootType projections referent) :
      BorrowValid program state store (.reference referent cell projections)
  | slice
      (storedType : store cell = some rootType)
      (cellFound : state.cellEntry? cell = some entry)
      (initialized : entry.value = some rootValue)
      (rootTyped : ValueHasType program rootValue rootType)
      (projected : ProjectionHasType program rootType projections
        (.array elementType arrayLength))
      (inBounds : start + length ≤ arrayLength) :
      BorrowValid program state store
        (.slice elementType cell projections start length)

/-- Every reference stored inside a value names an initialized live cell whose
    statically assigned root type supports the reference's projection path. -/
def BorrowsValid
    (program : Program) (state : State) (store : StoreTyping) (value : Value) : Prop :=
  ∀ descriptor, descriptor ∈ valueBorrows value →
    BorrowValid program state store descriptor

theorem BorrowValid.withWorld
    (valid : BorrowValid program state store descriptor)
    (world : World.State) :
    BorrowValid program { state with world := world } store descriptor := by
  cases valid with
  | reference stored found initialized rootTyped projected =>
      exact .reference stored found initialized rootTyped projected
  | slice stored found initialized rootTyped projected inBounds =>
      exact .slice stored found initialized rootTyped projected inBounds

theorem BorrowsValid.withWorld
    (valid : BorrowsValid program state store value)
    (world : World.State) :
    BorrowsValid program { state with world := world } store value := by
  intro descriptor member
  exact (valid descriptor member).withWorld world

theorem BorrowValid.withI32ArrayViews
    (valid : BorrowValid program state store descriptor)
    (views : List I32ArrayView) :
    BorrowValid program { state with i32ArrayViews := views } store descriptor := by
  cases valid with
  | reference stored found initialized rootTyped projected =>
      exact .reference stored found initialized rootTyped projected
  | slice stored found initialized rootTyped projected inBounds =>
      exact .slice stored found initialized rootTyped projected inBounds

theorem BorrowsValid.withI32ArrayViews
    (valid : BorrowsValid program state store value)
    (views : List I32ArrayView) :
    BorrowsValid program { state with i32ArrayViews := views } store value := by
  intro descriptor member
  exact (valid descriptor member).withI32ArrayViews views

theorem BorrowValid.withHeap
    (valid : BorrowValid program state store descriptor)
    (heap : Heap) :
    BorrowValid program { state with heap := heap } store descriptor := by
  cases valid with
  | reference stored found initialized rootTyped projected =>
      exact .reference stored found initialized rootTyped projected
  | slice stored found initialized rootTyped projected inBounds =>
      exact .slice stored found initialized rootTyped projected inBounds

theorem BorrowsValid.withHeap
    (valid : BorrowsValid program state store value)
    (heap : Heap) :
    BorrowsValid program { state with heap := heap } store value := by
  intro descriptor member
  exact (valid descriptor member).withHeap heap

theorem BorrowValid.withLocals
    (valid : BorrowValid program state store descriptor)
    (locals : List (VarId × CellId)) :
    BorrowValid program { state with locals := locals } store descriptor := by
  cases valid with
  | reference stored found initialized rootTyped projected =>
      exact .reference stored found initialized rootTyped projected
  | slice stored found initialized rootTyped projected inBounds =>
      exact .slice stored found initialized rootTyped projected inBounds

theorem BorrowsValid.withLocals
    (valid : BorrowsValid program state store value)
    (locals : List (VarId × CellId)) :
    BorrowsValid program { state with locals := locals } store value := by
  intro descriptor member
  exact (valid descriptor member).withLocals locals

def ValuesBorrowsValid
    (program : Program) (state : State) (store : StoreTyping)
    (values : List Value) : Prop :=
  ∀ descriptor, descriptor ∈ valueListBorrows values →
    BorrowValid program state store descriptor

theorem ValuesBorrowsValid.head
    (valid : ValuesBorrowsValid program state store (value :: values)) :
    BorrowsValid program state store value := by
  intro descriptor member
  exact valid descriptor (by
    simp [valueListBorrows, member])

theorem ValuesBorrowsValid.tail
    (valid : ValuesBorrowsValid program state store (value :: values)) :
    ValuesBorrowsValid program state store values := by
  intro descriptor member
  exact valid descriptor (by
    simp [valueListBorrows, member])

/-- A value embedded directly in a core term or constant cannot capture a
    runtime cell. References and slices arise dynamically from borrow and
    array-to-slice expressions instead. -/
def ValueIsClosed (value : Value) : Prop := valueBorrows value = []

mutual
  theorem Value.isLiteral_is_closed
      (value : Value) (literal : Typing.Value.isLiteral value = true) :
      ValueIsClosed value := by
    cases value with
    | array values =>
        exact Values.areLiteral_is_closed values literal
    | «structure» typeId values =>
        exact Values.areLiteral_is_closed values literal
    | enumeration typeId variant values =>
        exact Values.areLiteral_is_closed values literal
    | slice elementType cell projections start length =>
        simp [Typing.Value.isLiteral] at literal
    | reference referent cell projections =>
        simp [Typing.Value.isLiteral] at literal
    | unit => rfl
    | boolean value => rfl
    | signed type value => rfl
    | unsigned type value => rfl
    | f32Bits bits => rfl
    | f64Bits bits => rfl
    | character value => rfl
    | string value => rfl
    | pointer address => rfl

  theorem Values.areLiteral_is_closed
      (values : List Value) (literal : Typing.Values.areLiteral values = true) :
      valueListBorrows values = [] := by
    cases values with
    | nil => rfl
    | cons value values =>
        simp only [Typing.Values.areLiteral, Bool.and_eq_true] at literal
        have headClosed := Value.isLiteral_is_closed value literal.1
        unfold ValueIsClosed at headClosed
        rw [valueListBorrows, headClosed,
          Values.areLiteral_is_closed values literal.2, List.nil_append]
end

theorem ExprHasType.literal_is_closed
    (typed : ExprHasType program context (.value value) type) :
    ValueIsClosed value := by
  cases typed with
  | value valueTyped literal =>
      exact Value.isLiteral_is_closed value literal

theorem World.i32Result_is_closed (value : Int) :
    ValueIsClosed (World.i32Result value) := by
  rfl

@[simp] theorem World.valueBorrows_i32Result (value : Int) :
    valueBorrows (World.i32Result value) = [] := by
  rfl

theorem decodeI32Array_is_closed
    (decoded : decodeI32Array length bytes = .ok values) :
    ValueIsClosed (.array values) := by
  induction length generalizing bytes values with
  | zero =>
      simp only [decodeI32Array] at decoded
      split at decoded
      · cases decoded
        rfl
      · cases decoded
  | succ length induction =>
      simp only [decodeI32Array] at decoded
      split at decoded
      · cases decoded
      · cases tailDecoded : decodeI32Array length (bytes.drop 4) with
        | error reason => simp [tailDecoded] at decoded
        | ok tail =>
            rw [tailDecoded] at decoded
            cases decoded
            have tailClosed := induction tailDecoded
            simpa only [ValueIsClosed, valueBorrows, valueListBorrows,
              List.nil_append] using tailClosed

theorem ValueIsClosed.borrowsValid
    (closed : ValueIsClosed value) :
    BorrowsValid program state store value := by
  intro descriptor member
  rw [closed] at member
  simp at member

theorem ValueHasType.scalar_is_closed
    (typed : ValueHasType program value (.scalar type)) :
    ValueIsClosed value := by
  cases typed <;> rfl

theorem ValuesHaveTypes.drop
    (count : Nat) (typed : ValuesHaveTypes program values types) :
    ValuesHaveTypes program (values.drop count) (types.drop count) := by
  induction count generalizing values types with
  | zero => simpa
  | succ count inductionHypothesis =>
      cases typed with
      | nil => exact .nil
      | cons head tail =>
          simpa using inductionHypothesis tail

theorem ValuesHaveTypes.take
    (count : Nat) (typed : ValuesHaveTypes program values types) :
    ValuesHaveTypes program (values.take count) (types.take count) := by
  induction count generalizing values types with
  | zero => exact .nil
  | succ count inductionHypothesis =>
      cases typed with
      | nil => exact .nil
      | cons head tail =>
          simpa using ValuesHaveTypes.cons head (inductionHypothesis tail)

theorem ValuesHaveTypes.replicate_of_mem
    (typed : ∀ value, value ∈ values → ValueHasType program value type) :
    ValuesHaveTypes program values (List.replicate values.length type) := by
  induction values with
  | nil => exact .nil
  | cons value values induction =>
      exact .cons (typed value (by simp))
        (induction fun tailValue member => typed tailValue (by simp [member]))

inductive BindingsHaveTypes (program : Program) :
    List (VarId × Value) → List (VarId × Ty) → Prop where
  | nil : BindingsHaveTypes program [] []
  | cons
      {id : VarId}
      (head : ValueHasType program value type)
      (tail : BindingsHaveTypes program values types) :
      BindingsHaveTypes program ((id, value) :: values) ((id, type) :: types)

theorem BindingsHaveTypes.append
    (left : BindingsHaveTypes program leftValues leftTypes)
    (right : BindingsHaveTypes program rightValues rightTypes) :
    BindingsHaveTypes program (leftValues ++ rightValues)
      (leftTypes ++ rightTypes) := by
  induction left generalizing rightValues rightTypes with
  | nil => exact right
  | cons head tail induction =>
      exact .cons head (induction right)

theorem ValuesHaveTypes.parameterBindings
    (typed : ValuesHaveTypes program arguments (parameters.map Prod.snd)) :
    BindingsHaveTypes program
      ((parameters.zip arguments).map fun pair => (pair.1.1, pair.2))
      parameters := by
  induction parameters generalizing arguments with
  | nil =>
      cases arguments with
      | nil => exact .nil
      | cons value values => cases typed
  | cons parameter parameters induction =>
      cases arguments with
      | nil => cases typed
      | cons value values =>
          cases typed with
          | cons head tail =>
              exact .cons head (induction tail)

theorem bindParameters_preserves_types
    (typed : ValuesHaveTypes program arguments (parameters.map Prod.snd))
    (bound : bindParameters parameters arguments = some bindings) :
    BindingsHaveTypes program bindings parameters := by
  have sameLength : parameters.length = arguments.length := by
    simpa using (Lanius.Properties.ValuesHaveTypes.length_eq typed).symm
  simp only [bindParameters, sameLength, beq_self_eq_true, if_true,
    Option.some.injEq] at bound
  subst bindings
  exact Lanius.Properties.ValuesHaveTypes.parameterBindings typed

theorem bindParameters_exists
    (typed : ValuesHaveTypes program arguments (parameters.map Prod.snd)) :
    ∃ bindings, bindParameters parameters arguments = some bindings := by
  have sameLength : parameters.length = arguments.length := by
    simpa using (Lanius.Properties.ValuesHaveTypes.length_eq typed).symm
  refine ⟨(parameters.zip arguments).map fun pair => (pair.1.1, pair.2), ?_⟩
  simp [bindParameters, sameLength]

def BindingsBorrowsValid
    (program : Program) (state : State) (store : StoreTyping)
    (bindings : List (VarId × Value)) : Prop :=
  ∀ binding, binding ∈ bindings →
    BorrowsValid program state store binding.2

theorem BindingsBorrowsValid.nil :
    BindingsBorrowsValid program state store [] := by
  intro binding member
  simp at member

theorem BindingsBorrowsValid.cons
    {id : VarId}
    (head : BorrowsValid program state store value)
    (tail : BindingsBorrowsValid program state store bindings) :
    BindingsBorrowsValid program state store ((id, value) :: bindings) := by
  intro binding member
  simp only [List.mem_cons] at member
  rcases member with same | member
  · subst binding
    exact head
  · exact tail binding member

theorem BindingsBorrowsValid.append
    (left : BindingsBorrowsValid program state store leftBindings)
    (right : BindingsBorrowsValid program state store rightBindings) :
    BindingsBorrowsValid program state store (leftBindings ++ rightBindings) := by
  intro binding member
  rw [List.mem_append] at member
  exact member.elim (left binding) (right binding)

theorem ValuesBorrowsValid.parameterBindings
    (parameters : List (VarId × Ty)) (arguments : List Value)
    (typed : ValuesHaveTypes program arguments (parameters.map Prod.snd))
    (valid : ValuesBorrowsValid program state store arguments) :
    BindingsBorrowsValid program state store
      ((parameters.zip arguments).map fun pair => (pair.1.1, pair.2)) := by
  induction parameters generalizing arguments with
  | nil =>
      cases arguments with
      | nil => exact BindingsBorrowsValid.nil
      | cons value values => cases typed
  | cons parameter parameters induction =>
      cases arguments with
      | nil => cases typed
      | cons value values =>
          cases typed with
          | cons head tail =>
              exact BindingsBorrowsValid.cons valid.head
                (induction values tail valid.tail)

theorem bindParameters_preserves_borrows
    (parameters : List (VarId × Ty)) (arguments : List Value)
    (typed : ValuesHaveTypes program arguments (parameters.map Prod.snd))
    (valid : ValuesBorrowsValid program state store arguments)
    (bound : bindParameters parameters arguments = some bindings) :
    BindingsBorrowsValid program state store bindings := by
  have sameLength : parameters.length = arguments.length := by
    simpa using (Lanius.Properties.ValuesHaveTypes.length_eq typed).symm
  simp only [bindParameters, sameLength, beq_self_eq_true, if_true,
    Option.some.injEq] at bound
  subst bindings
  exact Lanius.Properties.ValuesBorrowsValid.parameterBindings
    parameters arguments typed valid

mutual
  theorem matchPattern_preserves_types
      (patternTyped : PatternHasType program pattern type bindingTypes)
      (valueTyped : ValueHasType program value type)
      (matched : matchPattern pattern value = some bindings) :
      BindingsHaveTypes program bindings bindingTypes := by
    cases patternTyped with
    | wildcard =>
        simp only [matchPattern, Option.some.injEq] at matched
        subst bindings
        exact .nil
    | bind id =>
        simp only [matchPattern, Option.some.injEq] at matched
        subst bindings
        exact .cons valueTyped .nil
    | literal literalTyped =>
        simp only [matchPattern] at matched
        cases equalResult : scalarEqual _ _ with
        | none =>
            rw [equalResult] at matched
            simp at matched
        | some result =>
            rw [equalResult] at matched
            cases result with
            | false => simp at matched
            | true =>
                simp only [Option.some.injEq] at matched
                subst bindings
                exact .nil
    | enumVariant declaration found variantFound payloadTyped =>
        cases valueTyped with
        | enumeration valueDeclaration valueFound valueVariantFound valuesTyped =>
            rename_i expectedVariant expectedPayloadTypes patterns actualVariant
              actualPayloadTypes values
            have sameDeclaration : valueDeclaration = declaration := by
              exact Option.some.inj (valueFound.symm.trans found)
            subst valueDeclaration
            simp only [matchPattern] at matched
            split at matched <;> rename_i tagsMatch
            · have variantEqual : expectedVariant = actualVariant := by
                simpa using tagsMatch
              subst actualVariant
              have samePayloadTypes : expectedPayloadTypes = actualPayloadTypes :=
                Option.some.inj (variantFound.symm.trans valueVariantFound)
              subst actualPayloadTypes
              exact matchPatterns_preserves_types payloadTyped valuesTyped matched
            · cases matched

  theorem matchPatterns_preserves_types
      (patternsTyped : PatternsHaveTypes program patterns types bindingTypes)
      (valuesTyped : ValuesHaveTypes program values types)
      (matched : matchPatterns patterns values = some bindings) :
      BindingsHaveTypes program bindings bindingTypes := by
    cases patternsTyped with
    | nil =>
        cases valuesTyped with
        | nil =>
            simp only [matchPatterns, Option.some.injEq] at matched
            subst bindings
            exact .nil
    | cons headTyped tailTyped =>
        cases valuesTyped with
        | cons valueTyped valuesTyped =>
            simp only [matchPatterns] at matched
            cases headResult : matchPattern _ _ with
            | none =>
                rw [headResult] at matched
                simp at matched
            | some headBindings =>
                rw [headResult] at matched
                cases tailResult : matchPatterns _ _ with
                | none =>
                    rw [tailResult] at matched
                    simp at matched
                | some tailBindings =>
                    rw [tailResult] at matched
                    simp only [Option.some.injEq] at matched
                    subst bindings
                    exact (matchPattern_preserves_types headTyped valueTyped
                      headResult).append
                        (matchPatterns_preserves_types tailTyped valuesTyped
                          tailResult)
end

mutual
  theorem matchPattern_preserves_borrows
      (patternTyped : PatternHasType program pattern type bindingTypes)
      (valueTyped : ValueHasType program value type)
      (sourceBorrows : BorrowsValid program state store value)
      (matched : matchPattern pattern value = some bindings) :
      BindingsBorrowsValid program state store bindings := by
    cases patternTyped with
    | wildcard =>
        simp only [matchPattern, Option.some.injEq] at matched
        subst bindings
        exact BindingsBorrowsValid.nil
    | bind id =>
        simp only [matchPattern, Option.some.injEq] at matched
        subst bindings
        exact BindingsBorrowsValid.cons sourceBorrows
          BindingsBorrowsValid.nil
    | literal literalTyped =>
        simp only [matchPattern] at matched
        cases equalResult : scalarEqual _ _ with
        | none =>
            rw [equalResult] at matched
            simp at matched
        | some result =>
            rw [equalResult] at matched
            cases result with
            | false => simp at matched
            | true =>
                simp only [Option.some.injEq] at matched
                subst bindings
                exact BindingsBorrowsValid.nil
    | enumVariant declaration found variantFound payloadTyped =>
        cases valueTyped with
        | enumeration valueDeclaration valueFound valueVariantFound valuesTyped =>
            rename_i expectedVariant expectedPayloadTypes patterns actualVariant
              actualPayloadTypes values
            have sameDeclaration : valueDeclaration = declaration := by
              exact Option.some.inj (valueFound.symm.trans found)
            subst valueDeclaration
            simp only [matchPattern] at matched
            split at matched <;> rename_i tagsMatch
            · have variantEqual : expectedVariant = actualVariant := by
                simpa using tagsMatch
              subst actualVariant
              have samePayloadTypes : expectedPayloadTypes = actualPayloadTypes :=
                Option.some.inj (variantFound.symm.trans valueVariantFound)
              subst actualPayloadTypes
              have payloadBorrows :
                  ValuesBorrowsValid program state store values := by
                intro descriptor member
                exact sourceBorrows descriptor (by
                  simpa [valueBorrows] using member)
              exact matchPatterns_preserves_borrows payloadTyped valuesTyped
                payloadBorrows matched
            · cases matched

  theorem matchPatterns_preserves_borrows
      (patternsTyped : PatternsHaveTypes program patterns types bindingTypes)
      (valuesTyped : ValuesHaveTypes program values types)
      (sourceBorrows : ValuesBorrowsValid program state store values)
      (matched : matchPatterns patterns values = some bindings) :
      BindingsBorrowsValid program state store bindings := by
    cases patternsTyped with
    | nil =>
        cases valuesTyped with
        | nil =>
            simp only [matchPatterns, Option.some.injEq] at matched
            subst bindings
            exact BindingsBorrowsValid.nil
    | cons headTyped tailTyped =>
        cases valuesTyped with
        | cons valueTyped valuesTyped =>
            have headBorrows := sourceBorrows.head
            have tailBorrows := sourceBorrows.tail
            simp only [matchPatterns] at matched
            cases headResult : matchPattern _ _ with
            | none =>
                rw [headResult] at matched
                simp at matched
            | some headBindings =>
                rw [headResult] at matched
                cases tailResult : matchPatterns _ _ with
                | none =>
                    rw [tailResult] at matched
                    simp at matched
                | some tailBindings =>
                    rw [tailResult] at matched
                    simp only [Option.some.injEq] at matched
                    subst bindings
                    exact (matchPattern_preserves_borrows headTyped valueTyped
                      headBorrows headResult).append
                        (matchPatterns_preserves_borrows tailTyped valuesTyped
                          tailBorrows tailResult)
end

def ProgramConstantsClosed (program : Program) : Prop :=
  ∀ constant, constant ∈ program.constants → ValueIsClosed constant.value

/-- A store typing covers every semantic cell. Uninitialized cells still have
    a type; initialized cells contain a value of that type and no dangling or
    ill-projected references. -/
def StoreMatches
    (program : Program) (state : State) (store : StoreTyping) : Prop :=
  ∀ entry, entry ∈ state.cells →
    ∃ type, store entry.id = some type ∧
      match entry.value with
      | none => True
      | some value => ValueHasType program value type ∧
          BorrowsValid program state store value

/-- The store typing has neither missing nor speculative rows: its domain is
    exactly the stable cells allocated in the semantic state. This makes a
    newly allocated `nextCell` genuinely fresh in both domains. -/
def StoreDomainMatches (state : State) (store : StoreTyping) : Prop :=
  ∀ cell, (store cell).isSome = (state.cellEntry? cell).isSome

/-- The lexical type context and runtime local environment have the same
    visible names. Their selected stable cell carries the selected type. -/
def LocalsMatch
    (context : Context) (state : State) (store : StoreTyping) : Prop :=
  ∀ id,
    match context id, state.cellId? id with
    | some type, some cell => store cell = some type
    | none, none => True
    | _, _ => False

structure StateHasType
    (program : Program) (context : Context)
    (state : State) (store : StoreTyping) : Prop where
  wellFormed : StateWellFormed state
  storeDomain : StoreDomainMatches state store
  storeMatches : StoreMatches program state store
  localsMatch : LocalsMatch context state store

def I32ArrayPlaceHasType
    (program : Program) (state : State) (store : StoreTyping)
    (root : CellId) (projections : List ValueProjection) (length : Nat) : Prop :=
  ∃ rootType entry rootValue,
    store root = some rootType ∧
    state.cellEntry? root = some entry ∧
    entry.value = some rootValue ∧
    ValueHasType program rootValue rootType ∧
    ProjectionHasType program rootType projections
      (.array (.scalar (.signed .i32)) length)

def I32ArrayViewPlaceHasType
    (program : Program) (state : State) (store : StoreTyping)
    (view : I32ArrayView) : Prop :=
  I32ArrayPlaceHasType program state store view.root view.projections view.length

theorem I32ArrayPlaceHasType.withHeap
    (typed : I32ArrayPlaceHasType program state store root projections length)
    (heap : Heap) :
    I32ArrayPlaceHasType program { state with heap := heap } store
      root projections length := by
  obtain ⟨rootType, entry, rootValue, stored, found, initialized,
    rootTyped, projected⟩ := typed
  exact ⟨rootType, entry, rootValue, stored, found, initialized,
    rootTyped, projected⟩

theorem I32ArrayPlaceHasType.withI32ArrayViews
    (typed : I32ArrayPlaceHasType program state store root projections length)
    (views : List I32ArrayView) :
    I32ArrayPlaceHasType program { state with i32ArrayViews := views } store
      root projections length := by
  obtain ⟨rootType, entry, rootValue, stored, found, initialized,
    rootTyped, projected⟩ := typed
  exact ⟨rootType, entry, rootValue, stored, found, initialized,
    rootTyped, projected⟩

def I32ArrayViewBlockWellFormed (heap : Heap) (view : I32ArrayView) : Prop :=
  ∃ block,
    heap.block? view.address = some block ∧
    block.live = true ∧
    block.owned = false ∧
    block.size = view.length * 4 ∧
    block.alignment = 4

/-- A registered raw view must connect one exactly typed `[i32; N]` place to
    one live, non-owning heap block of `4 * N` bytes. Byte coherence is a
    transition property established by the explicit synchronization passes;
    this structural invariant is what makes either direction safe to run. -/
def I32ArrayViewWellFormed
    (program : Program) (state : State) (store : StoreTyping)
    (view : I32ArrayView) : Prop :=
  I32ArrayViewPlaceHasType program state store view ∧
    I32ArrayViewBlockWellFormed state.heap view

theorem I32ArrayViewWellFormed.withI32ArrayViews
    (valid : I32ArrayViewWellFormed program state store view)
    (views : List I32ArrayView) :
    I32ArrayViewWellFormed program
      { state with i32ArrayViews := views } store view := by
  exact ⟨valid.1.withI32ArrayViews views, valid.2⟩

def I32ArrayViewsWellFormed
    (program : Program) (state : State) (store : StoreTyping) : Prop :=
  ∀ view, view ∈ state.i32ArrayViews →
    I32ArrayViewWellFormed program state store view

def I32ArrayViewBlocksPreserved
    (views : List I32ArrayView) (beforeHeap afterHeap : Heap) : Prop :=
  ∀ view, view ∈ views →
    I32ArrayViewBlockWellFormed beforeHeap view →
    I32ArrayViewBlockWellFormed afterHeap view

theorem I32ArrayViewBlocksPreserved.refl (heap : Heap)
    (views : List I32ArrayView) :
    I32ArrayViewBlocksPreserved views heap heap := by
  intro view member valid
  exact valid

theorem I32ArrayViewBlocksPreserved.trans
    (first : I32ArrayViewBlocksPreserved views beforeHeap middleHeap)
    (second : I32ArrayViewBlocksPreserved views middleHeap afterHeap) :
    I32ArrayViewBlocksPreserved views beforeHeap afterHeap := by
  intro view member valid
  exact second view member (first view member valid)

theorem appendBlock_preserves_i32_array_view_blocks
    (views : List I32ArrayView) (heap : Heap) (block : Block) :
    I32ArrayViewBlocksPreserved views heap
      { heap with blocks := heap.blocks ++ [block] } := by
  intro view member valid
  obtain ⟨viewBlock, found, live, borrowed, size, alignment⟩ := valid
  exact ⟨viewBlock,
    block?_append_preserves_found heap view.address viewBlock block found,
    live, borrowed, size, alignment⟩

theorem replaceBlock_preserves_i32_array_view_blocks
    (heapWellFormed : HeapWellFormed heap)
    (originalMember : original ∈ heap.blocks)
    (replacementBase : replacement.base = original.base)
    (replacementSize : replacement.size = original.size)
    (replacementLive : replacement.live = original.live)
    (replacementOwned : replacement.owned = original.owned)
    (replacementAlignment : replacement.alignment = original.alignment)
    (remaining : Option Nat) :
    I32ArrayViewBlocksPreserved views heap {
      heap with
      blocks := replaceBlock heap.blocks replacement
      remaining
    } := by
  intro view member valid
  obtain ⟨viewBlock, found, live, borrowed, size, alignment⟩ := valid
  by_cases sameAddress : view.address = replacement.base
  · have viewBlockMember : viewBlock ∈ heap.blocks :=
      List.mem_of_find?_eq_some found
    have foundList :
        heap.blocks.find? (fun block => block.base == view.address) =
          some viewBlock := by
      simpa only [Heap.block?] using found
    have predicate : (viewBlock.base == view.address) = true :=
      List.find?_some (p := fun block : Block =>
        block.base == view.address) foundList
    have viewBlockBase : viewBlock.base = view.address :=
      beq_iff_eq.mp predicate
    have sameBase : viewBlock.base = original.base := by
      calc
        viewBlock.base = view.address := viewBlockBase
        _ = replacement.base := sameAddress
        _ = original.base := replacementBase
    have sameBlock := heapWellFormed.blockBasesUnique viewBlock viewBlockMember
      original originalMember sameBase
    subst viewBlock
    refine ⟨replacement, ?_, ?_, ?_, ?_, ?_⟩
    · simp only [Heap.block?]
      have originalFound :
          heap.blocks.find? (fun block => block.base == replacement.base) =
            some original := by
        simpa only [Heap.block?, sameAddress] using found
      simpa only [sameAddress] using
        replaceBlock_find_same heap.blocks replacement original originalFound
    · simpa only [replacementLive] using live
    · simpa only [replacementOwned] using borrowed
    · simpa only [replacementSize] using size
    · simpa only [replacementAlignment] using alignment
  · refine ⟨viewBlock, ?_, live, borrowed, size, alignment⟩
    simp only [Heap.block?] at found ⊢
    exact (replaceBlock_find_other heap.blocks replacement view.address
      sameAddress).trans found

theorem replaceOwnedBlock_preserves_i32_array_view_blocks
    (heapWellFormed : HeapWellFormed heap)
    (originalMember : original ∈ heap.blocks)
    (originalOwned : original.owned = true)
    (replacementBase : replacement.base = original.base)
    (remaining : Option Nat) :
    I32ArrayViewBlocksPreserved views heap {
      heap with
      blocks := replaceBlock heap.blocks replacement
      remaining
    } := by
  intro view member valid
  obtain ⟨viewBlock, found, live, borrowed, size, alignment⟩ := valid
  have different : view.address ≠ replacement.base := by
    intro sameAddress
    have viewBlockMember : viewBlock ∈ heap.blocks :=
      List.mem_of_find?_eq_some found
    have foundList :
        heap.blocks.find? (fun block => block.base == view.address) =
          some viewBlock := by
      simpa only [Heap.block?] using found
    have viewBlockBase : viewBlock.base = view.address :=
      beq_iff_eq.mp (List.find?_some
        (p := fun block : Block => block.base == view.address) foundList)
    have sameBase : viewBlock.base = original.base := by
      calc
        viewBlock.base = view.address := viewBlockBase
        _ = replacement.base := sameAddress
        _ = original.base := replacementBase
    have sameBlock := heapWellFormed.blockBasesUnique viewBlock viewBlockMember
      original originalMember sameBase
    subst viewBlock
    rw [originalOwned] at borrowed
    contradiction
  refine ⟨viewBlock, ?_, live, borrowed, size, alignment⟩
  simp only [Heap.block?] at found ⊢
  exact (replaceBlock_find_other heap.blocks replacement view.address
    different).trans found

theorem setByte_length (bytes : List UInt8) (index : Nat) (value : UInt8) :
    (setByte bytes index value).length = bytes.length := by
  induction bytes generalizing index with
  | nil => rfl
  | cons first rest induction =>
      cases index with
      | zero => rfl
      | succ index =>
          simp only [setByte, List.length_cons]
          exact congrArg Nat.succ (induction index)

theorem storeByte_preserves_heap_well_formed
    (wellFormed : HeapWellFormed heap)
    (stored : heap.storeByte pointer offset byte = .ok afterHeap) :
    HeapWellFormed afterHeap := by
  cases containing : heap.containingBlock? (pointer + offset) with
  | none =>
      rw [Heap.storeByte, containing] at stored
      cases pointerContaining : heap.containingBlock? pointer with
      | some block => simp [pointerContaining] at stored
      | none =>
          cases direct : heap.block? pointer with
          | none => simp [pointerContaining, direct] at stored
          | some block =>
              simp only [pointerContaining, direct] at stored
              split at stored <;> contradiction
  | some block =>
    rw [Heap.storeByte, containing] at stored
    let updated : Block := {
      block with
      bytes := setByte block.bytes (pointer + offset - block.base) byte
    }
    have blockMember : block ∈ heap.blocks :=
      List.mem_of_find?_eq_some containing
    have blockWellFormed := wellFormed.blocksWellFormed block blockMember
    have updatedWellFormed : BlockWellFormed updated := by
      refine ⟨blockWellFormed.1, blockWellFormed.2.1, ?_,
        blockWellFormed.2.2.2⟩
      simpa only [updated, setByte_length] using blockWellFormed.2.2.1
    simp only at stored
    cases stored
    exact replaceBlock_preserves_heap_well_formed wellFormed blockMember
      updatedWellFormed rfl rfl heap.remaining

theorem storeByte_preserves_i32_array_view_blocks
    (wellFormed : HeapWellFormed heap)
    (stored : heap.storeByte pointer offset byte = .ok afterHeap) :
    I32ArrayViewBlocksPreserved views heap afterHeap := by
  cases containing : heap.containingBlock? (pointer + offset) with
  | none =>
      rw [Heap.storeByte, containing] at stored
      cases pointerContaining : heap.containingBlock? pointer with
      | some block => simp [pointerContaining] at stored
      | none =>
          cases direct : heap.block? pointer with
          | none => simp [pointerContaining, direct] at stored
          | some block =>
              simp only [pointerContaining, direct] at stored
              split at stored <;> contradiction
  | some block =>
    rw [Heap.storeByte, containing] at stored
    let updated : Block := {
      block with
      bytes := setByte block.bytes (pointer + offset - block.base) byte
    }
    have blockMember : block ∈ heap.blocks :=
      List.mem_of_find?_eq_some containing
    cases stored
    exact replaceBlock_preserves_i32_array_view_blocks
      (views := views) (original := block) (replacement := updated)
      wellFormed blockMember rfl rfl rfl rfl rfl heap.remaining

theorem storeBytesFrom_preserves_heap_well_formed
    (wellFormed : HeapWellFormed heap)
    (stored : storeBytesFrom heap pointer offset bytes = .ok afterHeap) :
    HeapWellFormed afterHeap := by
  induction bytes generalizing heap offset with
  | nil =>
      simp only [storeBytesFrom, Except.ok.injEq] at stored
      subst afterHeap
      exact wellFormed
  | cons byte rest induction =>
      simp only [storeBytesFrom] at stored
      cases storedByte : heap.storeByte pointer offset byte with
      | error reason => simp [storedByte] at stored
      | ok nextHeap =>
          rw [storedByte] at stored
          have nextWellFormed := storeByte_preserves_heap_well_formed
            wellFormed storedByte
          exact induction nextWellFormed stored

theorem storeBytes_preserves_heap_well_formed
    (wellFormed : HeapWellFormed heap)
    (stored : heap.storeBytes pointer bytes = .ok afterHeap) :
    HeapWellFormed afterHeap := by
  exact storeBytesFrom_preserves_heap_well_formed wellFormed stored

theorem storeBytesFrom_preserves_i32_array_view_blocks
    (wellFormed : HeapWellFormed heap)
    (stored : storeBytesFrom heap pointer offset bytes = .ok afterHeap) :
    I32ArrayViewBlocksPreserved views heap afterHeap := by
  induction bytes generalizing heap offset with
  | nil =>
      simp only [storeBytesFrom, Except.ok.injEq] at stored
      subst afterHeap
      exact I32ArrayViewBlocksPreserved.refl heap views
  | cons byte rest induction =>
      simp only [storeBytesFrom] at stored
      cases storedByte : heap.storeByte pointer offset byte with
      | error reason => simp [storedByte] at stored
      | ok nextHeap =>
          rw [storedByte] at stored
          have nextWellFormed := storeByte_preserves_heap_well_formed
            wellFormed storedByte
          have first := storeByte_preserves_i32_array_view_blocks
            (views := views) wellFormed storedByte
          have second := induction nextWellFormed stored
          exact first.trans second

theorem storeBytes_preserves_i32_array_view_blocks
    (wellFormed : HeapWellFormed heap)
    (stored : heap.storeBytes pointer bytes = .ok afterHeap) :
    I32ArrayViewBlocksPreserved views heap afterHeap := by
  exact storeBytesFrom_preserves_i32_array_view_blocks wellFormed stored

theorem deallocate_preserves_i32_array_view_blocks
    (wellFormed : HeapWellFormed heap)
    (deallocated : heap.deallocate pointer size alignment = .ok afterHeap) :
    I32ArrayViewBlocksPreserved views heap afterHeap := by
  by_cases nullPointer : pointer = null
  · subst pointer
    simp only [Heap.deallocate, BEq.rfl, ↓reduceIte, Except.ok.injEq] at deallocated
    subst afterHeap
    exact I32ArrayViewBlocksPreserved.refl heap views
  · have notNull : (pointer == null) = false := by simpa using nullPointer
    simp only [Heap.deallocate, notNull, Bool.false_eq_true, ↓reduceIte] at deallocated
    cases found : heap.block? pointer with
    | none => simp [found] at deallocated
    | some block =>
        simp only [found] at deallocated
        cases live : block.live with
        | false => simp [live] at deallocated
        | true =>
            simp only [live, Bool.not_true, Bool.false_eq_true, ↓reduceIte] at deallocated
            cases owned : block.owned with
            | false => simp [owned] at deallocated
            | true =>
                simp only [owned, Bool.not_true, Bool.false_eq_true,
                  ↓reduceIte] at deallocated
                split at deallocated
                · cases deallocated
                · let released : Block := { block with live := false }
                  have blockMember : block ∈ heap.blocks :=
                    List.mem_of_find?_eq_some found
                  cases deallocated
                  simpa [released, owned] using
                    replaceOwnedBlock_preserves_i32_array_view_blocks
                      (views := views) (original := block)
                      (replacement := released) wellFormed blockMember owned rfl
                      (refundBudget heap.remaining block.size)

theorem allocate_preserves_i32_array_view_blocks
    (allocated : heap.allocate size alignment = .allocated pointer afterHeap) :
    I32ArrayViewBlocksPreserved views heap afterHeap := by
  by_cases alignmentValid : validAlignment alignment = true
  · cases budget : consumeBudget heap.remaining size with
    | none => simp [Heap.allocate, alignmentValid, budget] at allocated
    | some remaining =>
        let base := alignUp (max heap.nextAddress 1) alignment
        let block : Block := {
          base
          size
          alignment
          bytes := List.replicate size 0
        }
        let allocatedHeap : Heap := {
          heap with
          blocks := heap.blocks ++ [block]
          nextAddress := base + max size 1
          remaining
        }
        have shape : heap.allocate size alignment =
            .allocated base allocatedHeap := by
          simp [Heap.allocate, alignmentValid, budget, allocatedHeap, block,
            base]
        rw [shape] at allocated
        have pointerEq : base = pointer := by injection allocated
        have heapEq : allocatedHeap = afterHeap := by injection allocated
        subst pointer
        subst afterHeap
        simpa only [allocatedHeap, I32ArrayViewBlocksPreserved,
          I32ArrayViewBlockWellFormed, Heap.block?] using
          appendBlock_preserves_i32_array_view_blocks views heap block
  · simp [Heap.allocate, alignmentValid] at allocated

theorem allocate_success_block_owned
    (wellFormed : HeapWellFormed heap)
    (allocated : heap.allocate size alignment = .allocated pointer afterHeap)
    (found : afterHeap.block? pointer = some block) :
    block.owned = true := by
  by_cases alignmentValid : validAlignment alignment = true
  · cases budget : consumeBudget heap.remaining size with
    | none => simp [Heap.allocate, alignmentValid, budget] at allocated
    | some remaining =>
        let base := alignUp (max heap.nextAddress 1) alignment
        let fresh : Block := {
          base
          size
          alignment
          bytes := List.replicate size 0
        }
        let allocatedHeap : Heap := {
          heap with
          blocks := heap.blocks ++ [fresh]
          nextAddress := base + max size 1
          remaining
        }
        have shape : heap.allocate size alignment =
            .allocated base allocatedHeap := by
          simp [Heap.allocate, alignmentValid, budget, allocatedHeap, fresh,
            base]
        rw [shape] at allocated
        have pointerEq : base = pointer := by injection allocated
        have heapEq : allocatedHeap = afterHeap := by injection allocated
        subst pointer
        subst afterHeap
        have allocatedWellFormed : HeapWellFormed allocatedHeap := by
          simpa only [AllocationResultWellFormed, shape] using
            allocate_preserves_heap_well_formed wellFormed
              (size := size) (alignment := alignment)
        have blockMember : block ∈ allocatedHeap.blocks :=
          List.mem_of_find?_eq_some found
        have freshMember : fresh ∈ allocatedHeap.blocks := by
          simp [allocatedHeap]
        have foundList : allocatedHeap.blocks.find?
            (fun candidate => candidate.base == base) = some block := by
          simpa only [Heap.block?] using found
        have blockBase : block.base = base := by
          exact beq_iff_eq.mp (List.find?_some
            (p := fun candidate : Block => candidate.base == base) foundList)
        have same := allocatedWellFormed.blockBasesUnique block blockMember
          fresh freshMember (by simpa only [fresh] using blockBase)
        subst block
        rfl
  · simp [Heap.allocate, alignmentValid] at allocated

theorem reallocate_preserves_i32_array_view_blocks
    (wellFormed : HeapWellFormed heap)
    (reallocated : heap.reallocate pointer oldSize newSize alignment =
      .allocated replacement afterHeap) :
    I32ArrayViewBlocksPreserved views heap afterHeap := by
  by_cases nullPointer : pointer = null
  · subst pointer
    simp only [Heap.reallocate, BEq.rfl, ↓reduceIte] at reallocated
    exact allocate_preserves_i32_array_view_blocks reallocated
  · have notNull : (pointer == null) = false := by simpa using nullPointer
    simp only [Heap.reallocate, notNull, Bool.false_eq_true, ↓reduceIte] at reallocated
    by_cases zeroSize : newSize = 0
    · have isZero : (newSize == 0) = true := by simpa using zeroSize
      simp only [isZero, ↓reduceIte] at reallocated
      cases released : heap.deallocate pointer oldSize alignment with
      | error reason => simp [released] at reallocated
      | ok releasedHeap =>
          simp only [released, AllocationResult.allocated.injEq] at reallocated
          obtain ⟨replacementEq, heapEq⟩ := reallocated
          subst replacement
          subst afterHeap
          exact deallocate_preserves_i32_array_view_blocks wellFormed released
    · have notZero : (newSize == 0) = false := by simpa using zeroSize
      simp only [notZero, Bool.false_eq_true, ↓reduceIte] at reallocated
      cases found : heap.block? pointer with
      | none => simp [found] at reallocated
      | some oldBlock =>
          simp only [found] at reallocated
          split at reallocated
          · contradiction
          · split at reallocated
            · contradiction
            · split at reallocated
              · contradiction
              · cases released : heap.deallocate pointer oldSize alignment with
                | error reason => simp [released] at reallocated
                | ok credited =>
                    have creditedWellFormed :=
                      deallocate_preserves_heap_well_formed wellFormed released
                    have releasedViews :=
                      deallocate_preserves_i32_array_view_blocks
                        (views := views) wellFormed released
                    simp only [released] at reallocated
                    cases allocatedResult : credited.allocate newSize alignment with
                    | exhausted exhausted => simp [allocatedResult] at reallocated
                    | trapped reason trapped => simp [allocatedResult] at reallocated
                    | allocated newPointer allocated =>
                        have allocatedWellFormed : HeapWellFormed allocated := by
                          have preserved := allocate_preserves_heap_well_formed
                            creditedWellFormed (size := newSize)
                              (alignment := alignment)
                          rw [allocatedResult] at preserved
                          exact preserved
                        have allocatedViews :=
                          allocate_preserves_i32_array_view_blocks
                            (views := views) allocatedResult
                        simp only [allocatedResult] at reallocated
                        cases replacementFound : allocated.block? newPointer with
                        | none => simp [replacementFound] at reallocated
                        | some newBlock =>
                            simp only [replacementFound] at reallocated
                            let copied : Block := {
                              newBlock with
                              bytes := resizeBytes oldBlock.bytes newSize
                            }
                            have newBlockMember : newBlock ∈ allocated.blocks :=
                              List.mem_of_find?_eq_some replacementFound
                            have newBlockOwned : newBlock.owned = true :=
                              allocate_success_block_owned creditedWellFormed
                                allocatedResult replacementFound
                            have copiedViews :=
                              replaceOwnedBlock_preserves_i32_array_view_blocks
                                (views := views) (original := newBlock)
                                (replacement := copied) allocatedWellFormed
                                newBlockMember newBlockOwned rfl allocated.remaining
                            cases reallocated
                            exact releasedViews.trans
                              (allocatedViews.trans (by
                                simpa [copied, newBlockOwned] using copiedViews))

theorem allocate_exhausted_heap_eq
    (heap afterHeap : Heap) (size alignment : Nat)
    (exhausted : heap.allocate size alignment = .exhausted afterHeap) :
    afterHeap = heap := by
  by_cases alignmentValid : validAlignment alignment = true
  · cases budget : consumeBudget heap.remaining size with
    | none =>
        simp [Heap.allocate, alignmentValid, budget] at exhausted
        exact exhausted.symm
    | some remaining => simp [Heap.allocate, alignmentValid, budget] at exhausted
  · simp [Heap.allocate, alignmentValid] at exhausted

theorem allocate_trapped_heap_eq
    (heap afterHeap : Heap) (size alignment : Nat) (reason : Trap)
    (trapped : heap.allocate size alignment = .trapped reason afterHeap) :
    afterHeap = heap := by
  by_cases alignmentValid : validAlignment alignment = true
  · cases budget : consumeBudget heap.remaining size with
    | none => simp [Heap.allocate, alignmentValid, budget] at trapped
    | some remaining => simp [Heap.allocate, alignmentValid, budget] at trapped
  · simp [Heap.allocate, alignmentValid] at trapped
    exact trapped.2.symm

theorem reallocate_exhausted_heap_eq
    (heap afterHeap : Heap) (pointer oldSize newSize alignment : Nat)
    (exhausted : heap.reallocate pointer oldSize newSize alignment =
      .exhausted afterHeap) :
    afterHeap = heap := by
  by_cases nullPointer : pointer = null
  · subst pointer
    simp only [Heap.reallocate, BEq.rfl, ↓reduceIte] at exhausted
    exact allocate_exhausted_heap_eq heap afterHeap newSize alignment exhausted
  · have notNull : (pointer == null) = false := by simpa using nullPointer
    simp only [Heap.reallocate, notNull, Bool.false_eq_true, ↓reduceIte] at exhausted
    by_cases zeroSize : newSize = 0
    · have isZero : (newSize == 0) = true := by simpa using zeroSize
      simp only [isZero, ↓reduceIte] at exhausted
      cases released : heap.deallocate pointer oldSize alignment <;>
        simp [released] at exhausted
    · have notZero : (newSize == 0) = false := by simpa using zeroSize
      simp only [notZero, Bool.false_eq_true, ↓reduceIte] at exhausted
      cases found : heap.block? pointer with
      | none => simp [found] at exhausted
      | some oldBlock =>
          simp only [found] at exhausted
          split at exhausted
          · contradiction
          · split at exhausted
            · contradiction
            · split at exhausted
              · contradiction
              · cases released : heap.deallocate pointer oldSize alignment with
                | error reason => simp [released] at exhausted
                | ok credited =>
                    simp only [released] at exhausted
                    cases allocated : credited.allocate newSize alignment with
                    | exhausted exhaustedHeap =>
                        simp [allocated] at exhausted
                        exact exhausted.symm
                    | trapped reason trappedHeap => simp [allocated] at exhausted
                    | allocated replacement allocatedHeap =>
                        simp only [allocated] at exhausted
                        cases replacementFound : allocatedHeap.block? replacement <;>
                          simp [replacementFound] at exhausted

theorem reallocate_trapped_heap_eq
    (heap afterHeap : Heap) (pointer oldSize newSize alignment : Nat)
    (reason : Trap)
    (trapped : heap.reallocate pointer oldSize newSize alignment =
      .trapped reason afterHeap) :
    afterHeap = heap := by
  by_cases nullPointer : pointer = null
  · subst pointer
    simp only [Heap.reallocate, BEq.rfl, ↓reduceIte] at trapped
    exact allocate_trapped_heap_eq heap afterHeap newSize alignment reason trapped
  · have notNull : (pointer == null) = false := by simpa using nullPointer
    simp only [Heap.reallocate, notNull, Bool.false_eq_true, ↓reduceIte] at trapped
    by_cases zeroSize : newSize = 0
    · have isZero : (newSize == 0) = true := by simpa using zeroSize
      simp only [isZero, ↓reduceIte] at trapped
      cases released : heap.deallocate pointer oldSize alignment with
      | error releaseReason =>
          simp [released] at trapped
          exact trapped.2.symm
      | ok releasedHeap => simp [released] at trapped
    · have notZero : (newSize == 0) = false := by simpa using zeroSize
      simp only [notZero, Bool.false_eq_true, ↓reduceIte] at trapped
      cases found : heap.block? pointer with
      | none =>
          simp [found] at trapped
          exact trapped.2.symm
      | some oldBlock =>
          simp only [found] at trapped
          split at trapped
          · injection trapped with reasonEq heapEq
            exact heapEq.symm
          · split at trapped
            · injection trapped with reasonEq heapEq
              exact heapEq.symm
            · split at trapped
              · injection trapped with reasonEq heapEq
                exact heapEq.symm
              · cases released : heap.deallocate pointer oldSize alignment with
                | error releaseReason =>
                    simp [released] at trapped
                    exact trapped.2.symm
                | ok credited =>
                    simp only [released] at trapped
                    cases allocated : credited.allocate newSize alignment with
                    | exhausted exhaustedHeap => simp [allocated] at trapped
                    | trapped allocationReason trappedHeap =>
                        simp [allocated] at trapped
                        exact trapped.2.symm
                    | allocated replacement allocatedHeap =>
                        simp only [allocated] at trapped
                        cases replacementFound : allocatedHeap.block? replacement with
                        | none =>
                            simp [replacementFound] at trapped
                            exact trapped.2.symm
                        | some newBlock => simp [replacementFound] at trapped

/-- The dynamic invariant used at raw-memory and host-call boundaries. The
    ordinary `StateHasType` component remains reusable for language-only
    evaluation; registered borrowed views are never left implicit. -/
structure RuntimeStateHasType
    (program : Program) (context : Context)
    (state : State) (store : StoreTyping) : Prop where
  typed : StateHasType program context state store
  views : I32ArrayViewsWellFormed program state store

def RuntimeValueOutcomeHasType
    (program : Program) (context : Context) (store : StoreTyping)
    (outcome : Outcome Value) (type : Ty) : Prop :=
  match outcome with
  | .done value state =>
      RuntimeStateHasType program context state store ∧
        ValueHasType program value type ∧
        BorrowsValid program state store value
  | .trapped _ state | .exited _ state =>
      RuntimeStateHasType program context state store
  | .outOfFuel => True

theorem StateHasType.withWorld
    (typed : StateHasType program context state store)
    (world : World.State) :
    StateHasType program context { state with world := world } store := by
  constructor
  · exact ⟨typed.wellFormed.heapWellFormed,
      typed.wellFormed.cellIdsUnique,
      typed.wellFormed.cellIdsBelowNext,
      typed.wellFormed.localsReferenceCells⟩
  · exact typed.storeDomain
  · intro entry member
    obtain ⟨type, stored, contents⟩ := typed.storeMatches entry member
    refine ⟨type, stored, ?_⟩
    cases initialized : entry.value with
    | none => trivial
    | some value =>
        have initializedContents :
            ValueHasType program value type ∧
              BorrowsValid program state store value := by
          simpa [initialized] using contents
        simp only
        exact ⟨initializedContents.1,
          initializedContents.2.withWorld world⟩
  · exact typed.localsMatch

theorem StateHasType.withI32ArrayViews
    (typed : StateHasType program context state store)
    (views : List I32ArrayView) :
    StateHasType program context { state with i32ArrayViews := views } store := by
  constructor
  · exact ⟨typed.wellFormed.heapWellFormed,
      typed.wellFormed.cellIdsUnique,
      typed.wellFormed.cellIdsBelowNext,
      typed.wellFormed.localsReferenceCells⟩
  · exact typed.storeDomain
  · intro entry member
    obtain ⟨type, stored, contents⟩ := typed.storeMatches entry member
    refine ⟨type, stored, ?_⟩
    cases initialized : entry.value with
    | none => trivial
    | some value =>
        have initializedContents :
            ValueHasType program value type ∧
              BorrowsValid program state store value := by
          simpa [initialized] using contents
        simp only
        exact ⟨initializedContents.1,
          initializedContents.2.withI32ArrayViews views⟩
  · exact typed.localsMatch

theorem StateHasType.withHeap
    (typed : StateHasType program context state store)
    (heap : Heap) (heapWellFormed : HeapWellFormed heap) :
    StateHasType program context { state with heap := heap } store := by
  constructor
  · exact ⟨heapWellFormed, typed.wellFormed.cellIdsUnique,
      typed.wellFormed.cellIdsBelowNext,
      typed.wellFormed.localsReferenceCells⟩
  · exact typed.storeDomain
  · intro entry member
    obtain ⟨type, stored, contents⟩ := typed.storeMatches entry member
    refine ⟨type, stored, ?_⟩
    cases initialized : entry.value with
    | none => trivial
    | some value =>
        have initializedContents :
            ValueHasType program value type ∧
              BorrowsValid program state store value := by
          simpa [initialized] using contents
        simp only
        exact ⟨initializedContents.1,
          initializedContents.2.withHeap heap⟩
  · exact typed.localsMatch

theorem StateHasType.restoreLocals
    (callerTyped : StateHasType program context caller callerStore)
    (completedTyped : StateHasType program completedContext completed completedStore)
    (storePreserved : StoreExtends callerStore completedStore) :
    StateHasType program context (restoreLocals caller completed)
      completedStore := by
  constructor
  · constructor
    · exact completedTyped.wellFormed.heapWellFormed
    · exact completedTyped.wellFormed.cellIdsUnique
    · exact completedTyped.wellFormed.cellIdsBelowNext
    · intro binding member
      obtain ⟨oldEntry, oldMember, oldId⟩ :=
        callerTyped.wellFormed.localsReferenceCells binding member
      obtain ⟨type, oldStored, contents⟩ :=
        callerTyped.storeMatches oldEntry oldMember
      have completedStored := storePreserved oldEntry.id type oldStored
      have completedDomain := completedTyped.storeDomain oldEntry.id
      rw [completedStored] at completedDomain
      cases completedFound : completed.cellEntry? oldEntry.id with
      | none => simp [completedFound] at completedDomain
      | some completedEntry =>
          have completedMember : completedEntry ∈ completed.cells :=
            List.mem_of_find?_eq_some completedFound
          have completedId : completedEntry.id = oldEntry.id := by
            simpa using List.find?_some completedFound
          exact ⟨completedEntry, completedMember, completedId.trans oldId⟩
  · exact completedTyped.storeDomain
  · intro entry member
    obtain ⟨type, stored, contents⟩ := completedTyped.storeMatches entry member
    refine ⟨type, stored, ?_⟩
    cases initialized : entry.value with
    | none => trivial
    | some value =>
        have initializedContents :
            ValueHasType program value type ∧
              BorrowsValid program completed completedStore value := by
          simpa [initialized] using contents
        simp only
        exact ⟨initializedContents.1,
          initializedContents.2.withLocals caller.locals⟩
  · intro id
    change match context id, caller.cellId? id with
      | some type, some cell => completedStore cell = some type
      | none, none => True
      | _, _ => False
    have callerLocal := callerTyped.localsMatch id
    cases contextFound : context id with
    | none =>
        cases localFound : caller.cellId? id <;>
          simp [contextFound, localFound] at callerLocal ⊢
    | some type =>
        cases localFound : caller.cellId? id with
        | none => simp [contextFound, localFound] at callerLocal
        | some cell =>
            simp [contextFound, localFound] at callerLocal ⊢
            exact storePreserved cell type callerLocal

theorem StateHasType.clearLocals
    (typed : StateHasType program context state store) :
    StateHasType program Context.empty { state with locals := [] } store := by
  constructor
  · exact ⟨typed.wellFormed.heapWellFormed,
      typed.wellFormed.cellIdsUnique,
      typed.wellFormed.cellIdsBelowNext, by simp [LocalsReferenceCells]⟩
  · exact typed.storeDomain
  · intro entry member
    obtain ⟨type, stored, contents⟩ := typed.storeMatches entry member
    refine ⟨type, stored, ?_⟩
    cases initialized : entry.value with
    | none => trivial
    | some value =>
        have initializedContents :
            ValueHasType program value type ∧
              BorrowsValid program state store value := by
          simpa [initialized] using contents
        simp only
        exact ⟨initializedContents.1,
          initializedContents.2.withLocals []⟩
  · intro id
    simp [Context.empty, State.cellId?]

theorem StateHasType.local_cell
    {id : VarId} {type : Ty}
    (typed : StateHasType program context state store)
    (found : context id = some type) :
    ∃ cell, state.cellId? id = some cell ∧ store cell = some type := by
  have matched := typed.localsMatch id
  cases localFound : state.cellId? id with
  | none => simp [found, localFound] at matched
  | some cell =>
      refine ⟨cell, rfl, ?_⟩
      simpa [found, localFound] using matched

theorem StateHasType.initialized_cell
    {cell : CellId} {type : Ty} {entry : Cell} {value : Value}
    (typed : StateHasType program context state store)
    (stored : store cell = some type)
    (found : state.cellEntry? cell = some entry)
    (initialized : entry.value = some value) :
    ValueHasType program value type ∧ BorrowsValid program state store value := by
  have member : entry ∈ state.cells := List.mem_of_find?_eq_some found
  obtain ⟨entryType, entryStored, contents⟩ :=
    typed.storeMatches entry member
  have entryId : entry.id = cell := by
    simpa using List.find?_some found
  rw [entryId] at entryStored
  have sameType : entryType = type :=
    Option.some.inj (entryStored.symm.trans stored)
  subst entryType
  rw [initialized] at contents
  exact contents

theorem StateHasType.typed_cell_exists
    {cell : CellId} {type : Ty}
    (typed : StateHasType program context state store)
    (stored : store cell = some type) :
    ∃ entry, state.cellEntry? cell = some entry := by
  have domain := typed.storeDomain cell
  rw [stored] at domain
  cases found : state.cellEntry? cell with
  | none => simp [found] at domain
  | some entry => exact ⟨entry, rfl⟩

theorem StateHasType.nextCell_store_none
    (typed : StateHasType program context state store) :
    store state.nextCell = none := by
  have domain := typed.storeDomain state.nextCell
  rw [nextCell_is_not_allocated state typed.wellFormed] at domain
  cases found : store state.nextCell with
  | none => rfl
  | some type => simp [found] at domain

theorem BorrowValid.assignCell
    (assigned : state.assignCell cell replacement = some next)
    (stored : store cell = some cellType)
    (replacementTyped : ValueHasType program replacement cellType)
    (valid : BorrowValid program state store descriptor) :
    BorrowValid program next store descriptor := by
  cases valid with
  | reference descriptorStored cellFound initialized rootTyped projected =>
      rename_i borrowedCell rootType entry rootValue projections referent
      by_cases same : borrowedCell = cell
      · subst borrowedCell
        have sameType : rootType = cellType :=
          Option.some.inj (descriptorStored.symm.trans stored)
        subst rootType
        exact .reference stored (assignCell_finds_assigned assigned) rfl
          replacementTyped projected
      · exact .reference descriptorStored
          ((assignCell_preserves_other assigned same).trans cellFound)
          initialized rootTyped projected
  | slice descriptorStored cellFound initialized rootTyped projected inBounds =>
      rename_i borrowedCell rootType entry rootValue projections elementType
        arrayLength start length
      by_cases same : borrowedCell = cell
      · subst borrowedCell
        have sameType : rootType = cellType :=
          Option.some.inj (descriptorStored.symm.trans stored)
        subst rootType
        exact .slice stored (assignCell_finds_assigned assigned) rfl
          replacementTyped projected inBounds
      · exact .slice descriptorStored
          ((assignCell_preserves_other assigned same).trans cellFound)
          initialized rootTyped projected inBounds

theorem BorrowsValid.assignCell
    (assigned : state.assignCell cell replacement = some next)
    (stored : store cell = some cellType)
    (replacementTyped : ValueHasType program replacement cellType)
    (valid : BorrowsValid program state store value) :
    BorrowsValid program next store value := by
  intro descriptor member
  exact (valid descriptor member).assignCell assigned stored replacementTyped

theorem StoreMatches.assignCell
    (typed : StateHasType program context state store)
    (assigned : state.assignCell cell replacement = some next)
    (stored : store cell = some cellType)
    (replacementTyped : ValueHasType program replacement cellType)
    (replacementBorrows : BorrowsValid program state store replacement) :
    StoreMatches program next store := by
  intro entry member
  rw [assignCell_state assigned] at member
  rw [replaceCell_eq_map] at member
  obtain ⟨oldEntry, oldMember, entryEq⟩ := List.mem_map.1 member
  subst entry
  by_cases same : oldEntry.id = cell
  · subst cell
    simp
    refine ⟨cellType, stored, replacementTyped, ?_⟩
    exact replacementBorrows.assignCell assigned stored replacementTyped
  · simp [same]
    obtain ⟨oldType, oldStored, oldContents⟩ :=
      typed.storeMatches oldEntry oldMember
    refine ⟨oldType, oldStored, ?_⟩
    cases found : oldEntry.value with
    | none => trivial
    | some oldValue =>
        rw [found] at oldContents
        exact ⟨oldContents.1,
          oldContents.2.assignCell assigned stored replacementTyped⟩

theorem StoreDomainMatches.assignCell
    (typed : StateHasType program context state store)
    (assigned : state.assignCell cell replacement = some next)
    (stored : store cell = some cellType) :
    StoreDomainMatches next store := by
  intro queried
  by_cases same : queried = cell
  · subst queried
    rw [stored, assignCell_finds_assigned assigned]
    rfl
  · rw [assignCell_preserves_other assigned same]
    exact typed.storeDomain queried

theorem LocalsMatch.assignCell
    (typed : StateHasType program context state store)
    (assigned : state.assignCell cell replacement = some next) :
    LocalsMatch context next store := by
  rw [assignCell_state assigned]
  exact typed.localsMatch

theorem StateHasType.assignCell
    (typed : StateHasType program context state store)
    (assigned : state.assignCell cell replacement = some next)
    (stored : store cell = some cellType)
    (replacementTyped : ValueHasType program replacement cellType)
    (replacementBorrows : BorrowsValid program state store replacement) :
    StateHasType program context next store := by
  constructor
  · exact assignCell_preserves_well_formed typed.wellFormed assigned
  · exact StoreDomainMatches.assignCell typed assigned stored
  · exact StoreMatches.assignCell typed assigned stored replacementTyped
      replacementBorrows
  · exact LocalsMatch.assignCell typed assigned

theorem BorrowValid.bindCell
    (typed : StateHasType program context state store)
    (id : VarId) (contents : Option Value) (freshType : Ty)
    (valid : BorrowValid program state store descriptor) :
    BorrowValid program (state.bindCell id contents)
      (store.extend state.nextCell freshType) descriptor := by
  cases valid with
  | reference stored found initialized rootTyped projected =>
      have old := found_cell_is_below_next state _ _ typed.wellFormed found
      exact .reference
        (by
          rw [StoreTyping.extend_other _ _ _ _ (Nat.ne_of_lt old)]
          exact stored)
        ((bindCell_preserves_old_cell state id contents _ old).trans found)
        initialized rootTyped projected
  | slice stored found initialized rootTyped projected inBounds =>
      have old := found_cell_is_below_next state _ _ typed.wellFormed found
      exact .slice
        (by
          rw [StoreTyping.extend_other _ _ _ _ (Nat.ne_of_lt old)]
          exact stored)
        ((bindCell_preserves_old_cell state id contents _ old).trans found)
        initialized rootTyped projected inBounds

theorem BorrowsValid.bindCell
    (typed : StateHasType program context state store)
    (id : VarId) (contents : Option Value) (freshType : Ty)
    (valid : BorrowsValid program state store value) :
    BorrowsValid program (state.bindCell id contents)
      (store.extend state.nextCell freshType) value := by
  intro descriptor member
  exact (valid descriptor member).bindCell typed id contents freshType

theorem BorrowValid.allocateTemporary
    (typed : StateHasType program context state store)
    (temporary : Value) (temporaryType : Ty)
    (valid : BorrowValid program state store descriptor) :
    BorrowValid program (state.allocateTemporary temporary).2
      (store.extend state.nextCell temporaryType) descriptor := by
  cases valid with
  | reference storedType cellFound initialized rootTyped projected =>
      have old := found_cell_is_below_next state _ _ typed.wellFormed cellFound
      apply BorrowValid.reference
      · rw [StoreTyping.extend_other _ _ _ _ (Nat.ne_of_lt old)]
        exact storedType
      · rw [allocateTemporary_preserves_old_cell state temporary _ old]
        exact cellFound
      · exact initialized
      · exact rootTyped
      · exact projected
  | slice storedType cellFound initialized rootTyped projected inBounds =>
      have old := found_cell_is_below_next state _ _ typed.wellFormed cellFound
      apply BorrowValid.slice
      · rw [StoreTyping.extend_other _ _ _ _ (Nat.ne_of_lt old)]
        exact storedType
      · rw [allocateTemporary_preserves_old_cell state temporary _ old]
        exact cellFound
      · exact initialized
      · exact rootTyped
      · exact projected
      · exact inBounds

theorem BorrowsValid.allocateTemporary
    (typed : StateHasType program context state store)
    (temporary : Value) (temporaryType : Ty)
    (valid : BorrowsValid program state store value) :
    BorrowsValid program (state.allocateTemporary temporary).2
      (store.extend state.nextCell temporaryType) value := by
  intro descriptor member
  exact (valid descriptor member).allocateTemporary typed temporary temporaryType

theorem StoreMatches.allocateTemporary
    (typed : StateHasType program context state store)
    (valueTyped : ValueHasType program value type)
    (borrows : BorrowsValid program state store value) :
    StoreMatches program (state.allocateTemporary value).2
      (store.extend state.nextCell type) := by
  intro entry member
  simp only [State.allocateTemporary] at member
  simp only [List.mem_append, List.mem_singleton] at member
  rcases member with oldMember | fresh
  · obtain ⟨entryType, stored, contents⟩ :=
      typed.storeMatches entry oldMember
    have old := typed.wellFormed.cellIdsBelowNext entry oldMember
    refine ⟨entryType, ?_, ?_⟩
    · rw [StoreTyping.extend_other _ _ _ _ (Nat.ne_of_lt old)]
      exact stored
    · cases found : entry.value with
      | none => trivial
      | some oldValue =>
          rw [found] at contents
          simp only at contents ⊢
          exact ⟨contents.1,
            contents.2.allocateTemporary typed value type⟩
  · subst entry
    refine ⟨type, StoreTyping.extend_same store state.nextCell type, ?_⟩
    exact ⟨valueTyped, borrows.allocateTemporary typed value type⟩

theorem StoreDomainMatches.allocateTemporary
    (typed : StateHasType program context state store)
    (value : Value) (type : Ty) :
    StoreDomainMatches (state.allocateTemporary value).2
      (store.extend state.nextCell type) := by
  intro cell
  by_cases same : cell = state.nextCell
  · subst cell
    have found : (state.allocateTemporary value).2.cellEntry? state.nextCell =
        some { id := state.nextCell, value := some value } := by
      rw [← allocateTemporary_returns_fresh_cell state value]
      exact allocateTemporary_finds_fresh_cell state value typed.wellFormed
    rw [found]
    simp [StoreTyping.extend]
  · rw [StoreTyping.extend_other store state.nextCell cell type same]
    rw [allocateTemporary_preserves_other_cell state value cell same]
    exact typed.storeDomain cell

theorem LocalsMatch.allocateTemporary
    (typed : StateHasType program context state store)
    (value : Value) (type : Ty) :
    LocalsMatch context (state.allocateTemporary value).2
      (store.extend state.nextCell type) := by
  intro id
  have old := typed.localsMatch id
  change match context id, state.cellId? id with
    | some localType, some cell =>
        (store.extend state.nextCell type) cell = some localType
    | none, none => True
    | _, _ => False
  cases contextFound : context id with
  | none =>
      cases localFound : state.cellId? id <;>
        simp [contextFound, localFound] at old ⊢
  | some localType =>
      cases localFound : state.cellId? id with
      | none => simp [contextFound, localFound] at old
      | some cell =>
          simp [contextFound, localFound] at old ⊢
          have different : cell ≠ state.nextCell := by
            intro same
            subst cell
            rw [typed.nextCell_store_none] at old
            cases old
          rw [StoreTyping.extend_other store state.nextCell cell type different]
          exact old

theorem LocalsMatch.bindCell
    (typed : StateHasType program context state store)
    (id : VarId) (contents : Option Value) (type : Ty) :
    LocalsMatch (context.bind id type) (state.bindCell id contents)
      (store.extend state.nextCell type) := by
  intro queried
  by_cases same : queried = id
  · subst queried
    simp [Context.bind, State.bindCell, State.cellId?, StoreTyping.extend]
  · have old := LocalsMatch.allocateTemporary typed .unit type queried
    simpa [Context.bind, State.bindCell, State.allocateTemporary,
      State.cellId?, same, Ne.symm same] using old

theorem StateHasType.allocateTemporary
    (typed : StateHasType program context state store)
    (valueTyped : ValueHasType program value type)
    (borrows : BorrowsValid program state store value) :
    StateHasType program context (state.allocateTemporary value).2
      (store.extend state.nextCell type) := by
  constructor
  · exact allocateTemporary_preserves_well_formed state value typed.wellFormed
  · exact StoreDomainMatches.allocateTemporary typed value type
  · exact StoreMatches.allocateTemporary typed valueTyped borrows
  · exact LocalsMatch.allocateTemporary typed value type

theorem StateHasType.bindLocal
    (id : VarId)
    (typed : StateHasType program context state store)
    (valueTyped : ValueHasType program value type)
    (borrows : BorrowsValid program state store value) :
    StateHasType program (context.bind id type) (state.bindLocal id value)
      (store.extend state.nextCell type) := by
  constructor
  · exact bindLocal_preserves_well_formed state id value typed.wellFormed
  · change StoreDomainMatches (state.allocateTemporary value).2
      (store.extend state.nextCell type)
    exact StoreDomainMatches.allocateTemporary typed value type
  · have allocated := StoreMatches.allocateTemporary typed valueTyped borrows
    intro entry member
    have allocatedMember : entry ∈ (state.allocateTemporary value).2.cells :=
      member
    obtain ⟨entryType, stored, contents⟩ := allocated entry allocatedMember
    refine ⟨entryType, stored, ?_⟩
    cases initialized : entry.value with
    | none => trivial
    | some entryValue =>
        have initializedContents :
            ValueHasType program entryValue entryType ∧
              BorrowsValid program (state.allocateTemporary value).2
                (store.extend state.nextCell type) entryValue := by
          simpa [initialized] using contents
        simp only
        refine ⟨initializedContents.1, ?_⟩
        change BorrowsValid program
          { (state.allocateTemporary value).2 with
            locals := (id, state.nextCell) :: state.locals }
          (store.extend state.nextCell type) entryValue
        exact initializedContents.2.withLocals _
  · intro queried
    by_cases same : queried = id
    · subst queried
      simp [Context.bind, State.bindLocal, State.bindCell, State.cellId?,
        StoreTyping.extend]
    · have old := LocalsMatch.allocateTemporary typed value type queried
      simpa [Context.bind, State.bindLocal, State.bindCell,
        State.allocateTemporary, State.cellId?, same, Ne.symm same] using old

theorem StateHasType.bindUninitialized
    (id : VarId) (type : Ty)
    (typed : StateHasType program context state store) :
    StateHasType program (context.bind id type)
      (state.bindUninitialized id) (store.extend state.nextCell type) := by
  constructor
  · exact bindUninitialized_preserves_well_formed state id typed.wellFormed
  · simp only [State.bindUninitialized]
    intro cell
    by_cases same : cell = state.nextCell
    · subst cell
      rw [bindCell_finds_fresh_cell state id none typed.wellFormed]
      simp [StoreTyping.extend]
    · rw [StoreTyping.extend_other store state.nextCell cell type same]
      rw [bindCell_preserves_other_cell state id none cell same]
      exact typed.storeDomain cell
  · intro entry member
    simp only [State.bindUninitialized, State.bindCell] at member
    simp only [List.mem_append, List.mem_singleton] at member
    rcases member with oldMember | fresh
    · obtain ⟨entryType, stored, contents⟩ :=
        typed.storeMatches entry oldMember
      have old := typed.wellFormed.cellIdsBelowNext entry oldMember
      refine ⟨entryType, ?_, ?_⟩
      · rw [StoreTyping.extend_other _ _ _ _ (Nat.ne_of_lt old)]
        exact stored
      · cases initialized : entry.value with
        | none => trivial
        | some value =>
            have initializedContents :
                ValueHasType program value entryType ∧
                  BorrowsValid program state store value := by
              simpa [initialized] using contents
            simp only
            exact ⟨initializedContents.1,
              initializedContents.2.bindCell typed id none type⟩
    · subst entry
      exact ⟨type, StoreTyping.extend_same store state.nextCell type,
        trivial⟩
  · simpa [State.bindUninitialized] using
      LocalsMatch.bindCell typed id none type

theorem BorrowsValid.bindLocal
    (valid : BorrowsValid program state store borrowedValue)
    (typed : StateHasType program context state store)
    (id : VarId) (boundValue : Value) (boundType : Ty) :
    BorrowsValid program (state.bindLocal id boundValue)
      (store.extend state.nextCell boundType) borrowedValue := by
  change BorrowsValid program
    { (state.allocateTemporary boundValue).2 with
      locals := (id, state.nextCell) :: state.locals }
    (store.extend state.nextCell boundType) borrowedValue
  exact (valid.allocateTemporary typed boundValue boundType).withLocals _

theorem BindingsBorrowsValid.head
    {id : VarId}
    (valid : BindingsBorrowsValid program state store
      ((id, value) :: bindings)) :
    BorrowsValid program state store value := by
  exact valid (id, value) (by simp)

theorem BindingsBorrowsValid.tail
    {id : VarId}
    (valid : BindingsBorrowsValid program state store
      ((id, value) :: bindings)) :
    BindingsBorrowsValid program state store bindings := by
  intro binding member
  exact valid binding (List.mem_cons_of_mem _ member)

theorem BindingsBorrowsValid.bindLocal
    (valid : BindingsBorrowsValid program state store bindings)
    (typed : StateHasType program context state store)
    (id : VarId) (boundValue : Value) (boundType : Ty) :
    BindingsBorrowsValid program (state.bindLocal id boundValue)
      (store.extend state.nextCell boundType) bindings := by
  intro binding member
  exact (valid binding member).bindLocal typed id boundValue boundType

theorem BindingsBorrowsValid.withLocals
    (valid : BindingsBorrowsValid program state store bindings)
    (locals : List (VarId × CellId)) :
    BindingsBorrowsValid program { state with locals := locals } store bindings := by
  intro binding member
  exact (valid binding member).withLocals locals

theorem StateHasType.allocateTemporary_extends
    (typed : StateHasType program context state store)
    (valueTyped : ValueHasType program value type)
    (borrows : BorrowsValid program state store value) :
    ∃ nextStore,
      StoreExtends store nextStore ∧
      StateHasType program context (state.allocateTemporary value).2 nextStore := by
  refine ⟨store.extend state.nextCell type, ?_, ?_⟩
  · exact StoreTyping.extends_extend store state.nextCell type
      typed.nextCell_store_none
  · exact typed.allocateTemporary valueTyped borrows

theorem temporaryArraySlice_borrow_valid
    (typed : StateHasType program context state store)
    (arrayTyped : ValueHasType program (.array elements)
      (.array elementType length)) :
    BorrowValid program (state.allocateTemporary (.array elements)).2
      (store.extend state.nextCell (.array elementType length))
      (.slice elementType state.nextCell [] 0 length) := by
  apply BorrowValid.slice
      (rootType := .array elementType length)
      (entry := { id := state.nextCell, value := some (.array elements) })
      (rootValue := .array elements)
      (arrayLength := length)
  · exact StoreTyping.extend_same store state.nextCell
      (.array elementType length)
  · rw [← allocateTemporary_returns_fresh_cell state (.array elements)]
    exact allocateTemporary_finds_fresh_cell state (.array elements)
      typed.wellFormed
  · rfl
  · exact arrayTyped
  · exact .nil
  · simp

theorem temporaryArraySlice_borrows_valid
    (typed : StateHasType program context state store)
    (arrayTyped : ValueHasType program (.array elements)
      (.array elementType length)) :
    BorrowsValid program (state.allocateTemporary (.array elements)).2
      (store.extend state.nextCell (.array elementType length))
      (.slice elementType state.nextCell [] 0 length) := by
  intro descriptor member
  simp [valueBorrows] at member
  subst descriptor
  exact temporaryArraySlice_borrow_valid typed arrayTyped

theorem StateHasType.allocateTemporaryArraySlice
    (typed : StateHasType program context state store)
    (arrayTyped : ValueHasType program (.array elements)
      (.array elementType length))
    (arrayBorrows : BorrowsValid program state store (.array elements)) :
    let nextState := (state.allocateTemporary (.array elements)).2
    let nextStore := store.extend state.nextCell (.array elementType length)
    let slice := Value.slice elementType state.nextCell [] 0 length
    StateHasType program context nextState nextStore ∧
      ValueHasType program slice (.slice elementType) ∧
      BorrowsValid program nextState nextStore slice := by
  dsimp
  refine ⟨typed.allocateTemporary arrayTyped arrayBorrows, ?_, ?_⟩
  · exact .slice elementType state.nextCell [] 0 length
  · exact temporaryArraySlice_borrows_valid typed arrayTyped

theorem existingArraySlice_result_valid
    (storedType : store cell = some rootType)
    (cellFound : state.cellEntry? cell = some entry)
    (initialized : entry.value = some rootValue)
    (rootTyped : ValueHasType program rootValue rootType)
    (projected : ProjectionHasType program rootType projections
      (.array elementType length)) :
    ValueHasType program
        (.slice elementType cell projections 0 length) (.slice elementType) ∧
      BorrowsValid program state store
        (.slice elementType cell projections 0 length) := by
  constructor
  · exact .slice elementType cell projections 0 length
  · intro descriptor member
    simp [valueBorrows] at member
    subst descriptor
    exact .slice storedType cellFound initialized rootTyped projected (by simp)

theorem existingReference_result_valid
    (storedType : store cell = some rootType)
    (cellFound : state.cellEntry? cell = some entry)
    (initialized : entry.value = some rootValue)
    (rootTyped : ValueHasType program rootValue rootType)
    (projected : ProjectionHasType program rootType projections referent) :
    ValueHasType program (.reference referent cell projections)
        (.reference referent) ∧
      BorrowsValid program state store
        (.reference referent cell projections) := by
  constructor
  · exact .reference referent cell projections
  · intro descriptor member
    simp [valueBorrows] at member
    subst descriptor
    exact .reference storedType cellFound initialized rootTyped projected

theorem ValuesHaveTypes.setValue_preserves
    (typed : ValuesHaveTypes program values types)
    (typeFound : types[index]? = some replacementType)
    (replacementTyped : ValueHasType program replacement replacementType) :
    ValuesHaveTypes program (setValue values index replacement) types := by
  induction index generalizing values types with
  | zero =>
      cases typed with
      | nil => simp at typeFound
      | cons head tail =>
          simp [setValue] at typeFound ⊢
          subst replacementType
          exact .cons replacementTyped tail
  | succ index inductionHypothesis =>
      cases typed with
      | nil => simp at typeFound
      | cons head tail =>
          simp [setValue] at typeFound ⊢
          exact .cons head
            (inductionHypothesis tail typeFound)

theorem setValue_length (values : List Value) (index : Nat)
    (replacement : Value) :
    (setValue values index replacement).length = values.length := by
  induction values generalizing index with
  | nil => simp [setValue]
  | cons head tail inductionHypothesis =>
      cases index with
      | zero => simp [setValue]
      | succ index => simp [setValue, inductionHypothesis]

theorem ValuesHaveTypes.getElem?_typed
    (index : Nat)
    (typed : ValuesHaveTypes program values types)
    (typeFound : types[index]? = some selectedType) :
    ∃ value, values[index]? = some value ∧
      ValueHasType program value selectedType := by
  induction index generalizing values types with
  | zero =>
      cases typed with
      | nil => simp at typeFound
      | cons head tail =>
          simp at typeFound
          subst selectedType
          exact ⟨_, rfl, head⟩
  | succ index inductionHypothesis =>
      cases typed with
      | nil => simp at typeFound
      | cons head tail =>
          simp at typeFound ⊢
          exact inductionHypothesis tail typeFound

theorem ValuesHaveTypes.getElem?_aligned
    (index : Nat)
    (typed : ValuesHaveTypes program values types)
    (valueFound : values[index]? = some selectedValue) :
    ∃ selectedType, types[index]? = some selectedType ∧
      ValueHasType program selectedValue selectedType := by
  induction index generalizing values types with
  | zero =>
      cases typed with
      | nil => simp at valueFound
      | cons head tail =>
          simp at valueFound
          subst selectedValue
          exact ⟨_, rfl, head⟩
  | succ index inductionHypothesis =>
      cases typed with
      | nil => simp at valueFound
      | cons head tail =>
          simp at valueFound ⊢
          exact inductionHypothesis tail valueFound

theorem replicate_getElem?_some {α : Type} (length index : Nat)
    (value selected : α)
    (found : (List.replicate length value)[index]? = some selected) :
    selected = value := by
  rw [List.getElem?_replicate] at found
  split at found <;> simp_all

theorem replaceProjectedValue_preserves_type
    (rootTyped : ValueHasType program rootValue rootType)
    (projected : ProjectionHasType program rootType projections resultType)
    (replacementTyped : ValueHasType program replacement resultType)
    (replaced : replaceProjectedValue rootValue projections replacement =
      .ok updated) :
    ValueHasType program updated rootType := by
  induction projected generalizing rootValue updated with
  | nil =>
      simp [replaceProjectedValue] at replaced
      subst updated
      exact replacementTyped
  | field declaration found fieldFound tail inductionHypothesis =>
      cases rootTyped with
      | «structure» valueDeclaration valueFound fieldsTyped =>
          have sameDeclaration : valueDeclaration = declaration := by
            exact Option.some.inj (valueFound.symm.trans found)
          subst valueDeclaration
          obtain ⟨oldValue, oldFound, oldTyped⟩ :=
            Lanius.Properties.ValuesHaveTypes.getElem?_typed _ fieldsTyped
              fieldFound
          simp only [replaceProjectedValue, oldFound] at replaced
          cases recursive : replaceProjectedValue oldValue _ replacement with
          | error reason =>
              rw [recursive] at replaced
              cases replaced
          | ok replacementField =>
              rw [recursive] at replaced
              cases replaced
              have replacementFieldTyped := inductionHypothesis
                oldTyped replacementTyped recursive
              exact .structure declaration found
                (Lanius.Properties.ValuesHaveTypes.setValue_preserves
                  fieldsTyped fieldFound replacementFieldTyped)
  | arrayIndex tail inductionHypothesis =>
      rename_i index
      cases rootTyped with
      | array values elementType length elementsTyped =>
          cases valueFound : values[index]? with
          | none => simp [replaceProjectedValue, valueFound] at replaced
          | some oldValue =>
            obtain ⟨selectedType, typeFound, oldTyped⟩ :=
              Lanius.Properties.ValuesHaveTypes.getElem?_aligned _ elementsTyped
                valueFound
            have replicatedFound := typeFound
            have selectedTypeEq := replicate_getElem?_some _ _ _ _ typeFound
            subst selectedType
            simp only [replaceProjectedValue, valueFound] at replaced
            cases recursive : replaceProjectedValue oldValue _ replacement with
            | error reason =>
              rw [recursive] at replaced
              cases replaced
            | ok replacementElement =>
              rw [recursive] at replaced
              cases replaced
              have replacementElementTyped := inductionHypothesis
                oldTyped replacementTyped recursive
              exact .array _ _ ((setValue_length _ _ _).trans length)
                (Lanius.Properties.ValuesHaveTypes.setValue_preserves
                  elementsTyped replicatedFound
                  replacementElementTyped)
  | sliceIndex tail inductionHypothesis =>
      cases rootTyped with
      | slice => simp [replaceProjectedValue] at replaced

theorem valueListBorrows_setValue_valid
    (oldValid : ∀ descriptor, descriptor ∈ valueListBorrows values →
      BorrowValid program state store descriptor)
    (replacementValid : BorrowsValid program state store replacement) :
    ∀ descriptor,
      descriptor ∈ valueListBorrows (setValue values index replacement) →
      BorrowValid program state store descriptor := by
  induction index generalizing values with
  | zero =>
      cases values with
      | nil => simp [setValue, valueListBorrows]
      | cons head tail =>
          intro descriptor member
          simp only [setValue, valueListBorrows, List.mem_append] at member
          rcases member with replacementMember | tailMember
          · exact replacementValid descriptor replacementMember
          · exact oldValid descriptor (by
              simp [valueListBorrows, tailMember])
  | succ index inductionHypothesis =>
      cases values with
      | nil => simp [setValue, valueListBorrows]
      | cons head tail =>
          intro descriptor member
          simp only [setValue, valueListBorrows, List.mem_append] at member
          rcases member with headMember | tailMember
          · exact oldValid descriptor (by
              simp [valueListBorrows, headMember])
          · exact inductionHypothesis
              (fun candidate candidateMember => oldValid candidate (by
                simp [valueListBorrows, candidateMember]))
              descriptor tailMember

theorem valueBorrows_mem_valueListBorrows
    (valueMember : value ∈ values)
    (borrowMember : descriptor ∈ valueBorrows value) :
    descriptor ∈ valueListBorrows values := by
  induction values with
  | nil => simp at valueMember
  | cons head tail inductionHypothesis =>
      simp only [List.mem_cons] at valueMember
      rcases valueMember with same | tailMember
      · subst head
        simp [valueListBorrows, borrowMember]
      · simp [valueListBorrows,
          inductionHypothesis tailMember]

theorem mem_valueListBorrows
    (member : descriptor ∈ valueListBorrows values) :
    ∃ value, value ∈ values ∧ descriptor ∈ valueBorrows value := by
  induction values with
  | nil => simp [valueListBorrows] at member
  | cons head tail induction =>
      simp only [valueListBorrows, List.mem_append] at member
      rcases member with headMember | tailMember
      · exact ⟨head, by simp, headMember⟩
      · obtain ⟨value, valueMember, borrowMember⟩ := induction tailMember
        exact ⟨value, by simp [valueMember], borrowMember⟩

theorem replaceProjectedValue_preserves_borrows
    (rootValid : BorrowsValid program state store rootValue)
    (replacementValid : BorrowsValid program state store replacement)
    (replaced : replaceProjectedValue rootValue projections replacement =
      .ok updated) :
    BorrowsValid program state store updated := by
  induction projections generalizing rootValue updated with
  | nil =>
      simp [replaceProjectedValue] at replaced
      subst updated
      exact replacementValid
  | cons projection projections inductionHypothesis =>
      cases projection with
      | field field =>
          cases rootValue with
          | «structure» declaration fields =>
              cases oldFound : fields[field]? with
              | none => simp [replaceProjectedValue, oldFound] at replaced
              | some oldValue =>
                  simp only [replaceProjectedValue, oldFound] at replaced
                  cases recursive : replaceProjectedValue oldValue projections
                      replacement with
                  | error reason =>
                      rw [recursive] at replaced
                      cases replaced
                  | ok replacementField =>
                      rw [recursive] at replaced
                      cases replaced
                      have oldValueValid :
                          BorrowsValid program state store oldValue := by
                        intro descriptor member
                        exact rootValid descriptor (by
                          simpa [valueBorrows] using
                            valueBorrows_mem_valueListBorrows
                              (List.mem_of_getElem? oldFound) member)
                      have replacementFieldValid := inductionHypothesis
                        oldValueValid recursive
                      intro descriptor member
                      simp only [valueBorrows] at member
                      exact valueListBorrows_setValue_valid
                        (fun candidate candidateMember => rootValid candidate (by
                          simpa [valueBorrows] using candidateMember))
                        replacementFieldValid descriptor member
          | _ => simp [replaceProjectedValue] at replaced
      | index index =>
          cases rootValue with
          | array elements =>
              cases oldFound : elements[index]? with
              | none => simp [replaceProjectedValue, oldFound] at replaced
              | some oldValue =>
                  simp only [replaceProjectedValue, oldFound] at replaced
                  cases recursive : replaceProjectedValue oldValue projections
                      replacement with
                  | error reason =>
                      rw [recursive] at replaced
                      cases replaced
                  | ok replacementElement =>
                      rw [recursive] at replaced
                      cases replaced
                      have oldValueValid :
                          BorrowsValid program state store oldValue := by
                        intro descriptor member
                        exact rootValid descriptor (by
                          simpa [valueBorrows] using
                            valueBorrows_mem_valueListBorrows
                              (List.mem_of_getElem? oldFound) member)
                      have replacementElementValid := inductionHypothesis
                        oldValueValid recursive
                      intro descriptor member
                      simp only [valueBorrows] at member
                      exact valueListBorrows_setValue_valid
                        (fun candidate candidateMember => rootValid candidate (by
                          simpa [valueBorrows] using candidateMember))
                        replacementElementValid descriptor member
          | _ => simp [replaceProjectedValue] at replaced

theorem projectedValue_preserves_type
    (rootTyped : ValueHasType program rootValue rootType)
    (projected : ProjectionHasType program rootType projections resultType)
    (evaluated : projectedValue rootValue projections = .ok result) :
    ValueHasType program result resultType := by
  induction projected generalizing rootValue result with
  | nil =>
      simp [projectedValue] at evaluated
      subst result
      exact rootTyped
  | field declaration found fieldFound tail inductionHypothesis =>
      cases rootTyped with
      | «structure» valueDeclaration valueFound fieldsTyped =>
          have sameDeclaration : valueDeclaration = declaration := by
            exact Option.some.inj (valueFound.symm.trans found)
          subst valueDeclaration
          obtain ⟨fieldValue, fieldValueFound, fieldTyped⟩ :=
            Lanius.Properties.ValuesHaveTypes.getElem?_typed _ fieldsTyped
              fieldFound
          simp only [projectedValue, fieldValueFound] at evaluated
          exact inductionHypothesis fieldTyped evaluated
  | arrayIndex tail inductionHypothesis =>
      rename_i index
      cases rootTyped with
      | array values selectedElementType length elementsTyped =>
          cases valueFound : values[index]? with
          | none => simp [projectedValue, valueFound] at evaluated
          | some value =>
              obtain ⟨selectedType, typeFound, valueTyped⟩ :=
                Lanius.Properties.ValuesHaveTypes.getElem?_aligned _
                  elementsTyped valueFound
              have selectedTypeEq :=
                replicate_getElem?_some _ _ _ _ typeFound
              subst selectedType
              simp only [projectedValue, valueFound] at evaluated
              exact inductionHypothesis valueTyped evaluated
  | sliceIndex tail inductionHypothesis =>
      cases rootTyped with
      | slice => simp [projectedValue] at evaluated

theorem projectedValue_append
    (prefixEvaluated : projectedValue root prefixPath = .ok middle)
    (suffixEvaluated : projectedValue middle suffixPath = .ok result) :
    projectedValue root (prefixPath ++ suffixPath) = .ok result := by
  induction prefixPath generalizing root middle with
  | nil =>
      simp [projectedValue] at prefixEvaluated ⊢
      subst middle
      exact suffixEvaluated
  | cons projection prefixPath inductionHypothesis =>
      cases projection with
      | field field =>
          cases root with
          | «structure» declaration fields =>
              cases selected : fields[field]? with
              | none => simp [projectedValue, selected] at prefixEvaluated
              | some fieldValue =>
                  simp only [List.cons_append, projectedValue, selected]
                    at prefixEvaluated ⊢
                  exact inductionHypothesis prefixEvaluated suffixEvaluated
          | _ => simp [projectedValue] at prefixEvaluated
      | index index =>
          cases root with
          | array elements =>
              cases selected : elements[index]? with
              | none => simp [projectedValue, selected] at prefixEvaluated
              | some element =>
                  simp only [List.cons_append, projectedValue, selected]
                    at prefixEvaluated ⊢
                  exact inductionHypothesis prefixEvaluated suffixEvaluated
          | _ => simp [projectedValue] at prefixEvaluated

theorem projectedValue_preserves_borrows
    (rootValid : BorrowsValid program state store rootValue)
    (evaluated : projectedValue rootValue projections = .ok result) :
    BorrowsValid program state store result := by
  induction projections generalizing rootValue result with
  | nil =>
      simp [projectedValue] at evaluated
      subst result
      exact rootValid
  | cons projection projections inductionHypothesis =>
      cases projection with
      | field field =>
          cases rootValue with
          | «structure» declaration fields =>
              cases selected : fields[field]? with
              | none => simp [projectedValue, selected] at evaluated
              | some fieldValue =>
                  simp only [projectedValue, selected] at evaluated
                  have fieldValid :
                      BorrowsValid program state store fieldValue := by
                    intro descriptor member
                    exact rootValid descriptor (by
                      simpa [valueBorrows] using
                        valueBorrows_mem_valueListBorrows
                          (List.mem_of_getElem? selected) member)
                  exact inductionHypothesis fieldValid evaluated
          | _ => simp [projectedValue] at evaluated
      | index index =>
          cases rootValue with
          | array elements =>
              cases selected : elements[index]? with
              | none => simp [projectedValue, selected] at evaluated
              | some element =>
                  simp only [projectedValue, selected] at evaluated
                  have elementValid :
                      BorrowsValid program state store element := by
                    intro descriptor member
                    exact rootValid descriptor (by
                      simpa [valueBorrows] using
                        valueBorrows_mem_valueListBorrows
                          (List.mem_of_getElem? selected) member)
                  exact inductionHypothesis elementValid evaluated
          | _ => simp [projectedValue] at evaluated

theorem sliceValues_getElem?_typed
    (index : Nat)
    (valid : BorrowValid program state store
      (.slice elementType cell projections start length))
    (sliced : sliceValues state cell projections start length = .ok values)
    (selected : values[index]? = some result) :
    ValueHasType program result elementType := by
  cases valid with
  | slice stored cellFound initialized rootTyped projected inBounds =>
      rename_i rootType entry rootValue arrayLength
      cases entry with
      | mk entryId contents =>
          cases contents with
          | none => simp at initialized
          | some storedRoot =>
              simp at initialized
              subst storedRoot
              simp only [sliceValues, readCellProjection, cellFound] at sliced
              cases projectionResult : projectedValue rootValue projections with
              | error reason =>
                  rw [projectionResult] at sliced
                  cases sliced
              | ok projectedValue =>
                  rw [projectionResult] at sliced
                  have projectedTyped := projectedValue_preserves_type
                    rootTyped projected projectionResult
                  cases projectedTyped with
                  | array elements selectedElementType valueLength elementsTyped =>
                      simp only at sliced
                      split at sliced
                      · cases sliced
                        have slicedTyped :=
                          Lanius.Properties.ValuesHaveTypes.take length
                            (Lanius.Properties.ValuesHaveTypes.drop start
                              elementsTyped)
                        obtain ⟨selectedType, selectedTypeFound, resultTyped⟩ :=
                          Lanius.Properties.ValuesHaveTypes.getElem?_aligned _
                            slicedTyped selected
                        have enough : length ≤ arrayLength - start := by omega
                        have selectedTypeEq : selectedType = elementType := by
                          have replicated := replicate_getElem?_some _ _ _ _
                            (by
                              simpa [List.drop_replicate, List.take_replicate,
                                Nat.min_eq_left enough] using selectedTypeFound)
                          exact replicated
                        subst selectedType
                        exact resultTyped
                      · cases sliced

theorem sliceValues_getElem?_borrows
    (index : Nat)
    (stateTyped : StateHasType program context state store)
    (valid : BorrowValid program state store
      (.slice elementType cell projections start length))
    (sliced : sliceValues state cell projections start length = .ok values)
    (selected : values[index]? = some result) :
    BorrowsValid program state store result := by
  cases valid with
  | slice stored cellFound initialized rootTyped projected inBounds =>
      rename_i rootType entry rootValue arrayLength
      have rootBorrows :=
        (stateTyped.initialized_cell stored cellFound initialized).2
      cases entry with
      | mk entryId contents =>
          cases contents with
          | none => simp at initialized
          | some storedRoot =>
              simp at initialized
              subst storedRoot
              simp only [sliceValues, readCellProjection, cellFound] at sliced
              cases projectionResult : projectedValue rootValue projections with
              | error reason =>
                  rw [projectionResult] at sliced
                  cases sliced
              | ok projectedValue =>
                  rw [projectionResult] at sliced
                  have projectedTyped := projectedValue_preserves_type
                    rootTyped projected projectionResult
                  have projectedBorrows := projectedValue_preserves_borrows
                    rootBorrows projectionResult
                  cases projectedTyped with
                  | array elements selectedElementType valueLength elementsTyped =>
                      simp only at sliced
                      split at sliced
                      · cases sliced
                        have selectedInElements : result ∈ elements :=
                          List.mem_of_mem_drop
                            (List.mem_of_mem_take
                              (List.mem_of_getElem? selected))
                        intro descriptor member
                        exact projectedBorrows descriptor (by
                          simpa [valueBorrows] using
                            valueBorrows_mem_valueListBorrows
                              selectedInElements member)
                      · cases sliced

theorem sliceValues_have_types
    (valid : BorrowValid program state store
      (.slice elementType cell projections start length))
    (sliced : sliceValues state cell projections start length = .ok values) :
    ValuesHaveTypes program values
      (List.replicate values.length elementType) := by
  apply ValuesHaveTypes.replicate_of_mem
  intro value member
  obtain ⟨index, inBounds, selected⟩ := (List.mem_iff_getElem).mp member
  apply sliceValues_getElem?_typed index valid sliced
  rw [List.getElem?_eq_getElem inBounds, selected]

theorem sliceValues_borrows_valid
    (stateTyped : StateHasType program context state store)
    (valid : BorrowValid program state store
      (.slice elementType cell projections start length))
    (sliced : sliceValues state cell projections start length = .ok values) :
    ValuesBorrowsValid program state store values := by
  intro descriptor member
  obtain ⟨value, valueMember, descriptorMember⟩ :=
    mem_valueListBorrows member
  obtain ⟨index, inBounds, selected⟩ :=
    (List.mem_iff_getElem).mp valueMember
  have selectedResult : values[index]? = some value := by
    rw [List.getElem?_eq_getElem inBounds, selected]
  exact sliceValues_getElem?_borrows index stateTyped valid sliced
    selectedResult descriptor descriptorMember

theorem readCellProjection_reference_typed
    (valid : BorrowValid program state store
      (.reference referent cell projections))
    (read : readCellProjection state cell projections = .ok result) :
    ValueHasType program result referent := by
  cases valid with
  | reference stored cellFound initialized rootTyped projected =>
      rename_i rootType entry rootValue
      cases entry with
      | mk entryId contents =>
          cases contents with
          | none => simp at initialized
          | some storedRoot =>
              simp at initialized
              subst storedRoot
              simp only [readCellProjection, cellFound] at read
              exact projectedValue_preserves_type rootTyped projected read

theorem readCellProjection_reference_borrows
    (stateTyped : StateHasType program context state store)
    (valid : BorrowValid program state store
      (.reference referent cell projections))
    (read : readCellProjection state cell projections = .ok result) :
    BorrowsValid program state store result := by
  cases valid with
  | reference stored cellFound initialized rootTyped projected =>
      rename_i rootType entry rootValue
      have rootBorrows :=
        (stateTyped.initialized_cell stored cellFound initialized).2
      cases entry with
      | mk entryId contents =>
          cases contents with
          | none => simp at initialized
          | some storedRoot =>
              simp at initialized
              subst storedRoot
              simp only [readCellProjection, cellFound] at read
              exact projectedValue_preserves_borrows rootBorrows read

/-- A resolved place carries the dynamic evidence needed by assignment. A
    missing cached value records what place evaluation observed; the stable
    root may be initialized by a later subexpression before the place is used. -/
inductive ResolvedPlaceHasType
    (program : Program) (state : State) (store : StoreTyping) :
    ResolvedPlace → Ty → Prop where
  | rootNoCachedValue
      (stored : store root = some type)
      (found : state.cellEntry? root = some entry) :
      ResolvedPlaceHasType program state store
        { root, projections := [], value := none } type
  | rootInitialized
      (stored : store root = some type)
      (found : state.cellEntry? root = some entry)
      (initialized : entry.value = some rootValue)
      (rootTyped : ValueHasType program rootValue type)
      (rootBorrows : BorrowsValid program state store rootValue)
      (valueTyped : ValueHasType program value type)
      (valueBorrows : BorrowsValid program state store value) :
      ResolvedPlaceHasType program state store
        { root, projections := [], value := some value } type
  | projected
      (stored : store root = some rootType)
      (found : state.cellEntry? root = some entry)
      (initialized : entry.value = some rootValue)
      (rootTyped : ValueHasType program rootValue rootType)
      (rootBorrows : BorrowsValid program state store rootValue)
      (projectionTyped : ProjectionHasType program rootType projections resultType)
      (valueTyped : ValueHasType program value resultType)
      (valueBorrows : BorrowsValid program state store value) :
      ResolvedPlaceHasType program state store
        { root, projections, value := some value }
        resultType

theorem ResolvedPlaceHasType.i32ArrayPlace
    (typed : ResolvedPlaceHasType program state store
      { root, projections, value := some (.array elements) }
      (.array (.scalar (.signed .i32)) length)) :
    I32ArrayPlaceHasType program state store root projections length := by
  cases typed with
  | rootInitialized stored found initialized rootTyped rootBorrows valueTyped
      valueBorrows =>
      exact ⟨_, _, _, stored, found, initialized, rootTyped,
        ProjectionHasType.nil⟩
  | projected stored found initialized rootTyped rootBorrows projectionTyped
      valueTyped valueBorrows =>
      exact ⟨_, _, _, stored, found, initialized, rootTyped, projectionTyped⟩

theorem writeResolvedPlace_preserves_state_typing
    (stateTyped : StateHasType program context state store)
    (placeTyped : ResolvedPlaceHasType program state store place type)
    (replacementTyped : ValueHasType program replacement type)
    (replacementBorrows : BorrowsValid program state store replacement)
    (written : writeResolvedPlace state place replacement = .ok next) :
    StateHasType program context next store := by
  cases placeTyped with
  | rootNoCachedValue stored found =>
      simp only [writeResolvedPlace] at written
      cases assigned : state.assignCell _ replacement with
      | none => rw [assigned] at written; cases written
      | some assignedState =>
          rw [assigned] at written
          cases written
          exact stateTyped.assignCell assigned stored replacementTyped
            replacementBorrows
  | rootInitialized stored found initialized rootTyped rootBorrows oldValueTyped
      oldValueBorrows =>
      simp only [writeResolvedPlace] at written
      cases assigned : state.assignCell _ replacement with
      | none => rw [assigned] at written; cases written
      | some assignedState =>
          rw [assigned] at written
          cases written
          exact stateTyped.assignCell assigned stored replacementTyped
            replacementBorrows
  | projected stored found initialized rootTyped rootBorrows projectionTyped
      oldValueTyped oldValueBorrows =>
      rename_i root rootType entry rootValue projections currentValue
      cases projections with
      | nil =>
          cases projectionTyped with
          | nil =>
              simp only [writeResolvedPlace] at written
              cases assigned : state.assignCell root replacement with
              | none => rw [assigned] at written; cases written
              | some assignedState =>
                  rw [assigned] at written
                  cases written
                  exact stateTyped.assignCell assigned stored replacementTyped
                    replacementBorrows
      | cons projection projections =>
          have entryShape : entry = { entry with value := some rootValue } := by
            cases entry
            simp_all
          rw [entryShape] at found
          simp only [writeResolvedPlace, found] at written
          cases replaced : replaceProjectedValue rootValue
              (projection :: projections) replacement with
          | error reason => simp only [replaced] at written; cases written
          | ok updated =>
              simp only [replaced] at written
              cases assigned : state.assignCell root updated with
              | none => simp only [assigned] at written; cases written
              | some assignedState =>
                  simp only [assigned] at written
                  cases written
                  have updatedTyped := replaceProjectedValue_preserves_type
                    rootTyped projectionTyped replacementTyped replaced
                  have updatedBorrows := replaceProjectedValue_preserves_borrows
                    rootBorrows replacementBorrows replaced
                  exact stateTyped.assignCell assigned stored updatedTyped
                    updatedBorrows

theorem writeI32ArrayView_preserves_state_typing
    (stateTyped : StateHasType program context state store)
    (viewTyped : I32ArrayViewPlaceHasType program state store view)
    (replacementTyped : ValueHasType program replacement
      (.array (.scalar (.signed .i32)) view.length))
    (replacementBorrows : BorrowsValid program state store replacement)
    (written : writeResolvedPlace state
      { root := view.root, projections := view.projections, value := none }
      replacement = .ok next) :
    StateHasType program context next store := by
  obtain ⟨rootType, entry, rootValue, stored, found, initialized,
    rootTyped, projectionTyped⟩ := viewTyped
  have rootBorrows :=
    (stateTyped.initialized_cell stored found initialized).2
  cases projectionsShape : view.projections with
  | nil =>
      rw [projectionsShape] at projectionTyped written
      cases projectionTyped with
      | nil =>
          simp only [writeResolvedPlace] at written
          cases assigned : state.assignCell view.root replacement with
          | none => rw [assigned] at written; cases written
          | some assignedState =>
              rw [assigned] at written
              cases written
              exact stateTyped.assignCell assigned stored replacementTyped
                replacementBorrows
  | cons projection projections =>
      rw [projectionsShape] at projectionTyped written
      have entryShape : entry = { entry with value := some rootValue } := by
        cases entry
        simp_all
      rw [entryShape] at found
      simp only [writeResolvedPlace, found] at written
      cases replaced : replaceProjectedValue rootValue
          (projection :: projections) replacement with
      | error reason => simp only [replaced] at written; cases written
      | ok updated =>
          simp only [replaced] at written
          cases assigned : state.assignCell view.root updated with
          | none => simp only [assigned] at written; cases written
          | some assignedState =>
              simp only [assigned] at written
              cases written
              have updatedTyped := replaceProjectedValue_preserves_type
                rootTyped projectionTyped replacementTyped replaced
              have updatedBorrows := replaceProjectedValue_preserves_borrows
                rootBorrows replacementBorrows replaced
              exact stateTyped.assignCell assigned stored updatedTyped
                updatedBorrows

/-- Evaluation never removes or uninitializes an existing initialized semantic
    cell. Its value may change, but the stable identity remains initialized.
    This is the state-side fact needed to keep references obtained earlier in
    a left-to-right evaluation valid after later subexpressions run. -/
def InitializedCellsPreserved (before after : State) : Prop :=
  ∀ cell entry value,
    before.cellEntry? cell = some entry → entry.value = some value →
    ∃ nextEntry nextValue,
      after.cellEntry? cell = some nextEntry ∧ nextEntry.value = some nextValue

def ValueOutcomePreservesInitializedCells
    (before : State) (outcome : Outcome Value) : Prop :=
  match outcome with
  | .done _ afterState | .trapped _ afterState | .exited _ afterState =>
      InitializedCellsPreserved before afterState
  | .outOfFuel => True

theorem InitializedCellsPreserved.refl (state : State) :
    InitializedCellsPreserved state state := by
  intro cell entry value found initialized
  exact ⟨entry, value, found, initialized⟩

theorem InitializedCellsPreserved.withWorld
    (state : State) (world : World.State) :
    InitializedCellsPreserved state { state with world := world } := by
  intro cell entry value found initialized
  exact ⟨entry, value, found, initialized⟩

theorem InitializedCellsPreserved.withHeap
    (state : State) (heap : Heap) :
    InitializedCellsPreserved state { state with heap := heap } := by
  intro cell entry value found initialized
  exact ⟨entry, value, found, initialized⟩

theorem InitializedCellsPreserved.withHeapAndI32ArrayViews
    (state : State) (heap : Heap) (views : List I32ArrayView) :
    InitializedCellsPreserved state
      { state with heap := heap, i32ArrayViews := views } := by
  intro cell entry value found initialized
  exact ⟨entry, value, found, initialized⟩

theorem I32ArrayViewPlaceHasType.preserve
    (storePreserved : StoreExtends beforeStore afterStore)
    (cellsPreserved : InitializedCellsPreserved beforeState afterState)
    (afterTyped : StateHasType program context afterState afterStore)
    (typed : I32ArrayViewPlaceHasType program beforeState beforeStore view) :
    I32ArrayViewPlaceHasType program afterState afterStore view := by
  obtain ⟨rootType, entry, rootValue, stored, found, initialized,
    rootTyped, projected⟩ := typed
  obtain ⟨nextEntry, nextValue, nextFound, nextInitialized⟩ :=
    cellsPreserved view.root entry rootValue found initialized
  have nextStored := storePreserved view.root rootType stored
  have nextRootTyped :=
    (afterTyped.initialized_cell nextStored nextFound nextInitialized).1
  exact ⟨rootType, nextEntry, nextValue, nextStored, nextFound,
    nextInitialized, nextRootTyped, projected⟩

theorem I32ArrayViewsWellFormed.preserve
    (storePreserved : StoreExtends beforeStore afterStore)
    (cellsPreserved : InitializedCellsPreserved beforeState afterState)
    (afterTyped : StateHasType program context afterState afterStore)
    (viewsSame : afterState.i32ArrayViews = beforeState.i32ArrayViews)
    (blocksPreserved : I32ArrayViewBlocksPreserved
      beforeState.i32ArrayViews beforeState.heap afterState.heap)
    (valid : I32ArrayViewsWellFormed program beforeState beforeStore) :
    I32ArrayViewsWellFormed program afterState afterStore := by
  intro view afterMember
  have beforeMember : view ∈ beforeState.i32ArrayViews := by
    simpa [viewsSame] using afterMember
  have beforeValid := valid view beforeMember
  exact ⟨beforeValid.1.preserve storePreserved cellsPreserved afterTyped,
    blocksPreserved view beforeMember beforeValid.2⟩

theorem RuntimeStateHasType.withWorld
    (typed : RuntimeStateHasType program context state store)
    (world : World.State) :
    RuntimeStateHasType program context { state with world := world } store := by
  let next : State := { state with world := world }
  have nextTyped := typed.typed.withWorld world
  refine ⟨nextTyped, ?_⟩
  apply typed.views.preserve (StoreExtends.refl store)
    (InitializedCellsPreserved.withWorld state world) nextTyped
  · rfl
  · exact I32ArrayViewBlocksPreserved.refl state.heap state.i32ArrayViews

theorem RuntimeStateHasType.withHeap
    (typed : RuntimeStateHasType program context state store)
    (heap : Heap) (heapWellFormed : HeapWellFormed heap)
    (blocksPreserved : I32ArrayViewBlocksPreserved
      state.i32ArrayViews state.heap heap) :
    RuntimeStateHasType program context { state with heap := heap } store := by
  let next : State := { state with heap := heap }
  have nextTyped := typed.typed.withHeap heap heapWellFormed
  refine ⟨nextTyped, ?_⟩
  apply typed.views.preserve (StoreExtends.refl store)
    (InitializedCellsPreserved.withHeap state heap) nextTyped
  · rfl
  · exact blocksPreserved

theorem allocate_has_runtime_type
    (typed : RuntimeStateHasType program context state store) :
    RuntimeValueOutcomeHasType program context store
      (match state.heap.allocate size alignment with
      | .allocated pointer heap =>
          .done (.pointer pointer) { state with heap }
      | .exhausted heap =>
          .done (.pointer null) { state with heap }
      | .trapped reason heap =>
          .trapped reason { state with heap })
      (.scalar .rawPtr) := by
  cases allocation : state.heap.allocate size alignment with
  | allocated pointer heap =>
      simp only [allocation, RuntimeValueOutcomeHasType]
      have heapWellFormed : HeapWellFormed heap := by
        have preserved := allocate_preserves_heap_well_formed
          typed.typed.wellFormed.heapWellFormed
            (size := size) (alignment := alignment)
        rw [allocation] at preserved
        exact preserved
      have blocksPreserved := allocate_preserves_i32_array_view_blocks
        (views := state.i32ArrayViews) allocation
      refine ⟨typed.withHeap heap heapWellFormed blocksPreserved,
        .pointer pointer, ?_⟩
      intro descriptor member
      simp [valueBorrows] at member
  | exhausted heap =>
      have heapEq := allocate_exhausted_heap_eq state.heap heap size alignment
        allocation
      subst heap
      simp only [allocation, RuntimeValueOutcomeHasType]
      refine ⟨typed, .pointer null, ?_⟩
      intro descriptor member
      simp [valueBorrows] at member
  | trapped reason heap =>
      have heapEq := allocate_trapped_heap_eq state.heap heap size alignment
        reason allocation
      subst heap
      simp only [allocation, RuntimeValueOutcomeHasType]
      exact typed

theorem reallocate_has_runtime_type
    (typed : RuntimeStateHasType program context state store) :
    RuntimeValueOutcomeHasType program context store
      (match state.heap.reallocate pointer oldSize newSize alignment with
      | .allocated replacement heap =>
          .done (.pointer replacement) { state with heap }
      | .exhausted heap =>
          .done (.pointer null) { state with heap }
      | .trapped reason heap =>
          .trapped reason { state with heap })
      (.scalar .rawPtr) := by
  cases reallocated : state.heap.reallocate pointer oldSize newSize alignment with
  | allocated replacement heap =>
      simp only [reallocated, RuntimeValueOutcomeHasType]
      have heapWellFormed : HeapWellFormed heap := by
        have preserved := reallocate_preserves_heap_well_formed
          (pointer := pointer) (oldSize := oldSize) (newSize := newSize)
            (alignment := alignment) typed.typed.wellFormed.heapWellFormed
        rw [reallocated] at preserved
        exact preserved
      have blocksPreserved := reallocate_preserves_i32_array_view_blocks
        (views := state.i32ArrayViews) typed.typed.wellFormed.heapWellFormed
          reallocated
      refine ⟨typed.withHeap heap heapWellFormed blocksPreserved,
        .pointer replacement, ?_⟩
      intro descriptor member
      simp [valueBorrows] at member
  | exhausted heap =>
      have heapEq := reallocate_exhausted_heap_eq state.heap heap pointer
        oldSize newSize alignment reallocated
      subst heap
      simp only [reallocated, RuntimeValueOutcomeHasType]
      refine ⟨typed, .pointer null, ?_⟩
      intro descriptor member
      simp [valueBorrows] at member
  | trapped reason heap =>
      have heapEq := reallocate_trapped_heap_eq state.heap heap pointer
        oldSize newSize alignment reason reallocated
      subst heap
      simp only [reallocated, RuntimeValueOutcomeHasType]
      exact typed

theorem deallocate_has_runtime_type
    (typed : RuntimeStateHasType program context state store) :
    RuntimeValueOutcomeHasType program context store
      (match state.heap.deallocate pointer size alignment with
      | .ok heap => .done .unit { state with heap }
      | .error reason => .trapped reason state)
      .unit := by
  cases deallocated : state.heap.deallocate pointer size alignment with
  | error reason =>
      simp only [deallocated, RuntimeValueOutcomeHasType]
      exact typed
  | ok heap =>
      simp only [deallocated, RuntimeValueOutcomeHasType]
      have heapWellFormed := deallocate_preserves_heap_well_formed
        typed.typed.wellFormed.heapWellFormed deallocated
      have blocksPreserved := deallocate_preserves_i32_array_view_blocks
        (views := state.i32ArrayViews)
          typed.typed.wellFormed.heapWellFormed deallocated
      refine ⟨typed.withHeap heap heapWellFormed blocksPreserved, .unit, ?_⟩
      intro descriptor member
      simp [valueBorrows] at member

theorem loadByte_has_runtime_type
    (typed : RuntimeStateHasType program context state store) :
    RuntimeValueOutcomeHasType program context store
      (match state.heap.loadByte pointer offset with
      | .ok value => .done (.unsigned .u8 value.toNat) state
      | .error reason => .trapped reason state)
      (.scalar (.unsigned .u8)) := by
  cases loaded : state.heap.loadByte pointer offset with
  | error reason =>
      simp only [loaded, RuntimeValueOutcomeHasType]
      exact typed
  | ok value =>
      simp only [loaded, RuntimeValueOutcomeHasType]
      refine ⟨typed, .unsigned .u8 value.toNat ?_, ?_⟩
      · have bound := UInt8.toNat_lt value
        simp [unsignedMax, UnsignedIntTy.bits]
        omega
      · intro descriptor member
        simp [valueBorrows] at member

theorem syncI32ViewsToHeapFrom_preserves_runtime_type
    (typed : RuntimeStateHasType program context state store)
    (synced : syncI32ViewsToHeapFrom pending state = .ok afterState) :
    RuntimeStateHasType program context afterState store := by
  induction pending generalizing state with
  | nil =>
      simp only [syncI32ViewsToHeapFrom, Except.ok.injEq] at synced
      subst afterState
      exact typed
  | cons view rest induction =>
      simp only [syncI32ViewsToHeapFrom] at synced
      cases read : readCellProjection state view.root view.projections with
      | error reason => simp [read] at synced
      | ok value =>
          cases value <;> try simp [read] at synced
          rename_i elements
          by_cases lengthMatches : elements.length = view.length
          · simp [lengthMatches] at synced
            cases encoded : encodeI32Array elements with
            | error reason => simp [encoded] at synced
            | ok bytes =>
                simp [encoded] at synced
                cases stored : state.heap.storeBytes view.address bytes with
                | error reason => simp [stored] at synced
                | ok nextHeap =>
                    simp [stored] at synced
                    have nextHeapWellFormed :=
                      storeBytes_preserves_heap_well_formed
                        typed.typed.wellFormed.heapWellFormed stored
                    have blocksPreserved :=
                      storeBytes_preserves_i32_array_view_blocks
                        (views := state.i32ArrayViews)
                        typed.typed.wellFormed.heapWellFormed stored
                    have nextTyped := typed.withHeap nextHeap
                      nextHeapWellFormed blocksPreserved
                    exact induction nextTyped synced
          · simp [lengthMatches] at synced

theorem syncI32ViewsToHeap_preserves_runtime_type
    (typed : RuntimeStateHasType program context state store)
    (synced : syncI32ViewsToHeap state = .ok afterState) :
    RuntimeStateHasType program context afterState store := by
  exact syncI32ViewsToHeapFrom_preserves_runtime_type typed synced

theorem allocateTemporary_preserves_initialized_cells
    (wellFormed : StateWellFormed state) (temporary : Value) :
    InitializedCellsPreserved state
      (state.allocateTemporary temporary).2 := by
  intro cell entry value found initialized
  have below := found_cell_is_below_next state cell entry wellFormed found
  exact ⟨entry, value,
    (allocateTemporary_preserves_old_cell state temporary cell below).trans found,
    initialized⟩

theorem RuntimeStateHasType.allocateTemporary
    (typed : RuntimeStateHasType program context state store)
    (valueTyped : ValueHasType program value type)
    (valueBorrows : BorrowsValid program state store value) :
    RuntimeStateHasType program context (state.allocateTemporary value).2
      (store.extend state.nextCell type) := by
  have nextTyped := typed.typed.allocateTemporary valueTyped valueBorrows
  refine ⟨nextTyped, ?_⟩
  apply typed.views.preserve
    (StoreTyping.extends_extend store state.nextCell type
      typed.typed.nextCell_store_none)
    (allocateTemporary_preserves_initialized_cells
      typed.typed.wellFormed value)
    nextTyped
  · rfl
  · exact I32ArrayViewBlocksPreserved.refl state.heap state.i32ArrayViews

theorem allocateTemporary_i32ArrayPlace_has_type
    (typed : RuntimeStateHasType program context state store)
    (elementsTyped : ValueHasType program (.array elements)
      (.array (.scalar (.signed .i32)) length)) :
    I32ArrayPlaceHasType program (state.allocateTemporary (.array elements)).2
      (store.extend state.nextCell
        (.array (.scalar (.signed .i32)) length))
      (state.allocateTemporary (.array elements)).1 [] length := by
  refine ⟨(.array (.scalar (.signed .i32)) length),
    { id := state.nextCell, value := some (.array elements) },
    .array elements, ?_, ?_, rfl, elementsTyped, ProjectionHasType.nil⟩
  · simp [StoreTyping.extend, State.allocateTemporary]
  · exact allocateTemporary_finds_fresh_cell state (.array elements)
      typed.typed.wellFormed

theorem InitializedCellsPreserved.trans
    (first : InitializedCellsPreserved before middle)
    (second : InitializedCellsPreserved middle after) :
    InitializedCellsPreserved before after := by
  intro cell entry value found initialized
  obtain ⟨middleEntry, middleValue, middleFound, middleInitialized⟩ :=
    first cell entry value found initialized
  exact second cell middleEntry middleValue middleFound middleInitialized

theorem syncI32ViewsToHeapFrom_preserves_initialized_cells
    (synced : syncI32ViewsToHeapFrom pending state = .ok afterState) :
    InitializedCellsPreserved state afterState := by
  induction pending generalizing state with
  | nil =>
      simp only [syncI32ViewsToHeapFrom, Except.ok.injEq] at synced
      subst afterState
      exact .refl state
  | cons view rest induction =>
      simp only [syncI32ViewsToHeapFrom] at synced
      cases read : readCellProjection state view.root view.projections with
      | error reason => simp [read] at synced
      | ok value =>
          cases value <;> try simp [read] at synced
          rename_i elements
          by_cases lengthMatches : elements.length = view.length
          · simp [lengthMatches] at synced
            cases encoded : encodeI32Array elements with
            | error reason => simp [encoded] at synced
            | ok bytes =>
                simp [encoded] at synced
                cases stored : state.heap.storeBytes view.address bytes with
                | error reason => simp [stored] at synced
                | ok nextHeap =>
                    simp [stored] at synced
                    exact (InitializedCellsPreserved.withHeap state nextHeap).trans
                      (induction synced)
          · simp [lengthMatches] at synced

theorem syncI32ViewsToHeap_preserves_initialized_cells
    (synced : syncI32ViewsToHeap state = .ok afterState) :
    InitializedCellsPreserved state afterState :=
  syncI32ViewsToHeapFrom_preserves_initialized_cells synced

theorem syncI32ViewsToHeapFrom_preserves_world
    (synced : syncI32ViewsToHeapFrom pending state = .ok afterState) :
    afterState.world = state.world := by
  induction pending generalizing state afterState with
  | nil =>
      simp only [syncI32ViewsToHeapFrom, Except.ok.injEq] at synced
      subst afterState
      rfl
  | cons view rest induction =>
      simp only [syncI32ViewsToHeapFrom] at synced
      cases read : readCellProjection state view.root view.projections with
      | error reason => simp [read] at synced
      | ok value =>
          cases value <;> try simp [read] at synced
          rename_i elements
          by_cases lengthMatches : elements.length = view.length
          · simp [lengthMatches] at synced
            cases encoded : encodeI32Array elements with
            | error reason => simp [encoded] at synced
            | ok bytes =>
                simp [encoded] at synced
                cases stored : state.heap.storeBytes view.address bytes with
                | error reason => simp [stored] at synced
                | ok nextHeap =>
                    simp [stored] at synced
                    exact induction
                      (state := { state with heap := nextHeap })
                      (afterState := afterState) synced
          · simp [lengthMatches] at synced

theorem syncI32ViewsToHeap_preserves_world
    (synced : syncI32ViewsToHeap state = .ok afterState) :
    afterState.world = state.world :=
  syncI32ViewsToHeapFrom_preserves_world synced

theorem InitializedCellsPreserved.restoreLocals
    (preserved : InitializedCellsPreserved before completed)
    (caller : State) :
    InitializedCellsPreserved before (restoreLocals caller completed) := by
  exact preserved

theorem InitializedCellsPreserved.withLocals
    (state : State) (locals : List (VarId × CellId)) :
    InitializedCellsPreserved state { state with locals := locals } := by
  exact InitializedCellsPreserved.refl state

theorem bindLocal_preserves_initialized_cells
    (wellFormed : StateWellFormed state) (id : VarId) (value : Value) :
    InitializedCellsPreserved state (state.bindLocal id value) := by
  intro cell entry oldValue found initialized
  have below := found_cell_is_below_next state cell entry wellFormed found
  refine ⟨entry, oldValue, ?_, initialized⟩
  change (state.allocateTemporary value).2.cellEntry? cell = some entry
  exact (allocateTemporary_preserves_old_cell state value cell below).trans found

theorem bindUninitialized_preserves_initialized_cells
    (wellFormed : StateWellFormed state) (id : VarId) :
    InitializedCellsPreserved state (state.bindUninitialized id) := by
  intro cell entry value found initialized
  have below := found_cell_is_below_next state cell entry wellFormed found
  exact ⟨entry, value,
    (bindCell_preserves_old_cell state id none cell below).trans found,
    initialized⟩

theorem StateHasType.bindLocals
    (typed : StateHasType program context state store)
    (bindingsTyped : BindingsHaveTypes program bindings bindingTypes)
    (bindingsBorrows : BindingsBorrowsValid program state store bindings) :
    ∃ nextStore,
      StoreExtends store nextStore ∧
      InitializedCellsPreserved state (state.bindLocals bindings) ∧
      StateHasType program (context.bindAll bindingTypes)
        (state.bindLocals bindings) nextStore := by
  induction bindingsTyped generalizing context state store with
  | nil =>
      exact ⟨store, StoreExtends.refl store,
        InitializedCellsPreserved.refl state, typed⟩
  | @cons value type values types id head tail induction =>
      have headBorrows := bindingsBorrows.head
      have afterHeadTyped := typed.bindLocal id head headBorrows
      have tailBorrows := bindingsBorrows.tail
      have tailBorrowsAfter := tailBorrows.bindLocal typed id value type
      obtain ⟨nextStore, storePreserved, cellsPreserved, completedTyped⟩ :=
        induction afterHeadTyped tailBorrowsAfter
      refine ⟨nextStore, ?_, ?_, ?_⟩
      · exact (StoreTyping.extends_extend store state.nextCell type
          typed.nextCell_store_none).trans storePreserved
      · exact (bindLocal_preserves_initialized_cells typed.wellFormed id value).trans
          cellsPreserved
      · simpa [State.bindLocals, Context.bindAll] using completedTyped

theorem State.bindLocals_preserves_heap_and_views
    (state : State) (bindings : List (VarId × Value)) :
    (state.bindLocals bindings).heap = state.heap ∧
      (state.bindLocals bindings).i32ArrayViews = state.i32ArrayViews := by
  induction bindings generalizing state with
  | nil => simp [State.bindLocals]
  | cons binding rest induction =>
      simpa [State.bindLocals, State.bindLocal, State.bindCell] using
        induction (state := state.bindLocal binding.1 binding.2)

theorem RuntimeStateHasType.bindLocal
    (typed : RuntimeStateHasType program context state store)
    (id : VarId)
    (valueTyped : ValueHasType program value type)
    (valueBorrows : BorrowsValid program state store value) :
    RuntimeStateHasType program (context.bind id type)
      (state.bindLocal id value) (store.extend state.nextCell type) := by
  have nextTyped := typed.typed.bindLocal id valueTyped valueBorrows
  have cellsPreserved := bindLocal_preserves_initialized_cells
    typed.typed.wellFormed id value
  refine ⟨nextTyped, ?_⟩
  apply typed.views.preserve
    (StoreTyping.extends_extend store state.nextCell type
      typed.typed.nextCell_store_none)
    cellsPreserved nextTyped
  · rfl
  · exact I32ArrayViewBlocksPreserved.refl state.heap state.i32ArrayViews

theorem RuntimeStateHasType.bindUninitialized
    (typed : RuntimeStateHasType program context state store)
    (id : VarId) (type : Ty) :
    RuntimeStateHasType program (context.bind id type)
      (state.bindUninitialized id) (store.extend state.nextCell type) := by
  have nextTyped := typed.typed.bindUninitialized id type
  have cellsPreserved := bindUninitialized_preserves_initialized_cells
    typed.typed.wellFormed id
  refine ⟨nextTyped, ?_⟩
  apply typed.views.preserve
    (StoreTyping.extends_extend store state.nextCell type
      typed.typed.nextCell_store_none)
    cellsPreserved nextTyped
  · rfl
  · exact I32ArrayViewBlocksPreserved.refl state.heap state.i32ArrayViews

theorem RuntimeStateHasType.bindLocals
    (typed : RuntimeStateHasType program context state store)
    (bindingsTyped : BindingsHaveTypes program bindings bindingTypes)
    (bindingsBorrows : BindingsBorrowsValid program state store bindings) :
    ∃ nextStore,
      StoreExtends store nextStore ∧
      InitializedCellsPreserved state (state.bindLocals bindings) ∧
      RuntimeStateHasType program (context.bindAll bindingTypes)
        (state.bindLocals bindings) nextStore := by
  obtain ⟨nextStore, storePreserved, cellsPreserved, nextTyped⟩ :=
    typed.typed.bindLocals bindingsTyped bindingsBorrows
  have metadata := State.bindLocals_preserves_heap_and_views state bindings
  refine ⟨nextStore, storePreserved, cellsPreserved, nextTyped, ?_⟩
  apply typed.views.preserve storePreserved cellsPreserved nextTyped
  · exact metadata.2
  · intro view member valid
    simpa only [metadata.1] using valid

theorem RuntimeStateHasType.clearLocals
    (typed : RuntimeStateHasType program context state store) :
    RuntimeStateHasType program Context.empty { state with locals := [] }
      store := by
  have nextTyped := typed.typed.clearLocals
  refine ⟨nextTyped, ?_⟩
  apply typed.views.preserve (StoreExtends.refl store)
    (InitializedCellsPreserved.withLocals state []) nextTyped
  · rfl
  · exact I32ArrayViewBlocksPreserved.refl state.heap state.i32ArrayViews

theorem RuntimeStateHasType.restoreLocals
    (callerTyped : RuntimeStateHasType program context caller callerStore)
    (completedTyped : RuntimeStateHasType program completedContext completed
      completedStore)
    (storePreserved : StoreExtends callerStore completedStore) :
    RuntimeStateHasType program context (restoreLocals caller completed)
      completedStore := by
  have restoredTyped := callerTyped.typed.restoreLocals completedTyped.typed
    storePreserved
  refine ⟨restoredTyped, ?_⟩
  apply completedTyped.views.preserve (StoreExtends.refl completedStore)
    (InitializedCellsPreserved.withLocals completed caller.locals)
    restoredTyped
  · rfl
  · exact I32ArrayViewBlocksPreserved.refl completed.heap
      completed.i32ArrayViews

theorem prepareCallee_has_type
    (callerTyped : StateHasType program callerContext state store)
    (argumentsTyped : ValuesHaveTypes program arguments
      (parameters.map Prod.snd))
    (argumentBorrows : ValuesBorrowsValid program state store arguments)
    (bound : bindParameters parameters arguments = some bindings) :
    ∃ calleeStore,
      StoreExtends store calleeStore ∧
      InitializedCellsPreserved state
        (({ state with locals := [] }).bindLocals bindings) ∧
      StateHasType program (parameterContext parameters)
        (({ state with locals := [] }).bindLocals bindings) calleeStore := by
  have bindingsTyped := bindParameters_preserves_types argumentsTyped bound
  have bindingsBorrows := bindParameters_preserves_borrows
    parameters arguments argumentsTyped argumentBorrows bound
  have clearedTyped := callerTyped.clearLocals
  have clearedBorrows := bindingsBorrows.withLocals []
  obtain ⟨calleeStore, storePreserved, cellsPreserved, calleeTyped⟩ :=
    clearedTyped.bindLocals bindingsTyped clearedBorrows
  refine ⟨calleeStore, storePreserved, ?_, ?_⟩
  · exact (InitializedCellsPreserved.withLocals state []).trans cellsPreserved
  · simpa [parameterContext, Context.bindAll] using calleeTyped

theorem prepareCallee_has_runtime_type
    (callerTyped : RuntimeStateHasType program callerContext state store)
    (argumentsTyped : ValuesHaveTypes program arguments
      (parameters.map Prod.snd))
    (argumentBorrows : ValuesBorrowsValid program state store arguments)
    (bound : bindParameters parameters arguments = some bindings) :
    ∃ calleeStore,
      StoreExtends store calleeStore ∧
      InitializedCellsPreserved state
        (({ state with locals := [] }).bindLocals bindings) ∧
      RuntimeStateHasType program (parameterContext parameters)
        (({ state with locals := [] }).bindLocals bindings) calleeStore := by
  have bindingsTyped := bindParameters_preserves_types argumentsTyped bound
  have bindingsBorrows := bindParameters_preserves_borrows
    parameters arguments argumentsTyped argumentBorrows bound
  have clearedTyped := callerTyped.clearLocals
  have clearedBorrows := bindingsBorrows.withLocals []
  obtain ⟨calleeStore, storePreserved, cellsPreserved, calleeTyped⟩ :=
    clearedTyped.bindLocals bindingsTyped clearedBorrows
  refine ⟨calleeStore, storePreserved, ?_, ?_⟩
  · exact (InitializedCellsPreserved.withLocals state []).trans cellsPreserved
  · simpa [parameterContext, Context.bindAll] using calleeTyped

theorem assignCell_preserves_initialized_cells
    (assigned : state.assignCell target replacement = some next) :
    InitializedCellsPreserved state next := by
  intro cell entry value found initialized
  by_cases same : cell = target
  · subst cell
    exact ⟨{ id := target, value := some replacement }, replacement,
      assignCell_finds_assigned assigned, rfl⟩
  · exact ⟨entry, value,
      (assignCell_preserves_other assigned same).trans found, initialized⟩

theorem writeResolvedPlace_preserves_initialized_cells
    (written : writeResolvedPlace state place replacement = .ok next) :
    InitializedCellsPreserved state next := by
  cases place with
  | mk root projections cached =>
      cases projections with
      | nil =>
          simp only [writeResolvedPlace] at written
          cases assigned : state.assignCell root replacement with
          | none => rw [assigned] at written; cases written
          | some assignedState =>
              rw [assigned] at written
              cases written
              exact assignCell_preserves_initialized_cells assigned
      | cons projection projections =>
          simp only [writeResolvedPlace] at written
          cases found : state.cellEntry? root with
          | none => rw [found] at written; cases written
          | some entry =>
              rw [found] at written
              cases entry with
              | mk entryId contents =>
                  cases contents with
                  | none => simp at written
                  | some rootValue =>
                      simp only at written
                      cases replaced : replaceProjectedValue rootValue
                          (projection :: projections) replacement with
                      | error reason => rw [replaced] at written; cases written
                      | ok updated =>
                          rw [replaced] at written
                          simp only at written
                          cases assigned : state.assignCell root updated with
                          | none => rw [assigned] at written; cases written
                          | some assignedState =>
                              rw [assigned] at written
                              cases written
                              exact assignCell_preserves_initialized_cells assigned

theorem assignCell_preserves_heap_and_views
    {state next : State} {cell : CellId} {value : Value}
    (assigned : state.assignCell cell value = some next) :
    next.heap = state.heap ∧
      next.i32ArrayViews = state.i32ArrayViews := by
  simp only [State.assignCell] at assigned
  split at assigned
  · cases assigned
    exact ⟨rfl, rfl⟩
  · cases assigned

theorem writeResolvedPlace_preserves_heap_and_views
    {state next : State} {place : ResolvedPlace} {replacement : Value}
    (written : writeResolvedPlace state place replacement = .ok next) :
    next.heap = state.heap ∧
      next.i32ArrayViews = state.i32ArrayViews := by
  cases place with
  | mk root projections cached =>
      cases projections with
      | nil =>
          simp only [writeResolvedPlace] at written
          cases assigned : state.assignCell root replacement with
          | none => rw [assigned] at written; cases written
          | some assignedState =>
              rw [assigned] at written
              cases written
              exact assignCell_preserves_heap_and_views assigned
      | cons projection projections =>
          simp only [writeResolvedPlace] at written
          cases found : state.cellEntry? root with
          | none => rw [found] at written; cases written
          | some entry =>
              rw [found] at written
              cases entry with
              | mk entryId contents =>
                  cases contents with
                  | none => simp at written
                  | some rootValue =>
                      simp only at written
                      cases replaced : replaceProjectedValue rootValue
                          (projection :: projections) replacement with
                      | error reason => rw [replaced] at written; cases written
                      | ok updated =>
                          rw [replaced] at written
                          simp only at written
                          cases assigned : state.assignCell root updated with
                          | none => rw [assigned] at written; cases written
                          | some assignedState =>
                              rw [assigned] at written
                              cases written
                              exact assignCell_preserves_heap_and_views assigned

theorem writeResolvedPlace_preserves_runtime_type
    (typed : RuntimeStateHasType program context state store)
    (placeTyped : ResolvedPlaceHasType program state store place type)
    (replacementTyped : ValueHasType program replacement type)
    (replacementBorrows : BorrowsValid program state store replacement)
    (written : writeResolvedPlace state place replacement = .ok next) :
    RuntimeStateHasType program context next store := by
  have nextTyped := writeResolvedPlace_preserves_state_typing typed.typed
    placeTyped replacementTyped replacementBorrows written
  have cellsPreserved := writeResolvedPlace_preserves_initialized_cells written
  have metadata := writeResolvedPlace_preserves_heap_and_views written
  refine ⟨nextTyped, ?_⟩
  apply typed.views.preserve (StoreExtends.refl store) cellsPreserved nextTyped
  · exact metadata.2
  · intro oldView member valid
    simpa only [metadata.1] using valid

theorem writeI32ArrayView_preserves_runtime_type
    (typed : RuntimeStateHasType program context state store)
    (viewTyped : I32ArrayViewPlaceHasType program state store view)
    (replacementTyped : ValueHasType program replacement
      (.array (.scalar (.signed .i32)) view.length))
    (replacementBorrows : BorrowsValid program state store replacement)
    (written : writeResolvedPlace state
      { root := view.root, projections := view.projections, value := none }
      replacement = .ok next) :
    RuntimeStateHasType program context next store := by
  have nextTyped := writeI32ArrayView_preserves_state_typing typed.typed
    viewTyped replacementTyped replacementBorrows written
  have cellsPreserved := writeResolvedPlace_preserves_initialized_cells written
  have metadata := writeResolvedPlace_preserves_heap_and_views written
  refine ⟨nextTyped, ?_⟩
  apply typed.views.preserve (StoreExtends.refl store) cellsPreserved nextTyped
  · exact metadata.2
  · intro oldView member valid
    simpa only [metadata.1] using valid

theorem syncI32ViewsFromHeapFrom_preserves_runtime_type
    (typed : RuntimeStateHasType program context state store)
    (registered : ∀ view, view ∈ pending → view ∈ state.i32ArrayViews)
    (synced : syncI32ViewsFromHeapFrom pending state = .ok afterState) :
    RuntimeStateHasType program context afterState store := by
  induction pending generalizing state with
  | nil =>
      simp only [syncI32ViewsFromHeapFrom, Except.ok.injEq] at synced
      subst afterState
      exact typed
  | cons view rest induction =>
      have viewRegistered : view ∈ state.i32ArrayViews :=
        registered view (by simp)
      have viewValid := typed.views view viewRegistered
      simp only [syncI32ViewsFromHeapFrom] at synced
      cases loaded : state.heap.loadBytes view.address (view.length * 4) with
      | error reason => simp [loaded] at synced
      | ok bytes =>
          simp [loaded] at synced
          cases decoded : decodeI32Array view.length bytes with
          | error reason => simp [decoded] at synced
          | ok elements =>
              simp [decoded] at synced
              cases written : writeResolvedPlace state
                  { root := view.root, projections := view.projections,
                    value := none }
                  (.array elements) with
              | error reason => simp [written] at synced
              | ok next =>
                  simp [written] at synced
                  have replacementTyped := decodeI32Array_has_type
                    (program := program) decoded
                  have replacementBorrows : BorrowsValid program state store
                      (.array elements) :=
                    (decodeI32Array_is_closed decoded).borrowsValid
                      (program := program) (state := state) (store := store)
                  have nextTyped := writeI32ArrayView_preserves_runtime_type
                    typed viewValid.1 replacementTyped replacementBorrows written
                  have metadata :=
                    writeResolvedPlace_preserves_heap_and_views written
                  have restRegistered : ∀ candidate, candidate ∈ rest →
                      candidate ∈ next.i32ArrayViews := by
                    intro candidate member
                    rw [metadata.2]
                    exact registered candidate (by simp [member])
                  exact induction nextTyped restRegistered synced

theorem syncI32ViewsFromHeap_preserves_runtime_type
    (typed : RuntimeStateHasType program context state store)
    (synced : syncI32ViewsFromHeap state = .ok afterState) :
    RuntimeStateHasType program context afterState store := by
  apply syncI32ViewsFromHeapFrom_preserves_runtime_type typed
  · intro view member
    exact member
  · exact synced

theorem syncI32ViewsFromHeapFrom_preserves_initialized_cells
    (synced : syncI32ViewsFromHeapFrom pending state = .ok afterState) :
    InitializedCellsPreserved state afterState := by
  induction pending generalizing state with
  | nil =>
      simp only [syncI32ViewsFromHeapFrom, Except.ok.injEq] at synced
      subst afterState
      exact .refl state
  | cons view rest induction =>
      simp only [syncI32ViewsFromHeapFrom] at synced
      cases loaded : state.heap.loadBytes view.address (view.length * 4) with
      | error reason => simp [loaded] at synced
      | ok bytes =>
          simp [loaded] at synced
          cases decoded : decodeI32Array view.length bytes with
          | error reason => simp [decoded] at synced
          | ok elements =>
              simp [decoded] at synced
              cases written : writeResolvedPlace state
                  { root := view.root, projections := view.projections,
                    value := none }
                  (.array elements) with
              | error reason => simp [written] at synced
              | ok next =>
                  simp [written] at synced
                  exact (writeResolvedPlace_preserves_initialized_cells
                    written).trans (induction synced)

theorem syncI32ViewsFromHeap_preserves_initialized_cells
    (synced : syncI32ViewsFromHeap state = .ok afterState) :
    InitializedCellsPreserved state afterState :=
  syncI32ViewsFromHeapFrom_preserves_initialized_cells synced

theorem storeByte_has_runtime_type
    (typed : RuntimeStateHasType program context state store) :
    RuntimeValueOutcomeHasType program context store
      (match state.heap.storeByte pointer offset byte with
      | .error reason => .trapped reason state
      | .ok heap =>
          match syncI32ViewsFromHeap { state with heap } with
          | .ok updated => .done .unit updated
          | .error reason => .trapped reason { state with heap })
      .unit := by
  cases stored : state.heap.storeByte pointer offset byte with
  | error reason =>
      simp only [stored, RuntimeValueOutcomeHasType]
      exact typed
  | ok heap =>
      have heapWellFormed := storeByte_preserves_heap_well_formed
        typed.typed.wellFormed.heapWellFormed stored
      have blocksPreserved := storeByte_preserves_i32_array_view_blocks
        (views := state.i32ArrayViews)
          typed.typed.wellFormed.heapWellFormed stored
      have heapTyped := typed.withHeap heap heapWellFormed blocksPreserved
      cases synced : syncI32ViewsFromHeap { state with heap } with
      | error reason =>
          simp only [stored, synced, RuntimeValueOutcomeHasType]
          exact heapTyped
      | ok updated =>
          simp only [stored, synced, RuntimeValueOutcomeHasType]
          have updatedTyped := syncI32ViewsFromHeap_preserves_runtime_type
            heapTyped synced
          refine ⟨updatedTyped, .unit, ?_⟩
          intro descriptor member
          simp [valueBorrows] at member

theorem reallocateOutcome_preserves_initialized_cells
    (state : State) (pointer : Address) (oldSize newSize alignment : Nat) :
    ValueOutcomePreservesInitializedCells state
      (match state.heap.reallocate pointer oldSize newSize alignment with
      | .allocated replacement heap =>
          .done (.pointer replacement) { state with heap }
      | .exhausted heap => .done (.pointer null) { state with heap }
      | .trapped reason heap => .trapped reason { state with heap }) := by
  cases state.heap.reallocate pointer oldSize newSize alignment with
  | allocated replacement heap | exhausted heap | trapped reason heap =>
      exact InitializedCellsPreserved.withHeap state heap

theorem deallocateOutcome_preserves_initialized_cells
    (state : State) (pointer : Address) (size alignment : Nat) :
    ValueOutcomePreservesInitializedCells state
      (match state.heap.deallocate pointer size alignment with
      | .ok heap => .done .unit { state with heap }
      | .error reason => .trapped reason state) := by
  cases state.heap.deallocate pointer size alignment with
  | error reason => exact InitializedCellsPreserved.refl state
  | ok heap => exact InitializedCellsPreserved.withHeap state heap

theorem loadByteOutcome_preserves_initialized_cells
    (state : State) (pointer : Address) (offset : Nat) :
    ValueOutcomePreservesInitializedCells state
      (match state.heap.loadByte pointer offset with
      | .ok value => .done (.unsigned .u8 value.toNat) state
      | .error reason => .trapped reason state) := by
  cases state.heap.loadByte pointer offset <;>
    exact InitializedCellsPreserved.refl state

theorem storeByteOutcome_preserves_initialized_cells
    (state : State) (pointer : Address) (offset : Nat) (byte : UInt8) :
    ValueOutcomePreservesInitializedCells state
      (match state.heap.storeByte pointer offset byte with
      | .error reason => .trapped reason state
      | .ok heap =>
          match syncI32ViewsFromHeap { state with heap } with
          | .ok updated => .done .unit updated
          | .error reason => .trapped reason { state with heap }) := by
  cases stored : state.heap.storeByte pointer offset byte with
  | error reason =>
      simp only
      exact InitializedCellsPreserved.refl state
  | ok heap =>
      simp only
      have heapCells := InitializedCellsPreserved.withHeap state heap
      cases synced : syncI32ViewsFromHeap { state with heap } with
      | error reason =>
          simp only
          exact heapCells
      | ok updated =>
          simp only
          exact heapCells.trans
            (syncI32ViewsFromHeap_preserves_initialized_cells synced)

/-- The semantic contract implemented by a modeled host service. Foreign code
    may update the world and bytes in existing allocations, but it may neither
    corrupt heap geometry nor invalidate a registered borrowed view. Returned
    values are closed because a host service cannot manufacture stable Lanius
    cell identities. -/
def WorldEffectResultHasType
    (program : Program) (views : List I32ArrayView) (beforeHeap : Heap)
    (result : World.EffectResult) (returnType : Ty) : Prop :=
  match result with
  | .returned value heap _ =>
      HeapWellFormed heap ∧
        I32ArrayViewBlocksPreserved views beforeHeap heap ∧
        ValueHasType program value returnType ∧ ValueIsClosed value
  | .exited _ heap _ | .unavailable _ heap _ | .trapped _ heap _
  | .typeMismatch heap _ =>
      HeapWellFormed heap ∧
        I32ArrayViewBlocksPreserved views beforeHeap heap

theorem WorldEffectResultHasType.returned
    (heapWellFormed : HeapWellFormed afterHeap)
    (blocksPreserved : I32ArrayViewBlocksPreserved views beforeHeap afterHeap)
    (valueTyped : ValueHasType program value returnType)
    (valueClosed : ValueIsClosed value) :
    WorldEffectResultHasType program views beforeHeap
      (.returned value afterHeap world) returnType := by
  exact ⟨heapWellFormed, blocksPreserved, valueTyped, valueClosed⟩

theorem WorldEffectResultHasType.i32
    (heapWellFormed : HeapWellFormed afterHeap)
    (blocksPreserved : I32ArrayViewBlocksPreserved views beforeHeap afterHeap) :
    WorldEffectResultHasType program views beforeHeap
      (.returned (World.i32Result value) afterHeap world)
      (.scalar (.signed .i32)) := by
  exact .returned heapWellFormed blocksPreserved
    (World.i32Result_has_type program value) (World.i32Result_is_closed value)

theorem WorldEffectResultHasType.exited
    (heapWellFormed : HeapWellFormed afterHeap)
    (blocksPreserved : I32ArrayViewBlocksPreserved views beforeHeap afterHeap) :
    WorldEffectResultHasType program views beforeHeap
      (.exited code afterHeap world) returnType := by
  exact ⟨heapWellFormed, blocksPreserved⟩

theorem WorldEffectResultHasType.unavailable
    (heapWellFormed : HeapWellFormed afterHeap)
    (blocksPreserved : I32ArrayViewBlocksPreserved views beforeHeap afterHeap) :
    WorldEffectResultHasType program views beforeHeap
      (.unavailable service afterHeap world) returnType := by
  exact ⟨heapWellFormed, blocksPreserved⟩

theorem WorldEffectResultHasType.trapped
    (heapWellFormed : HeapWellFormed afterHeap)
    (blocksPreserved : I32ArrayViewBlocksPreserved views beforeHeap afterHeap) :
    WorldEffectResultHasType program views beforeHeap
      (.trapped reason afterHeap world) returnType := by
  exact ⟨heapWellFormed, blocksPreserved⟩

theorem WorldEffectResultHasType.typeMismatch
    (heapWellFormed : HeapWellFormed afterHeap)
    (blocksPreserved : I32ArrayViewBlocksPreserved views beforeHeap afterHeap) :
    WorldEffectResultHasType program views beforeHeap
      (.typeMismatch afterHeap world) returnType := by
  exact ⟨heapWellFormed, blocksPreserved⟩

theorem World.copyToHeap_preserves_heap_and_views
    (count : Nat)
    (wellFormed : HeapWellFormed heap)
    (copied : World.copyToHeap heap pointer capacity bytes =
      .ok (count, afterHeap)) :
    HeapWellFormed afterHeap ∧
      I32ArrayViewBlocksPreserved views heap afterHeap := by
  simp only [World.copyToHeap] at copied
  cases stored : heap.storeBytes pointer (bytes.take (min capacity bytes.length)) with
  | error reason => simp [stored] at copied
  | ok next =>
      rw [stored] at copied
      cases copied
      exact ⟨storeBytes_preserves_heap_well_formed wellFormed stored,
        storeBytes_preserves_i32_array_view_blocks wellFormed stored⟩

def OpaqueCallResultHasType
    (program : Program) (result : World.OpaqueCallResult)
    (returnType : Ty) : Prop :=
  match result with
  | .returned value _ =>
      ValueHasType program value returnType ∧ ValueIsClosed value
  | .trapped _ _ | .unmodeled _ => True

def WorldCallResultHasType
    (program : Program) (result : World.CallResult) (returnType : Ty) : Prop :=
  match result with
  | .returned value _ =>
      ValueHasType program value returnType ∧ ValueIsClosed value
  | .exited _ _ | .unavailable _ _ | .trapped _ _ | .typeMismatch _ => True

theorem valuesHaveTypes_nil_shape
    (typed : ValuesHaveTypes program values []) : values = [] := by
  cases typed
  rfl

theorem valuesHaveTypes_i32_shape
    (typed : ValuesHaveTypes program values [(.scalar (.signed .i32))]) :
    ∃ value, values = [.signed .i32 value] := by
  cases typed with
  | cons head tail =>
      cases head with
      | signed type value lower upper =>
          cases tail
          exact ⟨value, rfl⟩

theorem valuesHaveTypes_i32_i32_shape
    (typed : ValuesHaveTypes program values
      [(.scalar (.signed .i32)), (.scalar (.signed .i32))]) :
    ∃ first second, values = [.signed .i32 first, .signed .i32 second] := by
  cases typed with
  | cons firstTyped rest =>
      cases firstTyped with
      | signed firstType first lower upper =>
          cases rest with
          | cons secondTyped tail =>
              cases secondTyped with
              | signed secondType second secondLower secondUpper =>
                  cases tail
                  exact ⟨first, second, rfl⟩

theorem valuesHaveTypes_i32_string_shape
    (typed : ValuesHaveTypes program values
      [(.scalar (.signed .i32)), (.scalar .string)]) :
    ∃ first text, values = [.signed .i32 first, .string text] := by
  cases typed with
  | cons firstTyped rest =>
      cases firstTyped with
      | signed firstType first lower upper =>
          cases rest with
          | cons textTyped tail =>
              cases textTyped with
              | string text =>
                  cases tail
                  exact ⟨first, text, rfl⟩

theorem valuesHaveTypes_string_shape
    (typed : ValuesHaveTypes program values [(.scalar .string)]) :
    ∃ text, values = [.string text] := by
  cases typed with
  | cons head tail =>
      cases head with
      | string text =>
          cases tail
          exact ⟨text, rfl⟩

theorem valuesHaveTypes_usize_usize_shape
    (typed : ValuesHaveTypes program values
      [(.scalar (.unsigned .usize)), (.scalar (.unsigned .usize))]) :
    ∃ first second,
      values = [.unsigned .usize first, .unsigned .usize second] := by
  cases typed with
  | cons firstTyped rest =>
      cases firstTyped with
      | unsigned firstType first upper =>
          cases rest with
          | cons secondTyped tail =>
              cases secondTyped with
              | unsigned secondType second secondUpper =>
                  cases tail
                  exact ⟨first, second, rfl⟩

theorem valueHasType_usize_shape
    (typed : ValueHasType program value (.scalar (.unsigned .usize))) :
    ∃ number, value = .unsigned .usize number := by
  cases typed with
  | unsigned type number upper =>
      exact ⟨number, rfl⟩

theorem valuesHaveTypes_ptr_usize_shape
    (typed : ValuesHaveTypes program values
      [(.scalar .rawPtr), (.scalar (.unsigned .usize))]) :
    ∃ pointer size, values = [.pointer pointer, .unsigned .usize size] := by
  cases typed with
  | cons pointerTyped rest =>
      cases pointerTyped with
      | pointer pointer =>
          cases rest with
          | cons sizeTyped tail =>
              cases sizeTyped with
              | unsigned sizeType size upper =>
                  cases tail
                  exact ⟨pointer, size, rfl⟩

theorem valuesHaveTypes_ptr_usize_usize_shape
    (typed : ValuesHaveTypes program values
      [(.scalar .rawPtr), (.scalar (.unsigned .usize)),
        (.scalar (.unsigned .usize))]) :
    ∃ pointer first second,
      values = [.pointer pointer, .unsigned .usize first,
        .unsigned .usize second] := by
  cases typed with
  | cons pointerTyped rest =>
      cases pointerTyped with
      | pointer pointer =>
          cases rest with
          | cons firstTyped rest =>
              cases firstTyped with
              | unsigned firstType first firstUpper =>
                  cases rest with
                  | cons secondTyped tail =>
                      cases secondTyped with
                      | unsigned secondType second secondUpper =>
                          cases tail
                          exact ⟨pointer, first, second, rfl⟩

theorem valuesHaveTypes_ptr_usize_u8_shape
    (typed : ValuesHaveTypes program values
      [(.scalar .rawPtr), (.scalar (.unsigned .usize)),
        (.scalar (.unsigned .u8))]) :
    ∃ pointer offset byte,
      values = [.pointer pointer, .unsigned .usize offset,
        .unsigned .u8 byte] := by
  cases typed with
  | cons pointerTyped rest =>
      cases pointerTyped with
      | pointer pointer =>
          cases rest with
          | cons offsetTyped rest =>
              cases offsetTyped with
              | unsigned offsetType offset offsetUpper =>
                  cases rest with
                  | cons byteTyped tail =>
                      cases byteTyped with
                      | unsigned byteType byte byteUpper =>
                          cases tail
                          exact ⟨pointer, offset, byte, rfl⟩

theorem valuesHaveTypes_ptr_usize_usize_usize_shape
    (typed : ValuesHaveTypes program values
      [(.scalar .rawPtr), (.scalar (.unsigned .usize)),
        (.scalar (.unsigned .usize)), (.scalar (.unsigned .usize))]) :
    ∃ pointer first second third,
      values = [.pointer pointer, .unsigned .usize first,
        .unsigned .usize second, .unsigned .usize third] := by
  cases typed with
  | cons pointerTyped rest =>
      cases pointerTyped with
      | pointer pointer =>
          cases rest with
          | cons firstTyped rest =>
              cases firstTyped with
              | unsigned firstType first firstUpper =>
                  cases rest with
                  | cons secondTyped rest =>
                      cases secondTyped with
                      | unsigned secondType second secondUpper =>
                          cases rest with
                          | cons thirdTyped tail =>
                              cases thirdTyped with
                              | unsigned thirdType third thirdUpper =>
                                  cases tail
                                  exact ⟨pointer, first, second, third, rfl⟩

theorem valuesHaveTypes_i32_ptr_usize_shape
    (typed : ValuesHaveTypes program values
      [(.scalar (.signed .i32)), (.scalar .rawPtr),
        (.scalar (.unsigned .usize))]) :
    ∃ first pointer size,
      values = [.signed .i32 first, .pointer pointer,
        .unsigned .usize size] := by
  cases typed with
  | cons firstTyped rest =>
      cases firstTyped with
      | signed firstType first lower upper =>
          cases rest with
          | cons pointerTyped rest =>
              cases pointerTyped with
              | pointer pointer =>
                  cases rest with
                  | cons sizeTyped tail =>
                      cases sizeTyped with
                      | unsigned sizeType size sizeUpper =>
                          cases tail
                          exact ⟨first, pointer, size, rfl⟩

theorem valuesHaveTypes_ptr_usize_ptr_usize_shape
    (typed : ValuesHaveTypes program values
      [(.scalar .rawPtr), (.scalar (.unsigned .usize)),
        (.scalar .rawPtr), (.scalar (.unsigned .usize))]) :
    ∃ firstPointer firstSize secondPointer secondSize,
      values = [.pointer firstPointer, .unsigned .usize firstSize,
        .pointer secondPointer, .unsigned .usize secondSize] := by
  cases typed with
  | cons firstPointerTyped rest =>
      cases firstPointerTyped with
      | pointer firstPointer =>
          cases rest with
          | cons firstSizeTyped rest =>
              cases firstSizeTyped with
              | unsigned firstSizeType firstSize firstUpper =>
                  cases rest with
                  | cons secondPointerTyped rest =>
                      cases secondPointerTyped with
                      | pointer secondPointer =>
                          cases rest with
                          | cons secondSizeTyped tail =>
                              cases secondSizeTyped with
                              | unsigned secondSizeType secondSize secondUpper =>
                                  cases tail
                                  exact ⟨firstPointer, firstSize,
                                    secondPointer, secondSize, rfl⟩

theorem World.callSimple_has_type
    (argumentsTyped : ValuesHaveTypes program arguments service.parameterTypes) :
    WorldCallResultHasType program (World.callSimple world service arguments)
      service.returnType := by
  cases service <;>
    simp only [HostService.parameterTypes] at argumentsTyped
  case writeText =>
    obtain ⟨handle, text, rfl⟩ := valuesHaveTypes_i32_string_shape argumentsTyped
    simp only [World.callSimple]
    split <;> simp [WorldCallResultHasType, HostService.returnType,
      World.i32Result_has_type, World.i32Result_is_closed,
      ValueIsClosed, valueBorrows]
  case writeI32 =>
    obtain ⟨handle, value, rfl⟩ := valuesHaveTypes_i32_i32_shape argumentsTyped
    simp only [World.callSimple]
    split <;> simp [WorldCallResultHasType, HostService.returnType,
      World.i32Result_has_type, World.i32Result_is_closed,
      ValueIsClosed, valueBorrows]
  case writeByte =>
    obtain ⟨handle, value, rfl⟩ := valuesHaveTypes_i32_i32_shape argumentsTyped
    simp only [World.callSimple]
    split <;> simp [WorldCallResultHasType, HostService.returnType,
      World.i32Result_has_type, World.i32Result_is_closed,
      ValueIsClosed, valueBorrows]
  case writeNewline =>
    obtain ⟨handle, rfl⟩ := valuesHaveTypes_i32_shape argumentsTyped
    simp only [World.callSimple]
    split <;> simp [WorldCallResultHasType, HostService.returnType,
      World.i32Result_has_type, World.i32Result_is_closed,
      ValueIsClosed, valueBorrows]
  case i32ToF32 =>
    obtain ⟨value, rfl⟩ := valuesHaveTypes_i32_shape argumentsTyped
    simp [World.callSimple, WorldCallResultHasType, HostService.returnType,
      ValueIsClosed, valueBorrows]
    exact .f32Bits _
  case exit =>
    obtain ⟨code, rfl⟩ := valuesHaveTypes_i32_shape argumentsTyped
    simp [World.callSimple, WorldCallResultHasType, HostService.returnType]
  case secureU32 =>
    have empty := valuesHaveTypes_nil_shape argumentsTyped
    subst arguments
    cases stream : world.secureU32Stream with
    | nil =>
        simp [World.callSimple, World.record, stream,
          WorldCallResultHasType, HostService.returnType]
    | cons value rest =>
        simp only [World.callSimple, World.record, stream,
          WorldCallResultHasType, HostService.returnType]
        refine ⟨.unsigned .u32 _ ?_, rfl⟩
        have bounded := wrapUnsigned_le_max program.target .u32 value
        simpa [wrapUnsigned, unsignedModulus, unsignedMax,
          UnsignedIntTy.bits] using bounded
  case argc =>
    have empty := valuesHaveTypes_nil_shape argumentsTyped
    subst arguments
    simp [World.callSimple, WorldCallResultHasType,
      HostService.returnType, World.i32Result_has_type,
      World.i32Result_is_closed, ValueIsClosed, valueBorrows]
  case argLen =>
    obtain ⟨index, rfl⟩ := valuesHaveTypes_i32_shape argumentsTyped
    by_cases negative : index < 0
    · simp [World.callSimple, negative, WorldCallResultHasType,
        HostService.returnType, World.i32Result_has_type,
        World.i32Result_is_closed, ValueIsClosed, valueBorrows]
    · cases found : world.arguments[index.toNat]? with
      | none =>
          simp [World.callSimple, World.record, negative, found,
            WorldCallResultHasType, HostService.returnType,
            World.i32Result_has_type, World.i32Result_is_closed,
            ValueIsClosed, valueBorrows]
      | some value =>
          simp [World.callSimple, World.record, negative, found,
            WorldCallResultHasType, HostService.returnType,
            World.i32Result_has_type, World.i32Result_is_closed,
            ValueIsClosed, valueBorrows]
  case unixSeconds =>
    have empty := valuesHaveTypes_nil_shape argumentsTyped
    subst arguments
    simp [World.callSimple, WorldCallResultHasType,
      HostService.returnType, World.i32Result_has_type,
      World.i32Result_is_closed, ValueIsClosed, valueBorrows]
  case sleepMsI32 =>
    obtain ⟨milliseconds, rfl⟩ := valuesHaveTypes_i32_shape argumentsTyped
    by_cases negative : milliseconds < 0 <;>
      simp [World.callSimple, negative, WorldCallResultHasType,
        HostService.returnType, World.i32Result_has_type,
        World.i32Result_is_closed, ValueIsClosed, valueBorrows]
  all_goals simp [World.callSimple, WorldCallResultHasType,
    HostService.returnType]

theorem World.call_has_type
    (heapWellFormed : HeapWellFormed heap)
    (argumentsTyped : ValuesHaveTypes program arguments service.parameterTypes) :
    WorldEffectResultHasType program views heap
      (World.call heap world service arguments) service.returnType := by
  have unchanged := I32ArrayViewBlocksPreserved.refl heap views
  have simpleTyped := World.callSimple_has_type
    (world := world) argumentsTyped
  cases simple : World.callSimple world service arguments with
  | returned value next =>
      rw [simple] at simpleTyped
      simp only [World.call, simple]
      exact .returned heapWellFormed unchanged simpleTyped.1 simpleTyped.2
  | exited code next =>
      simp only [World.call, simple]
      exact .exited heapWellFormed unchanged
  | trapped reason next =>
      simp only [World.call, simple]
      exact .trapped heapWellFormed unchanged
  | typeMismatch next =>
      simp only [World.call, simple]
      exact .typeMismatch heapWellFormed unchanged
  | unavailable unavailableService next =>
      cases service <;>
        simp only [HostService.parameterTypes] at argumentsTyped
      case openReadPath | openWritePath =>
        obtain ⟨text, rfl⟩ := valuesHaveTypes_string_shape argumentsTyped
        simp [World.call, simple, WorldEffectResultHasType,
          HostService.returnType, heapWellFormed, unchanged,
          World.i32Result_has_type, World.i32Result_is_closed,
          ValueIsClosed, valueBorrows]
      case readI32 =>
        obtain ⟨first, second, rfl⟩ :=
          valuesHaveTypes_i32_i32_shape argumentsTyped
        simp [World.call, simple, WorldEffectResultHasType,
          HostService.returnType, heapWellFormed, unchanged,
          World.i32Result_has_type, World.i32Result_is_closed,
          ValueIsClosed, valueBorrows]
      case writeI32 =>
        obtain ⟨handle, value, rfl⟩ :=
          valuesHaveTypes_i32_i32_shape argumentsTyped
        simp only [World.call, simple]
        cases written : World.writeFileBytes next handle (World.utf8Bytes (toString value)) <;>
          simp [written, WorldEffectResultHasType, HostService.returnType,
            heapWellFormed, unchanged, World.i32Result_has_type,
            World.i32Result_is_closed, ValueIsClosed, valueBorrows]
      case writeByte =>
        obtain ⟨handle, value, rfl⟩ :=
          valuesHaveTypes_i32_i32_shape argumentsTyped
        simp only [World.call, simple]
        cases written : World.writeFileBytes next handle
            [UInt8.ofNat (Int.toNat (value % 256))] <;>
          simp [written, WorldEffectResultHasType, HostService.returnType,
            heapWellFormed, unchanged, World.i32Result_has_type,
            World.i32Result_is_closed, ValueIsClosed, valueBorrows]
      case writeText =>
        obtain ⟨handle, text, rfl⟩ :=
          valuesHaveTypes_i32_string_shape argumentsTyped
        simp only [World.call, simple]
        cases written : World.writeFileBytes next handle (World.utf8Bytes text) <;>
          simp [written, WorldEffectResultHasType, HostService.returnType,
            heapWellFormed, unchanged, World.i32Result_has_type,
            World.i32Result_is_closed, ValueIsClosed, valueBorrows]
      case writeNewline =>
        obtain ⟨handle, rfl⟩ := valuesHaveTypes_i32_shape argumentsTyped
        simp only [World.call, simple]
        cases written : World.writeFileBytes next handle [10] <;>
          simp [written, WorldEffectResultHasType, HostService.returnType,
            heapWellFormed, unchanged, World.i32Result_has_type,
            World.i32Result_is_closed, ValueIsClosed, valueBorrows]
      case closeFile | close =>
        obtain ⟨handle, rfl⟩ := valuesHaveTypes_i32_shape argumentsTyped
        simp only [World.call, simple]
        cases closed : World.closeHandle next handle <;>
          simp [closed, WorldEffectResultHasType, HostService.returnType,
            heapWellFormed, unchanged, World.i32Result_has_type,
            World.i32Result_is_closed, ValueIsClosed, valueBorrows]
      case varKeyLen =>
        obtain ⟨index, rfl⟩ := valuesHaveTypes_i32_shape argumentsTyped
        simp only [World.call, simple]
        by_cases negative : index < 0
        · simp [negative, WorldEffectResultHasType, HostService.returnType,
            heapWellFormed, unchanged, World.i32Result_has_type,
            World.i32Result_is_closed, ValueIsClosed, valueBorrows]
        · cases found : next.environment[index.toNat]? <;>
            simp [negative, found, WorldEffectResultHasType,
              HostService.returnType, heapWellFormed, unchanged,
              World.i32Result_has_type, World.i32Result_is_closed,
              ValueIsClosed, valueBorrows]
      case i32ToF32 | exit =>
        obtain ⟨value, rfl⟩ := valuesHaveTypes_i32_shape argumentsTyped
        simp [World.callSimple] at simple
      case argLen =>
        obtain ⟨index, rfl⟩ := valuesHaveTypes_i32_shape argumentsTyped
        by_cases negative : index < 0
        · simp [World.callSimple, negative] at simple
        · cases found : world.arguments[index.toNat]? <;>
            simp [World.callSimple, World.record, negative, found] at simple
      case sleepMsI32 =>
        obtain ⟨milliseconds, rfl⟩ := valuesHaveTypes_i32_shape argumentsTyped
        by_cases negative : milliseconds < 0 <;>
          simp [World.callSimple, negative] at simple
      case secureU32 | argc | unixSeconds | varCount =>
        have empty := valuesHaveTypes_nil_shape argumentsTyped
        subst arguments
        simp [World.call, simple, WorldEffectResultHasType,
          HostService.returnType, heapWellFormed, unchanged,
          World.i32Result_has_type, World.i32Result_is_closed,
          ValueIsClosed, valueBorrows]
      case alloc =>
        obtain ⟨first, second, rfl⟩ :=
          valuesHaveTypes_usize_usize_shape argumentsTyped
        simp only [World.call, simple]
        cases allocated : heap.allocate first second with
        | allocated pointer afterHeap =>
            have afterWellFormed : HeapWellFormed afterHeap := by
              have preserved := allocate_preserves_heap_well_formed
                heapWellFormed (size := first) (alignment := second)
              rw [allocated] at preserved
              exact preserved
            have afterViews := allocate_preserves_i32_array_view_blocks
              (views := views) allocated
            exact .returned afterWellFormed afterViews (.pointer pointer)
              (show ValueIsClosed (.pointer pointer) by rfl)
        | exhausted afterHeap =>
            have heapEq := allocate_exhausted_heap_eq heap afterHeap first second
              allocated
            subst afterHeap
            exact .returned heapWellFormed unchanged (.pointer null)
              (show ValueIsClosed (.pointer null) by rfl)
        | trapped reason afterHeap =>
            have heapEq := allocate_trapped_heap_eq heap afterHeap first second
              reason allocated
            subst afterHeap
            exact .trapped heapWellFormed unchanged
      case allocFailed =>
        obtain ⟨first, second, rfl⟩ :=
          valuesHaveTypes_usize_usize_shape argumentsTyped
        simp [World.call, simple]
        exact .trapped heapWellFormed unchanged
      case dealloc =>
        obtain ⟨pointer, size, alignment, rfl⟩ :=
          valuesHaveTypes_ptr_usize_usize_shape argumentsTyped
        simp only [World.call, simple]
        cases deallocated : heap.deallocate pointer size alignment with
        | error reason => exact .trapped heapWellFormed unchanged
        | ok afterHeap =>
            have afterWellFormed := deallocate_preserves_heap_well_formed
              heapWellFormed deallocated
            have afterViews := deallocate_preserves_i32_array_view_blocks
              (views := views) heapWellFormed deallocated
            exact .returned afterWellFormed afterViews .unit rfl
      case realloc =>
        obtain ⟨pointer, oldSize, newSize, alignment, rfl⟩ :=
          valuesHaveTypes_ptr_usize_usize_usize_shape argumentsTyped
        simp only [World.call, simple]
        cases reallocated : heap.reallocate pointer oldSize newSize alignment with
        | allocated replacement afterHeap =>
            have afterWellFormed : HeapWellFormed afterHeap := by
              have preserved := reallocate_preserves_heap_well_formed
                (pointer := pointer) (oldSize := oldSize) (newSize := newSize)
                  (alignment := alignment) heapWellFormed
              rw [reallocated] at preserved
              exact preserved
            have afterViews := reallocate_preserves_i32_array_view_blocks
              (views := views) heapWellFormed reallocated
            exact .returned afterWellFormed afterViews (.pointer replacement)
              (show ValueIsClosed (.pointer replacement) by rfl)
        | exhausted afterHeap =>
            have heapEq := reallocate_exhausted_heap_eq heap afterHeap pointer
              oldSize newSize alignment reallocated
            subst afterHeap
            exact .returned heapWellFormed unchanged (.pointer null)
              (show ValueIsClosed (.pointer null) by rfl)
        | trapped reason afterHeap =>
            have heapEq := reallocate_trapped_heap_eq heap afterHeap pointer
              oldSize newSize alignment reason reallocated
            subst afterHeap
            exact .trapped heapWellFormed unchanged
      case argRead =>
        obtain ⟨index, pointer, size, rfl⟩ :=
          valuesHaveTypes_i32_ptr_usize_shape argumentsTyped
        simp only [World.call, simple]
        by_cases negative : index < 0
        · simp only [negative, ↓reduceIte]
          exact .i32 heapWellFormed unchanged
        · cases found : next.arguments[index.toNat]? with
          | none =>
              simp only [negative, Bool.false_eq_true, ↓reduceIte, found]
              exact .i32 heapWellFormed unchanged
          | some argument =>
              simp only [negative, Bool.false_eq_true, ↓reduceIte, found]
              cases copied : World.copyToHeap heap pointer size
                  (World.utf8Bytes argument) with
              | error reason =>
                  simp only [copied]
                  exact .trapped heapWellFormed unchanged
              | ok result =>
                  rcases result with ⟨count, afterHeap⟩
                  simp only [copied]
                  obtain ⟨afterWellFormed, afterViews⟩ :=
                    World.copyToHeap_preserves_heap_and_views count
                      heapWellFormed copied
                  exact .i32 afterWellFormed afterViews
      case varKeyRead =>
        obtain ⟨index, pointer, size, rfl⟩ :=
          valuesHaveTypes_i32_ptr_usize_shape argumentsTyped
        simp only [World.call, simple]
        by_cases negative : index < 0
        · simp only [negative, ↓reduceIte]
          exact .i32 heapWellFormed unchanged
        · cases found : next.environment[index.toNat]? with
          | none =>
              simp only [negative, Bool.false_eq_true, ↓reduceIte, found]
              exact .i32 heapWellFormed unchanged
          | some entry =>
              simp only [negative, Bool.false_eq_true, ↓reduceIte, found]
              cases copied : World.copyToHeap heap pointer size
                  (World.utf8Bytes entry.1) with
              | error reason =>
                  simp only [copied]
                  exact .trapped heapWellFormed unchanged
              | ok result =>
                  rcases result with ⟨count, afterHeap⟩
                  simp only [copied]
                  obtain ⟨afterWellFormed, afterViews⟩ :=
                    World.copyToHeap_preserves_heap_and_views count
                      heapWellFormed copied
                  exact .i32 afterWellFormed afterViews
      case read =>
        obtain ⟨handle, pointer, size, rfl⟩ :=
          valuesHaveTypes_i32_ptr_usize_shape argumentsTyped
        simp only [World.call, simple]
        cases readResult : World.readFileBytes next handle size with
        | none =>
            simp only [readResult]
            exact .i32 heapWellFormed unchanged
        | some result =>
            rcases result with ⟨bytes, readWorld⟩
            simp only [readResult]
            cases stored : heap.storeBytes pointer bytes with
            | error reason =>
                simp only [stored]
                exact .trapped heapWellFormed unchanged
            | ok afterHeap =>
                simp only [stored]
                have afterWellFormed := storeBytes_preserves_heap_well_formed
                  heapWellFormed stored
                have afterViews := storeBytes_preserves_i32_array_view_blocks
                  (views := views) heapWellFormed stored
                exact .i32 afterWellFormed afterViews
      case write =>
        obtain ⟨handle, pointer, size, rfl⟩ :=
          valuesHaveTypes_i32_ptr_usize_shape argumentsTyped
        simp only [World.call, simple]
        cases loaded : heap.loadBytes pointer size with
        | error reason =>
            simp only [loaded]
            exact .trapped heapWellFormed unchanged
        | ok bytes =>
            simp only [loaded]
            cases written : World.writeFileBytes next handle bytes <;>
              simp [written, WorldEffectResultHasType, HostService.returnType,
                heapWellFormed, unchanged, World.i32Result_has_type,
                World.i32Result_is_closed, ValueIsClosed, valueBorrows]
      case currentDirRead =>
        obtain ⟨pointer, size, rfl⟩ :=
          valuesHaveTypes_ptr_usize_shape argumentsTyped
        simp only [World.call, simple]
        cases copied : World.copyToHeap heap pointer size
            (World.utf8Bytes next.currentDirectory) with
        | error reason =>
            simp only [copied]
            exact .trapped heapWellFormed unchanged
        | ok result =>
            rcases result with ⟨count, afterHeap⟩
            simp only [copied]
            obtain ⟨afterWellFormed, afterViews⟩ :=
              World.copyToHeap_preserves_heap_and_views count heapWellFormed copied
            exact .i32 afterWellFormed afterViews
      case readStdin =>
        obtain ⟨pointer, size, rfl⟩ :=
          valuesHaveTypes_ptr_usize_shape argumentsTyped
        simp only [World.call, simple]
        let bytes := next.standardInput.take size
        cases stored : heap.storeBytes pointer bytes with
        | error reason =>
            simp only [bytes, stored]
            exact .trapped heapWellFormed unchanged
        | ok afterHeap =>
            simp only [bytes, stored]
            have afterWellFormed := storeBytes_preserves_heap_well_formed
              heapWellFormed stored
            have afterViews := storeBytes_preserves_i32_array_view_blocks
              (views := views) heapWellFormed stored
            exact .i32 afterWellFormed afterViews
      case fillSecureBytes =>
        obtain ⟨pointer, size, rfl⟩ :=
          valuesHaveTypes_ptr_usize_shape argumentsTyped
        simp only [World.call, simple]
        by_cases exhausted : next.secureByteStream.length < size
        · simp only [exhausted, ↓reduceIte]
          exact .trapped heapWellFormed unchanged
        · simp only [exhausted, Bool.false_eq_true, ↓reduceIte]
          cases stored : heap.storeBytes pointer
              (next.secureByteStream.take size) with
          | error reason =>
              simp only [stored]
              exact .trapped heapWellFormed unchanged
          | ok afterHeap =>
              simp only [stored]
              have afterWellFormed := storeBytes_preserves_heap_well_formed
                heapWellFormed stored
              have afterViews := storeBytes_preserves_i32_array_view_blocks
                (views := views) heapWellFormed stored
              exact .i32 afterWellFormed afterViews
      case monotonicRead =>
        obtain ⟨pointer, size, rfl⟩ :=
          valuesHaveTypes_ptr_usize_shape argumentsTyped
        simp only [World.call, simple]
        by_cases tooSmall : size < 16
        · simp only [tooSmall, ↓reduceIte]
          exact .i32 heapWellFormed unchanged
        · simp only [tooSmall, Bool.false_eq_true, ↓reduceIte]
          cases stored : heap.storeBytes pointer
              (World.timespecBytes next.monotonicSeconds
                next.monotonicNanoseconds) with
          | error reason =>
              simp only [stored]
              exact .trapped heapWellFormed unchanged
          | ok afterHeap =>
              simp only [stored]
              exact .i32 (storeBytes_preserves_heap_well_formed
                  heapWellFormed stored)
                (storeBytes_preserves_i32_array_view_blocks
                  (views := views) heapWellFormed stored)
      case systemRead =>
        obtain ⟨pointer, size, rfl⟩ :=
          valuesHaveTypes_ptr_usize_shape argumentsTyped
        simp only [World.call, simple]
        by_cases tooSmall : size < 16
        · simp only [tooSmall, ↓reduceIte]
          exact .i32 heapWellFormed unchanged
        · simp only [tooSmall, Bool.false_eq_true, ↓reduceIte]
          cases stored : heap.storeBytes pointer
              (World.timespecBytes next.systemSeconds
                next.systemNanoseconds) with
          | error reason =>
              simp only [stored]
              exact .trapped heapWellFormed unchanged
          | ok afterHeap =>
              simp only [stored]
              exact .i32 (storeBytes_preserves_heap_well_formed
                  heapWellFormed stored)
                (storeBytes_preserves_i32_array_view_blocks
                  (views := views) heapWellFormed stored)
      case openRead | openWrite | openAppend | writeStdout | writeStderr =>
        obtain ⟨pointer, size, rfl⟩ :=
          valuesHaveTypes_ptr_usize_shape argumentsTyped
        simp only [World.call, simple]
        cases loaded : heap.loadBytes pointer size with
        | error reason =>
            simp only [loaded]
            exact .trapped heapWellFormed unchanged
        | ok bytes =>
            simp [loaded, WorldEffectResultHasType, HostService.returnType,
              heapWellFormed, unchanged, World.i32Result_has_type,
              World.i32Result_is_closed, ValueIsClosed, valueBorrows]
      case varLen =>
        obtain ⟨pointer, size, rfl⟩ :=
          valuesHaveTypes_ptr_usize_shape argumentsTyped
        simp only [World.call, simple]
        cases loaded : heap.loadBytes pointer size with
        | error reason =>
            simp only [loaded]
            exact .trapped heapWellFormed unchanged
        | ok bytes =>
            simp only [loaded]
            cases found : World.environmentValue? next bytes <;>
              simp [found, WorldEffectResultHasType, HostService.returnType,
                heapWellFormed, unchanged, World.i32Result_has_type,
                World.i32Result_is_closed, ValueIsClosed, valueBorrows]
      case removeFile =>
        obtain ⟨pointer, size, rfl⟩ :=
          valuesHaveTypes_ptr_usize_shape argumentsTyped
        simp only [World.call, simple]
        cases loaded : heap.loadBytes pointer size with
        | error reason =>
            simp only [loaded]
            exact .trapped heapWellFormed unchanged
        | ok bytes =>
            simp only [loaded]
            cases found : next.file? bytes <;>
              simp [found, WorldEffectResultHasType, HostService.returnType,
                heapWellFormed, unchanged, World.i32Result_has_type,
                World.i32Result_is_closed, ValueIsClosed, valueBorrows]
      case createDir =>
        obtain ⟨pointer, size, rfl⟩ :=
          valuesHaveTypes_ptr_usize_shape argumentsTyped
        simp only [World.call, simple]
        cases loaded : heap.loadBytes pointer size with
        | error reason =>
            simp only [loaded]
            exact .trapped heapWellFormed unchanged
        | ok bytes =>
            simp only [loaded]
            split <;> simp_all [WorldEffectResultHasType,
              HostService.returnType, heapWellFormed, unchanged,
              World.i32Result_has_type, World.i32Result_is_closed,
              ValueIsClosed, valueBorrows]
      case removeDir =>
        obtain ⟨pointer, size, rfl⟩ :=
          valuesHaveTypes_ptr_usize_shape argumentsTyped
        simp only [World.call, simple]
        cases loaded : heap.loadBytes pointer size with
        | error reason =>
            simp only [loaded]
            exact .trapped heapWellFormed unchanged
        | ok bytes =>
            simp only [loaded]
            let nonempty := next.files.any
                (fun file => World.descendantPath bytes file.path) ||
              next.directories.any (World.descendantPath bytes)
            split <;> simp_all [nonempty, WorldEffectResultHasType,
              HostService.returnType, heapWellFormed, unchanged,
              World.i32Result_has_type, World.i32Result_is_closed,
              ValueIsClosed, valueBorrows]
      case varRead =>
        obtain ⟨firstPointer, firstSize, secondPointer, secondSize, rfl⟩ :=
          valuesHaveTypes_ptr_usize_ptr_usize_shape argumentsTyped
        simp only [World.call, simple]
        cases loaded : heap.loadBytes firstPointer firstSize with
        | error reason =>
            simp only [loaded]
            exact .trapped heapWellFormed unchanged
        | ok key =>
            simp only [loaded]
            cases found : World.environmentValue? next key with
            | none =>
                simp only [found]
                exact .i32 heapWellFormed unchanged
            | some value =>
                simp only [found]
                cases copied : World.copyToHeap heap secondPointer secondSize
                    (World.utf8Bytes value) with
                | error reason =>
                    simp only [copied]
                    exact .trapped heapWellFormed unchanged
                | ok result =>
                    rcases result with ⟨count, afterHeap⟩
                    simp only [copied]
                    obtain ⟨afterWellFormed, afterViews⟩ :=
                      World.copyToHeap_preserves_heap_and_views count
                        heapWellFormed copied
                    exact .i32 afterWellFormed afterViews
      case rename =>
        obtain ⟨firstPointer, firstSize, secondPointer, secondSize, rfl⟩ :=
          valuesHaveTypes_ptr_usize_ptr_usize_shape argumentsTyped
        simp only [World.call, simple]
        cases firstLoaded : heap.loadBytes firstPointer firstSize with
        | error reason =>
            simp only [firstLoaded]
            exact .trapped heapWellFormed unchanged
        | ok sourcePath =>
            cases secondLoaded : heap.loadBytes secondPointer secondSize with
            | error reason =>
                simp only [firstLoaded, secondLoaded]
                exact .trapped heapWellFormed unchanged
            | ok destinationPath =>
                simp only [firstLoaded, secondLoaded]
                split
                next samePath =>
                  split <;> exact .i32 heapWellFormed unchanged
                next differentPath =>
                  split
                  next destinationOccupied =>
                    exact .i32 heapWellFormed unchanged
                  next destinationFree =>
                    cases next.file? sourcePath with
                    | some file => exact .i32 heapWellFormed unchanged
                    | none =>
                        by_cases rejected :
                            (!next.directories.contains sourcePath ||
                              World.descendantPath sourcePath destinationPath) =
                                true
                        · simp only [rejected, if_true]
                          exact .i32 heapWellFormed unchanged
                        · simp only [rejected, if_false]
                          exact .i32 heapWellFormed unchanged

theorem worldCallOutcome_has_runtime_type
    (typed : RuntimeStateHasType program context state store)
    (effectTyped : WorldEffectResultHasType program state.i32ArrayViews
      state.heap effect returnType) :
    RuntimeValueOutcomeHasType program context store
      (worldCallOutcome functionId state effect) returnType := by
  cases effect with
  | returned value heap world =>
      obtain ⟨heapWellFormed, blocksPreserved, valueTyped, valueClosed⟩ :=
        effectTyped
      have heapWorldTyped : RuntimeStateHasType program context
          { state with heap, world } store := by
        have heapTyped := typed.withHeap heap heapWellFormed blocksPreserved
        simpa only using heapTyped.withWorld world
      cases synced : syncI32ViewsFromHeap { state with heap, world } with
      | error reason =>
          simp only [worldCallOutcome, synced, RuntimeValueOutcomeHasType]
          exact heapWorldTyped
      | ok next =>
          simp only [worldCallOutcome, synced, RuntimeValueOutcomeHasType]
          exact ⟨syncI32ViewsFromHeap_preserves_runtime_type
              heapWorldTyped synced,
            valueTyped, valueClosed.borrowsValid⟩
  | exited code heap world =>
      obtain ⟨heapWellFormed, blocksPreserved⟩ := effectTyped
      have heapWorldTyped : RuntimeStateHasType program context
          { state with heap, world } store := by
        have heapTyped := typed.withHeap heap heapWellFormed blocksPreserved
        simpa only using heapTyped.withWorld world
      cases synced : syncI32ViewsFromHeap { state with heap, world } with
      | error reason =>
          simp only [worldCallOutcome, synced, RuntimeValueOutcomeHasType]
          exact heapWorldTyped
      | ok next =>
          simp only [worldCallOutcome, synced, RuntimeValueOutcomeHasType]
          exact syncI32ViewsFromHeap_preserves_runtime_type heapWorldTyped synced
  | unavailable service heap world =>
      obtain ⟨heapWellFormed, blocksPreserved⟩ := effectTyped
      simp only [worldCallOutcome, RuntimeValueOutcomeHasType]
      have heapTyped := typed.withHeap heap heapWellFormed blocksPreserved
      simpa only using heapTyped.withWorld world
  | trapped reason heap world =>
      obtain ⟨heapWellFormed, blocksPreserved⟩ := effectTyped
      simp only [worldCallOutcome, RuntimeValueOutcomeHasType]
      have heapTyped := typed.withHeap heap heapWellFormed blocksPreserved
      simpa only using heapTyped.withWorld world
  | typeMismatch heap world =>
      obtain ⟨heapWellFormed, blocksPreserved⟩ := effectTyped
      simp only [worldCallOutcome, RuntimeValueOutcomeHasType]
      have heapTyped := typed.withHeap heap heapWellFormed blocksPreserved
      simpa only using heapTyped.withWorld world

theorem worldCallOutcome_preserves_initialized_cells :
    ValueOutcomePreservesInitializedCells state
      (worldCallOutcome functionId state effect) := by
  cases effect with
  | returned value heap world =>
      let changed : State := { state with heap, world }
      have changedCells : InitializedCellsPreserved state changed := by
        exact (InitializedCellsPreserved.withHeap state heap).trans
          (InitializedCellsPreserved.withWorld { state with heap := heap } world)
      cases synced : syncI32ViewsFromHeap changed with
      | error reason =>
          simpa only [worldCallOutcome, changed, synced,
            ValueOutcomePreservesInitializedCells] using changedCells
      | ok next =>
          simp only [worldCallOutcome, changed, synced,
            ValueOutcomePreservesInitializedCells]
          exact changedCells.trans
            (syncI32ViewsFromHeap_preserves_initialized_cells synced)
  | exited code heap world =>
      let changed : State := { state with heap, world }
      have changedCells : InitializedCellsPreserved state changed := by
        exact (InitializedCellsPreserved.withHeap state heap).trans
          (InitializedCellsPreserved.withWorld { state with heap := heap } world)
      cases synced : syncI32ViewsFromHeap changed with
      | error reason =>
          simpa only [worldCallOutcome, changed, synced,
            ValueOutcomePreservesInitializedCells] using changedCells
      | ok next =>
          simp only [worldCallOutcome, changed, synced,
            ValueOutcomePreservesInitializedCells]
          exact changedCells.trans
            (syncI32ViewsFromHeap_preserves_initialized_cells synced)
  | unavailable service heap world | trapped service heap world =>
      exact (InitializedCellsPreserved.withHeap state heap).trans
        (InitializedCellsPreserved.withWorld { state with heap := heap } world)
  | typeMismatch heap world =>
      exact (InitializedCellsPreserved.withHeap state heap).trans
        (InitializedCellsPreserved.withWorld { state with heap := heap } world)

/-- A concrete host call, including heap/view synchronization before the
    backend-visible result is returned, preserves the runtime invariant. -/
theorem hostCallOutcome_has_runtime_type
    (typed : RuntimeStateHasType program context state store)
    (argumentsTyped : ValuesHaveTypes program arguments service.parameterTypes) :
    RuntimeValueOutcomeHasType program context store
      (worldCallOutcome functionId state
        (World.call state.heap state.world service arguments))
      service.returnType :=
  worldCallOutcome_has_runtime_type typed
    (World.call_has_type typed.typed.wellFormed.heapWellFormed argumentsTyped)

theorem opaqueCallOutcome_has_runtime_type
    (typed : RuntimeStateHasType program context state store)
    (resultTyped : OpaqueCallResultHasType program result returnType) :
    RuntimeValueOutcomeHasType program context store
      (opaqueCallOutcome external state result) returnType := by
  cases result with
  | returned value world =>
      obtain ⟨valueTyped, valueClosed⟩ := resultTyped
      have worldTyped := typed.withWorld world
      cases synced : syncI32ViewsFromHeap { state with world } with
      | error reason =>
          simp only [opaqueCallOutcome, synced, RuntimeValueOutcomeHasType]
          exact worldTyped
      | ok next =>
          simp only [opaqueCallOutcome, synced, RuntimeValueOutcomeHasType]
          exact ⟨syncI32ViewsFromHeap_preserves_runtime_type worldTyped synced,
            valueTyped, valueClosed.borrowsValid⟩
  | trapped reason world =>
      simp only [opaqueCallOutcome, RuntimeValueOutcomeHasType]
      exact typed.withWorld world
  | unmodeled world =>
      simp only [opaqueCallOutcome, RuntimeValueOutcomeHasType]
      exact typed.withWorld world

theorem opaqueCallOutcome_preserves_initialized_cells :
    ValueOutcomePreservesInitializedCells state
      (opaqueCallOutcome external state result) := by
  cases result with
  | returned value world =>
      let changed : State := { state with world }
      have changedCells : InitializedCellsPreserved state changed :=
        InitializedCellsPreserved.withWorld state world
      cases synced : syncI32ViewsFromHeap changed with
      | error reason =>
          simpa only [opaqueCallOutcome, changed, synced,
            ValueOutcomePreservesInitializedCells] using changedCells
      | ok next =>
          simp only [opaqueCallOutcome, changed, synced,
            ValueOutcomePreservesInitializedCells]
          exact changedCells.trans
            (syncI32ViewsFromHeap_preserves_initialized_cells synced)
  | trapped reason world | unmodeled world =>
      exact InitializedCellsPreserved.withWorld state world

theorem mapI32ArrayView_has_type
    (typed : RuntimeStateHasType program context state store)
    (placeTyped : I32ArrayPlaceHasType program state store
      root projections elements.length) :
    RuntimeValueOutcomeHasType program context store
      (mapI32ArrayView state root projections elements) (.scalar .rawPtr) := by
  cases existing : state.i32ArrayView? root projections with
  | some view =>
      simp only [mapI32ArrayView, existing]
      cases synchronized : syncI32ViewsToHeap state with
      | error reason =>
          simp [synchronized, RuntimeValueOutcomeHasType]
          exact typed
      | ok next =>
          have nextTyped := syncI32ViewsToHeap_preserves_runtime_type
            typed synchronized
          simp only [synchronized, RuntimeValueOutcomeHasType]
          refine ⟨nextTyped, .pointer view.address, ?_⟩
          intro descriptor member
          simp [valueBorrows] at member

  | none =>
      simp only [mapI32ArrayView, existing]
      cases encoded : encodeI32Array elements with
      | error reason =>
          simp [encoded, RuntimeValueOutcomeHasType]
          exact typed
      | ok bytes =>
          let base := alignUp (max state.heap.nextAddress 1) 4
          let block : Block := {
            base
            size := bytes.length
            alignment := 4
            bytes
            owned := false
          }
          let heap : Heap := {
            state.heap with
            blocks := state.heap.blocks ++ [block]
            nextAddress := base + max bytes.length 1
          }
          let view : I32ArrayView := {
            address := base
            root
            projections
            length := elements.length
          }
          have alignmentValid : validAlignment 4 = true := by decide
          have mapped : state.heap.mapBorrowed bytes 4 = .allocated base heap := by
            simp [Heap.mapBorrowed, alignmentValid, heap, block, base]
          simp only [encoded, mapped, RuntimeValueOutcomeHasType]
          have heapWellFormed : HeapWellFormed heap := by
            have preserved := mapBorrowed_preserves_heap_well_formed
              (bytes := bytes) (alignment := 4)
              typed.typed.wellFormed.heapWellFormed
            rw [mapped] at preserved
            exact preserved
          have alignmentNonzero : (4 : Nat) ≠ 0 := by decide
          have frontierLeBase : state.heap.nextAddress ≤ base := by
            have aligned := alignUp_ge (max state.heap.nextAddress 1) 4
              alignmentNonzero
            exact Nat.le_trans (Nat.le_max_left _ _) aligned
          have oldBlocksPreserved : I32ArrayViewBlocksPreserved
              state.i32ArrayViews state.heap heap := by
            intro oldView member valid
            have preserved := appendBlock_preserves_i32_array_view_blocks
              state.i32ArrayViews state.heap block oldView member valid
            simpa only [heap, I32ArrayViewBlockWellFormed, Heap.block?] using
              preserved
          have heapStateTyped := typed.withHeap heap heapWellFormed
            oldBlocksPreserved
          have viewPlaceTyped : I32ArrayViewPlaceHasType program
              { state with heap := heap } store view := by
            have moved := placeTyped.withHeap heap
            simpa only [I32ArrayViewPlaceHasType, view] using moved
          have viewBlockValid : I32ArrayViewBlockWellFormed heap view := by
            refine ⟨block, ?_, rfl, rfl, ?_, rfl⟩
            · change ({ state.heap with
                blocks := state.heap.blocks ++ [block] } : Heap).block?
                  block.base = some block
              exact block?_append_fresh
                typed.typed.wellFormed.heapWellFormed frontierLeBase
            · have byteLength := encodeI32Array_length encoded
              simpa only [block, view] using byteLength
          let next : State := {
            state with
            heap
            i32ArrayViews := state.i32ArrayViews ++ [view]
          }
          have nextStateTyped : StateHasType program context next store := by
            simpa only [next] using
              heapStateTyped.typed.withI32ArrayViews
                (state.i32ArrayViews ++ [view])
          have nextViewsTyped : I32ArrayViewsWellFormed program next store := by
            intro candidate member
            simp only [next, List.mem_append, List.mem_singleton] at member
            rcases member with old | added
            · have oldValid := heapStateTyped.views candidate old
              have changed := oldValid.withI32ArrayViews
                (state.i32ArrayViews ++ [view])
              simpa only [next] using changed
            · subst candidate
              exact ⟨viewPlaceTyped, viewBlockValid⟩
          refine ⟨⟨nextStateTyped, nextViewsTyped⟩,
            ValueHasType.pointer base, ?_⟩
          intro descriptor member
          simp [valueBorrows] at member

theorem mapI32ArrayView_preserves_initialized_cells
    (state : State) (root : CellId) (projections : List ValueProjection)
    (elements : List Value) :
    ValueOutcomePreservesInitializedCells state
      (mapI32ArrayView state root projections elements) := by
  cases existing : state.i32ArrayView? root projections with
  | some view =>
      cases synchronized : syncI32ViewsToHeap state with
      | error reason =>
          simp [mapI32ArrayView, existing, synchronized,
            ValueOutcomePreservesInitializedCells]
          exact InitializedCellsPreserved.refl state
      | ok next =>
          simp [mapI32ArrayView, existing, synchronized,
            ValueOutcomePreservesInitializedCells]
          exact syncI32ViewsToHeap_preserves_initialized_cells synchronized
  | none =>
      cases encoded : encodeI32Array elements with
      | error reason =>
          simp [mapI32ArrayView, existing, encoded,
            ValueOutcomePreservesInitializedCells]
          exact InitializedCellsPreserved.refl state
      | ok bytes =>
          cases mapped : state.heap.mapBorrowed bytes 4 with
          | allocated address heap =>
              simp [mapI32ArrayView, existing, encoded, mapped,
                ValueOutcomePreservesInitializedCells]
              exact InitializedCellsPreserved.withHeapAndI32ArrayViews state heap
                (state.i32ArrayViews ++ [{
                  address, root, projections, length := elements.length }])
          | exhausted heap | trapped reason heap =>
              simp [mapI32ArrayView, existing, encoded, mapped,
                ValueOutcomePreservesInitializedCells]
              exact InitializedCellsPreserved.withHeap state heap

/-- Evaluation may allocate stable temporary cells, so preservation quantifies
    a store typing that extends the input store and records that initialized
    cell identities survive, rather than requiring literal state equality. -/
def StateHasExtendedType
    (program : Program) (context : Context)
    (beforeState : State) (beforeStore : StoreTyping) (afterState : State) : Prop :=
  ∃ afterStore, StoreExtends beforeStore afterStore ∧
    InitializedCellsPreserved beforeState afterState ∧
    StateHasType program context afterState afterStore

def ValueOutcomeHasType
    (program : Program) (context : Context)
    (beforeState : State) (beforeStore : StoreTyping)
    (outcome : Outcome Value) (type : Ty) : Prop :=
  match outcome with
  | .done value afterState =>
      ∃ afterStore, StoreExtends beforeStore afterStore ∧
        InitializedCellsPreserved beforeState afterState ∧
        StateHasType program context afterState afterStore ∧
        ValueHasType program value type ∧
        BorrowsValid program afterState afterStore value
  | .trapped _ afterState | .exited _ afterState =>
      StateHasExtendedType program context beforeState beforeStore afterState
  | .outOfFuel => True

/-- Runtime preservation strengthens ordinary state preservation with the
    explicit borrowed-view invariant. This is the compositional relation used
    by expressions that may cross raw-memory or foreign-call boundaries. -/
def RuntimeStateHasExtendedType
    (program : Program) (context : Context)
    (beforeState : State) (beforeStore : StoreTyping)
    (afterState : State) : Prop :=
  ∃ afterStore, StoreExtends beforeStore afterStore ∧
    InitializedCellsPreserved beforeState afterState ∧
    RuntimeStateHasType program context afterState afterStore

def RuntimeValueOutcomeHasExtendedType
    (program : Program) (context : Context)
    (beforeState : State) (beforeStore : StoreTyping)
    (outcome : Outcome Value) (type : Ty) : Prop :=
  match outcome with
  | .done value afterState =>
      ∃ afterStore, StoreExtends beforeStore afterStore ∧
        InitializedCellsPreserved beforeState afterState ∧
        RuntimeStateHasType program context afterState afterStore ∧
        ValueHasType program value type ∧
        BorrowsValid program afterState afterStore value
  | .trapped _ afterState | .exited _ afterState =>
      RuntimeStateHasExtendedType program context beforeState beforeStore
        afterState
  | .outOfFuel => True

def RuntimeValuesOutcomeHaveTypes
    (program : Program) (context : Context)
    (beforeState : State) (beforeStore : StoreTyping)
    (outcome : Outcome (List Value)) (types : List Ty) : Prop :=
  match outcome with
  | .done values afterState =>
      ∃ afterStore, StoreExtends beforeStore afterStore ∧
        InitializedCellsPreserved beforeState afterState ∧
        RuntimeStateHasType program context afterState afterStore ∧
        ValuesHaveTypes program values types ∧
        ValuesBorrowsValid program afterState afterStore values
  | .trapped _ afterState | .exited _ afterState =>
      RuntimeStateHasExtendedType program context beforeState beforeStore
        afterState
  | .outOfFuel => True

def RuntimePlaceOutcomeHasType
    (program : Program) (context : Context)
    (beforeState : State) (beforeStore : StoreTyping)
    (outcome : Outcome ResolvedPlace) (type : Ty) : Prop :=
  match outcome with
  | .done place afterState =>
      ∃ afterStore, StoreExtends beforeStore afterStore ∧
        InitializedCellsPreserved beforeState afterState ∧
        RuntimeStateHasType program context afterState afterStore ∧
        ResolvedPlaceHasType program afterState afterStore place type
  | .trapped _ afterState | .exited _ afterState =>
      RuntimeStateHasExtendedType program context beforeState beforeStore
        afterState
  | .outOfFuel => True

theorem InitializedCellsPreserved.prependOutcome
    (outcome : Outcome Value)
    (preceding : InitializedCellsPreserved beforeState middleState)
    (suffix : ValueOutcomePreservesInitializedCells middleState outcome) :
    ValueOutcomePreservesInitializedCells beforeState outcome := by
  cases outcome with
  | done value afterState | trapped value afterState | exited value afterState =>
      exact preceding.trans suffix
  | outOfFuel => trivial

theorem RuntimeValueOutcomeHasType.prepend
    (prefixStore : StoreExtends beforeStore middleStore)
    (prefixCells : InitializedCellsPreserved beforeState middleState)
    (suffixCells : ValueOutcomePreservesInitializedCells middleState outcome)
    (typed : RuntimeValueOutcomeHasType program context middleStore outcome type) :
    RuntimeValueOutcomeHasExtendedType program context beforeState beforeStore
      outcome type := by
  cases outcome with
  | done value afterState =>
      exact ⟨middleStore, prefixStore, prefixCells.trans suffixCells, typed.1,
        typed.2.1, typed.2.2⟩
  | trapped reason afterState | exited reason afterState =>
      exact ⟨middleStore, prefixStore, prefixCells.trans suffixCells, typed⟩
  | outOfFuel => trivial

theorem RuntimeValueOutcomeHasExtendedType.toValueOutcomeHasType
    (typed : RuntimeValueOutcomeHasExtendedType program context
      beforeState beforeStore outcome type) :
    ValueOutcomeHasType program context beforeState beforeStore outcome type := by
  cases outcome with
  | done value afterState =>
      obtain ⟨afterStore, storePreserved, cellsPreserved, afterTyped,
        valueTyped, valueBorrows⟩ := typed
      exact ⟨afterStore, storePreserved, cellsPreserved, afterTyped.typed,
        valueTyped, valueBorrows⟩
  | trapped reason afterState | exited reason afterState =>
      obtain ⟨afterStore, storePreserved, cellsPreserved, afterTyped⟩ := typed
      exact ⟨afterStore, storePreserved, cellsPreserved, afterTyped.typed⟩
  | outOfFuel => trivial

theorem RuntimeStateHasExtendedType.prepend
    (prefixStore : StoreExtends beforeStore middleStore)
    (prefixCells : InitializedCellsPreserved beforeState middleState)
    (typed : RuntimeStateHasExtendedType program context middleState
      middleStore afterState) :
    RuntimeStateHasExtendedType program context beforeState beforeStore
      afterState := by
  obtain ⟨afterStore, suffixStore, suffixCells, afterTyped⟩ := typed
  exact ⟨afterStore, prefixStore.trans suffixStore,
    prefixCells.trans suffixCells, afterTyped⟩

theorem RuntimeValueOutcomeHasExtendedType.prepend
    (prefixStore : StoreExtends beforeStore middleStore)
    (prefixCells : InitializedCellsPreserved beforeState middleState)
    (typed : RuntimeValueOutcomeHasExtendedType program context middleState
      middleStore outcome type) :
    RuntimeValueOutcomeHasExtendedType program context beforeState beforeStore
      outcome type := by
  cases outcome with
  | done value afterState =>
      obtain ⟨afterStore, suffixStore, suffixCells, afterTyped,
        valueTyped, valueBorrows⟩ := typed
      exact ⟨afterStore, prefixStore.trans suffixStore,
        prefixCells.trans suffixCells, afterTyped, valueTyped, valueBorrows⟩
  | trapped reason afterState | exited reason afterState =>
      exact RuntimeStateHasExtendedType.prepend prefixStore prefixCells typed
  | outOfFuel => trivial

theorem RuntimeValuesOutcomeHaveTypes.prepend
    (prefixStore : StoreExtends beforeStore middleStore)
    (prefixCells : InitializedCellsPreserved beforeState middleState)
    (typed : RuntimeValuesOutcomeHaveTypes program context middleState
      middleStore outcome types) :
    RuntimeValuesOutcomeHaveTypes program context beforeState beforeStore
      outcome types := by
  cases outcome with
  | done values afterState =>
      obtain ⟨afterStore, suffixStore, suffixCells, afterTyped,
        valuesTyped, valuesBorrows⟩ := typed
      exact ⟨afterStore, prefixStore.trans suffixStore,
        prefixCells.trans suffixCells, afterTyped, valuesTyped, valuesBorrows⟩
  | trapped reason afterState | exited reason afterState =>
      exact RuntimeStateHasExtendedType.prepend prefixStore prefixCells typed
  | outOfFuel => trivial

theorem RuntimePlaceOutcomeHasType.prepend
    (prefixStore : StoreExtends beforeStore middleStore)
    (prefixCells : InitializedCellsPreserved beforeState middleState)
    (typed : RuntimePlaceOutcomeHasType program context middleState middleStore
      outcome type) :
    RuntimePlaceOutcomeHasType program context beforeState beforeStore
      outcome type := by
  cases outcome with
  | done place afterState =>
      obtain ⟨afterStore, suffixStore, suffixCells, afterTyped,
        placeTyped⟩ := typed
      exact ⟨afterStore, prefixStore.trans suffixStore,
        prefixCells.trans suffixCells, afterTyped, placeTyped⟩
  | trapped reason afterState | exited reason afterState =>
      exact RuntimeStateHasExtendedType.prepend prefixStore prefixCells typed
  | outOfFuel => trivial

def ValuesOutcomeHaveTypes
    (program : Program) (context : Context)
    (beforeState : State) (beforeStore : StoreTyping)
    (outcome : Outcome (List Value)) (types : List Ty) : Prop :=
  match outcome with
  | .done values afterState =>
      ∃ afterStore, StoreExtends beforeStore afterStore ∧
        InitializedCellsPreserved beforeState afterState ∧
        StateHasType program context afterState afterStore ∧
        ValuesHaveTypes program values types ∧
        ValuesBorrowsValid program afterState afterStore values
  | .trapped _ afterState | .exited _ afterState =>
      StateHasExtendedType program context beforeState beforeStore afterState
  | .outOfFuel => True

def PlaceOutcomeHasType
    (program : Program) (context : Context)
    (beforeState : State) (beforeStore : StoreTyping)
    (outcome : Outcome ResolvedPlace) (type : Ty) : Prop :=
  match outcome with
  | .done place afterState =>
      ∃ afterStore, StoreExtends beforeStore afterStore ∧
        InitializedCellsPreserved beforeState afterState ∧
        StateHasType program context afterState afterStore ∧
        ResolvedPlaceHasType program afterState afterStore place type
  | .trapped _ afterState | .exited _ afterState =>
      StateHasExtendedType program context beforeState beforeStore afterState
  | .outOfFuel => True

theorem RuntimePlaceOutcomeHasType.toPlaceOutcomeHasType
    (typed : RuntimePlaceOutcomeHasType program context beforeState beforeStore
      outcome type) :
    PlaceOutcomeHasType program context beforeState beforeStore outcome type := by
  cases outcome with
  | done place afterState =>
      obtain ⟨afterStore, storePreserved, cellsPreserved, afterTyped,
        placeTyped⟩ := typed
      exact ⟨afterStore, storePreserved, cellsPreserved, afterTyped.typed,
        placeTyped⟩
  | trapped reason afterState | exited reason afterState =>
      obtain ⟨afterStore, storePreserved, cellsPreserved, afterTyped⟩ := typed
      exact ⟨afterStore, storePreserved, cellsPreserved, afterTyped.typed⟩
  | outOfFuel => trivial

def CompletionHasType
    (program : Program) (returnType : Ty) (inLoop : Bool)
    (state : State) (store : StoreTyping) : Completion → Prop
  | .next => True
  | .returned none => returnType = .unit
  | .returned (some value) =>
      ValueHasType program value returnType ∧
        BorrowsValid program state store value
  | .breakLoop | .continueLoop => inLoop = true

def CompletionOutcomeHasType
    (program : Program) (returnType : Ty) (context : Context) (inLoop : Bool)
    (beforeState : State) (beforeStore : StoreTyping)
    (outcome : Outcome Completion) : Prop :=
  match outcome with
  | .done completion afterState =>
      ∃ afterStore, StoreExtends beforeStore afterStore ∧
        InitializedCellsPreserved beforeState afterState ∧
        StateHasType program context afterState afterStore ∧
        CompletionHasType program returnType inLoop afterState afterStore
          completion
  | .trapped _ afterState | .exited _ afterState =>
      StateHasExtendedType program context beforeState beforeStore afterState
  | .outOfFuel => True

def RuntimeCompletionOutcomeHasType
    (program : Program) (returnType : Ty) (context : Context) (inLoop : Bool)
    (beforeState : State) (beforeStore : StoreTyping)
    (outcome : Outcome Completion) : Prop :=
  match outcome with
  | .done completion afterState =>
      ∃ afterStore, StoreExtends beforeStore afterStore ∧
        InitializedCellsPreserved beforeState afterState ∧
        RuntimeStateHasType program context afterState afterStore ∧
        CompletionHasType program returnType inLoop afterState afterStore
          completion
  | .trapped _ afterState | .exited _ afterState =>
      RuntimeStateHasExtendedType program context beforeState beforeStore
        afterState
  | .outOfFuel => True

/-- The preservation contract supplied by the expression evaluator to
    statement execution. Keeping it explicit lets statement preservation be
    proved independently while call and external-world cases are completed. -/
def ExpressionsPreserveTypes (program : Program) : Prop :=
  ∀ (fuel : Nat) (context : Context) (state : State) (store : StoreTyping)
    (expression : Expr) (type : Ty),
    StateHasType program context state store →
    ExprHasType program context expression type →
    ValueOutcomeHasType program context state store
      (evalExpr fuel program state expression) type

def RuntimeExpressionsPreserveTypes (program : Program) : Prop :=
  ∀ (fuel : Nat) (context : Context) (state : State) (store : StoreTyping)
    (expression : Expr) (type : Ty),
    RuntimeStateHasType program context state store →
    ExprHasType program context expression type →
    RuntimeValueOutcomeHasExtendedType program context state store
      (evalExpr fuel program state expression) type

/-- The recursive evaluator contract below a strict fuel bound. This is the
    form used while proving preservation: every recursive evaluator call has
    less fuel than the expression whose preservation is being established. -/
def RuntimeExpressionsPreserveTypesBelow
    (program : Program) (limit : Nat) : Prop :=
  ∀ (fuel : Nat), fuel < limit →
    ∀ (context : Context) (state : State) (store : StoreTyping)
      (expression : Expr) (type : Ty),
      RuntimeStateHasType program context state store →
      ExprHasType program context expression type →
      RuntimeValueOutcomeHasExtendedType program context state store
        (evalExpr fuel program state expression) type

inductive ImmediateExternalTrap : ExternalBehavior → Trap → Prop where
  | unavailable (capability : Capability) :
      ImmediateExternalTrap (.unavailable capability)
        (.serviceUnavailable capability)
  | panic : ImmediateExternalTrap .panic .panic
  | unreachable : ImmediateExternalTrap .unreachable .reachedUnreachable

theorem evalImmediateExternalCall_has_runtime_type
    (fuel : Nat)
    (functionFound : program.function? functionId = some function)
    (bodyMissing : function.body = none)
    (externalFound : function.external = some external)
    (immediate : ImmediateExternalTrap external reason)
    (argumentsPreserved : RuntimeValuesOutcomeHaveTypes program context state
      store (evalExprs fuel program state arguments)
      (function.parameters.map Prod.snd)) :
    RuntimeValueOutcomeHasExtendedType program context state store
      (evalExpr (fuel + 1) program state (.call functionId arguments))
      function.returnType := by
  cases argumentsResult : evalExprs fuel program state arguments with
  | done values afterArguments =>
      rw [argumentsResult] at argumentsPreserved
      obtain ⟨afterStore, storePreserved, cellsPreserved,
        afterArgumentsTyped, argumentsTyped, argumentBorrows⟩ :=
        argumentsPreserved
      obtain ⟨bindings, bound⟩ := bindParameters_exists argumentsTyped
      cases immediate with
      | unavailable capability | panic | unreachable =>
          simp only [evalExpr, argumentsResult, functionFound, bodyMissing,
            bound, externalFound]
          exact ⟨afterStore, storePreserved, cellsPreserved,
            afterArgumentsTyped⟩
  | trapped reason next | exited reason next =>
      rw [argumentsResult] at argumentsPreserved
      simpa only [evalExpr, argumentsResult, RuntimeValuesOutcomeHaveTypes,
        RuntimeValueOutcomeHasExtendedType] using argumentsPreserved
  | outOfFuel =>
      simp [evalExpr, argumentsResult, RuntimeValueOutcomeHasExtendedType]

/-- The actual evaluator branch for a typed host function preserves the
    runtime state invariant. Argument evaluation is supplied compositionally;
    the theorem itself covers parameter-shape validation, borrowed-view
    synchronization, host dispatch, and result synchronization. -/
theorem evalHostCall_has_runtime_type
    (fuel : Nat)
    (programTyped : ProgramWellTyped program)
    (functionFound : program.function? functionId = some function)
    (bodyMissing : function.body = none)
    (externalFound : function.external = some (.host service))
    (argumentsPreserved : RuntimeValuesOutcomeHaveTypes program context
      state store (evalExprs fuel program state arguments)
      (function.parameters.map Prod.snd)) :
    RuntimeValueOutcomeHasExtendedType program context state store
      (evalExpr (fuel + 1) program state (.call functionId arguments))
      function.returnType := by
  have functionMember : function ∈ program.functions :=
    List.mem_of_find?_eq_some functionFound
  have functionTyped := programTyped.2 function functionMember
  simp only [FunctionWellTyped, bodyMissing, externalFound] at functionTyped
  obtain ⟨parameterTypes, returnType⟩ := functionTyped
  cases argumentsResult : evalExprs fuel program state arguments with
  | done values afterArguments =>
      rw [argumentsResult] at argumentsPreserved
      obtain ⟨argumentsStore, storePreserved, cellsPreserved,
        afterArgumentsTyped, argumentsTyped, argumentBorrows⟩ :=
        argumentsPreserved
      obtain ⟨bindings, bound⟩ := bindParameters_exists argumentsTyped
      cases synchronized : syncI32ViewsToHeap afterArguments with
      | error reason =>
          simp only [evalExpr, argumentsResult, functionFound, bodyMissing,
            bound, externalFound, synchronized]
          exact ⟨argumentsStore, storePreserved, cellsPreserved,
            afterArgumentsTyped⟩
      | ok next =>
          have nextTyped := syncI32ViewsToHeap_preserves_runtime_type
            afterArgumentsTyped synchronized
          have synchronizedCells :=
            syncI32ViewsToHeap_preserves_initialized_cells synchronized
          have called := hostCallOutcome_has_runtime_type
            (functionId := functionId) nextTyped
            (parameterTypes ▸ argumentsTyped)
          have callCells := worldCallOutcome_preserves_initialized_cells
            (functionId := functionId) (state := next)
            (effect := World.call next.heap next.world service values)
          rw [← returnType] at called
          simpa only [evalExpr, argumentsResult, functionFound, bodyMissing,
            bound, externalFound, synchronized] using
            called.prepend storePreserved cellsPreserved
              (InitializedCellsPreserved.prependOutcome _ synchronizedCells
                callCells)
  | trapped reason next =>
      rw [argumentsResult] at argumentsPreserved
      simpa only [evalExpr, argumentsResult, RuntimeValuesOutcomeHaveTypes,
        RuntimeValueOutcomeHasExtendedType] using argumentsPreserved
  | exited code next =>
      rw [argumentsResult] at argumentsPreserved
      simpa only [evalExpr, argumentsResult, RuntimeValuesOutcomeHaveTypes,
        RuntimeValueOutcomeHasExtendedType] using argumentsPreserved
  | outOfFuel =>
      simp [evalExpr, argumentsResult, RuntimeValueOutcomeHasExtendedType]

theorem BorrowValid.preserve
    (storePreserved : StoreExtends beforeStore afterStore)
    (cellsPreserved : InitializedCellsPreserved beforeState afterState)
    (afterTyped : StateHasType program context afterState afterStore)
    (valid : BorrowValid program beforeState beforeStore descriptor) :
    BorrowValid program afterState afterStore descriptor := by
  cases valid with
  | reference stored found initialized rootTyped projected =>
      obtain ⟨nextEntry, nextValue, nextFound, nextInitialized⟩ :=
        cellsPreserved _ _ _ found initialized
      have nextStored := storePreserved _ _ stored
      have nextRootTyped :=
        (afterTyped.initialized_cell nextStored nextFound nextInitialized).1
      exact .reference nextStored nextFound nextInitialized nextRootTyped projected
  | slice stored found initialized rootTyped projected inBounds =>
      obtain ⟨nextEntry, nextValue, nextFound, nextInitialized⟩ :=
        cellsPreserved _ _ _ found initialized
      have nextStored := storePreserved _ _ stored
      have nextRootTyped :=
        (afterTyped.initialized_cell nextStored nextFound nextInitialized).1
      exact .slice nextStored nextFound nextInitialized nextRootTyped projected inBounds

theorem BorrowsValid.preserve
    (storePreserved : StoreExtends beforeStore afterStore)
    (cellsPreserved : InitializedCellsPreserved beforeState afterState)
    (afterTyped : StateHasType program context afterState afterStore)
    (valid : BorrowsValid program beforeState beforeStore value) :
    BorrowsValid program afterState afterStore value := by
  intro descriptor member
  exact (valid descriptor member).preserve storePreserved cellsPreserved afterTyped

theorem ValuesBorrowsValid.preserve
    (storePreserved : StoreExtends beforeStore afterStore)
    (cellsPreserved : InitializedCellsPreserved beforeState afterState)
    (afterTyped : StateHasType program context afterState afterStore)
    (valid : ValuesBorrowsValid program beforeState beforeStore values) :
    ValuesBorrowsValid program afterState afterStore values := by
  intro descriptor member
  exact (valid descriptor member).preserve storePreserved cellsPreserved afterTyped

theorem BorrowsValid.array_values
    (valid : BorrowsValid program state store (.array values)) :
    ValuesBorrowsValid program state store values := by
  intro descriptor member
  exact valid descriptor (by
    simpa only [valueBorrows] using member)

theorem evalAssignValue_preserves_borrows
    (operation : AssignOpHasType op type)
    (currentTyped : ∀ currentValue, current = some currentValue →
      ValueHasType program currentValue type)
    (rightTyped : ValueHasType program right type)
    (rightBorrows : BorrowsValid program state store right)
    (evaluated : evalAssignValue program.target op current right = .ok result) :
    BorrowsValid program state store result := by
  have resultTyped := evalAssignValue_preserves_type operation currentTyped
    rightTyped evaluated
  cases operation with
  | set =>
      simp [evalAssignValue, assignOpBinary?] at evaluated
      subst result
      exact rightBorrows
  | add arithmetic =>
      cases arithmetic <;> exact
        (Lanius.Properties.ValueHasType.scalar_is_closed resultTyped).borrowsValid
  | subtract arithmetic =>
      cases arithmetic <;> exact
        (Lanius.Properties.ValueHasType.scalar_is_closed resultTyped).borrowsValid
  | multiply arithmetic =>
      cases arithmetic <;> exact
        (Lanius.Properties.ValueHasType.scalar_is_closed resultTyped).borrowsValid
  | divide arithmetic =>
      cases arithmetic <;> exact
        (Lanius.Properties.ValueHasType.scalar_is_closed resultTyped).borrowsValid
  | remainder integer =>
      cases integer <;> exact
        (Lanius.Properties.ValueHasType.scalar_is_closed resultTyped).borrowsValid
  | bitXor integer =>
      cases integer <;> exact
        (Lanius.Properties.ValueHasType.scalar_is_closed resultTyped).borrowsValid
  | shiftLeft integer =>
      cases integer <;> exact
        (Lanius.Properties.ValueHasType.scalar_is_closed resultTyped).borrowsValid
  | shiftRight integer =>
      cases integer <;> exact
        (Lanius.Properties.ValueHasType.scalar_is_closed resultTyped).borrowsValid
  | bitAnd integer =>
      cases integer <;> exact
        (Lanius.Properties.ValueHasType.scalar_is_closed resultTyped).borrowsValid
  | bitOr integer =>
      cases integer <;> exact
        (Lanius.Properties.ValueHasType.scalar_is_closed resultTyped).borrowsValid

theorem ResolvedPlaceHasType.preserve
    (storePreserved : StoreExtends beforeStore afterStore)
    (cellsPreserved : InitializedCellsPreserved beforeState afterState)
    (afterTyped : StateHasType program context afterState afterStore)
    (typed : ResolvedPlaceHasType program beforeState beforeStore place type) :
    ResolvedPlaceHasType program afterState afterStore place type := by
  cases typed with
  | rootNoCachedValue stored found =>
      have nextStored := storePreserved _ _ stored
      obtain ⟨nextEntry, nextFound⟩ := afterTyped.typed_cell_exists nextStored
      exact .rootNoCachedValue nextStored nextFound
  | rootInitialized stored found initialized rootTyped rootBorrows valueTyped
      cachedBorrows =>
      obtain ⟨nextEntry, nextRootValue, nextFound, nextInitialized⟩ :=
        cellsPreserved _ _ _ found initialized
      have nextStored := storePreserved _ _ stored
      obtain ⟨nextRootTyped, nextRootBorrows⟩ :=
        afterTyped.initialized_cell nextStored nextFound nextInitialized
      exact .rootInitialized nextStored nextFound nextInitialized
        nextRootTyped nextRootBorrows valueTyped
        (cachedBorrows.preserve storePreserved cellsPreserved afterTyped)
  | projected stored found initialized rootTyped rootBorrows projectionTyped
      valueTyped valueBorrows =>
      obtain ⟨nextEntry, nextRootValue, nextFound, nextInitialized⟩ :=
        cellsPreserved _ _ _ found initialized
      have nextStored := storePreserved _ _ stored
      obtain ⟨nextRootTyped, nextRootBorrows⟩ :=
        afterTyped.initialized_cell nextStored nextFound nextInitialized
      exact .projected nextStored nextFound nextInitialized nextRootTyped
        nextRootBorrows projectionTyped valueTyped
        (valueBorrows.preserve storePreserved cellsPreserved afterTyped)

theorem ResolvedPlaceHasType.value_typed
    (typed : ResolvedPlaceHasType program state store place type)
    (hasValue : place.value = some value) :
    ValueHasType program value type := by
  cases typed with
  | rootNoCachedValue stored found => simp at hasValue
  | rootInitialized stored found initialized rootTyped rootBorrows valueTyped
      cachedBorrows =>
      simp at hasValue
      subst value
      exact valueTyped
  | projected stored found initialized rootTyped rootBorrows projectionTyped
      valueTyped valueBorrows =>
      simp at hasValue
      subst value
      exact valueTyped

theorem ResolvedPlaceHasType.value_borrows
    (typed : ResolvedPlaceHasType program state store place type)
    (hasValue : place.value = some value) :
    BorrowsValid program state store value := by
  cases typed with
  | rootNoCachedValue stored found => simp at hasValue
  | rootInitialized stored found initialized rootTyped rootBorrows valueTyped
      cachedBorrows =>
      simp at hasValue
      subst value
      exact cachedBorrows
  | projected stored found initialized rootTyped rootBorrows projectionTyped
      valueTyped cachedBorrows =>
      simp at hasValue
      subst value
      exact cachedBorrows

theorem ResolvedPlaceHasType.array_slice
    (typed : ResolvedPlaceHasType program state store place
      (.array elementType length))
    (hasArray : place.value = some (.array elements)) :
    ValueHasType program
        (.slice elementType place.root place.projections 0 elements.length)
        (.slice elementType) ∧
      BorrowsValid program state store
        (.slice elementType place.root place.projections 0 elements.length) := by
  cases typed with
  | rootNoCachedValue stored found => simp at hasArray
  | rootInitialized stored found initialized rootTyped rootBorrows valueTyped
      valueBorrows =>
      cases valueTyped with
      | array cachedElements cachedElementType valueLength elementsTyped =>
          simp at hasArray
          subst cachedElements
          rw [valueLength]
          exact existingArraySlice_result_valid stored found initialized rootTyped
            ProjectionHasType.nil
  | projected stored found initialized rootTyped rootBorrows projectionTyped
      valueTyped valueBorrows =>
      cases valueTyped with
      | array cachedElements cachedElementType valueLength elementsTyped =>
          simp at hasArray
          subst cachedElements
          rw [valueLength]
          exact existingArraySlice_result_valid stored found initialized rootTyped
            projectionTyped

theorem ResolvedPlaceHasType.append_array_index
    (typed : ResolvedPlaceHasType program state store place
      (.array elementType length))
    (hasArray : place.value = some (.array elements))
    (selected : elements[index]? = some value) :
    ResolvedPlaceHasType program state store
      { place with
        projections := place.projections ++ [.index index]
        value := some value }
      elementType := by
  cases typed with
  | rootNoCachedValue stored found => simp at hasArray
  | rootInitialized stored found initialized rootTyped rootBorrows valueTyped
      cachedBorrows =>
      cases valueTyped with
      | array cachedElements selectedElementType valueLength elementsTyped =>
          simp at hasArray
          subst cachedElements
          obtain ⟨selectedType, typeFound, selectedTyped⟩ :=
            Lanius.Properties.ValuesHaveTypes.getElem?_aligned _
              elementsTyped selected
          have selectedTypeEq := replicate_getElem?_some _ _ _ _ typeFound
          subst selectedType
          simp only [List.nil_append]
          have selectedBorrows : BorrowsValid program state store value := by
            intro descriptor member
            exact cachedBorrows descriptor (by
              simpa [valueBorrows] using
                valueBorrows_mem_valueListBorrows
                  (List.mem_of_getElem? selected) member)
          exact .projected stored found initialized rootTyped rootBorrows
            (.arrayIndex .nil) selectedTyped selectedBorrows
  | projected stored found initialized rootTyped rootBorrows projectionTyped
      valueTyped cachedBorrows =>
      cases valueTyped with
      | array cachedElements selectedElementType valueLength elementsTyped =>
          simp at hasArray
          subst cachedElements
          obtain ⟨selectedType, typeFound, selectedTyped⟩ :=
            Lanius.Properties.ValuesHaveTypes.getElem?_aligned _
              elementsTyped selected
          have selectedTypeEq := replicate_getElem?_some _ _ _ _ typeFound
          subst selectedType
          have selectedBorrows : BorrowsValid program state store value := by
            intro descriptor member
            exact cachedBorrows descriptor (by
              simpa [valueBorrows] using
                valueBorrows_mem_valueListBorrows
                  (List.mem_of_getElem? selected) member)
          exact .projected stored found initialized rootTyped rootBorrows
            (projectionTyped.trans (.arrayIndex .nil)) selectedTyped
            selectedBorrows

theorem ResolvedPlaceHasType.slice_index
    (index : Nat)
    (stateTyped : StateHasType program context state store)
    (valid : BorrowValid program state store
      (.slice elementType cell projections start length))
    (valueTyped : ValueHasType program value elementType)
    (valueBorrows : BorrowsValid program state store value) :
    ResolvedPlaceHasType program state store
      { root := cell
        projections := projections ++ [.index (start + index)]
        value := some value }
      elementType := by
  cases valid with
  | slice stored found initialized rootTyped projected inBounds =>
      have rootBorrows :=
        (stateTyped.initialized_cell stored found initialized).2
      exact .projected stored found initialized rootTyped rootBorrows
        (projected.trans (.arrayIndex .nil)) valueTyped valueBorrows

theorem StateHasExtendedType.prepend
    (prefixStore : StoreExtends beforeStore middleStore)
    (prefixCells : InitializedCellsPreserved beforeState middleState)
    (typed : StateHasExtendedType program context middleState middleStore afterState) :
    StateHasExtendedType program context beforeState beforeStore afterState := by
  obtain ⟨afterStore, suffixStore, suffixCells, stateTyped⟩ := typed
  exact ⟨afterStore, prefixStore.trans suffixStore,
    prefixCells.trans suffixCells, stateTyped⟩

theorem ValueOutcomeHasType.prepend
    (prefixStore : StoreExtends beforeStore middleStore)
    (prefixCells : InitializedCellsPreserved beforeState middleState)
    (typed : ValueOutcomeHasType program context middleState middleStore outcome type) :
    ValueOutcomeHasType program context beforeState beforeStore outcome type := by
  cases outcome with
  | done value afterState =>
      obtain ⟨afterStore, suffixStore, suffixCells, stateTyped, valueTyped,
        borrows⟩ := typed
      exact ⟨afterStore, prefixStore.trans suffixStore,
        prefixCells.trans suffixCells, stateTyped, valueTyped, borrows⟩
  | trapped reason afterState =>
      exact Lanius.Properties.StateHasExtendedType.prepend
        prefixStore prefixCells typed
  | exited code afterState =>
      exact Lanius.Properties.StateHasExtendedType.prepend
        prefixStore prefixCells typed
  | outOfFuel => trivial

theorem ValueOutcomeHasType.restoreLocals
    (callerTyped : StateHasType program callerContext caller callerStore)
    (boundStorePreserved : StoreExtends callerStore boundStore)
    (boundCellsPreserved : InitializedCellsPreserved caller boundState)
    (typed : ValueOutcomeHasType program boundContext boundState boundStore
      outcome type) :
    ValueOutcomeHasType program callerContext caller callerStore
      (restoreOutcomeLocals caller outcome) type := by
  cases outcome with
  | done value completed =>
      obtain ⟨completedStore, bodyStorePreserved, bodyCellsPreserved,
        completedTyped, valueTyped, valueBorrows⟩ := typed
      have allStorePreserved := boundStorePreserved.trans bodyStorePreserved
      have allCellsPreserved :=
        (boundCellsPreserved.trans bodyCellsPreserved).restoreLocals caller
      exact ⟨completedStore, allStorePreserved, allCellsPreserved,
        callerTyped.restoreLocals completedTyped allStorePreserved,
        valueTyped, valueBorrows.withLocals caller.locals⟩
  | trapped reason completed =>
      obtain ⟨completedStore, bodyStorePreserved, bodyCellsPreserved,
        completedTyped⟩ := typed
      have allStorePreserved := boundStorePreserved.trans bodyStorePreserved
      exact ⟨completedStore, allStorePreserved,
        (boundCellsPreserved.trans bodyCellsPreserved).restoreLocals caller,
        callerTyped.restoreLocals completedTyped allStorePreserved⟩
  | exited code completed =>
      obtain ⟨completedStore, bodyStorePreserved, bodyCellsPreserved,
        completedTyped⟩ := typed
      have allStorePreserved := boundStorePreserved.trans bodyStorePreserved
      exact ⟨completedStore, allStorePreserved,
        (boundCellsPreserved.trans bodyCellsPreserved).restoreLocals caller,
        callerTyped.restoreLocals completedTyped allStorePreserved⟩
  | outOfFuel => trivial

theorem RuntimeValueOutcomeHasExtendedType.restoreLocals
    (callerTyped : RuntimeStateHasType program callerContext caller callerStore)
    (boundStorePreserved : StoreExtends callerStore boundStore)
    (boundCellsPreserved : InitializedCellsPreserved caller boundState)
    (typed : RuntimeValueOutcomeHasExtendedType program boundContext boundState
      boundStore outcome type) :
    RuntimeValueOutcomeHasExtendedType program callerContext caller callerStore
      (restoreOutcomeLocals caller outcome) type := by
  cases outcome with
  | done value completed =>
      obtain ⟨completedStore, bodyStorePreserved, bodyCellsPreserved,
        completedTyped, valueTyped, valueBorrows⟩ := typed
      have allStorePreserved := boundStorePreserved.trans bodyStorePreserved
      have allCellsPreserved :=
        (boundCellsPreserved.trans bodyCellsPreserved).restoreLocals caller
      exact ⟨completedStore, allStorePreserved, allCellsPreserved,
        callerTyped.restoreLocals completedTyped allStorePreserved,
        valueTyped, valueBorrows.withLocals caller.locals⟩
  | trapped reason completed | exited reason completed =>
      obtain ⟨completedStore, bodyStorePreserved, bodyCellsPreserved,
        completedTyped⟩ := typed
      have allStorePreserved := boundStorePreserved.trans bodyStorePreserved
      exact ⟨completedStore, allStorePreserved,
        (boundCellsPreserved.trans bodyCellsPreserved).restoreLocals caller,
        callerTyped.restoreLocals completedTyped allStorePreserved⟩
  | outOfFuel => trivial

theorem CompletionHasType.withLocals
    (typed : CompletionHasType program returnType inLoop state store completion)
    (locals : List (VarId × CellId)) :
    CompletionHasType program returnType inLoop { state with locals := locals }
      store completion := by
  cases completion with
  | next => trivial
  | returned value =>
      cases value with
      | none => exact typed
      | some result => exact ⟨typed.1, typed.2.withLocals locals⟩
  | breakLoop => exact typed
  | continueLoop => exact typed

theorem CompletionOutcomeHasType.prepend
    (prefixStore : StoreExtends beforeStore middleStore)
    (prefixCells : InitializedCellsPreserved beforeState middleState)
    (typed : CompletionOutcomeHasType program returnType context inLoop
      middleState middleStore outcome) :
    CompletionOutcomeHasType program returnType context inLoop
      beforeState beforeStore outcome := by
  cases outcome with
  | done completion afterState =>
      obtain ⟨afterStore, suffixStore, suffixCells, stateTyped,
        completionTyped⟩ := typed
      exact ⟨afterStore, prefixStore.trans suffixStore,
        prefixCells.trans suffixCells, stateTyped, completionTyped⟩
  | trapped reason afterState =>
      exact Lanius.Properties.StateHasExtendedType.prepend
        prefixStore prefixCells typed
  | exited code afterState =>
      exact Lanius.Properties.StateHasExtendedType.prepend
        prefixStore prefixCells typed
  | outOfFuel => trivial

theorem CompletionOutcomeHasType.restoreLocals
    (callerTyped : StateHasType program callerContext caller callerStore)
    (boundStorePreserved : StoreExtends callerStore boundStore)
    (boundCellsPreserved : InitializedCellsPreserved caller boundState)
    (typed : CompletionOutcomeHasType program returnType boundContext inLoop
      boundState boundStore outcome) :
    CompletionOutcomeHasType program returnType callerContext inLoop
      caller callerStore (restoreOutcomeLocals caller outcome) := by
  cases outcome with
  | done completion completed =>
      obtain ⟨completedStore, bodyStorePreserved, bodyCellsPreserved,
        completedTyped, completionTyped⟩ := typed
      have allStorePreserved := boundStorePreserved.trans bodyStorePreserved
      exact ⟨completedStore, allStorePreserved,
        (boundCellsPreserved.trans bodyCellsPreserved).restoreLocals caller,
        callerTyped.restoreLocals completedTyped allStorePreserved,
        completionTyped.withLocals caller.locals⟩
  | trapped reason completed =>
      obtain ⟨completedStore, bodyStorePreserved, bodyCellsPreserved,
        completedTyped⟩ := typed
      have allStorePreserved := boundStorePreserved.trans bodyStorePreserved
      exact ⟨completedStore, allStorePreserved,
        (boundCellsPreserved.trans bodyCellsPreserved).restoreLocals caller,
        callerTyped.restoreLocals completedTyped allStorePreserved⟩
  | exited code completed =>
      obtain ⟨completedStore, bodyStorePreserved, bodyCellsPreserved,
        completedTyped⟩ := typed
      have allStorePreserved := boundStorePreserved.trans bodyStorePreserved
      exact ⟨completedStore, allStorePreserved,
        (boundCellsPreserved.trans bodyCellsPreserved).restoreLocals caller,
        callerTyped.restoreLocals completedTyped allStorePreserved⟩
  | outOfFuel => trivial

theorem RuntimeCompletionOutcomeHasType.prepend
    (prefixStore : StoreExtends beforeStore middleStore)
    (prefixCells : InitializedCellsPreserved beforeState middleState)
    (typed : RuntimeCompletionOutcomeHasType program returnType context inLoop
      middleState middleStore outcome) :
    RuntimeCompletionOutcomeHasType program returnType context inLoop
      beforeState beforeStore outcome := by
  cases outcome with
  | done completion afterState =>
      obtain ⟨afterStore, suffixStore, suffixCells, stateTyped,
        completionTyped⟩ := typed
      exact ⟨afterStore, prefixStore.trans suffixStore,
        prefixCells.trans suffixCells, stateTyped, completionTyped⟩
  | trapped reason afterState | exited reason afterState =>
      exact RuntimeStateHasExtendedType.prepend prefixStore prefixCells typed
  | outOfFuel => trivial

theorem RuntimeCompletionOutcomeHasType.restoreLocals
    (callerTyped : RuntimeStateHasType program callerContext caller callerStore)
    (boundStorePreserved : StoreExtends callerStore boundStore)
    (boundCellsPreserved : InitializedCellsPreserved caller boundState)
    (typed : RuntimeCompletionOutcomeHasType program returnType boundContext
      inLoop boundState boundStore outcome) :
    RuntimeCompletionOutcomeHasType program returnType callerContext inLoop
      caller callerStore (restoreOutcomeLocals caller outcome) := by
  cases outcome with
  | done completion completed =>
      obtain ⟨completedStore, bodyStorePreserved, bodyCellsPreserved,
        completedTyped, completionTyped⟩ := typed
      have allStorePreserved := boundStorePreserved.trans bodyStorePreserved
      exact ⟨completedStore, allStorePreserved,
        (boundCellsPreserved.trans bodyCellsPreserved).restoreLocals caller,
        callerTyped.restoreLocals completedTyped allStorePreserved,
        completionTyped.withLocals caller.locals⟩
  | trapped reason completed | exited reason completed =>
      obtain ⟨completedStore, bodyStorePreserved, bodyCellsPreserved,
        completedTyped⟩ := typed
      have allStorePreserved := boundStorePreserved.trans bodyStorePreserved
      exact ⟨completedStore, allStorePreserved,
        (boundCellsPreserved.trans bodyCellsPreserved).restoreLocals caller,
        callerTyped.restoreLocals completedTyped allStorePreserved⟩
  | outOfFuel => trivial

theorem ValuesOutcomeHaveTypes.prepend
    (prefixStore : StoreExtends beforeStore middleStore)
    (prefixCells : InitializedCellsPreserved beforeState middleState)
    (typed : ValuesOutcomeHaveTypes program context middleState middleStore
      outcome types) :
    ValuesOutcomeHaveTypes program context beforeState beforeStore outcome types := by
  cases outcome with
  | done values afterState =>
      obtain ⟨afterStore, suffixStore, suffixCells, stateTyped, valuesTyped,
        borrows⟩ := typed
      exact ⟨afterStore, prefixStore.trans suffixStore,
        prefixCells.trans suffixCells, stateTyped, valuesTyped, borrows⟩
  | trapped reason afterState =>
      exact Lanius.Properties.StateHasExtendedType.prepend
        prefixStore prefixCells typed
  | exited code afterState =>
      exact Lanius.Properties.StateHasExtendedType.prepend
        prefixStore prefixCells typed
  | outOfFuel => trivial

theorem PlaceOutcomeHasType.prepend
    (prefixStore : StoreExtends beforeStore middleStore)
    (prefixCells : InitializedCellsPreserved beforeState middleState)
    (typed : PlaceOutcomeHasType program context middleState middleStore
      outcome type) :
    PlaceOutcomeHasType program context beforeState beforeStore outcome type := by
  cases outcome with
  | done place afterState =>
      obtain ⟨afterStore, suffixStore, suffixCells, stateTyped, placeTyped⟩ := typed
      exact ⟨afterStore, prefixStore.trans suffixStore,
        prefixCells.trans suffixCells, stateTyped, placeTyped⟩
  | trapped reason afterState =>
      exact Lanius.Properties.StateHasExtendedType.prepend
        prefixStore prefixCells typed
  | exited code afterState =>
      exact Lanius.Properties.StateHasExtendedType.prepend
        prefixStore prefixCells typed
  | outOfFuel => trivial

theorem ValueOutcomeHasType.done
    (stateTyped : StateHasType program context state store)
    (valueTyped : ValueHasType program value type)
    (borrows : BorrowsValid program state store value) :
    ValueOutcomeHasType program context state store (.done value state) type := by
  exact ⟨store, StoreExtends.refl store, InitializedCellsPreserved.refl state,
    stateTyped, valueTyped, borrows⟩

theorem ValueOutcomeHasType.trapped
    (stateTyped : StateHasType program context state store) :
    ValueOutcomeHasType program context state store (.trapped reason state) type := by
  exact ⟨store, StoreExtends.refl store, InitializedCellsPreserved.refl state,
    stateTyped⟩

theorem ValueOutcomeHasType.exited
    (stateTyped : StateHasType program context state store) :
    ValueOutcomeHasType program context state store (.exited code state) type := by
  exact ⟨store, StoreExtends.refl store, InitializedCellsPreserved.refl state,
    stateTyped⟩

theorem RuntimeValueOutcomeHasExtendedType.done
    (stateTyped : RuntimeStateHasType program context state store)
    (valueTyped : ValueHasType program value type)
    (borrows : BorrowsValid program state store value) :
    RuntimeValueOutcomeHasExtendedType program context state store
      (.done value state) type := by
  exact ⟨store, StoreExtends.refl store, InitializedCellsPreserved.refl state,
    stateTyped, valueTyped, borrows⟩

theorem RuntimeValueOutcomeHasExtendedType.trapped
    (stateTyped : RuntimeStateHasType program context state store) :
    RuntimeValueOutcomeHasExtendedType program context state store
      (.trapped reason state) type := by
  exact ⟨store, StoreExtends.refl store, InitializedCellsPreserved.refl state,
    stateTyped⟩

theorem RuntimeValueOutcomeHasExtendedType.exited
    (stateTyped : RuntimeStateHasType program context state store) :
    RuntimeValueOutcomeHasExtendedType program context state store
      (.exited code state) type := by
  exact ⟨store, StoreExtends.refl store, InitializedCellsPreserved.refl state,
    stateTyped⟩

theorem RuntimePlaceOutcomeHasType.done
    (stateTyped : RuntimeStateHasType program context state store)
    (placeTyped : ResolvedPlaceHasType program state store place type) :
    RuntimePlaceOutcomeHasType program context state store
      (.done place state) type := by
  exact ⟨store, StoreExtends.refl store, InitializedCellsPreserved.refl state,
    stateTyped, placeTyped⟩

theorem RuntimePlaceOutcomeHasType.trapped
    (stateTyped : RuntimeStateHasType program context state store) :
    RuntimePlaceOutcomeHasType program context state store
      (.trapped reason state) type := by
  exact ⟨store, StoreExtends.refl store, InitializedCellsPreserved.refl state,
    stateTyped⟩

theorem RuntimePlaceOutcomeHasType.exited
    (stateTyped : RuntimeStateHasType program context state store) :
    RuntimePlaceOutcomeHasType program context state store
      (.exited code state) type := by
  exact ⟨store, StoreExtends.refl store, InitializedCellsPreserved.refl state,
    stateTyped⟩

theorem evalValue_has_type
    (fuel : Nat)
    (stateTyped : StateHasType program context state store)
    (valueTyped : ValueHasType program value type)
    (borrows : BorrowsValid program state store value) :
    ValueOutcomeHasType program context state store
      (evalExpr (fuel + 1) program state (.value value)) type := by
  exact ValueOutcomeHasType.done stateTyped valueTyped borrows

theorem evalClosedValue_has_type
    (fuel : Nat)
    (stateTyped : StateHasType program context state store)
    (valueTyped : ValueHasType program value type)
    (closed : ValueIsClosed value) :
    ValueOutcomeHasType program context state store
      (evalExpr (fuel + 1) program state (.value value)) type := by
  exact evalValue_has_type fuel stateTyped valueTyped closed.borrowsValid

theorem evalLocal_has_type
    (fuel : Nat) {id : VarId} {type : Ty}
    (stateTyped : StateHasType program context state store)
    (localTyped : context id = some type) :
    ValueOutcomeHasType program context state store
      (evalExpr (fuel + 1) program state (.local id)) type := by
  obtain ⟨cell, localFound, stored⟩ := stateTyped.local_cell localTyped
  obtain ⟨entry, cellFound⟩ := stateTyped.typed_cell_exists stored
  cases entry with
  | mk entryId contents =>
      cases contents with
      | none =>
          simp only [evalExpr, localFound, cellFound]
          exact ValueOutcomeHasType.trapped stateTyped
      | some value =>
          have valueProperties := stateTyped.initialized_cell stored cellFound rfl
          simp only [evalExpr, localFound, cellFound]
          exact ValueOutcomeHasType.done stateTyped valueProperties.1
            valueProperties.2

theorem evalLocalPlace_has_type
    (fuel : Nat) {id : VarId} {type : Ty}
    (stateTyped : StateHasType program context state store)
    (localTyped : context id = some type) :
    PlaceOutcomeHasType program context state store
      (evalPlace (fuel + 1) program state (.local id)) type := by
  obtain ⟨cell, localFound, stored⟩ := stateTyped.local_cell localTyped
  obtain ⟨entry, cellFound⟩ := stateTyped.typed_cell_exists stored
  cases entry with
  | mk entryId contents =>
      cases contents with
      | none =>
          simp only [evalPlace, localFound, cellFound]
          exact ⟨store, StoreExtends.refl store,
            InitializedCellsPreserved.refl state, stateTyped,
            .rootNoCachedValue stored cellFound⟩
      | some value =>
          have valueProperties := stateTyped.initialized_cell stored cellFound rfl
          simp only [evalPlace, localFound, cellFound]
          exact ⟨store, StoreExtends.refl store,
            InitializedCellsPreserved.refl state, stateTyped,
            .rootInitialized stored cellFound rfl valueProperties.1
              valueProperties.2 valueProperties.1 valueProperties.2⟩

theorem evalValue_has_runtime_type
    (fuel : Nat)
    (stateTyped : RuntimeStateHasType program context state store)
    (valueTyped : ValueHasType program value type)
    (borrows : BorrowsValid program state store value) :
    RuntimeValueOutcomeHasExtendedType program context state store
      (evalExpr (fuel + 1) program state (.value value)) type := by
  exact RuntimeValueOutcomeHasExtendedType.done stateTyped valueTyped borrows

theorem evalClosedValue_has_runtime_type
    (fuel : Nat)
    (stateTyped : RuntimeStateHasType program context state store)
    (valueTyped : ValueHasType program value type)
    (closed : ValueIsClosed value) :
    RuntimeValueOutcomeHasExtendedType program context state store
      (evalExpr (fuel + 1) program state (.value value)) type := by
  exact evalValue_has_runtime_type fuel stateTyped valueTyped
    closed.borrowsValid

theorem evalLocal_has_runtime_type
    (fuel : Nat) {id : VarId} {type : Ty}
    (stateTyped : RuntimeStateHasType program context state store)
    (localTyped : context id = some type) :
    RuntimeValueOutcomeHasExtendedType program context state store
      (evalExpr (fuel + 1) program state (.local id)) type := by
  obtain ⟨cell, localFound, stored⟩ := stateTyped.typed.local_cell localTyped
  obtain ⟨entry, cellFound⟩ := stateTyped.typed.typed_cell_exists stored
  cases entry with
  | mk entryId contents =>
      cases contents with
      | none =>
          simp only [evalExpr, localFound, cellFound]
          exact RuntimeValueOutcomeHasExtendedType.trapped stateTyped
      | some value =>
          have valueProperties :=
            stateTyped.typed.initialized_cell stored cellFound rfl
          simp only [evalExpr, localFound, cellFound]
          exact RuntimeValueOutcomeHasExtendedType.done stateTyped
            valueProperties.1 valueProperties.2

theorem evalLocalPlace_has_runtime_type
    (fuel : Nat) {id : VarId} {type : Ty}
    (stateTyped : RuntimeStateHasType program context state store)
    (localTyped : context id = some type) :
    RuntimePlaceOutcomeHasType program context state store
      (evalPlace (fuel + 1) program state (.local id)) type := by
  obtain ⟨cell, localFound, stored⟩ := stateTyped.typed.local_cell localTyped
  obtain ⟨entry, cellFound⟩ := stateTyped.typed.typed_cell_exists stored
  cases entry with
  | mk entryId contents =>
      cases contents with
      | none =>
          simp only [evalPlace, localFound, cellFound]
          exact RuntimePlaceOutcomeHasType.done stateTyped
            (.rootNoCachedValue stored cellFound)
      | some value =>
          have valueProperties :=
            stateTyped.typed.initialized_cell stored cellFound rfl
          simp only [evalPlace, localFound, cellFound]
          exact RuntimePlaceOutcomeHasType.done stateTyped
            (.rootInitialized stored cellFound rfl valueProperties.1
              valueProperties.2 valueProperties.1 valueProperties.2)

theorem evalFieldPlace_has_type
    (fuel : Nat)
    (found : program.structure? typeId = some declaration)
    (fieldFound : declaration.fields[field]? = some fieldType)
    (basePreserved : PlaceOutcomeHasType program context state store
      (evalPlace fuel program state base) (.structure typeId)) :
    PlaceOutcomeHasType program context state store
      (evalPlace (fuel + 1) program state (.field base field)) fieldType := by
  cases baseResult : evalPlace fuel program state base with
  | done resolved next =>
      rw [baseResult] at basePreserved
      obtain ⟨afterStore, storePreserved, cellsPreserved, nextTyped,
        resolvedTyped⟩ := basePreserved
      cases resolvedTyped with
      | rootNoCachedValue stored cellFound =>
          simp only [evalPlace, baseResult]
          exact ⟨afterStore, storePreserved, cellsPreserved, nextTyped⟩
      | rootInitialized stored cellFound initialized rootTyped rootBorrows
          valueTyped cachedBorrows =>
          cases valueTyped with
          | «structure» valueDeclaration valueFound fieldsTyped =>
              have sameDeclaration : valueDeclaration = declaration := by
                exact Option.some.inj (valueFound.symm.trans found)
              subst valueDeclaration
              obtain ⟨fieldValue, valueFieldFound, fieldTyped⟩ :=
                Lanius.Properties.ValuesHaveTypes.getElem?_typed _ fieldsTyped
                  fieldFound
              have fieldBorrows :
                  BorrowsValid program next afterStore fieldValue := by
                intro descriptor member
                exact cachedBorrows descriptor (by
                  simpa [valueBorrows] using
                    valueBorrows_mem_valueListBorrows
                      (List.mem_of_getElem? valueFieldFound) member)
              simp only [evalPlace, baseResult, valueFieldFound,
                List.nil_append]
              refine ⟨afterStore, storePreserved, cellsPreserved, nextTyped,
                .projected stored cellFound initialized
                  rootTyped rootBorrows
                  (.field declaration found fieldFound .nil) fieldTyped
                  fieldBorrows⟩
      | projected stored cellFound initialized rootTyped rootBorrows
          projectionTyped valueTyped cachedBorrows =>
          cases valueTyped with
          | «structure» valueDeclaration valueFound fieldsTyped =>
              have sameDeclaration : valueDeclaration = declaration := by
                exact Option.some.inj (valueFound.symm.trans found)
              subst valueDeclaration
              obtain ⟨fieldValue, valueFieldFound, fieldTyped⟩ :=
                Lanius.Properties.ValuesHaveTypes.getElem?_typed _ fieldsTyped
                  fieldFound
              have fieldBorrows :
                  BorrowsValid program next afterStore fieldValue := by
                intro descriptor member
                exact cachedBorrows descriptor (by
                  simpa [valueBorrows] using
                    valueBorrows_mem_valueListBorrows
                      (List.mem_of_getElem? valueFieldFound) member)
              have suffixTyped : ProjectionHasType program
                  (.structure declaration.id) [.field field] fieldType :=
                .field declaration found fieldFound .nil
              simp only [evalPlace, baseResult, valueFieldFound]
              exact ⟨afterStore, storePreserved, cellsPreserved, nextTyped,
                .projected stored cellFound initialized rootTyped rootBorrows
                  (projectionTyped.trans suffixTyped) fieldTyped fieldBorrows⟩
  | trapped reason next =>
      rw [baseResult] at basePreserved
      simpa only [evalPlace, baseResult, PlaceOutcomeHasType] using basePreserved
  | exited code next =>
      rw [baseResult] at basePreserved
      simpa only [evalPlace, baseResult, PlaceOutcomeHasType] using basePreserved
  | outOfFuel =>
      simp [evalPlace, baseResult, PlaceOutcomeHasType]

theorem evalFieldPlace_has_runtime_type
    (fuel : Nat)
    (found : program.structure? typeId = some declaration)
    (fieldFound : declaration.fields[field]? = some fieldType)
    (basePreserved : RuntimePlaceOutcomeHasType program context state store
      (evalPlace fuel program state base) (.structure typeId)) :
    RuntimePlaceOutcomeHasType program context state store
      (evalPlace (fuel + 1) program state (.field base field)) fieldType := by
  cases baseResult : evalPlace fuel program state base with
  | done resolved next =>
      rw [baseResult] at basePreserved
      obtain ⟨afterStore, storePreserved, cellsPreserved, nextTyped,
        resolvedTyped⟩ := basePreserved
      cases resolvedTyped with
      | rootNoCachedValue stored cellFound =>
          simp only [evalPlace, baseResult]
          exact ⟨afterStore, storePreserved, cellsPreserved, nextTyped⟩
      | rootInitialized stored cellFound initialized rootTyped rootBorrows
          valueTyped cachedBorrows =>
          cases valueTyped with
          | «structure» valueDeclaration valueFound fieldsTyped =>
              have sameDeclaration : valueDeclaration = declaration :=
                Option.some.inj (valueFound.symm.trans found)
              subst valueDeclaration
              obtain ⟨fieldValue, valueFieldFound, fieldTyped⟩ :=
                Lanius.Properties.ValuesHaveTypes.getElem?_typed _ fieldsTyped
                  fieldFound
              have fieldBorrows :
                  BorrowsValid program next afterStore fieldValue := by
                intro descriptor member
                exact cachedBorrows descriptor (by
                  simpa [valueBorrows] using
                    valueBorrows_mem_valueListBorrows
                      (List.mem_of_getElem? valueFieldFound) member)
              simp only [evalPlace, baseResult, valueFieldFound,
                List.nil_append]
              refine ⟨afterStore, storePreserved, cellsPreserved, nextTyped,
                .projected stored cellFound initialized rootTyped rootBorrows
                  (.field declaration found fieldFound .nil) fieldTyped
                  fieldBorrows⟩
      | projected stored cellFound initialized rootTyped rootBorrows
          projectionTyped valueTyped cachedBorrows =>
          cases valueTyped with
          | «structure» valueDeclaration valueFound fieldsTyped =>
              have sameDeclaration : valueDeclaration = declaration :=
                Option.some.inj (valueFound.symm.trans found)
              subst valueDeclaration
              obtain ⟨fieldValue, valueFieldFound, fieldTyped⟩ :=
                Lanius.Properties.ValuesHaveTypes.getElem?_typed _ fieldsTyped
                  fieldFound
              have fieldBorrows :
                  BorrowsValid program next afterStore fieldValue := by
                intro descriptor member
                exact cachedBorrows descriptor (by
                  simpa [valueBorrows] using
                    valueBorrows_mem_valueListBorrows
                      (List.mem_of_getElem? valueFieldFound) member)
              have suffixTyped : ProjectionHasType program
                  (.structure declaration.id) [.field field] fieldType :=
                .field declaration found fieldFound .nil
              simp only [evalPlace, baseResult, valueFieldFound]
              exact ⟨afterStore, storePreserved, cellsPreserved, nextTyped,
                .projected stored cellFound initialized rootTyped rootBorrows
                  (projectionTyped.trans suffixTyped) fieldTyped fieldBorrows⟩
  | trapped reason next | exited reason next =>
      rw [baseResult] at basePreserved
      simpa only [evalPlace, baseResult,
        RuntimePlaceOutcomeHasType] using basePreserved
  | outOfFuel =>
      simp [evalPlace, baseResult, RuntimePlaceOutcomeHasType]

theorem evalArrayIndexPlace_has_type
    (fuel : Nat)
    (basePreserved : PlaceOutcomeHasType program context state store
      (evalPlace fuel program state base) (.array elementType length))
    (indexPreserved :
      ∀ (intermediate : State) (intermediateStore : StoreTyping),
        StateHasType program context intermediate intermediateStore →
        ValueOutcomeHasType program context intermediate intermediateStore
          (evalExpr fuel program intermediate indexExpression) indexType) :
    PlaceOutcomeHasType program context state store
      (evalPlace (fuel + 1) program state (.index base indexExpression))
      elementType := by
  cases baseResult : evalPlace fuel program state base with
  | done resolved afterBase =>
      rw [baseResult] at basePreserved
      obtain ⟨baseStore, baseStorePreserved, baseCellsPreserved,
        afterBaseTyped, resolvedTyped⟩ := basePreserved
      cases resolved with
      | mk root projections cached =>
          cases cached with
          | none =>
              simp only [evalPlace, baseResult]
              exact ⟨baseStore, baseStorePreserved, baseCellsPreserved,
                afterBaseTyped⟩
          | some cachedValue =>
              have cachedTyped := resolvedTyped.value_typed rfl
              cases cachedTyped with
              | array elements selectedElementType valueLength elementsTyped =>
                  have indexOutcome :=
                    indexPreserved afterBase baseStore afterBaseTyped
                  cases indexResult :
                      evalExpr fuel program afterBase indexExpression with
                  | done indexValue afterIndex =>
                      rw [indexResult] at indexOutcome
                      obtain ⟨indexStore, indexStorePreserved,
                        indexCellsPreserved, afterIndexTyped, indexTyped,
                        indexBorrows⟩ := indexOutcome
                      have resolvedAfterIndex := resolvedTyped.preserve
                        indexStorePreserved indexCellsPreserved afterIndexTyped
                      simp only [evalPlace, baseResult, indexResult]
                      cases converted : integerIndex indexValue with
                      | error reason =>
                          simp only
                          exact ⟨indexStore,
                            baseStorePreserved.trans indexStorePreserved,
                            baseCellsPreserved.trans indexCellsPreserved,
                            afterIndexTyped⟩
                      | ok selectedIndex =>
                          simp only
                          cases selected : elements[selectedIndex]? with
                          | none =>
                              simp only
                              exact ⟨indexStore,
                                baseStorePreserved.trans indexStorePreserved,
                                baseCellsPreserved.trans indexCellsPreserved,
                                afterIndexTyped⟩
                          | some value =>
                              simp only
                              exact ⟨indexStore,
                                baseStorePreserved.trans indexStorePreserved,
                                baseCellsPreserved.trans indexCellsPreserved,
                                afterIndexTyped,
                                resolvedAfterIndex.append_array_index rfl selected⟩
                  | trapped reason next =>
                      rw [indexResult] at indexOutcome
                      simpa only [evalPlace, baseResult, indexResult,
                        ValueOutcomeHasType, PlaceOutcomeHasType] using
                          indexOutcome.prepend baseStorePreserved
                            baseCellsPreserved
                  | exited code next =>
                      rw [indexResult] at indexOutcome
                      simpa only [evalPlace, baseResult, indexResult,
                        ValueOutcomeHasType, PlaceOutcomeHasType] using
                          indexOutcome.prepend baseStorePreserved
                            baseCellsPreserved
                  | outOfFuel =>
                      simp [evalPlace, baseResult, indexResult,
                        PlaceOutcomeHasType]
  | trapped reason next =>
      rw [baseResult] at basePreserved
      simpa only [evalPlace, baseResult, PlaceOutcomeHasType] using basePreserved
  | exited code next =>
      rw [baseResult] at basePreserved
      simpa only [evalPlace, baseResult, PlaceOutcomeHasType] using basePreserved
  | outOfFuel =>
      simp [evalPlace, baseResult, PlaceOutcomeHasType]

theorem evalArrayIndexPlace_has_runtime_type
    (fuel : Nat)
    (basePreserved : RuntimePlaceOutcomeHasType program context state store
      (evalPlace fuel program state base) (.array elementType length))
    (indexPreserved :
      ∀ (intermediate : State) (intermediateStore : StoreTyping),
        RuntimeStateHasType program context intermediate intermediateStore →
        RuntimeValueOutcomeHasExtendedType program context intermediate
          intermediateStore
          (evalExpr fuel program intermediate indexExpression) indexType) :
    RuntimePlaceOutcomeHasType program context state store
      (evalPlace (fuel + 1) program state (.index base indexExpression))
      elementType := by
  cases baseResult : evalPlace fuel program state base with
  | done resolved afterBase =>
      rw [baseResult] at basePreserved
      obtain ⟨baseStore, baseStorePreserved, baseCellsPreserved,
        afterBaseTyped, resolvedTyped⟩ := basePreserved
      cases resolved with
      | mk root projections cached =>
          cases cached with
          | none =>
              simp only [evalPlace, baseResult]
              exact ⟨baseStore, baseStorePreserved, baseCellsPreserved,
                afterBaseTyped⟩
          | some cachedValue =>
              have cachedTyped := resolvedTyped.value_typed rfl
              cases cachedTyped with
              | array elements selectedElementType valueLength elementsTyped =>
                  have indexOutcome :=
                    indexPreserved afterBase baseStore afterBaseTyped
                  cases indexResult :
                      evalExpr fuel program afterBase indexExpression with
                  | done indexValue afterIndex =>
                      rw [indexResult] at indexOutcome
                      obtain ⟨indexStore, indexStorePreserved,
                        indexCellsPreserved, afterIndexTyped, indexTyped,
                        indexBorrows⟩ := indexOutcome
                      have resolvedAfterIndex := resolvedTyped.preserve
                        indexStorePreserved indexCellsPreserved
                        afterIndexTyped.typed
                      simp only [evalPlace, baseResult, indexResult]
                      cases converted : integerIndex indexValue with
                      | error reason =>
                          simp only
                          exact ⟨indexStore,
                            baseStorePreserved.trans indexStorePreserved,
                            baseCellsPreserved.trans indexCellsPreserved,
                            afterIndexTyped⟩
                      | ok selectedIndex =>
                          simp only
                          cases selected : elements[selectedIndex]? with
                          | none =>
                              simp only
                              exact ⟨indexStore,
                                baseStorePreserved.trans indexStorePreserved,
                                baseCellsPreserved.trans indexCellsPreserved,
                                afterIndexTyped⟩
                          | some value =>
                              simp only
                              exact ⟨indexStore,
                                baseStorePreserved.trans indexStorePreserved,
                                baseCellsPreserved.trans indexCellsPreserved,
                                afterIndexTyped,
                                resolvedAfterIndex.append_array_index rfl
                                  selected⟩
                  | trapped reason next | exited reason next =>
                      rw [indexResult] at indexOutcome
                      simpa only [evalPlace, baseResult, indexResult,
                        RuntimeValueOutcomeHasExtendedType,
                        RuntimePlaceOutcomeHasType] using
                          indexOutcome.prepend baseStorePreserved
                            baseCellsPreserved
                  | outOfFuel =>
                      simp [evalPlace, baseResult, indexResult,
                        RuntimePlaceOutcomeHasType]
  | trapped reason next | exited reason next =>
      rw [baseResult] at basePreserved
      simpa only [evalPlace, baseResult,
        RuntimePlaceOutcomeHasType] using basePreserved
  | outOfFuel =>
      simp [evalPlace, baseResult, RuntimePlaceOutcomeHasType]

theorem evalSliceIndexPlace_has_type
    (fuel : Nat)
    (basePreserved : PlaceOutcomeHasType program context state store
      (evalPlace fuel program state base) (.slice elementType))
    (indexPreserved :
      ∀ (intermediate : State) (intermediateStore : StoreTyping),
        StateHasType program context intermediate intermediateStore →
        ValueOutcomeHasType program context intermediate intermediateStore
          (evalExpr fuel program intermediate indexExpression) indexType) :
    PlaceOutcomeHasType program context state store
      (evalPlace (fuel + 1) program state (.index base indexExpression))
      elementType := by
  cases baseResult : evalPlace fuel program state base with
  | done resolved afterBase =>
      rw [baseResult] at basePreserved
      obtain ⟨baseStore, baseStorePreserved, baseCellsPreserved,
        afterBaseTyped, resolvedTyped⟩ := basePreserved
      cases resolved with
      | mk root projections cached =>
          cases cached with
          | none =>
              simp only [evalPlace, baseResult]
              exact ⟨baseStore, baseStorePreserved, baseCellsPreserved,
                afterBaseTyped⟩
          | some cachedValue =>
              have cachedTyped := resolvedTyped.value_typed rfl
              have cachedBorrows := resolvedTyped.value_borrows rfl
              cases cachedTyped with
              | slice selectedElementType cell sliceProjections start sliceLength =>
                  have sliceValid := cachedBorrows
                    (.slice elementType cell sliceProjections start sliceLength)
                    (by simp [valueBorrows])
                  have indexOutcome :=
                    indexPreserved afterBase baseStore afterBaseTyped
                  cases indexResult :
                      evalExpr fuel program afterBase indexExpression with
                  | done indexValue afterIndex =>
                      rw [indexResult] at indexOutcome
                      obtain ⟨indexStore, indexStorePreserved,
                        indexCellsPreserved, afterIndexTyped, indexTyped,
                        indexBorrows⟩ := indexOutcome
                      have sliceValidAfterIndex := sliceValid.preserve
                        indexStorePreserved indexCellsPreserved afterIndexTyped
                      simp only [evalPlace, baseResult, indexResult]
                      cases converted : integerIndex indexValue with
                      | error reason =>
                          simp only
                          exact ⟨indexStore,
                            baseStorePreserved.trans indexStorePreserved,
                            baseCellsPreserved.trans indexCellsPreserved,
                            afterIndexTyped⟩
                      | ok selectedIndex =>
                          simp only
                          by_cases inBounds : selectedIndex < sliceLength
                          · rw [if_pos inBounds]
                            cases sliced : sliceValues afterIndex cell
                                sliceProjections start sliceLength with
                            | error reason =>
                                simp only
                                exact ⟨indexStore,
                                  baseStorePreserved.trans indexStorePreserved,
                                  baseCellsPreserved.trans indexCellsPreserved,
                                  afterIndexTyped⟩
                            | ok values =>
                                simp only
                                cases selected : values[selectedIndex]? with
                                | none =>
                                    simp only
                                    exact ⟨indexStore,
                                      baseStorePreserved.trans indexStorePreserved,
                                      baseCellsPreserved.trans indexCellsPreserved,
                                      afterIndexTyped⟩
                                | some value =>
                                    simp only
                                    have valueTyped :=
                                      sliceValues_getElem?_typed selectedIndex
                                        sliceValidAfterIndex sliced selected
                                    have valueBorrows :=
                                      sliceValues_getElem?_borrows selectedIndex
                                        afterIndexTyped sliceValidAfterIndex sliced
                                        selected
                                    exact ⟨indexStore,
                                      baseStorePreserved.trans indexStorePreserved,
                                      baseCellsPreserved.trans indexCellsPreserved,
                                      afterIndexTyped,
                                      ResolvedPlaceHasType.slice_index selectedIndex
                                        afterIndexTyped sliceValidAfterIndex
                                        valueTyped valueBorrows⟩
                          · rw [if_neg inBounds]
                            exact ⟨indexStore,
                              baseStorePreserved.trans indexStorePreserved,
                              baseCellsPreserved.trans indexCellsPreserved,
                              afterIndexTyped⟩
                  | trapped reason next =>
                      rw [indexResult] at indexOutcome
                      simpa only [evalPlace, baseResult, indexResult,
                        ValueOutcomeHasType, PlaceOutcomeHasType] using
                          indexOutcome.prepend baseStorePreserved
                            baseCellsPreserved
                  | exited code next =>
                      rw [indexResult] at indexOutcome
                      simpa only [evalPlace, baseResult, indexResult,
                        ValueOutcomeHasType, PlaceOutcomeHasType] using
                          indexOutcome.prepend baseStorePreserved
                            baseCellsPreserved
                  | outOfFuel =>
                      simp [evalPlace, baseResult, indexResult,
                        PlaceOutcomeHasType]
  | trapped reason next =>
      rw [baseResult] at basePreserved
      simpa only [evalPlace, baseResult, PlaceOutcomeHasType] using basePreserved
  | exited code next =>
      rw [baseResult] at basePreserved
      simpa only [evalPlace, baseResult, PlaceOutcomeHasType] using basePreserved
  | outOfFuel =>
      simp [evalPlace, baseResult, PlaceOutcomeHasType]

theorem evalSliceIndexPlace_has_runtime_type
    (fuel : Nat)
    (basePreserved : RuntimePlaceOutcomeHasType program context state store
      (evalPlace fuel program state base) (.slice elementType))
    (indexPreserved :
      ∀ (intermediate : State) (intermediateStore : StoreTyping),
        RuntimeStateHasType program context intermediate intermediateStore →
        RuntimeValueOutcomeHasExtendedType program context intermediate
          intermediateStore
          (evalExpr fuel program intermediate indexExpression) indexType) :
    RuntimePlaceOutcomeHasType program context state store
      (evalPlace (fuel + 1) program state (.index base indexExpression))
      elementType := by
  cases baseResult : evalPlace fuel program state base with
  | done resolved afterBase =>
      rw [baseResult] at basePreserved
      obtain ⟨baseStore, baseStorePreserved, baseCellsPreserved,
        afterBaseTyped, resolvedTyped⟩ := basePreserved
      cases resolved with
      | mk root projections cached =>
          cases cached with
          | none =>
              simp only [evalPlace, baseResult]
              exact ⟨baseStore, baseStorePreserved, baseCellsPreserved,
                afterBaseTyped⟩
          | some cachedValue =>
              have cachedTyped := resolvedTyped.value_typed rfl
              have cachedBorrows := resolvedTyped.value_borrows rfl
              cases cachedTyped with
              | slice selectedElementType cell sliceProjections start
                  sliceLength =>
                  have sliceValid := cachedBorrows
                    (.slice elementType cell sliceProjections start sliceLength)
                    (by simp [valueBorrows])
                  have indexOutcome :=
                    indexPreserved afterBase baseStore afterBaseTyped
                  cases indexResult :
                      evalExpr fuel program afterBase indexExpression with
                  | done indexValue afterIndex =>
                      rw [indexResult] at indexOutcome
                      obtain ⟨indexStore, indexStorePreserved,
                        indexCellsPreserved, afterIndexTyped, indexTyped,
                        indexBorrows⟩ := indexOutcome
                      have sliceValidAfterIndex := sliceValid.preserve
                        indexStorePreserved indexCellsPreserved
                        afterIndexTyped.typed
                      simp only [evalPlace, baseResult, indexResult]
                      cases converted : integerIndex indexValue with
                      | error reason =>
                          simp only
                          exact ⟨indexStore,
                            baseStorePreserved.trans indexStorePreserved,
                            baseCellsPreserved.trans indexCellsPreserved,
                            afterIndexTyped⟩
                      | ok selectedIndex =>
                          simp only
                          by_cases inBounds : selectedIndex < sliceLength
                          · rw [if_pos inBounds]
                            cases sliced : sliceValues afterIndex cell
                                sliceProjections start sliceLength with
                            | error reason =>
                                simp only
                                exact ⟨indexStore,
                                  baseStorePreserved.trans indexStorePreserved,
                                  baseCellsPreserved.trans indexCellsPreserved,
                                  afterIndexTyped⟩
                            | ok values =>
                                simp only
                                cases selected : values[selectedIndex]? with
                                | none =>
                                    simp only
                                    exact ⟨indexStore,
                                      baseStorePreserved.trans
                                        indexStorePreserved,
                                      baseCellsPreserved.trans
                                        indexCellsPreserved,
                                      afterIndexTyped⟩
                                | some value =>
                                    simp only
                                    have valueTyped :=
                                      sliceValues_getElem?_typed selectedIndex
                                        sliceValidAfterIndex sliced selected
                                    have valueBorrows :=
                                      sliceValues_getElem?_borrows selectedIndex
                                        afterIndexTyped.typed sliceValidAfterIndex
                                        sliced selected
                                    exact ⟨indexStore,
                                      baseStorePreserved.trans
                                        indexStorePreserved,
                                      baseCellsPreserved.trans
                                        indexCellsPreserved,
                                      afterIndexTyped,
                                      ResolvedPlaceHasType.slice_index
                                        selectedIndex afterIndexTyped.typed
                                        sliceValidAfterIndex valueTyped
                                        valueBorrows⟩
                          · rw [if_neg inBounds]
                            exact ⟨indexStore,
                              baseStorePreserved.trans indexStorePreserved,
                              baseCellsPreserved.trans indexCellsPreserved,
                              afterIndexTyped⟩
                  | trapped reason next | exited reason next =>
                      rw [indexResult] at indexOutcome
                      simpa only [evalPlace, baseResult, indexResult,
                        RuntimeValueOutcomeHasExtendedType,
                        RuntimePlaceOutcomeHasType] using
                          indexOutcome.prepend baseStorePreserved
                            baseCellsPreserved
                  | outOfFuel =>
                      simp [evalPlace, baseResult, indexResult,
                        RuntimePlaceOutcomeHasType]
  | trapped reason next | exited reason next =>
      rw [baseResult] at basePreserved
      simpa only [evalPlace, baseResult,
        RuntimePlaceOutcomeHasType] using basePreserved
  | outOfFuel =>
      simp [evalPlace, baseResult, RuntimePlaceOutcomeHasType]

theorem evalPlace_has_type
    (fuel : Nat)
    (stateTyped : StateHasType program context state store)
    (placeTyped : PlaceHasType program context place type)
    (expressionPreserved :
      ∀ (expressionFuel : Nat)
        (intermediate : State) (intermediateStore : StoreTyping)
        (expression : Expr) (expressionType : Ty),
        StateHasType program context intermediate intermediateStore →
        ExprHasType program context expression expressionType →
        ValueOutcomeHasType program context intermediate intermediateStore
          (evalExpr expressionFuel program intermediate expression)
          expressionType) :
    PlaceOutcomeHasType program context state store
      (evalPlace (fuel + 1) program state place) type := by
  induction fuel generalizing state store place type with
  | zero =>
      cases placeTyped with
      | «local» found => exact evalLocalPlace_has_type 0 stateTyped found
      | field base declaration found fieldFound =>
          simp [evalPlace, PlaceOutcomeHasType]
      | indexArray base index integerIndex =>
          simp [evalPlace, PlaceOutcomeHasType]
      | indexSlice base index integerIndex =>
          simp [evalPlace, PlaceOutcomeHasType]
  | succ fuel inductionHypothesis =>
      cases placeTyped with
      | «local» found =>
          exact evalLocalPlace_has_type (fuel + 1) stateTyped found
      | field base declaration found fieldFound =>
          exact evalFieldPlace_has_type (fuel + 1) found fieldFound
            (inductionHypothesis stateTyped base)
      | indexArray base index integerIndex =>
          exact evalArrayIndexPlace_has_type (fuel + 1)
            (inductionHypothesis stateTyped base)
            (fun intermediate intermediateStore intermediateTyped =>
              expressionPreserved (fuel + 1) intermediate intermediateStore _ _
                intermediateTyped index)
      | indexSlice base index integerIndex =>
          exact evalSliceIndexPlace_has_type (fuel + 1)
            (inductionHypothesis stateTyped base)
            (fun intermediate intermediateStore intermediateTyped =>
              expressionPreserved (fuel + 1) intermediate intermediateStore _ _
                intermediateTyped index)

theorem evalPlace_has_runtime_type
    (fuel : Nat)
    (stateTyped : RuntimeStateHasType program context state store)
    (placeTyped : PlaceHasType program context place type)
    (expressionPreserved :
      ∀ (expressionFuel : Nat)
        (intermediate : State) (intermediateStore : StoreTyping)
        (expression : Expr) (expressionType : Ty),
        RuntimeStateHasType program context intermediate intermediateStore →
        ExprHasType program context expression expressionType →
        RuntimeValueOutcomeHasExtendedType program context intermediate
          intermediateStore
          (evalExpr expressionFuel program intermediate expression)
          expressionType) :
    RuntimePlaceOutcomeHasType program context state store
      (evalPlace (fuel + 1) program state place) type := by
  induction fuel generalizing state store place type with
  | zero =>
      cases placeTyped with
      | «local» found =>
          exact evalLocalPlace_has_runtime_type 0 stateTyped found
      | field base declaration found fieldFound =>
          simp [evalPlace, RuntimePlaceOutcomeHasType]
      | indexArray base index integerIndex =>
          simp [evalPlace, RuntimePlaceOutcomeHasType]
      | indexSlice base index integerIndex =>
          simp [evalPlace, RuntimePlaceOutcomeHasType]
  | succ fuel inductionHypothesis =>
      cases placeTyped with
      | «local» found =>
          exact evalLocalPlace_has_runtime_type (fuel + 1) stateTyped found
      | field base declaration found fieldFound =>
          exact evalFieldPlace_has_runtime_type (fuel + 1) found fieldFound
            (inductionHypothesis stateTyped base)
      | indexArray base index integerIndex =>
          exact evalArrayIndexPlace_has_runtime_type (fuel + 1)
            (inductionHypothesis stateTyped base)
            (fun intermediate intermediateStore intermediateTyped =>
              expressionPreserved (fuel + 1) intermediate intermediateStore _ _
                intermediateTyped index)
      | indexSlice base index integerIndex =>
          exact evalSliceIndexPlace_has_runtime_type (fuel + 1)
            (inductionHypothesis stateTyped base)
            (fun intermediate intermediateStore intermediateTyped =>
              expressionPreserved (fuel + 1) intermediate intermediateStore _ _
                intermediateTyped index)

theorem evalPlace_atFuel_has_runtime_type
    (fuel : Nat)
    (stateTyped : RuntimeStateHasType program context state store)
    (placeTyped : PlaceHasType program context place type)
    (expressionPreserved : RuntimeExpressionsPreserveTypesBelow program limit)
    (fuelLt : fuel < limit) :
    RuntimePlaceOutcomeHasType program context state store
      (evalPlace fuel program state place) type := by
  induction fuel generalizing state store place type with
  | zero => simp [evalPlace, RuntimePlaceOutcomeHasType]
  | succ fuel induction =>
      have smaller : fuel < limit :=
        Nat.lt_trans (Nat.lt_succ_self fuel) fuelLt
      cases placeTyped with
      | «local» found =>
          exact evalLocalPlace_has_runtime_type fuel stateTyped found
      | field base declaration found fieldFound =>
          exact evalFieldPlace_has_runtime_type fuel found fieldFound
            (induction stateTyped base smaller)
      | indexArray base index integerIndex =>
          exact evalArrayIndexPlace_has_runtime_type fuel
            (induction stateTyped base smaller)
            (fun intermediate intermediateStore intermediateTyped =>
              expressionPreserved fuel smaller _ _ _ _ _ intermediateTyped
                index)
      | indexSlice base index integerIndex =>
          exact evalSliceIndexPlace_has_runtime_type fuel
            (induction stateTyped base smaller)
            (fun intermediate intermediateStore intermediateTyped =>
              expressionPreserved fuel smaller _ _ _ _ _ intermediateTyped
                index)

theorem evalCast_has_type
    (fuel : Nat)
    (conversion : ScalarCast source destination)
    (operandPreserved : ValueOutcomeHasType program context state store
      (evalExpr fuel program state operand) (.scalar source)) :
    ValueOutcomeHasType program context state store
      (evalExpr (fuel + 1) program state (.cast destination operand))
      (.scalar destination) := by
  cases operandResult : evalExpr fuel program state operand with
  | done value next =>
      rw [operandResult] at operandPreserved
      obtain ⟨after, extension, cellsPreserved, nextTyped, valueTyped,
        valueBorrows⟩ :=
        operandPreserved
      simp only [evalExpr, operandResult]
      cases castResult : evalScalarCast program.target destination value with
      | error reason =>
          exact ⟨after, extension, cellsPreserved, nextTyped⟩
      | ok result =>
          have resultTyped := evalScalarCast_preserves_type conversion
            valueTyped castResult
          exact ⟨after, extension, cellsPreserved, nextTyped, resultTyped,
            (Lanius.Properties.ValueHasType.scalar_is_closed
              resultTyped).borrowsValid⟩
  | trapped reason next =>
      rw [operandResult] at operandPreserved
      simpa only [evalExpr, operandResult, ValueOutcomeHasType] using
        operandPreserved
  | exited code next =>
      rw [operandResult] at operandPreserved
      simpa only [evalExpr, operandResult, ValueOutcomeHasType] using
        operandPreserved
  | outOfFuel =>
      simp [evalExpr, operandResult, ValueOutcomeHasType]

theorem evalUnary_has_type
    (fuel : Nat)
    (operation : UnaryOpHasType op inputType outputType)
    (operandPreserved : ValueOutcomeHasType program context state store
      (evalExpr fuel program state operand) inputType) :
    ValueOutcomeHasType program context state store
      (evalExpr (fuel + 1) program state (.unary op operand)) outputType := by
  cases operandResult : evalExpr fuel program state operand with
  | done value next =>
      rw [operandResult] at operandPreserved
      obtain ⟨after, extension, cellsPreserved, nextTyped, valueTyped,
        valueBorrows⟩ :=
        operandPreserved
      simp only [evalExpr, operandResult]
      cases unaryResult : evalUnaryValue program.target op value with
      | error reason =>
          exact ⟨after, extension, cellsPreserved, nextTyped⟩
      | ok result =>
          have resultTyped := evalUnaryValue_preserves_type operation
            valueTyped unaryResult
          obtain ⟨scalar, outputScalar⟩ :=
            Lanius.Properties.UnaryOpHasType.output_is_scalar operation
          subst outputType
          have resultClosed : ValueIsClosed result :=
            Lanius.Properties.ValueHasType.scalar_is_closed resultTyped
          exact ⟨after, extension, cellsPreserved, nextTyped, resultTyped,
            resultClosed.borrowsValid⟩
  | trapped reason next =>
      rw [operandResult] at operandPreserved
      simpa only [evalExpr, operandResult, ValueOutcomeHasType] using
        operandPreserved
  | exited code next =>
      rw [operandResult] at operandPreserved
      simpa only [evalExpr, operandResult, ValueOutcomeHasType] using
        operandPreserved
  | outOfFuel =>
      simp [evalExpr, operandResult, ValueOutcomeHasType]

theorem evalCast_has_runtime_type
    (fuel : Nat)
    (conversion : ScalarCast source destination)
    (operandPreserved : RuntimeValueOutcomeHasExtendedType program context
      state store (evalExpr fuel program state operand) (.scalar source)) :
    RuntimeValueOutcomeHasExtendedType program context state store
      (evalExpr (fuel + 1) program state (.cast destination operand))
      (.scalar destination) := by
  cases operandResult : evalExpr fuel program state operand with
  | done value next =>
      rw [operandResult] at operandPreserved
      obtain ⟨after, extension, cellsPreserved, nextTyped, valueTyped,
        valueBorrows⟩ := operandPreserved
      simp only [evalExpr, operandResult]
      cases castResult : evalScalarCast program.target destination value with
      | error reason =>
          exact ⟨after, extension, cellsPreserved, nextTyped⟩
      | ok result =>
          have resultTyped := evalScalarCast_preserves_type conversion
            valueTyped castResult
          exact ⟨after, extension, cellsPreserved, nextTyped, resultTyped,
            (Lanius.Properties.ValueHasType.scalar_is_closed
              resultTyped).borrowsValid⟩
  | trapped reason next | exited reason next =>
      rw [operandResult] at operandPreserved
      simpa only [evalExpr, operandResult,
        RuntimeValueOutcomeHasExtendedType] using operandPreserved
  | outOfFuel =>
      simp [evalExpr, operandResult, RuntimeValueOutcomeHasExtendedType]

theorem evalUnary_has_runtime_type
    (fuel : Nat)
    (operation : UnaryOpHasType op inputType outputType)
    (operandPreserved : RuntimeValueOutcomeHasExtendedType program context
      state store (evalExpr fuel program state operand) inputType) :
    RuntimeValueOutcomeHasExtendedType program context state store
      (evalExpr (fuel + 1) program state (.unary op operand)) outputType := by
  cases operandResult : evalExpr fuel program state operand with
  | done value next =>
      rw [operandResult] at operandPreserved
      obtain ⟨after, extension, cellsPreserved, nextTyped, valueTyped,
        valueBorrows⟩ := operandPreserved
      simp only [evalExpr, operandResult]
      cases unaryResult : evalUnaryValue program.target op value with
      | error reason =>
          exact ⟨after, extension, cellsPreserved, nextTyped⟩
      | ok result =>
          have resultTyped := evalUnaryValue_preserves_type operation
            valueTyped unaryResult
          obtain ⟨scalar, outputScalar⟩ :=
            Lanius.Properties.UnaryOpHasType.output_is_scalar operation
          subst outputType
          have resultClosed : ValueIsClosed result :=
            Lanius.Properties.ValueHasType.scalar_is_closed resultTyped
          exact ⟨after, extension, cellsPreserved, nextTyped, resultTyped,
            resultClosed.borrowsValid⟩
  | trapped reason next | exited reason next =>
      rw [operandResult] at operandPreserved
      simpa only [evalExpr, operandResult,
        RuntimeValueOutcomeHasExtendedType] using operandPreserved
  | outOfFuel =>
      simp [evalExpr, operandResult, RuntimeValueOutcomeHasExtendedType]

theorem evalEagerBinary_has_type
    (fuel : Nat)
    (operation : BinaryOpHasType op leftType rightType resultType)
    (notAnd : op ≠ .logicalAnd)
    (notOr : op ≠ .logicalOr)
    (leftPreserved : ValueOutcomeHasType program context state store
      (evalExpr fuel program state left) leftType)
    (rightPreserved :
      ∀ (intermediate : State) (intermediateStore : StoreTyping),
        StateHasType program context intermediate intermediateStore →
        ValueOutcomeHasType program context intermediate intermediateStore
          (evalExpr fuel program intermediate right) rightType) :
    ValueOutcomeHasType program context state store
      (evalExpr (fuel + 1) program state (.binary op left right)) resultType := by
  cases leftResult : evalExpr fuel program state left with
  | done leftValue afterLeft =>
      rw [leftResult] at leftPreserved
      obtain ⟨leftStore, leftExtension, leftCellsPreserved, afterLeftTyped,
        leftTyped, leftBorrows⟩ := leftPreserved
      have rightOutcome := rightPreserved afterLeft leftStore afterLeftTyped
      cases rightResult : evalExpr fuel program afterLeft right with
      | done rightValue afterRight =>
          rw [rightResult] at rightOutcome
          obtain ⟨rightStore, rightExtension, rightCellsPreserved,
            afterRightTyped, rightTyped, rightBorrows⟩ := rightOutcome
          simp only [evalExpr, leftResult, rightResult]
          cases binaryResult : evalBinaryValue program.target op leftValue rightValue with
          | error reason =>
              exact ⟨rightStore, leftExtension.trans rightExtension,
                leftCellsPreserved.trans rightCellsPreserved, afterRightTyped⟩
          | ok result =>
              have resultTyped := evalBinaryValue_preserves_type operation
                leftTyped rightTyped binaryResult
              obtain ⟨scalar, resultScalar⟩ :=
                Lanius.Properties.BinaryOpHasType.output_is_scalar operation
              subst resultType
              exact ⟨rightStore, leftExtension.trans rightExtension,
                leftCellsPreserved.trans rightCellsPreserved, afterRightTyped,
                resultTyped,
                (Lanius.Properties.ValueHasType.scalar_is_closed
                  resultTyped).borrowsValid⟩
      | trapped reason next =>
          rw [rightResult] at rightOutcome
          simpa only [evalExpr, notAnd, notOr, leftResult, rightResult,
            ValueOutcomeHasType] using
              rightOutcome.prepend leftExtension leftCellsPreserved
      | exited code next =>
          rw [rightResult] at rightOutcome
          simpa only [evalExpr, notAnd, notOr, leftResult, rightResult,
            ValueOutcomeHasType] using
              rightOutcome.prepend leftExtension leftCellsPreserved
      | outOfFuel =>
          simp [evalExpr, leftResult, rightResult,
            ValueOutcomeHasType]
  | trapped reason next =>
      rw [leftResult] at leftPreserved
      simpa only [evalExpr, notAnd, notOr, leftResult, ValueOutcomeHasType] using
        leftPreserved
  | exited code next =>
      rw [leftResult] at leftPreserved
      simpa only [evalExpr, notAnd, notOr, leftResult, ValueOutcomeHasType] using
        leftPreserved
  | outOfFuel =>
      simp [evalExpr, leftResult, ValueOutcomeHasType]

theorem evalEagerBinary_has_runtime_type
    (fuel : Nat)
    (operation : BinaryOpHasType op leftType rightType resultType)
    (notAnd : op ≠ .logicalAnd)
    (notOr : op ≠ .logicalOr)
    (leftPreserved : RuntimeValueOutcomeHasExtendedType program context state
      store (evalExpr fuel program state left) leftType)
    (rightPreserved :
      ∀ (intermediate : State) (intermediateStore : StoreTyping),
        RuntimeStateHasType program context intermediate intermediateStore →
        RuntimeValueOutcomeHasExtendedType program context intermediate
          intermediateStore (evalExpr fuel program intermediate right)
          rightType) :
    RuntimeValueOutcomeHasExtendedType program context state store
      (evalExpr (fuel + 1) program state (.binary op left right))
      resultType := by
  cases leftResult : evalExpr fuel program state left with
  | done leftValue afterLeft =>
      rw [leftResult] at leftPreserved
      obtain ⟨leftStore, leftExtension, leftCellsPreserved, afterLeftTyped,
        leftTyped, leftBorrows⟩ := leftPreserved
      have rightOutcome := rightPreserved afterLeft leftStore afterLeftTyped
      cases rightResult : evalExpr fuel program afterLeft right with
      | done rightValue afterRight =>
          rw [rightResult] at rightOutcome
          obtain ⟨rightStore, rightExtension, rightCellsPreserved,
            afterRightTyped, rightTyped, rightBorrows⟩ := rightOutcome
          simp only [evalExpr, leftResult, rightResult]
          cases binaryResult :
              evalBinaryValue program.target op leftValue rightValue with
          | error reason =>
              exact ⟨rightStore, leftExtension.trans rightExtension,
                leftCellsPreserved.trans rightCellsPreserved,
                afterRightTyped⟩
          | ok result =>
              have resultTyped := evalBinaryValue_preserves_type operation
                leftTyped rightTyped binaryResult
              obtain ⟨scalar, resultScalar⟩ :=
                Lanius.Properties.BinaryOpHasType.output_is_scalar operation
              subst resultType
              exact ⟨rightStore, leftExtension.trans rightExtension,
                leftCellsPreserved.trans rightCellsPreserved, afterRightTyped,
                resultTyped,
                (Lanius.Properties.ValueHasType.scalar_is_closed
                  resultTyped).borrowsValid⟩
      | trapped reason next | exited reason next =>
          rw [rightResult] at rightOutcome
          simpa only [evalExpr, notAnd, notOr, leftResult, rightResult,
            RuntimeValueOutcomeHasExtendedType] using
              rightOutcome.prepend leftExtension leftCellsPreserved
      | outOfFuel =>
          simp [evalExpr, leftResult, rightResult,
            RuntimeValueOutcomeHasExtendedType]
  | trapped reason next | exited reason next =>
      rw [leftResult] at leftPreserved
      simpa only [evalExpr, notAnd, notOr, leftResult,
        RuntimeValueOutcomeHasExtendedType] using leftPreserved
  | outOfFuel =>
      simp [evalExpr, leftResult, RuntimeValueOutcomeHasExtendedType]

theorem evalLogicalAnd_has_type
    (fuel : Nat)
    (leftPreserved : ValueOutcomeHasType program context state store
      (evalExpr fuel program state left) (.scalar .bool))
    (rightPreserved :
      ∀ (intermediate : State) (intermediateStore : StoreTyping),
        StateHasType program context intermediate intermediateStore →
        ValueOutcomeHasType program context intermediate intermediateStore
          (evalExpr fuel program intermediate right) (.scalar .bool)) :
    ValueOutcomeHasType program context state store
      (evalExpr (fuel + 1) program state (.binary .logicalAnd left right))
      (.scalar .bool) := by
  cases leftResult : evalExpr fuel program state left with
  | done leftValue afterLeft =>
      rw [leftResult] at leftPreserved
      obtain ⟨leftStore, leftExtension, leftCellsPreserved, afterLeftTyped,
        leftTyped, leftBorrows⟩ := leftPreserved
      cases leftTyped with
      | boolean leftBoolean =>
          cases leftBoolean with
          | false =>
              simp only [evalExpr, leftResult]
              exact ⟨leftStore, leftExtension, leftCellsPreserved,
                afterLeftTyped, .boolean false,
                (show ValueIsClosed (.boolean false) by rfl).borrowsValid⟩
          | true =>
              have rightOutcome := rightPreserved afterLeft leftStore afterLeftTyped
              simpa only [evalExpr, leftResult] using
                rightOutcome.prepend leftExtension leftCellsPreserved
  | trapped reason next =>
      rw [leftResult] at leftPreserved
      simpa only [evalExpr, leftResult, ValueOutcomeHasType] using leftPreserved
  | exited code next =>
      rw [leftResult] at leftPreserved
      simpa only [evalExpr, leftResult, ValueOutcomeHasType] using leftPreserved
  | outOfFuel =>
      simp [evalExpr, leftResult, ValueOutcomeHasType]

theorem evalLogicalOr_has_type
    (fuel : Nat)
    (leftPreserved : ValueOutcomeHasType program context state store
      (evalExpr fuel program state left) (.scalar .bool))
    (rightPreserved :
      ∀ (intermediate : State) (intermediateStore : StoreTyping),
        StateHasType program context intermediate intermediateStore →
        ValueOutcomeHasType program context intermediate intermediateStore
          (evalExpr fuel program intermediate right) (.scalar .bool)) :
    ValueOutcomeHasType program context state store
      (evalExpr (fuel + 1) program state (.binary .logicalOr left right))
      (.scalar .bool) := by
  cases leftResult : evalExpr fuel program state left with
  | done leftValue afterLeft =>
      rw [leftResult] at leftPreserved
      obtain ⟨leftStore, leftExtension, leftCellsPreserved, afterLeftTyped,
        leftTyped, leftBorrows⟩ := leftPreserved
      cases leftTyped with
      | boolean leftBoolean =>
          cases leftBoolean with
          | false =>
              have rightOutcome := rightPreserved afterLeft leftStore afterLeftTyped
              simpa only [evalExpr, leftResult] using
                rightOutcome.prepend leftExtension leftCellsPreserved
          | true =>
              simp only [evalExpr, leftResult]
              exact ⟨leftStore, leftExtension, leftCellsPreserved,
                afterLeftTyped, .boolean true,
                (show ValueIsClosed (.boolean true) by rfl).borrowsValid⟩
  | trapped reason next =>
      rw [leftResult] at leftPreserved
      simpa only [evalExpr, leftResult, ValueOutcomeHasType] using leftPreserved
  | exited code next =>
      rw [leftResult] at leftPreserved
      simpa only [evalExpr, leftResult, ValueOutcomeHasType] using leftPreserved
  | outOfFuel =>
      simp [evalExpr, leftResult, ValueOutcomeHasType]

theorem evalBinary_has_type
    (fuel : Nat)
    (operation : BinaryOpHasType op leftType rightType resultType)
    (leftPreserved : ValueOutcomeHasType program context state store
      (evalExpr fuel program state left) leftType)
    (rightPreserved :
      ∀ (intermediate : State) (intermediateStore : StoreTyping),
        StateHasType program context intermediate intermediateStore →
        ValueOutcomeHasType program context intermediate intermediateStore
          (evalExpr fuel program intermediate right) rightType) :
    ValueOutcomeHasType program context state store
      (evalExpr (fuel + 1) program state (.binary op left right)) resultType := by
  cases operation with
  | logicalAnd => exact evalLogicalAnd_has_type fuel leftPreserved rightPreserved
  | logicalOr => exact evalLogicalOr_has_type fuel leftPreserved rightPreserved
  | equal equality =>
      exact evalEagerBinary_has_type fuel (.equal equality) (by decide) (by decide)
        leftPreserved rightPreserved
  | notEqual equality =>
      exact evalEagerBinary_has_type fuel (.notEqual equality) (by decide) (by decide)
        leftPreserved rightPreserved
  | less ordered =>
      exact evalEagerBinary_has_type fuel (.less ordered) (by decide) (by decide)
        leftPreserved rightPreserved
  | lessEqual ordered =>
      exact evalEagerBinary_has_type fuel (.lessEqual ordered) (by decide) (by decide)
        leftPreserved rightPreserved
  | greater ordered =>
      exact evalEagerBinary_has_type fuel (.greater ordered) (by decide) (by decide)
        leftPreserved rightPreserved
  | greaterEqual ordered =>
      exact evalEagerBinary_has_type fuel (.greaterEqual ordered) (by decide) (by decide)
        leftPreserved rightPreserved
  | add arithmetic =>
      exact evalEagerBinary_has_type fuel (.add arithmetic) (by decide) (by decide)
        leftPreserved rightPreserved
  | pointerAdd offset =>
      exact evalEagerBinary_has_type fuel (.pointerAdd offset) (by decide) (by decide)
        leftPreserved rightPreserved
  | subtract arithmetic =>
      exact evalEagerBinary_has_type fuel (.subtract arithmetic) (by decide) (by decide)
        leftPreserved rightPreserved
  | pointerSubtract offset =>
      exact evalEagerBinary_has_type fuel (.pointerSubtract offset) (by decide) (by decide)
        leftPreserved rightPreserved
  | multiply arithmetic =>
      exact evalEagerBinary_has_type fuel (.multiply arithmetic) (by decide) (by decide)
        leftPreserved rightPreserved
  | divide arithmetic =>
      exact evalEagerBinary_has_type fuel (.divide arithmetic) (by decide) (by decide)
        leftPreserved rightPreserved
  | remainder integer =>
      exact evalEagerBinary_has_type fuel (.remainder integer) (by decide) (by decide)
        leftPreserved rightPreserved
  | bitAnd integer =>
      exact evalEagerBinary_has_type fuel (.bitAnd integer) (by decide) (by decide)
        leftPreserved rightPreserved
  | bitOr integer =>
      exact evalEagerBinary_has_type fuel (.bitOr integer) (by decide) (by decide)
        leftPreserved rightPreserved
  | bitXor integer =>
      exact evalEagerBinary_has_type fuel (.bitXor integer) (by decide) (by decide)
        leftPreserved rightPreserved
  | shiftLeft integer =>
      exact evalEagerBinary_has_type fuel (.shiftLeft integer) (by decide) (by decide)
        leftPreserved rightPreserved
  | shiftRight integer =>
      exact evalEagerBinary_has_type fuel (.shiftRight integer) (by decide) (by decide)
        leftPreserved rightPreserved

theorem evalLogicalAnd_has_runtime_type
    (fuel : Nat)
    (leftPreserved : RuntimeValueOutcomeHasExtendedType program context state
      store (evalExpr fuel program state left) (.scalar .bool))
    (rightPreserved :
      ∀ (intermediate : State) (intermediateStore : StoreTyping),
        RuntimeStateHasType program context intermediate intermediateStore →
        RuntimeValueOutcomeHasExtendedType program context intermediate
          intermediateStore (evalExpr fuel program intermediate right)
          (.scalar .bool)) :
    RuntimeValueOutcomeHasExtendedType program context state store
      (evalExpr (fuel + 1) program state (.binary .logicalAnd left right))
      (.scalar .bool) := by
  cases leftResult : evalExpr fuel program state left with
  | done leftValue afterLeft =>
      rw [leftResult] at leftPreserved
      obtain ⟨leftStore, leftExtension, leftCellsPreserved, afterLeftTyped,
        leftTyped, leftBorrows⟩ := leftPreserved
      cases leftTyped with
      | boolean leftBoolean =>
          cases leftBoolean with
          | false =>
              simp only [evalExpr, leftResult]
              exact ⟨leftStore, leftExtension, leftCellsPreserved,
                afterLeftTyped, .boolean false,
                (show ValueIsClosed (.boolean false) by rfl).borrowsValid⟩
          | true =>
              have rightOutcome :=
                rightPreserved afterLeft leftStore afterLeftTyped
              simpa only [evalExpr, leftResult] using
                rightOutcome.prepend leftExtension leftCellsPreserved
  | trapped reason next | exited reason next =>
      rw [leftResult] at leftPreserved
      simpa only [evalExpr, leftResult,
        RuntimeValueOutcomeHasExtendedType] using leftPreserved
  | outOfFuel =>
      simp [evalExpr, leftResult, RuntimeValueOutcomeHasExtendedType]

theorem evalLogicalOr_has_runtime_type
    (fuel : Nat)
    (leftPreserved : RuntimeValueOutcomeHasExtendedType program context state
      store (evalExpr fuel program state left) (.scalar .bool))
    (rightPreserved :
      ∀ (intermediate : State) (intermediateStore : StoreTyping),
        RuntimeStateHasType program context intermediate intermediateStore →
        RuntimeValueOutcomeHasExtendedType program context intermediate
          intermediateStore (evalExpr fuel program intermediate right)
          (.scalar .bool)) :
    RuntimeValueOutcomeHasExtendedType program context state store
      (evalExpr (fuel + 1) program state (.binary .logicalOr left right))
      (.scalar .bool) := by
  cases leftResult : evalExpr fuel program state left with
  | done leftValue afterLeft =>
      rw [leftResult] at leftPreserved
      obtain ⟨leftStore, leftExtension, leftCellsPreserved, afterLeftTyped,
        leftTyped, leftBorrows⟩ := leftPreserved
      cases leftTyped with
      | boolean leftBoolean =>
          cases leftBoolean with
          | false =>
              have rightOutcome :=
                rightPreserved afterLeft leftStore afterLeftTyped
              simpa only [evalExpr, leftResult] using
                rightOutcome.prepend leftExtension leftCellsPreserved
          | true =>
              simp only [evalExpr, leftResult]
              exact ⟨leftStore, leftExtension, leftCellsPreserved,
                afterLeftTyped, .boolean true,
                (show ValueIsClosed (.boolean true) by rfl).borrowsValid⟩
  | trapped reason next | exited reason next =>
      rw [leftResult] at leftPreserved
      simpa only [evalExpr, leftResult,
        RuntimeValueOutcomeHasExtendedType] using leftPreserved
  | outOfFuel =>
      simp [evalExpr, leftResult, RuntimeValueOutcomeHasExtendedType]

theorem evalBinary_has_runtime_type
    (fuel : Nat)
    (operation : BinaryOpHasType op leftType rightType resultType)
    (leftPreserved : RuntimeValueOutcomeHasExtendedType program context state
      store (evalExpr fuel program state left) leftType)
    (rightPreserved :
      ∀ (intermediate : State) (intermediateStore : StoreTyping),
        RuntimeStateHasType program context intermediate intermediateStore →
        RuntimeValueOutcomeHasExtendedType program context intermediate
          intermediateStore (evalExpr fuel program intermediate right)
          rightType) :
    RuntimeValueOutcomeHasExtendedType program context state store
      (evalExpr (fuel + 1) program state (.binary op left right))
      resultType := by
  cases operation with
  | logicalAnd =>
      exact evalLogicalAnd_has_runtime_type fuel leftPreserved rightPreserved
  | logicalOr =>
      exact evalLogicalOr_has_runtime_type fuel leftPreserved rightPreserved
  | equal equality =>
      exact evalEagerBinary_has_runtime_type fuel (.equal equality)
        (by decide) (by decide) leftPreserved rightPreserved
  | notEqual equality =>
      exact evalEagerBinary_has_runtime_type fuel (.notEqual equality)
        (by decide) (by decide) leftPreserved rightPreserved
  | less ordered =>
      exact evalEagerBinary_has_runtime_type fuel (.less ordered)
        (by decide) (by decide) leftPreserved rightPreserved
  | lessEqual ordered =>
      exact evalEagerBinary_has_runtime_type fuel (.lessEqual ordered)
        (by decide) (by decide) leftPreserved rightPreserved
  | greater ordered =>
      exact evalEagerBinary_has_runtime_type fuel (.greater ordered)
        (by decide) (by decide) leftPreserved rightPreserved
  | greaterEqual ordered =>
      exact evalEagerBinary_has_runtime_type fuel (.greaterEqual ordered)
        (by decide) (by decide) leftPreserved rightPreserved
  | add arithmetic =>
      exact evalEagerBinary_has_runtime_type fuel (.add arithmetic)
        (by decide) (by decide) leftPreserved rightPreserved
  | pointerAdd offset =>
      exact evalEagerBinary_has_runtime_type fuel (.pointerAdd offset)
        (by decide) (by decide) leftPreserved rightPreserved
  | subtract arithmetic =>
      exact evalEagerBinary_has_runtime_type fuel (.subtract arithmetic)
        (by decide) (by decide) leftPreserved rightPreserved
  | pointerSubtract offset =>
      exact evalEagerBinary_has_runtime_type fuel (.pointerSubtract offset)
        (by decide) (by decide) leftPreserved rightPreserved
  | multiply arithmetic =>
      exact evalEagerBinary_has_runtime_type fuel (.multiply arithmetic)
        (by decide) (by decide) leftPreserved rightPreserved
  | divide arithmetic =>
      exact evalEagerBinary_has_runtime_type fuel (.divide arithmetic)
        (by decide) (by decide) leftPreserved rightPreserved
  | remainder integer =>
      exact evalEagerBinary_has_runtime_type fuel (.remainder integer)
        (by decide) (by decide) leftPreserved rightPreserved
  | bitAnd integer =>
      exact evalEagerBinary_has_runtime_type fuel (.bitAnd integer)
        (by decide) (by decide) leftPreserved rightPreserved
  | bitOr integer =>
      exact evalEagerBinary_has_runtime_type fuel (.bitOr integer)
        (by decide) (by decide) leftPreserved rightPreserved
  | bitXor integer =>
      exact evalEagerBinary_has_runtime_type fuel (.bitXor integer)
        (by decide) (by decide) leftPreserved rightPreserved
  | shiftLeft integer =>
      exact evalEagerBinary_has_runtime_type fuel (.shiftLeft integer)
        (by decide) (by decide) leftPreserved rightPreserved
  | shiftRight integer =>
      exact evalEagerBinary_has_runtime_type fuel (.shiftRight integer)
        (by decide) (by decide) leftPreserved rightPreserved

theorem evalExprsNil_have_types
    (fuel : Nat)
    (stateTyped : StateHasType program context state store) :
    ValuesOutcomeHaveTypes program context state store
      (evalExprs (fuel + 1) program state []) [] := by
  simp only [evalExprs]
  refine ⟨store, StoreExtends.refl store, InitializedCellsPreserved.refl state,
    stateTyped, .nil, ?_⟩
  intro descriptor member
  simp [valueListBorrows] at member

theorem evalExprsCons_have_types
    (fuel : Nat)
    (headPreserved : ValueOutcomeHasType program context state store
      (evalExpr fuel program state head) headType)
    (tailPreserved :
      ∀ (intermediate : State) (intermediateStore : StoreTyping),
        StateHasType program context intermediate intermediateStore →
        ValuesOutcomeHaveTypes program context intermediate intermediateStore
          (evalExprs fuel program intermediate tail) tailTypes) :
    ValuesOutcomeHaveTypes program context state store
      (evalExprs (fuel + 1) program state (head :: tail))
      (headType :: tailTypes) := by
  cases headResult : evalExpr fuel program state head with
  | done headValue afterHead =>
      rw [headResult] at headPreserved
      obtain ⟨headStore, headStorePreserved, headCellsPreserved,
        afterHeadTyped, headTyped, headBorrows⟩ := headPreserved
      have tailOutcome := tailPreserved afterHead headStore afterHeadTyped
      cases tailResult : evalExprs fuel program afterHead tail with
      | done tailValues afterTail =>
          rw [tailResult] at tailOutcome
          obtain ⟨tailStore, tailStorePreserved, tailCellsPreserved,
            afterTailTyped, tailTyped, tailBorrows⟩ := tailOutcome
          simp only [evalExprs, headResult, tailResult]
          refine ⟨tailStore, headStorePreserved.trans tailStorePreserved,
            headCellsPreserved.trans tailCellsPreserved, afterTailTyped,
            .cons headTyped tailTyped, ?_⟩
          have headBorrowsAfterTail := headBorrows.preserve
            tailStorePreserved tailCellsPreserved afterTailTyped
          intro descriptor member
          simp only [valueListBorrows, List.mem_append] at member
          rcases member with headMember | tailMember
          · exact headBorrowsAfterTail descriptor headMember
          · exact tailBorrows descriptor tailMember
      | trapped reason next =>
          rw [tailResult] at tailOutcome
          simpa only [evalExprs, headResult, tailResult,
            ValuesOutcomeHaveTypes] using
              tailOutcome.prepend headStorePreserved headCellsPreserved
      | exited code next =>
          rw [tailResult] at tailOutcome
          simpa only [evalExprs, headResult, tailResult,
            ValuesOutcomeHaveTypes] using
              tailOutcome.prepend headStorePreserved headCellsPreserved
      | outOfFuel =>
          simp [evalExprs, headResult, tailResult, ValuesOutcomeHaveTypes]
  | trapped reason next =>
      rw [headResult] at headPreserved
      simpa only [evalExprs, headResult, ValueOutcomeHasType,
        ValuesOutcomeHaveTypes] using headPreserved
  | exited code next =>
      rw [headResult] at headPreserved
      simpa only [evalExprs, headResult, ValueOutcomeHasType,
        ValuesOutcomeHaveTypes] using headPreserved
  | outOfFuel =>
      simp [evalExprs, headResult, ValuesOutcomeHaveTypes]

theorem evalExprs_have_types
    (fuel : Nat)
    (stateTyped : StateHasType program context state store)
    (expressionsTyped : ExprsHaveTypes program context expressions types)
    (expressionPreserved :
      ∀ (expressionFuel : Nat)
        (intermediate : State) (intermediateStore : StoreTyping)
        (expression : Expr) (type : Ty),
        StateHasType program context intermediate intermediateStore →
        ExprHasType program context expression type →
        ValueOutcomeHasType program context intermediate intermediateStore
          (evalExpr expressionFuel program intermediate expression) type) :
    ValuesOutcomeHaveTypes program context state store
      (evalExprs (fuel + 1) program state expressions) types := by
  cases expressionsTyped with
  | nil => exact evalExprsNil_have_types fuel stateTyped
  | cons headTyped tailTyped =>
      exact evalExprsCons_have_types fuel
        (expressionPreserved fuel state store _ _ stateTyped headTyped)
        (fun intermediate intermediateStore intermediateTyped =>
          match fuel with
          | 0 => by simp [evalExprs, ValuesOutcomeHaveTypes]
          | tailFuel + 1 =>
              evalExprs_have_types tailFuel intermediateTyped tailTyped
                expressionPreserved)
termination_by fuel + expressions.length

theorem evalExprsNil_have_runtime_types
    (fuel : Nat)
    (stateTyped : RuntimeStateHasType program context state store) :
    RuntimeValuesOutcomeHaveTypes program context state store
      (evalExprs (fuel + 1) program state []) [] := by
  simp only [evalExprs]
  refine ⟨store, StoreExtends.refl store, InitializedCellsPreserved.refl state,
    stateTyped, .nil, ?_⟩
  intro descriptor member
  simp [valueListBorrows] at member

theorem evalExprsCons_have_runtime_types
    (fuel : Nat)
    (headPreserved : RuntimeValueOutcomeHasExtendedType program context state
      store (evalExpr fuel program state head) headType)
    (tailPreserved :
      ∀ (intermediate : State) (intermediateStore : StoreTyping),
        RuntimeStateHasType program context intermediate intermediateStore →
        RuntimeValuesOutcomeHaveTypes program context intermediate
          intermediateStore (evalExprs fuel program intermediate tail)
          tailTypes) :
    RuntimeValuesOutcomeHaveTypes program context state store
      (evalExprs (fuel + 1) program state (head :: tail))
      (headType :: tailTypes) := by
  cases headResult : evalExpr fuel program state head with
  | done headValue afterHead =>
      rw [headResult] at headPreserved
      obtain ⟨headStore, headStorePreserved, headCellsPreserved,
        afterHeadTyped, headTyped, headBorrows⟩ := headPreserved
      have tailOutcome := tailPreserved afterHead headStore afterHeadTyped
      cases tailResult : evalExprs fuel program afterHead tail with
      | done tailValues afterTail =>
          rw [tailResult] at tailOutcome
          obtain ⟨tailStore, tailStorePreserved, tailCellsPreserved,
            afterTailTyped, tailTyped, tailBorrows⟩ := tailOutcome
          simp only [evalExprs, headResult, tailResult]
          refine ⟨tailStore, headStorePreserved.trans tailStorePreserved,
            headCellsPreserved.trans tailCellsPreserved, afterTailTyped,
            .cons headTyped tailTyped, ?_⟩
          have headBorrowsAfterTail := headBorrows.preserve
            tailStorePreserved tailCellsPreserved afterTailTyped.typed
          intro descriptor member
          simp only [valueListBorrows, List.mem_append] at member
          rcases member with headMember | tailMember
          · exact headBorrowsAfterTail descriptor headMember
          · exact tailBorrows descriptor tailMember
      | trapped reason next =>
          rw [tailResult] at tailOutcome
          simpa only [evalExprs, headResult, tailResult,
            RuntimeValuesOutcomeHaveTypes] using
              tailOutcome.prepend headStorePreserved headCellsPreserved
      | exited code next =>
          rw [tailResult] at tailOutcome
          simpa only [evalExprs, headResult, tailResult,
            RuntimeValuesOutcomeHaveTypes] using
              tailOutcome.prepend headStorePreserved headCellsPreserved
      | outOfFuel =>
          simp [evalExprs, headResult, tailResult,
            RuntimeValuesOutcomeHaveTypes]
  | trapped reason next =>
      rw [headResult] at headPreserved
      simpa only [evalExprs, headResult,
        RuntimeValueOutcomeHasExtendedType,
        RuntimeValuesOutcomeHaveTypes] using headPreserved
  | exited code next =>
      rw [headResult] at headPreserved
      simpa only [evalExprs, headResult,
        RuntimeValueOutcomeHasExtendedType,
        RuntimeValuesOutcomeHaveTypes] using headPreserved
  | outOfFuel =>
      simp [evalExprs, headResult, RuntimeValuesOutcomeHaveTypes]

theorem evalExprs_have_runtime_types
    (fuel : Nat)
    (stateTyped : RuntimeStateHasType program context state store)
    (expressionsTyped : ExprsHaveTypes program context expressions types)
    (expressionPreserved :
      ∀ (expressionFuel : Nat)
        (intermediate : State) (intermediateStore : StoreTyping)
        (expression : Expr) (type : Ty),
        RuntimeStateHasType program context intermediate intermediateStore →
        ExprHasType program context expression type →
        RuntimeValueOutcomeHasExtendedType program context intermediate
          intermediateStore
          (evalExpr expressionFuel program intermediate expression) type) :
    RuntimeValuesOutcomeHaveTypes program context state store
      (evalExprs (fuel + 1) program state expressions) types := by
  cases expressionsTyped with
  | nil => exact evalExprsNil_have_runtime_types fuel stateTyped
  | cons headTyped tailTyped =>
      exact evalExprsCons_have_runtime_types fuel
        (expressionPreserved fuel state store _ _ stateTyped headTyped)
        (fun intermediate intermediateStore intermediateTyped =>
          match fuel with
          | 0 => by simp [evalExprs, RuntimeValuesOutcomeHaveTypes]
          | tailFuel + 1 =>
              evalExprs_have_runtime_types tailFuel intermediateTyped tailTyped
                expressionPreserved)
termination_by fuel + expressions.length

theorem evalExprs_atFuel_have_runtime_types
    (fuel : Nat)
    (stateTyped : RuntimeStateHasType program context state store)
    (expressionsTyped : ExprsHaveTypes program context expressions types)
    (expressionPreserved : RuntimeExpressionsPreserveTypesBelow program limit)
    (fuelLt : fuel < limit) :
    RuntimeValuesOutcomeHaveTypes program context state store
      (evalExprs fuel program state expressions) types := by
  induction fuel generalizing state store expressions types with
  | zero => simp [evalExprs, RuntimeValuesOutcomeHaveTypes]
  | succ fuel induction =>
      cases expressionsTyped with
      | nil => exact evalExprsNil_have_runtime_types fuel stateTyped
      | cons headTyped tailTyped =>
          have smaller : fuel < limit :=
            Nat.lt_trans (Nat.lt_succ_self fuel) fuelLt
          exact evalExprsCons_have_runtime_types fuel
            (expressionPreserved fuel smaller _ _ _ _ _ stateTyped headTyped)
            (fun intermediate intermediateStore intermediateTyped =>
              induction intermediateTyped tailTyped smaller)

theorem evalArray_has_type
    (fuel : Nat)
    (elementsPreserved : ValuesOutcomeHaveTypes program context state store
      (evalExprs fuel program state expressions)
      (List.replicate expressions.length elementType)) :
    ValueOutcomeHasType program context state store
      (evalExpr (fuel + 1) program state (.array elementType expressions))
      (.array elementType expressions.length) := by
  cases elementsResult : evalExprs fuel program state expressions with
  | done values next =>
      rw [elementsResult] at elementsPreserved
      obtain ⟨afterStore, storePreserved, cellsPreserved, nextTyped,
        valuesTyped, borrows⟩ := elementsPreserved
      simp only [evalExpr, elementsResult]
      have valueLength : values.length = expressions.length := by
        have aligned :=
          Lanius.Properties.ValuesHaveTypes.length_eq valuesTyped
        simpa using aligned
      exact ⟨afterStore, storePreserved, cellsPreserved, nextTyped,
        .array values elementType valueLength valuesTyped,
        (by simpa [BorrowsValid, ValuesBorrowsValid, valueBorrows] using borrows)⟩
  | trapped reason next =>
      rw [elementsResult] at elementsPreserved
      simpa only [evalExpr, elementsResult, ValueOutcomeHasType,
        ValuesOutcomeHaveTypes] using elementsPreserved
  | exited code next =>
      rw [elementsResult] at elementsPreserved
      simpa only [evalExpr, elementsResult, ValueOutcomeHasType,
        ValuesOutcomeHaveTypes] using elementsPreserved
  | outOfFuel =>
      simp [evalExpr, elementsResult, ValueOutcomeHasType]

theorem evalStructValue_has_type
    (fuel : Nat)
    (found : program.structure? typeId = some declaration)
    (fieldsPreserved : ValuesOutcomeHaveTypes program context state store
      (evalExprs fuel program state expressions) declaration.fields) :
    ValueOutcomeHasType program context state store
      (evalExpr (fuel + 1) program state (.structValue typeId expressions))
      (.structure typeId) := by
  cases fieldsResult : evalExprs fuel program state expressions with
  | done values next =>
      rw [fieldsResult] at fieldsPreserved
      obtain ⟨afterStore, storePreserved, cellsPreserved, nextTyped,
        valuesTyped, borrows⟩ := fieldsPreserved
      simp only [evalExpr, fieldsResult]
      have sameId : declaration.id = typeId := by
        simpa [Program.structure?] using List.find?_some found
      subst typeId
      exact ⟨afterStore, storePreserved, cellsPreserved, nextTyped,
        .structure declaration found valuesTyped,
        (by simpa [BorrowsValid, ValuesBorrowsValid, valueBorrows] using borrows)⟩
  | trapped reason next =>
      rw [fieldsResult] at fieldsPreserved
      simpa only [evalExpr, fieldsResult, ValueOutcomeHasType,
        ValuesOutcomeHaveTypes] using fieldsPreserved
  | exited code next =>
      rw [fieldsResult] at fieldsPreserved
      simpa only [evalExpr, fieldsResult, ValueOutcomeHasType,
        ValuesOutcomeHaveTypes] using fieldsPreserved
  | outOfFuel =>
      simp [evalExpr, fieldsResult, ValueOutcomeHasType]

theorem evalEnumValue_has_type
    (fuel : Nat)
    (found : program.enumeration? typeId = some declaration)
    (variantFound : declaration.variants[variant]? = some payloadTypes)
    (payloadPreserved : ValuesOutcomeHaveTypes program context state store
      (evalExprs fuel program state expressions) payloadTypes) :
    ValueOutcomeHasType program context state store
      (evalExpr (fuel + 1) program state
        (.enumValue typeId variant expressions))
      (.enumeration typeId) := by
  cases payloadResult : evalExprs fuel program state expressions with
  | done values next =>
      rw [payloadResult] at payloadPreserved
      obtain ⟨afterStore, storePreserved, cellsPreserved, nextTyped,
        valuesTyped, borrows⟩ := payloadPreserved
      simp only [evalExpr, payloadResult]
      have sameId : declaration.id = typeId := by
        simpa [Program.enumeration?] using List.find?_some found
      subst typeId
      exact ⟨afterStore, storePreserved, cellsPreserved, nextTyped,
        .enumeration declaration found variantFound valuesTyped,
        (by simpa [BorrowsValid, ValuesBorrowsValid, valueBorrows] using borrows)⟩
  | trapped reason next =>
      rw [payloadResult] at payloadPreserved
      simpa only [evalExpr, payloadResult, ValueOutcomeHasType,
        ValuesOutcomeHaveTypes] using payloadPreserved
  | exited code next =>
      rw [payloadResult] at payloadPreserved
      simpa only [evalExpr, payloadResult, ValueOutcomeHasType,
        ValuesOutcomeHaveTypes] using payloadPreserved
  | outOfFuel =>
      simp [evalExpr, payloadResult, ValueOutcomeHasType]

theorem evalArray_has_runtime_type
    (fuel : Nat)
    (elementsPreserved : RuntimeValuesOutcomeHaveTypes program context state
      store (evalExprs fuel program state expressions)
      (List.replicate expressions.length elementType)) :
    RuntimeValueOutcomeHasExtendedType program context state store
      (evalExpr (fuel + 1) program state (.array elementType expressions))
      (.array elementType expressions.length) := by
  cases elementsResult : evalExprs fuel program state expressions with
  | done values next =>
      rw [elementsResult] at elementsPreserved
      obtain ⟨afterStore, storePreserved, cellsPreserved, nextTyped,
        valuesTyped, borrows⟩ := elementsPreserved
      simp only [evalExpr, elementsResult]
      have valueLength : values.length = expressions.length := by
        simpa using
          Lanius.Properties.ValuesHaveTypes.length_eq valuesTyped
      exact ⟨afterStore, storePreserved, cellsPreserved, nextTyped,
        .array values elementType valueLength valuesTyped,
        (by simpa [BorrowsValid, ValuesBorrowsValid, valueBorrows] using borrows)⟩
  | trapped reason next | exited reason next =>
      rw [elementsResult] at elementsPreserved
      simpa only [evalExpr, elementsResult,
        RuntimeValueOutcomeHasExtendedType,
        RuntimeValuesOutcomeHaveTypes] using elementsPreserved
  | outOfFuel =>
      simp [evalExpr, elementsResult, RuntimeValueOutcomeHasExtendedType]

theorem evalStructValue_has_runtime_type
    (fuel : Nat)
    (found : program.structure? typeId = some declaration)
    (fieldsPreserved : RuntimeValuesOutcomeHaveTypes program context state
      store (evalExprs fuel program state expressions) declaration.fields) :
    RuntimeValueOutcomeHasExtendedType program context state store
      (evalExpr (fuel + 1) program state (.structValue typeId expressions))
      (.structure typeId) := by
  cases fieldsResult : evalExprs fuel program state expressions with
  | done values next =>
      rw [fieldsResult] at fieldsPreserved
      obtain ⟨afterStore, storePreserved, cellsPreserved, nextTyped,
        valuesTyped, borrows⟩ := fieldsPreserved
      simp only [evalExpr, fieldsResult]
      have sameId : declaration.id = typeId := by
        simpa [Program.structure?] using List.find?_some found
      subst typeId
      exact ⟨afterStore, storePreserved, cellsPreserved, nextTyped,
        .structure declaration found valuesTyped,
        (by simpa [BorrowsValid, ValuesBorrowsValid, valueBorrows] using borrows)⟩
  | trapped reason next | exited reason next =>
      rw [fieldsResult] at fieldsPreserved
      simpa only [evalExpr, fieldsResult,
        RuntimeValueOutcomeHasExtendedType,
        RuntimeValuesOutcomeHaveTypes] using fieldsPreserved
  | outOfFuel =>
      simp [evalExpr, fieldsResult, RuntimeValueOutcomeHasExtendedType]

theorem evalEnumValue_has_runtime_type
    (fuel : Nat)
    (found : program.enumeration? typeId = some declaration)
    (variantFound : declaration.variants[variant]? = some payloadTypes)
    (payloadPreserved : RuntimeValuesOutcomeHaveTypes program context state
      store (evalExprs fuel program state expressions) payloadTypes) :
    RuntimeValueOutcomeHasExtendedType program context state store
      (evalExpr (fuel + 1) program state
        (.enumValue typeId variant expressions))
      (.enumeration typeId) := by
  cases payloadResult : evalExprs fuel program state expressions with
  | done values next =>
      rw [payloadResult] at payloadPreserved
      obtain ⟨afterStore, storePreserved, cellsPreserved, nextTyped,
        valuesTyped, borrows⟩ := payloadPreserved
      simp only [evalExpr, payloadResult]
      have sameId : declaration.id = typeId := by
        simpa [Program.enumeration?] using List.find?_some found
      subst typeId
      exact ⟨afterStore, storePreserved, cellsPreserved, nextTyped,
        .enumeration declaration found variantFound valuesTyped,
        (by simpa [BorrowsValid, ValuesBorrowsValid, valueBorrows] using borrows)⟩
  | trapped reason next | exited reason next =>
      rw [payloadResult] at payloadPreserved
      simpa only [evalExpr, payloadResult,
        RuntimeValueOutcomeHasExtendedType,
        RuntimeValuesOutcomeHaveTypes] using payloadPreserved
  | outOfFuel =>
      simp [evalExpr, payloadResult, RuntimeValueOutcomeHasExtendedType]

theorem evalField_has_type
    (fuel : Nat)
    (found : program.structure? typeId = some declaration)
    (fieldFound : declaration.fields[field]? = some fieldType)
    (basePreserved : ValueOutcomeHasType program context state store
      (evalExpr fuel program state base) (.structure typeId)) :
    ValueOutcomeHasType program context state store
      (evalExpr (fuel + 1) program state (.field base field)) fieldType := by
  cases baseResult : evalExpr fuel program state base with
  | done value next =>
      rw [baseResult] at basePreserved
      obtain ⟨afterStore, storePreserved, cellsPreserved, nextTyped,
        valueTyped, valueBorrowsValid⟩ := basePreserved
      cases valueTyped with
      | «structure» valueDeclaration valueFound fieldsTyped =>
          have sameDeclaration : valueDeclaration = declaration := by
            exact Option.some.inj (valueFound.symm.trans found)
          subst valueDeclaration
          obtain ⟨fieldValue, fieldValueFound, fieldTyped⟩ :=
            Lanius.Properties.ValuesHaveTypes.getElem?_typed _ fieldsTyped
              fieldFound
          simp only [evalExpr, baseResult, fieldValueFound]
          refine ⟨afterStore, storePreserved, cellsPreserved, nextTyped,
            fieldTyped, ?_⟩
          intro descriptor member
          exact valueBorrowsValid descriptor (by
            simpa [valueBorrows] using
              valueBorrows_mem_valueListBorrows
                (List.mem_of_getElem? fieldValueFound) member)
  | trapped reason next =>
      rw [baseResult] at basePreserved
      simpa only [evalExpr, baseResult, ValueOutcomeHasType] using basePreserved
  | exited code next =>
      rw [baseResult] at basePreserved
      simpa only [evalExpr, baseResult, ValueOutcomeHasType] using basePreserved
  | outOfFuel =>
      simp [evalExpr, baseResult, ValueOutcomeHasType]

theorem evalField_has_runtime_type
    (fuel : Nat)
    (found : program.structure? typeId = some declaration)
    (fieldFound : declaration.fields[field]? = some fieldType)
    (basePreserved : RuntimeValueOutcomeHasExtendedType program context state
      store (evalExpr fuel program state base) (.structure typeId)) :
    RuntimeValueOutcomeHasExtendedType program context state store
      (evalExpr (fuel + 1) program state (.field base field)) fieldType := by
  cases baseResult : evalExpr fuel program state base with
  | done value next =>
      rw [baseResult] at basePreserved
      obtain ⟨afterStore, storePreserved, cellsPreserved, nextTyped,
        valueTyped, valueBorrowsValid⟩ := basePreserved
      cases valueTyped with
      | «structure» valueDeclaration valueFound fieldsTyped =>
          have sameDeclaration : valueDeclaration = declaration :=
            Option.some.inj (valueFound.symm.trans found)
          subst valueDeclaration
          obtain ⟨fieldValue, fieldValueFound, fieldTyped⟩ :=
            Lanius.Properties.ValuesHaveTypes.getElem?_typed _ fieldsTyped
              fieldFound
          simp only [evalExpr, baseResult, fieldValueFound]
          refine ⟨afterStore, storePreserved, cellsPreserved, nextTyped,
            fieldTyped, ?_⟩
          intro descriptor member
          exact valueBorrowsValid descriptor (by
            simpa [valueBorrows] using
              valueBorrows_mem_valueListBorrows
                (List.mem_of_getElem? fieldValueFound) member)
  | trapped reason next | exited reason next =>
      rw [baseResult] at basePreserved
      simpa only [evalExpr, baseResult,
        RuntimeValueOutcomeHasExtendedType] using basePreserved
  | outOfFuel =>
      simp [evalExpr, baseResult, RuntimeValueOutcomeHasExtendedType]

theorem evalArrayIndex_has_type
    (fuel : Nat)
    (basePreserved : ValueOutcomeHasType program context state store
      (evalExpr fuel program state base) (.array elementType length))
    (indexPreserved :
      ∀ (intermediate : State) (intermediateStore : StoreTyping),
        StateHasType program context intermediate intermediateStore →
        ValueOutcomeHasType program context intermediate intermediateStore
          (evalExpr fuel program intermediate index) indexType) :
    ValueOutcomeHasType program context state store
      (evalExpr (fuel + 1) program state (.index base index)) elementType := by
  cases baseResult : evalExpr fuel program state base with
  | done baseValue afterBase =>
      rw [baseResult] at basePreserved
      obtain ⟨baseStore, baseStorePreserved, baseCellsPreserved,
        afterBaseTyped, baseTyped, baseBorrows⟩ := basePreserved
      cases baseTyped with
      | array elements selectedElementType valueLength elementsTyped =>
          have indexOutcome := indexPreserved afterBase baseStore afterBaseTyped
          cases indexResult : evalExpr fuel program afterBase index with
          | done indexValue afterIndex =>
              rw [indexResult] at indexOutcome
              obtain ⟨indexStore, indexStorePreserved, indexCellsPreserved,
                afterIndexTyped, indexTyped, indexBorrows⟩ := indexOutcome
              have baseBorrowsAfterIndex := baseBorrows.preserve
                indexStorePreserved indexCellsPreserved afterIndexTyped
              simp only [evalExpr, baseResult, indexResult]
              cases converted : integerIndex indexValue with
              | error reason =>
                  simp only
                  exact ⟨indexStore, baseStorePreserved.trans indexStorePreserved,
                    baseCellsPreserved.trans indexCellsPreserved,
                    afterIndexTyped⟩
              | ok selectedIndex =>
                  simp only
                  cases selected : elements[selectedIndex]? with
                  | none =>
                      simp only
                      exact ⟨indexStore,
                        baseStorePreserved.trans indexStorePreserved,
                        baseCellsPreserved.trans indexCellsPreserved,
                        afterIndexTyped⟩
                  | some selectedValue =>
                      simp only
                      obtain ⟨selectedType, typeFound, selectedTyped⟩ :=
                        Lanius.Properties.ValuesHaveTypes.getElem?_aligned _
                          elementsTyped selected
                      have selectedTypeEq :=
                        replicate_getElem?_some _ _ _ _ typeFound
                      subst selectedType
                      refine ⟨indexStore,
                        baseStorePreserved.trans indexStorePreserved,
                        baseCellsPreserved.trans indexCellsPreserved,
                        afterIndexTyped, selectedTyped, ?_⟩
                      intro descriptor member
                      exact baseBorrowsAfterIndex descriptor (by
                        simpa [valueBorrows] using
                          valueBorrows_mem_valueListBorrows
                            (List.mem_of_getElem? selected) member)
          | trapped reason next =>
              rw [indexResult] at indexOutcome
              simpa only [evalExpr, baseResult, indexResult,
                ValueOutcomeHasType] using
                  indexOutcome.prepend baseStorePreserved baseCellsPreserved
          | exited code next =>
              rw [indexResult] at indexOutcome
              simpa only [evalExpr, baseResult, indexResult,
                ValueOutcomeHasType] using
                  indexOutcome.prepend baseStorePreserved baseCellsPreserved
          | outOfFuel =>
              simp [evalExpr, baseResult, indexResult, ValueOutcomeHasType]
  | trapped reason next =>
      rw [baseResult] at basePreserved
      simpa only [evalExpr, baseResult, ValueOutcomeHasType] using basePreserved
  | exited code next =>
      rw [baseResult] at basePreserved
      simpa only [evalExpr, baseResult, ValueOutcomeHasType] using basePreserved
  | outOfFuel =>
      simp [evalExpr, baseResult, ValueOutcomeHasType]

theorem evalArrayIndex_has_runtime_type
    (fuel : Nat)
    (basePreserved : RuntimeValueOutcomeHasExtendedType program context state
      store (evalExpr fuel program state base) (.array elementType length))
    (indexPreserved :
      ∀ (intermediate : State) (intermediateStore : StoreTyping),
        RuntimeStateHasType program context intermediate intermediateStore →
        RuntimeValueOutcomeHasExtendedType program context intermediate
          intermediateStore (evalExpr fuel program intermediate index)
          indexType) :
    RuntimeValueOutcomeHasExtendedType program context state store
      (evalExpr (fuel + 1) program state (.index base index)) elementType := by
  cases baseResult : evalExpr fuel program state base with
  | done baseValue afterBase =>
      rw [baseResult] at basePreserved
      obtain ⟨baseStore, baseStorePreserved, baseCellsPreserved,
        afterBaseTyped, baseTyped, baseBorrows⟩ := basePreserved
      cases baseTyped with
      | array elements selectedElementType valueLength elementsTyped =>
          have indexOutcome :=
            indexPreserved afterBase baseStore afterBaseTyped
          cases indexResult : evalExpr fuel program afterBase index with
          | done indexValue afterIndex =>
              rw [indexResult] at indexOutcome
              obtain ⟨indexStore, indexStorePreserved, indexCellsPreserved,
                afterIndexTyped, indexTyped, indexBorrows⟩ := indexOutcome
              have baseBorrowsAfterIndex := baseBorrows.preserve
                indexStorePreserved indexCellsPreserved afterIndexTyped.typed
              simp only [evalExpr, baseResult, indexResult]
              cases converted : integerIndex indexValue with
              | error reason =>
                  simp only
                  exact ⟨indexStore,
                    baseStorePreserved.trans indexStorePreserved,
                    baseCellsPreserved.trans indexCellsPreserved,
                    afterIndexTyped⟩
              | ok selectedIndex =>
                  simp only
                  cases selected : elements[selectedIndex]? with
                  | none =>
                      simp only
                      exact ⟨indexStore,
                        baseStorePreserved.trans indexStorePreserved,
                        baseCellsPreserved.trans indexCellsPreserved,
                        afterIndexTyped⟩
                  | some selectedValue =>
                      simp only
                      obtain ⟨selectedType, typeFound, selectedTyped⟩ :=
                        Lanius.Properties.ValuesHaveTypes.getElem?_aligned _
                          elementsTyped selected
                      have selectedTypeEq :=
                        replicate_getElem?_some _ _ _ _ typeFound
                      subst selectedType
                      refine ⟨indexStore,
                        baseStorePreserved.trans indexStorePreserved,
                        baseCellsPreserved.trans indexCellsPreserved,
                        afterIndexTyped, selectedTyped, ?_⟩
                      intro descriptor member
                      exact baseBorrowsAfterIndex descriptor (by
                        simpa [valueBorrows] using
                          valueBorrows_mem_valueListBorrows
                            (List.mem_of_getElem? selected) member)
          | trapped reason next | exited reason next =>
              rw [indexResult] at indexOutcome
              simpa only [evalExpr, baseResult, indexResult,
                RuntimeValueOutcomeHasExtendedType] using
                  indexOutcome.prepend baseStorePreserved baseCellsPreserved
          | outOfFuel =>
              simp [evalExpr, baseResult, indexResult,
                RuntimeValueOutcomeHasExtendedType]
  | trapped reason next | exited reason next =>
      rw [baseResult] at basePreserved
      simpa only [evalExpr, baseResult,
        RuntimeValueOutcomeHasExtendedType] using basePreserved
  | outOfFuel =>
      simp [evalExpr, baseResult, RuntimeValueOutcomeHasExtendedType]

theorem evalSliceIndex_has_type
    (fuel : Nat)
    (basePreserved : ValueOutcomeHasType program context state store
      (evalExpr fuel program state base) (.slice elementType))
    (indexPreserved :
      ∀ (intermediate : State) (intermediateStore : StoreTyping),
        StateHasType program context intermediate intermediateStore →
        ValueOutcomeHasType program context intermediate intermediateStore
          (evalExpr fuel program intermediate index) indexType) :
    ValueOutcomeHasType program context state store
      (evalExpr (fuel + 1) program state (.index base index)) elementType := by
  cases baseResult : evalExpr fuel program state base with
  | done baseValue afterBase =>
      rw [baseResult] at basePreserved
      obtain ⟨baseStore, baseStorePreserved, baseCellsPreserved,
        afterBaseTyped, baseTyped, baseBorrows⟩ := basePreserved
      cases baseTyped with
      | slice selectedElementType cell projections start sliceLength =>
          have sliceValid := baseBorrows
            (.slice elementType cell projections start sliceLength) (by
              simp [valueBorrows])
          have indexOutcome := indexPreserved afterBase baseStore afterBaseTyped
          cases indexResult : evalExpr fuel program afterBase index with
          | done indexValue afterIndex =>
              rw [indexResult] at indexOutcome
              obtain ⟨indexStore, indexStorePreserved, indexCellsPreserved,
                afterIndexTyped, indexTyped, indexBorrows⟩ := indexOutcome
              have sliceValidAfterIndex := sliceValid.preserve
                indexStorePreserved indexCellsPreserved afterIndexTyped
              simp only [evalExpr, baseResult, indexResult]
              cases converted : integerIndex indexValue with
              | error reason =>
                  simp only
                  exact ⟨indexStore, baseStorePreserved.trans indexStorePreserved,
                    baseCellsPreserved.trans indexCellsPreserved,
                    afterIndexTyped⟩
              | ok selectedIndex =>
                  simp only
                  by_cases inBounds : selectedIndex < sliceLength
                  · rw [if_pos inBounds]
                    cases sliced : sliceValues afterIndex cell projections start
                        sliceLength with
                    | error reason =>
                        simp only
                        exact ⟨indexStore,
                          baseStorePreserved.trans indexStorePreserved,
                          baseCellsPreserved.trans indexCellsPreserved,
                          afterIndexTyped⟩
                    | ok values =>
                        simp only
                        cases selected : values[selectedIndex]? with
                        | none =>
                            simp only
                            exact ⟨indexStore,
                              baseStorePreserved.trans indexStorePreserved,
                              baseCellsPreserved.trans indexCellsPreserved,
                              afterIndexTyped⟩
                        | some result =>
                            simp only
                            exact ⟨indexStore,
                              baseStorePreserved.trans indexStorePreserved,
                              baseCellsPreserved.trans indexCellsPreserved,
                              afterIndexTyped,
                              sliceValues_getElem?_typed selectedIndex
                                sliceValidAfterIndex sliced selected,
                              sliceValues_getElem?_borrows selectedIndex
                                afterIndexTyped sliceValidAfterIndex sliced selected⟩
                  · rw [if_neg inBounds]
                    exact ⟨indexStore,
                      baseStorePreserved.trans indexStorePreserved,
                      baseCellsPreserved.trans indexCellsPreserved,
                      afterIndexTyped⟩
          | trapped reason next =>
              rw [indexResult] at indexOutcome
              simpa only [evalExpr, baseResult, indexResult,
                ValueOutcomeHasType] using
                  indexOutcome.prepend baseStorePreserved baseCellsPreserved
          | exited code next =>
              rw [indexResult] at indexOutcome
              simpa only [evalExpr, baseResult, indexResult,
                ValueOutcomeHasType] using
                  indexOutcome.prepend baseStorePreserved baseCellsPreserved
          | outOfFuel =>
              simp [evalExpr, baseResult, indexResult, ValueOutcomeHasType]
  | trapped reason next =>
      rw [baseResult] at basePreserved
      simpa only [evalExpr, baseResult, ValueOutcomeHasType] using basePreserved
  | exited code next =>
      rw [baseResult] at basePreserved
      simpa only [evalExpr, baseResult, ValueOutcomeHasType] using basePreserved
  | outOfFuel =>
      simp [evalExpr, baseResult, ValueOutcomeHasType]

theorem evalSliceIndex_has_runtime_type
    (fuel : Nat)
    (basePreserved : RuntimeValueOutcomeHasExtendedType program context state
      store (evalExpr fuel program state base) (.slice elementType))
    (indexPreserved :
      ∀ (intermediate : State) (intermediateStore : StoreTyping),
        RuntimeStateHasType program context intermediate intermediateStore →
        RuntimeValueOutcomeHasExtendedType program context intermediate
          intermediateStore (evalExpr fuel program intermediate index)
          indexType) :
    RuntimeValueOutcomeHasExtendedType program context state store
      (evalExpr (fuel + 1) program state (.index base index)) elementType := by
  cases baseResult : evalExpr fuel program state base with
  | done baseValue afterBase =>
      rw [baseResult] at basePreserved
      obtain ⟨baseStore, baseStorePreserved, baseCellsPreserved,
        afterBaseTyped, baseTyped, baseBorrows⟩ := basePreserved
      cases baseTyped with
      | slice selectedElementType cell projections start sliceLength =>
          have sliceValid := baseBorrows
            (.slice elementType cell projections start sliceLength)
            (by simp [valueBorrows])
          have indexOutcome :=
            indexPreserved afterBase baseStore afterBaseTyped
          cases indexResult : evalExpr fuel program afterBase index with
          | done indexValue afterIndex =>
              rw [indexResult] at indexOutcome
              obtain ⟨indexStore, indexStorePreserved, indexCellsPreserved,
                afterIndexTyped, indexTyped, indexBorrows⟩ := indexOutcome
              have sliceValidAfterIndex := sliceValid.preserve
                indexStorePreserved indexCellsPreserved afterIndexTyped.typed
              simp only [evalExpr, baseResult, indexResult]
              cases converted : integerIndex indexValue with
              | error reason =>
                  simp only
                  exact ⟨indexStore,
                    baseStorePreserved.trans indexStorePreserved,
                    baseCellsPreserved.trans indexCellsPreserved,
                    afterIndexTyped⟩
              | ok selectedIndex =>
                  simp only
                  by_cases inBounds : selectedIndex < sliceLength
                  · rw [if_pos inBounds]
                    cases sliced : sliceValues afterIndex cell projections start
                        sliceLength with
                    | error reason =>
                        simp only
                        exact ⟨indexStore,
                          baseStorePreserved.trans indexStorePreserved,
                          baseCellsPreserved.trans indexCellsPreserved,
                          afterIndexTyped⟩
                    | ok values =>
                        simp only
                        cases selected : values[selectedIndex]? with
                        | none =>
                            simp only
                            exact ⟨indexStore,
                              baseStorePreserved.trans indexStorePreserved,
                              baseCellsPreserved.trans indexCellsPreserved,
                              afterIndexTyped⟩
                        | some result =>
                            simp only
                            exact ⟨indexStore,
                              baseStorePreserved.trans indexStorePreserved,
                              baseCellsPreserved.trans indexCellsPreserved,
                              afterIndexTyped,
                              sliceValues_getElem?_typed selectedIndex
                                sliceValidAfterIndex sliced selected,
                              sliceValues_getElem?_borrows selectedIndex
                                afterIndexTyped.typed sliceValidAfterIndex sliced
                                selected⟩
                  · rw [if_neg inBounds]
                    exact ⟨indexStore,
                      baseStorePreserved.trans indexStorePreserved,
                      baseCellsPreserved.trans indexCellsPreserved,
                      afterIndexTyped⟩
          | trapped reason next | exited reason next =>
              rw [indexResult] at indexOutcome
              simpa only [evalExpr, baseResult, indexResult,
                RuntimeValueOutcomeHasExtendedType] using
                  indexOutcome.prepend baseStorePreserved baseCellsPreserved
          | outOfFuel =>
              simp [evalExpr, baseResult, indexResult,
                RuntimeValueOutcomeHasExtendedType]
  | trapped reason next | exited reason next =>
      rw [baseResult] at basePreserved
      simpa only [evalExpr, baseResult,
        RuntimeValueOutcomeHasExtendedType] using basePreserved
  | outOfFuel =>
      simp [evalExpr, baseResult, RuntimeValueOutcomeHasExtendedType]

theorem evalDereference_has_type
    (fuel : Nat)
    (referencePreserved : ValueOutcomeHasType program context state store
      (evalExpr fuel program state reference) (.reference referent)) :
    ValueOutcomeHasType program context state store
      (evalExpr (fuel + 1) program state (.dereference reference)) referent := by
  cases referenceResult : evalExpr fuel program state reference with
  | done referenceValue next =>
      rw [referenceResult] at referencePreserved
      obtain ⟨afterStore, storePreserved, cellsPreserved, nextTyped,
        referenceTyped, referenceBorrows⟩ := referencePreserved
      cases referenceTyped with
      | reference selectedReferent cell projections =>
          have valid := referenceBorrows
            (.reference referent cell projections) (by simp [valueBorrows])
          simp only [evalExpr, referenceResult, dereferenceValue]
          cases read : readCellProjection next cell projections with
          | error reason =>
              simp only
              exact ⟨afterStore, storePreserved, cellsPreserved, nextTyped⟩
          | ok result =>
              simp only
              exact ⟨afterStore, storePreserved, cellsPreserved, nextTyped,
                readCellProjection_reference_typed valid read,
                readCellProjection_reference_borrows nextTyped valid read⟩
  | trapped reason next =>
      rw [referenceResult] at referencePreserved
      simpa only [evalExpr, referenceResult, ValueOutcomeHasType] using
        referencePreserved
  | exited code next =>
      rw [referenceResult] at referencePreserved
      simpa only [evalExpr, referenceResult, ValueOutcomeHasType] using
        referencePreserved
  | outOfFuel =>
      simp [evalExpr, referenceResult, ValueOutcomeHasType]

theorem evalBorrow_has_type
    (fuel : Nat)
    (placePreserved : PlaceOutcomeHasType program context state store
      (evalPlace fuel program state place) referent) :
    ValueOutcomeHasType program context state store
      (evalExpr (fuel + 1) program state (.borrow referent place))
      (.reference referent) := by
  cases placeResult : evalPlace fuel program state place with
  | done resolved next =>
      rw [placeResult] at placePreserved
      obtain ⟨afterStore, storePreserved, cellsPreserved, nextTyped,
        resolvedTyped⟩ := placePreserved
      cases resolvedTyped with
      | rootNoCachedValue stored found =>
          simp only [evalExpr, placeResult]
          exact ⟨afterStore, storePreserved, cellsPreserved, nextTyped⟩
      | rootInitialized stored found initialized rootTyped rootBorrows valueTyped
          valueBorrows =>
          simp only [evalExpr, placeResult]
          obtain ⟨referenceTyped, referenceBorrows⟩ :=
            existingReference_result_valid stored found initialized rootTyped
              ProjectionHasType.nil
          exact ⟨afterStore, storePreserved, cellsPreserved, nextTyped,
            referenceTyped, referenceBorrows⟩
      | projected stored found initialized rootTyped rootBorrows projectionTyped
          valueTyped valueBorrows =>
          simp only [evalExpr, placeResult]
          obtain ⟨referenceTyped, referenceBorrows⟩ :=
            existingReference_result_valid stored found initialized rootTyped
              projectionTyped
          exact ⟨afterStore, storePreserved, cellsPreserved, nextTyped,
            referenceTyped, referenceBorrows⟩
  | trapped reason next =>
      rw [placeResult] at placePreserved
      simpa only [evalExpr, placeResult, PlaceOutcomeHasType,
        ValueOutcomeHasType] using placePreserved
  | exited code next =>
      rw [placeResult] at placePreserved
      simpa only [evalExpr, placeResult, PlaceOutcomeHasType,
        ValueOutcomeHasType] using placePreserved
  | outOfFuel =>
      simp [evalExpr, placeResult, ValueOutcomeHasType]

theorem evalDereference_has_runtime_type
    (fuel : Nat)
    (referencePreserved : RuntimeValueOutcomeHasExtendedType program context
      state store (evalExpr fuel program state reference)
      (.reference referent)) :
    RuntimeValueOutcomeHasExtendedType program context state store
      (evalExpr (fuel + 1) program state (.dereference reference)) referent := by
  cases referenceResult : evalExpr fuel program state reference with
  | done referenceValue next =>
      rw [referenceResult] at referencePreserved
      obtain ⟨afterStore, storePreserved, cellsPreserved, nextTyped,
        referenceTyped, referenceBorrows⟩ := referencePreserved
      cases referenceTyped with
      | reference selectedReferent cell projections =>
          have valid := referenceBorrows
            (.reference referent cell projections) (by simp [valueBorrows])
          simp only [evalExpr, referenceResult, dereferenceValue]
          cases read : readCellProjection next cell projections with
          | error reason =>
              simp only
              exact ⟨afterStore, storePreserved, cellsPreserved, nextTyped⟩
          | ok result =>
              simp only
              exact ⟨afterStore, storePreserved, cellsPreserved, nextTyped,
                readCellProjection_reference_typed valid read,
                readCellProjection_reference_borrows nextTyped.typed valid read⟩
  | trapped reason next | exited reason next =>
      rw [referenceResult] at referencePreserved
      simpa only [evalExpr, referenceResult,
        RuntimeValueOutcomeHasExtendedType] using referencePreserved
  | outOfFuel =>
      simp [evalExpr, referenceResult, RuntimeValueOutcomeHasExtendedType]

theorem evalBorrow_has_runtime_type
    (fuel : Nat)
    (placePreserved : RuntimePlaceOutcomeHasType program context state store
      (evalPlace fuel program state place) referent) :
    RuntimeValueOutcomeHasExtendedType program context state store
      (evalExpr (fuel + 1) program state (.borrow referent place))
      (.reference referent) := by
  cases placeResult : evalPlace fuel program state place with
  | done resolved next =>
      rw [placeResult] at placePreserved
      obtain ⟨afterStore, storePreserved, cellsPreserved, nextTyped,
        resolvedTyped⟩ := placePreserved
      cases resolvedTyped with
      | rootNoCachedValue stored found =>
          simp only [evalExpr, placeResult]
          exact ⟨afterStore, storePreserved, cellsPreserved, nextTyped⟩
      | rootInitialized stored found initialized rootTyped rootBorrows
          valueTyped valueBorrows =>
          simp only [evalExpr, placeResult]
          obtain ⟨referenceTyped, referenceBorrows⟩ :=
            existingReference_result_valid stored found initialized rootTyped
              ProjectionHasType.nil
          exact ⟨afterStore, storePreserved, cellsPreserved, nextTyped,
            referenceTyped, referenceBorrows⟩
      | projected stored found initialized rootTyped rootBorrows projectionTyped
          valueTyped valueBorrows =>
          simp only [evalExpr, placeResult]
          obtain ⟨referenceTyped, referenceBorrows⟩ :=
            existingReference_result_valid stored found initialized rootTyped
              projectionTyped
          exact ⟨afterStore, storePreserved, cellsPreserved, nextTyped,
            referenceTyped, referenceBorrows⟩
  | trapped reason next | exited reason next =>
      rw [placeResult] at placePreserved
      simpa only [evalExpr, placeResult, RuntimePlaceOutcomeHasType,
        RuntimeValueOutcomeHasExtendedType] using placePreserved
  | outOfFuel =>
      simp [evalExpr, placeResult, RuntimeValueOutcomeHasExtendedType]

theorem expressionPlace?_has_type
    (typed : ExprHasType program context expression type)
    (found : expressionPlace? expression = some place) :
    PlaceHasType program context place type := by
  cases typed with
  | «local» localFound =>
      simp only [expressionPlace?, Option.some.injEq] at found
      subst place
      exact .local localFound
  | field base declaration declarationFound fieldFound =>
      simp only [expressionPlace?] at found
      generalize baseFound : expressionPlace? _ = baseResult at found
      cases baseResult with
      | none => simp at found
      | some basePlace =>
          cases found
          exact .field (expressionPlace?_has_type base baseFound) declaration
            declarationFound fieldFound
  | indexArray base index integerIndex =>
      simp only [expressionPlace?] at found
      generalize baseFound : expressionPlace? _ = baseResult at found
      cases baseResult with
      | none => simp at found
      | some basePlace =>
          cases found
          exact .indexArray (expressionPlace?_has_type base baseFound) index
            integerIndex
  | indexSlice base index integerIndex =>
      simp only [expressionPlace?] at found
      generalize baseFound : expressionPlace? _ = baseResult at found
      cases baseResult with
      | none => simp at found
      | some basePlace =>
          cases found
          exact .indexSlice (expressionPlace?_has_type base baseFound) index
            integerIndex
  | value valueTyped => simp [expressionPlace?] at found
  | cast operand conversion => simp [expressionPlace?] at found
  | unary operand operation => simp [expressionPlace?] at found
  | binary left right operation =>
      simp [expressionPlace?] at found
  | array elements => simp [expressionPlace?] at found
  | arrayToSlice array => simp [expressionPlace?] at found
  | structValue declaration declarationFound fields =>
      simp [expressionPlace?] at found
  | enumValue declaration declarationFound variantFound payload =>
      simp [expressionPlace?] at found
  | matchValue scrutinee typedArms =>
      simp [expressionPlace?] at found
  | assign target value operation =>
      simp [expressionPlace?] at found
  | borrow target => simp [expressionPlace?] at found
  | dereference reference => simp [expressionPlace?] at found
  | constant declaration declarationFound => simp [expressionPlace?] at found
  | call function declarationFound arguments =>
      simp [expressionPlace?] at found
  | printI32 argument => simp [expressionPlace?] at found
  | assert argument => simp [expressionPlace?] at found
  | i32ArrayDataPtr array => simp [expressionPlace?] at found
  | alloc size alignment =>
      simp [expressionPlace?] at found
  | realloc pointer oldSize newSize alignment =>
      simp [expressionPlace?] at found
  | dealloc pointer size alignment =>
      simp [expressionPlace?] at found
  | loadByte pointer offset =>
      simp [expressionPlace?] at found
  | storeByte pointer offset value =>
      simp [expressionPlace?] at found
termination_by expression

theorem evalArrayToSlice_has_type
    (fuel : Nat)
    (placePreserved :
      ∀ (place : Place), expressionPlace? array = some place →
        PlaceOutcomeHasType program context state store
          (evalPlace fuel program state place) (.array elementType length))
    (arrayPreserved : expressionPlace? array = none →
      ValueOutcomeHasType program context state store
        (evalExpr fuel program state array) (.array elementType length)) :
    ValueOutcomeHasType program context state store
      (evalExpr (fuel + 1) program state
        (.arrayToSlice elementType array)) (.slice elementType) := by
  cases placeCase : expressionPlace? array with
  | some place =>
      have placeOutcome := placePreserved place placeCase
      cases placeResult : evalPlace fuel program state place with
      | done resolved next =>
          rw [placeResult] at placeOutcome
          obtain ⟨afterStore, storePreserved, cellsPreserved, nextTyped,
            resolvedTyped⟩ := placeOutcome
          cases resolved with
          | mk root projections cachedValue =>
              cases cachedValue with
              | none =>
                  simp only [evalExpr, placeCase, placeResult]
                  exact ⟨afterStore, storePreserved, cellsPreserved,
                    nextTyped⟩
              | some value =>
                  have valueTyped := resolvedTyped.value_typed rfl
                  cases valueTyped with
                  | array elements valueElementType valueLength elementsTyped =>
                      simp only [evalExpr, placeCase, placeResult]
                      obtain ⟨sliceTyped, sliceBorrows⟩ :=
                        resolvedTyped.array_slice rfl
                      exact ⟨afterStore, storePreserved, cellsPreserved,
                        nextTyped, sliceTyped, sliceBorrows⟩
      | trapped reason next =>
          rw [placeResult] at placeOutcome
          simpa only [evalExpr, placeCase, placeResult,
            PlaceOutcomeHasType, ValueOutcomeHasType] using placeOutcome
      | exited code next =>
          rw [placeResult] at placeOutcome
          simpa only [evalExpr, placeCase, placeResult,
            PlaceOutcomeHasType, ValueOutcomeHasType] using placeOutcome
      | outOfFuel =>
          simp [evalExpr, placeCase, placeResult, ValueOutcomeHasType]
  | none =>
      have arrayOutcome := arrayPreserved placeCase
      cases arrayResult : evalExpr fuel program state array with
      | done value next =>
          rw [arrayResult] at arrayOutcome
          obtain ⟨afterStore, storePreserved, cellsPreserved, nextTyped,
            valueTyped, valueBorrows⟩ := arrayOutcome
          cases valueTyped with
          | array elements valueElementType valueLength elementsTyped =>
              simp only [evalExpr, placeCase, arrayResult]
              have arrayTyped : ValueHasType program (.array elements)
                  (.array elementType length) :=
                .array elements elementType valueLength elementsTyped
              let nextStore := afterStore.extend next.nextCell
                (.array elementType length)
              refine ⟨nextStore, ?_, ?_, ?_, .slice _ _ _ _ _, ?_⟩
              · exact storePreserved.trans
                  (StoreTyping.extends_extend afterStore next.nextCell
                    (.array elementType length) nextTyped.nextCell_store_none)
              · exact cellsPreserved.trans
                  (allocateTemporary_preserves_initialized_cells
                    nextTyped.wellFormed (.array elements))
              · exact nextTyped.allocateTemporary arrayTyped valueBorrows
              · rw [valueLength]
                exact temporaryArraySlice_borrows_valid nextTyped arrayTyped
      | trapped reason next =>
          rw [arrayResult] at arrayOutcome
          simpa only [evalExpr, placeCase, arrayResult,
            ValueOutcomeHasType] using arrayOutcome
      | exited code next =>
          rw [arrayResult] at arrayOutcome
          simpa only [evalExpr, placeCase, arrayResult,
            ValueOutcomeHasType] using arrayOutcome
      | outOfFuel =>
          simp [evalExpr, placeCase, arrayResult, ValueOutcomeHasType]

theorem evalArrayToSlice_has_runtime_type
    (fuel : Nat)
    (placePreserved :
      ∀ (place : Place), expressionPlace? array = some place →
        RuntimePlaceOutcomeHasType program context state store
          (evalPlace fuel program state place) (.array elementType length))
    (arrayPreserved : expressionPlace? array = none →
      RuntimeValueOutcomeHasExtendedType program context state store
        (evalExpr fuel program state array) (.array elementType length)) :
    RuntimeValueOutcomeHasExtendedType program context state store
      (evalExpr (fuel + 1) program state
        (.arrayToSlice elementType array)) (.slice elementType) := by
  cases placeCase : expressionPlace? array with
  | some place =>
      have placeOutcome := placePreserved place placeCase
      cases placeResult : evalPlace fuel program state place with
      | done resolved next =>
          rw [placeResult] at placeOutcome
          obtain ⟨afterStore, storePreserved, cellsPreserved, nextTyped,
            resolvedTyped⟩ := placeOutcome
          cases resolved with
          | mk root projections cachedValue =>
              cases cachedValue with
              | none =>
                  simp only [evalExpr, placeCase, placeResult]
                  exact ⟨afterStore, storePreserved, cellsPreserved,
                    nextTyped⟩
              | some value =>
                  have valueTyped := resolvedTyped.value_typed rfl
                  cases valueTyped with
                  | array elements valueElementType valueLength elementsTyped =>
                      simp only [evalExpr, placeCase, placeResult]
                      obtain ⟨sliceTyped, sliceBorrows⟩ :=
                        resolvedTyped.array_slice rfl
                      exact ⟨afterStore, storePreserved, cellsPreserved,
                        nextTyped, sliceTyped, sliceBorrows⟩
      | trapped reason next | exited reason next =>
          rw [placeResult] at placeOutcome
          simpa only [evalExpr, placeCase, placeResult,
            RuntimePlaceOutcomeHasType,
            RuntimeValueOutcomeHasExtendedType] using placeOutcome
      | outOfFuel =>
          simp [evalExpr, placeCase, placeResult,
            RuntimeValueOutcomeHasExtendedType]
  | none =>
      have arrayOutcome := arrayPreserved placeCase
      cases arrayResult : evalExpr fuel program state array with
      | done value next =>
          rw [arrayResult] at arrayOutcome
          obtain ⟨afterStore, storePreserved, cellsPreserved, nextTyped,
            valueTyped, valueBorrows⟩ := arrayOutcome
          cases valueTyped with
          | array elements valueElementType valueLength elementsTyped =>
              simp only [evalExpr, placeCase, arrayResult]
              have arrayTyped : ValueHasType program (.array elements)
                  (.array elementType length) :=
                .array elements elementType valueLength elementsTyped
              let nextStore := afterStore.extend next.nextCell
                (.array elementType length)
              refine ⟨nextStore, ?_, ?_, ?_, .slice _ _ _ _ _, ?_⟩
              · exact storePreserved.trans
                  (StoreTyping.extends_extend afterStore next.nextCell
                    (.array elementType length)
                    nextTyped.typed.nextCell_store_none)
              · exact cellsPreserved.trans
                  (allocateTemporary_preserves_initialized_cells
                    nextTyped.typed.wellFormed (.array elements))
              · exact nextTyped.allocateTemporary arrayTyped valueBorrows
              · rw [valueLength]
                exact temporaryArraySlice_borrows_valid nextTyped.typed
                  arrayTyped
      | trapped reason next | exited reason next =>
          rw [arrayResult] at arrayOutcome
          simpa only [evalExpr, placeCase, arrayResult,
            RuntimeValueOutcomeHasExtendedType] using arrayOutcome
      | outOfFuel =>
          simp [evalExpr, placeCase, arrayResult,
            RuntimeValueOutcomeHasExtendedType]

theorem evalI32ArrayDataPtr_has_runtime_type
    (fuel : Nat)
    (placePreserved :
      ∀ (place : Place), expressionPlace? array = some place →
        RuntimePlaceOutcomeHasType program context state store
          (evalPlace fuel program state place)
          (.array (.scalar (.signed .i32)) length))
    (arrayPreserved : expressionPlace? array = none →
      RuntimeValueOutcomeHasExtendedType program context state store
        (evalExpr fuel program state array)
        (.array (.scalar (.signed .i32)) length)) :
    RuntimeValueOutcomeHasExtendedType program context state store
      (evalExpr (fuel + 1) program state (.i32ArrayDataPtr array))
      (.scalar .rawPtr) := by
  cases placeCase : expressionPlace? array with
  | some place =>
      have placeOutcome := placePreserved place placeCase
      cases placeResult : evalPlace fuel program state place with
      | done resolved next =>
          rw [placeResult] at placeOutcome
          obtain ⟨afterStore, storePreserved, cellsPreserved, nextTyped,
            resolvedTyped⟩ := placeOutcome
          cases resolved with
          | mk root projections cachedValue =>
              cases cachedValue with
              | none =>
                  simp only [evalExpr, placeCase, placeResult]
                  exact ⟨afterStore, storePreserved, cellsPreserved, nextTyped⟩
              | some value =>
                  have valueTyped := resolvedTyped.value_typed rfl
                  cases valueTyped with
                  | array elements elementType valueLength elementsTyped =>
                      have placeTyped := resolvedTyped.i32ArrayPlace
                      rw [← valueLength] at placeTyped
                      have mapped := mapI32ArrayView_has_type nextTyped placeTyped
                      have mappedCells :=
                        mapI32ArrayView_preserves_initialized_cells next root
                          projections elements
                      simpa only [evalExpr, placeCase, placeResult] using
                        mapped.prepend storePreserved cellsPreserved mappedCells
      | trapped reason next | exited reason next =>
          rw [placeResult] at placeOutcome
          simpa only [evalExpr, placeCase, placeResult,
            RuntimePlaceOutcomeHasType,
            RuntimeValueOutcomeHasExtendedType] using placeOutcome
      | outOfFuel =>
          simp [evalExpr, placeCase, placeResult,
            RuntimeValueOutcomeHasExtendedType]
  | none =>
      have arrayOutcome := arrayPreserved placeCase
      cases arrayResult : evalExpr fuel program state array with
      | done value next =>
          rw [arrayResult] at arrayOutcome
          obtain ⟨afterStore, storePreserved, cellsPreserved, nextTyped,
            valueTyped, valueBorrows⟩ := arrayOutcome
          cases valueTyped with
          | array elements elementType valueLength elementsTyped =>
              have arrayTyped : ValueHasType program (.array elements)
                  (.array (.scalar (.signed .i32)) length) :=
                .array elements (.scalar (.signed .i32)) valueLength elementsTyped
              let nextStore := afterStore.extend next.nextCell
                (.array (.scalar (.signed .i32)) length)
              have temporaryTyped := nextTyped.allocateTemporary arrayTyped
                valueBorrows
              have temporaryPlaceTyped :=
                allocateTemporary_i32ArrayPlace_has_type nextTyped arrayTyped
              have temporaryPlaceAtElements : I32ArrayPlaceHasType program
                  (next.allocateTemporary (.array elements)).2 nextStore
                  (next.allocateTemporary (.array elements)).1 []
                  elements.length := by
                rw [valueLength]
                exact temporaryPlaceTyped
              have mapped := mapI32ArrayView_has_type temporaryTyped
                temporaryPlaceAtElements
              have mappedCells := mapI32ArrayView_preserves_initialized_cells
                (next.allocateTemporary (.array elements)).2
                (next.allocateTemporary (.array elements)).1 [] elements
              have temporaryStorePreserved : StoreExtends afterStore nextStore :=
                StoreTyping.extends_extend afterStore next.nextCell
                  (.array (.scalar (.signed .i32)) length)
                  nextTyped.typed.nextCell_store_none
              have temporaryCells :=
                allocateTemporary_preserves_initialized_cells
                  nextTyped.typed.wellFormed (.array elements)
              simpa only [evalExpr, placeCase, arrayResult, nextStore] using
                mapped.prepend
                  (storePreserved.trans temporaryStorePreserved)
                  (cellsPreserved.trans temporaryCells) mappedCells
      | trapped reason next | exited reason next =>
          rw [arrayResult] at arrayOutcome
          simpa only [evalExpr, placeCase, arrayResult,
            RuntimeValueOutcomeHasExtendedType] using arrayOutcome
      | outOfFuel =>
          simp [evalExpr, placeCase, arrayResult,
            RuntimeValueOutcomeHasExtendedType]

theorem evalConstant_has_type
    (fuel : Nat)
    (stateTyped : StateHasType program context state store)
    (programTyped : ProgramWellTyped program)
    (constantsClosed : ProgramConstantsClosed program)
    (found : program.constant? constantId = some declaration) :
    ValueOutcomeHasType program context state store
      (evalExpr (fuel + 1) program state (.constant constantId))
      declaration.type := by
  have member : declaration ∈ program.constants :=
    List.mem_of_find?_eq_some found
  have valueTyped := programTyped.1 declaration member
  have valueClosed := constantsClosed declaration member
  simp only [evalExpr, found]
  exact ValueOutcomeHasType.done stateTyped valueTyped
    valueClosed.borrowsValid

theorem evalConstant_has_runtime_type
    (fuel : Nat)
    (stateTyped : RuntimeStateHasType program context state store)
    (programTyped : ProgramWellTyped program)
    (constantsClosed : ProgramConstantsClosed program)
    (found : program.constant? constantId = some declaration) :
    RuntimeValueOutcomeHasExtendedType program context state store
      (evalExpr (fuel + 1) program state (.constant constantId))
      declaration.type := by
  have member : declaration ∈ program.constants :=
    List.mem_of_find?_eq_some found
  have valueTyped := programTyped.1 declaration member
  have valueClosed := constantsClosed declaration member
  simp only [evalExpr, found]
  exact RuntimeValueOutcomeHasExtendedType.done stateTyped valueTyped
    valueClosed.borrowsValid

theorem evalPrintI32_has_type
    (fuel : Nat)
    (argumentPreserved : ValueOutcomeHasType program context state store
      (evalExpr fuel program state argument) (.scalar (.signed .i32))) :
    ValueOutcomeHasType program context state store
      (evalExpr (fuel + 1) program state
        (.intrinsic .printI32 argument)) .unit := by
  cases argumentResult : evalExpr fuel program state argument with
  | done value next =>
      rw [argumentResult] at argumentPreserved
      obtain ⟨afterStore, storePreserved, cellsPreserved, nextTyped,
        valueTyped, valueBorrows⟩ := argumentPreserved
      cases valueTyped with
      | signed type integer lower upper =>
          let nextWorld := next.world.afterPrintI32 integer
          simp only [evalExpr, argumentResult]
          exact ⟨afterStore, storePreserved,
            cellsPreserved.trans
              (InitializedCellsPreserved.withWorld next nextWorld),
            nextTyped.withWorld nextWorld, .unit,
            (show ValueIsClosed .unit by rfl).borrowsValid⟩
  | trapped reason next =>
      rw [argumentResult] at argumentPreserved
      simpa only [evalExpr, argumentResult, ValueOutcomeHasType] using
        argumentPreserved
  | exited code next =>
      rw [argumentResult] at argumentPreserved
      simpa only [evalExpr, argumentResult, ValueOutcomeHasType] using
        argumentPreserved
  | outOfFuel =>
      simp [evalExpr, argumentResult, ValueOutcomeHasType]

theorem evalAssert_has_type
    (fuel : Nat)
    (argumentPreserved : ValueOutcomeHasType program context state store
      (evalExpr fuel program state argument) (.scalar .bool)) :
    ValueOutcomeHasType program context state store
      (evalExpr (fuel + 1) program state
        (.intrinsic .assert argument)) .unit := by
  cases argumentResult : evalExpr fuel program state argument with
  | done value next =>
      rw [argumentResult] at argumentPreserved
      obtain ⟨afterStore, storePreserved, cellsPreserved, nextTyped,
        valueTyped, valueBorrows⟩ := argumentPreserved
      cases valueTyped with
      | boolean condition =>
          cases condition <;> simp only [evalExpr, argumentResult]
          · exact ⟨afterStore, storePreserved, cellsPreserved, nextTyped⟩
          · exact ⟨afterStore, storePreserved, cellsPreserved, nextTyped,
              .unit, (show ValueIsClosed .unit by rfl).borrowsValid⟩
  | trapped reason next =>
      rw [argumentResult] at argumentPreserved
      simpa only [evalExpr, argumentResult, ValueOutcomeHasType] using
        argumentPreserved
  | exited code next =>
      rw [argumentResult] at argumentPreserved
      simpa only [evalExpr, argumentResult, ValueOutcomeHasType] using
        argumentPreserved
  | outOfFuel =>
      simp [evalExpr, argumentResult, ValueOutcomeHasType]

theorem evalPrintI32_has_runtime_type
    (fuel : Nat)
    (argumentPreserved : RuntimeValueOutcomeHasExtendedType program context
      state store (evalExpr fuel program state argument)
      (.scalar (.signed .i32))) :
    RuntimeValueOutcomeHasExtendedType program context state store
      (evalExpr (fuel + 1) program state
        (.intrinsic .printI32 argument)) .unit := by
  cases argumentResult : evalExpr fuel program state argument with
  | done value next =>
      rw [argumentResult] at argumentPreserved
      obtain ⟨afterStore, storePreserved, cellsPreserved, nextTyped,
        valueTyped, valueBorrows⟩ := argumentPreserved
      cases valueTyped with
      | signed type integer lower upper =>
          let nextWorld := next.world.afterPrintI32 integer
          simp only [evalExpr, argumentResult]
          exact ⟨afterStore, storePreserved,
            cellsPreserved.trans
              (InitializedCellsPreserved.withWorld next nextWorld),
            nextTyped.withWorld nextWorld, .unit,
            (show ValueIsClosed .unit by rfl).borrowsValid⟩
  | trapped reason next | exited reason next =>
      rw [argumentResult] at argumentPreserved
      simpa only [evalExpr, argumentResult,
        RuntimeValueOutcomeHasExtendedType] using argumentPreserved
  | outOfFuel =>
      simp [evalExpr, argumentResult, RuntimeValueOutcomeHasExtendedType]

theorem evalAssert_has_runtime_type
    (fuel : Nat)
    (argumentPreserved : RuntimeValueOutcomeHasExtendedType program context
      state store (evalExpr fuel program state argument) (.scalar .bool)) :
    RuntimeValueOutcomeHasExtendedType program context state store
      (evalExpr (fuel + 1) program state
        (.intrinsic .assert argument)) .unit := by
  cases argumentResult : evalExpr fuel program state argument with
  | done value next =>
      rw [argumentResult] at argumentPreserved
      obtain ⟨afterStore, storePreserved, cellsPreserved, nextTyped,
        valueTyped, valueBorrows⟩ := argumentPreserved
      cases valueTyped with
      | boolean condition =>
          cases condition <;> simp only [evalExpr, argumentResult]
          · exact ⟨afterStore, storePreserved, cellsPreserved, nextTyped⟩
          · exact ⟨afterStore, storePreserved, cellsPreserved, nextTyped,
              .unit, (show ValueIsClosed .unit by rfl).borrowsValid⟩
  | trapped reason next | exited reason next =>
      rw [argumentResult] at argumentPreserved
      simpa only [evalExpr, argumentResult,
        RuntimeValueOutcomeHasExtendedType] using argumentPreserved
  | outOfFuel =>
      simp [evalExpr, argumentResult, RuntimeValueOutcomeHasExtendedType]

theorem evalMatchedArm_has_type
    (fuel : Nat)
    (stateTyped : StateHasType program context state store)
    (patternTyped : PatternHasType program pattern scrutineeType bindingTypes)
    (bodyTyped : ExprHasType program (context.bindAll bindingTypes) body resultType)
    (valueTyped : ValueHasType program value scrutineeType)
    (valueBorrows : BorrowsValid program state store value)
    (matched : matchPattern pattern value = some bindings)
    (expressionPreserved :
      ∀ (expressionFuel : Nat) (expressionContext : Context)
        (intermediate : State) (intermediateStore : StoreTyping)
        (expression : Expr) (expressionType : Ty),
        StateHasType program expressionContext intermediate intermediateStore →
        ExprHasType program expressionContext expression expressionType →
        ValueOutcomeHasType program expressionContext intermediate
          intermediateStore
          (evalExpr expressionFuel program intermediate expression)
          expressionType) :
    ValueOutcomeHasType program context state store
      (restoreOutcomeLocals state
        (evalExpr fuel program (state.bindLocals bindings) body))
      resultType := by
  have bindingsTyped := matchPattern_preserves_types patternTyped valueTyped matched
  have bindingsBorrows := matchPattern_preserves_borrows patternTyped valueTyped
    valueBorrows matched
  obtain ⟨boundStore, storePreserved, cellsPreserved, boundTyped⟩ :=
    stateTyped.bindLocals bindingsTyped bindingsBorrows
  have bodyOutcome := expressionPreserved fuel _ _ boundStore body resultType
    boundTyped bodyTyped
  exact bodyOutcome.restoreLocals stateTyped storePreserved cellsPreserved

theorem evalMatchArms_has_type
    (fuel : Nat)
    (stateTyped : StateHasType program context state store)
    (valueTyped : ValueHasType program value scrutineeType)
    (valueBorrows : BorrowsValid program state store value)
    (armsTyped : MatchArmsHaveType program context arms scrutineeType resultType)
    (expressionPreserved :
      ∀ (expressionFuel : Nat) (expressionContext : Context)
        (intermediate : State) (intermediateStore : StoreTyping)
        (expression : Expr) (expressionType : Ty),
        StateHasType program expressionContext intermediate intermediateStore →
        ExprHasType program expressionContext expression expressionType →
        ValueOutcomeHasType program expressionContext intermediate
          intermediateStore
          (evalExpr expressionFuel program intermediate expression)
          expressionType) :
    ValueOutcomeHasType program context state store
      (evalMatchArms fuel program state value arms) resultType := by
  induction fuel generalizing context state store arms with
  | zero => simp [evalMatchArms, ValueOutcomeHasType]
  | succ fuel induction =>
      cases armsTyped with
      | one patternTyped bodyTyped =>
          rename_i armPattern bindingTypes armBody
          cases matchResult : matchPattern armPattern value with
          | none =>
              cases fuel with
              | zero => simp [evalMatchArms, matchResult, ValueOutcomeHasType]
              | succ remaining =>
                  simp only [evalMatchArms, matchResult]
                  exact ⟨store, StoreExtends.refl store,
                    InitializedCellsPreserved.refl state, stateTyped⟩
          | some bindings =>
              simpa only [evalMatchArms, matchResult] using
                evalMatchedArm_has_type fuel stateTyped patternTyped bodyTyped
                  valueTyped valueBorrows matchResult expressionPreserved
      | cons patternTyped bodyTyped tailTyped =>
          rename_i armPattern bindingTypes armBody remainingArms
          cases matchResult : matchPattern armPattern value with
          | none =>
              simpa only [evalMatchArms, matchResult] using
                induction stateTyped valueBorrows tailTyped
          | some bindings =>
              simpa only [evalMatchArms, matchResult] using
                evalMatchedArm_has_type fuel stateTyped patternTyped bodyTyped
                  valueTyped valueBorrows matchResult expressionPreserved

theorem evalMatchValue_has_type
    (fuel : Nat)
    (scrutineePreserved : ValueOutcomeHasType program context state store
      (evalExpr fuel program state scrutinee) scrutineeType)
    (armsTyped : MatchArmsHaveType program context arms scrutineeType resultType)
    (expressionPreserved :
      ∀ (expressionFuel : Nat) (expressionContext : Context)
        (intermediate : State) (intermediateStore : StoreTyping)
        (expression : Expr) (expressionType : Ty),
        StateHasType program expressionContext intermediate intermediateStore →
        ExprHasType program expressionContext expression expressionType →
        ValueOutcomeHasType program expressionContext intermediate
          intermediateStore
          (evalExpr expressionFuel program intermediate expression)
          expressionType) :
    ValueOutcomeHasType program context state store
      (evalExpr (fuel + 1) program state (.matchValue scrutinee arms))
      resultType := by
  cases scrutineeResult : evalExpr fuel program state scrutinee with
  | done value next =>
      rw [scrutineeResult] at scrutineePreserved
      obtain ⟨afterStore, storePreserved, cellsPreserved, nextTyped,
        valueTyped, valueBorrows⟩ := scrutineePreserved
      have armsOutcome := evalMatchArms_has_type fuel nextTyped valueTyped
        valueBorrows armsTyped expressionPreserved
      simpa only [evalExpr, scrutineeResult] using
        armsOutcome.prepend storePreserved cellsPreserved
  | trapped reason next =>
      rw [scrutineeResult] at scrutineePreserved
      simpa only [evalExpr, scrutineeResult, ValueOutcomeHasType] using
        scrutineePreserved
  | exited code next =>
      rw [scrutineeResult] at scrutineePreserved
      simpa only [evalExpr, scrutineeResult, ValueOutcomeHasType] using
        scrutineePreserved
  | outOfFuel =>
      simp [evalExpr, scrutineeResult, ValueOutcomeHasType]

theorem evalMatchedArm_has_runtime_type
    (fuel : Nat)
    (stateTyped : RuntimeStateHasType program context state store)
    (patternTyped : PatternHasType program pattern scrutineeType bindingTypes)
    (_bodyTyped : ExprHasType program (context.bindAll bindingTypes) body
      resultType)
    (valueTyped : ValueHasType program value scrutineeType)
    (valueBorrows : BorrowsValid program state store value)
    (matched : matchPattern pattern value = some bindings)
    (bodyPreserved :
      ∀ (intermediate : State) (intermediateStore : StoreTyping),
        RuntimeStateHasType program (context.bindAll bindingTypes) intermediate
          intermediateStore →
        RuntimeValueOutcomeHasExtendedType program
          (context.bindAll bindingTypes) intermediate intermediateStore
          (evalExpr fuel program intermediate body) resultType) :
    RuntimeValueOutcomeHasExtendedType program context state store
      (restoreOutcomeLocals state
        (evalExpr fuel program (state.bindLocals bindings) body))
      resultType := by
  have bindingsTyped :=
    matchPattern_preserves_types patternTyped valueTyped matched
  have bindingsBorrows := matchPattern_preserves_borrows patternTyped valueTyped
    valueBorrows matched
  obtain ⟨boundStore, storePreserved, cellsPreserved, boundTyped⟩ :=
    stateTyped.bindLocals bindingsTyped bindingsBorrows
  have bodyOutcome := bodyPreserved _ boundStore boundTyped
  exact bodyOutcome.restoreLocals stateTyped storePreserved cellsPreserved

theorem evalMatchArms_has_runtime_type
    (fuel : Nat)
    (stateTyped : RuntimeStateHasType program context state store)
    (valueTyped : ValueHasType program value scrutineeType)
    (valueBorrows : BorrowsValid program state store value)
    (armsTyped : MatchArmsHaveType program context arms scrutineeType resultType)
    (expressionPreserved : RuntimeExpressionsPreserveTypesBelow program limit)
    (fuelLt : fuel < limit) :
    RuntimeValueOutcomeHasExtendedType program context state store
      (evalMatchArms fuel program state value arms) resultType := by
  induction fuel generalizing context state store arms with
  | zero => simp [evalMatchArms, RuntimeValueOutcomeHasExtendedType]
  | succ fuel induction =>
      have smaller : fuel < limit :=
        Nat.lt_trans (Nat.lt_succ_self fuel) fuelLt
      cases armsTyped with
      | one patternTyped bodyTyped =>
          rename_i armPattern bindingTypes armBody
          cases matchResult : matchPattern armPattern value with
          | none =>
              cases fuel with
              | zero =>
                  simp [evalMatchArms, matchResult,
                    RuntimeValueOutcomeHasExtendedType]
              | succ remaining =>
                  simp only [evalMatchArms, matchResult]
                  exact ⟨store, StoreExtends.refl store,
                    InitializedCellsPreserved.refl state, stateTyped⟩
          | some bindings =>
              simpa only [evalMatchArms, matchResult] using
                evalMatchedArm_has_runtime_type fuel stateTyped patternTyped
                  bodyTyped valueTyped valueBorrows matchResult
                  (fun intermediate intermediateStore intermediateTyped =>
                    expressionPreserved fuel smaller _ _ _ _ _
                      intermediateTyped bodyTyped)
      | cons patternTyped bodyTyped tailTyped =>
          rename_i armPattern bindingTypes armBody remainingArms
          cases matchResult : matchPattern armPattern value with
          | none =>
              simpa only [evalMatchArms, matchResult] using
                induction stateTyped valueBorrows tailTyped smaller
          | some bindings =>
              simpa only [evalMatchArms, matchResult] using
                evalMatchedArm_has_runtime_type fuel stateTyped patternTyped
                  bodyTyped valueTyped valueBorrows matchResult
                  (fun intermediate intermediateStore intermediateTyped =>
                    expressionPreserved fuel smaller _ _ _ _ _
                      intermediateTyped bodyTyped)

theorem evalMatchValue_has_runtime_type
    (fuel : Nat)
    (scrutineePreserved : RuntimeValueOutcomeHasExtendedType program context
      state store (evalExpr fuel program state scrutinee) scrutineeType)
    (armsTyped : MatchArmsHaveType program context arms scrutineeType resultType)
    (expressionPreserved : RuntimeExpressionsPreserveTypesBelow program limit)
    (fuelLt : fuel < limit) :
    RuntimeValueOutcomeHasExtendedType program context state store
      (evalExpr (fuel + 1) program state (.matchValue scrutinee arms))
      resultType := by
  cases scrutineeResult : evalExpr fuel program state scrutinee with
  | done value next =>
      rw [scrutineeResult] at scrutineePreserved
      obtain ⟨afterStore, storePreserved, cellsPreserved, nextTyped,
        valueTyped, valueBorrows⟩ := scrutineePreserved
      have armsOutcome := evalMatchArms_has_runtime_type fuel nextTyped
        valueTyped valueBorrows armsTyped expressionPreserved fuelLt
      simpa only [evalExpr, scrutineeResult] using
        armsOutcome.prepend storePreserved cellsPreserved
  | trapped reason next | exited reason next =>
      rw [scrutineeResult] at scrutineePreserved
      simpa only [evalExpr, scrutineeResult,
        RuntimeValueOutcomeHasExtendedType] using scrutineePreserved
  | outOfFuel =>
      simp [evalExpr, scrutineeResult, RuntimeValueOutcomeHasExtendedType]

theorem evalAssign_has_type
    (fuel : Nat)
    (operation : AssignOpHasType op type)
    (placePreserved : PlaceOutcomeHasType program context state store
      (evalPlace fuel program state place) type)
    (rightPreserved :
      ∀ (intermediate : State) (intermediateStore : StoreTyping),
        StateHasType program context intermediate intermediateStore →
        ValueOutcomeHasType program context intermediate intermediateStore
          (evalExpr fuel program intermediate rightExpression) type) :
    ValueOutcomeHasType program context state store
      (evalExpr (fuel + 1) program state
        (.assign op place rightExpression)) .unit := by
  cases placeResult : evalPlace fuel program state place with
  | done resolved afterPlace =>
      rw [placeResult] at placePreserved
      obtain ⟨placeStore, placeStorePreserved, placeCellsPreserved,
        afterPlaceTyped, resolvedTyped⟩ := placePreserved
      have rightOutcome := rightPreserved afterPlace placeStore afterPlaceTyped
      cases rightResult : evalExpr fuel program afterPlace rightExpression with
      | done right afterValue =>
          rw [rightResult] at rightOutcome
          obtain ⟨valueStore, valueStorePreserved, valueCellsPreserved,
            afterValueTyped, rightTyped, rightBorrows⟩ := rightOutcome
          have resolvedAfterValue := resolvedTyped.preserve
            valueStorePreserved valueCellsPreserved afterValueTyped
          simp only [evalExpr, placeResult, rightResult]
          cases assignedValue :
              evalAssignValue program.target op resolved.value right with
          | error reason =>
              simp only
              exact ⟨valueStore, placeStorePreserved.trans valueStorePreserved,
                placeCellsPreserved.trans valueCellsPreserved,
                afterValueTyped⟩
          | ok result =>
              simp only
              have resultTyped := evalAssignValue_preserves_type operation
                (fun currentValue found =>
                  resolvedAfterValue.value_typed found)
                rightTyped assignedValue
              have resultBorrows := evalAssignValue_preserves_borrows operation
                (fun currentValue found =>
                  resolvedAfterValue.value_typed found)
                rightTyped rightBorrows assignedValue
              cases written : writeResolvedPlace afterValue resolved result with
              | error reason =>
                  simp only
                  exact ⟨valueStore,
                    placeStorePreserved.trans valueStorePreserved,
                    placeCellsPreserved.trans valueCellsPreserved,
                    afterValueTyped⟩
              | ok assigned =>
                  simp only
                  have assignedTyped := writeResolvedPlace_preserves_state_typing
                    afterValueTyped resolvedAfterValue resultTyped resultBorrows
                    written
                  have writeCells :=
                    writeResolvedPlace_preserves_initialized_cells written
                  exact ⟨valueStore,
                    placeStorePreserved.trans valueStorePreserved,
                    (placeCellsPreserved.trans valueCellsPreserved).trans
                      writeCells,
                    assignedTyped, .unit,
                    (show ValueIsClosed .unit by rfl).borrowsValid⟩
      | trapped reason next =>
          rw [rightResult] at rightOutcome
          simpa only [evalExpr, placeResult, rightResult,
            ValueOutcomeHasType] using
              rightOutcome.prepend placeStorePreserved placeCellsPreserved
      | exited code next =>
          rw [rightResult] at rightOutcome
          simpa only [evalExpr, placeResult, rightResult,
            ValueOutcomeHasType] using
              rightOutcome.prepend placeStorePreserved placeCellsPreserved
      | outOfFuel =>
          simp [evalExpr, placeResult, rightResult, ValueOutcomeHasType]
  | trapped reason next =>
      rw [placeResult] at placePreserved
      simpa only [evalExpr, placeResult, PlaceOutcomeHasType,
        ValueOutcomeHasType] using placePreserved
  | exited code next =>
      rw [placeResult] at placePreserved
      simpa only [evalExpr, placeResult, PlaceOutcomeHasType,
        ValueOutcomeHasType] using placePreserved
  | outOfFuel =>
      simp [evalExpr, placeResult, ValueOutcomeHasType]

theorem evalAssign_has_runtime_type
    (fuel : Nat)
    (operation : AssignOpHasType op type)
    (placePreserved : RuntimePlaceOutcomeHasType program context state store
      (evalPlace fuel program state place) type)
    (rightPreserved :
      ∀ (intermediate : State) (intermediateStore : StoreTyping),
        RuntimeStateHasType program context intermediate intermediateStore →
        RuntimeValueOutcomeHasExtendedType program context intermediate
          intermediateStore
          (evalExpr fuel program intermediate rightExpression) type) :
    RuntimeValueOutcomeHasExtendedType program context state store
      (evalExpr (fuel + 1) program state
        (.assign op place rightExpression)) .unit := by
  cases placeResult : evalPlace fuel program state place with
  | done resolved afterPlace =>
      rw [placeResult] at placePreserved
      obtain ⟨placeStore, placeStorePreserved, placeCellsPreserved,
        afterPlaceTyped, resolvedTyped⟩ := placePreserved
      have rightOutcome :=
        rightPreserved afterPlace placeStore afterPlaceTyped
      cases rightResult : evalExpr fuel program afterPlace rightExpression with
      | done right afterValue =>
          rw [rightResult] at rightOutcome
          obtain ⟨valueStore, valueStorePreserved, valueCellsPreserved,
            afterValueTyped, rightTyped, rightBorrows⟩ := rightOutcome
          have resolvedAfterValue := resolvedTyped.preserve
            valueStorePreserved valueCellsPreserved afterValueTyped.typed
          simp only [evalExpr, placeResult, rightResult]
          cases assignedValue :
              evalAssignValue program.target op resolved.value right with
          | error reason =>
              simp only
              exact ⟨valueStore,
                placeStorePreserved.trans valueStorePreserved,
                placeCellsPreserved.trans valueCellsPreserved,
                afterValueTyped⟩
          | ok result =>
              simp only
              have resultTyped := evalAssignValue_preserves_type operation
                (fun currentValue found =>
                  resolvedAfterValue.value_typed found)
                rightTyped assignedValue
              have resultBorrows := evalAssignValue_preserves_borrows operation
                (fun currentValue found =>
                  resolvedAfterValue.value_typed found)
                rightTyped rightBorrows assignedValue
              cases written : writeResolvedPlace afterValue resolved result with
              | error reason =>
                  simp only
                  exact ⟨valueStore,
                    placeStorePreserved.trans valueStorePreserved,
                    placeCellsPreserved.trans valueCellsPreserved,
                    afterValueTyped⟩
              | ok assigned =>
                  simp only
                  have assignedTyped := writeResolvedPlace_preserves_runtime_type
                    afterValueTyped resolvedAfterValue resultTyped resultBorrows
                    written
                  have writeCells :=
                    writeResolvedPlace_preserves_initialized_cells written
                  exact ⟨valueStore,
                    placeStorePreserved.trans valueStorePreserved,
                    (placeCellsPreserved.trans valueCellsPreserved).trans
                      writeCells,
                    assignedTyped, .unit,
                    (show ValueIsClosed .unit by rfl).borrowsValid⟩
      | trapped reason next | exited reason next =>
          rw [rightResult] at rightOutcome
          simpa only [evalExpr, placeResult, rightResult,
            RuntimeValueOutcomeHasExtendedType] using
              rightOutcome.prepend placeStorePreserved placeCellsPreserved
      | outOfFuel =>
          simp [evalExpr, placeResult, rightResult,
            RuntimeValueOutcomeHasExtendedType]
  | trapped reason next | exited reason next =>
      rw [placeResult] at placePreserved
      simpa only [evalExpr, placeResult, RuntimePlaceOutcomeHasType,
        RuntimeValueOutcomeHasExtendedType] using placePreserved
  | outOfFuel =>
      simp [evalExpr, placeResult, RuntimeValueOutcomeHasExtendedType]

theorem evalAlloc_has_runtime_type
    (fuel : Nat)
    (sizePreserved : RuntimeValueOutcomeHasExtendedType program context state
      store (evalExpr fuel program state sizeExpression)
      (.scalar (.unsigned .usize)))
    (alignmentPreserved :
      ∀ (intermediate : State) (intermediateStore : StoreTyping),
        RuntimeStateHasType program context intermediate intermediateStore →
        RuntimeValueOutcomeHasExtendedType program context intermediate
          intermediateStore
          (evalExpr fuel program intermediate alignmentExpression)
          (.scalar (.unsigned .usize))) :
    RuntimeValueOutcomeHasExtendedType program context state store
      (evalExpr (fuel + 1) program state
        (.alloc sizeExpression alignmentExpression)) (.scalar .rawPtr) := by
  cases sizeResult : evalExpr fuel program state sizeExpression with
  | done sizeValue afterSize =>
      rw [sizeResult] at sizePreserved
      obtain ⟨sizeStore, sizeStorePreserved, sizeCellsPreserved,
        afterSizeTyped, sizeTyped, sizeBorrows⟩ := sizePreserved
      obtain ⟨size, rfl⟩ := valueHasType_usize_shape sizeTyped
      have alignmentOutcome :=
        alignmentPreserved afterSize sizeStore afterSizeTyped
      cases alignmentResult :
          evalExpr fuel program afterSize alignmentExpression with
      | done alignmentValue afterAlignment =>
          rw [alignmentResult] at alignmentOutcome
          obtain ⟨alignmentStore, alignmentStorePreserved,
            alignmentCellsPreserved, afterAlignmentTyped, alignmentTyped,
            alignmentBorrows⟩ := alignmentOutcome
          obtain ⟨alignment, rfl⟩ :=
            valueHasType_usize_shape alignmentTyped
          have allocated := allocate_has_runtime_type
            (size := size) (alignment := alignment) afterAlignmentTyped
          cases allocation : afterAlignment.heap.allocate size alignment with
          | allocated pointer heap =>
              rw [allocation] at allocated
              have allocationCells : ValueOutcomePreservesInitializedCells
                  afterAlignment
                  (.done (.pointer pointer) { afterAlignment with heap }) :=
                InitializedCellsPreserved.withHeap afterAlignment heap
              simpa only [evalExpr, sizeResult, alignmentResult, allocation]
                using allocated.prepend
                  (sizeStorePreserved.trans alignmentStorePreserved)
                  (sizeCellsPreserved.trans alignmentCellsPreserved)
                  allocationCells
          | exhausted heap =>
              rw [allocation] at allocated
              have allocationCells : ValueOutcomePreservesInitializedCells
                  afterAlignment
                  (.done (.pointer null) { afterAlignment with heap }) :=
                InitializedCellsPreserved.withHeap afterAlignment heap
              simpa only [evalExpr, sizeResult, alignmentResult, allocation]
                using allocated.prepend
                  (sizeStorePreserved.trans alignmentStorePreserved)
                  (sizeCellsPreserved.trans alignmentCellsPreserved)
                  allocationCells
          | trapped reason heap =>
              rw [allocation] at allocated
              have allocationCells : ValueOutcomePreservesInitializedCells
                  afterAlignment
                  (.trapped reason { afterAlignment with heap }) :=
                InitializedCellsPreserved.withHeap afterAlignment heap
              simpa only [evalExpr, sizeResult, alignmentResult, allocation]
                using allocated.prepend
                  (sizeStorePreserved.trans alignmentStorePreserved)
                  (sizeCellsPreserved.trans alignmentCellsPreserved)
                  allocationCells
      | trapped reason next | exited reason next =>
          rw [alignmentResult] at alignmentOutcome
          simpa only [evalExpr, sizeResult, alignmentResult,
            RuntimeValueOutcomeHasExtendedType] using
              alignmentOutcome.prepend sizeStorePreserved sizeCellsPreserved
      | outOfFuel =>
          simp [evalExpr, sizeResult, alignmentResult,
            RuntimeValueOutcomeHasExtendedType]
  | trapped reason next | exited reason next =>
      rw [sizeResult] at sizePreserved
      simpa only [evalExpr, sizeResult,
        RuntimeValueOutcomeHasExtendedType] using sizePreserved
  | outOfFuel =>
      simp [evalExpr, sizeResult, RuntimeValueOutcomeHasExtendedType]

theorem evalRealloc_has_runtime_type
    (fuel : Nat)
    (argumentsPreserved : RuntimeValuesOutcomeHaveTypes program context state
      store (evalExprs fuel program state
        [pointerExpression, oldSizeExpression, newSizeExpression,
          alignmentExpression])
        [(.scalar .rawPtr), (.scalar (.unsigned .usize)),
          (.scalar (.unsigned .usize)), (.scalar (.unsigned .usize))]) :
    RuntimeValueOutcomeHasExtendedType program context state store
      (evalExpr (fuel + 1) program state
        (.realloc pointerExpression oldSizeExpression newSizeExpression
          alignmentExpression)) (.scalar .rawPtr) := by
  cases argumentsResult : evalExprs fuel program state
      [pointerExpression, oldSizeExpression, newSizeExpression,
        alignmentExpression] with
  | done values next =>
      rw [argumentsResult] at argumentsPreserved
      obtain ⟨afterStore, storePreserved, cellsPreserved, nextTyped,
        valuesTyped, valuesBorrows⟩ := argumentsPreserved
      obtain ⟨pointer, oldSize, newSize, alignment, rfl⟩ :=
        valuesHaveTypes_ptr_usize_usize_usize_shape valuesTyped
      cases synchronized : syncI32ViewsToHeap next with
      | error reason =>
          simp only [evalExpr, argumentsResult, synchronized]
          exact ⟨afterStore, storePreserved, cellsPreserved, nextTyped⟩
      | ok synchronizedState =>
          have synchronizedTyped := syncI32ViewsToHeap_preserves_runtime_type
            nextTyped synchronized
          have synchronizedCells :=
            syncI32ViewsToHeap_preserves_initialized_cells synchronized
          have reallocated := reallocate_has_runtime_type
            (pointer := pointer) (oldSize := oldSize) (newSize := newSize)
            (alignment := alignment) synchronizedTyped
          cases reallocation : synchronizedState.heap.reallocate pointer oldSize
              newSize alignment with
          | allocated replacement heap =>
              rw [reallocation] at reallocated
              have reallocatedCells : ValueOutcomePreservesInitializedCells
                  synchronizedState
                  (.done (.pointer replacement)
                    { synchronizedState with heap }) :=
                InitializedCellsPreserved.withHeap synchronizedState heap
              simpa only [evalExpr, argumentsResult, synchronized,
                reallocation] using reallocated.prepend storePreserved
                  (cellsPreserved.trans synchronizedCells) reallocatedCells
          | exhausted heap =>
              rw [reallocation] at reallocated
              have reallocatedCells : ValueOutcomePreservesInitializedCells
                  synchronizedState
                  (.done (.pointer null) { synchronizedState with heap }) :=
                InitializedCellsPreserved.withHeap synchronizedState heap
              simpa only [evalExpr, argumentsResult, synchronized,
                reallocation] using reallocated.prepend storePreserved
                  (cellsPreserved.trans synchronizedCells) reallocatedCells
          | trapped reason heap =>
              rw [reallocation] at reallocated
              have reallocatedCells : ValueOutcomePreservesInitializedCells
                  synchronizedState
                  (.trapped reason { synchronizedState with heap }) :=
                InitializedCellsPreserved.withHeap synchronizedState heap
              simpa only [evalExpr, argumentsResult, synchronized,
                reallocation] using reallocated.prepend storePreserved
                  (cellsPreserved.trans synchronizedCells) reallocatedCells
  | trapped reason next | exited reason next =>
      rw [argumentsResult] at argumentsPreserved
      simpa only [evalExpr, argumentsResult,
        RuntimeValuesOutcomeHaveTypes,
        RuntimeValueOutcomeHasExtendedType] using argumentsPreserved
  | outOfFuel =>
      simp [evalExpr, argumentsResult, RuntimeValueOutcomeHasExtendedType]

theorem evalDealloc_has_runtime_type
    (fuel : Nat)
    (argumentsPreserved : RuntimeValuesOutcomeHaveTypes program context state
      store (evalExprs fuel program state
        [pointerExpression, sizeExpression, alignmentExpression])
        [(.scalar .rawPtr), (.scalar (.unsigned .usize)),
          (.scalar (.unsigned .usize))]) :
    RuntimeValueOutcomeHasExtendedType program context state store
      (evalExpr (fuel + 1) program state
        (.dealloc pointerExpression sizeExpression alignmentExpression))
      .unit := by
  cases argumentsResult : evalExprs fuel program state
      [pointerExpression, sizeExpression, alignmentExpression] with
  | done values next =>
      rw [argumentsResult] at argumentsPreserved
      obtain ⟨afterStore, storePreserved, cellsPreserved, nextTyped,
        valuesTyped, valuesBorrows⟩ := argumentsPreserved
      obtain ⟨pointer, size, alignment, rfl⟩ :=
        valuesHaveTypes_ptr_usize_usize_shape valuesTyped
      cases synchronized : syncI32ViewsToHeap next with
      | error reason =>
          simp only [evalExpr, argumentsResult, synchronized]
          exact ⟨afterStore, storePreserved, cellsPreserved, nextTyped⟩
      | ok synchronizedState =>
          have synchronizedTyped := syncI32ViewsToHeap_preserves_runtime_type
            nextTyped synchronized
          have synchronizedCells :=
            syncI32ViewsToHeap_preserves_initialized_cells synchronized
          have deallocated := deallocate_has_runtime_type
            (pointer := pointer) (size := size) (alignment := alignment)
            synchronizedTyped
          cases deallocation : synchronizedState.heap.deallocate pointer size
              alignment with
          | error reason =>
              rw [deallocation] at deallocated
              have deallocatedCells : ValueOutcomePreservesInitializedCells
                  synchronizedState (.trapped reason synchronizedState) :=
                InitializedCellsPreserved.refl synchronizedState
              simpa only [evalExpr, argumentsResult, synchronized,
                deallocation] using deallocated.prepend storePreserved
                  (cellsPreserved.trans synchronizedCells) deallocatedCells
          | ok heap =>
              rw [deallocation] at deallocated
              have deallocatedCells : ValueOutcomePreservesInitializedCells
                  synchronizedState
                  (.done .unit { synchronizedState with heap }) :=
                InitializedCellsPreserved.withHeap synchronizedState heap
              simpa only [evalExpr, argumentsResult, synchronized,
                deallocation] using deallocated.prepend storePreserved
                  (cellsPreserved.trans synchronizedCells) deallocatedCells
  | trapped reason next | exited reason next =>
      rw [argumentsResult] at argumentsPreserved
      simpa only [evalExpr, argumentsResult,
        RuntimeValuesOutcomeHaveTypes,
        RuntimeValueOutcomeHasExtendedType] using argumentsPreserved
  | outOfFuel =>
      simp [evalExpr, argumentsResult, RuntimeValueOutcomeHasExtendedType]

theorem evalLoadByte_has_runtime_type
    (fuel : Nat)
    (argumentsPreserved : RuntimeValuesOutcomeHaveTypes program context state
      store (evalExprs fuel program state [pointerExpression, offsetExpression])
        [(.scalar .rawPtr), (.scalar (.unsigned .usize))]) :
    RuntimeValueOutcomeHasExtendedType program context state store
      (evalExpr (fuel + 1) program state
        (.loadByte pointerExpression offsetExpression))
      (.scalar (.unsigned .u8)) := by
  cases argumentsResult : evalExprs fuel program state
      [pointerExpression, offsetExpression] with
  | done values next =>
      rw [argumentsResult] at argumentsPreserved
      obtain ⟨afterStore, storePreserved, cellsPreserved, nextTyped,
        valuesTyped, valuesBorrows⟩ := argumentsPreserved
      obtain ⟨pointer, offset, rfl⟩ :=
        valuesHaveTypes_ptr_usize_shape valuesTyped
      cases synchronized : syncI32ViewsToHeap next with
      | error reason =>
          simp only [evalExpr, argumentsResult, synchronized]
          exact ⟨afterStore, storePreserved, cellsPreserved, nextTyped⟩
      | ok synchronizedState =>
          have synchronizedTyped := syncI32ViewsToHeap_preserves_runtime_type
            nextTyped synchronized
          have synchronizedCells :=
            syncI32ViewsToHeap_preserves_initialized_cells synchronized
          have loaded := loadByte_has_runtime_type
            (pointer := pointer) (offset := offset) synchronizedTyped
          cases loadResult : synchronizedState.heap.loadByte pointer offset with
          | error reason =>
              rw [loadResult] at loaded
              have loadedCells : ValueOutcomePreservesInitializedCells
                  synchronizedState (.trapped reason synchronizedState) :=
                InitializedCellsPreserved.refl synchronizedState
              simpa only [evalExpr, argumentsResult, synchronized,
                loadResult] using loaded.prepend storePreserved
                  (cellsPreserved.trans synchronizedCells) loadedCells
          | ok byte =>
              rw [loadResult] at loaded
              have loadedCells : ValueOutcomePreservesInitializedCells
                  synchronizedState
                  (.done (.unsigned .u8 byte.toNat) synchronizedState) :=
                InitializedCellsPreserved.refl synchronizedState
              simpa only [evalExpr, argumentsResult, synchronized,
                loadResult] using loaded.prepend storePreserved
                  (cellsPreserved.trans synchronizedCells) loadedCells
  | trapped reason next | exited reason next =>
      rw [argumentsResult] at argumentsPreserved
      simpa only [evalExpr, argumentsResult,
        RuntimeValuesOutcomeHaveTypes,
        RuntimeValueOutcomeHasExtendedType] using argumentsPreserved
  | outOfFuel =>
      simp [evalExpr, argumentsResult, RuntimeValueOutcomeHasExtendedType]

theorem evalStoreByte_has_runtime_type
    (fuel : Nat)
    (argumentsPreserved : RuntimeValuesOutcomeHaveTypes program context state
      store (evalExprs fuel program state
        [pointerExpression, offsetExpression, valueExpression])
        [(.scalar .rawPtr), (.scalar (.unsigned .usize)),
          (.scalar (.unsigned .u8))]) :
    RuntimeValueOutcomeHasExtendedType program context state store
      (evalExpr (fuel + 1) program state
        (.storeByte pointerExpression offsetExpression valueExpression))
      .unit := by
  cases argumentsResult : evalExprs fuel program state
      [pointerExpression, offsetExpression, valueExpression] with
  | done values next =>
      rw [argumentsResult] at argumentsPreserved
      obtain ⟨afterStore, storePreserved, cellsPreserved, nextTyped,
        valuesTyped, valuesBorrows⟩ := argumentsPreserved
      obtain ⟨pointer, offset, byte, rfl⟩ :=
        valuesHaveTypes_ptr_usize_u8_shape valuesTyped
      cases synchronized : syncI32ViewsToHeap next with
      | error reason =>
          simp only [evalExpr, argumentsResult, synchronized]
          exact ⟨afterStore, storePreserved, cellsPreserved, nextTyped⟩
      | ok synchronizedState =>
          have synchronizedTyped := syncI32ViewsToHeap_preserves_runtime_type
            nextTyped synchronized
          have synchronizedCells :=
            syncI32ViewsToHeap_preserves_initialized_cells synchronized
          have stored := storeByte_has_runtime_type
            (pointer := pointer) (offset := offset) (byte := UInt8.ofNat byte)
            synchronizedTyped
          cases storeResult : synchronizedState.heap.storeByte pointer offset
              (UInt8.ofNat byte) with
          | error reason =>
              rw [storeResult] at stored
              have storedCells : ValueOutcomePreservesInitializedCells
                  synchronizedState (.trapped reason synchronizedState) :=
                InitializedCellsPreserved.refl synchronizedState
              simpa only [evalExpr, argumentsResult, synchronized,
                storeResult] using stored.prepend storePreserved
                  (cellsPreserved.trans synchronizedCells) storedCells
          | ok heap =>
              cases fromHeap : syncI32ViewsFromHeap
                  { synchronizedState with heap } with
              | error reason =>
                  simp only [storeResult, fromHeap] at stored
                  have storedCells : ValueOutcomePreservesInitializedCells
                      synchronizedState
                      (.trapped reason { synchronizedState with heap }) :=
                    InitializedCellsPreserved.withHeap synchronizedState heap
                  simpa only [evalExpr, argumentsResult, synchronized,
                    storeResult, fromHeap] using stored.prepend storePreserved
                      (cellsPreserved.trans synchronizedCells) storedCells
              | ok updated =>
                  simp only [storeResult, fromHeap] at stored
                  have storedCells : ValueOutcomePreservesInitializedCells
                      synchronizedState (.done .unit updated) :=
                    (InitializedCellsPreserved.withHeap synchronizedState heap).trans
                      (syncI32ViewsFromHeap_preserves_initialized_cells fromHeap)
                  simpa only [evalExpr, argumentsResult, synchronized,
                    storeResult, fromHeap] using stored.prepend storePreserved
                      (cellsPreserved.trans synchronizedCells) storedCells
  | trapped reason next | exited reason next =>
      rw [argumentsResult] at argumentsPreserved
      simpa only [evalExpr, argumentsResult,
        RuntimeValuesOutcomeHaveTypes,
        RuntimeValueOutcomeHasExtendedType] using argumentsPreserved
  | outOfFuel =>
      simp [evalExpr, argumentsResult, RuntimeValueOutcomeHasExtendedType]

theorem execSkip_has_runtime_type
    (fuel : Nat)
    (stateTyped : RuntimeStateHasType program context state store) :
    RuntimeCompletionOutcomeHasType program returnType context inLoop state
      store (execStmt (fuel + 1) program state .skip) := by
  exact ⟨store, StoreExtends.refl store,
    InitializedCellsPreserved.refl state, stateTyped, trivial⟩

theorem execExpression_has_runtime_type
    (fuel : Nat)
    (expressionPreserved : RuntimeValueOutcomeHasExtendedType program context
      state store (evalExpr fuel program state expression) type) :
    RuntimeCompletionOutcomeHasType program returnType context inLoop state
      store (execStmt (fuel + 1) program state (.expression expression)) := by
  cases expressionResult : evalExpr fuel program state expression with
  | done value next =>
      rw [expressionResult] at expressionPreserved
      obtain ⟨afterStore, storePreserved, cellsPreserved, nextTyped,
        valueTyped, valueBorrows⟩ := expressionPreserved
      simp only [execStmt, expressionResult]
      exact ⟨afterStore, storePreserved, cellsPreserved, nextTyped, trivial⟩
  | trapped reason next | exited reason next =>
      rw [expressionResult] at expressionPreserved
      simpa only [execStmt, expressionResult,
        RuntimeValueOutcomeHasExtendedType,
        RuntimeCompletionOutcomeHasType] using expressionPreserved
  | outOfFuel =>
      simp [execStmt, expressionResult, RuntimeCompletionOutcomeHasType]

theorem execReturnUnit_has_runtime_type
    (fuel : Nat)
    (stateTyped : RuntimeStateHasType program context state store)
    (isUnit : returnType = .unit) :
    RuntimeCompletionOutcomeHasType program returnType context inLoop state
      store (execStmt (fuel + 1) program state (.returnValue none)) := by
  exact ⟨store, StoreExtends.refl store,
    InitializedCellsPreserved.refl state, stateTyped, isUnit⟩

theorem execReturnValue_has_runtime_type
    (fuel : Nat)
    (valuePreserved : RuntimeValueOutcomeHasExtendedType program context state
      store (evalExpr fuel program state expression) returnType) :
    RuntimeCompletionOutcomeHasType program returnType context inLoop state
      store (execStmt (fuel + 1) program state
        (.returnValue (some expression))) := by
  cases valueResult : evalExpr fuel program state expression with
  | done value next =>
      rw [valueResult] at valuePreserved
      obtain ⟨afterStore, storePreserved, cellsPreserved, nextTyped,
        valueTyped, valueBorrows⟩ := valuePreserved
      simp only [execStmt, valueResult]
      exact ⟨afterStore, storePreserved, cellsPreserved, nextTyped,
        valueTyped, valueBorrows⟩
  | trapped reason next | exited reason next =>
      rw [valueResult] at valuePreserved
      simpa only [execStmt, valueResult,
        RuntimeValueOutcomeHasExtendedType,
        RuntimeCompletionOutcomeHasType] using valuePreserved
  | outOfFuel =>
      simp [execStmt, valueResult, RuntimeCompletionOutcomeHasType]

theorem execBreak_has_runtime_type
    (fuel : Nat)
    (stateTyped : RuntimeStateHasType program context state store) :
    RuntimeCompletionOutcomeHasType program returnType context true state store
      (execStmt (fuel + 1) program state .breakLoop) := by
  exact ⟨store, StoreExtends.refl store,
    InitializedCellsPreserved.refl state, stateTyped, rfl⟩

theorem execContinue_has_runtime_type
    (fuel : Nat)
    (stateTyped : RuntimeStateHasType program context state store) :
    RuntimeCompletionOutcomeHasType program returnType context true state store
      (execStmt (fuel + 1) program state .continueLoop) := by
  exact ⟨store, StoreExtends.refl store,
    InitializedCellsPreserved.refl state, stateTyped, rfl⟩

theorem execSequence_has_runtime_type
    (fuel : Nat)
    (firstPreserved : RuntimeCompletionOutcomeHasType program returnType context
      inLoop state store (execStmt fuel program state first))
    (secondPreserved :
      ∀ (intermediate : State) (intermediateStore : StoreTyping),
        RuntimeStateHasType program context intermediate intermediateStore →
        RuntimeCompletionOutcomeHasType program returnType context inLoop
          intermediate intermediateStore
          (execStmt fuel program intermediate second)) :
    RuntimeCompletionOutcomeHasType program returnType context inLoop state store
      (execStmt (fuel + 1) program state (.sequence first second)) := by
  cases firstResult : execStmt fuel program state first with
  | done completion next =>
      rw [firstResult] at firstPreserved
      obtain ⟨afterStore, storePreserved, cellsPreserved, nextTyped,
        completionTyped⟩ := firstPreserved
      cases completion with
      | next =>
          have secondOutcome := secondPreserved next afterStore nextTyped
          simpa only [execStmt, firstResult] using
            secondOutcome.prepend storePreserved cellsPreserved
      | returned value | breakLoop | continueLoop =>
          simp only [execStmt, firstResult]
          exact ⟨afterStore, storePreserved, cellsPreserved, nextTyped,
            completionTyped⟩
  | trapped reason next | exited reason next =>
      rw [firstResult] at firstPreserved
      simpa only [execStmt, firstResult,
        RuntimeCompletionOutcomeHasType] using firstPreserved
  | outOfFuel =>
      simp [execStmt, firstResult, RuntimeCompletionOutcomeHasType]

theorem execIfThenElse_has_runtime_type
    (fuel : Nat)
    (conditionPreserved : RuntimeValueOutcomeHasExtendedType program context
      state store (evalExpr fuel program state condition) (.scalar .bool))
    (thenPreserved :
      ∀ (intermediate : State) (intermediateStore : StoreTyping),
        RuntimeStateHasType program context intermediate intermediateStore →
        RuntimeCompletionOutcomeHasType program returnType context inLoop
          intermediate intermediateStore
          (execStmt fuel program intermediate thenBranch))
    (elsePreserved :
      ∀ (intermediate : State) (intermediateStore : StoreTyping),
        RuntimeStateHasType program context intermediate intermediateStore →
        RuntimeCompletionOutcomeHasType program returnType context inLoop
          intermediate intermediateStore
          (execStmt fuel program intermediate elseBranch)) :
    RuntimeCompletionOutcomeHasType program returnType context inLoop state store
      (execStmt (fuel + 1) program state
        (.ifThenElse condition thenBranch elseBranch)) := by
  cases conditionResult : evalExpr fuel program state condition with
  | done value next =>
      rw [conditionResult] at conditionPreserved
      obtain ⟨afterStore, storePreserved, cellsPreserved, nextTyped,
        valueTyped, valueBorrows⟩ := conditionPreserved
      cases valueTyped with
      | boolean conditionValue =>
          cases conditionValue
          · have branchOutcome := elsePreserved next afterStore nextTyped
            simpa only [execStmt, conditionResult] using
              branchOutcome.prepend storePreserved cellsPreserved
          · have branchOutcome := thenPreserved next afterStore nextTyped
            simpa only [execStmt, conditionResult] using
              branchOutcome.prepend storePreserved cellsPreserved
  | trapped reason next | exited reason next =>
      rw [conditionResult] at conditionPreserved
      simpa only [execStmt, conditionResult,
        RuntimeValueOutcomeHasExtendedType,
        RuntimeCompletionOutcomeHasType] using conditionPreserved
  | outOfFuel =>
      simp [execStmt, conditionResult, RuntimeCompletionOutcomeHasType]

theorem execLetLocal_has_runtime_type
    (fuel : Nat) (id : VarId)
    (initializerPreserved : RuntimeValueOutcomeHasExtendedType program context
      state store (evalExpr fuel program state initializer) type)
    (bodyPreserved :
      ∀ (intermediate : State) (intermediateStore : StoreTyping),
        RuntimeStateHasType program (context.bind id type) intermediate
          intermediateStore →
        RuntimeCompletionOutcomeHasType program returnType
          (context.bind id type) inLoop intermediate intermediateStore
          (execStmt fuel program intermediate body)) :
    RuntimeCompletionOutcomeHasType program returnType context inLoop state store
      (execStmt (fuel + 1) program state
        (.letLocal id type initializer body)) := by
  cases initializerResult : evalExpr fuel program state initializer with
  | done value next =>
      rw [initializerResult] at initializerPreserved
      obtain ⟨afterStore, storePreserved, cellsPreserved, nextTyped,
        valueTyped, valueBorrows⟩ := initializerPreserved
      have boundTyped := nextTyped.bindLocal id valueTyped valueBorrows
      have boundStorePreserved := StoreTyping.extends_extend afterStore
        next.nextCell type nextTyped.typed.nextCell_store_none
      have boundCellsPreserved := bindLocal_preserves_initialized_cells
        nextTyped.typed.wellFormed id value
      have bodyOutcome := bodyPreserved (next.bindLocal id value)
        (afterStore.extend next.nextCell type) boundTyped
      have restored := bodyOutcome.restoreLocals nextTyped boundStorePreserved
        boundCellsPreserved
      simpa only [execStmt, initializerResult] using
        restored.prepend storePreserved cellsPreserved
  | trapped reason next | exited reason next =>
      rw [initializerResult] at initializerPreserved
      simpa only [execStmt, initializerResult,
        RuntimeValueOutcomeHasExtendedType,
        RuntimeCompletionOutcomeHasType] using initializerPreserved
  | outOfFuel =>
      simp [execStmt, initializerResult, RuntimeCompletionOutcomeHasType]

theorem execLetUninitialized_has_runtime_type
    (fuel : Nat) (id : VarId)
    (stateTyped : RuntimeStateHasType program context state store)
    (bodyPreserved :
      ∀ (intermediate : State) (intermediateStore : StoreTyping),
        RuntimeStateHasType program (context.bind id type) intermediate
          intermediateStore →
        RuntimeCompletionOutcomeHasType program returnType
          (context.bind id type) inLoop intermediate intermediateStore
          (execStmt fuel program intermediate body)) :
    RuntimeCompletionOutcomeHasType program returnType context inLoop state store
      (execStmt (fuel + 1) program state
        (.letUninitialized id type body)) := by
  have boundTyped := stateTyped.bindUninitialized id type
  have storePreserved := StoreTyping.extends_extend store state.nextCell type
    stateTyped.typed.nextCell_store_none
  have cellsPreserved := bindUninitialized_preserves_initialized_cells
    stateTyped.typed.wellFormed id
  have bodyOutcome := bodyPreserved (state.bindUninitialized id)
    (store.extend state.nextCell type) boundTyped
  simpa only [execStmt] using
    bodyOutcome.restoreLocals stateTyped storePreserved cellsPreserved

theorem execWhileLoop_has_runtime_type
    (fuel : Nat)
    (stateTyped : RuntimeStateHasType program context state store)
    (conditionPreserved :
      ∀ (expressionFuel : Nat) (intermediate : State)
        (intermediateStore : StoreTyping),
        expressionFuel ≤ fuel →
        RuntimeStateHasType program context intermediate intermediateStore →
        RuntimeValueOutcomeHasExtendedType program context intermediate
          intermediateStore
          (evalExpr expressionFuel program intermediate condition)
          (.scalar .bool))
    (bodyPreserved :
      ∀ (statementFuel : Nat) (intermediate : State)
        (intermediateStore : StoreTyping),
        statementFuel ≤ fuel →
        RuntimeStateHasType program context intermediate intermediateStore →
        RuntimeCompletionOutcomeHasType program returnType context true
          intermediate intermediateStore
          (execStmt statementFuel program intermediate body)) :
    RuntimeCompletionOutcomeHasType program returnType context inLoop state store
      (execStmt (fuel + 1) program state (.whileLoop condition body)) := by
  induction fuel generalizing inLoop state store with
  | zero =>
      rw [execStmt.eq_8]
      rw [evalExpr.eq_1]
      simp only
      trivial
  | succ fuel induction =>
      have conditionOutcome := conditionPreserved (fuel + 1) state store
        (Nat.le_refl _) stateTyped
      cases conditionResult : evalExpr (fuel + 1) program state condition with
      | done value afterCondition =>
          rw [conditionResult] at conditionOutcome
          obtain ⟨conditionStore, conditionStorePreserved,
            conditionCellsPreserved, afterConditionTyped, valueTyped,
            valueBorrows⟩ := conditionOutcome
          cases valueTyped with
          | boolean conditionValue =>
              cases conditionValue with
              | false =>
                  rw [execStmt.eq_8]
                  simp only [conditionResult]
                  exact ⟨conditionStore, conditionStorePreserved,
                    conditionCellsPreserved, afterConditionTyped, trivial⟩
              | true =>
                  rw [execStmt.eq_8]
                  simp only [conditionResult]
                  have bodyOutcome := bodyPreserved (fuel + 1) afterCondition
                    conditionStore (Nat.le_refl _) afterConditionTyped
                  cases bodyResult : execStmt (fuel + 1) program afterCondition
                      body with
                  | done completion completed =>
                      rw [bodyResult] at bodyOutcome
                      obtain ⟨bodyStore, bodyStorePreserved, bodyCellsPreserved,
                        completedTyped, completionTyped⟩ := bodyOutcome
                      cases completion with
                      | next =>
                          have nextIteration := induction
                            (conditionPreserved := fun expressionFuel intermediate
                              intermediateStore expressionFuelLe typed =>
                                conditionPreserved expressionFuel intermediate
                                  intermediateStore
                                  (Nat.le_trans expressionFuelLe
                                    (Nat.le_succ fuel)) typed)
                            (bodyPreserved := fun statementFuel intermediate
                              intermediateStore statementFuelLe typed =>
                                bodyPreserved statementFuel intermediate
                                  intermediateStore
                                  (Nat.le_trans statementFuelLe
                                    (Nat.le_succ fuel)) typed)
                            (inLoop := inLoop) completedTyped
                          simp only
                          exact
                            (nextIteration.prepend bodyStorePreserved
                              bodyCellsPreserved).prepend conditionStorePreserved
                                conditionCellsPreserved
                      | continueLoop =>
                          have nextIteration := induction
                            (conditionPreserved := fun expressionFuel intermediate
                              intermediateStore expressionFuelLe typed =>
                                conditionPreserved expressionFuel intermediate
                                  intermediateStore
                                  (Nat.le_trans expressionFuelLe
                                    (Nat.le_succ fuel)) typed)
                            (bodyPreserved := fun statementFuel intermediate
                              intermediateStore statementFuelLe typed =>
                                bodyPreserved statementFuel intermediate
                                  intermediateStore
                                  (Nat.le_trans statementFuelLe
                                    (Nat.le_succ fuel)) typed)
                            (inLoop := inLoop) completedTyped
                          simp only
                          exact
                            (nextIteration.prepend bodyStorePreserved
                              bodyCellsPreserved).prepend conditionStorePreserved
                                conditionCellsPreserved
                      | breakLoop =>
                          simp only
                          exact ⟨bodyStore,
                            conditionStorePreserved.trans bodyStorePreserved,
                            conditionCellsPreserved.trans bodyCellsPreserved,
                            completedTyped, trivial⟩
                      | returned result =>
                          simp only
                          have returnedTyped : CompletionHasType program
                              returnType inLoop completed bodyStore
                              (.returned result) := by
                            cases result <;> exact completionTyped
                          exact ⟨bodyStore,
                            conditionStorePreserved.trans bodyStorePreserved,
                            conditionCellsPreserved.trans bodyCellsPreserved,
                            completedTyped, returnedTyped⟩
                  | trapped reason completed | exited reason completed =>
                      rw [bodyResult] at bodyOutcome
                      simp only
                      exact bodyOutcome.prepend conditionStorePreserved
                        conditionCellsPreserved
                  | outOfFuel =>
                      simp only
                      trivial
      | trapped reason next | exited reason next =>
          rw [conditionResult] at conditionOutcome
          rw [execStmt.eq_8]
          simp only [conditionResult]
          exact conditionOutcome
      | outOfFuel =>
          rw [execStmt.eq_8]
          simp only [conditionResult]
          trivial

theorem execForValues_has_runtime_type
    (fuel : Nat) (id : VarId)
    (stateTyped : RuntimeStateHasType program context state store)
    (valuesTyped : ValuesHaveTypes program values
      (List.replicate values.length elementType))
    (valuesBorrows : ValuesBorrowsValid program state store values)
    (bodyPreserved :
      ∀ (statementFuel : Nat) (intermediate : State)
        (intermediateStore : StoreTyping),
        statementFuel < fuel →
        RuntimeStateHasType program (context.bind id elementType) intermediate
          intermediateStore →
        RuntimeCompletionOutcomeHasType program returnType
          (context.bind id elementType) true intermediate intermediateStore
          (execStmt statementFuel program intermediate body)) :
    RuntimeCompletionOutcomeHasType program returnType context inLoop state store
      (execForValues fuel program state id values body) := by
  induction fuel generalizing state store values inLoop with
  | zero =>
      rw [execForValues.eq_1]
      trivial
  | succ fuel induction =>
      cases values with
      | nil =>
          rw [execForValues.eq_2]
          exact ⟨store, StoreExtends.refl store,
            InitializedCellsPreserved.refl state, stateTyped, trivial⟩
      | cons value values =>
          cases valuesTyped with
          | cons valueTyped tailTyped =>
              have valueBorrows := valuesBorrows.head
              have tailBorrows := valuesBorrows.tail
              have boundTyped := stateTyped.bindLocal id valueTyped valueBorrows
              have boundStorePreserved := StoreTyping.extends_extend store
                state.nextCell elementType stateTyped.typed.nextCell_store_none
              have boundCellsPreserved := bindLocal_preserves_initialized_cells
                stateTyped.typed.wellFormed id value
              have bodyOutcome := bodyPreserved fuel (state.bindLocal id value)
                (store.extend state.nextCell elementType)
                (Nat.lt_succ_self fuel) boundTyped
              cases bodyResult : execStmt fuel program (state.bindLocal id value)
                  body with
              | done completion completed =>
                  rw [bodyResult] at bodyOutcome
                  have restoredOutcome := bodyOutcome.restoreLocals stateTyped
                    boundStorePreserved boundCellsPreserved
                  simp only [restoreOutcomeLocals] at restoredOutcome
                  obtain ⟨bodyStore, bodyStorePreserved, bodyCellsPreserved,
                    completedTyped, completionTyped⟩ := restoredOutcome
                  rw [execForValues.eq_3]
                  simp only [bodyResult]
                  cases completion with
                  | next =>
                      have tailBorrowsAfter := tailBorrows.preserve
                        bodyStorePreserved bodyCellsPreserved completedTyped.typed
                      have tailOutcome := induction completedTyped tailTyped
                        tailBorrowsAfter
                        (bodyPreserved := fun statementFuel intermediate
                          intermediateStore statementFuelLt typed =>
                            bodyPreserved statementFuel intermediate
                              intermediateStore
                              (Nat.lt_trans statementFuelLt
                                (Nat.lt_succ_self fuel)) typed)
                        (inLoop := inLoop)
                      exact tailOutcome.prepend bodyStorePreserved
                        bodyCellsPreserved
                  | continueLoop =>
                      have tailBorrowsAfter := tailBorrows.preserve
                        bodyStorePreserved bodyCellsPreserved completedTyped.typed
                      have tailOutcome := induction completedTyped tailTyped
                        tailBorrowsAfter
                        (bodyPreserved := fun statementFuel intermediate
                          intermediateStore statementFuelLt typed =>
                            bodyPreserved statementFuel intermediate
                              intermediateStore
                              (Nat.lt_trans statementFuelLt
                                (Nat.lt_succ_self fuel)) typed)
                        (inLoop := inLoop)
                      exact tailOutcome.prepend bodyStorePreserved
                        bodyCellsPreserved
                  | breakLoop =>
                      exact ⟨bodyStore, bodyStorePreserved, bodyCellsPreserved,
                        completedTyped, trivial⟩
                  | returned result =>
                      have returnedTyped : CompletionHasType program returnType
                          inLoop (restoreLocals state completed) bodyStore
                          (.returned result) := by
                        cases result <;> exact completionTyped
                      exact ⟨bodyStore, bodyStorePreserved, bodyCellsPreserved,
                        completedTyped, returnedTyped⟩
              | trapped reason completed | exited reason completed =>
                  rw [bodyResult] at bodyOutcome
                  have restoredOutcome := bodyOutcome.restoreLocals stateTyped
                    boundStorePreserved boundCellsPreserved
                  rw [execForValues.eq_3]
                  simp only [bodyResult]
                  exact restoredOutcome
              | outOfFuel =>
                  rw [execForValues.eq_3]
                  simp only [bodyResult]
                  trivial

theorem execForRange_has_runtime_type
    (fuel : Nat) (id : VarId)
    (stateTyped : RuntimeStateHasType program context state store)
    (currentTyped : ValueHasType program (.signed .i32 current)
      (.scalar (.signed .i32)))
    (bodyPreserved :
      ∀ (statementFuel : Nat) (intermediate : State)
        (intermediateStore : StoreTyping),
        statementFuel < fuel →
        RuntimeStateHasType program
          (context.bind id (.scalar (.signed .i32))) intermediate
          intermediateStore →
        RuntimeCompletionOutcomeHasType program returnType
          (context.bind id (.scalar (.signed .i32))) true intermediate
          intermediateStore
          (execStmt statementFuel program intermediate body)) :
    RuntimeCompletionOutcomeHasType program returnType context inLoop state store
      (execForRange fuel program state id current stop inclusive body) := by
  induction fuel generalizing state store current inLoop with
  | zero =>
      rw [execForRange]
      trivial
  | succ fuel induction =>
      let running : Outcome Completion :=
        match execStmt fuel program
            (state.bindLocal id (.signed .i32 current)) body with
        | .done .next completed
        | .done .continueLoop completed =>
            let unbound := restoreLocals state completed
            if inclusive && stop == some current then
              .done .next unbound
            else
              let next := wrapSigned program.target .i32 (current + 1)
              execForRange fuel program unbound id next stop inclusive body
        | .done .breakLoop completed =>
            .done .next (restoreLocals state completed)
        | .done returned@(.returned _) completed =>
            .done returned (restoreLocals state completed)
        | .trapped reason completed =>
            .trapped reason (restoreLocals state completed)
        | .exited code completed =>
            .exited code (restoreLocals state completed)
        | .outOfFuel => .outOfFuel
      have runningTyped : RuntimeCompletionOutcomeHasType program returnType
          context inLoop state store running := by
        have currentBorrows : BorrowsValid program state store
            (.signed .i32 current) :=
          (Lanius.Properties.ValueHasType.scalar_is_closed
            currentTyped).borrowsValid
        have boundTyped := stateTyped.bindLocal id currentTyped currentBorrows
        have boundStorePreserved := StoreTyping.extends_extend store
          state.nextCell (.scalar (.signed .i32))
          stateTyped.typed.nextCell_store_none
        have boundCellsPreserved := bindLocal_preserves_initialized_cells
          stateTyped.typed.wellFormed id (.signed .i32 current)
        have bodyOutcome := bodyPreserved fuel
          (state.bindLocal id (.signed .i32 current))
          (store.extend state.nextCell (.scalar (.signed .i32)))
          (Nat.lt_succ_self fuel) boundTyped
        cases bodyResult : execStmt fuel program
            (state.bindLocal id (.signed .i32 current)) body with
        | done completion completed =>
            rw [bodyResult] at bodyOutcome
            have restoredOutcome := bodyOutcome.restoreLocals stateTyped
              boundStorePreserved boundCellsPreserved
            simp only [restoreOutcomeLocals] at restoredOutcome
            obtain ⟨bodyStore, bodyStorePreserved, bodyCellsPreserved,
              completedTyped, completionTyped⟩ := restoredOutcome
            cases completion with
            | next =>
                simp only [running, bodyResult]
                split
                next reachedInclusiveEnd =>
                  exact ⟨bodyStore, bodyStorePreserved,
                    bodyCellsPreserved, completedTyped, trivial⟩
                next continueRange =>
                  have nextTyped : ValueHasType program
                      (.signed .i32
                        (wrapSigned program.target .i32 (current + 1)))
                      (.scalar (.signed .i32)) :=
                    .signed .i32 _
                      (wrapSigned_in_range program.target .i32 _).1
                      (wrapSigned_in_range program.target .i32 _).2
                  have nextOutcome := induction completedTyped nextTyped
                    (bodyPreserved := fun statementFuel intermediate
                      intermediateStore statementFuelLt typed =>
                        bodyPreserved statementFuel intermediate
                          intermediateStore
                          (Nat.lt_trans statementFuelLt
                            (Nat.lt_succ_self fuel)) typed)
                    (inLoop := inLoop)
                  exact nextOutcome.prepend bodyStorePreserved
                    bodyCellsPreserved
            | continueLoop =>
                simp only [running, bodyResult]
                split
                next reachedInclusiveEnd =>
                  exact ⟨bodyStore, bodyStorePreserved,
                    bodyCellsPreserved, completedTyped, trivial⟩
                next continueRange =>
                  have nextTyped : ValueHasType program
                      (.signed .i32
                        (wrapSigned program.target .i32 (current + 1)))
                      (.scalar (.signed .i32)) :=
                    .signed .i32 _
                      (wrapSigned_in_range program.target .i32 _).1
                      (wrapSigned_in_range program.target .i32 _).2
                  have nextOutcome := induction completedTyped nextTyped
                    (bodyPreserved := fun statementFuel intermediate
                      intermediateStore statementFuelLt typed =>
                        bodyPreserved statementFuel intermediate
                          intermediateStore
                          (Nat.lt_trans statementFuelLt
                            (Nat.lt_succ_self fuel)) typed)
                    (inLoop := inLoop)
                  exact nextOutcome.prepend bodyStorePreserved
                    bodyCellsPreserved
            | breakLoop =>
                simp only [running, bodyResult]
                exact ⟨bodyStore, bodyStorePreserved, bodyCellsPreserved,
                  completedTyped, trivial⟩
            | returned result =>
                simp only [running, bodyResult]
                have returnedTyped : CompletionHasType program returnType
                    inLoop (restoreLocals state completed) bodyStore
                    (.returned result) := by
                  cases result <;> exact completionTyped
                exact ⟨bodyStore, bodyStorePreserved, bodyCellsPreserved,
                  completedTyped, returnedTyped⟩
        | trapped reason completed | exited reason completed =>
            rw [bodyResult] at bodyOutcome
            have restoredOutcome := bodyOutcome.restoreLocals stateTyped
              boundStorePreserved boundCellsPreserved
            simp only [running, bodyResult]
            exact restoredOutcome
        | outOfFuel =>
            simp only [running, bodyResult]
            trivial
      cases stop with
      | none =>
          rw [execForRange]
          simp only [Bool.false_eq_true, if_false]
          change RuntimeCompletionOutcomeHasType program returnType context
            inLoop state store running
          exact runningTyped
      | some bound =>
          rw [execForRange]
          by_cases finished : rangeFinished current (some bound) inclusive = true
          · simp only [finished, if_true]
            exact ⟨store, StoreExtends.refl store,
              InitializedCellsPreserved.refl state, stateTyped, trivial⟩
          · simp only [finished]
            change RuntimeCompletionOutcomeHasType program returnType context
              inLoop state store running
            exact runningTyped

theorem execForArray_has_runtime_type
    (fuel : Nat) (id : VarId)
    (iterablePreserved : RuntimeValueOutcomeHasExtendedType program context
      state store (evalExpr fuel program state iterable)
      (.array elementType length))
    (bodyPreserved :
      ∀ (statementFuel : Nat) (intermediate : State)
        (intermediateStore : StoreTyping),
        statementFuel < fuel →
        RuntimeStateHasType program (context.bind id elementType) intermediate
          intermediateStore →
        RuntimeCompletionOutcomeHasType program returnType
          (context.bind id elementType) true intermediate intermediateStore
          (execStmt statementFuel program intermediate body)) :
    RuntimeCompletionOutcomeHasType program returnType context inLoop state store
      (execStmt (fuel + 1) program state (.forValues id iterable body)) := by
  cases iterableResult : evalExpr fuel program state iterable with
  | done value next =>
      rw [iterableResult] at iterablePreserved
      obtain ⟨afterStore, storePreserved, cellsPreserved, nextTyped,
        valueTyped, valueBorrows⟩ := iterablePreserved
      cases valueTyped with
      | array values valueElementType valueLength elementsTyped =>
          have homogeneous : ValuesHaveTypes program values
              (List.replicate values.length elementType) := by
            simpa [valueLength] using elementsTyped
          have elementsBorrows := valueBorrows.array_values
          have loopOutcome := execForValues_has_runtime_type fuel id nextTyped
            homogeneous elementsBorrows bodyPreserved (inLoop := inLoop)
          simpa only [execStmt.eq_9, iterableResult] using
            loopOutcome.prepend storePreserved cellsPreserved
  | trapped reason next | exited reason next =>
      rw [iterableResult] at iterablePreserved
      simpa only [execStmt.eq_9, iterableResult,
        RuntimeValueOutcomeHasExtendedType,
        RuntimeCompletionOutcomeHasType] using iterablePreserved
  | outOfFuel =>
      simp [execStmt.eq_9, iterableResult, RuntimeCompletionOutcomeHasType]

theorem execForSlice_has_runtime_type
    (fuel : Nat) (id : VarId)
    (iterablePreserved : RuntimeValueOutcomeHasExtendedType program context
      state store (evalExpr fuel program state iterable) (.slice elementType))
    (bodyPreserved :
      ∀ (statementFuel : Nat) (intermediate : State)
        (intermediateStore : StoreTyping),
        statementFuel < fuel →
        RuntimeStateHasType program (context.bind id elementType) intermediate
          intermediateStore →
        RuntimeCompletionOutcomeHasType program returnType
          (context.bind id elementType) true intermediate intermediateStore
          (execStmt statementFuel program intermediate body)) :
    RuntimeCompletionOutcomeHasType program returnType context inLoop state store
      (execStmt (fuel + 1) program state (.forValues id iterable body)) := by
  cases iterableResult : evalExpr fuel program state iterable with
  | done value next =>
      rw [iterableResult] at iterablePreserved
      obtain ⟨afterStore, storePreserved, cellsPreserved, nextTyped,
        valueTyped, valueBorrows⟩ := iterablePreserved
      cases valueTyped with
      | slice valueElementType cell projections start length =>
          have sliceValid : BorrowValid program next afterStore
              (.slice elementType cell projections start length) :=
            valueBorrows _ (by simp [Lanius.Properties.valueBorrows])
          cases sliced : sliceValues next cell projections start length with
          | error reason =>
              simp only [execStmt.eq_9, iterableResult, sliced]
              exact ⟨afterStore, storePreserved, cellsPreserved, nextTyped⟩
          | ok values =>
              have valuesTyped := sliceValues_have_types sliceValid sliced
              have valuesBorrows := sliceValues_borrows_valid nextTyped.typed
                sliceValid sliced
              have loopOutcome := execForValues_has_runtime_type fuel id nextTyped
                valuesTyped valuesBorrows bodyPreserved (inLoop := inLoop)
              simpa only [execStmt.eq_9, iterableResult, sliced] using
                loopOutcome.prepend storePreserved cellsPreserved
  | trapped reason next | exited reason next =>
      rw [iterableResult] at iterablePreserved
      simpa only [execStmt.eq_9, iterableResult,
        RuntimeValueOutcomeHasExtendedType,
        RuntimeCompletionOutcomeHasType] using iterablePreserved
  | outOfFuel =>
      simp [execStmt.eq_9, iterableResult, RuntimeCompletionOutcomeHasType]

theorem execSkip_has_type
    (fuel : Nat)
    (stateTyped : StateHasType program context state store) :
    CompletionOutcomeHasType program returnType context inLoop state store
      (execStmt (fuel + 1) program state .skip) := by
  exact ⟨store, StoreExtends.refl store,
    InitializedCellsPreserved.refl state, stateTyped, trivial⟩

theorem execExpression_has_type
    (fuel : Nat)
    (expressionPreserved : ValueOutcomeHasType program context state store
      (evalExpr fuel program state expression) type) :
    CompletionOutcomeHasType program returnType context inLoop state store
      (execStmt (fuel + 1) program state (.expression expression)) := by
  cases expressionResult : evalExpr fuel program state expression with
  | done value next =>
      rw [expressionResult] at expressionPreserved
      obtain ⟨afterStore, storePreserved, cellsPreserved, nextTyped,
        valueTyped, valueBorrows⟩ := expressionPreserved
      simp only [execStmt, expressionResult]
      exact ⟨afterStore, storePreserved, cellsPreserved, nextTyped, trivial⟩
  | trapped reason next =>
      rw [expressionResult] at expressionPreserved
      simpa only [execStmt, expressionResult, ValueOutcomeHasType,
        CompletionOutcomeHasType] using expressionPreserved
  | exited code next =>
      rw [expressionResult] at expressionPreserved
      simpa only [execStmt, expressionResult, ValueOutcomeHasType,
        CompletionOutcomeHasType] using expressionPreserved
  | outOfFuel =>
      simp [execStmt, expressionResult, CompletionOutcomeHasType]

theorem execReturnUnit_has_type
    (fuel : Nat)
    (stateTyped : StateHasType program context state store)
    (isUnit : returnType = .unit) :
    CompletionOutcomeHasType program returnType context inLoop state store
      (execStmt (fuel + 1) program state (.returnValue none)) := by
  exact ⟨store, StoreExtends.refl store,
    InitializedCellsPreserved.refl state, stateTyped, isUnit⟩

theorem execReturnValue_has_type
    (fuel : Nat)
    (valuePreserved : ValueOutcomeHasType program context state store
      (evalExpr fuel program state expression) returnType) :
    CompletionOutcomeHasType program returnType context inLoop state store
      (execStmt (fuel + 1) program state
        (.returnValue (some expression))) := by
  cases valueResult : evalExpr fuel program state expression with
  | done value next =>
      rw [valueResult] at valuePreserved
      obtain ⟨afterStore, storePreserved, cellsPreserved, nextTyped,
        valueTyped, valueBorrows⟩ := valuePreserved
      simp only [execStmt, valueResult]
      exact ⟨afterStore, storePreserved, cellsPreserved, nextTyped,
        valueTyped, valueBorrows⟩
  | trapped reason next =>
      rw [valueResult] at valuePreserved
      simpa only [execStmt, valueResult, ValueOutcomeHasType,
        CompletionOutcomeHasType] using valuePreserved
  | exited code next =>
      rw [valueResult] at valuePreserved
      simpa only [execStmt, valueResult, ValueOutcomeHasType,
        CompletionOutcomeHasType] using valuePreserved
  | outOfFuel =>
      simp [execStmt, valueResult, CompletionOutcomeHasType]

theorem execBreak_has_type
    (fuel : Nat)
    (stateTyped : StateHasType program context state store) :
    CompletionOutcomeHasType program returnType context true state store
      (execStmt (fuel + 1) program state .breakLoop) := by
  exact ⟨store, StoreExtends.refl store,
    InitializedCellsPreserved.refl state, stateTyped, rfl⟩

theorem execContinue_has_type
    (fuel : Nat)
    (stateTyped : StateHasType program context state store) :
    CompletionOutcomeHasType program returnType context true state store
      (execStmt (fuel + 1) program state .continueLoop) := by
  exact ⟨store, StoreExtends.refl store,
    InitializedCellsPreserved.refl state, stateTyped, rfl⟩

theorem execSequence_has_type
    (fuel : Nat)
    (firstPreserved : CompletionOutcomeHasType program returnType context inLoop
      state store (execStmt fuel program state first))
    (secondPreserved :
      ∀ (intermediate : State) (intermediateStore : StoreTyping),
        StateHasType program context intermediate intermediateStore →
        CompletionOutcomeHasType program returnType context inLoop
          intermediate intermediateStore
          (execStmt fuel program intermediate second)) :
    CompletionOutcomeHasType program returnType context inLoop state store
      (execStmt (fuel + 1) program state (.sequence first second)) := by
  cases firstResult : execStmt fuel program state first with
  | done completion next =>
      rw [firstResult] at firstPreserved
      obtain ⟨afterStore, storePreserved, cellsPreserved, nextTyped,
        completionTyped⟩ := firstPreserved
      cases completion with
      | next =>
          have secondOutcome := secondPreserved next afterStore nextTyped
          simpa only [execStmt, firstResult] using
            secondOutcome.prepend storePreserved cellsPreserved
      | returned value =>
          simp only [execStmt, firstResult]
          exact ⟨afterStore, storePreserved, cellsPreserved, nextTyped,
            completionTyped⟩
      | breakLoop =>
          simp only [execStmt, firstResult]
          exact ⟨afterStore, storePreserved, cellsPreserved, nextTyped,
            completionTyped⟩
      | continueLoop =>
          simp only [execStmt, firstResult]
          exact ⟨afterStore, storePreserved, cellsPreserved, nextTyped,
            completionTyped⟩
  | trapped reason next =>
      rw [firstResult] at firstPreserved
      simpa only [execStmt, firstResult, CompletionOutcomeHasType] using
        firstPreserved
  | exited code next =>
      rw [firstResult] at firstPreserved
      simpa only [execStmt, firstResult, CompletionOutcomeHasType] using
        firstPreserved
  | outOfFuel =>
      simp [execStmt, firstResult, CompletionOutcomeHasType]

theorem execIfThenElse_has_type
    (fuel : Nat)
    (conditionPreserved : ValueOutcomeHasType program context state store
      (evalExpr fuel program state condition) (.scalar .bool))
    (thenPreserved :
      ∀ (intermediate : State) (intermediateStore : StoreTyping),
        StateHasType program context intermediate intermediateStore →
        CompletionOutcomeHasType program returnType context inLoop
          intermediate intermediateStore
          (execStmt fuel program intermediate thenBranch))
    (elsePreserved :
      ∀ (intermediate : State) (intermediateStore : StoreTyping),
        StateHasType program context intermediate intermediateStore →
        CompletionOutcomeHasType program returnType context inLoop
          intermediate intermediateStore
          (execStmt fuel program intermediate elseBranch)) :
    CompletionOutcomeHasType program returnType context inLoop state store
      (execStmt (fuel + 1) program state
        (.ifThenElse condition thenBranch elseBranch)) := by
  cases conditionResult : evalExpr fuel program state condition with
  | done value next =>
      rw [conditionResult] at conditionPreserved
      obtain ⟨afterStore, storePreserved, cellsPreserved, nextTyped,
        valueTyped, valueBorrows⟩ := conditionPreserved
      cases valueTyped with
      | boolean conditionValue =>
          cases conditionValue
          · have branchOutcome := elsePreserved next afterStore nextTyped
            simpa only [execStmt, conditionResult] using
              branchOutcome.prepend storePreserved cellsPreserved
          · have branchOutcome := thenPreserved next afterStore nextTyped
            simpa only [execStmt, conditionResult] using
              branchOutcome.prepend storePreserved cellsPreserved
  | trapped reason next =>
      rw [conditionResult] at conditionPreserved
      simpa only [execStmt, conditionResult, ValueOutcomeHasType,
        CompletionOutcomeHasType] using conditionPreserved
  | exited code next =>
      rw [conditionResult] at conditionPreserved
      simpa only [execStmt, conditionResult, ValueOutcomeHasType,
        CompletionOutcomeHasType] using conditionPreserved
  | outOfFuel =>
      simp [execStmt, conditionResult, CompletionOutcomeHasType]

theorem execLetLocal_has_type
    (fuel : Nat) (id : VarId)
    (initializerPreserved : ValueOutcomeHasType program context state store
      (evalExpr fuel program state initializer) type)
    (bodyPreserved :
      ∀ (intermediate : State) (intermediateStore : StoreTyping),
        StateHasType program (context.bind id type) intermediate
          intermediateStore →
        CompletionOutcomeHasType program returnType (context.bind id type)
          inLoop intermediate intermediateStore
          (execStmt fuel program intermediate body)) :
    CompletionOutcomeHasType program returnType context inLoop state store
      (execStmt (fuel + 1) program state
        (.letLocal id type initializer body)) := by
  cases initializerResult : evalExpr fuel program state initializer with
  | done value next =>
      rw [initializerResult] at initializerPreserved
      obtain ⟨afterStore, storePreserved, cellsPreserved, nextTyped,
        valueTyped, valueBorrows⟩ := initializerPreserved
      have boundTyped := nextTyped.bindLocal id valueTyped valueBorrows
      have boundStorePreserved := StoreTyping.extends_extend afterStore
        next.nextCell type nextTyped.nextCell_store_none
      have boundCellsPreserved := bindLocal_preserves_initialized_cells
        nextTyped.wellFormed id value
      have bodyOutcome := bodyPreserved (next.bindLocal id value)
        (afterStore.extend next.nextCell type) boundTyped
      have restored := bodyOutcome.restoreLocals nextTyped boundStorePreserved
        boundCellsPreserved
      simpa only [execStmt, initializerResult] using
        restored.prepend storePreserved cellsPreserved
  | trapped reason next =>
      rw [initializerResult] at initializerPreserved
      simpa only [execStmt, initializerResult, ValueOutcomeHasType,
        CompletionOutcomeHasType] using initializerPreserved
  | exited code next =>
      rw [initializerResult] at initializerPreserved
      simpa only [execStmt, initializerResult, ValueOutcomeHasType,
        CompletionOutcomeHasType] using initializerPreserved
  | outOfFuel =>
      simp [execStmt, initializerResult, CompletionOutcomeHasType]

theorem execLetUninitialized_has_type
    (fuel : Nat) (id : VarId)
    (stateTyped : StateHasType program context state store)
    (bodyPreserved :
      ∀ (intermediate : State) (intermediateStore : StoreTyping),
        StateHasType program (context.bind id type) intermediate
          intermediateStore →
        CompletionOutcomeHasType program returnType (context.bind id type)
          inLoop intermediate intermediateStore
          (execStmt fuel program intermediate body)) :
    CompletionOutcomeHasType program returnType context inLoop state store
      (execStmt (fuel + 1) program state
        (.letUninitialized id type body)) := by
  have boundTyped := stateTyped.bindUninitialized id type
  have storePreserved := StoreTyping.extends_extend store state.nextCell type
    stateTyped.nextCell_store_none
  have cellsPreserved := bindUninitialized_preserves_initialized_cells
    stateTyped.wellFormed id
  have bodyOutcome := bodyPreserved (state.bindUninitialized id)
    (store.extend state.nextCell type) boundTyped
  simpa only [execStmt] using
    bodyOutcome.restoreLocals stateTyped storePreserved cellsPreserved

theorem execWhileLoop_has_type
    (fuel : Nat)
    (stateTyped : StateHasType program context state store)
    (conditionPreserved :
      ∀ (expressionFuel : Nat) (intermediate : State)
        (intermediateStore : StoreTyping),
        StateHasType program context intermediate intermediateStore →
        ValueOutcomeHasType program context intermediate intermediateStore
          (evalExpr expressionFuel program intermediate condition)
          (.scalar .bool))
    (bodyPreserved :
      ∀ (statementFuel : Nat) (intermediate : State)
        (intermediateStore : StoreTyping),
        StateHasType program context intermediate intermediateStore →
        CompletionOutcomeHasType program returnType context true
          intermediate intermediateStore
          (execStmt statementFuel program intermediate body)) :
    CompletionOutcomeHasType program returnType context inLoop state store
      (execStmt (fuel + 1) program state (.whileLoop condition body)) := by
  induction fuel generalizing inLoop state store with
  | zero =>
      rw [execStmt.eq_8]
      rw [evalExpr.eq_1]
      simp only
      trivial
  | succ fuel induction =>
      have conditionOutcome := conditionPreserved (fuel + 1) state store stateTyped
      cases conditionResult : evalExpr (fuel + 1) program state condition with
      | done value afterCondition =>
          rw [conditionResult] at conditionOutcome
          obtain ⟨conditionStore, conditionStorePreserved,
            conditionCellsPreserved, afterConditionTyped, valueTyped,
            valueBorrows⟩ := conditionOutcome
          cases valueTyped with
          | boolean conditionValue =>
              cases conditionValue with
              | false =>
                  rw [execStmt.eq_8]
                  simp only [conditionResult]
                  exact ⟨conditionStore, conditionStorePreserved,
                    conditionCellsPreserved, afterConditionTyped, trivial⟩
              | true =>
                  rw [execStmt.eq_8]
                  simp only [conditionResult]
                  have bodyOutcome := bodyPreserved (fuel + 1) afterCondition
                    conditionStore afterConditionTyped
                  cases bodyResult : execStmt (fuel + 1) program afterCondition body with
                  | done completion completed =>
                      rw [bodyResult] at bodyOutcome
                      obtain ⟨bodyStore, bodyStorePreserved, bodyCellsPreserved,
                        completedTyped, completionTyped⟩ := bodyOutcome
                      cases completion with
                      | next =>
                          have nextIteration := induction
                            (inLoop := inLoop) completedTyped
                          simp only
                          exact
                            (nextIteration.prepend bodyStorePreserved
                              bodyCellsPreserved).prepend conditionStorePreserved
                                conditionCellsPreserved
                      | continueLoop =>
                          have nextIteration := induction
                            (inLoop := inLoop) completedTyped
                          simp only
                          exact
                            (nextIteration.prepend bodyStorePreserved
                              bodyCellsPreserved).prepend conditionStorePreserved
                                conditionCellsPreserved
                      | breakLoop =>
                          simp only
                          exact ⟨bodyStore,
                            conditionStorePreserved.trans bodyStorePreserved,
                            conditionCellsPreserved.trans bodyCellsPreserved,
                            completedTyped, trivial⟩
                      | returned result =>
                          simp only
                          have returnedTyped : CompletionHasType program
                              returnType inLoop completed bodyStore
                              (.returned result) := by
                            cases result <;> exact completionTyped
                          exact ⟨bodyStore,
                            conditionStorePreserved.trans bodyStorePreserved,
                            conditionCellsPreserved.trans bodyCellsPreserved,
                            completedTyped, returnedTyped⟩
                  | trapped reason completed =>
                      rw [bodyResult] at bodyOutcome
                      simp only
                      exact bodyOutcome.prepend conditionStorePreserved
                        conditionCellsPreserved
                  | exited code completed =>
                      rw [bodyResult] at bodyOutcome
                      simp only
                      exact bodyOutcome.prepend conditionStorePreserved
                        conditionCellsPreserved
                  | outOfFuel =>
                      simp only
                      trivial
      | trapped reason next =>
          rw [conditionResult] at conditionOutcome
          rw [execStmt.eq_8]
          simp only [conditionResult]
          exact conditionOutcome
      | exited code next =>
          rw [conditionResult] at conditionOutcome
          rw [execStmt.eq_8]
          simp only [conditionResult]
          exact conditionOutcome
      | outOfFuel =>
          rw [execStmt.eq_8]
          simp only [conditionResult]
          trivial

theorem execForValues_has_type
    (fuel : Nat) (id : VarId)
    (stateTyped : StateHasType program context state store)
    (valuesTyped : ValuesHaveTypes program values
      (List.replicate values.length elementType))
    (valuesBorrows : ValuesBorrowsValid program state store values)
    (bodyPreserved :
      ∀ (statementFuel : Nat) (intermediate : State)
        (intermediateStore : StoreTyping),
        StateHasType program (context.bind id elementType) intermediate
          intermediateStore →
        CompletionOutcomeHasType program returnType
          (context.bind id elementType) true intermediate intermediateStore
          (execStmt statementFuel program intermediate body)) :
    CompletionOutcomeHasType program returnType context inLoop state store
      (execForValues fuel program state id values body) := by
  induction fuel generalizing state store values inLoop with
  | zero =>
      rw [execForValues.eq_1]
      trivial
  | succ fuel induction =>
      cases values with
      | nil =>
          rw [execForValues.eq_2]
          exact ⟨store, StoreExtends.refl store,
            InitializedCellsPreserved.refl state, stateTyped, trivial⟩
      | cons value values =>
          cases valuesTyped with
          | cons valueTyped tailTyped =>
              have valueBorrows := valuesBorrows.head
              have tailBorrows := valuesBorrows.tail
              have boundTyped := stateTyped.bindLocal id valueTyped valueBorrows
              have boundStorePreserved := StoreTyping.extends_extend store
                state.nextCell elementType stateTyped.nextCell_store_none
              have boundCellsPreserved := bindLocal_preserves_initialized_cells
                stateTyped.wellFormed id value
              have bodyOutcome := bodyPreserved fuel (state.bindLocal id value)
                (store.extend state.nextCell elementType) boundTyped
              cases bodyResult : execStmt fuel program (state.bindLocal id value)
                  body with
              | done completion completed =>
                  rw [bodyResult] at bodyOutcome
                  have restoredOutcome := bodyOutcome.restoreLocals stateTyped
                    boundStorePreserved boundCellsPreserved
                  simp only [restoreOutcomeLocals] at restoredOutcome
                  obtain ⟨bodyStore, bodyStorePreserved, bodyCellsPreserved,
                    completedTyped, completionTyped⟩ := restoredOutcome
                  rw [execForValues.eq_3]
                  simp only [bodyResult]
                  cases completion with
                  | next =>
                      have tailBorrowsAfter := tailBorrows.preserve
                        bodyStorePreserved bodyCellsPreserved completedTyped
                      have tailOutcome := induction completedTyped tailTyped
                        tailBorrowsAfter (inLoop := inLoop)
                      exact tailOutcome.prepend bodyStorePreserved
                        bodyCellsPreserved
                  | continueLoop =>
                      have tailBorrowsAfter := tailBorrows.preserve
                        bodyStorePreserved bodyCellsPreserved completedTyped
                      have tailOutcome := induction completedTyped tailTyped
                        tailBorrowsAfter (inLoop := inLoop)
                      exact tailOutcome.prepend bodyStorePreserved
                        bodyCellsPreserved
                  | breakLoop =>
                      exact ⟨bodyStore, bodyStorePreserved, bodyCellsPreserved,
                        completedTyped, trivial⟩
                  | returned result =>
                      have returnedTyped : CompletionHasType program returnType
                          inLoop (restoreLocals state completed) bodyStore
                          (.returned result) := by
                        cases result <;> exact completionTyped
                      exact ⟨bodyStore, bodyStorePreserved, bodyCellsPreserved,
                        completedTyped, returnedTyped⟩
              | trapped reason completed =>
                  rw [bodyResult] at bodyOutcome
                  have restoredOutcome := bodyOutcome.restoreLocals stateTyped
                    boundStorePreserved boundCellsPreserved
                  rw [execForValues.eq_3]
                  simp only [bodyResult]
                  exact restoredOutcome
              | exited code completed =>
                  rw [bodyResult] at bodyOutcome
                  have restoredOutcome := bodyOutcome.restoreLocals stateTyped
                    boundStorePreserved boundCellsPreserved
                  rw [execForValues.eq_3]
                  simp only [bodyResult]
                  exact restoredOutcome
              | outOfFuel =>
                  rw [execForValues.eq_3]
                  simp only [bodyResult]
                  trivial

theorem execForRange_has_type
    (fuel : Nat) (id : VarId)
    (stateTyped : StateHasType program context state store)
    (currentTyped : ValueHasType program (.signed .i32 current)
      (.scalar (.signed .i32)))
    (bodyPreserved :
      ∀ (statementFuel : Nat) (intermediate : State)
        (intermediateStore : StoreTyping),
        StateHasType program
          (context.bind id (.scalar (.signed .i32))) intermediate
          intermediateStore →
        CompletionOutcomeHasType program returnType
          (context.bind id (.scalar (.signed .i32))) true intermediate
          intermediateStore
          (execStmt statementFuel program intermediate body)) :
    CompletionOutcomeHasType program returnType context inLoop state store
      (execForRange fuel program state id current stop inclusive body) := by
  induction fuel generalizing state store current inLoop with
  | zero =>
      rw [execForRange]
      trivial
  | succ fuel induction =>
      let running : Outcome Completion :=
        match execStmt fuel program
            (state.bindLocal id (.signed .i32 current)) body with
        | .done .next completed
        | .done .continueLoop completed =>
            let unbound := restoreLocals state completed
            if inclusive && stop == some current then
              .done .next unbound
            else
              let next := wrapSigned program.target .i32 (current + 1)
              execForRange fuel program unbound id next stop inclusive body
        | .done .breakLoop completed =>
            .done .next (restoreLocals state completed)
        | .done returned@(.returned _) completed =>
            .done returned (restoreLocals state completed)
        | .trapped reason completed =>
            .trapped reason (restoreLocals state completed)
        | .exited code completed =>
            .exited code (restoreLocals state completed)
        | .outOfFuel => .outOfFuel
      have runningTyped : CompletionOutcomeHasType program returnType context
          inLoop state store running := by
        have currentBorrows : BorrowsValid program state store
            (.signed .i32 current) :=
          (Lanius.Properties.ValueHasType.scalar_is_closed
            currentTyped).borrowsValid
        have boundTyped := stateTyped.bindLocal id currentTyped currentBorrows
        have boundStorePreserved := StoreTyping.extends_extend store
          state.nextCell (.scalar (.signed .i32))
          stateTyped.nextCell_store_none
        have boundCellsPreserved := bindLocal_preserves_initialized_cells
          stateTyped.wellFormed id (.signed .i32 current)
        have bodyOutcome := bodyPreserved fuel
          (state.bindLocal id (.signed .i32 current))
          (store.extend state.nextCell (.scalar (.signed .i32))) boundTyped
        cases bodyResult : execStmt fuel program
            (state.bindLocal id (.signed .i32 current)) body with
        | done completion completed =>
            rw [bodyResult] at bodyOutcome
            have restoredOutcome := bodyOutcome.restoreLocals stateTyped
              boundStorePreserved boundCellsPreserved
            simp only [restoreOutcomeLocals] at restoredOutcome
            obtain ⟨bodyStore, bodyStorePreserved, bodyCellsPreserved,
              completedTyped, completionTyped⟩ := restoredOutcome
            cases completion with
            | next =>
                simp only [running, bodyResult]
                split
                next reachedInclusiveEnd =>
                  exact ⟨bodyStore, bodyStorePreserved,
                    bodyCellsPreserved, completedTyped, trivial⟩
                next continueRange =>
                  have nextTyped : ValueHasType program
                      (.signed .i32
                        (wrapSigned program.target .i32 (current + 1)))
                      (.scalar (.signed .i32)) :=
                    .signed .i32 _
                      (wrapSigned_in_range program.target .i32 _).1
                      (wrapSigned_in_range program.target .i32 _).2
                  have nextOutcome := induction completedTyped nextTyped
                    (inLoop := inLoop)
                  exact nextOutcome.prepend bodyStorePreserved
                    bodyCellsPreserved
            | continueLoop =>
                simp only [running, bodyResult]
                split
                next reachedInclusiveEnd =>
                  exact ⟨bodyStore, bodyStorePreserved,
                    bodyCellsPreserved, completedTyped, trivial⟩
                next continueRange =>
                  have nextTyped : ValueHasType program
                      (.signed .i32
                        (wrapSigned program.target .i32 (current + 1)))
                      (.scalar (.signed .i32)) :=
                    .signed .i32 _
                      (wrapSigned_in_range program.target .i32 _).1
                      (wrapSigned_in_range program.target .i32 _).2
                  have nextOutcome := induction completedTyped nextTyped
                    (inLoop := inLoop)
                  exact nextOutcome.prepend bodyStorePreserved
                    bodyCellsPreserved
            | breakLoop =>
                simp only [running, bodyResult]
                exact ⟨bodyStore, bodyStorePreserved, bodyCellsPreserved,
                  completedTyped, trivial⟩
            | returned result =>
                simp only [running, bodyResult]
                have returnedTyped : CompletionHasType program returnType
                    inLoop (restoreLocals state completed) bodyStore
                    (.returned result) := by
                  cases result <;> exact completionTyped
                exact ⟨bodyStore, bodyStorePreserved, bodyCellsPreserved,
                  completedTyped, returnedTyped⟩
        | trapped reason completed =>
            rw [bodyResult] at bodyOutcome
            have restoredOutcome := bodyOutcome.restoreLocals stateTyped
              boundStorePreserved boundCellsPreserved
            simp only [running, bodyResult]
            exact restoredOutcome
        | exited code completed =>
            rw [bodyResult] at bodyOutcome
            have restoredOutcome := bodyOutcome.restoreLocals stateTyped
              boundStorePreserved boundCellsPreserved
            simp only [running, bodyResult]
            exact restoredOutcome
        | outOfFuel =>
            simp only [running, bodyResult]
            trivial
      cases stop with
      | none =>
          rw [execForRange]
          simp only [Bool.false_eq_true, if_false]
          change CompletionOutcomeHasType program returnType context inLoop
            state store running
          exact runningTyped
      | some bound =>
          rw [execForRange]
          by_cases finished : rangeFinished current (some bound) inclusive = true
          · simp only [finished, if_true]
            exact ⟨store, StoreExtends.refl store,
              InitializedCellsPreserved.refl state, stateTyped, trivial⟩
          · simp only [finished]
            change CompletionOutcomeHasType program returnType context inLoop
              state store running
            exact runningTyped

theorem execStmt_zero_has_type
    (_stateTyped : StateHasType program context state store) :
    CompletionOutcomeHasType program returnType context inLoop state store
      (execStmt 0 program state statement) := by
  rw [execStmt.eq_1]
  trivial

theorem execStmt_has_type
    (expressionsPreserve : ExpressionsPreserveTypes program)
    (statementTyped : StmtHasType program returnType context inLoop statement)
    (fuel : Nat)
    (stateTyped : StateHasType program context state store) :
    CompletionOutcomeHasType program returnType context inLoop state store
      (execStmt fuel program state statement) := by
  induction statementTyped generalizing fuel state store with
  | skip =>
      cases fuel with
      | zero => exact execStmt_zero_has_type stateTyped
      | succ fuel => exact execSkip_has_type fuel stateTyped
  | expression expressionTyped =>
      cases fuel with
      | zero => exact execStmt_zero_has_type stateTyped
      | succ fuel =>
          exact execExpression_has_type fuel
            (expressionsPreserve fuel _ _ _ _ _ stateTyped expressionTyped)
  | sequence firstTyped secondTyped firstInduction secondInduction =>
      cases fuel with
      | zero => exact execStmt_zero_has_type stateTyped
      | succ fuel =>
          exact execSequence_has_type fuel
            (firstInduction fuel stateTyped)
            (fun intermediate intermediateStore intermediateTyped =>
              secondInduction fuel intermediateTyped)
  | letLocal initializerTyped bodyTyped bodyInduction =>
      cases fuel with
      | zero => exact execStmt_zero_has_type stateTyped
      | succ fuel =>
          exact execLetLocal_has_type fuel _
            (expressionsPreserve fuel _ _ _ _ _ stateTyped initializerTyped)
            (fun intermediate intermediateStore intermediateTyped =>
              bodyInduction fuel intermediateTyped)
  | letUninitialized bodyTyped bodyInduction =>
      cases fuel with
      | zero => exact execStmt_zero_has_type stateTyped
      | succ fuel =>
          exact execLetUninitialized_has_type fuel _ stateTyped
            (fun intermediate intermediateStore intermediateTyped =>
              bodyInduction fuel intermediateTyped)
  | ifThenElse conditionTyped thenTyped elseTyped thenInduction elseInduction =>
      cases fuel with
      | zero => exact execStmt_zero_has_type stateTyped
      | succ fuel =>
          exact execIfThenElse_has_type fuel
            (expressionsPreserve fuel _ _ _ _ _ stateTyped conditionTyped)
            (fun intermediate intermediateStore intermediateTyped =>
              thenInduction fuel intermediateTyped)
            (fun intermediate intermediateStore intermediateTyped =>
              elseInduction fuel intermediateTyped)
  | whileLoop conditionTyped bodyTyped bodyInduction =>
      cases fuel with
      | zero => exact execStmt_zero_has_type stateTyped
      | succ fuel =>
          exact execWhileLoop_has_type fuel stateTyped
            (fun expressionFuel intermediate intermediateStore
                intermediateTyped =>
              expressionsPreserve expressionFuel _ _ _ _ _ intermediateTyped
                conditionTyped)
            (fun statementFuel intermediate intermediateStore
                intermediateTyped =>
              bodyInduction statementFuel intermediateTyped)
  | forArray iterableTyped bodyTyped bodyInduction =>
      rename_i context' iterableExpr elementType length localId bodyStmt inLoop'
      cases fuel with
      | zero => exact execStmt_zero_has_type stateTyped
      | succ fuel =>
          have iterableOutcome := expressionsPreserve fuel _ _ _ _ _
            stateTyped iterableTyped
          cases iterableResult : evalExpr fuel program state iterableExpr with
          | done value next =>
              rw [iterableResult] at iterableOutcome
              obtain ⟨afterStore, storePreserved, cellsPreserved, nextTyped,
                valueTyped, valueBorrows⟩ := iterableOutcome
              cases valueTyped with
              | array values elementType valueLength elementsTyped =>
                  have homogeneous : ValuesHaveTypes program values
                      (List.replicate values.length elementType) := by
                    simpa [valueLength] using elementsTyped
                  have elementsBorrows := valueBorrows.array_values
                  have loopOutcome := execForValues_has_type fuel localId
                    nextTyped homogeneous elementsBorrows
                    (fun statementFuel intermediate intermediateStore
                        intermediateTyped =>
                      bodyInduction statementFuel intermediateTyped)
                    (inLoop := inLoop')
                  simpa only [execStmt.eq_9, iterableResult] using
                    loopOutcome.prepend storePreserved cellsPreserved
          | trapped reason next =>
              rw [iterableResult] at iterableOutcome
              simpa only [execStmt.eq_9, iterableResult, ValueOutcomeHasType,
                CompletionOutcomeHasType] using iterableOutcome
          | exited code next =>
              rw [iterableResult] at iterableOutcome
              simpa only [execStmt.eq_9, iterableResult, ValueOutcomeHasType,
                CompletionOutcomeHasType] using iterableOutcome
          | outOfFuel =>
              simp [execStmt.eq_9, iterableResult, CompletionOutcomeHasType]
  | forSlice iterableTyped bodyTyped bodyInduction =>
      rename_i context' iterableExpr elementType localId bodyStmt inLoop'
      cases fuel with
      | zero => exact execStmt_zero_has_type stateTyped
      | succ fuel =>
          have iterableOutcome := expressionsPreserve fuel _ _ _ _ _
            stateTyped iterableTyped
          cases iterableResult : evalExpr fuel program state iterableExpr with
          | done value next =>
              rw [iterableResult] at iterableOutcome
              obtain ⟨afterStore, storePreserved, cellsPreserved, nextTyped,
                valueTyped, valueBorrows⟩ := iterableOutcome
              cases valueTyped with
              | slice elementType cell projections start length =>
                  have sliceValid : BorrowValid program next afterStore
                      (.slice elementType cell projections start length) :=
                    valueBorrows _ (by
                      simp [Lanius.Properties.valueBorrows])
                  cases sliced : sliceValues next cell projections start length with
                  | error reason =>
                      simp only [execStmt.eq_9, iterableResult, sliced]
                      exact ⟨afterStore, storePreserved, cellsPreserved,
                        nextTyped⟩
                  | ok values =>
                      have valuesTyped := sliceValues_have_types sliceValid sliced
                      have valuesBorrows := sliceValues_borrows_valid nextTyped
                        sliceValid sliced
                      have loopOutcome := execForValues_has_type fuel localId
                        nextTyped valuesTyped valuesBorrows
                        (fun statementFuel intermediate intermediateStore
                            intermediateTyped =>
                          bodyInduction statementFuel intermediateTyped)
                        (inLoop := inLoop')
                      simpa only [execStmt.eq_9, iterableResult, sliced] using
                        loopOutcome.prepend storePreserved cellsPreserved
          | trapped reason next =>
              rw [iterableResult] at iterableOutcome
              simpa only [execStmt.eq_9, iterableResult, ValueOutcomeHasType,
                CompletionOutcomeHasType] using iterableOutcome
          | exited code next =>
              rw [iterableResult] at iterableOutcome
              simpa only [execStmt.eq_9, iterableResult, ValueOutcomeHasType,
                CompletionOutcomeHasType] using iterableOutcome
          | outOfFuel =>
              simp [execStmt.eq_9, iterableResult, CompletionOutcomeHasType]
  | forRange startTyped stopTyped bodyTyped bodyInduction =>
      rename_i context' startExpr stopExpr localId bodyStmt inLoop' inclusive
      cases fuel with
      | zero => exact execStmt_zero_has_type stateTyped
      | succ fuel =>
          have startOutcome := expressionsPreserve fuel _ _ _ _ _ stateTyped
            startTyped
          cases startResult : evalExpr fuel program state startExpr with
          | done value afterStart =>
              rw [startResult] at startOutcome
              obtain ⟨startStore, startStorePreserved, startCellsPreserved,
                afterStartTyped, valueTyped, valueBorrows⟩ := startOutcome
              cases valueTyped with
              | signed type startValue lower upper =>
                  have typedStart : ValueHasType program (.signed .i32 startValue)
                      (.scalar (.signed .i32)) := .signed .i32 startValue lower upper
                  cases stopTyped with
                  | none =>
                      have rangeOutcome := execForRange_has_type fuel localId
                        afterStartTyped typedStart
                        (fun statementFuel intermediate intermediateStore
                            intermediateTyped =>
                          bodyInduction statementFuel intermediateTyped)
                        (inLoop := inLoop')
                        (stop := none) (inclusive := inclusive)
                      simpa only [execStmt.eq_10, startResult] using
                        rangeOutcome.prepend startStorePreserved
                          startCellsPreserved
                  | some typedStop =>
                      rename_i stopExpression
                      have stopOutcome := expressionsPreserve fuel _ _ _ _ _
                        afterStartTyped typedStop
                      cases stopResult : evalExpr fuel program afterStart
                          stopExpression with
                      | done stopValue afterStop =>
                          rw [stopResult] at stopOutcome
                          obtain ⟨stopStore, stopStorePreserved,
                            stopCellsPreserved, afterStopTyped, stopValueTyped,
                            stopValueBorrows⟩ := stopOutcome
                          cases stopValueTyped with
                          | signed type stopValue lower upper =>
                              have rangeOutcome := execForRange_has_type fuel
                                localId afterStopTyped typedStart
                                (fun statementFuel intermediate
                                    intermediateStore intermediateTyped =>
                                  bodyInduction statementFuel intermediateTyped)
                                (inLoop := inLoop')
                                (stop := some stopValue)
                                (inclusive := inclusive)
                              simpa only [execStmt.eq_10, startResult,
                                stopResult] using
                                (rangeOutcome.prepend stopStorePreserved
                                  stopCellsPreserved).prepend
                                    startStorePreserved startCellsPreserved
                      | trapped reason next =>
                          rw [stopResult] at stopOutcome
                          simpa only [execStmt.eq_10, startResult, stopResult,
                            ValueOutcomeHasType, CompletionOutcomeHasType] using
                            stopOutcome.prepend startStorePreserved
                              startCellsPreserved
                      | exited code next =>
                          rw [stopResult] at stopOutcome
                          simpa only [execStmt.eq_10, startResult, stopResult,
                            ValueOutcomeHasType, CompletionOutcomeHasType] using
                            stopOutcome.prepend startStorePreserved
                              startCellsPreserved
                      | outOfFuel =>
                          simp [execStmt.eq_10, startResult, stopResult,
                            CompletionOutcomeHasType]
          | trapped reason next =>
              rw [startResult] at startOutcome
              simpa only [execStmt.eq_10, startResult, ValueOutcomeHasType,
                CompletionOutcomeHasType] using startOutcome
          | exited code next =>
              rw [startResult] at startOutcome
              simpa only [execStmt.eq_10, startResult, ValueOutcomeHasType,
                CompletionOutcomeHasType] using startOutcome
          | outOfFuel =>
              simp [execStmt.eq_10, startResult, CompletionOutcomeHasType]
  | returnUnit isUnit =>
      cases fuel with
      | zero => exact execStmt_zero_has_type stateTyped
      | succ fuel => exact execReturnUnit_has_type fuel stateTyped isUnit
  | returnValue valueTyped =>
      cases fuel with
      | zero => exact execStmt_zero_has_type stateTyped
      | succ fuel =>
          exact execReturnValue_has_type fuel
            (expressionsPreserve fuel _ _ _ _ _ stateTyped valueTyped)
  | breakLoop =>
      cases fuel with
      | zero => exact execStmt_zero_has_type stateTyped
      | succ fuel => exact execBreak_has_type fuel stateTyped
  | continueLoop =>
      cases fuel with
      | zero => exact execStmt_zero_has_type stateTyped
      | succ fuel => exact execContinue_has_type fuel stateTyped

theorem execStmt_zero_has_runtime_type
    (_stateTyped : RuntimeStateHasType program context state store) :
    RuntimeCompletionOutcomeHasType program returnType context inLoop state
      store (execStmt 0 program state statement) := by
  rw [execStmt.eq_1]
  trivial

theorem execStmt_has_runtime_type_below
    (expressionsPreserve : RuntimeExpressionsPreserveTypesBelow program limit)
    (statementTyped : StmtHasType program returnType context inLoop statement)
    (fuel : Nat)
    (fuelLt : fuel < limit)
    (stateTyped : RuntimeStateHasType program context state store) :
    RuntimeCompletionOutcomeHasType program returnType context inLoop state store
      (execStmt fuel program state statement) := by
  induction statementTyped generalizing fuel state store with
  | skip =>
      cases fuel with
      | zero => exact execStmt_zero_has_runtime_type stateTyped
      | succ fuel => exact execSkip_has_runtime_type fuel stateTyped
  | expression expressionTyped =>
      cases fuel with
      | zero => exact execStmt_zero_has_runtime_type stateTyped
      | succ fuel =>
          have smaller := Nat.lt_trans (Nat.lt_succ_self fuel) fuelLt
          exact execExpression_has_runtime_type fuel
            (expressionsPreserve fuel smaller _ _ _ _ _ stateTyped
              expressionTyped)
  | sequence firstTyped secondTyped firstInduction secondInduction =>
      cases fuel with
      | zero => exact execStmt_zero_has_runtime_type stateTyped
      | succ fuel =>
          have smaller := Nat.lt_trans (Nat.lt_succ_self fuel) fuelLt
          exact execSequence_has_runtime_type fuel
            (firstInduction fuel smaller stateTyped)
            (fun intermediate intermediateStore intermediateTyped =>
              secondInduction fuel smaller intermediateTyped)
  | letLocal initializerTyped bodyTyped bodyInduction =>
      cases fuel with
      | zero => exact execStmt_zero_has_runtime_type stateTyped
      | succ fuel =>
          have smaller := Nat.lt_trans (Nat.lt_succ_self fuel) fuelLt
          exact execLetLocal_has_runtime_type fuel _
            (expressionsPreserve fuel smaller _ _ _ _ _ stateTyped
              initializerTyped)
            (fun intermediate intermediateStore intermediateTyped =>
              bodyInduction fuel smaller intermediateTyped)
  | letUninitialized bodyTyped bodyInduction =>
      cases fuel with
      | zero => exact execStmt_zero_has_runtime_type stateTyped
      | succ fuel =>
          have smaller := Nat.lt_trans (Nat.lt_succ_self fuel) fuelLt
          exact execLetUninitialized_has_runtime_type fuel _ stateTyped
            (fun intermediate intermediateStore intermediateTyped =>
              bodyInduction fuel smaller intermediateTyped)
  | ifThenElse conditionTyped thenTyped elseTyped thenInduction elseInduction =>
      cases fuel with
      | zero => exact execStmt_zero_has_runtime_type stateTyped
      | succ fuel =>
          have smaller := Nat.lt_trans (Nat.lt_succ_self fuel) fuelLt
          exact execIfThenElse_has_runtime_type fuel
            (expressionsPreserve fuel smaller _ _ _ _ _ stateTyped
              conditionTyped)
            (fun intermediate intermediateStore intermediateTyped =>
              thenInduction fuel smaller intermediateTyped)
            (fun intermediate intermediateStore intermediateTyped =>
              elseInduction fuel smaller intermediateTyped)
  | whileLoop conditionTyped bodyTyped bodyInduction =>
      cases fuel with
      | zero => exact execStmt_zero_has_runtime_type stateTyped
      | succ fuel =>
          have smaller := Nat.lt_trans (Nat.lt_succ_self fuel) fuelLt
          exact execWhileLoop_has_runtime_type fuel stateTyped
            (fun expressionFuel intermediate intermediateStore
                expressionFuelLe intermediateTyped =>
              expressionsPreserve expressionFuel
                (Nat.lt_of_le_of_lt expressionFuelLe smaller) _ _ _ _ _
                intermediateTyped conditionTyped)
            (fun statementFuel intermediate intermediateStore
                statementFuelLe intermediateTyped =>
              bodyInduction statementFuel
                (Nat.lt_of_le_of_lt statementFuelLe smaller)
                intermediateTyped)
  | forArray iterableTyped bodyTyped bodyInduction =>
      rename_i context' iterableExpr elementType length localId bodyStmt inLoop'
      cases fuel with
      | zero => exact execStmt_zero_has_runtime_type stateTyped
      | succ fuel =>
          have smaller := Nat.lt_trans (Nat.lt_succ_self fuel) fuelLt
          exact execForArray_has_runtime_type fuel localId
            (expressionsPreserve fuel smaller _ _ _ _ _ stateTyped
              iterableTyped)
            (fun statementFuel intermediate intermediateStore
                statementFuelLt intermediateTyped =>
              bodyInduction statementFuel
                (Nat.lt_trans statementFuelLt smaller) intermediateTyped)
            (inLoop := inLoop')
  | forSlice iterableTyped bodyTyped bodyInduction =>
      rename_i context' iterableExpr elementType localId bodyStmt inLoop'
      cases fuel with
      | zero => exact execStmt_zero_has_runtime_type stateTyped
      | succ fuel =>
          have smaller := Nat.lt_trans (Nat.lt_succ_self fuel) fuelLt
          exact execForSlice_has_runtime_type fuel localId
            (expressionsPreserve fuel smaller _ _ _ _ _ stateTyped
              iterableTyped)
            (fun statementFuel intermediate intermediateStore
                statementFuelLt intermediateTyped =>
              bodyInduction statementFuel
                (Nat.lt_trans statementFuelLt smaller) intermediateTyped)
            (inLoop := inLoop')
  | forRange startTyped stopTyped bodyTyped bodyInduction =>
      rename_i context' startExpr stopExpr localId bodyStmt inLoop' inclusive
      cases fuel with
      | zero => exact execStmt_zero_has_runtime_type stateTyped
      | succ fuel =>
          have smaller := Nat.lt_trans (Nat.lt_succ_self fuel) fuelLt
          have startOutcome := expressionsPreserve fuel smaller _ _ _ _ _
            stateTyped startTyped
          cases startResult : evalExpr fuel program state startExpr with
          | done value afterStart =>
              rw [startResult] at startOutcome
              obtain ⟨startStore, startStorePreserved, startCellsPreserved,
                afterStartTyped, valueTyped, valueBorrows⟩ := startOutcome
              cases valueTyped with
              | signed type startValue lower upper =>
                  have typedStart : ValueHasType program (.signed .i32 startValue)
                      (.scalar (.signed .i32)) := .signed .i32 startValue lower upper
                  cases stopTyped with
                  | none =>
                      have rangeOutcome := execForRange_has_runtime_type fuel
                        localId afterStartTyped typedStart
                        (fun statementFuel intermediate intermediateStore
                            statementFuelLt intermediateTyped =>
                          bodyInduction statementFuel
                            (Nat.lt_trans statementFuelLt smaller)
                            intermediateTyped)
                        (inLoop := inLoop') (stop := none)
                        (inclusive := inclusive)
                      simpa only [execStmt.eq_10, startResult] using
                        rangeOutcome.prepend startStorePreserved
                          startCellsPreserved
                  | some typedStop =>
                      rename_i stopExpression
                      have stopOutcome := expressionsPreserve fuel smaller
                        _ _ _ _ _ afterStartTyped typedStop
                      cases stopResult : evalExpr fuel program afterStart
                          stopExpression with
                      | done stopValue afterStop =>
                          rw [stopResult] at stopOutcome
                          obtain ⟨stopStore, stopStorePreserved,
                            stopCellsPreserved, afterStopTyped, stopValueTyped,
                            stopValueBorrows⟩ := stopOutcome
                          cases stopValueTyped with
                          | signed type stopValue lower upper =>
                              have rangeOutcome := execForRange_has_runtime_type
                                fuel localId afterStopTyped typedStart
                                (fun statementFuel intermediate
                                    intermediateStore statementFuelLt
                                    intermediateTyped =>
                                  bodyInduction statementFuel
                                    (Nat.lt_trans statementFuelLt smaller)
                                    intermediateTyped)
                                (inLoop := inLoop') (stop := some stopValue)
                                (inclusive := inclusive)
                              simpa only [execStmt.eq_10, startResult,
                                stopResult] using
                                (rangeOutcome.prepend stopStorePreserved
                                  stopCellsPreserved).prepend
                                    startStorePreserved startCellsPreserved
                      | trapped reason next | exited reason next =>
                          rw [stopResult] at stopOutcome
                          simpa only [execStmt.eq_10, startResult, stopResult,
                            RuntimeValueOutcomeHasExtendedType,
                            RuntimeCompletionOutcomeHasType] using
                            stopOutcome.prepend startStorePreserved
                              startCellsPreserved
                      | outOfFuel =>
                          simp [execStmt.eq_10, startResult, stopResult,
                            RuntimeCompletionOutcomeHasType]
          | trapped reason next | exited reason next =>
              rw [startResult] at startOutcome
              simpa only [execStmt.eq_10, startResult,
                RuntimeValueOutcomeHasExtendedType,
                RuntimeCompletionOutcomeHasType] using startOutcome
          | outOfFuel =>
              simp [execStmt.eq_10, startResult,
                RuntimeCompletionOutcomeHasType]
  | returnUnit isUnit =>
      cases fuel with
      | zero => exact execStmt_zero_has_runtime_type stateTyped
      | succ fuel => exact execReturnUnit_has_runtime_type fuel stateTyped isUnit
  | returnValue valueTyped =>
      cases fuel with
      | zero => exact execStmt_zero_has_runtime_type stateTyped
      | succ fuel =>
          have smaller := Nat.lt_trans (Nat.lt_succ_self fuel) fuelLt
          exact execReturnValue_has_runtime_type fuel
            (expressionsPreserve fuel smaller _ _ _ _ _ stateTyped valueTyped)
  | breakLoop =>
      cases fuel with
      | zero => exact execStmt_zero_has_runtime_type stateTyped
      | succ fuel => exact execBreak_has_runtime_type fuel stateTyped
  | continueLoop =>
      cases fuel with
      | zero => exact execStmt_zero_has_runtime_type stateTyped
      | succ fuel => exact execContinue_has_runtime_type fuel stateTyped

theorem evalInternalCall_has_type
    (fuel : Nat)
    (_stateTyped : StateHasType program context state store)
    (programTyped : ProgramWellTyped program)
    (functionFound : program.function? functionId = some function)
    (bodyFound : function.body = some body)
    (argumentsPreserved : ValuesOutcomeHaveTypes program context state store
      (evalExprs fuel program state arguments)
      (function.parameters.map Prod.snd))
    (expressionsPreserve : ExpressionsPreserveTypes program) :
    ValueOutcomeHasType program context state store
      (evalExpr (fuel + 1) program state (.call functionId arguments))
      function.returnType := by
  cases argumentsResult : evalExprs fuel program state arguments with
  | done values afterArguments =>
      rw [argumentsResult] at argumentsPreserved
      obtain ⟨argumentsStore, argumentsStorePreserved,
        argumentsCellsPreserved, afterArgumentsTyped, argumentsTyped,
        argumentBorrows⟩ := argumentsPreserved
      have functionMember : function ∈ program.functions :=
        List.mem_of_find?_eq_some functionFound
      have functionTyped := programTyped.2 function functionMember
      simp only [FunctionWellTyped, bodyFound] at functionTyped
      obtain ⟨externalNone, bodyTyped, returnCoverage⟩ := functionTyped
      obtain ⟨bindings, bound⟩ := bindParameters_exists argumentsTyped
      obtain ⟨calleeStore, calleeStorePreserved, calleeCellsPreserved,
        calleeTyped⟩ := prepareCallee_has_type afterArgumentsTyped
          argumentsTyped argumentBorrows bound
      have statementOutcome := execStmt_has_type expressionsPreserve bodyTyped
        fuel calleeTyped
      cases statementResult : execStmt fuel program
          (({ afterArguments with locals := [] }).bindLocals bindings) body with
      | done completion completed =>
          rw [statementResult] at statementOutcome
          have restoredOutcome := statementOutcome.restoreLocals
            afterArgumentsTyped calleeStorePreserved calleeCellsPreserved
          simp only [restoreOutcomeLocals] at restoredOutcome
          obtain ⟨bodyStore, bodyStorePreserved, bodyCellsPreserved,
            completedTyped, completionTyped⟩ := restoredOutcome
          simp only [evalExpr, argumentsResult, functionFound, bodyFound, bound,
            statementResult]
          cases completion with
          | returned result =>
              cases result with
              | none =>
                  have isUnit : function.returnType = .unit := completionTyped
                  simp only [isUnit, if_true]
                  exact ⟨bodyStore,
                    argumentsStorePreserved.trans bodyStorePreserved,
                    argumentsCellsPreserved.trans bodyCellsPreserved,
                    completedTyped, .unit,
                    (show ValueIsClosed .unit by rfl).borrowsValid⟩
              | some result =>
                  exact ⟨bodyStore,
                    argumentsStorePreserved.trans bodyStorePreserved,
                    argumentsCellsPreserved.trans bodyCellsPreserved,
                    completedTyped, completionTyped.1, completionTyped.2⟩
          | next =>
              by_cases isUnit : function.returnType = .unit
              · simp only [isUnit, if_true]
                exact ⟨bodyStore,
                  argumentsStorePreserved.trans bodyStorePreserved,
                  argumentsCellsPreserved.trans bodyCellsPreserved,
                  completedTyped, .unit,
                  (show ValueIsClosed .unit by rfl).borrowsValid⟩
              · simp only [isUnit, if_false]
                exact ⟨bodyStore,
                  argumentsStorePreserved.trans bodyStorePreserved,
                  argumentsCellsPreserved.trans bodyCellsPreserved,
                  completedTyped⟩
          | breakLoop =>
              simp [CompletionHasType] at completionTyped
          | continueLoop =>
              simp [CompletionHasType] at completionTyped
      | trapped reason completed =>
          rw [statementResult] at statementOutcome
          have restoredOutcome := statementOutcome.restoreLocals
            afterArgumentsTyped calleeStorePreserved calleeCellsPreserved
          simp only [evalExpr, argumentsResult, functionFound, bodyFound, bound,
            statementResult, ValueOutcomeHasType]
          exact restoredOutcome.prepend argumentsStorePreserved
            argumentsCellsPreserved
      | exited code completed =>
          rw [statementResult] at statementOutcome
          have restoredOutcome := statementOutcome.restoreLocals
            afterArgumentsTyped calleeStorePreserved calleeCellsPreserved
          simp only [evalExpr, argumentsResult, functionFound, bodyFound, bound,
            statementResult, ValueOutcomeHasType]
          exact restoredOutcome.prepend argumentsStorePreserved
            argumentsCellsPreserved
      | outOfFuel =>
          simp [evalExpr, argumentsResult, functionFound, bodyFound, bound,
            statementResult, ValueOutcomeHasType]
  | trapped reason next =>
      rw [argumentsResult] at argumentsPreserved
      simpa only [evalExpr, argumentsResult, ValuesOutcomeHaveTypes,
        ValueOutcomeHasType] using argumentsPreserved
  | exited code next =>
      rw [argumentsResult] at argumentsPreserved
      simpa only [evalExpr, argumentsResult, ValuesOutcomeHaveTypes,
        ValueOutcomeHasType] using argumentsPreserved
  | outOfFuel =>
      simp [evalExpr, argumentsResult, ValueOutcomeHasType]

theorem evalInternalCall_has_runtime_type
    (fuel : Nat)
    (_stateTyped : RuntimeStateHasType program context state store)
    (programTyped : ProgramWellTyped program)
    (functionFound : program.function? functionId = some function)
    (bodyFound : function.body = some body)
    (argumentsPreserved : RuntimeValuesOutcomeHaveTypes program context state
      store (evalExprs fuel program state arguments)
      (function.parameters.map Prod.snd))
    (expressionsPreserve : RuntimeExpressionsPreserveTypesBelow program limit)
    (fuelLt : fuel < limit) :
    RuntimeValueOutcomeHasExtendedType program context state store
      (evalExpr (fuel + 1) program state (.call functionId arguments))
      function.returnType := by
  cases argumentsResult : evalExprs fuel program state arguments with
  | done values afterArguments =>
      rw [argumentsResult] at argumentsPreserved
      obtain ⟨argumentsStore, argumentsStorePreserved,
        argumentsCellsPreserved, afterArgumentsTyped, argumentsTyped,
        argumentBorrows⟩ := argumentsPreserved
      have functionMember : function ∈ program.functions :=
        List.mem_of_find?_eq_some functionFound
      have functionTyped := programTyped.2 function functionMember
      simp only [FunctionWellTyped, bodyFound] at functionTyped
      obtain ⟨externalNone, bodyTyped, returnCoverage⟩ := functionTyped
      obtain ⟨bindings, bound⟩ := bindParameters_exists argumentsTyped
      obtain ⟨calleeStore, calleeStorePreserved, calleeCellsPreserved,
        calleeTyped⟩ := prepareCallee_has_runtime_type afterArgumentsTyped
          argumentsTyped argumentBorrows bound
      have statementOutcome := execStmt_has_runtime_type_below
        expressionsPreserve bodyTyped fuel fuelLt calleeTyped
      cases statementResult : execStmt fuel program
          (({ afterArguments with locals := [] }).bindLocals bindings) body with
      | done completion completed =>
          rw [statementResult] at statementOutcome
          have restoredOutcome := statementOutcome.restoreLocals
            afterArgumentsTyped calleeStorePreserved calleeCellsPreserved
          simp only [restoreOutcomeLocals] at restoredOutcome
          obtain ⟨bodyStore, bodyStorePreserved, bodyCellsPreserved,
            completedTyped, completionTyped⟩ := restoredOutcome
          simp only [evalExpr, argumentsResult, functionFound, bodyFound, bound,
            statementResult]
          cases completion with
          | returned result =>
              cases result with
              | none =>
                  have isUnit : function.returnType = .unit := completionTyped
                  simp only [isUnit, if_true]
                  exact ⟨bodyStore,
                    argumentsStorePreserved.trans bodyStorePreserved,
                    argumentsCellsPreserved.trans bodyCellsPreserved,
                    completedTyped, .unit,
                    (show ValueIsClosed .unit by rfl).borrowsValid⟩
              | some result =>
                  exact ⟨bodyStore,
                    argumentsStorePreserved.trans bodyStorePreserved,
                    argumentsCellsPreserved.trans bodyCellsPreserved,
                    completedTyped, completionTyped.1, completionTyped.2⟩
          | next =>
              by_cases isUnit : function.returnType = .unit
              · simp only [isUnit, if_true]
                exact ⟨bodyStore,
                  argumentsStorePreserved.trans bodyStorePreserved,
                  argumentsCellsPreserved.trans bodyCellsPreserved,
                  completedTyped, .unit,
                  (show ValueIsClosed .unit by rfl).borrowsValid⟩
              · simp only [isUnit, if_false]
                exact ⟨bodyStore,
                  argumentsStorePreserved.trans bodyStorePreserved,
                  argumentsCellsPreserved.trans bodyCellsPreserved,
                  completedTyped⟩
          | breakLoop => simp [CompletionHasType] at completionTyped
          | continueLoop => simp [CompletionHasType] at completionTyped
      | trapped reason completed | exited reason completed =>
          rw [statementResult] at statementOutcome
          have restoredOutcome := statementOutcome.restoreLocals
            afterArgumentsTyped calleeStorePreserved calleeCellsPreserved
          simp only [evalExpr, argumentsResult, functionFound, bodyFound, bound,
            statementResult, RuntimeValueOutcomeHasExtendedType]
          exact restoredOutcome.prepend argumentsStorePreserved
            argumentsCellsPreserved
      | outOfFuel =>
          simp [evalExpr, argumentsResult, functionFound, bodyFound, bound,
            statementResult, RuntimeValueOutcomeHasExtendedType]
  | trapped reason next | exited reason next =>
      rw [argumentsResult] at argumentsPreserved
      simpa only [evalExpr, argumentsResult, RuntimeValuesOutcomeHaveTypes,
        RuntimeValueOutcomeHasExtendedType] using argumentsPreserved
  | outOfFuel =>
      simp [evalExpr, argumentsResult, RuntimeValueOutcomeHasExtendedType]

def emptyStoreTyping : StoreTyping := fun _ => none

theorem empty_state_has_type (program : Program) :
    StateHasType program Context.empty ({} : State) emptyStoreTyping := by
  constructor
  · exact empty_state_well_formed
  · intro cell
    rfl
  · intro entry member
    simp at member
  · intro id
    simp [Context.empty, State.cellId?]

/-- The executable opaque-call oracle is a typed assumption at the foreign
    boundary. Every declaration sharing an external identity must accept the
    queued response at its declared result type; returned values are closed so
    the oracle cannot forge references into the Lanius stable-cell store. -/
def OpaqueResponsesWellTyped (program : Program) (world : World.State) : Prop :=
  ∀ response, response ∈ world.opaqueResponses →
    ∀ function, function ∈ program.functions →
      function.external = some (.opaque response.external) →
      match response.outcome with
      | .trapped _ => True
      | .returned value =>
          ValueHasType program value function.returnType ∧ ValueIsClosed value

theorem callOpaque_has_type
    (responsesTyped : OpaqueResponsesWellTyped program world)
    (functionMember : function ∈ program.functions)
    (externalMatches : function.external = some (.opaque external)) :
    OpaqueCallResultHasType program
      (world.callOpaque external arguments) function.returnType := by
  cases responses : world.opaqueResponses with
  | nil => simp [World.State.callOpaque, responses, OpaqueCallResultHasType]
  | cons response rest =>
      have responseTyped := responsesTyped response (by simp [responses])
        function functionMember
      by_cases sameExternal : response.external = external
      · have responseExternal :
            function.external = some (.opaque response.external) := by
          simpa only [sameExternal] using externalMatches
        have typedAtFunction := responseTyped responseExternal
        cases outcome : response.outcome with
        | returned value =>
            simpa [World.State.callOpaque, responses, sameExternal,
              OpaqueCallResultHasType, outcome] using typedAtFunction
        | trapped reason =>
            simp [World.State.callOpaque, responses, sameExternal,
              OpaqueCallResultHasType, outcome]
      · simp [World.State.callOpaque, responses, sameExternal,
          OpaqueCallResultHasType]

/-- A queued opaque response satisfying the foreign-boundary contract remains
    well typed after the runtime records the call and synchronizes borrowed
    array views. -/
theorem opaqueHostCallOutcome_has_runtime_type
    (typed : RuntimeStateHasType program context state store)
    (responsesTyped : OpaqueResponsesWellTyped program state.world)
    (functionMember : function ∈ program.functions)
    (externalMatches : function.external = some (.opaque external)) :
    RuntimeValueOutcomeHasType program context store
      (opaqueCallOutcome external state
        (state.world.callOpaque external arguments)) function.returnType :=
  opaqueCallOutcome_has_runtime_type typed
    (callOpaque_has_type responsesTyped functionMember externalMatches)

/-- The evaluator's opaque-external call branch preserves runtime typing when
    the response queue at the post-argument world satisfies the declared
    foreign-result contract. This premise is explicit because argument
    expressions may themselves consume opaque responses. -/
theorem evalOpaqueCall_has_runtime_type
    (fuel : Nat)
    (functionFound : program.function? functionId = some function)
    (bodyMissing : function.body = none)
    (externalFound : function.external = some (.opaque external))
    (argumentsPreserved : RuntimeValuesOutcomeHaveTypes program context
      state store (evalExprs fuel program state arguments)
      (function.parameters.map Prod.snd))
    (responsesTyped : ∀ values afterArguments,
      evalExprs fuel program state arguments = .done values afterArguments →
      OpaqueResponsesWellTyped program afterArguments.world) :
    RuntimeValueOutcomeHasExtendedType program context state store
      (evalExpr (fuel + 1) program state (.call functionId arguments))
      function.returnType := by
  have functionMember : function ∈ program.functions :=
    List.mem_of_find?_eq_some functionFound
  cases argumentsResult : evalExprs fuel program state arguments with
  | done values afterArguments =>
      rw [argumentsResult] at argumentsPreserved
      obtain ⟨argumentsStore, storePreserved, cellsPreserved,
        afterArgumentsTyped, argumentsTyped, argumentBorrows⟩ :=
        argumentsPreserved
      obtain ⟨bindings, bound⟩ := bindParameters_exists argumentsTyped
      cases synchronized : syncI32ViewsToHeap afterArguments with
      | error reason =>
          simp only [evalExpr, argumentsResult, functionFound, bodyMissing,
            bound, externalFound, synchronized]
          exact ⟨argumentsStore, storePreserved, cellsPreserved,
            afterArgumentsTyped⟩
      | ok next =>
          have nextTyped := syncI32ViewsToHeap_preserves_runtime_type
            afterArgumentsTyped synchronized
          have synchronizedCells :=
            syncI32ViewsToHeap_preserves_initialized_cells synchronized
          have synchronizedWorld :=
            syncI32ViewsToHeap_preserves_world synchronized
          have nextResponsesTyped :
              OpaqueResponsesWellTyped program next.world := by
            rw [synchronizedWorld]
            exact responsesTyped values afterArguments argumentsResult
          have called := opaqueHostCallOutcome_has_runtime_type nextTyped
            nextResponsesTyped functionMember externalFound
            (arguments := values)
          have callCells := opaqueCallOutcome_preserves_initialized_cells
            (external := external) (state := next)
            (result := next.world.callOpaque external values)
          simpa only [evalExpr, argumentsResult, functionFound, bodyMissing,
            bound, externalFound, synchronized] using
            called.prepend storePreserved cellsPreserved
              (InitializedCellsPreserved.prependOutcome _ synchronizedCells
                callCells)
  | trapped reason next =>
      rw [argumentsResult] at argumentsPreserved
      simpa only [evalExpr, argumentsResult, RuntimeValuesOutcomeHaveTypes,
        RuntimeValueOutcomeHasExtendedType] using argumentsPreserved
  | exited code next =>
      rw [argumentsResult] at argumentsPreserved
      simpa only [evalExpr, argumentsResult, RuntimeValuesOutcomeHaveTypes,
        RuntimeValueOutcomeHasExtendedType] using argumentsPreserved
  | outOfFuel =>
      simp [evalExpr, argumentsResult, RuntimeValueOutcomeHasExtendedType]

/-- Every expression constructor preserves runtime typing provided recursive
    expression evaluations satisfy the same contract. The separate closure
    theorem discharges this recursive premise by fuel. -/
theorem evalExpr_has_runtime_type_assuming
    (programTyped : ProgramWellTyped program)
    (constantsClosed : ProgramConstantsClosed program)
    (opaqueWorldsTyped : ∀ world, OpaqueResponsesWellTyped program world)
    (fuel : Nat)
    (expressionsPreserve : RuntimeExpressionsPreserveTypesBelow program fuel)
    (stateTyped : RuntimeStateHasType program context state store)
    (typed : ExprHasType program context expression type) :
    RuntimeValueOutcomeHasExtendedType program context state store
      (evalExpr fuel program state expression) type := by
  cases fuel with
  | zero => simp [evalExpr, RuntimeValueOutcomeHasExtendedType]
  | succ fuel =>
      have fuelLt : fuel < fuel + 1 := Nat.lt_succ_self fuel
      have preserveAtFuel :
          ∀ (expressionContext : Context) (intermediate : State)
            (intermediateStore : StoreTyping) (nested : Expr)
            (nestedType : Ty),
            RuntimeStateHasType program expressionContext intermediate
              intermediateStore →
            ExprHasType program expressionContext nested nestedType →
            RuntimeValueOutcomeHasExtendedType program expressionContext
              intermediate intermediateStore
              (evalExpr fuel program intermediate nested) nestedType :=
        fun expressionContext intermediate intermediateStore nested nestedType
            intermediateTyped nestedTyped =>
          expressionsPreserve fuel fuelLt expressionContext intermediate
            intermediateStore nested nestedType intermediateTyped nestedTyped
      cases typed with
      | value valueTyped literal =>
          exact evalClosedValue_has_runtime_type fuel stateTyped valueTyped
            (Value.isLiteral_is_closed _ literal)
      | «local» found => exact evalLocal_has_runtime_type fuel stateTyped found
      | cast operand conversion =>
          exact evalCast_has_runtime_type fuel conversion
            (preserveAtFuel _ _ _ _ _ stateTyped operand)
      | unary operand operation =>
          exact evalUnary_has_runtime_type fuel operation
            (preserveAtFuel _ _ _ _ _ stateTyped operand)
      | binary left right operation =>
          exact evalBinary_has_runtime_type fuel operation
            (preserveAtFuel _ _ _ _ _ stateTyped left)
            (fun intermediate intermediateStore intermediateTyped =>
              preserveAtFuel _ _ _ _ _ intermediateTyped right)
      | array elements =>
          exact evalArray_has_runtime_type fuel
            (evalExprs_atFuel_have_runtime_types fuel stateTyped elements
              expressionsPreserve fuelLt)
      | arrayToSlice arrayTyped =>
          exact evalArrayToSlice_has_runtime_type fuel
            (fun place found =>
              evalPlace_atFuel_has_runtime_type fuel stateTyped
                (expressionPlace?_has_type arrayTyped found)
                expressionsPreserve fuelLt)
            (fun _ => preserveAtFuel _ _ _ _ _ stateTyped arrayTyped)
      | indexArray base index integerIndex =>
          exact evalArrayIndex_has_runtime_type fuel
            (preserveAtFuel _ _ _ _ _ stateTyped base)
            (fun intermediate intermediateStore intermediateTyped =>
              preserveAtFuel _ _ _ _ _ intermediateTyped index)
      | indexSlice base index integerIndex =>
          exact evalSliceIndex_has_runtime_type fuel
            (preserveAtFuel _ _ _ _ _ stateTyped base)
            (fun intermediate intermediateStore intermediateTyped =>
              preserveAtFuel _ _ _ _ _ intermediateTyped index)
      | structValue declaration found fields =>
          exact evalStructValue_has_runtime_type fuel found
            (evalExprs_atFuel_have_runtime_types fuel stateTyped fields
              expressionsPreserve fuelLt)
      | field base declaration found fieldFound =>
          exact evalField_has_runtime_type fuel found fieldFound
            (preserveAtFuel _ _ _ _ _ stateTyped base)
      | enumValue declaration found variantFound payload =>
          exact evalEnumValue_has_runtime_type fuel found variantFound
            (evalExprs_atFuel_have_runtime_types fuel stateTyped payload
              expressionsPreserve fuelLt)
      | matchValue scrutinee armsTyped =>
          exact evalMatchValue_has_runtime_type fuel
            (preserveAtFuel _ _ _ _ _ stateTyped scrutinee)
            armsTyped expressionsPreserve fuelLt
      | assign target value operation =>
          exact evalAssign_has_runtime_type fuel operation
            (evalPlace_atFuel_has_runtime_type fuel stateTyped target
              expressionsPreserve fuelLt)
            (fun intermediate intermediateStore intermediateTyped =>
              preserveAtFuel _ _ _ _ _ intermediateTyped value)
      | borrow target =>
          exact evalBorrow_has_runtime_type fuel
            (evalPlace_atFuel_has_runtime_type fuel stateTyped target
              expressionsPreserve fuelLt)
      | dereference reference =>
          exact evalDereference_has_runtime_type fuel
            (preserveAtFuel _ _ _ _ _ stateTyped reference)
      | constant declaration found =>
          exact evalConstant_has_runtime_type fuel stateTyped programTyped
            constantsClosed found
      | call function found arguments =>
          have argumentsOutcome := evalExprs_atFuel_have_runtime_types fuel
            stateTyped arguments expressionsPreserve fuelLt
          cases body : function.body with
          | some functionBody =>
              exact evalInternalCall_has_runtime_type fuel stateTyped
                programTyped found body argumentsOutcome expressionsPreserve
                fuelLt
          | none =>
              cases external : function.external with
              | none =>
                  have functionMember : function ∈ program.functions :=
                    List.mem_of_find?_eq_some found
                  have functionTyped := programTyped.2 function functionMember
                  simp [FunctionWellTyped, body, external] at functionTyped
              | some behavior =>
                  cases behavior with
                  | host service =>
                      exact evalHostCall_has_runtime_type fuel programTyped found
                        body external argumentsOutcome
                  | unavailable capability =>
                      exact evalImmediateExternalCall_has_runtime_type fuel found
                        body external (.unavailable capability) argumentsOutcome
                  | panic =>
                      exact evalImmediateExternalCall_has_runtime_type fuel found
                        body external .panic argumentsOutcome
                  | unreachable =>
                      exact evalImmediateExternalCall_has_runtime_type fuel found
                        body external .unreachable argumentsOutcome
                  | «opaque» externalId =>
                      exact evalOpaqueCall_has_runtime_type fuel found body
                        external argumentsOutcome
                        (fun values afterArguments result =>
                          opaqueWorldsTyped afterArguments.world)
      | printI32 argument =>
          exact evalPrintI32_has_runtime_type fuel
            (preserveAtFuel _ _ _ _ _ stateTyped argument)
      | assert argument =>
          exact evalAssert_has_runtime_type fuel
            (preserveAtFuel _ _ _ _ _ stateTyped argument)
      | i32ArrayDataPtr array =>
          exact evalI32ArrayDataPtr_has_runtime_type fuel
            (fun place found =>
              evalPlace_atFuel_has_runtime_type fuel stateTyped
                (expressionPlace?_has_type array found) expressionsPreserve
                fuelLt)
            (fun _ => preserveAtFuel _ _ _ _ _ stateTyped array)
      | alloc size alignment =>
          exact evalAlloc_has_runtime_type fuel
            (preserveAtFuel _ _ _ _ _ stateTyped size)
            (fun intermediate intermediateStore intermediateTyped =>
              preserveAtFuel _ _ _ _ _ intermediateTyped alignment)
      | realloc pointer oldSize newSize alignment =>
          exact evalRealloc_has_runtime_type fuel
            (evalExprs_atFuel_have_runtime_types fuel stateTyped
                (.cons pointer (.cons oldSize (.cons newSize
                (.cons alignment .nil)))) expressionsPreserve fuelLt)
      | dealloc pointer size alignment =>
          exact evalDealloc_has_runtime_type fuel
            (evalExprs_atFuel_have_runtime_types fuel stateTyped
              (.cons pointer (.cons size (.cons alignment .nil)))
              expressionsPreserve fuelLt)
      | loadByte pointer offset =>
          exact evalLoadByte_has_runtime_type fuel
            (evalExprs_atFuel_have_runtime_types fuel stateTyped
              (.cons pointer (.cons offset .nil)) expressionsPreserve fuelLt)
      | storeByte pointer offset value =>
          exact evalStoreByte_has_runtime_type fuel
            (evalExprs_atFuel_have_runtime_types fuel stateTyped
              (.cons pointer (.cons offset (.cons value .nil)))
              expressionsPreserve fuelLt)

/-- Whole-evaluator runtime preservation. The strong induction hypothesis is
    exposed only below the current fuel, so recursive expressions, statement
    bodies, match arms, places, and calls cannot appeal circularly to the case
    currently being proved. -/
theorem runtimeExpressionsPreserveTypes
    (programTyped : ProgramWellTyped program)
    (constantsClosed : ProgramConstantsClosed program)
    (opaqueWorldsTyped : ∀ world, OpaqueResponsesWellTyped program world) :
    RuntimeExpressionsPreserveTypes program := by
  intro fuel
  induction fuel using Nat.strongRecOn with
  | ind fuel induction =>
      intro context state store expression type stateTyped expressionTyped
      exact evalExpr_has_runtime_type_assuming programTyped constantsClosed
        opaqueWorldsTyped fuel
        (fun smaller smallerLt => induction smaller smallerLt)
        stateTyped expressionTyped

theorem evalExpr_has_runtime_type
    (programTyped : ProgramWellTyped program)
    (constantsClosed : ProgramConstantsClosed program)
    (opaqueWorldsTyped : ∀ world, OpaqueResponsesWellTyped program world)
    (fuel : Nat)
    (stateTyped : RuntimeStateHasType program context state store)
    (expressionTyped : ExprHasType program context expression type) :
    RuntimeValueOutcomeHasExtendedType program context state store
      (evalExpr fuel program state expression) type :=
  runtimeExpressionsPreserveTypes programTyped constantsClosed
    opaqueWorldsTyped fuel context state store expression type stateTyped
    expressionTyped

theorem execStmt_has_runtime_type
    (programTyped : ProgramWellTyped program)
    (constantsClosed : ProgramConstantsClosed program)
    (opaqueWorldsTyped : ∀ world, OpaqueResponsesWellTyped program world)
    (statementTyped : StmtHasType program returnType context inLoop statement)
    (fuel : Nat)
    (stateTyped : RuntimeStateHasType program context state store) :
    RuntimeCompletionOutcomeHasType program returnType context inLoop state store
      (execStmt fuel program state statement) := by
  have preserve := runtimeExpressionsPreserveTypes programTyped constantsClosed
    opaqueWorldsTyped
  exact execStmt_has_runtime_type_below
    (limit := fuel + 1)
    (fun expressionFuel _ expressionContext intermediate intermediateStore
        expression expressionType intermediateTyped expressionTyped =>
      preserve expressionFuel expressionContext intermediate intermediateStore
        expression expressionType intermediateTyped expressionTyped)
    statementTyped fuel (Nat.lt_succ_self fuel) stateTyped

/-- A whole-program result retains the entrypoint's language type and the
    runtime-state invariant.  Ordinary return, explicit process exit, traps,
    and fuel exhaustion remain distinct observations. -/
def ExecutionResultHasType
    (program : Program) (returnType : Ty)
    (beforeState : State) (beforeStore : StoreTyping) :
    Execution.Result → Prop
  | .returned value afterState =>
      ∃ afterStore, StoreExtends beforeStore afterStore ∧
        InitializedCellsPreserved beforeState afterState ∧
        RuntimeStateHasType program Context.empty afterState afterStore ∧
        ValueHasType program value returnType ∧
        BorrowsValid program afterState afterStore value
  | .exited _ afterState | .trapped _ afterState =>
      RuntimeStateHasExtendedType program Context.empty beforeState beforeStore
        afterState
  | .outOfFuel => True

/-- Selecting a well-formed executable entrypoint produces a typed, closed
    zero-argument call expression. -/
theorem executable_entrypoint_call_has_type
    (wellFormed : Execution.ExecutableWellFormed executable) :
    ∃ returnType,
      Execution.EntrypointReturnType returnType ∧
        ExprHasType executable.program Context.empty
          (.call executable.entrypoint []) returnType := by
  obtain ⟨function, found, noParameters, returnType, functionTyped⟩ := wellFormed
  refine ⟨function.returnType, returnType, ?_⟩
  apply ExprHasType.call function found
  simpa [noParameters] using
    (ExprsHaveTypes.nil (program := executable.program)
      (context := Context.empty))

/-- Whole-program preservation.  A well-typed executable cannot ordinarily
    return a value outside its declared entrypoint type, and every terminal
    result preserves the runtime store and borrowed-view invariants. -/
theorem executable_run_has_runtime_type
    (programTyped : ProgramWellTyped executable.program)
    (constantsClosed : ProgramConstantsClosed executable.program)
    (opaqueWorldsTyped : ∀ world,
      OpaqueResponsesWellTyped executable.program world)
    (wellFormed : Execution.ExecutableWellFormed executable)
    (fuel : Nat) (initial : State) (initialStore : StoreTyping)
    (initialTyped : RuntimeStateHasType executable.program Context.empty
      initial initialStore) :
    ∃ returnType,
      Execution.EntrypointReturnType returnType ∧
        ExecutionResultHasType executable.program returnType initial initialStore
          (Execution.run fuel executable initial) := by
  obtain ⟨returnType, returnAllowed, callTyped⟩ :=
    executable_entrypoint_call_has_type wellFormed
  refine ⟨returnType, returnAllowed, ?_⟩
  have evaluated := evalExpr_has_runtime_type programTyped constantsClosed
    opaqueWorldsTyped fuel initialTyped callTyped
  cases result : evalExpr fuel executable.program initial
      (.call executable.entrypoint []) <;>
    rw [result] at evaluated <;>
    simpa [Execution.run, result, ExecutionResultHasType,
      RuntimeValueOutcomeHasExtendedType] using evaluated

/-- A process world containing arguments, environment variables, files,
    clocks, entropy, and opaque responses is a valid initial language state:
    none of those inputs fabricates a Lanius cell or borrowed raw view. -/
theorem initial_world_state_has_runtime_type
    (program : Program) (world : World.State) :
    RuntimeStateHasType program Context.empty
      ({ world := world } : State) emptyStoreTyping := by
  constructor
  · simpa using (empty_state_has_type program).withWorld world
  · intro view member
    simp at member

end Lanius.Properties
