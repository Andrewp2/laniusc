import Lanius.X86.LiteralReturn
import Lanius.X86.ParameterReturn
import Lanius.X86.ScalarComposite
import Lanius.X86.ExpressionFunctionCheck

namespace Lanius.X86.FunctionCheck

open Lanius Lanius.Core
open Lanius.X86

def expressionAllocationCount : Core.Expr → Nat
  | .binary _ left right => expressionAllocationCount left + 1 + expressionAllocationCount right
  | .unary _ operand => expressionAllocationCount operand
  | _ => 0

def statementAllocationCount : Stmt → Nat
  | .skip => 0
  | .expression expression => expressionAllocationCount expression
  | .ifThenElse condition .skip .skip => expressionAllocationCount condition
  | .sequence first second => max (statementAllocationCount first)
      (statementAllocationCount second)
  | .returnValue (some expression) => expressionAllocationCount expression
  | .letLocal _ _ initializer _ => max 1 (expressionAllocationCount initializer)
  | _ => 0

def functionAllocationCount (entry : Function) : Nat :=
  match entry.body with
  | some source => statementAllocationCount source
  | _ => 0

theorem expression_allocation_count_eq {source : Core.Expr}
    (shape : ExpressionCheck.Shape source) :
    expressionAllocationCount source = shape.allocations := by
  induction shape with
  | lit => rfl
  | unary _ _ operand operandIH =>
      simp [ExpressionCheck.Shape.allocations, expressionAllocationCount, operandIH]
  | binary _ _ _ _ _ left right leftIH rightIH =>
      simp [ExpressionCheck.Shape.allocations, expressionAllocationCount,
        leftIH, rightIH]

theorem statement_shape_allocation_count_eq {source : Stmt}
    (shape : StatementCheck.StatementShape source) :
    statementAllocationCount source = shape.allocations := by
  induction shape with
  | skip => rfl
  | expr expression =>
      simp [statementAllocationCount, StatementCheck.StatementShape.allocations,
        expression_allocation_count_eq expression.checked.1]
  | ifThenElse conditionCertificate _ _ =>
      simp [statementAllocationCount, StatementCheck.StatementShape.allocations,
        expression_allocation_count_eq conditionCertificate.checked.1]
  | sequence left right leftIH rightIH =>
      simp [statementAllocationCount, StatementCheck.StatementShape.allocations,
        leftIH, rightIH]

theorem body_allocation_count_eq {source : Stmt}
    (shape : ExpressionFunctionCheck.BodyShape source) :
    statementAllocationCount source = shape.allocations := by
  induction shape with
  | terminal expression =>
      simp [statementAllocationCount, ExpressionFunctionCheck.BodyShape.allocations,
        expression_allocation_count_eq expression.checked.1]
  | sequence head tail tailIH =>
      simp [statementAllocationCount, ExpressionFunctionCheck.BodyShape.allocations,
        statement_shape_allocation_count_eq head, tailIH]
  | letLocal initializerShape initializerI32 =>
      simp [statementAllocationCount, ExpressionFunctionCheck.BodyShape.allocations,
        expression_allocation_count_eq initializerShape.checked.1]

def literalOfValue? (value : Value) :
    Option { literal : LiteralReturn.Literal // literal.value = value } :=
  match value with
  | .signed .i32 number =>
      if bounds : -2147483648 ≤ number ∧ number < 2147483648 then
        some ⟨.i32 (BitVec.ofInt 32 number), by
          simp [LiteralReturn.Literal.value,
            LiteralReturn.i32_ofInt_toInt number bounds.1 bounds.2]⟩
      else none
  | .boolean value =>
      some ⟨.bool value, by simp [LiteralReturn.Literal.value]⟩
  | _ => none

private def literalShape (function : Function) :
    Option (LiteralReturn.Supported function) :=
  match function with
  | ⟨id, parameters, returnType,
      some (.returnValue (some (.value value))), none⟩ =>
      match literalOfValue? value with
      | some ⟨literal, literalValue⟩ =>
          if hId : id < 2147483648 then
            if hParams : parameters = [] then
              if hReturn : returnType = literal.ty then
                some {
                  literal := literal
                  functionIdI32 := hId
                  zeroParameters := hParams
                  resultType := hReturn
                  internal := rfl
                  bodyExact := by
                    simp only [LiteralReturn.body]
                    rw [literalValue] }
              else none
            else none
          else none
      | none => none
  | _ => none

/- The backend emits the same immediate-return bytes for a literal body even
   when the source function has parameters that the body does not inspect.
   Keep this witness separate from [literalShape], whose transport contract
   authenticates the zero-parameter encoding. -/
private def literalParametersShape (function : Function) :
    Option (LiteralReturn.ParametersSupported function) :=
  match function with
  | ⟨id, _parameters, returnType,
      some (.returnValue (some (.value value))), none⟩ =>
      match literalOfValue? value with
      | some ⟨literal, literalValue⟩ =>
          if hId : id < 2147483648 then
            if hReturn : returnType = literal.ty then
              some {
                literal := literal
                functionIdI32 := hId
                resultType := hReturn
                internal := rfl
                bodyExact := by
                  simp only [LiteralReturn.body]
                  rw [literalValue] }
            else none
          else none
      | none => none
  | _ => none

private def literalParametersTrailingShape (function : Function) :
    Option (LiteralReturn.ParametersTrailingSupported function) :=
  match function with
  | ⟨id, _parameters, returnType,
      some (.sequence (.returnValue (some (.value value))) .skip), none⟩ =>
      match literalOfValue? value with
      | some ⟨literal, literalValue⟩ =>
          if hId : id < 2147483648 then
            if hReturn : returnType = literal.ty then
              some {
                literal := literal
                functionIdI32 := hId
                resultType := hReturn
                internal := rfl
                bodyExact := by
                  simp only [LiteralReturn.trailingBody, LiteralReturn.body]
                  rw [literalValue] }
            else none
          else none
      | none => none
  | _ => none

private def literalTrailingShape (function : Function) :
    Option (LiteralReturn.TrailingSupported function) :=
  match function with
  | ⟨id, parameters, returnType,
      some (.sequence (.returnValue (some (.value value))) .skip), none⟩ =>
      match literalOfValue? value with
      | some ⟨literal, literalValue⟩ =>
          if hId : id < 2147483648 then
            if hParams : parameters = [] then
              if hReturn : returnType = literal.ty then
                some {
                  literal := literal
                  functionIdI32 := hId
                  zeroParameters := hParams
                  resultType := hReturn
                  internal := rfl
                  bodyExact := by
                    simp only [LiteralReturn.trailingBody, LiteralReturn.body]
                    rw [literalValue] }
              else none
            else none
          else none
      | none => none
  | _ => none

/- Return the first parameter whose ID is [id], retaining the dependent index
   and the equality needed to authenticate the Core local expression. -/
def parameterPosition? (parameters : List (VarId × Ty)) (id : VarId) :
    Option { position : Fin parameters.length // (parameters.get position).1 = id } :=
  match parameters with
  | [] => none
  | parameter :: rest =>
      if h : parameter.1 = id then
        some ⟨⟨0, by simp⟩, by simp [h]⟩
      else
        match parameterPosition? rest id with
        | none => none
        | some ⟨position, positionId⟩ =>
            some ⟨⟨position.val + 1, by simp [position.isLt]⟩, by
              simpa using positionId⟩
termination_by parameters.length

private def parameterShape (function : Function) :
    Option (ParameterReturn.Supported function) :=
  match function with
  | ⟨id, parameters, returnType,
      some (.returnValue (some (.local localId))), none⟩ =>
      parameterSupported id parameters returnType localId false
  | ⟨id, parameters, returnType,
      some (.sequence (.returnValue (some (.local localId))) .skip), none⟩ =>
      parameterSupported id parameters returnType localId true
  | _ => none
where
  parameterSupported (id : FunctionId) (parameters : List (VarId × Ty))
      (returnType : Ty) (localId : VarId) (trailing : Bool) :
      Option (ParameterReturn.Supported ⟨id, parameters, returnType,
        some (if trailing then
          .sequence (.returnValue (some (.local localId))) .skip
        else .returnValue (some (.local localId))), none⟩) :=
    match parameterPosition? parameters localId with
    | none => none
    | some ⟨position, positionId⟩ =>
        if atMostSix : parameters.length ≤ 6 then
          if allI32 : ∀ parameter ∈ parameters,
              parameter.2 = .scalar (.signed .i32) then
            if distinct : (parameters.map Prod.fst).Nodup then
              if bounded : ∀ parameter ∈ parameters,
                  parameter.1 ≤ 2147483647 then
                if functionBound : id ≤ 2147483647 then
                  if resultI32 : returnType = .scalar (.signed .i32) then
                    some {
                      position := position
                      atMostSix := atMostSix
                      allI32 := allI32
                      parameterIdsDistinct := distinct
                      parameterIdsBound := bounded
                      functionIdBound := functionBound
                      resultI32 := resultI32
                      internal := rfl
                      trailingSkip := trailing
                      bodyExact := by
                        cases trailing <;> simp [ParameterReturn.body]
                        · exact positionId.symm
                        · exact positionId.symm }
                  else none
                else none
              else none
            else none
          else none
        else none

/- Successful checking retains the exact relation required by the existing
   preservation theorems.  This is a sum because the two supported fragments
   have different source and machine contracts. -/
inductive Checked (function : Function) (emitted : List UInt8) where
  | literal (supported : LiteralReturn.Supported function)
      (bytesExact : emitted = LiteralReturn.bytes supported.literal)
  | literalParameters (supported : LiteralReturn.ParametersSupported function)
      (bytesExact : emitted = LiteralReturn.bytes supported.literal)
  | literalParametersTrailing
      (supported : LiteralReturn.ParametersTrailingSupported function)
      (bytesExact : emitted = LiteralReturn.bytes supported.literal)
  | literalTrailing (supported : LiteralReturn.TrailingSupported function)
      (bytesExact : emitted = LiteralReturn.bytes supported.literal)
  | parameter (supported : ParameterReturn.Supported function)
      (bytesExact : emitted = ParameterReturn.bytes supported.argument)
  | body (supported : ExpressionFunctionCheck.BodySupported function emitted)

def Checked.Authenticated (checked : Checked function emitted) : Prop :=
    match checked with
    | .literal supported _bytesExact =>
        emitted = LiteralReturn.bytes supported.literal
    | .literalParameters supported _bytesExact =>
        emitted = LiteralReturn.bytes supported.literal
    | .literalParametersTrailing supported _bytesExact =>
        emitted = LiteralReturn.bytes supported.literal
    | .literalTrailing supported _bytesExact =>
        emitted = LiteralReturn.bytes supported.literal
    | .parameter supported _bytesExact =>
        emitted = ParameterReturn.bytes supported.argument
    | .body supported =>
        emitted = ExpressionFunctionCheck.bodyFunctionBytes supported.checkedShape.1

theorem Checked.bytesExact (checked : Checked function emitted) :
    Checked.Authenticated checked := by
  cases checked with
  | literal supported bytesExact => exact bytesExact
  | literalParameters supported bytesExact => exact bytesExact
  | literalParametersTrailing supported bytesExact => exact bytesExact
  | literalTrailing supported bytesExact => exact bytesExact
  | parameter supported bytesExact => exact bytesExact
  | body supported => exact supported.checkedShape.2

theorem Checked.function_allocation_count_le
    (checked : Checked function emitted) :
    functionAllocationCount function ≤ 2^28 := by
  cases checked with
  | literal supported _ =>
      simp [functionAllocationCount, supported.bodyExact, LiteralReturn.body,
        statementAllocationCount, expressionAllocationCount]
  | literalParameters supported _ =>
      simp [functionAllocationCount, supported.bodyExact, LiteralReturn.body,
        statementAllocationCount, expressionAllocationCount]
  | literalParametersTrailing supported _ =>
      rw [functionAllocationCount, supported.bodyExact]
      simp [LiteralReturn.body, LiteralReturn.trailingBody, statementAllocationCount,
        expressionAllocationCount]
  | literalTrailing supported _ =>
      rw [functionAllocationCount, supported.bodyExact]
      simp [LiteralReturn.body, LiteralReturn.trailingBody, statementAllocationCount,
        expressionAllocationCount]
  | parameter supported _ =>
      rw [functionAllocationCount, supported.bodyExact]
      cases supported.trailingSkip <;>
        simp [ParameterReturn.body, statementAllocationCount, expressionAllocationCount]
  | body supported =>
      simp only [functionAllocationCount, supported.bodyExact]
      rw [body_allocation_count_eq]
      exact supported.allocationsBound

/- The compact backend leaves are retained here because the emitter has
   dedicated immediate-return and parameter-return paths.  Generic return
   bodies are handled by [check] below, before these leaves are considered. -/
private def checkSpecial (function : Function) (emitted : List UInt8) :
    Option (Checked function emitted) :=
  match literalShape function with
  | some supported =>
      if bytesExact : emitted = LiteralReturn.bytes supported.literal then
        some (.literal supported bytesExact)
      else none
  | none =>
      match literalParametersShape function with
      | some supported =>
          if bytesExact : emitted = LiteralReturn.bytes supported.literal then
            some (.literalParameters supported bytesExact)
          else none
      | none =>
        match literalParametersTrailingShape function with
        | some supported =>
            if bytesExact : emitted = LiteralReturn.bytes supported.literal then
              some (.literalParametersTrailing supported bytesExact)
            else none
        | none =>
            match literalTrailingShape function with
            | some supported =>
                if bytesExact : emitted = LiteralReturn.bytes supported.literal then
                  some (.literalTrailing supported bytesExact)
                else none
            | none =>
                match parameterShape function with
                | some supported =>
                    if bytesExact : emitted = ParameterReturn.bytes supported.argument then
                      some (.parameter supported bytesExact)
                    else none
                | none =>
                    none

def check (function : Function) (emitted : List UInt8) :
    Option (Checked function emitted) :=
  match ExpressionFunctionCheck.checkBody function emitted with
  | some supported => some (.body supported)
  | none => checkSpecial function emitted

theorem check_sound {function : Function} {emitted : List UInt8}
    {checked : Checked function emitted}
    (accepted : check function emitted = some checked) :
    Checked.Authenticated checked := by
  exact Checked.bytesExact checked

end Lanius.X86.FunctionCheck
