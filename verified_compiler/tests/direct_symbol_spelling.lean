import SelfCore
import Lanius.Semantics.CallProof
import Lanius.Semantics.PureProof
import Lanius.Semantics.SourceValue
import Lanius.Semantics.NativeReadFrame

namespace SymbolSpellingProof

open Lanius Lanius.Core Lanius.Semantics

def source := Extracted.«ir::symbol_catalog».Functions.«spelling».core
def unitType : Ty := match source_value Extracted.«ir::symbol_catalog».Types.«Unit».mk [] with
  | .structure id _ => .structure id | _ => .unit
def tokenType : Ty := match source_value Extracted.«verified::token».Types.«TokenRow».mk [] with
  | .structure id _ => .structure id | _ => .unit
def referenceValue (unit token : Int) : Value :=
  source_value Extracted.«ir::symbol_catalog».Types.«Ref».mk [.signed .i32 unit, .signed .i32 token]
def spellingValue (bytes : Value) (start length : Int) (valid : Bool) : Value :=
  source_value Extracted.«ir::symbol_catalog».Types.«Spelling».mk
    [bytes, .signed .i32 start, .signed .i32 length, .boolean valid]

/-- The existing catalog descriptor. Unused declaration metadata stays opaque;
    this contract only resolves its source units and token rows. -/
structure Catalog where
  bytes : Value
  sourceCount : Nat
  tokens : Value
  tokenCount : Nat
  tokenStorage : Nat
  units : Value
  unitCount : Nat
  types : Value
  variants : Value
  fields : Value
  functions : Value
  constants : Value
  typeCount : Int
  variantCount : Int
  fieldCount : Int
  functionCount : Int
  constantCount : Int

def Catalog.value (catalog : Catalog) : Value :=
  source_value Extracted.«ir::symbol_catalog».Types.«Catalog».mk
    [catalog.bytes, .signed .i32 catalog.sourceCount,
      source_value Extracted.«verified::token».Types.«TokenTable».mk
        [catalog.tokens, .signed .i32 catalog.tokenCount, .pointer catalog.tokenStorage],
      catalog.units, .signed .i32 catalog.unitCount,
      catalog.types, .signed .i32 catalog.typeCount,
      catalog.variants, .signed .i32 catalog.variantCount,
      catalog.fields, .signed .i32 catalog.fieldCount,
      catalog.functions, .signed .i32 catalog.functionCount,
      catalog.constants, .signed .i32 catalog.constantCount]

structure UnitSpan where
  sourceOffset : Nat
  sourceLength : Nat
  tokenOffset : Nat
  tokenCount : Nat
  modulePath : Value

def UnitSpan.value (unit : UnitSpan) : Value :=
  source_value Extracted.«ir::symbol_catalog».Types.«Unit».mk
    [.signed .i32 unit.sourceOffset, .signed .i32 unit.sourceLength,
      .signed .i32 unit.tokenOffset, .signed .i32 unit.tokenCount, unit.modulePath]

def identifierRow (start finish : Nat) : Value :=
  source_value Extracted.«verified::token».Types.«TokenRow».mk
    [source_value Extracted.«verified::token».Types.«TokenKind».«Identifier» [],
      .signed .i32 start, .signed .i32 finish]

/-- Native reads and source bounds, not the result of invoking `spelling`. -/
structure ValidSpan (catalog : Catalog) (unit : UnitSpan) (state : State)
    (unitIndex tokenIndex start finish : Nat) : Prop where
  sourceFits : catalog.sourceCount < 2 ^ 31
  tokensFit : catalog.tokenCount < 2 ^ 31
  unitInside : unitIndex < catalog.unitCount
  sourceRange : unit.sourceOffset + unit.sourceLength ≤ catalog.sourceCount
  tokenRange : unit.tokenOffset + unit.tokenCount ≤ catalog.tokenCount
  tokenInside : tokenIndex < unit.tokenCount
  span : start < finish ∧ finish ≤ unit.sourceLength
  unitRead : ∃ address length, catalog.units = .rawSlice unitType address length ∧
    readRawSliceIndex extractedProgram state unitType address length unitIndex = .ok unit.value
  tokenRead : ∃ address length, catalog.tokens = .rawSlice tokenType address length ∧
    readRawSliceIndex extractedProgram state tokenType address length (unit.tokenOffset + tokenIndex) =
      .ok (identifierRow start finish)

theorem ValidSpan.ofReads
    (valid : ValidSpan catalog unit before unitIndex tokenIndex start finish)
    (reads : HeapReads before.heap after.heap) :
    ValidSpan catalog unit after unitIndex tokenIndex start finish := by
  refine { valid with unitRead := ?_, tokenRead := ?_ }
  · obtain ⟨address, length, descriptor, read⟩ := valid.unitRead
    exact ⟨address, length, descriptor, reads.rawSlice read⟩
  · obtain ⟨address, length, descriptor, read⟩ := valid.tokenRead
    exact ⟨address, length, descriptor, reads.rawSlice read⟩

/-- Resolve the selected identifier from actual unit/token records. The source
    is neither reread nor reparsed, and all catalog/token guards are discharged. -/
theorem actualSpan (catalog : Catalog) (unit : UnitSpan)
    (valid : ValidSpan catalog unit state unitIndex tokenIndex start finish)
    (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram state
      (.call source.id [.value catalog.value, .value (referenceValue unitIndex tokenIndex)])
      (spellingValue catalog.bytes (unit.sourceOffset + start) (finish - start) true) after ∧
      PureFrame state after := by
  obtain ⟨sourceFits, tokensFit, unitInside, sourceRange, tokenRange, tokenInside, span,
    ⟨unitAddress, unitLength, units, unitRead⟩,
    ⟨tokenAddress, tokenLength, tokens, tokenRead⟩⟩ := valid
  have tokenPosition := eval_i32_addNonneg extractedProgram.target
    unit.tokenOffset tokenIndex (by omega) (by omega)
  have sourcePosition := eval_i32_addNonneg extractedProgram.target
    unit.sourceOffset start (by omega) (by omega)
  have sourceLength := eval_i32_subNonneg extractedProgram.target finish start (by omega) (by omega)
  have sourceRemaining := eval_i32_subNonneg extractedProgram.target
    catalog.sourceCount unit.sourceOffset (by omega) (by omega)
  have tokenRemaining := eval_i32_subNonneg extractedProgram.target
    catalog.tokenCount unit.tokenOffset (by omega) (by omega)
  simp only [Catalog.value, units, tokens]
  core_call_pure source as callee
  core_pure

/-- An out-of-range source unit is rejected without touching backing storage. -/
theorem actualInvalidUnit (catalog : Catalog) (unit token : Int)
    (bad : unit < 0 ∨ catalog.unitCount ≤ unit) (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram state
      (.call source.id [.value catalog.value, .value (referenceValue unit token)])
      (spellingValue catalog.bytes 0 0 false) after ∧ PureFrame state after := by
  core_call_pure source as callee
  core_pure

#print axioms actualSpan
#print axioms actualInvalidUnit

end SymbolSpellingProof
