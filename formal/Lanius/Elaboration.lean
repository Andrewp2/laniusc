import Lanius.LiteralSyntax
import Lanius.Static
import Lanius.Typing

namespace Lanius.Elaboration

open Lanius

/-- Name and const resolution are explicit inputs to elaboration. The formal
    semantics does not inherit token IDs or lookup tables from `laniusc`. -/
structure Resolution where
  resolveTypePath : Surface.Path → Option Core.Ty
  resolveConst : Surface.Name → Option Nat

def builtinScalar? : Surface.Name → Option Core.ScalarTy
  | "bool" => some .bool
  | "i8" => some (.signed .i8)
  | "i16" => some (.signed .i16)
  | "i32" => some (.signed .i32)
  | "i64" => some (.signed .i64)
  | "isize" => some (.signed .isize)
  | "u8" => some (.unsigned .u8)
  | "u16" => some (.unsigned .u16)
  | "u32" => some (.unsigned .u32)
  | "u64" => some (.unsigned .u64)
  | "usize" => some (.unsigned .usize)
  | "f32" => some .f32
  | "f64" => some .f64
  | "char" => some .char
  | "str" => some .string
  | "ptr" => some .rawPtr
  | _ => none

def builtinTypePath? : Surface.Path → Option Core.Ty
  | { segments := [.mk name []] } => builtinScalar? name |>.map Core.Ty.scalar
  | _ => none

/-- Builtins take precedence over user resolution. This makes the primitive
    namespace part of the language specification without baking the current
    compiler's builtin name-table row numbers into the model. -/
def Resolution.withBuiltins (fallback : Resolution) : Resolution := {
  resolveTypePath := fun path => builtinTypePath? path |>.orElse (fun _ => fallback.resolveTypePath path)
  resolveConst := fallback.resolveConst
}

/-- Literal elaboration is type-directed. Unsuffixed integers default to i32
    only when no expected type exists; an expected integer type accepts the
    same literal if and only if its mathematical value is representable. -/
inductive LiteralElaborates (target : Core.Target) :
    Surface.Literal → Core.Ty → Core.Expr → Prop where
  | boolean : LiteralElaborates target (.boolean value) (.scalar .bool)
      (.value (.boolean value))
  | character : LiteralElaborates target (.character value) (.scalar .char)
      (.value (.character (UInt32.ofNat value.toNat)))
  | string : LiteralElaborates target (.string value) (.scalar .string)
      (.value (.string value))
  | signedInteger
      (parsed : parseUnsignedInteger text = some value)
      (upper : Int.ofNat value ≤ Typing.signedMax target type) :
      LiteralElaborates target (.integer text) (.scalar (.signed type))
        (.value (.signed type (Int.ofNat value)))
  | unsignedInteger
      (parsed : parseUnsignedInteger text = some value)
      (upper : value ≤ Typing.unsignedMax target type) :
      LiteralElaborates target (.integer text) (.scalar (.unsigned type))
        (.value (.unsigned type value))
  | nullPointer
      (parsed : parseUnsignedInteger text = some 0) :
      LiteralElaborates target (.integer text) (.scalar .rawPtr)
        (.value (.pointer 0))
  | f32
      (parsed : parseFloatLiteral text = some value) :
      LiteralElaborates target (.float text) (.scalar .f32)
        (.value (.f32Bits value.toFloat32.toBits))
  | f64
      (parsed : parseFloatLiteral text = some value) :
      LiteralElaborates target (.float text) (.scalar .f64)
        (.value (.f64Bits value.toBits))

/-- Literal parsing and contextual typing determine one emitted core literal.
    Proof evidence for range checks cannot change the resulting expression. -/
theorem LiteralElaborates.core_unique
    (left : LiteralElaborates target literal type leftCore)
    (right : LiteralElaborates target literal type rightCore) :
    leftCore = rightCore := by
  cases left <;> cases right
  all_goals simp_all

def literalDefaultType : Surface.Literal → Core.Ty
  | .integer _ => .scalar (.signed .i32)
  | .float _ => .scalar .f32
  | .boolean _ => .scalar .bool
  | .character _ => .scalar .char
  | .string _ => .scalar .string

/-- The magnitude of a signed minimum is one greater than the positive maximum
    and therefore cannot first elaborate as a positive value of that type.
    This rule recognizes exactly that parser shape; ordinary negative literals
    continue through unary negation. -/
inductive SignedMinimumLiteralElaborates (target : Core.Target) :
    String → Core.SignedIntTy → Core.Expr → Prop where
  | minimum
      (parsed : parseUnsignedInteger text = some magnitude)
      (exactMinimum : Int.ofNat magnitude = -(Typing.signedMin target type)) :
      SignedMinimumLiteralElaborates target text type
        (.value (.signed type (Typing.signedMin target type)))

/-- The signed-minimum parser form has one core expression. -/
theorem SignedMinimumLiteralElaborates.core_unique
    (left : SignedMinimumLiteralElaborates target text type leftCore)
    (right : SignedMinimumLiteralElaborates target text type rightCore) :
    leftCore = rightCore := by
  cases left
  cases right
  rfl

/-- The exceptional signed-minimum spelling cannot also elaborate as the
    positive literal consumed by ordinary unary negation. Its magnitude is
    exactly one greater than the largest positive value of the same type. -/
theorem SignedMinimumLiteralElaborates.not_positive_literal
    (minimum : SignedMinimumLiteralElaborates target text type minimumCore)
    (positive : LiteralElaborates target (.integer text)
      (.scalar (.signed type)) positiveCore) : False := by
  cases minimum with
  | minimum minimumParsed exactMinimum =>
      cases positive with
      | signedInteger positiveParsed upper =>
          have magnitudeEquality := Option.some.inj
            (minimumParsed.symm.trans positiveParsed)
          cases magnitudeEquality
          simp [Typing.signedMin, Typing.signedMax] at exactMinimum upper
          omega

inductive ArrayLengthElaborates
    (resolution : Resolution) : Surface.ArrayLength → Nat → Prop where
  | literal : ArrayLengthElaborates resolution (.literal length) length
  | parameter (found : resolution.resolveConst name = some length) :
      ArrayLengthElaborates resolution (.parameter name) length

inductive TypeElaborates
    (resolution : Resolution) : Surface.TypeExpr → Core.Ty → Prop where
  | path
      (found : resolution.resolveTypePath { segments } = some type) :
      TypeElaborates resolution (.path segments) type
  | array
      (element : TypeElaborates resolution surfaceElement coreElement)
      (length : ArrayLengthElaborates resolution surfaceLength coreLength) :
      TypeElaborates resolution
        (.array surfaceElement surfaceLength) (.array coreElement coreLength)
  | slice (element : TypeElaborates resolution surfaceElement coreElement) :
      TypeElaborates resolution (.slice surfaceElement) (.slice coreElement)
  | reference (referent : TypeElaborates resolution surfaceReferent coreReferent) :
      TypeElaborates resolution
        (.reference surfaceReferent) (.reference coreReferent)

/-- The subset of resolved expressions that denotes a stable place. This is
    the precise boundary used by immutable receiver borrowing; arbitrary
    temporary expressions are not silently assigned storage. -/
inductive ExprAsPlace : Core.Expr → Core.Place → Prop where
  | local (id : VarId) : ExprAsPlace (.local id) (.local id)
  | field (base : ExprAsPlace baseExpression basePlace) :
      ExprAsPlace (.field baseExpression field) (.field basePlace field)
  | index (base : ExprAsPlace baseExpression basePlace) :
      ExprAsPlace (.index baseExpression index) (.index basePlace index)

/-- The structural expression-to-place projection has one result. -/
theorem ExprAsPlace.unique
    (left : ExprAsPlace expression leftPlace)
    (right : ExprAsPlace expression rightPlace) :
    leftPlace = rightPlace := by
  induction left generalizing rightPlace with
  | «local» => cases right; rfl
  | field _ induction =>
      cases right with
      | field rightBase => cases induction rightBase; rfl
  | index _ induction =>
      cases right with
      | index rightBase => cases induction rightBase; rfl

/-- Member access automatically dereferences immutable references. It does not
    reinterpret raw pointers, and it does not create mutable access. -/
inductive MemberBaseLowers
    (monomorphization : Static.Monomorphization) :
    Static.GroundTy → Core.Expr → Static.GroundTy → Core.Expr → Prop where
  | direct : MemberBaseLowers monomorphization type expression type expression
  | reference
      (tail : MemberBaseLowers monomorphization referent
        (.dereference expression) resultType resultExpression) :
      MemberBaseLowers monomorphization (.reference referent) expression
        resultType resultExpression

/-- Number of immutable-reference layers at the head of a ground type. -/
private def memberReferenceDepth : Static.GroundTy → Nat
  | .reference referent => memberReferenceDepth referent + 1
  | _ => 0

/-- Automatic member dereference can only remove leading reference layers. -/
private theorem MemberBaseLowers.reference_depth_le
    (lowered : MemberBaseLowers monomorphization sourceType sourceExpression
      resultType resultExpression) :
    memberReferenceDepth resultType ≤ memberReferenceDepth sourceType := by
  induction lowered with
  | direct => exact Nat.le_refl _
  | reference tail induction =>
      simp only [memberReferenceDepth]
      exact Nat.le_trans induction (Nat.le_add_right _ 1)

/-- For fixed source and result types, automatic member dereference emits one
    core expression. A direct projection cannot overlap a dereferencing one:
    every dereference strictly removes a leading reference layer. -/
theorem MemberBaseLowers.core_unique
    (left : MemberBaseLowers monomorphization sourceType sourceExpression
      resultType leftResult)
    (right : MemberBaseLowers monomorphization sourceType sourceExpression
      resultType rightResult) :
    leftResult = rightResult := by
  induction left generalizing rightResult with
  | direct =>
      cases right with
      | direct => rfl
      | @reference referent expression resultType resultExpression rightTail =>
          have depth := MemberBaseLowers.reference_depth_le rightTail
          simp only [memberReferenceDepth] at depth
          omega
  | @reference referent expression resultType resultExpression tail induction =>
      cases right with
      | direct =>
          have depth := MemberBaseLowers.reference_depth_le tail
          simp only [memberReferenceDepth] at depth
          omega
      | reference rightTail => exact induction rightTail

inductive ReceiverArgumentLowers
    (monomorphization : Static.Monomorphization) :
    Static.ReceiverMode → Static.GroundTy → Core.Expr → Core.Expr → Prop where
  | value : ReceiverArgumentLowers monomorphization .value type expression expression
  | explicit : ReceiverArgumentLowers monomorphization .explicit type expression expression
  | existingReference :
      ReceiverArgumentLowers monomorphization .reference type
        (.dereference reference) reference
  | reference
      (coreType : type.toCore monomorphization = some referent)
      (place : ExprAsPlace expression resolvedPlace) :
      ReceiverArgumentLowers monomorphization .reference type expression
        (.borrow referent resolvedPlace)

/-- Receiver adaptation is functional. A syntactic dereference cannot also be
    projected as a place, so the existing-reference and freshly-borrowed cases
    are disjoint. -/
theorem ReceiverArgumentLowers.unique
    (left : ReceiverArgumentLowers monomorphization mode type expression
      leftResult)
    (right : ReceiverArgumentLowers monomorphization mode type expression
      rightResult) :
    leftResult = rightResult := by
  cases left with
  | value => cases right; rfl
  | explicit => cases right; rfl
  | existingReference =>
      cases right with
      | existingReference => rfl
      | reference _ place => cases place
  | reference leftCoreType leftPlace =>
      cases right with
      | existingReference => cases leftPlace
      | reference rightCoreType rightPlace =>
          have coreTypeEquality := Option.some.inj
            (leftCoreType.symm.trans rightCoreType)
          cases coreTypeEquality
          cases leftPlace.unique rightPlace
          rfl

/-- Once subexpressions have been elaborated and typed, a uniquely selected
    member call lowers to an ordinary core function call. `self` is simply its
    first argument; `&self` is the immutable borrow produced above. -/
inductive MethodCallLowers
    (implementations : List Static.ImplScheme)
    (methods : List Static.MethodScheme)
    (instances : List Static.MethodInstance)
    (currentModule : ModuleId)
    (monomorphization : Static.Monomorphization)
    (receiverExpression : Core.Expr) (receiverType : Static.GroundTy)
    (name : String) (argumentExpressions : List Core.Expr)
    (argumentTypes : List Static.GroundTy) : Static.GroundTy → Core.Expr → Prop where
  | call
      (selected : Static.MethodScheme)
      (resolved : Static.MethodInstance)
      (selectedUniquely : Static.ResolvesMethod implementations methods instances
        currentModule receiverType name argumentTypes selected resolved)
      (substitution : Static.Substitution)
      (instantiated : Static.MethodInstantiates implementations selected
        substitution resolved)
      (resolvedReceiver : resolved.receiverType = receiverType)
      (resolvedName : resolved.name = name)
      (resolvedArguments : resolved.argumentTypes = argumentTypes)
      (receiverArgument : Core.Expr)
      (receiver : ReceiverArgumentLowers monomorphization resolved.receiverMode
        receiverType receiverExpression receiverArgument) :
      MethodCallLowers implementations methods instances currentModule monomorphization
        receiverExpression receiverType name argumentExpressions argumentTypes
        resolved.returnType
        (.call resolved.function (receiverArgument :: argumentExpressions))

/-- A type-qualified inherent-function call has no implicit receiver
    expression. Receiverless functions consume their stored parameters, while
    an explicit typed receiver is already the first ordinary source argument.
    Both cases therefore lower directly to the emitted core function call. -/
inductive AssociatedCallLowers
    (implementations : List Static.ImplScheme)
    (methods : List Static.MethodScheme)
    (instances : List Static.MethodInstance)
    (currentModule : ModuleId)
    (receiverType : Static.GroundTy)
    (name : String)
    (argumentExpressions : List Core.Expr)
    (argumentTypes : List Static.GroundTy) : Static.GroundTy → Core.Expr → Prop where
  | call
      (selected : Static.MethodScheme)
      (resolved : Static.MethodInstance)
      (selectedUniquely : Static.ResolvesAssociatedMethod implementations methods
        instances currentModule receiverType name argumentTypes selected resolved) :
      AssociatedCallLowers implementations methods instances currentModule
        receiverType name argumentExpressions argumentTypes resolved.returnType
        (.call resolved.function argumentExpressions)

end Lanius.Elaboration
