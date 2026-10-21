import verified_compiler.tests.direct_ir_catalog_construction

namespace IRCatalogConstructionProof

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics IRTypeRefProof
open IRCatalogAppendProof

private def zero : Value := .signed .i32 0
private def emptySlice (id : TypeId) : Value := .rawSlice (.structure id) 0 0
private def emptyTypes : Value := source_value Extracted.«ir::type_catalog».Types.«Table».mk
  [emptySlice 35, zero, emptySlice 36, zero, emptySlice 37, zero]
private def emptyConstants : Value := source_value Extracted.«ir::constant_catalog».Types.«Table».mk
  [emptySlice 22, zero, .rawSlice (.scalar (.signed .i32)) 0 0, zero]
private def emptyFunctions : Value := source_value Extracted.«ir::function_catalog».Types.«Table».mk
  [emptySlice 25, zero, emptySlice 24, zero]
private def emptyBodies : Value := source_value Extracted.«ir::body_catalog».Types.«Catalog».mk
  [.rawSlice bodyType 0 0, .rawSlice (.structure countId) 0 0, zero]
private def emptyTokens : Value := source_value Extracted.«verified::token».Types.«TokenTable».mk
  [emptySlice 195, zero, .pointer 0]
private def emptyNames : Value := source_value Extracted.«ir::symbol_catalog».Types.«Catalog».mk
  [.rawSlice (.scalar (.signed .i32)) 0 0, zero, emptyTokens, emptySlice 29, zero,
    emptySlice 30, zero, emptySlice 30, zero, emptySlice 30, zero, emptySlice 30, zero,
    emptySlice 31, zero]
def emptyProgram : Value := source_value Extracted.«ir::program».Types.«Program».mk
  [.signed .i32 (-1), emptyTypes, emptyConstants, emptyFunctions, emptyBodies, emptyNames]
def failureValue : Value := source_value Extracted.«lowering::program».Types.«LoweredProgram».mk
  [source_value Extracted.«lowering::program».Types.«LoweringStatus».«InvalidInput» [], emptyProgram]
def failureSource := Extracted.«lowering::program».Functions.«failure».core

@[core_pure_rule] private theorem typeFirstZero (width : Int) (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before
      (.call Extracted.«ir::type_catalog».Functions.«first».core.id
        [.value (.pointer 0), .value zero, .value (.signed .i32 width)]) (.pointer 0) after ∧
      PureFrame before after := by
  core_call_pure Extracted.«ir::type_catalog».Functions.«first».core as callee
  core_pure

@[core_pure_rule] private theorem functionFirstZero (width : Int) (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before
      (.call Extracted.«ir::function_catalog».Functions.«slice_first».core.id
        [.value (.pointer 0), .value zero, .value (.signed .i32 width)]) (.pointer 0) after ∧
      PureFrame before after := by
  core_call_pure Extracted.«ir::function_catalog».Functions.«slice_first».core as callee
  core_pure

@[core_pure_rule] private theorem symbolFirstZero (width : Int) (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before
      (.call Extracted.«ir::symbol_catalog».Functions.«first».core.id
        [.value (.pointer 0), .value zero, .value (.signed .i32 width)]) (.pointer 0) after ∧
      PureFrame before after := by
  core_call_pure Extracted.«ir::symbol_catalog».Functions.«first».core as callee
  core_pure

@[core_pure_rule] private theorem typesZero (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before
      (.call Extracted.«ir::type_catalog».Functions.«from_raw_parts».core.id
        [.value (.pointer 0), .value zero, .value zero, .value zero]) emptyTypes after ∧
      PureFrame before after := by
  core_call_pure Extracted.«ir::type_catalog».Functions.«from_raw_parts».core as callee
  core_pure

@[core_pure_rule] private theorem typesEmpty (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before (.call Extracted.«ir::type_catalog».Functions.«empty».core.id [])
      emptyTypes after ∧ PureFrame before after := by
  core_call_pure Extracted.«ir::type_catalog».Functions.«empty».core as callee
  core_pure

@[core_pure_rule] private theorem constantsZero (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before
      (.call Extracted.«ir::constant_catalog».Functions.«from_raw_parts».core.id
        [.value (.pointer 0), .value zero, .value zero]) emptyConstants after ∧ PureFrame before after := by
  core_call_pure Extracted.«ir::constant_catalog».Functions.«from_raw_parts».core as callee
  core_pure

@[core_pure_rule] private theorem constantsEmpty (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before (.call Extracted.«ir::constant_catalog».Functions.«empty».core.id [])
      emptyConstants after ∧ PureFrame before after := by
  core_call_pure Extracted.«ir::constant_catalog».Functions.«empty».core as callee
  core_pure

@[core_pure_rule] private theorem functionsZero (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before
      (.call Extracted.«ir::function_catalog».Functions.«from_raw_parts».core.id
        [.value (.pointer 0), .value zero, .value zero]) emptyFunctions after ∧ PureFrame before after := by
  core_call_pure Extracted.«ir::function_catalog».Functions.«from_raw_parts».core as callee
  core_pure

@[core_pure_rule] private theorem bodiesEmpty (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before (.call Extracted.«ir::body_catalog».Functions.«empty».core.id [])
      emptyBodies after ∧ PureFrame before after := by
  core_call_pure Extracted.«ir::body_catalog».Functions.«empty».core as callee
  core_pure

@[core_pure_rule] private theorem tokensZero (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before
      (.call Extracted.«verified::token».Functions.«from_raw_parts».core.id
        [.value (.pointer 0), .value zero]) emptyTokens after ∧ PureFrame before after := by
  have tokenLayout : NativeLayout.valueWords? extractedProgram (.structure 195) = some 3 := by decide +kernel
  core_call_pure Extracted.«verified::token».Functions.«from_raw_parts».core as callee
  core_pure

@[core_pure_rule] private theorem namesZero (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before
      (.call Extracted.«ir::symbol_catalog».Functions.«from_raw_parts».core.id
        [.value (.pointer 0), .value (.rawSlice (.scalar (.signed .i32)) 0 0), .value zero,
          .value emptyTokens, .value zero, .value zero, .value zero, .value zero, .value zero, .value zero])
      emptyNames after ∧ PureFrame before after := by
  have unitLayout : NativeLayout.valueWords? extractedProgram (.structure 29) = some 7 := by decide +kernel
  have refLayout : NativeLayout.valueWords? extractedProgram (.structure 30) = some 2 := by decide +kernel
  have nameLayout : NativeLayout.valueWords? extractedProgram (.structure 31) = some 3 := by decide +kernel
  core_call_pure Extracted.«ir::symbol_catalog».Functions.«from_raw_parts».core as callee
  repeat' (apply RunsStmt.letPure (value := .pointer 0); core_run; core_formed)
  core_pure

@[core_pure_rule] private theorem namesEmpty (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before (.call Extracted.«ir::symbol_catalog».Functions.«empty».core.id [])
      emptyNames after ∧ PureFrame before after := by
  core_call_pure Extracted.«ir::symbol_catalog».Functions.«empty».core as callee
  core_pure

@[core_pure_rule] theorem actualEmptyProgram (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before (.call Extracted.«ir::program».Functions.«empty».core.id [])
      emptyProgram after ∧ PureFrame before after := by
  core_call_pure Extracted.«ir::program».Functions.«empty».core as callee
  core_pure

private def unsupportedError : Value :=
  source_value Extracted.«lowering::error».Types.«LoweringError».«UnsupportedFeature» []

@[core_pure_rule] private theorem unsupportedCode (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before
      (.call Extracted.«lowering::error».Functions.«error_code».core.id [.value unsupportedError])
      (.signed .i32 2) after ∧ PureFrame before after := by
  core_call_pure Extracted.«lowering::error».Functions.«error_code».core as callee
  core_pure

@[core_pure_rule] private theorem unsupportedFailure (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before
      (.call Extracted.«lowering::error».Functions.«failure».core.id [.value unsupportedError])
      (.signed .i32 (-2)) after ∧ PureFrame before after := by
  core_call_pure Extracted.«lowering::error».Functions.«failure».core as callee
  core_pure

@[core_pure_rule] private theorem notUnsupported (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before
      (.call Extracted.«lowering::error».Functions.«failed_with».core.id
        [.value (.signed .i32 (-1)), .value unsupportedError]) (.boolean false) after ∧
      PureFrame before after := by
  core_call_pure Extracted.«lowering::error».Functions.«failed_with».core as callee
  core_pure

@[core_pure_rule] theorem actualFailure (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before (.call failureSource.id [.value (.signed .i32 (-1))])
      failureValue after ∧ PureFrame before after := by
  core_call_pure failureSource as callee
  apply RunsStmt.letPure
  · core_run
  · core_formed
  apply RunsStmt.guardFramedFalse
  · core_pure_expr
  intro middle frame
  apply RunsStmt.returnPure
  apply RunsExpr.structPure
  core_pure_arguments

def sizeGuard : Expr := match lowerSource.bindingStatement 15 with
  | .letLocal _ _ _ (.sequence (.ifThenElse condition _ _) _) => condition
  | _ => .value (.boolean false)
def nullGuard : Expr := match lowerSource.bindingStatement 16 with
  | .letLocal _ _ _ (.sequence (.ifThenElse condition _ _) _) => condition
  | _ => .value (.boolean false)
def failureReturn : Stmt := match lowerSource.bindingStatement 15 with
  | .letLocal _ _ _ (.sequence (.ifThenElse _ returned _) _) => returned
  | _ => .skip
def catalogSuccessTail : Stmt := match lowerSource.bindingStatement 17 with
  | .letLocal _ _ _ tail => tail
  | _ => .skip

theorem actualStageShape : lowerSource.bindingStatement 15 =
    .letLocal (lowerSource.bindingId 15) (.scalar (.signed .i32)) (lowerSource.bindingInitializer 15)
      (.sequence (.ifThenElse sizeGuard failureReturn .skip) (lowerSource.bindingStatement 16)) ∧
    lowerSource.bindingStatement 16 =
    .letLocal (lowerSource.bindingId 16) (.scalar .rawPtr) (lowerSource.bindingInitializer 16)
      (.sequence (.ifThenElse nullGuard failureReturn .skip) (lowerSource.bindingStatement 17)) ∧
    lowerSource.bindingStatement 17 =
    .letLocal (lowerSource.bindingId 17) (.structure 7) (lowerSource.bindingInitializer 17)
      catalogSuccessTail := ⟨rfl, rfl, rfl⟩

theorem actualInvalidCapacity (capacity : Int32) (bad : ¬Supported capacity)
    (required : before.local? (lowerSource.bindingId 7) = some
      (source_value Extracted.«lowering::signature_index».Types.«Requirements».mk
        [.signed .i32 capacity.toInt, members, variants, fields, constants, bytes, .boolean valid]))
    (formed : before.CellsWellFormed) : ∃ after,
    RunsStmt extractedProgram before (lowerSource.bindingStatement 15) (.returned (some failureValue)) after ∧
      PureFrame before after := by
  rw [actualStageShape.1]
  have rejected : allocationBytes capacity = -1 := by simp only [allocationBytes, if_neg bad]
  apply RunsStmt.letFramedPure
  · simpa only [rejected] using actualSizeInitializer capacity required formed
  intro sized pure
  core_pure

#print axioms actualEmptyProgram
#print axioms actualFailure
#print axioms actualStageShape
#print axioms actualInvalidCapacity

end IRCatalogConstructionProof
