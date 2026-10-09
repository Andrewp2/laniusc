import verified_compiler.tests.direct_ir_shape
import Lanius.Semantics.RawSlice

namespace MatchMetadataProof

open Lanius Lanius.Core Lanius.Semantics
open IRShapeProof

private def headerSource := Extracted.«ir::body_events».Functions.«matching_fields».core
private def armSource := Extracted.«ir::body_events».Functions.«matching_arm_fields».core
private def bindingSource := Extracted.«ir::body_events».Functions.«matching_binding_fields».core
private def idSource := Extracted.«verified::lean_body_shape».Functions.«match_binding_id».core

def bindingValue (token : Int) : Value :=
  source_value Extracted.«ir::body_events».Types.«LocalReference».mk [.signed .i32 token]
def bindingEvent (token : Int) : Value :=
  source_value Extracted.«ir::body_events».Types.«Event».«MatchBinding» [bindingValue token]

/-- The match emitter's three actual payload readers. The values are related
    to existing native events, not to a second syntax or typing tree. -/
@[core_pure_rule] theorem actualHeader (result : IRTypeRefProof.Reference) (typeId count : Int)
    (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram state
      (.call headerSource.id [.value (matchEvent result typeId count)])
      (matchHeaderValue result typeId count) after ∧ PureFrame state after := by
  core_call_pure headerSource as callee
  core_pure

@[core_pure_rule] theorem actualArm (ordinal count : Int) (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram state (.call armSource.id [.value (armEvent ordinal count)])
      (armValue ordinal count) after ∧ PureFrame state after := by
  core_call_pure armSource as callee
  core_pure

@[core_pure_rule] theorem actualBinding (token : Int) (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram state (.call bindingSource.id [.value (bindingEvent token)])
      (bindingValue token) after ∧ PureFrame state after := by
  core_call_pure bindingSource as callee
  core_pure

/-- The structural validator obtains the same token through its actual wrapper. -/
theorem actualBindingId (token : Int) (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram state (.call idSource.id [.value (bindingEvent token)])
      (.signed .i32 token) after ∧ PureFrame state after := by
  core_call_pure idSource as callee
  core_pure

/-- Native binding reads compose through a real indexed argument and preserve
    heap, caller cells, locals and runtime state. No reader success is assumed. -/
theorem actualNativeBinding (token : Int) (formed : state.CellsWellFormed)
    (read : readRawSliceIndex extractedProgram state eventType address length index = .ok (bindingEvent token)) :
    ∃ after, RunsExpr extractedProgram state
      (.call bindingSource.id [.index (.value (.rawSlice eventType address length))
        (.value (.signed .i32 index))]) (bindingValue token) after ∧ PureFrame state after := by
  core_pure_expr

private theorem invalidBinding (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram state
      (.call Extracted.«ir::body_events».Functions.«invalid_local_reference».core.id [])
      (bindingValue (-1)) after ∧ PureFrame state after := by
  core_call_pure Extracted.«ir::body_events».Functions.«invalid_local_reference».core as callee
  core_pure

/-- An expression-local event is not a pattern binding, even with a valid ID. -/
theorem rejectsExpressionLocal (token : Int) (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram state (.call idSource.id [.value
      (source_value Extracted.«ir::body_events».Types.«Event».«ExpressionLocal» [bindingValue token])])
      (.signed .i32 (-1)) after ∧ PureFrame state after := by
  core_call_pure idSource as callee
  have rejected : ∃ after, RunsExpr extractedProgram callee (.call bindingSource.id [.value
      (source_value Extracted.«ir::body_events».Types.«Event».«ExpressionLocal» [bindingValue token])])
      (bindingValue (-1)) after ∧ PureFrame callee after := by
    core_call_pure bindingSource as inner
    have invalid := invalidBinding (state := inner) (by core_formed)
    core_pure
  core_pure

#print axioms actualHeader
#print axioms actualArm
#print axioms actualBinding
#print axioms actualBindingId
#print axioms actualNativeBinding
#print axioms rejectsExpressionLocal

end MatchMetadataProof
