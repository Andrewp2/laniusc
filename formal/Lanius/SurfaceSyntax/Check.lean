import Lanius.SurfaceSyntax

/-! Structural checks for reconstructed Surface syntax. -/

namespace Lanius.SurfaceSyntax

open Lanius
open Lanius.Surface

abbrev ProofOf (predicate : Prop) := PLift predicate

/-! Structural, proof-producing eligibility checker for the concrete Surface
    syntax.  It checks only syntax shape; name resolution, typing, and lowering
    remain separate premises. -/

mutual
  def checkTypeExpr : (surface : TypeExpr) → Option (ProofOf (TypeExprWellFormed surface))
    | .path segments => do
        let formed ← checkTypePath segments
        pure ⟨.path formed.down⟩
    | .array element _ => do
        let formed ← checkTypeExpr element
        pure ⟨.array formed.down⟩
    | .slice element => do
        let formed ← checkTypeExpr element
        pure ⟨.slice formed.down⟩
    | .reference referent => do
        let formed ← checkTypeExpr referent
        pure ⟨.reference formed.down⟩

  def checkTypeExprs : (surface : List TypeExpr) →
      Option (ProofOf (TypeExprsWellFormed surface))
    | [] => some ⟨.nil⟩
    | head :: tail => do
        let headFormed ← checkTypeExpr head
        let tailFormed ← checkTypeExprs tail
        pure ⟨.cons headFormed.down tailFormed.down⟩

  def checkTypePath : (surface : List PathSegment) →
      Option (ProofOf (TypePathWellFormed surface))
    | [] => none
    | [.mk _ arguments] => do
        let formed ← checkTypeExprs arguments
        pure ⟨.last formed.down⟩
    | .mk name arguments :: tail =>
        if h : arguments = [] then do
          let formed ← checkTypePath tail
          pure ⟨by simpa [h] using (TypePathWellFormed.more formed.down)⟩
        else
          none
end

def checkValuePath : (surface : List PathSegment) →
    Option (ProofOf (ValuePathWellFormed surface))
  | [] => none
  | [.mk _ arguments] => do
      let formed ← checkTypeExprs arguments
      pure ⟨.last formed.down⟩
    | .mk _ arguments :: tail => do
      let head ← checkTypeExprs arguments
      let rest ← checkValuePath tail
      pure ⟨.more head.down rest.down⟩

def checkPath (surface : Path) : Option (ProofOf (PathWellFormed surface)) := do
  let formed ← checkValuePath surface.segments
  pure ⟨.intro formed.down⟩

mutual
  def checkBoundType : (surface : TypeExpr) →
      Option (ProofOf (BoundTypeWellFormed surface))
    | .path segments => do
        let formed ← checkBoundTypePath segments
        pure ⟨.path formed.down⟩
    | .reference referent => do
        let formed ← checkBoundType referent
        pure ⟨.reference formed.down⟩
    | _ => none

  def checkBoundTypes : (surface : List TypeExpr) →
      Option (ProofOf (BoundTypesWellFormed surface))
    | [] => some ⟨.nil⟩
    | head :: tail => do
        let headFormed ← checkBoundType head
        let tailFormed ← checkBoundTypes tail
        pure ⟨.cons headFormed.down tailFormed.down⟩

  def checkBoundTypePath : (surface : List PathSegment) →
      Option (ProofOf (BoundTypePathWellFormed surface))
    | [] => none
    | [.mk name arguments] => do
        let formed ← checkBoundTypes arguments
        pure ⟨.last formed.down⟩
    | .mk name arguments :: tail =>
        if h : arguments = [] then do
          let formed ← checkBoundTypePath tail
          pure ⟨by simpa [h] using (BoundTypePathWellFormed.more formed.down)⟩
        else
          none
end

def checkAll (predicate : α → Prop)
    (check : (value : α) → Option (ProofOf (predicate value))) :
    (values : List α) → Option (ProofOf (∀ value, value ∈ values → predicate value))
  | [] => some ⟨fun _ membership => by cases membership⟩
  | head :: tail => do
      let headFormed ← check head
      let tailFormed ← checkAll predicate check tail
      pure ⟨fun value membership => by
        simp only [List.mem_cons] at membership
        rcases membership with rfl | membership
        · exact headFormed.down
        · exact tailFormed.down value membership⟩

mutual
  def checkExpr : (surface : Expr) → Option (ProofOf (ExprWellFormed surface))
    | .literal _ => some ⟨.literal⟩
    | .path path => do
        let formed ← checkPath path
        pure ⟨.path formed.down⟩
    | .selfValue => some ⟨.selfValue⟩
    | .array elements => do
        let formed ← checkExprs elements
        pure ⟨.array formed.down⟩
    | .structValue path fields => do
        let pathFormed ← checkPath path
        let fieldsFormed ← checkNamedExprs fields
        pure ⟨.structValue pathFormed.down fieldsFormed.down⟩
    | .unary _ operand => do
        let formed ← checkExpr operand
        pure ⟨.unary formed.down⟩
    | .binary _ left right => do
        let leftFormed ← checkExpr left
        let rightFormed ← checkExpr right
        pure ⟨.binary leftFormed.down rightFormed.down⟩
    | .assign _ place value => do
        let placeFormed ← checkExpr place
        let valueFormed ← checkExpr value
        pure ⟨.assign placeFormed.down valueFormed.down⟩
    | .call callee arguments => do
        let calleeFormed ← checkExpr callee
        let argumentsFormed ← checkExprs arguments
        pure ⟨.call calleeFormed.down argumentsFormed.down⟩
    | .index base index => do
        let baseFormed ← checkExpr base
        let indexFormed ← checkExpr index
        pure ⟨.index baseFormed.down indexFormed.down⟩
    | .member base _ => do
        let formed ← checkExpr base
        pure ⟨.member formed.down⟩
    | .matchValue scrutinee arms => do
        let scrutineeFormed ← checkExpr scrutinee
        let armsFormed ← checkMatchArms arms
        pure ⟨.matchValue scrutineeFormed.down armsFormed.down⟩

  def checkExprs : (surface : List Expr) → Option (ProofOf (ExprsWellFormed surface))
    | [] => some ⟨.nil⟩
    | head :: tail => do
        let headFormed ← checkExpr head
        let tailFormed ← checkExprs tail
        pure ⟨.cons headFormed.down tailFormed.down⟩

  def checkNamedExprs : (surface : List (Name × Expr)) →
      Option (ProofOf (NamedExprsWellFormed surface))
    | [] => some ⟨.nil⟩
    | (_, value) :: tail => do
        let valueFormed ← checkExpr value
        let tailFormed ← checkNamedExprs tail
        pure ⟨.cons valueFormed.down tailFormed.down⟩

  def checkPattern : (surface : Pattern) → Option (ProofOf (PatternWellFormed surface))
    | .wildcard => some ⟨.wildcard⟩
    | .path path payload => do
        let pathFormed ← checkPath path
        let payloadFormed ← checkPatterns payload
        pure ⟨.path pathFormed.down payloadFormed.down⟩
    | .integer _ => some ⟨.integer⟩
    | .boolean _ => some ⟨.boolean⟩

  def checkPatterns : (surface : List Pattern) →
      Option (ProofOf (PatternsWellFormed surface))
    | [] => some ⟨.nil⟩
    | head :: tail => do
        let headFormed ← checkPattern head
        let tailFormed ← checkPatterns tail
        pure ⟨.cons headFormed.down tailFormed.down⟩

  def checkMatchArms : (surface : List (Pattern × Expr)) →
      Option (ProofOf (MatchArmsWellFormed surface))
    | [] => some ⟨.nil⟩
    | (pattern, body) :: tail => do
        let patternFormed ← checkPattern pattern
        let bodyFormed ← checkExpr body
        let tailFormed ← checkMatchArms tail
        pure ⟨.cons patternFormed.down bodyFormed.down tailFormed.down⟩
end

def checkRangeBoundPostfix :
  (surface : Expr) → Option (ProofOf (RangeBoundPostfix surface))
  | .path path =>
      match path with
      | { segments := segments } => match segments with
      | [.mk _ []] => some ⟨.name⟩
      | _ => none
  | .call callee _ => do
      let formed ← checkRangeBoundPostfix callee
      pure ⟨.call formed.down⟩
  | .index expression _ => do
      let formed ← checkRangeBoundPostfix expression
      pure ⟨.index formed.down⟩
  | .member expression _ => do
      let formed ← checkRangeBoundPostfix expression
      pure ⟨.member formed.down⟩
  | _ => none

def checkRangeBound :
    (surface : RangeBound) → Option (ProofOf (RangeBoundWellFormed surface))
  | .integer _ => some ⟨.integer⟩
  | .postfix expression => do
      let shape ← checkRangeBoundPostfix expression
      let formed ← checkExpr expression
      pure ⟨.postfix shape.down formed.down⟩

def checkRangeStart :
    (surface : RangeBound) → Option (ProofOf (RangeStartWellFormed surface))
  | .integer _ => some ⟨.integer⟩
  | .postfix _ => none

def checkForIterable :
    (surface : ForIterable) → Option (ProofOf (ForIterableWellFormed surface))
  | .path path => do
      let formed ← checkPath path
      pure ⟨.path formed.down⟩
  | .range .full none none => some ⟨.full⟩
  | .range .from (some start) none => do
      let formed ← checkRangeStart start
      pure ⟨.from formed.down⟩
  | .range .toExclusive none (some stop) => do
      let formed ← checkRangeBound stop
      pure ⟨.toExclusive formed.down⟩
  | .range .toInclusive none (some stop) => do
      let formed ← checkRangeBound stop
      pure ⟨.toInclusive formed.down⟩
  | .range .exclusive (some start) (some stop) => do
      let startFormed ← checkRangeStart start
      let stopFormed ← checkRangeBound stop
      pure ⟨.exclusive startFormed.down stopFormed.down⟩
  | .range .inclusive (some start) (some stop) => do
      let startFormed ← checkRangeStart start
      let stopFormed ← checkRangeBound stop
      pure ⟨.inclusive startFormed.down stopFormed.down⟩
  | .range _ _ _ => none

def checkOptionalType :
    (surface : Option TypeExpr) → Option (ProofOf (Optional TypeExprWellFormed surface))
  | none => some ⟨.none⟩
  | some value => do
      let formed ← checkTypeExpr value
      pure ⟨.some formed.down⟩

def checkOptionalExpr :
    (surface : Option Expr) → Option (ProofOf (Optional ExprWellFormed surface))
  | none => some ⟨.none⟩
  | some value => do
      let formed ← checkExpr value
      pure ⟨.some formed.down⟩

mutual
  def checkStmt : (surface : Stmt) → Option (ProofOf (StmtWellFormed surface))
    | .letLocal _ type initializer => do
        let typeFormed ← checkOptionalType type
        let initializerFormed ← checkOptionalExpr initializer
        pure ⟨.letLocal typeFormed.down initializerFormed.down⟩
    | .returnValue value => do
        let formed ← checkOptionalExpr value
        pure ⟨.returnValue formed.down⟩
    | .ifThenElse condition thenBody elseBody => do
        let conditionFormed ← checkExpr condition
        let thenFormed ← checkStmts thenBody
        let elseFormed ← checkStmts elseBody
        pure ⟨.ifThenElse conditionFormed.down thenFormed.down elseFormed.down⟩
    | .whileLoop condition body => do
        let conditionFormed ← checkExpr condition
        let bodyFormed ← checkStmts body
        pure ⟨.whileLoop conditionFormed.down bodyFormed.down⟩
    | .forLoop _ iterable body => do
        let iterableFormed ← checkForIterable iterable
        let bodyFormed ← checkStmts body
        pure ⟨.forLoop iterableFormed.down bodyFormed.down⟩
    | .breakLoop => some ⟨.breakLoop⟩
    | .continueLoop => some ⟨.continueLoop⟩
    | .block body => do
        let formed ← checkStmts body
        pure ⟨.block formed.down⟩
    | .expression expression => do
        let formed ← checkExpr expression
        pure ⟨.expression formed.down⟩

  def checkStmts : (surface : List Stmt) → Option (ProofOf (StmtsWellFormed surface))
    | [] => some ⟨.nil⟩
    | head :: tail => do
        let headFormed ← checkStmt head
        let tailFormed ← checkStmts tail
        pure ⟨.cons headFormed.down tailFormed.down⟩
end

def checkGenericParameter :
    (surface : GenericParameter) → Option (ProofOf (GenericParameterWellFormed surface))
  | .type parameter => do
      let formed ← checkBoundTypes parameter.bounds
      pure ⟨.type formed.down⟩
  | .const parameter => do
      let formed ← checkTypeExpr parameter.type
      pure ⟨.const formed.down⟩

def checkGenericParameters :
    (surface : List GenericParameter) →
      Option (ProofOf (GenericParametersWellFormed surface))
  | [] => some ⟨.nil⟩
  | head :: tail => do
      let headFormed ← checkGenericParameter head
      let tailFormed ← checkGenericParameters tail
      pure ⟨.cons headFormed.down tailFormed.down⟩

def checkWherePredicate :
    (surface : WherePredicate) → Option (ProofOf (WherePredicateWellFormed surface))
  | predicate =>
      if h : predicate.bounds = [] then
        none
      else do
        let formed ← checkBoundTypes predicate.bounds
        pure ⟨.intro h formed.down⟩

def checkWherePredicates :
    (surface : List WherePredicate) →
      Option (ProofOf (WherePredicatesWellFormed surface))
  | [] => some ⟨.nil⟩
  | head :: tail => do
      let headFormed ← checkWherePredicate head
      let tailFormed ← checkWherePredicates tail
      pure ⟨.cons headFormed.down tailFormed.down⟩

def checkParameter :
    (surface : Parameter) → Option (ProofOf (ParameterWellFormed surface))
  | .named _ type => do
      let formed ← checkTypeExpr type
      pure ⟨.named formed.down⟩
  | .selfValue type => do
      let formed ← checkOptionalType type
      pure ⟨.selfValue formed.down⟩
  | .selfReference => some ⟨.selfReference⟩

def checkParameters :
    (surface : List Parameter) → Option (ProofOf (ParametersWellFormed surface))
  | [] => some ⟨.nil⟩
  | head :: tail => do
      let headFormed ← checkParameter head
      let tailFormed ← checkParameters tail
      pure ⟨.cons headFormed.down tailFormed.down⟩

def checkFunction :
    (surface : Function) → Option (ProofOf (FunctionWellFormed surface))
  | declaration => do
      let genericParameters ← checkGenericParameters declaration.genericParameters
      let parameters ← checkParameters declaration.parameters
      let returnType ← checkOptionalType declaration.returnType
      let predicates ← checkWherePredicates declaration.wherePredicates
      let body ← checkStmts declaration.body
      pure ⟨genericParameters.down, parameters.down, returnType.down,
        predicates.down, body.down⟩

def checkExternFunction :
    (surface : ExternFunction) → Option (ProofOf (ExternFunctionWellFormed surface))
  | declaration => do
      let genericParameters ← checkGenericParameters declaration.genericParameters
      let parameters ← checkParameters declaration.parameters
      let returnType ← checkOptionalType declaration.returnType
      let predicates ← checkWherePredicates declaration.wherePredicates
      pure ⟨genericParameters.down, parameters.down, returnType.down, predicates.down⟩

def checkStructField :
    (surface : StructField) → Option (ProofOf (StructFieldWellFormed surface))
  | field => checkTypeExpr field.type

def checkStruct :
    (surface : StructDecl) → Option (ProofOf (StructDeclWellFormed surface))
  | declaration => do
      let genericParameters ← checkGenericParameters declaration.genericParameters
      let predicates ← checkWherePredicates declaration.wherePredicates
      let fields ← checkAll (fun field => StructFieldWellFormed field)
        checkStructField declaration.fields
      pure ⟨genericParameters.down, predicates.down, fields.down⟩

def checkEnumVariant :
    (surface : EnumVariant) → Option (ProofOf (EnumVariantWellFormed surface))
  | variant => checkTypeExprs variant.payload

def checkEnum :
    (surface : EnumDecl) → Option (ProofOf (EnumDeclWellFormed surface))
  | declaration => do
      let genericParameters ← checkGenericParameters declaration.genericParameters
      let predicates ← checkWherePredicates declaration.wherePredicates
      let variants ← checkAll (fun variant => EnumVariantWellFormed variant)
        checkEnumVariant declaration.variants
      pure ⟨genericParameters.down, predicates.down, variants.down⟩

def checkTraitMethod :
    (surface : TraitMethod) → Option (ProofOf (TraitMethodWellFormed surface))
  | method => if h : method.signature.abi = none then do
      let signature ← checkExternFunction method.signature
      pure ⟨h, signature.down⟩
    else
      none

def checkTrait :
    (surface : TraitDecl) → Option (ProofOf (TraitDeclWellFormed surface))
  | declaration => do
      let genericParameters ← checkGenericParameters declaration.genericParameters
      let predicates ← checkWherePredicates declaration.wherePredicates
      let methods ← checkAll (fun method => TraitMethodWellFormed method)
        checkTraitMethod declaration.methods
      pure ⟨genericParameters.down, predicates.down, methods.down⟩

def checkImpl :
    (surface : ImplDecl) → Option (ProofOf (ImplDeclWellFormed surface))
  | declaration => do
      let genericParameters ← checkGenericParameters declaration.genericParameters
      let traitType ← checkOptionalType declaration.traitType
      let receiverType ← checkTypeExpr declaration.receiverType
      let predicates ← checkWherePredicates declaration.wherePredicates
      let methods ← checkAll (fun method => FunctionWellFormed method)
        checkFunction declaration.methods
      pure ⟨genericParameters.down, traitType.down, receiverType.down,
        predicates.down, methods.down⟩

def checkItem :
    (surface : Item) → Option (ProofOf (ItemWellFormed surface))
  | .module path => do
      let formed ← checkPath path
      pure ⟨.module formed.down⟩
  | .importPath path => do
      let formed ← checkPath path
      pure ⟨.importPath formed.down⟩
  | .importString _ => some ⟨.importString⟩
  | .function declaration => do
      let formed ← checkFunction declaration
      pure ⟨.function formed.down⟩
  | .externFunction declaration => do
      let formed ← checkExternFunction declaration
      pure ⟨.externFunction formed.down⟩
  | .constant _ _ type value => do
      let typeFormed ← checkTypeExpr type
      let valueFormed ← checkExpr value
      pure ⟨.constant typeFormed.down valueFormed.down⟩
  | .typeAlias _ _ parameters predicates target => do
      let parametersFormed ← checkGenericParameters parameters
      let predicatesFormed ← checkWherePredicates predicates
      let targetFormed ← checkTypeExpr target
      pure ⟨.typeAlias parametersFormed.down predicatesFormed.down targetFormed.down⟩
  | .structure declaration => do
      let formed ← checkStruct declaration
      pure ⟨.structure formed.down⟩
  | .enumeration declaration => do
      let formed ← checkEnum declaration
      pure ⟨.enumeration formed.down⟩
  | .trait declaration => do
      let formed ← checkTrait declaration
      pure ⟨.trait formed.down⟩
  | .implementation declaration => do
      let formed ← checkImpl declaration
      pure ⟨.implementation formed.down⟩

def checkFileWellFormed (surface : File) :
    Option (ProofOf (FileWellFormed surface)) := do
  let formed ← checkAll (fun item => ItemWellFormed item) checkItem surface.items
  pure ⟨formed.down⟩

theorem checkFileWellFormed_evidence {surface : File} {formed : ProofOf (FileWellFormed surface)}
    (_accepted : checkFileWellFormed surface = some formed) :
    FileWellFormed surface := by
  exact formed.down

end Lanius.SurfaceSyntax
