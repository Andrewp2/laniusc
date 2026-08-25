import Lanius.Surface

namespace Lanius.SurfaceSyntax

open Lanius

inductive Optional (formed : α → Prop) : Option α → Prop where
  | none : Optional formed none
  | some (proof : formed value) : Optional formed (some value)

/-! ## Concrete literal spellings -/

/-- Escape decoding shared by string and character tokens. The current
    language recognizes the six conventional byte escapes below; every other
    escaped character denotes itself. -/
def decodeEscape : Char → Char
  | 'n' => '\n'
  | 'r' => '\r'
  | 't' => '\t'
  | '0' => Char.ofNat 0
  | '"' => '"'
  | '\\' => '\\'
  | character => character

/-- Decode a raw token body. An unescaped delimiter, newline, or backslash is
    rejected; a backslash consumes exactly one following character. -/
def decodeEscapedBody (delimiter : Char) : List Char → Option (List Char)
  | [] => some []
  | '\\' :: escaped :: tail => do
      let decodedTail ← decodeEscapedBody delimiter tail
      pure (decodeEscape escaped :: decodedTail)
  | character :: tail => do
      if character = delimiter ∨ character = '\n' then none
      else
        let decodedTail ← decodeEscapedBody delimiter tail
        pure (character :: decodedTail)

private def quotedBody? (delimiter : Char) (token : String) : Option (List Char) :=
  match token.toList with
  | first :: tail =>
      if first ≠ delimiter then none
      else
        match tail.reverse with
        | last :: reversedBody =>
            if last = delimiter then some reversedBody.reverse else none
        | [] => none
  | [] => none

/-- Decode a complete double-quoted token to its surface string value. -/
def stringLiteralValue? (token : String) : Option String := do
  let body ← quotedBody? '"' token
  return String.ofList (← decodeEscapedBody '"' body)

/-- Decode a complete single-quoted token. Exactly one decoded character is
    required; balanced multi-character tokens are rejected. -/
def characterLiteralValue? (token : String) : Option Char := do
  let body ← quotedBody? '\'' token
  match ← decodeEscapedBody '\'' body with
  | [value] => some value
  | _ => none

def StringLiteralSpells (token value : String) : Prop :=
  stringLiteralValue? token = some value

def CharacterLiteralSpells (token : String) (value : Char) : Prop :=
  characterLiteralValue? token = some value

instance (token value : String) : Decidable (StringLiteralSpells token value) := by
  unfold StringLiteralSpells
  infer_instance

instance (token : String) (value : Char) : Decidable (CharacterLiteralSpells token value) := by
  unfold CharacterLiteralSpells
  infer_instance

theorem StringLiteralSpells.functional
    (left : StringLiteralSpells token leftValue)
    (right : StringLiteralSpells token rightValue) :
    leftValue = rightValue := by
  exact Option.some.inj (left.symm.trans right)

theorem CharacterLiteralSpells.functional
    (left : CharacterLiteralSpells token leftValue)
    (right : CharacterLiteralSpells token rightValue) :
    leftValue = rightValue := by
  exact Option.some.inj (left.symm.trans right)

mutual
  /-- Type paths are nonempty, and only their final segment may carry the
      generic argument list admitted by the concrete grammar. -/
  inductive TypeExprWellFormed : Surface.TypeExpr → Prop where
    | path (segments : TypePathWellFormed surfaceSegments) :
        TypeExprWellFormed (.path surfaceSegments)
    | array (element : TypeExprWellFormed surfaceElement) :
        TypeExprWellFormed (.array surfaceElement length)
    | slice (element : TypeExprWellFormed surfaceElement) :
        TypeExprWellFormed (.slice surfaceElement)
    | reference (referent : TypeExprWellFormed surfaceReferent) :
        TypeExprWellFormed (.reference surfaceReferent)

  inductive TypeExprsWellFormed : List Surface.TypeExpr → Prop where
    | nil : TypeExprsWellFormed []
    | cons
        (head : TypeExprWellFormed surfaceHead)
        (tail : TypeExprsWellFormed surfaceTail) :
        TypeExprsWellFormed (surfaceHead :: surfaceTail)

  inductive TypePathWellFormed : List Surface.PathSegment → Prop where
    | last (arguments : TypeExprsWellFormed surfaceArguments) :
        TypePathWellFormed [.mk name surfaceArguments]
    | more (tail : TypePathWellFormed surfaceTail) :
        TypePathWellFormed (.mk name [] :: surfaceTail)

  /-- Value paths are nonempty and may carry arguments on any segment. -/
  inductive ValuePathWellFormed : List Surface.PathSegment → Prop where
    | last (arguments : TypeExprsWellFormed surfaceArguments) :
        ValuePathWellFormed [.mk name surfaceArguments]
    | more
        (arguments : TypeExprsWellFormed surfaceArguments)
        (tail : ValuePathWellFormed surfaceTail) :
        ValuePathWellFormed (.mk name surfaceArguments :: surfaceTail)
end

inductive PathWellFormed : Surface.Path → Prop where
  | intro (segments : ValuePathWellFormed surfaceSegments) :
      PathWellFormed { segments := surfaceSegments }

mutual
  /-- Bound syntax admits only paths and immutable references to bounds. -/
  inductive BoundTypeWellFormed : Surface.TypeExpr → Prop where
    | path (segments : BoundTypePathWellFormed surfaceSegments) :
        BoundTypeWellFormed (.path surfaceSegments)
    | reference (referent : BoundTypeWellFormed surfaceReferent) :
        BoundTypeWellFormed (.reference surfaceReferent)

  inductive BoundTypesWellFormed : List Surface.TypeExpr → Prop where
    | nil : BoundTypesWellFormed []
    | cons
        (head : BoundTypeWellFormed surfaceHead)
        (tail : BoundTypesWellFormed surfaceTail) :
        BoundTypesWellFormed (surfaceHead :: surfaceTail)

  inductive BoundTypePathWellFormed : List Surface.PathSegment → Prop where
    | last (arguments : BoundTypesWellFormed surfaceArguments) :
        BoundTypePathWellFormed [.mk name surfaceArguments]
    | more (tail : BoundTypePathWellFormed surfaceTail) :
        BoundTypePathWellFormed (.mk name [] :: surfaceTail)
end

mutual
  inductive ExprWellFormed : Surface.Expr → Prop where
    | literal : ExprWellFormed (.literal literal)
    | path (formed : PathWellFormed surfacePath) :
        ExprWellFormed (.path surfacePath)
    | selfValue : ExprWellFormed .selfValue
    | array (elements : ExprsWellFormed surfaceElements) :
        ExprWellFormed (.array surfaceElements)
    | structValue
        (path : PathWellFormed surfacePath)
        (fields : NamedExprsWellFormed surfaceFields) :
        ExprWellFormed (.structValue surfacePath surfaceFields)
    | unary (operand : ExprWellFormed surfaceOperand) :
        ExprWellFormed (.unary op surfaceOperand)
    | binary
        (left : ExprWellFormed surfaceLeft)
        (right : ExprWellFormed surfaceRight) :
        ExprWellFormed (.binary op surfaceLeft surfaceRight)
    | assign
        (place : ExprWellFormed surfacePlace)
        (value : ExprWellFormed surfaceValue) :
        ExprWellFormed (.assign op surfacePlace surfaceValue)
    | call
        (callee : ExprWellFormed surfaceCallee)
        (arguments : ExprsWellFormed surfaceArguments) :
        ExprWellFormed (.call surfaceCallee surfaceArguments)
    | index
        (base : ExprWellFormed surfaceBase)
        (index : ExprWellFormed surfaceIndex) :
        ExprWellFormed (.index surfaceBase surfaceIndex)
    | member (base : ExprWellFormed surfaceBase) :
        ExprWellFormed (.member surfaceBase name)
    | matchValue
        (scrutinee : ExprWellFormed surfaceScrutinee)
        (arms : MatchArmsWellFormed surfaceArms) :
        ExprWellFormed (.matchValue surfaceScrutinee surfaceArms)

  inductive ExprsWellFormed : List Surface.Expr → Prop where
    | nil : ExprsWellFormed []
    | cons
        (head : ExprWellFormed surfaceHead)
        (tail : ExprsWellFormed surfaceTail) :
        ExprsWellFormed (surfaceHead :: surfaceTail)

  inductive NamedExprsWellFormed : List (Surface.Name × Surface.Expr) → Prop where
    | nil : NamedExprsWellFormed []
    | cons
        (value : ExprWellFormed surfaceValue)
        (tail : NamedExprsWellFormed surfaceTail) :
        NamedExprsWellFormed ((name, surfaceValue) :: surfaceTail)

  inductive PatternWellFormed : Surface.Pattern → Prop where
    | wildcard : PatternWellFormed .wildcard
    | path
        (path : PathWellFormed surfacePath)
        (payload : PatternsWellFormed surfacePayload) :
        PatternWellFormed (.path surfacePath surfacePayload)
    | integer : PatternWellFormed (.integer text)
    | boolean : PatternWellFormed (.boolean value)

  inductive PatternsWellFormed : List Surface.Pattern → Prop where
    | nil : PatternsWellFormed []
    | cons
        (head : PatternWellFormed surfaceHead)
        (tail : PatternsWellFormed surfaceTail) :
        PatternsWellFormed (surfaceHead :: surfaceTail)

  inductive MatchArmsWellFormed :
      List (Surface.Pattern × Surface.Expr) → Prop where
    | nil : MatchArmsWellFormed []
    | cons
        (pattern : PatternWellFormed surfacePattern)
        (body : ExprWellFormed surfaceBody)
        (tail : MatchArmsWellFormed surfaceTail) :
        MatchArmsWellFormed ((surfacePattern, surfaceBody) :: surfaceTail)
end

inductive RangeBoundWellFormed : Surface.RangeBound → Prop where
  | integer : RangeBoundWellFormed (.integer text)
  | postfix
      (shape : Surface.RangeBoundPostfix surfaceExpression)
      (expression : ExprWellFormed surfaceExpression) :
      RangeBoundWellFormed (.postfix surfaceExpression)

/-- The left side of a range is the grammar's `range_start`, which is narrower
    than a stop bound: only an integer token may precede `..` or `..=`. -/
inductive RangeStartWellFormed : Surface.RangeBound → Prop where
  | integer : RangeStartWellFormed (.integer text)

inductive ForIterableWellFormed : Surface.ForIterable → Prop where
  | path (formed : PathWellFormed surfacePath) :
      ForIterableWellFormed (.path surfacePath)
  | full : ForIterableWellFormed (.range .full none none)
  | from (start : RangeStartWellFormed surfaceStart) :
      ForIterableWellFormed (.range .from (some surfaceStart) none)
  | toExclusive (stop : RangeBoundWellFormed surfaceStop) :
      ForIterableWellFormed (.range .toExclusive none (some surfaceStop))
  | toInclusive (stop : RangeBoundWellFormed surfaceStop) :
      ForIterableWellFormed (.range .toInclusive none (some surfaceStop))
  | exclusive
      (start : RangeStartWellFormed surfaceStart)
      (stop : RangeBoundWellFormed surfaceStop) :
      ForIterableWellFormed
        (.range .exclusive (some surfaceStart) (some surfaceStop))
  | inclusive
      (start : RangeStartWellFormed surfaceStart)
      (stop : RangeBoundWellFormed surfaceStop) :
      ForIterableWellFormed
        (.range .inclusive (some surfaceStart) (some surfaceStop))

mutual
  inductive StmtWellFormed : Surface.Stmt → Prop where
    | letLocal
        (type : Optional TypeExprWellFormed surfaceType)
        (initializer : Optional ExprWellFormed surfaceInitializer) :
        StmtWellFormed (.letLocal name surfaceType surfaceInitializer)
    | returnValue (value : Optional ExprWellFormed surfaceValue) :
        StmtWellFormed (.returnValue surfaceValue)
    | ifThenElse
        (condition : ExprWellFormed surfaceCondition)
        (thenBody : StmtsWellFormed surfaceThen)
        (elseBody : StmtsWellFormed surfaceElse) :
        StmtWellFormed (.ifThenElse surfaceCondition surfaceThen surfaceElse)
    | whileLoop
        (condition : ExprWellFormed surfaceCondition)
        (body : StmtsWellFormed surfaceBody) :
        StmtWellFormed (.whileLoop surfaceCondition surfaceBody)
    | forLoop
        (iterable : ForIterableWellFormed surfaceIterable)
        (body : StmtsWellFormed surfaceBody) :
        StmtWellFormed (.forLoop name surfaceIterable surfaceBody)
    | breakLoop : StmtWellFormed .breakLoop
    | continueLoop : StmtWellFormed .continueLoop
    | block (body : StmtsWellFormed surfaceBody) :
        StmtWellFormed (.block surfaceBody)
    | expression (formed : ExprWellFormed surfaceExpression) :
        StmtWellFormed (.expression surfaceExpression)

  inductive StmtsWellFormed : List Surface.Stmt → Prop where
    | nil : StmtsWellFormed []
    | cons
        (head : StmtWellFormed surfaceHead)
        (tail : StmtsWellFormed surfaceTail) :
        StmtsWellFormed (surfaceHead :: surfaceTail)
end

inductive GenericParameterWellFormed : Surface.GenericParameter → Prop where
  | type (bounds : BoundTypesWellFormed parameter.bounds) :
      GenericParameterWellFormed (.type parameter)
  | const (type : TypeExprWellFormed parameter.type) :
      GenericParameterWellFormed (.const parameter)

inductive GenericParametersWellFormed : List Surface.GenericParameter → Prop where
  | nil : GenericParametersWellFormed []
  | cons
      (head : GenericParameterWellFormed surfaceHead)
      (tail : GenericParametersWellFormed surfaceTail) :
      GenericParametersWellFormed (surfaceHead :: surfaceTail)

inductive WherePredicateWellFormed : Surface.WherePredicate → Prop where
  | intro
      (nonempty : predicate.bounds ≠ [])
      (bounds : BoundTypesWellFormed predicate.bounds) :
      WherePredicateWellFormed predicate

inductive WherePredicatesWellFormed : List Surface.WherePredicate → Prop where
  | nil : WherePredicatesWellFormed []
  | cons
      (head : WherePredicateWellFormed surfaceHead)
      (tail : WherePredicatesWellFormed surfaceTail) :
      WherePredicatesWellFormed (surfaceHead :: surfaceTail)

inductive ParameterWellFormed : Surface.Parameter → Prop where
  | named (type : TypeExprWellFormed surfaceType) :
      ParameterWellFormed (.named name surfaceType)
  | selfValue (type : Optional TypeExprWellFormed surfaceType) :
      ParameterWellFormed (.selfValue surfaceType)
  | selfReference : ParameterWellFormed .selfReference

inductive ParametersWellFormed : List Surface.Parameter → Prop where
  | nil : ParametersWellFormed []
  | cons
      (head : ParameterWellFormed surfaceHead)
      (tail : ParametersWellFormed surfaceTail) :
      ParametersWellFormed (surfaceHead :: surfaceTail)

def FunctionWellFormed (function : Surface.Function) : Prop :=
  GenericParametersWellFormed function.genericParameters ∧
  ParametersWellFormed function.parameters ∧
  Optional TypeExprWellFormed function.returnType ∧
  WherePredicatesWellFormed function.wherePredicates ∧
  StmtsWellFormed function.body

def ExternFunctionWellFormed (function : Surface.ExternFunction) : Prop :=
  GenericParametersWellFormed function.genericParameters ∧
  ParametersWellFormed function.parameters ∧
  Optional TypeExprWellFormed function.returnType ∧
  WherePredicatesWellFormed function.wherePredicates

def StructFieldWellFormed (field : Surface.StructField) : Prop :=
  TypeExprWellFormed field.type

def StructDeclWellFormed (declaration : Surface.StructDecl) : Prop :=
  GenericParametersWellFormed declaration.genericParameters ∧
  WherePredicatesWellFormed declaration.wherePredicates ∧
  ∀ field, field ∈ declaration.fields → StructFieldWellFormed field

def EnumVariantWellFormed (variant : Surface.EnumVariant) : Prop :=
  TypeExprsWellFormed variant.payload

def EnumDeclWellFormed (declaration : Surface.EnumDecl) : Prop :=
  GenericParametersWellFormed declaration.genericParameters ∧
  WherePredicatesWellFormed declaration.wherePredicates ∧
  ∀ variant, variant ∈ declaration.variants → EnumVariantWellFormed variant

def TraitMethodWellFormed (method : Surface.TraitMethod) : Prop :=
  method.signature.abi = none ∧ ExternFunctionWellFormed method.signature

def TraitDeclWellFormed (declaration : Surface.TraitDecl) : Prop :=
  GenericParametersWellFormed declaration.genericParameters ∧
  WherePredicatesWellFormed declaration.wherePredicates ∧
  ∀ method, method ∈ declaration.methods → TraitMethodWellFormed method

def ImplDeclWellFormed (declaration : Surface.ImplDecl) : Prop :=
  GenericParametersWellFormed declaration.genericParameters ∧
  Optional TypeExprWellFormed declaration.traitType ∧
  TypeExprWellFormed declaration.receiverType ∧
  WherePredicatesWellFormed declaration.wherePredicates ∧
  ∀ method, method ∈ declaration.methods → FunctionWellFormed method

inductive ItemWellFormed : Surface.Item → Prop where
  | module (path : PathWellFormed surfacePath) :
      ItemWellFormed (.module surfacePath)
  | importPath (path : PathWellFormed surfacePath) :
      ItemWellFormed (.importPath surfacePath)
  | importString : ItemWellFormed (.importString path)
  | function (formed : FunctionWellFormed declaration) :
      ItemWellFormed (.function declaration)
  | externFunction (formed : ExternFunctionWellFormed declaration) :
      ItemWellFormed (.externFunction declaration)
  | constant
      (type : TypeExprWellFormed surfaceType)
      (value : ExprWellFormed surfaceValue) :
      ItemWellFormed (.constant name isPublic surfaceType surfaceValue)
  | typeAlias
      (parameters : GenericParametersWellFormed surfaceParameters)
      (predicates : WherePredicatesWellFormed surfacePredicates)
      (target : TypeExprWellFormed surfaceTarget) :
      ItemWellFormed
        (.typeAlias name isPublic surfaceParameters surfacePredicates surfaceTarget)
  | structure (formed : StructDeclWellFormed declaration) :
      ItemWellFormed (.structure declaration)
  | enumeration (formed : EnumDeclWellFormed declaration) :
      ItemWellFormed (.enumeration declaration)
  | trait (formed : TraitDeclWellFormed declaration) :
      ItemWellFormed (.trait declaration)
  | implementation (formed : ImplDeclWellFormed declaration) :
      ItemWellFormed (.implementation declaration)

def FileWellFormed (file : Surface.File) : Prop :=
  ∀ item, item ∈ file.items → ItemWellFormed item

end Lanius.SurfaceSyntax
