import Lanius.Compiler.CoreBoundary
import Lanius.Compiler.StructureCheck
import Lanius.Compiler.ConstantCheck
import Lanius.Compiler.BodyCheck
import Lanius.Compiler.SignatureCheck
import Lanius.Compiler.FunctionContextCheck
import Lanius.Compiler.ExternalFunctionCheck

namespace Lanius.Compiler.ProgramLoweringCheck

open Lanius
open Lanius.Declarations
open Lanius.Compiler.ProgramLowering

/- Executable source addresses and membership checks drive all component exactness. -/
def addressesWhere (p : Surface.Item → Bool) (f : FileId) : Nat → List Surface.Item → List Declarations.ItemAddress
  | _, [] => [] | i, x :: xs => (if p x then [{ file := f, index := i }] else []) ++ addressesWhere p f (i + 1) xs

def packAddressesWhere (p : Surface.Item → Bool) (pack : Declarations.SourcePack) : List Declarations.ItemAddress :=
  pack.files.flatMap fun file => addressesWhere p file.id 0 file.contents.items

def isStructure : Surface.Item → Bool | .structure _ => true | _ => false

def isConstant : Surface.Item → Bool | .constant _ _ _ _ => true | _ => false

def isFunction : Surface.Item → Bool | .function _ => true | _ => false

def isExternal : Surface.Item → Bool | .externFunction _ => true | _ => false

def namedParametersSupported : List Surface.Parameter → Bool
  | [] => true | .named _ _ :: tail => namedParametersSupported tail | _ => false

def supportedItem : Surface.Item → Bool
  | .module _ | .importPath _ => true
  | .function d => d.genericParameters.isEmpty && d.wherePredicates.isEmpty && namedParametersSupported d.parameters
  | .externFunction d => d.abi.isNone && d.genericParameters.isEmpty && d.wherePredicates.isEmpty && namedParametersSupported d.parameters
  | .constant _ _ _ _ => true
  | .typeAlias _ _ parameters predicates _ => parameters.isEmpty && predicates.isEmpty
  | .structure d => d.genericParameters.isEmpty && d.wherePredicates.isEmpty
  | _ => false

def supportedPack (pack : Declarations.SourcePack) : Bool := pack.files.all fun file => file.contents.items.all supportedItem

private theorem namedParametersSupported_sound {parameters : List Surface.Parameter}
    (accepted : namedParametersSupported parameters = true) : NamedParametersSupported parameters := by
  induction parameters with
  | nil => simp [NamedParametersSupported]
  | cons head tail ih =>
      cases head <;> simp [namedParametersSupported] at accepted ⊢
      exact ih accepted

theorem supportedPack_sound {pack : Declarations.SourcePack}
    (accepted : supportedPack pack = true) : SupportedMonomorphic pack := by
  intro file fileMember item itemMember
  have fileAccepted := (List.all_eq_true.mp accepted) file fileMember
  have itemAccepted := (List.all_eq_true.mp fileAccepted) item itemMember
  cases item with
  | module _ | importPath _ => simp [SupportedItem]
  | importString _ => simp [supportedItem] at itemAccepted
  | function declaration =>
      simp [supportedItem] at itemAccepted
      exact ⟨itemAccepted.1.1, itemAccepted.1.2, namedParametersSupported_sound itemAccepted.2⟩
  | externFunction declaration =>
      simp [supportedItem] at itemAccepted
      exact ⟨itemAccepted.1.1.1, itemAccepted.1.1.2, itemAccepted.1.2, namedParametersSupported_sound itemAccepted.2⟩
  | constant _ _ _ _ => simp [SupportedItem]
  | typeAlias _ _ parameters predicates _ =>
      simp [supportedItem, SupportedItem] at itemAccepted
      exact ⟨itemAccepted.1, itemAccepted.2⟩
  | enumeration _ | trait _ | implementation _ =>
      simp [supportedItem, SupportedItem] at itemAccepted
  | «structure» declaration =>
      simpa [supportedItem, SupportedItem] using itemAccepted

def structureLowering? (pack : Declarations.SourcePack) (catalog : Declarations.Catalog) (program : Core.Program)
    (environment : Names.Environment) (baseContext : SurfaceElaboration.Context) (rows : List (DeclarationLowering pack catalog program))
    (entry : { row : DeclarationLowering pack catalog program // row ∈ rows }) (names : baseContext.names = environment) :
    Option (StructureLowering pack catalog program environment baseContext rows) :=
  let row := entry.1
  match hOcc : row.occurrence with
  | .item address =>
      match sourceFound : pack.item? address with
      | some (.structure declaration) =>
          match hcore : row.core with
          | .structure core =>
              let context := baseContext.forModule row.header.moduleId
              let candidate : StructureCheck.StructureCandidate pack catalog program environment baseContext rows :=
                { row := row, rowMember := entry.2, address := address, declaration := declaration,
                  sourceFound := sourceFound, source := hOcc, core := core, coreMap := hcore,
                  context := context, contextMatches := ⟨names, rfl, rfl, rfl, rfl, rfl, rfl⟩, noLocals := rfl }
              match StructureCheck.check candidate with
              | .ok lowering => some lowering | .error _ => none
          | _ => none
      | _ => none
  | _ => none

def constantLowering? (pack : Declarations.SourcePack) (catalog : Declarations.Catalog) (program : Core.Program)
    (environment : Names.Environment) (baseContext : SurfaceElaboration.Context) (rows : List (DeclarationLowering pack catalog program))
    (entry : { row : DeclarationLowering pack catalog program // row ∈ rows })
    (names : baseContext.names = environment) (target : program.target = baseContext.target) :
    Option (ConstantLowering pack catalog program environment baseContext rows) :=
  let row := entry.1
  match hOcc : row.occurrence with
  | .item address =>
      match sourceFound : pack.item? address with
      | some (.constant name isPublic surfaceType value) =>
          match hcore : row.core with
          | .constant core =>
              let context := baseContext.forModule row.header.moduleId
              let candidate : ConstantCheck.ConstantCandidate pack catalog program environment baseContext rows :=
                { row := row, rowMember := entry.2, address := address, name := name, isPublic := isPublic,
                  surfaceType := surfaceType, value := value, sourceFound := sourceFound, source := hOcc,
                  core := core, coreMap := hcore, context := context,
                  contextMatches := ⟨names, rfl, rfl, rfl, rfl, rfl, rfl⟩,
                  target := by change program.target = baseContext.target; exact target, noLocals := rfl }
              match ConstantCheck.check candidate with
              | .ok lowering => some lowering | .error _ => none
          | _ => none
      | _ => none
  | _ => none

def bodyLowering? (pack : Declarations.SourcePack) (catalog : Declarations.Catalog) (program : Core.Program)
    (environment : Names.Environment) (baseContext : SurfaceElaboration.Context) (rows : List (DeclarationLowering pack catalog program))
    (entry : { row : DeclarationLowering pack catalog program // row ∈ rows })
    (names : baseContext.names = environment) (target : program.target = baseContext.target) :
    Option (FunctionBodyLowering pack catalog program environment baseContext rows) :=
  let row := entry.1
  match hOcc : row.occurrence with
  | .item address =>
      match sourceFound : pack.item? address with
      | some (.function declaration) =>
          match hcore : row.core with
          | .function core =>
              match FunctionContextCheck.checkFunction baseContext row.header.moduleId
                  declaration core with
              | .error _ => none | .ok contextEvidence =>
                  let candidate : BodyCheck.FunctionBodyCandidate pack catalog program environment baseContext rows :=
                    { row := row, rowMember := entry.2, address := address, declaration := declaration,
                      sourceFound := sourceFound, source := hOcc, core := core, coreMap := hcore,
                      context := contextEvidence.context, next := contextEvidence.next,
                      parameters := contextEvidence.signature.parameters.down,
                      returnType := contextEvidence.signature.returnType.down,
                      contextMatches := by simpa [names] using contextEvidence.contextMatches,
                      parameterContext := contextEvidence.parameterContext,
                      target := target.trans contextEvidence.contextMatches.2.1.symm }
                  match BodyCheck.check candidate with
                  | .ok lowering => some lowering | .error _ => none
          | _ => none
      | _ => none
  | _ => none

def externalLowering? (pack : Declarations.SourcePack) (catalog : Declarations.Catalog) (program : Core.Program)
    (environment : Names.Environment) (baseContext : SurfaceElaboration.Context) (resolver : ExternalBehaviorResolver)
    (rows : List (DeclarationLowering pack catalog program))
    (entry : { row : DeclarationLowering pack catalog program // row ∈ rows }) (names : baseContext.names = environment) :
    Option (ExternalFunctionLowering pack catalog program environment baseContext resolver rows) :=
  let row := entry.1
  match hOcc : row.occurrence with
  | .item address =>
      match sourceFound : pack.item? address with
      | some (.externFunction declaration) =>
          match hcore : row.core with
          | .function core =>
              match FunctionContextCheck.checkExternFunction baseContext row.header.moduleId
                  declaration core with
              | .error _ => none | .ok contextEvidence =>
                  let candidate : ExternalFunctionCheck.ExternalFunctionCandidate pack catalog program environment baseContext rows :=
                    { row := row, rowMember := entry.2, address := address, declaration := declaration,
                      sourceFound := sourceFound, source := hOcc, core := core, coreMap := hcore,
                      context := contextEvidence.context,
                      contextMatches := by simpa [names] using contextEvidence.contextMatches }
                  match ExternalFunctionCheck.check resolver candidate with
                  | .ok lowering => some lowering | .error _ => none
          | _ => none
      | _ => none
  | _ => none

def structureLowerings (pack : Declarations.SourcePack) (catalog : Declarations.Catalog)
    (program : Core.Program) (environment : Names.Environment) (baseContext : SurfaceElaboration.Context)
    (rows : List (DeclarationLowering pack catalog program)) (names : baseContext.names = environment) :
    List (StructureLowering pack catalog program environment baseContext rows) :=
  rows.attach.filterMap (fun entry => structureLowering? pack catalog program environment baseContext rows entry names)

def constantLowerings (pack : Declarations.SourcePack) (catalog : Declarations.Catalog)
    (program : Core.Program) (environment : Names.Environment) (baseContext : SurfaceElaboration.Context)
    (rows : List (DeclarationLowering pack catalog program)) (names : baseContext.names = environment)
    (target : program.target = baseContext.target) : List (ConstantLowering pack catalog program environment baseContext rows) :=
  rows.attach.filterMap (fun entry => constantLowering? pack catalog program environment baseContext rows entry names target)

def bodyLowerings (pack : Declarations.SourcePack) (catalog : Declarations.Catalog)
    (program : Core.Program) (environment : Names.Environment) (baseContext : SurfaceElaboration.Context)
    (rows : List (DeclarationLowering pack catalog program)) (names : baseContext.names = environment)
    (target : program.target = baseContext.target) : List (FunctionBodyLowering pack catalog program environment baseContext rows) :=
  rows.attach.filterMap (fun entry => bodyLowering? pack catalog program environment baseContext rows entry names target)

def externalLowerings (pack : Declarations.SourcePack) (catalog : Declarations.Catalog)
    (program : Core.Program) (environment : Names.Environment) (baseContext : SurfaceElaboration.Context)
    (resolver : ExternalBehaviorResolver) (rows : List (DeclarationLowering pack catalog program))
    (names : baseContext.names = environment) : List (ExternalFunctionLowering pack catalog program environment baseContext resolver rows) :=
  rows.attach.filterMap (fun entry => externalLowering? pack catalog program environment baseContext resolver rows entry names)

private theorem addressesWhere_get {predicate : Surface.Item → Bool} {file : FileId} {start index : Nat}
    {items : List Surface.Item} {item : Surface.Item} (found : items[index]? = some item)
    (accepted : predicate item = true) : { file := file, index := start + index } ∈ addressesWhere predicate file start items := by
  induction items generalizing start index item with
  | nil => simp at found
  | cons head tail ih =>
      cases index with
      | zero =>
          have headEq : head = item := by simpa using found
          subst item
          simp [addressesWhere, accepted]
      | succ index =>
          have tailFound : tail[index]? = some item := by simpa using found
          have tailMember := ih (start := start + 1) tailFound accepted
          simp only [addressesWhere, List.mem_append]
          exact Or.inr (by simpa [Nat.add_assoc, Nat.add_comm, Nat.add_left_comm] using tailMember)

theorem packAddressesWhere_mem {predicate : Surface.Item → Bool} {pack : Declarations.SourcePack}
    {address : Declarations.ItemAddress} {file : Declarations.SourceFile} {item : Surface.Item}
    (fileFound : pack.file? address.file = some file) (itemFound : pack.item? address = some item)
    (accepted : predicate item = true) : address ∈ packAddressesWhere predicate pack := by
  have localFound : file.contents.items[address.index]? = some item := by simpa [Declarations.SourcePack.item?, fileFound] using itemFound
  have localMember := addressesWhere_get (file := file.id) (start := 0) localFound accepted
  have addressFile : address.file = file.id := Declarations.fileId_of_found_pack fileFound
  have fileMember : file ∈ pack.files := by simpa [Declarations.SourcePack.file?] using (List.mem_of_find?_eq_some fileFound)
  apply List.mem_flatMap.mpr; refine ⟨file, fileMember, ?_⟩
  have addressEq : address = { file := file.id, index := address.index } := by cases address with | mk addressFile index => simp_all
  rw [addressEq]; simpa using localMember

def coveredBy {α : Type} (addresses : List Declarations.ItemAddress) (rows : List α)
    (address : α → Declarations.ItemAddress) : Bool :=
  addresses.all fun expected => rows.any fun row => decide (address row = expected)

theorem coveredBy_sound {α : Type} {addresses : List Declarations.ItemAddress} {rows : List α}
    {address : α → Declarations.ItemAddress} (accepted : coveredBy addresses rows address = true) :
    ∀ expected, expected ∈ addresses → ∃ row, row ∈ rows ∧ address row = expected := by
  intro expected member
  have selected := (List.all_eq_true.mp accepted) expected member
  rcases List.any_eq_true.mp selected with ⟨row, rowMember, rowAddress⟩
  exact ⟨row, rowMember, of_decide_eq_true rowAddress⟩

theorem packAddressesWhere_item_mem {predicate : Surface.Item → Bool} {pack : Declarations.SourcePack}
    {address : Declarations.ItemAddress} {item : Surface.Item} (itemFound : pack.item? address = some item)
    (accepted : predicate item = true) : address ∈ packAddressesWhere predicate pack := by
  cases hFile : pack.file? address.file with
  | none => simp [Declarations.SourcePack.item?, hFile] at itemFound
  | some file => exact packAddressesWhere_mem hFile itemFound accepted

theorem lowerings_coverage {α : Type} {pack : Declarations.SourcePack} {lowerings : List α}
    (address : α → Declarations.ItemAddress) (accepted : coveredBy (packAddressesWhere predicate pack) lowerings address = true)
    {expected : Declarations.ItemAddress} {item : Surface.Item} (itemFound : pack.item? expected = some item)
    (kind : predicate item = true) : ∃ lowering, lowering ∈ lowerings ∧ address lowering = expected := by
  exact coveredBy_sound accepted expected
    (packAddressesWhere_item_mem itemFound kind)

theorem lowerings_unique {α β : Type} {pack : Declarations.SourcePack} {catalog : Declarations.Catalog}
    {program : Core.Program} {rows : List (DeclarationLowering pack catalog program)}
    (declarations : DeclarationLoweringsExact pack catalog program rows) (lowerings : List α)
    (row : α → DeclarationLowering pack catalog program) (address : α → Declarations.ItemAddress) (core : α → β)
    (embed : β → CoreDeclaration) (embedInjective : Function.Injective embed)
    (source : ∀ lowering, lowering ∈ lowerings → (row lowering).occurrence = .item (address lowering))
    (rowMember : ∀ lowering, lowering ∈ lowerings → row lowering ∈ rows)
    (rowCore : ∀ lowering, (row lowering).core = embed (core lowering)) :
    ∀ left ∈ lowerings, ∀ right ∈ lowerings, address left = address right → core left = core right := by
  intro left leftMember right rightMember addressEq
  have occurrenceEq : (row left).occurrence = (row right).occurrence := by
    calc (row left).occurrence = .item (address left) := source left leftMember
      _ = .item (address right) := by rw [addressEq]
      _ = (row right).occurrence := (source right rightMember).symm
  have coreEq := declarations.2.2.2.2 (row left) (rowMember left leftMember)
    (row right) (rowMember right rightMember) occurrenceEq
  rw [rowCore left, rowCore right] at coreEq
  exact embedInjective coreEq.2

inductive Failure where
  | environmentMismatch
  | contextEnvironmentMismatch
  | contextTargetMismatch
  | unsupportedSource
  | missingStructures
  | missingConstants
  | missingBodies
  | missingExternals
deriving DecidableEq, Repr

def check
    (checked : CoreBoundary.Checked encoded expectedSources frontend program)
    (baseContext : SurfaceElaboration.Context) (environment : Names.Environment)
    (resolver : ExternalBehaviorResolver) :
    Except Failure ProgramLowering :=
  let pack := FrontendBoundary.frontendPack frontend.frontend
  let catalog := frontend.catalog.catalog
  let imports := frontend.imports
  if hEnvironment : environment = Declarations.nameEnvironment pack catalog imports then
    if hNames : baseContext.names = environment then
      if hTarget : baseContext.target = program.target then
        if hEligible : supportedPack pack = true then
          let rows := checked.declarations.rows
          let structures := structureLowerings pack catalog program environment baseContext rows hNames
          let constants := constantLowerings pack catalog program environment baseContext rows hNames hTarget.symm
          let bodies := bodyLowerings pack catalog program environment baseContext rows hNames hTarget.symm
          let externals := externalLowerings pack catalog program environment baseContext resolver rows hNames
          let structureCovered := coveredBy (packAddressesWhere isStructure pack) structures
            StructureLowering.address
          let constantCovered := coveredBy (packAddressesWhere isConstant pack) constants
            ConstantLowering.address
          let bodyCovered := coveredBy (packAddressesWhere isFunction pack) bodies
            FunctionBodyLowering.address
          let externalCovered := coveredBy (packAddressesWhere isExternal pack) externals
            ExternalFunctionLowering.address
          if hStructures : structureCovered = true then
            if hConstants : constantCovered = true then
              if hBodies : bodyCovered = true then
                if hExternals : externalCovered = true then
                  have structureInjective : Function.Injective CoreDeclaration.structure := fun _ _ h => by injection h
                  have constantInjective : Function.Injective CoreDeclaration.constant := fun _ _ h => by injection h
                  have functionInjective : Function.Injective CoreDeclaration.function := fun _ _ h => by injection h
                  let structureExact : StructureLoweringsExact
                      pack catalog program environment baseContext rows structures :=
                    ⟨(by intro address declaration found; exact lowerings_coverage StructureLowering.address hStructures found rfl),
                      lowerings_unique checked.declarations.exact structures
                        StructureLowering.row StructureLowering.address StructureLowering.core
                        CoreDeclaration.structure structureInjective
                        (fun row _ => row.source) (fun row _ => row.rowMember)
                        (fun row => row.coreMap)⟩
                  let constantExact : ConstantLoweringsExact
                      pack catalog program environment baseContext rows constants :=
                    ⟨(by intro address name isPublic surfaceType value found; exact lowerings_coverage ConstantLowering.address hConstants found rfl),
                      lowerings_unique checked.declarations.exact constants
                        ConstantLowering.row ConstantLowering.address ConstantLowering.core
                        CoreDeclaration.constant constantInjective
                        (fun row _ => row.source) (fun row _ => row.rowMember)
                        (fun row => row.coreMap)⟩
                  let bodyExact : FunctionBodiesExact
                      pack catalog program environment baseContext rows bodies :=
                    ⟨(by intro address declaration found; exact lowerings_coverage FunctionBodyLowering.address hBodies found rfl),
                      lowerings_unique checked.declarations.exact bodies
                        FunctionBodyLowering.row FunctionBodyLowering.address FunctionBodyLowering.core
                        CoreDeclaration.function functionInjective
                        (fun row _ => row.source) (fun row _ => row.rowMember)
                        (fun row => row.coreMap)⟩
                  let externalExact : ExternalFunctionLoweringsExact
                      pack catalog program environment baseContext resolver rows externals :=
                    ⟨(by intro address declaration found; exact lowerings_coverage ExternalFunctionLowering.address hExternals found rfl),
                      lowerings_unique checked.declarations.exact externals
                        ExternalFunctionLowering.row ExternalFunctionLowering.address
                        ExternalFunctionLowering.core CoreDeclaration.function functionInjective
                        (fun row _ => row.source) (fun row _ => row.rowMember)
                        (fun row => row.coreMap)⟩
                  .ok {
                    pack := pack
                    catalog := catalog
                    imports := imports
                    environment := environment
                    context := baseContext
                    program := program
                    sourceWellFormed := (CoreBoundary.checked_evidence (checked := checked)).1
                    catalogWellFormed := (CoreBoundary.checked_evidence (checked := checked)).2.1
                    importsWellFormed := (CoreBoundary.checked_evidence (checked := checked)).2.2.1
                    eligible := supportedPack_sound hEligible
                    environmentMatches := hEnvironment
                    contextEnvironment := hNames
                    contextTarget := hTarget
                    declarations := rows
                    declarationsExact := checked.declarations.exact
                    aliases := checked.declarations.aliases
                    aliasesExact := checked.declarations.aliasesExact
                    structures := structures
                    structuresExact := structureExact
                    functionBodies := bodies
                    functionBodiesExact := bodyExact
                    externalBehavior := resolver
                    externals := externals
                    externalsExact := externalExact
                    constants := constants
                    constantsExact := constantExact
                    noEnumerations := checked.declarations.enumerationsEmpty
                    structuresUnique := checked.declarations.structuresIdsUnique
                    constantsUnique := checked.declarations.constantsIdsUnique
                    functionsUnique := checked.declarations.functionsIdsUnique
                    wellTyped := checked.typing.down }
                else .error .missingExternals
              else .error .missingBodies
            else .error .missingConstants
          else .error .missingStructures
        else .error .unsupportedSource
      else .error .contextTargetMismatch
    else .error .contextEnvironmentMismatch
  else .error .environmentMismatch

end Lanius.Compiler.ProgramLoweringCheck
