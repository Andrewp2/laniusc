import Lanius.ProofIR

namespace Lanius.ProofIR.Core

open Lanius
open Lanius.Core
open Lanius.ProofIR

/-! # Structural Core adapter

The operation records retain resolved operand and result types for intrinsic
Proof IR typing. Lowering erases those witnesses and emits ordinary Core
expressions. Local allocation is a backend concern: Proof IR references are
`Fin` indices, while `lowerBlock` assigns consecutive Core local IDs beginning
at a caller-selected fresh base.
-/

inductive Operation where
  | cast (source target : ScalarTy)
  | unary (operation : UnaryOp) (input output : Ty)
  | binary (operation : BinaryOp) (left right output : Ty)
  | index (base index element : Ty)
  | field (base : Ty) (field : FieldId) (result : Ty)
  | constant (id : ConstantId) (type : Ty)
deriving DecidableEq, Repr

def Operation.operandTypes : Operation → List Ty
  | .cast source _ => [.scalar source]
  | .unary _ input _ => [input]
  | .binary _ left right _ => [left, right]
  | Operation.index base indexType _ => [base, indexType]
  | .field base _ _ => [base]
  | .constant _ _ => []

def Operation.resultType : Operation → Ty
  | .cast _ target => .scalar target
  | .unary _ _ output => output
  | .binary _ _ _ output => output
  | Operation.index _ _ element => element
  | .field _ _ result => result
  | .constant _ type => type

def Operation.effect : Operation → EffectClass
  | Operation.index _ _ _ | .constant _ _ => .read
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

def lowerRef (layout : Layout arity) : Ref arity → Expr
  | .slot index => .local (layout index)
  | .literal value => .value value

def Operation.lower : Operation → List Expr → Expr
  | .cast _ target, [operand] => .cast target operand
  | .unary operation _ _, [operand] => .unary operation operand
  | .binary operation _ _ _, [left, right] => .binary operation left right
  | Operation.index _ _ _, [base, indexExpression] =>
      .index base indexExpression
  | .field _ fieldId _, [base] => .field base fieldId
  | .constant id _, [] => .constant id
  | _, _ => .value .unit

mutual

  def lowerTerm (layout : Layout arity) :
      Term signature arity → Expr
    | .reference reference => lowerRef layout reference
    | .apply operation arguments =>
        operation.lower (lowerTerms layout arguments)

  def lowerTerms (layout : Layout arity) :
      List (Term signature arity) → List Expr
    | [] => []
    | argument :: arguments =>
        lowerTerm layout argument :: lowerTerms layout arguments

end

/-- Number of Core local IDs required along one execution path. Branches may
    reuse IDs because their lexical scopes are disjoint. -/
def localCapacity : Block signature arity → Nat
  | .skip | .returnValue _ => 0
  | .sequence first second => localCapacity first + localCapacity second
  | .letValue _ _ body => 1 + localCapacity body
  | .ifThenElse _ thenBranch elseBranch =>
      max (localCapacity thenBranch) (localCapacity elseBranch)

/-- Deterministic lowering. `nextLocal` must be fresh relative to the supplied
    layout; the simulation theorem states that condition explicitly. -/
def lowerBlock (layout : Layout arity) (nextLocal : VarId) :
    Block signature arity → Stmt
  | .skip => .skip
  | .sequence first second =>
      .sequence (lowerBlock layout nextLocal first)
        (lowerBlock layout (nextLocal + localCapacity first) second)
  | .letValue type initializer body =>
      .letLocal nextLocal type (lowerTerm layout initializer)
        (lowerBlock (Layout.push layout nextLocal) (nextLocal + 1) body)
  | .ifThenElse condition thenBranch elseBranch =>
      .ifThenElse (lowerTerm layout condition)
        (lowerBlock layout nextLocal thenBranch)
        (lowerBlock layout nextLocal elseBranch)
  | .returnValue none => .returnValue none
  | .returnValue (some value) =>
      .returnValue (some (lowerTerm layout value))

def identityLayout : Layout arity := fun index => index.val

def reference (index : Fin arity) : Term signature arity :=
  .reference (.slot index)

def literal (value : Value) : Term signature arity :=
  .reference (.literal value)

def apply (operation : Operation)
    (arguments : List (Term signature arity)) : Term signature arity :=
  .apply operation arguments

end Lanius.ProofIR.Core
