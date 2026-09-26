import Lanius.TypedIR.Checked

namespace Lanius.TypedIR.Named

open Lanius

/-- A Lean source type has one semantic Core type. The generated instances are
    checked by the kernel and the linked program is checked by `link`. -/
class Code (α : Type) where
  ty : Core.Ty

abbrev I32 := Int32
instance : Code I32 where ty := .scalar (.signed .i32)
instance : Code Bool where ty := .scalar .bool
instance : Code Unit where ty := .unit

abbrev Usize := USize
instance : Code Usize where ty := .scalar (.unsigned .usize)
instance : Code String where ty := .scalar .string

inductive RawPtr
instance : Code RawPtr where ty := .scalar .rawPtr

inductive Slice (α : Type)
instance [Code α] : Code (Slice α) where ty := .slice (Code.ty α)

structure Var (α : Type) where
  id : VarId
  name : String
  code : Code α

def Var.named [Code α] (id : VarId) (name : String) : Var α :=
  ⟨id, name, inferInstance⟩

inductive Vars : List Type → Type 1 where
  | nil : Vars []
  | cons {α : Type} (head : Var α) (tail : Vars types) :
      Vars (α :: types)

def Vars.parameters : {types : List Type} → Vars types → List (VarId × Core.Ty)
  | _, .nil => []
  | _, .cons head tail => (head.id, head.code.ty) :: tail.parameters

def Vars.patterns : {types : List Type} → Vars types → List Core.Pattern
  | _, .nil => []
  | _, .cons head tail => .bind head.id :: tail.patterns

structure Variant (α : Type) (payloadTypes : List Type) where
  typeId : TypeId
  ordinal : VariantId
  name : String
  code : Code α
  sameType : code.ty = .enumeration typeId

def Variant.named [Code α] (typeId : TypeId) (ordinal : VariantId)
    (name : String) (sameType : Code.ty α = .enumeration typeId) :
    Variant α payloadTypes :=
  ⟨typeId, ordinal, name, inferInstance, sameType⟩

structure Expr (α : Type) where
  core : Core.Expr

def Expr.i32 (value : Int) : Expr I32 :=
  ⟨.value (.signed .i32 value)⟩

def Expr.local (binding : Var α) : Expr α :=
  ⟨.local binding.id⟩

def Expr.add (left right : Expr I32) : Expr I32 :=
  ⟨.binary .add left.core right.core⟩

def Expr.subtract (left right : Expr I32) : Expr I32 :=
  ⟨.binary .subtract left.core right.core⟩

def Expr.multiply (left right : Expr I32) : Expr I32 :=
  ⟨.binary .multiply left.core right.core⟩

inductive Args : List Type → Type 1 where
  | nil : Args []
  | cons {α : Type} (head : Expr α) (tail : Args types) :
      Args (α :: types)

def Args.core : {types : List Type} → Args types → List Core.Expr
  | _, .nil => []
  | _, .cons head tail => head.core :: tail.core

def Expr.variant (constructor : Variant α payloadTypes)
    (payload : Args payloadTypes) : Expr α :=
  ⟨.enumValue constructor.typeId constructor.ordinal payload.core⟩

structure Arm (α result : Type) where
  pattern : Core.Pattern
  body : Expr result

def Arm.variant
    (constructor : Variant α payloadTypes)
    (bindings : Vars payloadTypes) (body : Expr result) : Arm α result :=
  ⟨.enumVariant constructor.typeId constructor.ordinal bindings.patterns,
    body⟩

def Arm.wildcard
    (body : Expr result) : Arm α result :=
  ⟨.wildcard, body⟩

def Arm.core
    (arm : Arm α result) : Core.Pattern × Core.Expr :=
  (arm.pattern, arm.body.core)

def Expr.matchValue
    (scrutinee : Expr α) (arms : List (Arm α result)) : Expr result :=
  ⟨.matchValue scrutinee.core (arms.map Arm.core)⟩

structure Stmt (result : Type) where
  core : Core.Stmt

def Stmt.letLocal
    (binding : Var α) (initializer : Expr α)
    (body : Stmt result) : Stmt result :=
  ⟨.letLocal binding.id binding.code.ty initializer.core body.core⟩

def Stmt.returnValue
    (value : Expr result) : Stmt result :=
  ⟨.returnValue (some value.core)⟩

structure Function (parameters : List Type) (result : Type)
    [Code result] where
  id : FunctionId
  name : String
  arguments : Vars parameters
  body : Option (Stmt result)
  external : Option Core.ExternalBehavior := none

def Function.core [Code result]
    (function : Function parameters result) : Core.Function :=
  { id := function.id, parameters := function.arguments.parameters,
    returnType := Code.ty result, body := function.body.map Stmt.core,
    external := function.external }

structure AnyFunction where
  core : Core.Function

def Function.pack [Code result]
    (function : Function parameters result) : AnyFunction :=
  ⟨function.core⟩

def assemble (declarations : Core.Program)
    (functions : List AnyFunction) : Core.Program :=
  { declarations with functions := functions.map AnyFunction.core }

end Lanius.TypedIR.Named
