import Lanius.Core

namespace Lanius.TypedIR

open Lanius

abbrev I32 : Core.Ty := .scalar (.signed .i32)
abbrev Ty := Core.Ty

/-- Source names are metadata; the ID is the semantic local identity. -/
structure Var (type : Ty) where
  id : VarId
  name : String

def Var.type {type : Ty} (_ : Var type) : Ty := type

inductive Vars : List Ty → Type where
  | nil : Vars []
  | cons (head : Var type) (tail : Vars types) : Vars (type :: types)

def Vars.parameters : {types : List Ty} → Vars types → List (VarId × Ty)
  | _, .nil => []
  | _, .cons head tail => (head.id, head.type) :: tail.parameters

def Vars.patterns : {types : List Ty} → Vars types → List Core.Pattern
  | _, .nil => []
  | _, .cons head tail => .bind head.id :: tail.patterns

/-- An enum constructor carries its payload types independently of numeric
    transport tags. Its existence in the program is checked by `link`. -/
structure Variant (enumId : TypeId) (payloadTypes : List Ty) where
  ordinal : VariantId
  name : String

def Variant.typeId {enumId : TypeId} {payloadTypes : List Ty}
    (_ : Variant enumId payloadTypes) : TypeId := enumId

/-- An expression retains its resolved type beside the exact Core syntax.
    Its tag is checked at the linked-program boundary, not trusted here. -/
structure Expr (type : Ty) where
  core : Core.Expr

def Expr.i32 (value : Int) : Expr I32 :=
  ⟨.value (.signed .i32 value)⟩

def Expr.local (binding : Var type) : Expr type :=
  ⟨.local binding.id⟩

inductive Args : List Ty → Type where
  | nil : Args []
  | cons (head : Expr type) (tail : Args types) : Args (type :: types)

def Args.core : {types : List Ty} → Args types → List Core.Expr
  | _, .nil => []
  | _, .cons head tail => head.core :: tail.core

def Expr.variant (constructor : Variant enumId payloadTypes)
    (payload : Args payloadTypes) : Expr (.enumeration enumId) :=
  ⟨.enumValue constructor.typeId constructor.ordinal payload.core⟩

structure Arm (enumId : TypeId) (result : Ty) where
  pattern : Core.Pattern
  body : Expr result

def Arm.variant (constructor : Variant enumId payloadTypes)
    (bindings : Vars payloadTypes) (body : Expr result) : Arm enumId result :=
  ⟨.enumVariant constructor.typeId constructor.ordinal bindings.patterns,
    body⟩

def Arm.wildcard (body : Expr result) : Arm enumId result :=
  ⟨.wildcard, body⟩

def Arm.core (arm : Arm enumId result) : Core.Pattern × Core.Expr :=
  (arm.pattern, arm.body.core)

def Expr.matchValue (scrutinee : Expr (.enumeration enumId))
    (arms : List (Arm enumId result)) : Expr result :=
  ⟨.matchValue scrutinee.core (arms.map Arm.core)⟩

structure Stmt (returnType : Ty) where
  core : Core.Stmt

def Stmt.letLocal (binding : Var type) (initializer : Expr type)
    (body : Stmt returnType) : Stmt returnType :=
  ⟨.letLocal binding.id binding.type initializer.core body.core⟩

def Stmt.returnValue (value : Expr returnType) : Stmt returnType :=
  ⟨.returnValue (some value.core)⟩

structure Function (parameters : List Ty) (result : Ty) where
  id : FunctionId
  name : String
  arguments : Vars parameters
  body : Option (Stmt result)
  external : Option Core.ExternalBehavior := none

def Function.core (function : Function parameters result) : Core.Function :=
  { id := function.id, parameters := function.arguments.parameters,
    returnType := result, body := function.body.map Stmt.core,
    external := function.external }

structure AnyFunction where
  parameters : List Ty
  result : Ty
  value : Function parameters result

def AnyFunction.core (function : AnyFunction) : Core.Function :=
  function.value.core

def Function.pack (function : Function parameters result) : AnyFunction :=
  ⟨parameters, result, function⟩

def assemble (declarations : Core.Program)
    (functions : List AnyFunction) : Core.Program :=
  { declarations with functions := functions.map AnyFunction.core }

def entryValid (core : Core.Program) (entry : FunctionId) : Bool :=
  match core.function? entry with
  | none => false
  | some function => function.parameters.isEmpty && function.body.isSome

end Lanius.TypedIR
