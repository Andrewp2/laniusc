import SelfCore
import Lanius.Semantics.CallProof
import Lanius.Semantics.PureProof
import Lanius.Semantics.SourceValue

namespace IRTypeRefProof

open Lanius Lanius.Core Lanius.Semantics
abbrev Reference := Extracted.«ir::type_ref».Types.«TypeRef»
private def nominal := Extracted.«ir::type_ref».Functions.«nominal_code».core
private def nominalSlice := Extracted.«ir::type_ref».Functions.«nominal_slice_code».core
private def invalid := Extracted.«ir::type_ref».Functions.«is_invalid».core
private def code := Extracted.«ir::type_ref».Functions.«code».core
private def fromCode := Extracted.«ir::type_ref».Functions.«from_code».core
private def valid := Extracted.«ir::type_ref».Functions.«valid».core
private def validResult := Extracted.«ir::type_ref».Functions.«valid_result».core
private def same := Extracted.«ir::type_ref».Functions.«same».core

def referenceValue : Reference → Value
  | .Invalid => source_value Extracted.«ir::type_ref».Types.«TypeRef».«Invalid» []
  | .Void => source_value Extracted.«ir::type_ref».Types.«TypeRef».«Void» []
  | .I32 => source_value Extracted.«ir::type_ref».Types.«TypeRef».«I32» []
  | .Bool => source_value Extracted.«ir::type_ref».Types.«TypeRef».«Bool» []
  | .Usize => source_value Extracted.«ir::type_ref».Types.«TypeRef».«Usize» []
  | .Pointer => source_value Extracted.«ir::type_ref».Types.«TypeRef».«Pointer» []
  | .String => source_value Extracted.«ir::type_ref».Types.«TypeRef».«String» []
  | .Slice => source_value Extracted.«ir::type_ref».Types.«TypeRef».«Slice» []
  | .Nominal id => source_value Extracted.«ir::type_ref».Types.«TypeRef».«Nominal» [.signed .i32 id.toInt]
  | .NominalSlice id => source_value Extracted.«ir::type_ref».Types.«TypeRef».«NominalSlice» [.signed .i32 id.toInt]

/-- The two reserved ranges are disjoint and fit in a signed i32. -/
def nominalCode (base id : Int) : Int := if id < 0 ∨ id ≥ 1073741808 then -1 else base + id
def typeCode : Reference → Int
  | .Invalid => -1 | .Void => 0 | .I32 => 1 | .Bool => 2
  | .Usize => 3 | .Pointer => 4 | .String => 5 | .Slice => 6
  | .Nominal id => nominalCode 16 id.toInt
  | .NominalSlice id => nominalCode 1073741824 id.toInt
def isInvalid : Reference → Bool | .Invalid => true | _ => false
def isValid (value : Reference) : Bool := decide (typeCode value > 0)
def isValidResult (value : Reference) : Bool := decide (typeCode value ≥ 0)
def sameType (left right : Reference) : Bool :=
  if isInvalid left then isInvalid right else
    (decide (typeCode left ≥ 0) && decide (typeCode right ≥ 0)) && (typeCode left == typeCode right)

@[core_pure_rule] theorem actualNominal (id : Int) (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram state (.call nominal.id [.value (.signed .i32 id)])
      (.signed .i32 (nominalCode 16 id)) after ∧ PureFrame state after := by
  dsimp only [nominalCode]
  split
  · core_call_pure nominal as callee
    core_pure
  · have add := eval_i32_addNonneg extractedProgram.target 16 id (by omega) (by omega)
    core_call_pure nominal as callee
    core_pure

@[core_pure_rule] theorem actualNominalSlice (id : Int) (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram state (.call nominalSlice.id [.value (.signed .i32 id)])
      (.signed .i32 (nominalCode 1073741824 id)) after ∧ PureFrame state after := by
  dsimp only [nominalCode]
  split
  · core_call_pure nominalSlice as callee
    core_pure
  · have add := eval_i32_addNonneg extractedProgram.target 1073741824 id (by omega) (by omega)
    core_call_pure nominalSlice as callee
    core_pure

@[core_pure_rule] theorem actualInvalid (value : Reference) (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram state (.call invalid.id [.value (referenceValue value)])
      (.boolean (isInvalid value)) after ∧ PureFrame state after := by
  cases value <;> dsimp only [referenceValue, isInvalid]
  all_goals (core_call_pure invalid as callee; core_pure)

@[core_pure_rule] theorem actualCode (value : Reference) (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram state (.call code.id [.value (referenceValue value)])
      (.signed .i32 (typeCode value)) after ∧ PureFrame state after := by
  cases value <;> dsimp only [referenceValue, typeCode]
  all_goals (core_call_pure code as callee; core_pure)

/-- Every cacheable type survives the actual code decoder, including both
    disjoint nominal ranges. Invalid nominal IDs are not cacheable. -/
@[core_pure_rule] theorem actualFromCode (value : Reference) (supported : isValidResult value = true)
    (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram state (.call fromCode.id [.value (.signed .i32 (typeCode value))])
      (referenceValue value) after ∧ PureFrame state after := by
  have nominalBase : extractedProgram.constant? Extracted.«ir::type_ref».Constants.«NOMINAL_BASE».id =
      some { Extracted.«ir::type_ref».Constants.«NOMINAL_BASE».pack with value := .signed .i32 16 } := by
    core_lookup
  have nominalSliceBase : extractedProgram.constant? Extracted.«ir::type_ref».Constants.«NOMINAL_SLICE_BASE».id =
      some { Extracted.«ir::type_ref».Constants.«NOMINAL_SLICE_BASE».pack with value := .signed .i32 1073741824 } := by
    core_lookup
  cases value with
  | Invalid => simp [isValidResult, typeCode] at supported
  | Nominal id =>
      have bounds : 0 ≤ id.toInt ∧ id.toInt < 1073741808 := by
        have nonnegative : 0 ≤ typeCode (.Nominal id) := of_decide_eq_true supported
        dsimp only [typeCode, nominalCode] at nonnegative
        split at nonnegative <;> omega
      simp only [typeCode, referenceValue, nominalCode,
        show ¬(id.toInt < 0 ∨ id.toInt ≥ 1073741808) from by omega, ↓reduceIte]
      have subtract := eval_i32_subNonneg extractedProgram.target (16 + id.toInt) 16 (by omega) (by omega)
      simp only [show 16 + id.toInt - 16 = id.toInt from by omega] at subtract
      core_call_pure fromCode as callee
      core_pure
  | NominalSlice id =>
      have bounds : 0 ≤ id.toInt ∧ id.toInt < 1073741808 := by
        have nonnegative : 0 ≤ typeCode (.NominalSlice id) := of_decide_eq_true supported
        dsimp only [typeCode, nominalCode] at nonnegative
        split at nonnegative <;> omega
      simp only [typeCode, referenceValue, nominalCode,
        show ¬(id.toInt < 0 ∨ id.toInt ≥ 1073741808) from by omega, ↓reduceIte]
      have subtract := eval_i32_subNonneg extractedProgram.target (1073741824 + id.toInt) 1073741824 (by omega) (by omega)
      simp only [show 1073741824 + id.toInt - 1073741824 = id.toInt from by omega] at subtract
      core_call_pure fromCode as callee
      core_pure
  | Void | I32 | Bool | Usize | Pointer | String | Slice =>
      dsimp only [typeCode, referenceValue]
      core_call_pure fromCode as callee
      core_pure

@[core_pure_rule] theorem actualValid (value : Reference) (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram state (.call valid.id [.value (referenceValue value)])
      (.boolean (isValid value)) after ∧ PureFrame state after := by
  core_call_pure valid as callee
  core_pure

@[core_pure_rule] theorem actualValidResult (value : Reference) (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram state (.call validResult.id [.value (referenceValue value)])
      (.boolean (isValidResult value)) after ∧ PureFrame state after := by
  core_call_pure validResult as callee
  core_pure

@[core_pure_rule] theorem actualSame (left right : Reference) (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram state (.call same.id
      [.value (referenceValue left), .value (referenceValue right)])
      (.boolean (sameType left right)) after ∧ PureFrame state after := by
  dsimp only [sameType]
  split
  all_goals (core_call_pure same as callee; core_pure)

-- Fixed source constructors are already Core values at their call sites;
-- select their native model explicitly rather than invert the encoder.
@[core_pure_rule] theorem actualSameI32 (left : Reference) (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram state (.call same.id
      [.value (referenceValue left), .value (referenceValue .I32)])
      (.boolean (sameType left .I32)) after ∧ PureFrame state after := actualSame left .I32 formed

@[core_pure_rule] theorem actualSameUsize (left : Reference) (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram state (.call same.id
      [.value (referenceValue left), .value (referenceValue .Usize)])
      (.boolean (sameType left .Usize)) after ∧ PureFrame state after := actualSame left .Usize formed

#print axioms actualNominal
#print axioms actualNominalSlice
#print axioms actualInvalid
#print axioms actualCode
#print axioms actualFromCode
#print axioms actualValid
#print axioms actualValidResult
#print axioms actualSame

end IRTypeRefProof
