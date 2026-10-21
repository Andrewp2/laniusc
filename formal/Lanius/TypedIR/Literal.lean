import Lanius.TypedIR.Signature
import Lanius.TypedIR.Scope

namespace Lanius.TypedIR.Intrinsic

open Lanius Core Typing

/-- Only machine-domain scalar literals can enter source syntax. Runtime cell
    identities, references and raw slices are not literal constructors. -/
inductive Literal (target : Target) : Core.Ty → Type where
  | unit : Literal target .unit
  | boolean (value : Bool) : Literal target (.scalar .bool)
  | signed (width : SignedIntTy) (value : Int)
      (lower : signedMin target width ≤ value) (upper : value ≤ signedMax target width) :
      Literal target (.scalar (.signed width))
  | unsigned (width : UnsignedIntTy) (value : Nat) (upper : value ≤ unsignedMax target width) :
      Literal target (.scalar (.unsigned width))
  | f32Bits (bits : UInt32) : Literal target (.scalar .f32)
  | f64Bits (bits : UInt64) : Literal target (.scalar .f64)
  | character (value : UInt32) : Literal target (.scalar .char)
  | string (value : String) : Literal target (.scalar .string)
  | pointer (address : Address) : Literal target (.scalar .rawPtr)

def Literal.erase : Literal target type → Core.Value
  | .unit => .unit
  | .boolean value => .boolean value
  | .signed width value _ _ => .signed width value
  | .unsigned width value _ => .unsigned width value
  | .f32Bits bits => .f32Bits bits
  | .f64Bits bits => .f64Bits bits
  | .character value => .character value
  | .string value => .string value
  | .pointer address => .pointer address

theorem Literal.wellTyped (literal : Literal program.target type) :
    ValueHasType program literal.erase type := by
  cases literal <;> constructor <;> assumption

theorem Literal.isLiteral (literal : Literal target type) : Typing.Value.isLiteral literal.erase = true := by
  cases literal <;> rfl

structure Constant (target : Target) where
  id : ConstantId
  type : Core.Ty
  value : Literal target type

def Constant.erase (constant : Constant target) : Core.Constant :=
  ⟨constant.id, constant.type, constant.value.erase⟩

theorem constants_wellTyped (program : Core.Program) (constants : List (Constant program.target))
    (same : program.constants = Data.List.map Constant.erase constants) :
    ∀ constant ∈ program.constants, ConstantWellTyped program constant := by
  intro constant member
  rw [same, Data.List.map_eq] at member
  obtain ⟨source, _, rfl⟩ := List.mem_map.mp member
  exact source.value.wellTyped

/-- A resolved reference checks its identity against the signature once. It
    can be reused by every call, including recursive and mutually recursive calls. -/
structure FunctionRef (signature : Signature) (parameters : List Core.Ty) (result : Core.Ty) where
  id : FunctionId
  found : signature.function? id = some ⟨id, parameters, result⟩

structure StructRef (signature : Signature) (typeId : TypeId) (fields : List Core.Ty) where
  declaration : StructDecl
  found : signature.declarations.structure? typeId = some declaration
  fieldsMatch : declaration.fields = fields

structure VariantRef (signature : Signature) (typeId : TypeId) (payload : List Core.Ty) where
  ordinal : VariantId
  declaration : EnumDecl
  found : signature.declarations.enumeration? typeId = some declaration
  payloadMatch : declaration.variants[ordinal]? = some payload

structure ConstantRef (signature : Signature) (type : Core.Ty) where
  id : ConstantId
  found : (signature.declarations.constant? id).map Core.Constant.type = some type

structure Local (context : Scope) (type : Core.Ty) where
  id : VarId
  found : context id type

mutual
  inductive Pattern (signature : Signature) : Core.Ty → List (VarId × Core.Ty) → Type where
    | wildcard : Pattern signature type []
    | bind (id : VarId) : Pattern signature type [(id, type)]
    | literal (value : Literal signature.target type) : Pattern signature type []
    | variant (constructor : VariantRef signature typeId types)
        (payload : Patterns signature types bindings) : Pattern signature (.enumeration typeId) bindings

  inductive Patterns (signature : Signature) : List Core.Ty → List (VarId × Core.Ty) → Type where
    | nil : Patterns signature [] []
    | cons (head : Pattern signature type headBindings) (tail : Patterns signature types tailBindings) :
        Patterns signature (type :: types) (headBindings ++ tailBindings)
end

mutual
  def Pattern.erase : Pattern signature type bindings → Core.Pattern
    | .wildcard => .wildcard
    | .bind id => .bind id
    | .literal value => .literal value.erase
    | .variant (typeId := typeId) constructor payload => .enumVariant typeId constructor.ordinal payload.erase

  def Patterns.erase : Patterns signature types bindings → List Core.Pattern
    | .nil => []
    | .cons head tail => head.erase :: tail.erase
end

mutual
  theorem Pattern.wellTyped (pattern : Pattern signature type bindings)
      (linked : signature.Realizes program) : PatternHasType program pattern.erase type bindings :=
    match pattern with
    | .wildcard => .wildcard
    | .bind id => .bind id
    | .literal value => .literal (linked.value (value.wellTyped (program := signature.declarations)))
    | .variant constructor payload => .enumVariant constructor.declaration
        (linked.enumeration constructor.found) constructor.payloadMatch (payload.wellTyped linked)

  theorem Patterns.wellTyped (patterns : Patterns signature types bindings)
      (linked : signature.Realizes program) : PatternsHaveTypes program patterns.erase types bindings :=
    match patterns with
    | .nil => .nil
    | .cons head tail => .cons (head.wellTyped linked) (tail.wellTyped linked)
end

end Lanius.TypedIR.Intrinsic
