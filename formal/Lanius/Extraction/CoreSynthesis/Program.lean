import Lanius.Extraction.ArtifactPackContextChecker
import Lanius.Extraction.CompactArtifact
import Lanius.Extraction.CoreSynthesis
import Lanius.Execution
import Lanius.RuntimeBindings

namespace Lanius.Extraction.CoreSynthesis.Program

open Lanius
open Lanius.Core
open Lanius.SurfaceElaboration
open Lanius.Extraction.SurfaceElaborationChecker
open Lanius.Extraction.ArtifactContextChecker

structure Unit where
  moduleId : ModuleId
  modulePath : Names.ModulePath
  surface : Surface.File

def collectExternFunctions : List Surface.Item → List Surface.ExternFunction
  | [] => []
  | .externFunction declaration :: tail =>
      declaration :: collectExternFunctions tail
  | _ :: tail => collectExternFunctions tail

def externAsFunction (external : Surface.ExternFunction) : Surface.Function := {
  name := external.name
  isPublic := external.isPublic
  genericParameters := external.genericParameters
  parameters := external.parameters
  returnType := external.returnType
  wherePredicates := external.wherePredicates
  body := []
}

def decodeUnitsFrom :
    {artifacts : List Artifact} → Nat →
      ArtifactPackChecker.CheckedUnitSurfaces artifacts → Option (List Unit)
  | [], _, .nil => some []
  | _ :: _, nextModule, .cons head tail => do
      let modulePath ←
        ArtifactPackContextChecker.declaredModulePath? head.surface
      let rest ← decodeUnitsFrom (nextModule + 1) tail
      pure ({ moduleId := nextModule, modulePath, surface := head.surface } :: rest)

def Unit.module (unit : Unit) : Names.Module := {
  id := unit.moduleId
  path := unit.modulePath
}

def findModuleByPath? (units : List Unit)
    (path : Names.ModulePath) : Option ModuleId := do
  let unit ← units.find? fun unit => unit.modulePath == path
  pure unit.moduleId

def collectUnitImports (units : List Unit) (current : Unit) :
    List Surface.Item → Option (List Names.Import)
  | [] => some []
  | .importPath path :: tail => do
      let importedPath ← Declarations.plainPath? path
      let imported ← findModuleByPath? units importedPath
      if imported ≠ current.moduleId then
        let rest ← collectUnitImports units current tail
        pure ({ importer := current.moduleId, imported } :: rest)
      else none
  | .importString _ :: _ => none
  | _ :: tail => collectUnitImports units current tail

def collectImports (units : List Unit) :
    List Unit → Option (List Names.Import)
  | [] => some []
  | head :: tail => do
      let headImports ← collectUnitImports units head head.surface.items
      let rest ← collectImports units tail
      pure (headImports ++ rest)

structure Allocation where
  unit : Unit
  structureDeclarationStart : Nat
  structureTypeStart : TypeId
  typeAliasDeclarationStart : Nat
  constantDeclarationStart : Nat
  constantIdStart : ConstantId
  functionDeclarationStart : Nat
  functionIdStart : FunctionId
  externDeclarationStart : Nat
  externIdStart : FunctionId

def totalStructures (units : List Unit) : Nat :=
  (units.map fun unit => (collectStructures unit.surface.items).length).sum

def totalTypeAliases (units : List Unit) : Nat :=
  (units.map fun unit => (collectTypeAliases unit.surface.items).length).sum

def totalConstants (units : List Unit) : Nat :=
  (units.map fun unit => (collectConstants unit.surface.items).length).sum

def totalCallables (units : List Unit) : Nat :=
  (units.map fun unit =>
    (collectFunctions unit.surface.items).length +
      (collectExternFunctions unit.surface.items).length).sum

def allocateFrom (typeAliasBase constantBase functionBase : Nat) :
    Nat → Nat → Nat → Nat → Nat → Nat → List Unit → List Allocation
  | _, _, _, _, _, _, [] => []
  | structureCursor, aliasCursor, constantCursor, constantIdCursor,
      functionCursor, functionIdCursor, head :: tail =>
      let structures := (collectStructures head.surface.items).length
      let aliases := (collectTypeAliases head.surface.items).length
      let constants := (collectConstants head.surface.items).length
      let functions := (collectFunctions head.surface.items).length
      let externs := (collectExternFunctions head.surface.items).length
      {
        unit := head
        structureDeclarationStart := structureCursor
        structureTypeStart := structureCursor
        typeAliasDeclarationStart := typeAliasBase + aliasCursor
        constantDeclarationStart := constantBase + constantCursor
        constantIdStart := constantIdCursor
        functionDeclarationStart := functionBase + functionCursor
        functionIdStart := functionIdCursor
        externDeclarationStart := functionBase + functionCursor + functions
        externIdStart := functionIdCursor + functions
      } :: allocateFrom typeAliasBase constantBase functionBase
        (structureCursor + structures) (aliasCursor + aliases)
        (constantCursor + constants) (constantIdCursor + constants)
        (functionCursor + functions + externs)
        (functionIdCursor + functions + externs) tail

def allocate (units : List Unit) : List Allocation :=
  let typeAliasBase := totalStructures units
  let constantBase := typeAliasBase + totalTypeAliases units
  let functionBase := constantBase + totalConstants units
  allocateFrom typeAliasBase constantBase functionBase 0 0 0 0 0 0 units

private def nominalSkeletons :
    TypeId → List Surface.StructDecl → List Core.StructDecl
  | _, [] => []
  | next, _ :: tail =>
      { id := next, fields := [] } :: nominalSkeletons (next + 1) tail

structure Headers where
  symbols : List Names.Symbol
  nominalSchemes : List Static.NominalScheme
  nominalInstances : List Static.NominalInstance
  typeAliases : List TypeAliasEntry

private def buildHeaders : List Allocation → Option Headers
  | [] => some ⟨[], [], [], []⟩
  | allocation :: tail => do
      let structures := collectStructures allocation.unit.surface.items
      let aliases := collectTypeAliases allocation.unit.surface.items
      let constants := collectConstants allocation.unit.surface.items
      let functions := collectFunctions allocation.unit.surface.items
      let externs := collectExternFunctions allocation.unit.surface.items
      let nominal ← ArtifactContextChecker.buildNominalHeaders
        allocation.unit.moduleId allocation.structureDeclarationStart
        allocation.structureTypeStart structures
        (nominalSkeletons allocation.structureTypeStart structures)
      let aliasHeaders := ArtifactContextChecker.buildTypeAliasHeaders
        allocation.unit.moduleId allocation.typeAliasDeclarationStart aliases
      let constantSymbols := ArtifactContextChecker.buildConstantSymbols
        allocation.unit.moduleId allocation.constantDeclarationStart constants
      let functionSymbols := ArtifactContextChecker.buildFunctionSymbols
        allocation.unit.moduleId allocation.functionDeclarationStart functions
      let externSymbols := ArtifactContextChecker.buildFunctionSymbols
        allocation.unit.moduleId allocation.externDeclarationStart
        (externs.map externAsFunction)
      let rest ← buildHeaders tail
      pure {
        symbols := nominal.symbols ++ aliasHeaders.symbols ++
          constantSymbols ++ functionSymbols ++ externSymbols ++ rest.symbols
        nominalSchemes := nominal.schemes ++ rest.nominalSchemes
        nominalInstances := nominal.instances ++ rest.nominalInstances
        typeAliases := aliasHeaders.entries ++ rest.typeAliases
      }

private def itemsSupported : List Surface.Item → Bool
  | [] => true
  | .module _ :: tail | .importPath _ :: tail => itemsSupported tail
  | .structure declaration :: tail =>
      listEmptyBool declaration.genericParameters &&
        listEmptyBool declaration.wherePredicates && itemsSupported tail
  | .function declaration :: tail =>
      listEmptyBool declaration.genericParameters &&
        listEmptyBool declaration.wherePredicates && itemsSupported tail
  | .externFunction declaration :: tail =>
      listEmptyBool declaration.genericParameters &&
        listEmptyBool declaration.wherePredicates && itemsSupported tail
  | .typeAlias _ _ parameters predicates _ :: tail =>
      listEmptyBool parameters && listEmptyBool predicates && itemsSupported tail
  | .constant _ _ _ _ :: tail => itemsSupported tail
  | _ :: _ => false

private def allItemsSupported (units : List Unit) : Bool :=
  units.all fun unit => itemsSupported unit.surface.items

private def baseContext? (units : List Unit)
    (allocations : List Allocation) : Option Context := do
  if allItemsSupported units then
    let headers ← buildHeaders allocations
    let imports ← collectImports units units
    let names : Names.Environment := {
      modules := units.map Unit.module
      symbols := headers.symbols
      imports
    }
    let modulePathsUnique ← modulesUniquePaths? names
    let symbolsUnique ← symbolsUnique? names
    pure {
      target := .x86_64
      names
      modulesHaveUniquePaths := some ⟨modulePathsUnique.proof⟩
      symbolsAreUnique := some ⟨symbolsUnique.proof⟩
      currentModule := 0
      monomorphization := ArtifactContextChecker.monomorphizationFrom
        headers.nominalInstances
      nominalSchemes := headers.nominalSchemes
      nominalInstances := headers.nominalInstances
      typeAliases := headers.typeAliases
    }
  else none

private def groundFieldTypes (context : Context) :
    List Surface.StructField → Option (List Core.Ty)
  | [] => some []
  | head :: tail => do
      let grounded ← groundType? context head.type
      let coreType ← grounded.type.toCore context.monomorphization
      let rest ← groundFieldTypes context tail
      pure (coreType :: rest)

private def buildUnitStructs (context : Context) :
    TypeId → List Surface.StructDecl → Option (List Core.StructDecl)
  | _, [] => some []
  | next, head :: tail => do
      let fields ← groundFieldTypes context head.fields
      let rest ← buildUnitStructs context (next + 1) tail
      pure ({ id := next, fields } :: rest)

structure StructPhase where
  declarations : List Core.StructDecl
  fields : List FieldEntry
  constructors : List StructConstructorScheme

private def buildStructPhase (context : Context) :
    List Allocation → Option StructPhase
  | [] => some ⟨[], [], []⟩
  | allocation :: tail => do
      let surfaces := collectStructures allocation.unit.surface.items
      let declarations ← buildUnitStructs
        (context.forModule allocation.unit.moduleId)
        allocation.structureTypeStart surfaces
      let details ← ArtifactContextChecker.buildStructDetails
        (context.forModule allocation.unit.moduleId)
        allocation.structureDeclarationStart allocation.structureTypeStart
        surfaces declarations
      let rest ← buildStructPhase context tail
      pure {
        declarations := declarations ++ rest.declarations
        fields := details.fields ++ rest.fields
        constructors := details.constructors ++ rest.constructors
      }

private def constantSkeletons (context : Context) :
    ConstantId → List SourceConstant → Option (List Core.Constant)
  | _, [] => some []
  | next, head :: tail => do
      let grounded ← groundType? context head.type
      let coreType ← grounded.type.toCore context.monomorphization
      let rest ← constantSkeletons context (next + 1) tail
      pure ({ id := next, type := coreType, value := .unit } :: rest)

structure ConstantPhase where
  skeletons : List Core.Constant
  entries : List ConstantEntry

private def buildConstantPhase (context : Context) :
    List Allocation → Option ConstantPhase
  | [] => some ⟨[], []⟩
  | allocation :: tail => do
      let surfaces := collectConstants allocation.unit.surface.items
      let skeletons ← constantSkeletons
        (context.forModule allocation.unit.moduleId)
        allocation.constantIdStart surfaces
      let entries ← ArtifactContextChecker.buildConstantEntries
        (context.forModule allocation.unit.moduleId)
        allocation.constantDeclarationStart surfaces skeletons
      let rest ← buildConstantPhase context tail
      pure ⟨skeletons ++ rest.skeletons, entries ++ rest.entries⟩

private def parameterSkeletons (context : Context) :
    VarId → List Surface.Parameter → Option (List (VarId × Core.Ty))
  | _, [] => some []
  | next, .named _ type :: tail => do
      let grounded ← groundType? context type
      let coreType ← grounded.type.toCore context.monomorphization
      let rest ← parameterSkeletons context (next + 1) tail
      pure ((next, coreType) :: rest)
  | _, _ => none

private def functionSkeletons (context : Context) :
    FunctionId → List Surface.Function → Option (List Core.Function)
  | _, [] => some []
  | next, head :: tail => do
      let parameters ← parameterSkeletons context 0 head.parameters
      let returned ← groundReturn? context head.name head.returnType
      let returnType ← returned.type.toCore context.monomorphization
      let rest ← functionSkeletons context (next + 1) tail
      pure ({ id := next, parameters, returnType, body := none } :: rest)

structure FunctionHeaderPhase where
  skeletons : List Core.Function
  schemes : List Static.FunctionScheme
  instances : List Static.FunctionInstance

private def buildFunctionHeaderPhase (context : Context) :
    List Allocation → Option FunctionHeaderPhase
  | [] => some ⟨[], [], []⟩
  | allocation :: tail => do
      let surfaces := collectFunctions allocation.unit.surface.items
      let externSurfaces := collectExternFunctions allocation.unit.surface.items
      let externFunctions := externSurfaces.map externAsFunction
      let skeletons ← functionSkeletons
        (context.forModule allocation.unit.moduleId)
        allocation.functionIdStart surfaces
      let externSkeletons ← functionSkeletons
        (context.forModule allocation.unit.moduleId)
        allocation.externIdStart externFunctions
      let headers ← ArtifactContextChecker.buildFunctionHeaders
        (context.forModule allocation.unit.moduleId)
        allocation.functionDeclarationStart surfaces skeletons
      let externHeaders ← ArtifactContextChecker.buildFunctionHeaders
        (context.forModule allocation.unit.moduleId)
        allocation.externDeclarationStart externFunctions externSkeletons
      let rest ← buildFunctionHeaderPhase context tail
      pure {
        skeletons := skeletons ++ externSkeletons ++ rest.skeletons
        schemes := headers.schemes ++ externHeaders.schemes ++ rest.schemes
        instances := headers.instances ++ externHeaders.instances ++ rest.instances
      }

structure Prepared where
  units : List Unit
  allocations : List Allocation
  context : Context
  structures : List Core.StructDecl

def prepare? {artifacts : List Artifact}
    (surfaceData : ArtifactPackChecker.CheckedUnitSurfaces artifacts) :
    Option Prepared := do
  let units ← decodeUnitsFrom 0 surfaceData
  let allocations := allocate units
  let base ← baseContext? units allocations
  let structs ← buildStructPhase base allocations
  let structContext : Context := {
    base with
    fields := structs.fields
    structConstructors := structs.constructors
  }
  let constants ← buildConstantPhase structContext allocations
  let constantContext : Context := {
    structContext with constants := constants.entries
  }
  let functions ← buildFunctionHeaderPhase constantContext allocations
  let context : Context := {
    constantContext with
    functions := functions.schemes
    functionInstances := functions.instances
  }
  pure ⟨units, allocations, context, structs.declarations⟩

private def synthesizeConstants (context : Context) :
    ConstantId → List SourceConstant → Option (List Core.Constant)
  | _, [] => some []
  | next, head :: tail => do
      let grounded ← groundType? context head.type
      let coreType ← grounded.type.toCore context.monomorphization
      let value ← CoreSynthesis.check context head.value grounded.type
      match value.core with
      | .value literal =>
          let rest ← synthesizeConstants context (next + 1) tail
          pure ({ id := next, type := coreType, value := literal } :: rest)
      | _ => none

private def synthesizePackConstants (context : Context) :
    List Allocation → Option (List Core.Constant)
  | [] => some []
  | allocation :: tail => do
      let current ← synthesizeConstants
        (context.forModule allocation.unit.moduleId)
        allocation.constantIdStart
        (collectConstants allocation.unit.surface.items)
      let rest ← synthesizePackConstants context tail
      pure (current ++ rest)

private def constantsLiteral? :
    (constants : List Core.Constant) → Option (Evidence
      (∀ constant, constant ∈ constants →
        Typing.Value.isLiteral constant.value = true))
  | [] => some ⟨by simp⟩
  | head :: tail => do
      if headLiteral : Typing.Value.isLiteral head.value = true then
        let rest ← constantsLiteral? tail
        pure ⟨by
          intro constant member
          simp only [List.mem_cons] at member
          rcases member with rfl | member
          · exact headLiteral
          · exact rest.proof constant member⟩
      else none

def NoOpaqueExternals (functions : List Core.Function) : Prop :=
  ∀ function, function ∈ functions → ∀ external,
    function.external ≠ some (.opaque external)

private def externalNotOpaque? (function : Core.Function) :
    Option (Evidence (∀ external,
      function.external ≠ some (.opaque external))) :=
  match externalShape : function.external with
  | none => some ⟨by simp [externalShape]⟩
  | some (.host _) => some ⟨by simp [externalShape]⟩
  | some (.unavailable _) => some ⟨by simp [externalShape]⟩
  | some .panic => some ⟨by simp [externalShape]⟩
  | some .unreachable => some ⟨by simp [externalShape]⟩
  | some (.opaque _) => none

private def noOpaqueExternals? :
    (functions : List Core.Function) →
      Option (Evidence (NoOpaqueExternals functions))
  | [] => some ⟨by simp [NoOpaqueExternals]⟩
  | head :: tail => do
      let headSafe ← externalNotOpaque? head
      let rest ← noOpaqueExternals? tail
      pure ⟨by
        intro function member external
        simp only [List.mem_cons] at member
        rcases member with rfl | member
        · exact headSafe.proof external
        · exact rest.proof function member external⟩

inductive FunctionBodiesLower (context : Context) :
    FunctionId → List Surface.Function → List Core.Function → Prop where
  | nil : FunctionBodiesLower context next [] []
  | cons
      (sameId : core.id = next)
      (body : CheckedFunctionBody context surface core)
      (tail : FunctionBodiesLower context (next + 1) surfaces cores) :
      FunctionBodiesLower context next (surface :: surfaces) (core :: cores)

structure SynthesizedFunctions (context : Context) (next : FunctionId)
    (surfaces : List Surface.Function) where
  core : List Core.Function
  lowered : FunctionBodiesLower context next surfaces core

private def synthesizeFunctions (context : Context) :
    (next : FunctionId) → (surfaces : List Surface.Function) →
      Option (SynthesizedFunctions context next surfaces)
  | _, [] => some ⟨[], .nil⟩
  | next, head :: tail => do
      let synthesized ← CoreSynthesis.function context head next
      let rest ← synthesizeFunctions context (next + 1) tail
      pure ⟨synthesized.core :: rest.core,
        .cons synthesized.sameId synthesized.evidence rest.lowered⟩

private def selectExternalBehavior? (abi : Option String) (name : Surface.Name)
    (parameters : List Core.Ty) (returnType : Core.Ty) :
    Option Core.ExternalBehavior := do
  let binding ← RuntimeBindings.canonicalExternalBindings.find? fun binding =>
    binding.abi == abi && binding.name == name &&
      binding.parameterTypes == parameters && binding.returnType == returnType
  pure binding.behavior

inductive ExternFunctionsLower (context : Context) :
    FunctionId → List Surface.ExternFunction → List Core.Function → Prop where
  | nil : ExternFunctionsLower context next [] []
  | cons
      (parameters : List (VarId × Core.Ty))
      (returned : GroundedReturn context surface.name surface.returnType)
      (returnType : Core.Ty)
      (behavior : Core.ExternalBehavior)
      (parametersBuilt : parameterSkeletons context 0 surface.parameters =
        some parameters)
      (returnGrounded : groundReturn? context surface.name surface.returnType =
        some returned)
      (returnMapped : returned.type.toCore context.monomorphization =
        some returnType)
      (behaviorSelected : selectExternalBehavior? surface.abi surface.name
        (parameters.map Prod.snd) returnType = some behavior)
      (definition : core = {
        id := next
        parameters
        returnType
        body := none
        external := some behavior
      })
      (tail : ExternFunctionsLower context (next + 1) surfaces cores) :
      ExternFunctionsLower context next (surface :: surfaces) (core :: cores)

structure SynthesizedExternFunctions (context : Context) (next : FunctionId)
    (surfaces : List Surface.ExternFunction) where
  core : List Core.Function
  lowered : ExternFunctionsLower context next surfaces core

private def synthesizeExternFunctions (context : Context) :
    (next : FunctionId) → (surfaces : List Surface.ExternFunction) →
      Option (SynthesizedExternFunctions context next surfaces)
  | _, [] => some ⟨[], .nil⟩
  | next, head :: tail => do
      match parametersBuilt : parameterSkeletons context 0 head.parameters with
      | none => none
      | some parameters =>
        match returnGrounded : groundReturn? context head.name head.returnType with
        | none => none
        | some returned =>
          match returnMapped : returned.type.toCore context.monomorphization with
          | none => none
          | some returnType =>
            match behaviorSelected : selectExternalBehavior? head.abi head.name
                (parameters.map Prod.snd) returnType with
            | none => none
            | some behavior => do
              let rest ← synthesizeExternFunctions context (next + 1) tail
              let core : Core.Function := {
                id := next
                parameters
                returnType
                body := none
                external := some behavior
              }
              pure ⟨core :: rest.core, .cons parameters returned returnType
                behavior parametersBuilt returnGrounded returnMapped behaviorSelected
                rfl rest.lowered⟩

inductive PackFunctionsLower (context : Context) :
    List Allocation → List Core.Function → Prop where
  | nil : PackFunctionsLower context [] []
  | cons
      (internal : FunctionBodiesLower
        (context.forModule allocation.unit.moduleId)
        allocation.functionIdStart
        (collectFunctions allocation.unit.surface.items) internalCore)
      (externs : ExternFunctionsLower
        (context.forModule allocation.unit.moduleId)
        allocation.externIdStart
        (collectExternFunctions allocation.unit.surface.items) externCore)
      (tail : PackFunctionsLower context allocations restCore) :
      PackFunctionsLower context (allocation :: allocations)
        (internalCore ++ externCore ++ restCore)

structure SynthesizedPackFunctions (context : Context)
    (allocations : List Allocation) where
  core : List Core.Function
  lowered : PackFunctionsLower context allocations core

private def synthesizePackFunctions (context : Context) :
    (allocations : List Allocation) →
      Option (SynthesizedPackFunctions context allocations)
  | [] => some ⟨[], .nil⟩
  | allocation :: tail => do
      let current ← synthesizeFunctions
        (context.forModule allocation.unit.moduleId)
        allocation.functionIdStart
        (collectFunctions allocation.unit.surface.items)
      let externs ← synthesizeExternFunctions
        (context.forModule allocation.unit.moduleId)
        allocation.externIdStart
        (collectExternFunctions allocation.unit.surface.items)
      let rest ← synthesizePackFunctions context tail
      pure ⟨current.core ++ externs.core ++ rest.core,
        .cons current.lowered externs.lowered rest.lowered⟩

private def synthesizeFunctionsReport (context : Context) :
    (next : FunctionId) → (surfaces : List Surface.Function) →
      Except String (SynthesizedFunctions context next surfaces)
  | _, [] => .ok ⟨[], .nil⟩
  | next, head :: tail =>
      match CoreSynthesis.function context head next with
      | none => .error (head.name ++ ":" ++
          CoreSynthesis.diagnoseFunction context head)
      | some synthesized =>
          match synthesizeFunctionsReport context (next + 1) tail with
          | .error reason => .error reason
          | .ok rest => .ok ⟨synthesized.core :: rest.core,
              .cons synthesized.sameId synthesized.evidence rest.lowered⟩

private def synthesizePackFunctionsReport (context : Context) :
    (allocations : List Allocation) →
      Except String (SynthesizedPackFunctions context allocations)
  | [] => .ok ⟨[], .nil⟩
  | allocation :: tail =>
      let moduleName := String.intercalate "::" allocation.unit.modulePath
      match synthesizeFunctionsReport
          (context.forModule allocation.unit.moduleId)
          allocation.functionIdStart
          (collectFunctions allocation.unit.surface.items) with
      | .error functionName => .error (moduleName ++ "::" ++ functionName)
      | .ok current =>
          match synthesizeExternFunctions
              (context.forModule allocation.unit.moduleId)
              allocation.externIdStart
              (collectExternFunctions allocation.unit.surface.items) with
          | none => .error (moduleName ++ "::<extern>")
          | some externs =>
              match synthesizePackFunctionsReport context tail with
              | .error reason => .error reason
              | .ok rest => .ok
                  ⟨current.core ++ externs.core ++ rest.core,
                    .cons current.lowered externs.lowered rest.lowered⟩

structure CheckedProgram (artifacts : List Artifact) where
  surfaceData : ArtifactPackChecker.CheckedUnitSurfaces artifacts
  prepared : Prepared
  core : Core.Program
  target : core.target = .x86_64
  functionsLowered : PackFunctionsLower prepared.context prepared.allocations
    core.functions
  constantsLiteral : ∀ constant, constant ∈ core.constants →
    Typing.Value.isLiteral constant.value = true
  noOpaqueExternals : NoOpaqueExternals core.functions
  typed : Typing.ProgramWellTyped core

inductive FunctionNamedAt (name : Surface.Name) :
    FunctionId → List Surface.Function → FunctionId → Prop where
  | head {next : FunctionId} {surfaceFunction : Surface.Function}
      {tail : List Surface.Function}
      (sameName : surfaceFunction.name = name) :
      FunctionNamedAt name next (surfaceFunction :: tail) next
  | tail {next id : FunctionId} {surfaceFunction : Surface.Function}
      {tail : List Surface.Function}
      (found : FunctionNamedAt name (next + 1) tail id) :
      FunctionNamedAt name next (surfaceFunction :: tail) id

structure LocatedFunction (name : Surface.Name) (next : FunctionId)
    (functions : List Surface.Function) where
  id : FunctionId
  found : FunctionNamedAt name next functions id

private def locateFunction? (name : Surface.Name) :
    (next : FunctionId) → (functions : List Surface.Function) →
      Option (LocatedFunction name next functions)
  | _, [] => none
  | next, function :: tail =>
      if sameName : function.name = name then
        some ⟨next, .head sameName⟩
      else do
        let found ← locateFunction? name (next + 1) tail
        pure ⟨found.id, .tail found.found⟩

inductive SourceFunctionAt (modulePath : Names.ModulePath)
    (name : Surface.Name) : List Allocation → FunctionId → Prop where
  | head {allocation : Allocation} {tail : List Allocation}
      {id : FunctionId}
      (samePath : allocation.unit.modulePath = modulePath)
      (found : FunctionNamedAt name allocation.functionIdStart
        (collectFunctions allocation.unit.surface.items) id) :
      SourceFunctionAt modulePath name (allocation :: tail) id
  | tail {allocation : Allocation} {tail : List Allocation}
      {id : FunctionId}
      (found : SourceFunctionAt modulePath name tail id) :
      SourceFunctionAt modulePath name (allocation :: tail) id

structure LocatedSourceFunction (modulePath : Names.ModulePath)
    (name : Surface.Name) (allocations : List Allocation) where
  id : FunctionId
  found : SourceFunctionAt modulePath name allocations id

private def locateSourceFunction? (modulePath : Names.ModulePath)
    (name : Surface.Name) :
    (allocations : List Allocation) →
      Option (LocatedSourceFunction modulePath name allocations)
  | [] => none
  | allocation :: tail =>
      if samePath : allocation.unit.modulePath = modulePath then
        match locateFunction? name allocation.functionIdStart
            (collectFunctions allocation.unit.surface.items) with
        | some found => some ⟨found.id, .head samePath found.found⟩
        | none => do
            let found ← locateSourceFunction? modulePath name tail
            pure ⟨found.id, .tail found.found⟩
      else do
        let found ← locateSourceFunction? modulePath name tail
        pure ⟨found.id, .tail found.found⟩

/-- Source-linked lookup for ordinary functions with parameters, including
the extractor's I/O and serialization helpers. Executable-entrypoint policy
is applied separately by `checkEntrypoint?`. -/
structure CheckedSourceFunction {artifacts : List Artifact}
    (checked : CheckedProgram artifacts) (modulePath : Names.ModulePath)
    (name : Surface.Name) where
  source : LocatedSourceFunction modulePath name checked.prepared.allocations
  function : Core.Function
  found : checked.core.function? source.id = some function
  typed : Typing.FunctionWellTyped checked.core function

def checkSourceFunction? {artifacts : List Artifact}
    (checked : CheckedProgram artifacts) (modulePath : Names.ModulePath)
    (name : Surface.Name) : Option (CheckedSourceFunction checked modulePath name) := do
  let source ← locateSourceFunction? modulePath name checked.prepared.allocations
  match found : checked.core.function? source.id with
  | none => none
  | some function =>
      have member : function ∈ checked.core.functions := List.mem_of_find?_eq_some found
      pure ⟨source, function, found, checked.typed.2 function member⟩

private def entrypointReturnType? :
    (type : Core.Ty) → Option (Evidence (Execution.EntrypointReturnType type))
  | .unit => some ⟨.unit⟩
  | .scalar .bool => some ⟨.boolean⟩
  | .scalar (.signed _) => some ⟨.signed⟩
  | .scalar (.unsigned _) => some ⟨.unsigned⟩
  | .scalar .char => some ⟨.character⟩
  | _ => none

structure CheckedEntrypoint {artifacts : List Artifact}
    (checked : CheckedProgram artifacts) (modulePath : Names.ModulePath)
    (name : Surface.Name) where
  source : LocatedSourceFunction modulePath name checked.prepared.allocations
  function : Core.Function
  found : checked.core.function? source.id = some function
  noParameters : function.parameters = []
  returnAllowed : Execution.EntrypointReturnType function.returnType
  executable : Execution.Executable := {
    program := checked.core
    entrypoint := source.id
  }
  executableDefinition : executable = {
    program := checked.core
    entrypoint := source.id
  } := by rfl
  wellFormed : Execution.ExecutableWellFormed executable

def checkEntrypoint? {artifacts : List Artifact}
    (checked : CheckedProgram artifacts) (modulePath : Names.ModulePath)
    (name : Surface.Name) : Option (CheckedEntrypoint checked modulePath name) := do
  let source ← locateSourceFunction? modulePath name checked.prepared.allocations
  match functionFound : checked.core.function? source.id with
  | none => none
  | some function =>
      if noParameters : function.parameters = [] then
        match entrypointReturnType? function.returnType with
        | none => none
        | some returnAllowed =>
            let executable : Execution.Executable := {
              program := checked.core
              entrypoint := source.id
            }
            have functionMember : function ∈ checked.core.functions := by
              apply List.mem_of_find?_eq_some
              simpa [Core.Program.function?] using functionFound
            have functionTyped := checked.typed.2 function functionMember
            have wellFormed : Execution.ExecutableWellFormed executable := by
              exact ⟨function, functionFound, noParameters,
                returnAllowed.proof, functionTyped⟩
            some ⟨source, function, functionFound, noParameters,
              returnAllowed.proof, executable, rfl, wellFormed⟩
      else none

def synthesize? {artifacts : List Artifact}
    (surfaceData : ArtifactPackChecker.CheckedUnitSurfaces artifacts) :
    Option (CheckedProgram artifacts) := do
  let prepared ← prepare? surfaceData
  let constants ← synthesizePackConstants prepared.context prepared.allocations
  let constantsLiteral ← constantsLiteral? constants
  let functions ← synthesizePackFunctions prepared.context prepared.allocations
  let core : Core.Program := {
    target := .x86_64
    structures := prepared.structures
    constants
    functions := functions.core
  }
  let noOpaque ← noOpaqueExternals? core.functions
  let typed ← CoreTyping.checkProgram core
  pure ⟨surfaceData, prepared, core, rfl, functions.lowered,
    constantsLiteral.proof, noOpaque.proof, typed.proof⟩

structure CheckedCompactCoreSourcePack
    (encoded : String) (expectedSources : List SourceFile) where
  surface : CheckedCompactSurfaceSourcePack encoded expectedSources
  program : CheckedProgram surface.pack.units

inductive CoreSourcePackCheck
    (encoded : String) (expectedSources : List SourceFile) where
  | success (checked : CheckedCompactCoreSourcePack encoded expectedSources)
  | failure (stage : String)

def checkCompactCoreSourcePack
    (encoded : String) (expectedSources : List SourceFile) :
    CoreSourcePackCheck encoded expectedSources :=
  match checkCompactSurfaceArtifactPackSources? encoded expectedSources with
  | none => .failure "source-or-surface"
  | some surface =>
      match prepare? surface.surfaceData with
      | none => .failure "declaration-context"
      | some prepared =>
          match synthesizePackConstants prepared.context prepared.allocations with
          | none => .failure "constants"
          | some constants =>
              match constantsLiteral? constants with
              | none => .failure "constant-closure"
              | some constantsLiteral =>
                match synthesizePackFunctionsReport prepared.context
                    prepared.allocations with
                | .error reason => .failure ("function-lowering:" ++ reason)
                | .ok functions =>
                    let core : Core.Program := {
                      target := .x86_64
                      structures := prepared.structures
                      constants
                      functions := functions.core
                    }
                    match noOpaqueExternals? core.functions with
                    | none => .failure "opaque-external"
                    | some noOpaque =>
                      match CoreTyping.checkProgram core with
                      | none => .failure "core-typing"
                      | some typed =>
                        let program : CheckedProgram surface.pack.units :=
                          ⟨surface.surfaceData, prepared, core, rfl,
                            functions.lowered, constantsLiteral.proof,
                            noOpaque.proof, typed.proof⟩
                        .success ⟨surface, program⟩

def checkCompactCoreSourcePack?
    (encoded : String) (expectedSources : List SourceFile) :
    Option (CheckedCompactCoreSourcePack encoded expectedSources) :=
  match checkCompactCoreSourcePack encoded expectedSources with
  | .success checked => some checked
  | .failure _ => none

end Lanius.Extraction.CoreSynthesis.Program
