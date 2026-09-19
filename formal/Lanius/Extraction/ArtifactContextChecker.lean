import Lanius.Extraction.CoreDecode
import Lanius.Extraction.SurfaceElaborationChecker
import Lanius.Extraction.SurfaceReconstruct

namespace Lanius.Extraction.ArtifactContextChecker

open Lanius
open Lanius.Core
open Lanius.SurfaceElaboration
open Lanius.Extraction.SurfaceElaborationChecker

/-! ## Checked semantic-context reconstruction

The serialized semantic rows are suggestions, not authority.  This module
deterministically constructs the nongeneric single-module declaration context
from reconstructed Surface declarations and decoded Core artifacts, checks
their signatures and aggregate layouts, and then invokes the proof-producing
body checker.  Declaration IDs are dense checker-local identities; they are
not trusted exporter row numbers.
-/

def mapIndexedContext (build : Nat → α → β) : Nat → List α → List β
  | _, [] => []
  | index, head :: tail =>
      build index head :: mapIndexedContext build (index + 1) tail

def mapIndexedPair? (build : Nat → α → β → Option γ) :
    Nat → List α → List β → Option (List γ)
  | _, [], [] => some []
  | index, head :: tail, head' :: tail' => do
      let value ← build index head head'
      let rest ← mapIndexedPair? build (index + 1) tail tail'
      pure (value :: rest)
  | _, _, _ => none

def buildSymbol (moduleId : ModuleId) (lookupNamespace : Names.LookupNamespace)
    (name : Surface.Name) (isPublic : Bool) (declaration : Nat) : Names.Symbol := {
  moduleId
  lookupNamespace
  name
  visibility := if isPublic then .exported else .modulePrivate
  declaration
}

def collectStructures : List Surface.Item → List Surface.StructDecl :=
  List.filterMap fun
    | .structure declaration => some declaration
    | _ => none

def collectFunctions : List Surface.Item → List Surface.Function :=
  List.filterMap fun
    | .function declaration => some declaration
    | _ => none

structure SourceTypeAlias where
  name : Surface.Name
  isPublic : Bool
  target : Surface.TypeExpr

def collectTypeAliases : List Surface.Item → List SourceTypeAlias :=
  List.filterMap fun
    | .typeAlias name isPublic _ _ target => some ⟨name, isPublic, target⟩
    | _ => none

structure SourceConstant where
  name : Surface.Name
  isPublic : Bool
  type : Surface.TypeExpr
  value : Surface.Expr

def collectConstants : List Surface.Item → List SourceConstant :=
  List.filterMap fun
    | .constant name isPublic type value => some ⟨name, isPublic, type, value⟩
    | _ => none

def supportedSingleModuleItem : Surface.Item → Bool
  | .module _ => true
  | .structure declaration =>
      listEmptyBool declaration.genericParameters &&
        listEmptyBool declaration.wherePredicates
  | .function declaration =>
      listEmptyBool declaration.genericParameters &&
        listEmptyBool declaration.wherePredicates
  | .typeAlias _ _ parameters predicates _ =>
      listEmptyBool parameters && listEmptyBool predicates
  | .constant _ _ _ _ => true
  | _ => false

def supportedSingleModuleItems (items : List Surface.Item) : Bool :=
  items.all supportedSingleModuleItem

structure NominalHeaders where
  symbols : List Names.Symbol
  schemes : List Static.NominalScheme
  instances : List Static.NominalInstance

structure NominalHeader where
  symbol : Names.Symbol
  scheme : Static.NominalScheme
  nominalInstance : Static.NominalInstance

def buildNominalHeaders :
    ModuleId → Nat → TypeId →
      List Surface.StructDecl → List Core.StructDecl →
      Option NominalHeaders
  | moduleId, declaration, sourceType, surface, core => do
      let headers ← mapIndexedPair? (fun offset surface core =>
        pure ({
          symbol := buildSymbol moduleId .type surface.name surface.isPublic
            (declaration + offset)
          scheme := {
            declaration := declaration + offset
            type := sourceType + offset
            kind := .structure
            isPublic := surface.isPublic
          }
          nominalInstance := {
            declaration := declaration + offset
            sourceType := sourceType + offset
            kind := .structure
            coreType := core.id
          }
        } : NominalHeader)) 0 surface core
      pure {
        symbols := headers.map NominalHeader.symbol
        schemes := headers.map NominalHeader.scheme
        instances := headers.map NominalHeader.nominalInstance
      }

structure TypeAliasHeaders where
  symbols : List Names.Symbol
  entries : List TypeAliasEntry

def buildTypeAliasHeaders : ModuleId → Nat → List SourceTypeAlias → TypeAliasHeaders
  | moduleId, declaration, sources =>
      let headers := mapIndexedContext (fun declaration source =>
        ((buildSymbol moduleId .type source.name source.isPublic declaration), ({
          declaration
          moduleId
          target := source.target
        } : TypeAliasEntry))) declaration sources
      ⟨headers.map Prod.fst, headers.map Prod.snd⟩

def resolveNominalFrom (instances : List Static.NominalInstance)
    (sourceType : TypeId) (typeArguments : List Static.GroundTy)
    (constArguments : List Nat) : Option Core.Ty :=
  match typeArguments, constArguments with
  | [], [] =>
      (instances.find? fun row => row.sourceType == sourceType).map
        Static.NominalInstance.coreTy
  | _, _ => none

def monomorphizationFrom (instances : List Static.NominalInstance) :
    Static.Monomorphization := {
  resolveNominal := resolveNominalFrom instances
}

structure StructFields where
  entries : List FieldEntry
  schemes : List StructFieldScheme

def buildStructFields (context : Context) (receiver : Static.GroundTy) :
    FieldId → List Surface.StructField → List Core.Ty → Option StructFields
  | fieldId, surface, core => do
      let fields ← mapIndexedPair? (fun fieldId surface coreType => do
        let grounded ← groundType? context surface.type
        let _mapped ← checkCoreTypeMapping? context grounded.type coreType
        pure (({
          receiver
          name := surface.name
          field := fieldId
          type := grounded.type
        } : FieldEntry), ({
          name := surface.name
          field := fieldId
          type := grounded.type.toTy
        } : StructFieldScheme))) fieldId surface core
      pure ⟨fields.map Prod.fst, fields.map Prod.snd⟩

structure StructDetails where
  fields : List FieldEntry
  constructors : List StructConstructorScheme

def buildStructDetails (context : Context) :
    Nat → TypeId → List Surface.StructDecl → List Core.StructDecl →
      Option StructDetails
  | _, _, [], [] => some ⟨[], []⟩
  | declaration, sourceType, surface :: surfaceTail, core :: coreTail => do
      let receiver : Static.GroundTy := .nominal sourceType [] []
      let fields ← buildStructFields context receiver 0 surface.fields core.fields
      let tail ← buildStructDetails context (declaration + 1) (sourceType + 1)
        surfaceTail coreTail
      pure {
        fields := fields.entries ++ tail.fields
        constructors := {
          declaration
          sourceType
          fields := fields.schemes
        } :: tail.constructors
      }
  | _, _, _, _ => none

def buildValueSymbols (moduleId : ModuleId) (declaration : Nat)
    (name : α → Surface.Name) (isPublic : α → Bool) (values : List α) :
    List Names.Symbol :=
  mapIndexedContext (fun declaration value =>
    buildSymbol moduleId .value (name value) (isPublic value) declaration) declaration values

def buildFunctionSymbols : ModuleId → Nat → List Surface.Function → List Names.Symbol :=
  fun moduleId declaration =>
    buildValueSymbols moduleId declaration (·.name) (·.isPublic)

def buildConstantSymbols : ModuleId → Nat → List SourceConstant → List Names.Symbol :=
  fun moduleId declaration =>
    buildValueSymbols moduleId declaration (·.name) (·.isPublic)

def buildConstantEntries (context : Context) :
    Nat → List SourceConstant → List Core.Constant →
      Option (List ConstantEntry)
  | declaration, surface, core =>
      mapIndexedPair? (fun declaration surface core => do
        let grounded ← groundType? context surface.type
        let _mapped ← checkCoreTypeMapping? context grounded.type core.type
        pure (({
          declaration
          constant := core.id
          type := grounded.type
        } : ConstantEntry))) declaration surface core

structure CheckedConstantPair (context : Context)
    (surface : SourceConstant) (core : Core.Constant) where
  ground : Static.GroundTy
  typeGrounded : TypeGrounds context surface.type ground
  typeMapped : ground.toCore context.monomorphization = some core.type
  valueChecked : ExprChecks context surface.value ground (.value core.value)

inductive PairwiseChecked (check : α → β → Type) :
    List α → List β → Prop where
  | nil : PairwiseChecked check [] []
  | cons
      (head : check surfaceHead coreHead)
      (tail : PairwiseChecked check surfaceTail coreTail) :
      PairwiseChecked check (surfaceHead :: surfaceTail) (coreHead :: coreTail)

abbrev ConstantsChecked (context : Context) :
    List SourceConstant → List Core.Constant → Prop :=
  PairwiseChecked (fun surface core => CheckedConstantPair context surface core)

def checkConstants (context : Context) :
    (surface : List SourceConstant) → (core : List Core.Constant) →
      Option (Evidence (ConstantsChecked context surface core))
  | [], [] => some ⟨.nil⟩
  | surfaceHead :: surfaceTail, coreHead :: coreTail => do
      let grounded ← groundType? context surfaceHead.type
      let mapped ← checkCoreTypeMapping? context grounded.type coreHead.type
      let value ← checkExpr context surfaceHead.value grounded.type
        (.value coreHead.value)
      let tail ← checkConstants context surfaceTail coreTail
      pure ⟨.cons ⟨grounded.type, grounded.grounded, mapped.proof,
        value.proof⟩ tail.proof⟩
  | _, _ => none

structure FunctionParameters where
  ground : List Static.GroundTy
  static : List Static.Ty

def buildFunctionParameters (context : Context) :
    List Surface.Parameter → List (VarId × Core.Ty) →
      Option FunctionParameters
  | surface, core => do
      let parameters ← mapIndexedPair? (fun _ surface core =>
        match surface, core with
        | .named _ surfaceType, (_, coreType) => do
            let grounded ← groundType? context surfaceType
            let _mapped ← checkCoreTypeMapping? context grounded.type coreType
            pure (grounded.type, grounded.type.toTy)
        | _, _ => none) 0 surface core
      pure ⟨parameters.map Prod.fst, parameters.map Prod.snd⟩

structure FunctionHeaders where
  schemes : List Static.FunctionScheme
  instances : List Static.FunctionInstance

def buildFunctionHeaders (context : Context) :
    Nat → List Surface.Function → List Core.Function →
      Option FunctionHeaders
  | declaration, surface, core => do
      let headers ← mapIndexedPair? (fun declaration surface core => do
        if noExternal : core.external = none then
          let parameters ← buildFunctionParameters context
            surface.parameters core.parameters
          let returned ← groundReturn? context surface.name surface.returnType
          let _returnMapped ← checkCoreTypeMapping? context returned.type core.returnType
          pure (({
            declaration
            parameterTypes := parameters.static
            returnType := returned.type.toTy
          } : Static.FunctionScheme), ({
            declaration
            function := core.id
            parameterTypes := parameters.ground
            returnType := returned.type
          } : Static.FunctionInstance))
        else none) declaration surface core
      pure ⟨headers.map Prod.fst, headers.map Prod.snd⟩

def buildContext? (surface : Surface.File) (core : Core.Program) : Option Context := do
  if supported : supportedSingleModuleItems surface.items = true then
    if noEnums : core.enumerations = [] then
        let structures := collectStructures surface.items
        let aliases := collectTypeAliases surface.items
        let constants := collectConstants surface.items
        let functions := collectFunctions surface.items
        let aliasStart := structures.length
        let constantStart := aliasStart + aliases.length
        let functionStart := constantStart + constants.length
        let nominal ← buildNominalHeaders 0 0 0 structures core.structures
        let aliasHeaders := buildTypeAliasHeaders 0 aliasStart aliases
        let constantSymbols := buildConstantSymbols 0 constantStart constants
        let functionSymbols := buildFunctionSymbols 0 functionStart functions
        let typeContext : Context := {
          target := core.target
          names := { symbols := nominal.symbols ++ aliasHeaders.symbols ++
            constantSymbols ++ functionSymbols }
          currentModule := 0
          monomorphization := monomorphizationFrom nominal.instances
          nominalSchemes := nominal.schemes
          nominalInstances := nominal.instances
          typeAliases := aliasHeaders.entries
        }
        let details ← buildStructDetails typeContext 0 0 structures core.structures
        let declarationContext : Context := {
          typeContext with
          fields := details.fields
          structConstructors := details.constructors
        }
        let constantEntries ← buildConstantEntries declarationContext constantStart
          constants core.constants
        let constantContext : Context := {
          declarationContext with constants := constantEntries
        }
        let functionHeaders ← buildFunctionHeaders constantContext functionStart
          functions core.functions
        pure {
          constantContext with
          functions := functionHeaders.schemes
          functionInstances := functionHeaders.instances
        }
    else none
  else none

abbrev FunctionsChecked (context : Context) :
    List Surface.Function → List Core.Function → Prop :=
  PairwiseChecked (fun surface core => CheckedFunctionBody context surface core)

def checkFunctions (context : Context) :
    (surface : List Surface.Function) → (core : List Core.Function) →
      Option (Evidence (FunctionsChecked context surface core))
  | [], [] => some ⟨.nil⟩
  | surfaceHead :: surfaceTail, coreHead :: coreTail => do
      let head ← checkFunctionBody context surfaceHead coreHead
      let tail ← checkFunctions context surfaceTail coreTail
      pure ⟨.cons head tail.proof⟩
  | _, _ => none

structure CheckedSingleFileProgram (surface : Surface.File) (core : Core.Program) where
  context : Context
  constants : ConstantsChecked context (collectConstants surface.items) core.constants
  functions : FunctionsChecked context (collectFunctions surface.items) core.functions

def checkSingleFileProgram? (surface : Surface.File) (core : Core.Program) :
    Option (CheckedSingleFileProgram surface core) := do
  let context ← buildContext? surface core
  let constants ← checkConstants context (collectConstants surface.items) core.constants
  let functions ← checkFunctions context (collectFunctions surface.items) core.functions
  pure ⟨context, constants.proof, functions.proof⟩

structure CheckedArtifactProgram (artifact : Artifact) where
  surface : Surface.File
  surfaceDecoded : decodeReconstructedSurface artifact = some surface
  core : Core.Program
  coreDecoded : artifact.core_program.map CoreDecode.program = some core
  checked : CheckedSingleFileProgram surface core

def checkArtifactProgram? (artifact : Artifact) :
    Option (CheckedArtifactProgram artifact) := do
  match surfaceDecoded : decodeReconstructedSurface artifact with
  | none => none
  | some surface =>
      match coreDecoded : artifact.core_program.map CoreDecode.program with
      | none => none
      | some core => do
          let checked ← checkSingleFileProgram? surface core
          pure ⟨surface, surfaceDecoded, core, coreDecoded, checked⟩

end Lanius.Extraction.ArtifactContextChecker
