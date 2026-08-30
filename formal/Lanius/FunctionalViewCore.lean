import Lanius.FunctionalView

namespace Lanius.FunctionalView.Core

open Lanius
open Lanius.Core
open Lanius.FunctionalView

/-! # Structural Core adapter

The operation records retain resolved operand and result types for intrinsic
Functional View typing. Conversion erases those witnesses and reconstructs ordinary
Core expressions. Local allocation is a Core-representation concern: Functional View references are
`Fin` indices, while `toCoreStmt` assigns consecutive Core local IDs beginning
at a caller-selected fresh base.
-/

inductive Operation where
  | cast (source target : ScalarTy)
  | unary (operation : UnaryOp) (input output : Ty)
  | binary (operation : BinaryOp) (left right output : Ty)
  | index (base index element : Ty)
  | structValue (typeId : TypeId) (fields : List Ty)
  | field (base : Ty) (field : FieldId) (result : Ty)
  | constant (id : ConstantId) (type : Ty)
  | call (function : FunctionId) (arguments : List Ty) (result : Ty)
deriving DecidableEq, Repr

def Operation.operandTypes : Operation → List Ty
  | .cast source _ => [.scalar source]
  | .unary _ input _ => [input]
  | .binary _ left right _ => [left, right]
  | Operation.index base indexType _ => [base, indexType]
  | .structValue _ fields => fields
  | .field base _ _ => [base]
  | .constant _ _ => []
  | .call _ arguments _ => arguments

def Operation.resultType : Operation → Ty
  | .cast _ target => .scalar target
  | .unary _ _ output => output
  | .binary _ _ _ output => output
  | Operation.index _ _ element => element
  | .structValue typeId _ => .structure typeId
  | .field _ _ result => result
  | .constant _ type => type
  | .call _ _ result => result

def Operation.effect : Operation → EffectClass
  | Operation.index _ _ _ | .constant _ _ => .read
  | .call _ _ _ => .external
  | _ => .pure

def signature : Signature := {
  Op := Operation
  operandTypes := Operation.operandTypes
  resultType := Operation.resultType
  effect := Operation.effect
}

abbrev Layout (arity : Nat) := Fin arity → VarId

def Layout.push (layout : Layout arity) (id : VarId) : Layout (arity + 1) :=
  fun index =>
    if before : index.val < arity then
      layout ⟨index.val, before⟩
    else
      id

def refToCoreExpr (layout : Layout arity) : Ref arity → Expr
  | .slot index => .local (layout index)
  | .literal value => .value value

def Operation.toCoreExpr : Operation → List Expr → Expr
  | .cast _ target, [operand] => .cast target operand
  | .unary operation _ _, [operand] => .unary operation operand
  | .binary operation _ _ _, [left, right] => .binary operation left right
  | Operation.index _ _ _, [base, indexExpression] =>
      .index base indexExpression
  | .structValue typeId _, fields => .structValue typeId fields
  | .field _ fieldId _, [base] => .field base fieldId
  | .constant id _, [] => .constant id
  | .call function _ _, arguments => .call function arguments
  | _, _ => .value .unit

mutual

  def toCoreExpr (layout : Layout arity) :
      Term signature arity → Expr
    | .reference reference => refToCoreExpr layout reference
    | .apply operation arguments =>
        operation.toCoreExpr (toCoreExprs layout arguments)
    | .logicalAnd left right =>
        .binary .logicalAnd (toCoreExpr layout left) (toCoreExpr layout right)
    | .logicalOr left right =>
        .binary .logicalOr (toCoreExpr layout left) (toCoreExpr layout right)

  def toCoreExprs (layout : Layout arity) :
      List (Term signature arity) → List Expr
    | [] => []
    | argument :: arguments =>
        toCoreExpr layout argument :: toCoreExprs layout arguments

end

/-- Number of Core local IDs required along one execution path. Branches may
    reuse IDs because their lexical scopes are disjoint. -/
def localCapacity : Block signature arity → Nat
  | .skip | .returnValue _ => 0
  | .sequence first second => localCapacity first + localCapacity second
  | .letValue _ _ body => 1 + localCapacity body
  | .ifThenElse _ thenBranch elseBranch =>
      max (localCapacity thenBranch) (localCapacity elseBranch)

/-- Deterministic conversion back to Core. `nextLocal` must be fresh relative to the supplied
    layout; the simulation theorem states that condition explicitly. -/
def toCoreStmt (layout : Layout arity) (nextLocal : VarId) :
    Block signature arity → Stmt
  | .skip => .skip
  | .sequence first second =>
      .sequence (toCoreStmt layout nextLocal first)
        (toCoreStmt layout (nextLocal + localCapacity first) second)
  | .letValue type initializer body =>
      .letLocal nextLocal type (toCoreExpr layout initializer)
        (toCoreStmt (Layout.push layout nextLocal) (nextLocal + 1) body)
  | .ifThenElse condition thenBranch elseBranch =>
      .ifThenElse (toCoreExpr layout condition)
        (toCoreStmt layout nextLocal thenBranch)
        (toCoreStmt layout nextLocal elseBranch)
  | .returnValue none => .returnValue none
  | .returnValue (some value) =>
      .returnValue (some (toCoreExpr layout value))

def identityLayout : Layout arity := fun index => index.val

def reference (index : Fin arity) : Term signature arity :=
  .reference (.slot index)

def literal (value : Value) : Term signature arity :=
  .reference (.literal value)

def apply (operation : Operation)
    (arguments : List (Term signature arity)) : Term signature arity :=
  .apply operation arguments

def logicalAnd (left right : Term signature arity) : Term signature arity :=
  .logicalAnd left right

def logicalOr (left right : Term signature arity) : Term signature arity :=
  .logicalOr left right

end Lanius.FunctionalView.Core
