import SelfCore
import Lanius.Semantics.CallProof
import Lanius.Semantics.PureProof
import Lanius.Semantics.SourceValue

namespace IRLoweringErrorProof

open Lanius Lanius.Core Lanius.Semantics

private def errorCodeSource := Extracted.«lowering::error».Functions.«error_code».core
private def failureSource := Extracted.«lowering::error».Functions.«failure».core
private def invalidSource := Extracted.«lowering::body_context».Functions.«invalid».core
private def invalidError : Value := source_value Extracted.«lowering::error».Types.«LoweringError».«InvalidInput» []

@[core_pure_rule] theorem actualInvalidCode (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before (.call errorCodeSource.id [.value invalidError])
      (.signed .i32 1) after ∧ PureFrame before after := by
  core_call_pure errorCodeSource as callee
  core_pure

@[core_pure_rule] theorem actualInvalidFailure (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before (.call failureSource.id [.value invalidError])
      (.signed .i32 (-1)) after ∧ PureFrame before after := by
  core_call_pure failureSource as callee
  core_pure

@[core_pure_rule] theorem actualInvalid (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before (.call invalidSource.id [])
      (.signed .i32 (-1)) after ∧ PureFrame before after := by
  core_call_pure invalidSource as callee
  core_pure

end IRLoweringErrorProof
