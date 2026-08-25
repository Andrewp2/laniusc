import Lanius.Names
import Lanius.SurfaceSyntax

namespace Lanius.Declarations

open Lanius

/-- Declared package files contain exactly one leading `module`; synthetic
    files (for direct snippets or generated inputs) receive their module
    identity from the source-pack loader and contain no module declaration. -/
inductive SourceOrigin where
  | declared
  | synthetic
deriving DecidableEq, Repr

/-- The source-pack loader assigns file and module identities before language
    declaration collection. These identities are semantic inputs; filesystem
    paths and compiler token offsets are not. -/
structure SourceFile where
  id : FileId
  moduleInfo : Names.Module
  contents : Surface.File
  origin : SourceOrigin := .declared

structure SourcePack where
  files : List SourceFile := []

def SourcePack.file? (pack : SourcePack) (id : FileId) : Option SourceFile :=
  pack.files.find? (fun file => file.id == id)

structure ItemAddress where
  file : FileId
  index : Nat
deriving DecidableEq, Repr

def SourcePack.item? (pack : SourcePack) (address : ItemAddress) : Option Surface.Item := do
  let file ← pack.file? address.file
  file.contents.items[address.index]?

def plainPath? (path : Surface.Path) : Option Names.ModulePath :=
  match path.segments with
  | [] => none
  | segments =>
      segments.mapM fun
        | .mk name [] => some name
        | .mk _ (_ :: _) => none

theorem emptyPathIsNotAModulePath :
    plainPath? { segments := [] } = none := by
  rfl

def IsModuleItem (item : Surface.Item) : Prop :=
  ∃ path, item = .module path

def IsImportItem (item : Surface.Item) : Prop :=
  (∃ path, item = .importPath path) ∨
  ∃ literal, item = .importString literal

/-- Imports form one leading block. In a declared file the module header may
    precede that block; no declaration-bearing item may precede an import. -/
def ImportsAreLeading (file : SourceFile) : Prop :=
  ∀ (importIndex : Nat) importItem,
    file.contents.items[importIndex]? = some importItem → IsImportItem importItem →
    ∀ (itemIndex : Nat) item,
      file.contents.items[itemIndex]? = some item →
      ¬ IsModuleItem item → ¬ IsImportItem item →
      importIndex < itemIndex

theorem declarationBeforeImportRejectsLeading
    (importIndex itemIndex : Nat)
    (importFound : file.contents.items[importIndex]? = some importItem)
    (isImport : IsImportItem importItem)
    (declarationFound : file.contents.items[itemIndex]? = some item)
    (notModule : ¬ IsModuleItem item)
    (notImport : ¬ IsImportItem item)
    (notBefore : ¬ importIndex < itemIndex) :
    ¬ ImportsAreLeading file := by
  intro leading
  exact notBefore
    (leading importIndex importItem importFound isImport itemIndex item
      declarationFound notModule notImport)

def DeclaredModuleMatches (file : SourceFile) : Prop :=
  ∃ path,
    file.contents.items[0]? = some (.module path) ∧
    plainPath? path = some file.moduleInfo.path ∧
    ∀ (index : Nat) (item : Surface.Item),
      file.contents.items[index]? = some item → IsModuleItem item → index = 0

def SyntheticHasNoModule (file : SourceFile) : Prop :=
  ∀ (index : Nat) (item : Surface.Item),
    file.contents.items[index]? = some item → ¬ IsModuleItem item

def SourceFileWellFormed (file : SourceFile) : Prop :=
  SurfaceSyntax.FileWellFormed file.contents ∧
    file.moduleInfo.path ≠ [] ∧
    (match file.origin with
     | .declared => DeclaredModuleMatches file
     | .synthetic => SyntheticHasNoModule file) ∧
    ImportsAreLeading file

def SourceFileIdsUnique (pack : SourcePack) : Prop :=
  ∀ left, left ∈ pack.files →
    ∀ right, right ∈ pack.files → left.id = right.id → left = right

def SourceModulesUnique (pack : SourcePack) : Prop :=
  ∀ left, left ∈ pack.files →
    ∀ right, right ∈ pack.files →
      (left.moduleInfo.id = right.moduleInfo.id ∨
       left.moduleInfo.path = right.moduleInfo.path) → left.id = right.id

def SourcePackWellFormed (pack : SourcePack) : Prop :=
  (∀ file, file ∈ pack.files → SourceFileWellFormed file) ∧
    SourceFileIdsUnique pack ∧ SourceModulesUnique pack

def visibility (isPublic : Bool) : Names.Visibility :=
  if isPublic then .exported else .modulePrivate

inductive DeclarationKind where
  | function
  | externalFunction
  | constant
  | typeAlias
  | structureType
  | enumeration
  | enumVariant
  | trait
  | traitMethod
  | implementation
  | implementationMethod
deriving DecidableEq, Repr

/-- Nested declarations use their ordinal within the parent declaration. This
    distinguishes identical-looking methods and variants without importing
    parser-node or token identities into the language definition. -/
inductive DeclarationOccurrence where
  | item (address : ItemAddress)
  | enumVariant (parent : ItemAddress) (index : Nat)
  | traitMethod (parent : ItemAddress) (index : Nat)
  | implementationMethod (parent : ItemAddress) (index : Nat)
deriving DecidableEq, Repr

structure DeclarationHeader where
  source : DeclarationOccurrence
  moduleId : ModuleId
  declaration : Nat
  kind : DeclarationKind
  lookupNamespace : Option Names.LookupNamespace := none
  name : Option String := none
  visibility : Names.Visibility := .modulePrivate
deriving DecidableEq, Repr

/-- `Occurs` is the complete set of declaration-bearing syntax. Module and
    import items deliberately do not occur here; they are collected into the
    module graph rather than a value/type declaration namespace. -/
inductive Occurs (pack : SourcePack) : DeclarationOccurrence → Prop where
  | function
      (fileFound : pack.file? address.file = some file)
      (itemFound : pack.item? address = some (.function declaration)) :
      Occurs pack (.item address)
  | externalFunction
      (fileFound : pack.file? address.file = some file)
      (itemFound : pack.item? address = some (.externFunction declaration)) :
      Occurs pack (.item address)
  | constant
      (fileFound : pack.file? address.file = some file)
      (itemFound : pack.item? address = some (.constant name isPublic type value)) :
      Occurs pack (.item address)
  | typeAlias
      (fileFound : pack.file? address.file = some file)
      (itemFound : pack.item? address =
        some (.typeAlias name isPublic parameters predicates target)) :
      Occurs pack (.item address)
  | structureType
      (fileFound : pack.file? address.file = some file)
      (itemFound : pack.item? address = some (.structure declaration)) :
      Occurs pack (.item address)
  | enumeration
      (fileFound : pack.file? address.file = some file)
      (itemFound : pack.item? address = some (.enumeration declaration)) :
      Occurs pack (.item address)
  | trait
      (fileFound : pack.file? address.file = some file)
      (itemFound : pack.item? address = some (.trait declaration)) :
      Occurs pack (.item address)
  | implementation
      (fileFound : pack.file? address.file = some file)
      (itemFound : pack.item? address = some (.implementation declaration)) :
      Occurs pack (.item address)
  | enumVariant
      (fileFound : pack.file? parent.file = some file)
      (itemFound : pack.item? parent = some (.enumeration declaration))
      (childFound : declaration.variants[index]? = some variant) :
      Occurs pack (.enumVariant parent index)
  | traitMethod
      (fileFound : pack.file? parent.file = some file)
      (itemFound : pack.item? parent = some (.trait declaration))
      (childFound : declaration.methods[index]? = some method) :
      Occurs pack (.traitMethod parent index)
  | implementationMethod
      (fileFound : pack.file? parent.file = some file)
      (itemFound : pack.item? parent = some (.implementation declaration))
      (childFound : declaration.methods[index]? = some method) :
      Occurs pack (.implementationMethod parent index)

/-- A header is correct only if every visible field is derived from its source
    declaration. The only freely assigned component is the dense semantic
    declaration ID. -/
inductive HeaderMatches (pack : SourcePack) : DeclarationHeader → Prop where
  | function
      (fileFound : pack.file? address.file = some file)
      (itemFound : pack.item? address = some (.function function)) :
      HeaderMatches pack {
        source := .item address
        moduleId := file.moduleInfo.id
        declaration := declarationId
        kind := .function
        lookupNamespace := some .value
        name := some function.name
        visibility := visibility function.isPublic
      }
  | externalFunction
      (fileFound : pack.file? address.file = some file)
      (itemFound : pack.item? address = some (.externFunction function)) :
      HeaderMatches pack {
        source := .item address
        moduleId := file.moduleInfo.id
        declaration := declarationId
        kind := .externalFunction
        lookupNamespace := some .value
        name := some function.name
        visibility := visibility function.isPublic
      }
  | constant
      (fileFound : pack.file? address.file = some file)
      (itemFound : pack.item? address = some (.constant name isPublic type value)) :
      HeaderMatches pack {
        source := .item address
        moduleId := file.moduleInfo.id
        declaration := declarationId
        kind := .constant
        lookupNamespace := some .value
        name := some name
        visibility := visibility isPublic
      }
  | typeAlias
      (fileFound : pack.file? address.file = some file)
      (itemFound : pack.item? address =
        some (.typeAlias name isPublic parameters predicates target)) :
      HeaderMatches pack {
        source := .item address
        moduleId := file.moduleInfo.id
        declaration := declarationId
        kind := .typeAlias
        lookupNamespace := some .type
        name := some name
        visibility := visibility isPublic
      }
  | structureType
      (fileFound : pack.file? address.file = some file)
      (itemFound : pack.item? address = some (.structure structureDeclaration)) :
      HeaderMatches pack {
        source := .item address
        moduleId := file.moduleInfo.id
        declaration := declarationId
        kind := .structureType
        lookupNamespace := some .type
        name := some structureDeclaration.name
        visibility := visibility structureDeclaration.isPublic
      }
  | enumeration
      (fileFound : pack.file? address.file = some file)
      (itemFound : pack.item? address = some (.enumeration enumeration)) :
      HeaderMatches pack {
        source := .item address
        moduleId := file.moduleInfo.id
        declaration := declarationId
        kind := .enumeration
        lookupNamespace := some .type
        name := some enumeration.name
        visibility := visibility enumeration.isPublic
      }
  | trait
      (fileFound : pack.file? address.file = some file)
      (itemFound : pack.item? address = some (.trait trait)) :
      HeaderMatches pack {
        source := .item address
        moduleId := file.moduleInfo.id
        declaration := declarationId
        kind := .trait
        lookupNamespace := some .type
        name := some trait.name
        visibility := visibility trait.isPublic
      }
  | implementation
      (fileFound : pack.file? address.file = some file)
      (itemFound : pack.item? address = some (.implementation implementation)) :
      HeaderMatches pack {
        source := .item address
        moduleId := file.moduleInfo.id
        declaration := declarationId
        kind := .implementation
        visibility := visibility implementation.isPublic
      }
  | enumVariant
      (fileFound : pack.file? parent.file = some file)
      (itemFound : pack.item? parent = some (.enumeration enumeration))
      (childFound : enumeration.variants[index]? = some variant) :
      HeaderMatches pack {
        source := .enumVariant parent index
        moduleId := file.moduleInfo.id
        declaration := declarationId
        kind := .enumVariant
        lookupNamespace := some .value
        name := some variant.name
        visibility := visibility enumeration.isPublic
      }
  | traitMethod
      (fileFound : pack.file? parent.file = some file)
      (itemFound : pack.item? parent = some (.trait trait))
      (childFound : trait.methods[index]? = some method) :
      HeaderMatches pack {
        source := .traitMethod parent index
        moduleId := file.moduleInfo.id
        declaration := declarationId
        kind := .traitMethod
        name := some method.signature.name
        visibility := visibility method.signature.isPublic
      }
  | implementationMethod
      (fileFound : pack.file? parent.file = some file)
      (itemFound : pack.item? parent = some (.implementation implementation))
      (childFound : implementation.methods[index]? = some method) :
      HeaderMatches pack {
        source := .implementationMethod parent index
        moduleId := file.moduleInfo.id
        declaration := declarationId
        kind := .implementationMethod
        name := some method.name
        visibility := visibility method.isPublic
      }

structure Catalog where
  headers : List DeclarationHeader := []

inductive ImportOccurrence where
  | item (address : ItemAddress)
deriving DecidableEq, Repr

/-- A collected import is a resolved direct edge in the module graph. Quoted
    import syntax cannot construct this record because it has no elaboration
    rule in the current language. -/
structure CollectedImport where
  source : ImportOccurrence
  importer : ModuleId
  imported : ModuleId
deriving DecidableEq, Repr

inductive ImportOccurs (pack : SourcePack) : ImportOccurrence → Prop where
  | path
      (fileFound : pack.file? address.file = some file)
      (itemFound : pack.item? address = some (.importPath path)) :
      ImportOccurs pack (.item address)
  | string
      (fileFound : pack.file? address.file = some file)
      (itemFound : pack.item? address = some (.importString literal)) :
      ImportOccurs pack (.item address)

inductive ImportMatches (pack : SourcePack) : CollectedImport → Prop where
  | path
      (fileFound : pack.file? address.file = some file)
      (itemFound : pack.item? address = some (.importPath path))
      (plain : plainPath? path = some importedFile.moduleInfo.path)
      (importedMember : importedFile ∈ pack.files)
      (different : file.moduleInfo.id ≠ importedFile.moduleInfo.id) :
      ImportMatches pack {
        source := .item address
        importer := file.moduleInfo.id
        imported := importedFile.moduleInfo.id
      }

def ImportCollectionCovers
    (pack : SourcePack) (imports : List CollectedImport) : Prop :=
  (∀ occurrence, ImportOccurs pack occurrence →
    ∃ selected,
      selected ∈ imports ∧ selected.source = occurrence ∧ ImportMatches pack selected ∧
      ∀ candidate,
        candidate ∈ imports → candidate.source = occurrence →
      ImportMatches pack candidate → candidate = selected) ∧
  ∀ declaration, declaration ∈ imports → ImportMatches pack declaration

/-- Quoted imports are syntactically observable but deliberately have no
    matching import declaration in the current language. Consequently a pack
    containing one cannot satisfy the import-collection completeness rule. -/
theorem quotedImportRejectsCollection
    (fileFound : pack.file? address.file = some file)
    (itemFound : pack.item? address = some (.importString literal)) :
    ¬ ∃ imports, ImportCollectionCovers pack imports := by
  intro collection
  obtain ⟨imports, covers⟩ := collection
  obtain ⟨selected, _, _, matched, _⟩ :=
    covers.1 (.item address) (.string fileFound itemFound)
  cases matched
  simp_all

/-- Strict list order, used to witness a dependency-ready module schedule. -/
def AppearsBefore (first second : ModuleId) (order : List ModuleId) : Prop :=
  order.idxOf first < order.idxOf second

theorem notAppearsBeforeSelf (moduleId : ModuleId) (order : List ModuleId) :
    ¬ AppearsBefore moduleId moduleId order := by
  simp [AppearsBefore]

theorem notAppearsBeforeBothWays
    (left right : ModuleId) (order : List ModuleId) :
    ¬ (AppearsBefore left right order ∧ AppearsBefore right left order) := by
  intro both
  exact Nat.lt_asymm both.1 both.2

/-- A valid module schedule contains each source-pack module exactly once and
    places every directly imported module before its importer. Existence of
    such a schedule is the constructive acyclicity criterion. -/
def ModuleDependencyOrderCovers
    (pack : SourcePack) (imports : List CollectedImport)
    (order : List ModuleId) : Prop :=
  order.Pairwise (· ≠ ·) ∧
  (∀ file, file ∈ pack.files → file.moduleInfo.id ∈ order) ∧
  (∀ moduleId, moduleId ∈ order →
    ∃ file ∈ pack.files, file.moduleInfo.id = moduleId) ∧
  ∀ declaration, declaration ∈ imports →
    AppearsBefore declaration.imported declaration.importer order

def CoversOccurrence
    (pack : SourcePack) (catalog : Catalog)
    (occurrence : DeclarationOccurrence) : Prop :=
  ∃ selected,
    selected ∈ catalog.headers ∧ selected.source = occurrence ∧
      HeaderMatches pack selected ∧
    ∀ candidate,
      candidate ∈ catalog.headers → candidate.source = occurrence →
        HeaderMatches pack candidate → candidate = selected

def CatalogCovers (pack : SourcePack) (catalog : Catalog) : Prop :=
  (∀ occurrence, Occurs pack occurrence →
    CoversOccurrence pack catalog occurrence) ∧
  ∀ header, header ∈ catalog.headers → HeaderMatches pack header

def DeclarationIdsUnique (catalog : Catalog) : Prop :=
  ∀ left, left ∈ catalog.headers →
    ∀ right, right ∈ catalog.headers →
      left.declaration = right.declaration → left.source = right.source

def OccurrencesUnique (catalog : Catalog) : Prop :=
  ∀ left, left ∈ catalog.headers →
    ∀ right, right ∈ catalog.headers →
      left.source = right.source → left.declaration = right.declaration

def CatalogWellFormed (pack : SourcePack) (catalog : Catalog) : Prop :=
  CatalogCovers pack catalog ∧ DeclarationIdsUnique catalog ∧ OccurrencesUnique catalog

def DeclarationHeader.symbol? (header : DeclarationHeader) : Option Names.Symbol := do
  let lookupNamespace ← header.lookupNamespace
  let name ← header.name
  pure {
    moduleId := header.moduleId
    lookupNamespace
    name
    visibility := header.visibility
    declaration := header.declaration
  }

def Catalog.symbols (catalog : Catalog) : List Names.Symbol :=
  catalog.headers.filterMap DeclarationHeader.symbol?

def nameEnvironment
    (pack : SourcePack) (catalog : Catalog)
    (imports : List CollectedImport) : Names.Environment := {
  modules := pack.files.map (·.moduleInfo)
  symbols := catalog.symbols
  imports := imports.map fun declaration => {
    importer := declaration.importer
    imported := declaration.imported
  }
}

end Lanius.Declarations
