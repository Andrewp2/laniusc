import Lanius.Surface

namespace Lanius.Names

open Lanius

abbrev ModulePath := List String

inductive Visibility where
  | modulePrivate
  | exported
deriving DecidableEq, Repr

/-- Lanius has distinct type, value, and module lookup domains. A same-spelled
    type and function therefore do not create a false ambiguity. -/
inductive LookupNamespace where
  | type
  | value
  | module
deriving DecidableEq, Repr

structure Module where
  id : ModuleId
  path : ModulePath
deriving DecidableEq, Repr

structure Symbol where
  moduleId : ModuleId
  lookupNamespace : LookupNamespace
  name : String
  visibility : Visibility
  declaration : Nat
deriving DecidableEq, Repr

structure Import where
  importer : ModuleId
  imported : ModuleId
deriving DecidableEq, Repr

structure Environment where
  modules : List Module := []
  symbols : List Symbol := []
  imports : List Import := []

def Environment.module? (environment : Environment) (id : ModuleId) : Option Module :=
  environment.modules.find? (fun declaration => declaration.id == id)

def Environment.moduleByPath?
    (environment : Environment) (path : ModulePath) : Option Module :=
  environment.modules.find? (fun declaration => declaration.path == path)

def Environment.importsModule
    (environment : Environment) (importer imported : ModuleId) : Prop :=
  ∃ declaration ∈ environment.imports,
    declaration.importer = importer ∧ declaration.imported = imported

inductive Reference where
  | unqualified (lookupNamespace : LookupNamespace) (name : String)
  | qualified (lookupNamespace : LookupNamespace) (modulePath : ModulePath) (name : String)
deriving DecidableEq, Repr

def HasLocalDeclaration
    (environment : Environment) (current : ModuleId)
    (lookupNamespace : LookupNamespace) (name : String) : Prop :=
  ∃ symbol ∈ environment.symbols,
    symbol.moduleId = current ∧
    symbol.lookupNamespace = lookupNamespace ∧
    symbol.name = name

/-- A declaration is a candidate only through the language's module and
    visibility rules. A local declaration shadows imported declarations in its
    namespace. Otherwise direct imports contribute their exported declarations
    to unqualified lookup and authorize qualified lookup. -/
inductive Candidate
    (environment : Environment) (current : ModuleId) : Reference → Symbol → Prop where
  | local
      (member : symbol ∈ environment.symbols)
      (sameModule : symbol.moduleId = current)
      (sameNamespace : symbol.lookupNamespace = lookupNamespace)
      (sameName : symbol.name = name) :
      Candidate environment current (.unqualified lookupNamespace name) symbol
  | importedUnqualified
      (module : Module)
      (foundModule : module ∈ environment.modules)
      (imported : environment.importsModule current module.id)
      (noLocal : ¬ HasLocalDeclaration environment current lookupNamespace name)
      (member : symbol ∈ environment.symbols)
      (symbolModule : symbol.moduleId = module.id)
      (isPublic : symbol.visibility = .exported)
      (sameNamespace : symbol.lookupNamespace = lookupNamespace)
      (sameName : symbol.name = name) :
      Candidate environment current (.unqualified lookupNamespace name) symbol
  | ownQualified
      (module : Module)
      (foundModule : module ∈ environment.modules)
      (modulePath : module.path = path)
      (isCurrent : module.id = current)
      (member : symbol ∈ environment.symbols)
      (symbolModule : symbol.moduleId = module.id)
      (sameNamespace : symbol.lookupNamespace = lookupNamespace)
      (sameName : symbol.name = name) :
      Candidate environment current (.qualified lookupNamespace path name) symbol
  | importedQualified
      (module : Module)
      (foundModule : module ∈ environment.modules)
      (modulePath : module.path = path)
      (imported : environment.importsModule current module.id)
      (member : symbol ∈ environment.symbols)
      (symbolModule : symbol.moduleId = module.id)
      (isPublic : symbol.visibility = .exported)
      (sameNamespace : symbol.lookupNamespace = lookupNamespace)
      (sameName : symbol.name = name) :
      Candidate environment current (.qualified lookupNamespace path name) symbol

/-- Resolution requires one semantic declaration. Duplicate candidates that
    denote the same declaration are harmless; distinct declarations are an
    ambiguity and no `Resolves` proof exists. -/
def Resolves
    (environment : Environment) (current : ModuleId)
    (reference : Reference) (selected : Symbol) : Prop :=
  Candidate environment current reference selected ∧
    ∀ candidate, Candidate environment current reference candidate →
      candidate.lookupNamespace = selected.lookupNamespace ∧
      candidate.declaration = selected.declaration

def surfacePathNames (path : Surface.Path) : List String :=
  path.segments.map fun
    | .mk name _ => name

def Reference.fromSurfacePath?
    (lookupNamespace : LookupNamespace) (path : Surface.Path) : Option Reference :=
  match (surfacePathNames path).reverse with
  | [] => none
  | name :: reversedModule =>
      match reversedModule.reverse with
      | [] => some (.unqualified lookupNamespace name)
      | modulePath => some (.qualified lookupNamespace modulePath name)

def ModulesHaveUniquePaths (environment : Environment) : Prop :=
  ∀ left, left ∈ environment.modules →
    ∀ right, right ∈ environment.modules → left.path = right.path → left.id = right.id

def SymbolsAreUnique (environment : Environment) : Prop :=
  ∀ left, left ∈ environment.symbols →
    ∀ right, right ∈ environment.symbols →
      left.moduleId = right.moduleId →
      left.lookupNamespace = right.lookupNamespace →
      left.name = right.name → left.declaration = right.declaration

def ImportsExist (environment : Environment) : Prop :=
  ∀ declaration, declaration ∈ environment.imports →
    (environment.module? declaration.importer).isSome ∧
    (environment.module? declaration.imported).isSome

def EnvironmentWellFormed (environment : Environment) : Prop :=
  ModulesHaveUniquePaths environment ∧ SymbolsAreUnique environment ∧
    ImportsExist environment

end Lanius.Names
