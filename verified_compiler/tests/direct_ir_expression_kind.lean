import verified_compiler.tests.direct_ir_type_ref

namespace IRExpressionKindProof

open Lanius Lanius.Core Lanius.Semantics IRTypeRefProof

abbrev Status := Extracted.«lowering::body_expression».Types.«ExpressionStatus»
private def knownSource := Extracted.«lowering::body_expression».Functions.«known_kind».core
private def unsupportedSource := Extracted.«lowering::body_expression».Functions.«unsupported_kind».core
private def operandSource := Extracted.«lowering::body_expression».Functions.«operand_kind».core
private def typeSource := Extracted.«lowering::body_expression».Functions.«kind_type».core

def statusValue : Status → Value
  | .KnownExpression => source_value Extracted.«lowering::body_expression».Types.«ExpressionStatus».«KnownExpression» []
  | .InvalidExpression => source_value Extracted.«lowering::body_expression».Types.«ExpressionStatus».«InvalidExpression» []
  | .UnsupportedExpression => source_value Extracted.«lowering::body_expression».Types.«ExpressionStatus».«UnsupportedExpression» []

def result (status : Status) (kind : Reference) : Value :=
  source_value Extracted.«lowering::body_expression».Types.«ExpressionKind».mk
    [statusValue status, referenceValue kind]

def known := result .KnownExpression
def unsupported := result .UnsupportedExpression .Invalid

def operand (status : Status) (kind : Reference) : Value :=
  match status with
  | .KnownExpression => if isValid kind then known kind else unsupported
  | _ => result status kind

def resultType : Status → Reference → Reference
  | .KnownExpression, kind => kind
  | _, _ => .Invalid

@[core_pure_rule] theorem actualKnown (kind : Reference) (supported : isValidResult kind = true)
    (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before (.call knownSource.id [.value (referenceValue kind)])
      (known kind) after ∧ PureFrame before after := by
  core_call_pure knownSource as callee
  core_pure

@[core_pure_rule] theorem actualUnsupported (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before (.call unsupportedSource.id [])
      unsupported after ∧ PureFrame before after := by
  core_call_pure unsupportedSource as callee
  core_pure

@[core_pure_rule] theorem actualType (status : Status) (kind : Reference)
    (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before
      (.call typeSource.id [.value (result status kind)])
      (referenceValue (resultType status kind)) after ∧ PureFrame before after := by
  cases status <;> (core_call_pure typeSource as callee; core_pure)

/-- Operand positions reject non-value results, including Void, without
    rewriting existing inference failures or changing memory. -/
@[core_pure_rule] theorem actualOperand (status : Status) (kind : Reference)
    (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before
      (.call operandSource.id [.value (result status kind)])
      (operand status kind) after ∧ PureFrame before after := by
  cases status <;> dsimp only [operand]
  · split <;> (core_call_pure operandSource as callee; core_pure)
  all_goals (core_call_pure operandSource as callee; core_pure)

#print axioms actualKnown
#print axioms actualOperand

end IRExpressionKindProof
