import Lanius.Core
import Lanius.Data.List

namespace Lanius.TypedIR.Surface
open Lanius

/-- Source labels describe syntax; they do not certify its typing. -/
@[nospecialize] class Code (α : Type) where
  ty : Core.Ty

abbrev I32 := Int32
abbrev Usize := USize
inductive RawPtr
inductive Slice (α : Type)
instance : Code I32 := ⟨.scalar (.signed .i32)⟩
instance : Code Usize := ⟨.scalar (.unsigned .usize)⟩
instance : Code Bool := ⟨.scalar .bool⟩
instance : Code Unit := ⟨.unit⟩
instance : Code String := ⟨.scalar .string⟩
instance : Code RawPtr := ⟨.scalar .rawPtr⟩
instance [Code α] : Code (Slice α) := ⟨.slice (Code.ty α)⟩

structure Var (α : Type) where
  id : VarId
  name : String
def Var.named (id : VarId) (name : String) : Var α := ⟨id, name⟩

inductive Vars : List Type → Type 1 where
  | nil : Vars []
  | cons [Code α] (head : Var α) (tail : Vars types) : Vars (α :: types)
def Vars.parameters : Vars types → List (VarId × Core.Ty)
  | .nil => []
  | @Vars.cons α _ _ head tail => (head.id, Code.ty α) :: tail.parameters
def Vars.patterns (bindings : Vars types) : List Core.Pattern :=
  bindings.parameters.map (fun binding => .bind binding.1)

/-- Phantom labels support notation. Stored syntax has no scope, signature,
    or proof indices, and the label is not a Lanius typing guarantee. -/
structure Expr (α : Type) where
  core : Core.Expr
structure Place (α : Type) where
  core : Core.Place

/-- Argument types are checked by Lanius, not by constructing this list. -/
structure Args where
  values : List Core.Expr
def Args.nil : Args := ⟨[]⟩
def Args.cons (head : Expr α) (tail : Args) : Args := ⟨head.core :: tail.values⟩

def Expr.i32 (value : Nat) : Expr I32 := ⟨.value (.signed .i32 value)⟩
def Expr.bool (value : Bool) : Expr Bool := ⟨.value (.boolean value)⟩
def Expr.string (value : String) : Expr String := ⟨.value (.string value)⟩
def Expr.local (binding : Var α) : Expr α := ⟨.local binding.id⟩
def Place.local (binding : Var α) : Place α := ⟨.local binding.id⟩
def Expr.binary (op : Core.BinaryOp) (left : Expr α) (right : Expr β) : Expr α :=
  ⟨.binary op left.core right.core⟩
def Expr.add (left : Expr α) (right : Expr β) : Expr α := Expr.binary .add left right
def Expr.subtract (left : Expr α) (right : Expr β) : Expr α := Expr.binary .subtract left right
def Expr.multiply (left : Expr α) (right : Expr β) : Expr α := Expr.binary .multiply left right
def Expr.divide (left : Expr α) (right : Expr β) : Expr α := Expr.binary .divide left right
def Expr.remainder (left : Expr α) (right : Expr β) : Expr α := Expr.binary .remainder left right
def Expr.compare (op : Core.BinaryOp) (left : Expr α) (right : Expr β) : Expr Bool :=
  ⟨.binary op left.core right.core⟩
def Expr.equal (left : Expr α) (right : Expr β) : Expr Bool := Expr.compare .equal left right
def Expr.notEqual (left : Expr α) (right : Expr β) : Expr Bool := Expr.compare .notEqual left right
def Expr.less (left : Expr α) (right : Expr β) : Expr Bool := Expr.compare .less left right
def Expr.lessEqual (left : Expr α) (right : Expr β) : Expr Bool := Expr.compare .lessEqual left right
def Expr.greater (left : Expr α) (right : Expr β) : Expr Bool := Expr.compare .greater left right
def Expr.greaterEqual (left : Expr α) (right : Expr β) : Expr Bool := Expr.compare .greaterEqual left right
def Expr.logicalAnd (left : Expr α) (right : Expr β) : Expr Bool := Expr.compare .logicalAnd left right
def Expr.logicalOr (left : Expr α) (right : Expr β) : Expr Bool := Expr.compare .logicalOr left right
def Expr.logicalNot (value : Expr α) : Expr Bool := ⟨.unary .logicalNot value.core⟩
def Expr.positive (value : Expr α) : Expr α := ⟨.unary .positive value.core⟩
def Expr.negate (value : Expr α) : Expr α := ⟨.unary .negate value.core⟩

structure Variant (α : Type) (payload : List Type) where
  typeId : TypeId
  ordinal : VariantId
def Expr.variant (constructor : Variant α payload) (values : Args) : Expr α :=
  ⟨.enumValue constructor.typeId constructor.ordinal values.values⟩

structure Arm (α result : Type) where
  pattern : Core.Pattern
  body : Core.Expr
def Arm.variant (constructor : Variant α payload) (bindings : Vars payload)
    (body : Expr result) : Arm α result :=
  ⟨.enumVariant constructor.typeId constructor.ordinal bindings.patterns, body.core⟩
def Arm.wildcard (body : Expr result) : Arm α result := ⟨.wildcard, body.core⟩
def Expr.matchValue (scrutinee : Expr α) (head : Arm α result)
    (tail : List (Arm α result)) : Expr result :=
  ⟨.matchValue scrutinee.core ((head :: tail).map (fun arm => (arm.pattern, arm.body)))⟩

abbrev Stmt := Core.Stmt
def Stmt.skip : Stmt := Core.Stmt.skip
def Stmt.returnValue (value : Expr α) : Stmt := Core.Stmt.returnValue (some value.core)
def Stmt.returnUnit : Stmt := Core.Stmt.returnValue none
def Stmt.expression (value : Expr α) : Stmt := Core.Stmt.expression value.core
def Stmt.sequence (first second : Stmt) : Stmt := Core.Stmt.sequence first second
def Stmt.letLocal [Code α] (binding : Var α) (initializer : Expr α) (body : Stmt) : Stmt :=
  Core.Stmt.letLocal binding.id (Code.ty α) initializer.core body
def Stmt.letUninitialized [Code α] (binding : Var α) (body : Stmt) : Stmt :=
  Core.Stmt.letUninitialized binding.id (Code.ty α) body
def Stmt.ifThenElse (condition : Expr α) (first second : Stmt) : Stmt :=
  Core.Stmt.ifThenElse condition.core first second
def Stmt.whileLoop (condition : Expr α) (body : Stmt) : Stmt := Core.Stmt.whileLoop condition.core body

structure Function (parameters : List Type) (result : Type) where
  name : String
  core : Core.Function
def Function.external [Code result] (id : FunctionId) (name : String)
    (arguments : Vars parameters) (behavior : Core.ExternalBehavior) : Function parameters result :=
  ⟨name,
    { id, parameters := arguments.parameters, returnType := Code.ty result,
      body := none, external := some behavior }⟩
def Function.pack (function : Function parameters result) : Core.Function := function.core

end Lanius.TypedIR.Surface
