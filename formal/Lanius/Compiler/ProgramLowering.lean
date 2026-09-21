import Lanius.Declarations
import Lanius.SurfaceElaboration
import Lanius.Typing

namespace Lanius.Compiler.ProgramLowering

open Lanius

def NamedParametersSupported : List Surface.Parameter → Prop
  | [] => True
  | .named _ _ :: parameters => NamedParametersSupported parameters
  | _ :: _ => False

/-- The source subset for which the current front end has a monomorphic
    contract.  Imports and type aliases are compile-time syntax, not Core
    declarations.  Generic aliases remain outside this contract. -/
def SupportedItem : Surface.Item → Prop
  | .module _ | .importPath _ => True
  | .function declaration =>
      declaration.genericParameters = [] ∧ declaration.wherePredicates = [] ∧
        NamedParametersSupported declaration.parameters
  | .externFunction declaration =>
      declaration.abi = none ∧ declaration.genericParameters = [] ∧
        declaration.wherePredicates = [] ∧
        NamedParametersSupported declaration.parameters
  | .constant _ _ _ _ => True
  | .typeAlias _ _ parameters predicates _ =>
      parameters = [] ∧ predicates = []
  | .structure declaration =>
      declaration.genericParameters = [] ∧ declaration.wherePredicates = []
  | _ => False

def SupportedMonomorphic (pack : Declarations.SourcePack) : Prop :=
  ∀ file ∈ pack.files, ∀ item ∈ file.contents.items, SupportedItem item

/- Runtime rows intentionally omit compile-time-only aliases.  Keeping this
   predicate here makes declaration exactness explicit without pretending an
   alias has a Core declaration. -/
def RuntimeItem : Surface.Item → Prop
  | .function _ | .externFunction _ | .constant _ _ _ _ | .structure _ => True
  | _ => False

def RuntimeOccurrence (pack : Declarations.SourcePack)
    (occurrence : Declarations.DeclarationOccurrence) : Prop :=
  ∃ address item, occurrence = .item address ∧
    pack.item? address = some item ∧ RuntimeItem item

def AliasOccurrence (pack : Declarations.SourcePack)
    (occurrence : Declarations.DeclarationOccurrence) : Prop :=
  ∃ address name isPublic parameters predicates target,
    occurrence = .item address ∧
      pack.item? address =
        some (.typeAlias name isPublic parameters predicates target) ∧
      parameters = [] ∧ predicates = []

def ContextMatches
    (context base : SurfaceElaboration.Context)
    (environment : Names.Environment) (moduleId : ModuleId) : Prop :=
  context.names = environment ∧ context.target = base.target ∧
    context.monomorphization = base.monomorphization ∧
    context.currentModule = moduleId ∧ context.typeParameters = [] ∧
    context.constParameters = [] ∧ context.substitution = {}

abbrev ExternalBehaviorResolver :=
  Declarations.DeclarationHeader → Option Core.ExternalBehavior

inductive NamedParametersLower (context : SurfaceElaboration.Context) :
    List Surface.Parameter → List SurfaceElaboration.LocalBinding →
    List (VarId × Core.Ty) → Prop where
  | nil : NamedParametersLower context [] [] []
  | named
      (name : Surface.Name) (surfaceType : Surface.TypeExpr)
      (groundType : Static.GroundTy) (coreType : Core.Ty)
      (binding : SurfaceElaboration.LocalBinding)
      (typed : SurfaceElaboration.TypeGrounds context surfaceType groundType)
      (grounded : groundType.toCore context.monomorphization = some coreType)
      (nameMatches : binding.name = name)
      (typeMatches : binding.type = groundType)
      (tail : NamedParametersLower context surfaceTail tailBindings tailCore) :
      NamedParametersLower context
        (.named name surfaceType :: surfaceTail)
        (binding :: tailBindings) ((binding.id, coreType) :: tailCore)

inductive ReturnTypeLower (context : SurfaceElaboration.Context) :
    Option Surface.TypeExpr → Core.Ty → Prop where
  | none : ReturnTypeLower context none .unit
  | some
      (surfaceType : Surface.TypeExpr) (groundType : Static.GroundTy)
      (coreType : Core.Ty)
      (typed : SurfaceElaboration.TypeGrounds context surfaceType groundType)
      (grounded : groundType.toCore context.monomorphization = some coreType) :
      ReturnTypeLower context (some surfaceType) coreType

inductive CoreDeclaration where
  | structure (declaration : Core.StructDecl)
  | constant (declaration : Core.Constant)
  | function (declaration : Core.Function)

def CoreDeclaration.member (program : Core.Program) : CoreDeclaration → Prop
  | .structure declaration => declaration ∈ program.structures
  | .constant declaration => declaration ∈ program.constants
  | .function declaration => declaration ∈ program.functions

/-- Identification includes the declaration kind and dense source ID.  The
    body/external discriminant prevents an ordinary and an external function
    from being interchangeable at this boundary. -/
def CoreDeclaration.matches
    (header : Declarations.DeclarationHeader) : CoreDeclaration → Prop
  | .structure declaration =>
      header.kind = .structureType ∧ declaration.id = header.declaration
  | .constant declaration =>
      header.kind = .constant ∧ declaration.id = header.declaration
  | .function declaration =>
      (header.kind = .function ∧ declaration.id = header.declaration ∧
        (∃ body, declaration.body = some body) ∧ declaration.external = none) ∨
      (header.kind = .externalFunction ∧ declaration.id = header.declaration ∧
        declaration.body = none ∧ (∃ behavior, declaration.external = some behavior))

structure DeclarationLowering
    (pack : Declarations.SourcePack) (catalog : Declarations.Catalog)
    (program : Core.Program) where
  occurrence : Declarations.DeclarationOccurrence
  header : Declarations.DeclarationHeader
  core : CoreDeclaration
  occurs : Declarations.Occurs pack occurrence
  inCatalog : header ∈ catalog.headers
  source : header.source = occurrence
  headerMatches : Declarations.HeaderMatches pack header
  member : core.member program
  identified : core.matches header

def DeclarationLoweringsExact
    (pack : Declarations.SourcePack) (catalog : Declarations.Catalog)
    (program : Core.Program)
    (rows : List (DeclarationLowering pack catalog program)) : Prop :=
  (∀ occurrence, RuntimeOccurrence pack occurrence →
    ∃ row ∈ rows, row.occurrence = occurrence) ∧
  (∀ declaration, declaration ∈ program.structures →
    ∃ row ∈ rows, row.core = .structure declaration) ∧
  (∀ declaration, declaration ∈ program.constants →
    ∃ row ∈ rows, row.core = .constant declaration) ∧
  (∀ declaration, declaration ∈ program.functions →
    ∃ row ∈ rows, row.core = .function declaration) ∧
  (∀ left ∈ rows, ∀ right ∈ rows, left.occurrence = right.occurrence →
    left.header = right.header ∧ left.core = right.core)

/- An alias has source and catalog identity, but no Core member.  Its target
   remains Surface syntax because alias expansion is consumed by compile-time
   type elaboration rather than by the runtime Core program. -/
structure TypeAliasLowering
    (pack : Declarations.SourcePack) (catalog : Declarations.Catalog) where
  occurrence : Declarations.DeclarationOccurrence
  header : Declarations.DeclarationHeader
  address : Declarations.ItemAddress
  name : Surface.Name
  isPublic : Bool
  parameters : List Surface.GenericParameter
  predicates : List Surface.WherePredicate
  target : Surface.TypeExpr
  occurs : Declarations.Occurs pack occurrence
  inCatalog : header ∈ catalog.headers
  headerMatches : Declarations.HeaderMatches pack header
  headerKind : header.kind = .typeAlias
  source : occurrence = .item address
  occurrenceSource : occurrence = header.source
  headerSource : header.source = occurrence
  sourceFound : pack.item? address =
    some (.typeAlias name isPublic parameters predicates target)
  monomorphic : parameters = [] ∧ predicates = []

def TypeAliasLoweringsExact
    (pack : Declarations.SourcePack) (catalog : Declarations.Catalog)
    (rows : List (TypeAliasLowering pack catalog)) : Prop :=
  (∀ occurrence, AliasOccurrence pack occurrence →
    ∃ row ∈ rows, row.occurrence = occurrence) ∧
  (∀ row : TypeAliasLowering pack catalog, row ∈ rows →
    (row.header ∈ catalog.headers ∧ row.header.kind = .typeAlias ∧
      row.header.source = row.occurrence ∧
      row.parameters = [] ∧ row.predicates = []))

structure StructureLowering
    (pack : Declarations.SourcePack) (catalog : Declarations.Catalog)
    (program : Core.Program) (environment : Names.Environment)
    (baseContext : SurfaceElaboration.Context)
    (rows : List (DeclarationLowering pack catalog program)) where
  row : DeclarationLowering pack catalog program
  rowMember : row ∈ rows
  address : Declarations.ItemAddress
  declaration : Surface.StructDecl
  sourceFound : pack.item? address = some (.structure declaration)
  source : row.occurrence = .item address
  core : Core.StructDecl
  coreMap : row.core = .structure core
  context : SurfaceElaboration.Context
  fieldTypes : List Static.GroundTy
  fieldsLowering : SurfaceElaboration.TypesGround context
    (declaration.fields.map (fun field => field.type)) fieldTypes
  fieldsGrounded : Static.GroundTy.listToCore context.monomorphization fieldTypes =
    some core.fields
  contextMatches : ContextMatches context baseContext environment row.header.moduleId
  noLocals : context.locals = []

def StructureLoweringsExact
    (pack : Declarations.SourcePack) (catalog : Declarations.Catalog)
    (program : Core.Program) (environment : Names.Environment)
    (baseContext : SurfaceElaboration.Context)
    (rows : List (DeclarationLowering pack catalog program))
    (structures : List
      (StructureLowering pack catalog program environment baseContext rows)) : Prop :=
  (∀ address declaration, pack.item? address = some (.structure declaration) →
    ∃ row ∈ structures, row.address = address) ∧
  (∀ left ∈ structures, ∀ right ∈ structures, left.address = right.address →
    left.core = right.core)

structure FunctionBodyLowering
    (pack : Declarations.SourcePack) (catalog : Declarations.Catalog)
    (program : Core.Program) (environment : Names.Environment)
    (baseContext : SurfaceElaboration.Context)
    (rows : List (DeclarationLowering pack catalog program)) where
  row : DeclarationLowering pack catalog program
  rowMember : row ∈ rows
  address : Declarations.ItemAddress
  declaration : Surface.Function
  sourceFound : pack.item? address = some (.function declaration)
  source : row.occurrence = .item address
  core : Core.Function
  coreMap : row.core = .function core
  context : SurfaceElaboration.Context
  next : VarId
  parameters : NamedParametersLower context declaration.parameters context.locals core.parameters
  returnType : ReturnTypeLower context declaration.returnType core.returnType
  lowering : SurfaceElaboration.TypedStmtsLowering
    program context core.returnType false next declaration.body
  contextMatches : ContextMatches context baseContext environment row.header.moduleId
  parameterContext : context.coreLocals = Typing.parameterContext core.parameters
  coreShape : core.body = some lowering.core ∧
    core.external = none

def FunctionBodiesExact
    (pack : Declarations.SourcePack) (catalog : Declarations.Catalog)
    (program : Core.Program) (environment : Names.Environment)
    (baseContext : SurfaceElaboration.Context)
    (rows : List (DeclarationLowering pack catalog program))
    (bodies : List (FunctionBodyLowering pack catalog program environment baseContext rows)) : Prop :=
  (∀ address declaration, pack.item? address = some (.function declaration) →
    ∃ body ∈ bodies, body.address = address) ∧
  (∀ left ∈ bodies, ∀ right ∈ bodies, left.address = right.address →
    left.core = right.core)

structure ExternalFunctionLowering
    (pack : Declarations.SourcePack) (catalog : Declarations.Catalog)
    (program : Core.Program) (environment : Names.Environment)
    (baseContext : SurfaceElaboration.Context)
    (resolver : ExternalBehaviorResolver)
    (rows : List (DeclarationLowering pack catalog program)) where
  row : DeclarationLowering pack catalog program
  rowMember : row ∈ rows
  address : Declarations.ItemAddress
  declaration : Surface.ExternFunction
  sourceFound : pack.item? address = some (.externFunction declaration)
  source : row.occurrence = .item address
  core : Core.Function
  coreMap : row.core = .function core
  context : SurfaceElaboration.Context
  parameters : NamedParametersLower context declaration.parameters context.locals core.parameters
  returnType : ReturnTypeLower context declaration.returnType core.returnType
  contextMatches : ContextMatches context baseContext environment row.header.moduleId
  abi : declaration.abi = none
  behavior : core.external = resolver row.header
  coreShape : core.body = none
  wellTyped : Typing.FunctionWellTyped program core

def ExternalFunctionLoweringsExact
    (pack : Declarations.SourcePack) (catalog : Declarations.Catalog)
    (program : Core.Program) (environment : Names.Environment)
    (baseContext : SurfaceElaboration.Context)
    (resolver : ExternalBehaviorResolver)
    (rows : List (DeclarationLowering pack catalog program))
    (externals : List
      (ExternalFunctionLowering pack catalog program environment baseContext resolver rows)) : Prop :=
  (∀ address declaration, pack.item? address = some (.externFunction declaration) →
    ∃ row ∈ externals, row.address = address) ∧
  (∀ left ∈ externals, ∀ right ∈ externals, left.address = right.address →
    left.core = right.core)

structure ConstantLowering
    (pack : Declarations.SourcePack) (catalog : Declarations.Catalog)
    (program : Core.Program) (environment : Names.Environment)
    (baseContext : SurfaceElaboration.Context)
    (rows : List (DeclarationLowering pack catalog program)) where
  row : DeclarationLowering pack catalog program
  rowMember : row ∈ rows
  address : Declarations.ItemAddress
  name : Surface.Name
  isPublic : Bool
  surfaceType : Surface.TypeExpr
  value : Surface.Expr
  sourceFound : pack.item? address =
    some (.constant name isPublic surfaceType value)
  source : row.occurrence = .item address
  core : Core.Constant
  coreMap : row.core = .constant core
  context : SurfaceElaboration.Context
  typed : SurfaceElaboration.TypedExprLowering program context value
  declaredType : SurfaceElaboration.TypeGrounds context surfaceType typed.groundType
  typedType : typed.coreType = core.type
  coreValue : Core.Value
  typedValue : typed.core = Core.Expr.value coreValue
  contextMatches : ContextMatches context baseContext environment row.header.moduleId
  noLocals : context.locals = []
  coreShape : core.value = coreValue

def ConstantLoweringsExact
    (pack : Declarations.SourcePack) (catalog : Declarations.Catalog)
    (program : Core.Program) (environment : Names.Environment)
    (baseContext : SurfaceElaboration.Context)
    (rows : List (DeclarationLowering pack catalog program))
    (values : List (ConstantLowering pack catalog program environment baseContext rows)) : Prop :=
  (∀ address name isPublic surfaceType value,
    pack.item? address = some (.constant name isPublic surfaceType value) →
    ∃ row ∈ values, row.address = address) ∧
  (∀ left ∈ values, ∀ right ∈ values, left.address = right.address →
    left.core = right.core)

structure ProgramLowering where
  pack : Declarations.SourcePack
  catalog : Declarations.Catalog
  imports : List Declarations.CollectedImport
  environment : Names.Environment
  context : SurfaceElaboration.Context
  program : Core.Program
  sourceWellFormed : Declarations.SourcePackWellFormed pack
  catalogWellFormed : Declarations.CatalogWellFormed pack catalog
  importsWellFormed : Declarations.ImportCollectionCovers pack imports
  eligible : SupportedMonomorphic pack
  environmentMatches : environment = Declarations.nameEnvironment pack catalog imports
  contextEnvironment : context.names = environment
  contextTarget : context.target = program.target
  declarations : List (DeclarationLowering pack catalog program)
  declarationsExact : DeclarationLoweringsExact pack catalog program declarations
  aliases : List (TypeAliasLowering pack catalog)
  aliasesExact : TypeAliasLoweringsExact pack catalog aliases
  structures : List (StructureLowering
    pack catalog program environment context declarations)
  structuresExact : StructureLoweringsExact
    pack catalog program environment context declarations structures
  functionBodies : List (FunctionBodyLowering
    pack catalog program environment context declarations)
  functionBodiesExact : FunctionBodiesExact
    pack catalog program environment context declarations functionBodies
  externalBehavior : ExternalBehaviorResolver
  externals : List (ExternalFunctionLowering
    pack catalog program environment context externalBehavior declarations)
  externalsExact : ExternalFunctionLoweringsExact
    pack catalog program environment context externalBehavior declarations externals
  constants : List (ConstantLowering
    pack catalog program environment context declarations)
  constantsExact : ConstantLoweringsExact
    pack catalog program environment context declarations constants
  noEnumerations : program.enumerations = []
  structuresUnique : (program.structures.map fun declaration => declaration.id).Nodup
  constantsUnique : (program.constants.map fun declaration => declaration.id).Nodup
  functionsUnique : (program.functions.map fun declaration => declaration.id).Nodup
  wellTyped : Typing.ProgramWellTyped program

end Lanius.Compiler.ProgramLowering
