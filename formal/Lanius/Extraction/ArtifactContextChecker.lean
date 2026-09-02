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

def collectStructures : List Surface.Item → List Surface.StructDecl
  | [] => []
  | .structure declaration :: tail => declaration :: collectStructures tail
  | _ :: tail => collectStructures tail

def collectFunctions : List Surface.Item → List Surface.Function
  | [] => []
  | .function declaration :: tail => declaration :: collectFunctions tail
  | _ :: tail => collectFunctions tail

structure SourceTypeAlias where
  name : Surface.Name
  isPublic : Bool
  target : Surface.TypeExpr

def collectTypeAliases : List Surface.Item → List SourceTypeAlias
  | [] => []
  | .typeAlias name isPublic _ _ target :: tail =>
      ⟨name, isPublic, target⟩ :: collectTypeAliases tail
  | _ :: tail => collectTypeAliases tail

structure SourceConstant where
  name : Surface.Name
  isPublic : Bool
  type : Surface.TypeExpr
  value : Surface.Expr

def collectConstants : List Surface.Item → List SourceConstant
  | [] => []
  | .constant name isPublic type value :: tail =>
      ⟨name, isPublic, type, value⟩ :: collectConstants tail
  | _ :: tail => collectConstants tail

def supportedSingleModuleItems : List Surface.Item → Bool
  | [] => true
  | .module _ :: tail => supportedSingleModuleItems tail
  | .structure declaration :: tail =>
      listEmptyBool declaration.genericParameters &&
        listEmptyBool declaration.wherePredicates &&
        supportedSingleModuleItems tail
  | .function declaration :: tail =>
      listEmptyBool declaration.genericParameters &&
        listEmptyBool declaration.wherePredicates &&
        supportedSingleModuleItems tail
  | .typeAlias _ _ parameters predicates _ :: tail =>
      listEmptyBool parameters && listEmptyBool predicates &&
        supportedSingleModuleItems tail
  | .constant _ _ _ _ :: tail => supportedSingleModuleItems tail
  | _ :: _ => false

structure NominalHeaders where
  symbols : List Names.Symbol
  schemes : List Static.NominalScheme
  instances : List Static.NominalInstance

def buildNominalHeaders :
    ModuleId → Nat → TypeId →
      List Surface.StructDecl → List Core.StructDecl →
      Option NominalHeaders
  | _, _, _, [], [] => some ⟨[], [], []⟩
  | moduleId, declaration, sourceType,
      surface :: surfaceTail, core :: coreTail => do
      let tail ← buildNominalHeaders moduleId (declaration + 1)
        (sourceType + 1) surfaceTail coreTail
      pure {
        symbols := {
          moduleId
          lookupNamespace := .type
          name := surface.name
          visibility := if surface.isPublic then .exported else .modulePrivate
          declaration
        } :: tail.symbols
        schemes := {
          declaration
          type := sourceType
          kind := .structure
          isPublic := surface.isPublic
        } :: tail.schemes
        instances := {
          declaration
          sourceType
          kind := .structure
          coreType := core.id
        } :: tail.instances
      }
  | _, _, _, _, _ => none

structure TypeAliasHeaders where
  symbols : List Names.Symbol
  entries : List TypeAliasEntry

def buildTypeAliasHeaders : ModuleId → Nat → List SourceTypeAlias → TypeAliasHeaders
  | _, _, [] => ⟨[], []⟩
  | moduleId, declaration, source :: tail =>
      let rest := buildTypeAliasHeaders moduleId (declaration + 1) tail
      {
        symbols := {
          moduleId
          lookupNamespace := .type
          name := source.name
          visibility := if source.isPublic then .exported else .modulePrivate
          declaration
        } :: rest.symbols
        entries := {
          declaration
          moduleId
          target := source.target
        } :: rest.entries
      }

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
  | _, [], [] => some ⟨[], []⟩
  | fieldId, surface :: surfaceTail, coreType :: coreTail => do
      let grounded ← groundType? context surface.type
      let _mapped ← checkCoreTypeMapping? context grounded.type coreType
      let tail ← buildStructFields context receiver (fieldId + 1)
        surfaceTail coreTail
      pure {
        entries := {
          receiver
          name := surface.name
          field := fieldId
          type := grounded.type
        } :: tail.entries
        schemes := {
          name := surface.name
          field := fieldId
          type := grounded.type.toTy
        } :: tail.schemes
      }
  | _, _, _ => none

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

def buildFunctionSymbols : ModuleId → Nat → List Surface.Function → List Names.Symbol
  | _, _, [] => []
  | moduleId, declaration, function :: tail => {
      moduleId
      lookupNamespace := .value
      name := function.name
      visibility := if function.isPublic then .exported else .modulePrivate
      declaration
    } :: buildFunctionSymbols moduleId (declaration + 1) tail

def buildConstantSymbols : ModuleId → Nat → List SourceConstant → List Names.Symbol
  | _, _, [] => []
  | moduleId, declaration, constant :: tail => {
      moduleId
      lookupNamespace := .value
      name := constant.name
      visibility := if constant.isPublic then .exported else .modulePrivate
      declaration
    } :: buildConstantSymbols moduleId (declaration + 1) tail

def buildConstantEntries (context : Context) :
    Nat → List SourceConstant → List Core.Constant →
      Option (List ConstantEntry)
  | _, [], [] => some []
  | declaration, surface :: surfaceTail, core :: coreTail => do
      let grounded ← groundType? context surface.type
      let _mapped ← checkCoreTypeMapping? context grounded.type core.type
      let tail ← buildConstantEntries context (declaration + 1)
        surfaceTail coreTail
      pure (({
        declaration
        constant := core.id
        type := grounded.type
      } : ConstantEntry) :: tail)
  | _, _, _ => none

structure CheckedConstantPair (context : Context)
    (surface : SourceConstant) (core : Core.Constant) where
  ground : Static.GroundTy
  typeGrounded : TypeGrounds context surface.type ground
  typeMapped : ground.toCore context.monomorphization = some core.type
  valueChecked : ExprChecks context surface.value ground (.value core.value)

inductive ConstantsChecked (context : Context) :
    List SourceConstant → List Core.Constant → Prop where
  | nil : ConstantsChecked context [] []
  | cons
      (head : CheckedConstantPair context surfaceHead coreHead)
      (tail : ConstantsChecked context surfaceTail coreTail) :
      ConstantsChecked context (surfaceHead :: surfaceTail) (coreHead :: coreTail)

theorem ConstantsChecked.append
    (left : ConstantsChecked context surfaceLeft coreLeft)
    (right : ConstantsChecked context surfaceRight coreRight) :
    ConstantsChecked context (surfaceLeft ++ surfaceRight)
      (coreLeft ++ coreRight) := by
  induction left with
  | nil => exact right
  | cons head _ induction => exact .cons head induction

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
  | [], [] => some ⟨[], []⟩
  | .named _ surfaceType :: surfaceTail, (_, coreType) :: coreTail => do
      let grounded ← groundType? context surfaceType
      let _mapped ← checkCoreTypeMapping? context grounded.type coreType
      let tail ← buildFunctionParameters context surfaceTail coreTail
      pure ⟨grounded.type :: tail.ground, grounded.type.toTy :: tail.static⟩
  | _, _ => none

structure FunctionHeaders where
  schemes : List Static.FunctionScheme
  instances : List Static.FunctionInstance

def buildFunctionHeaders (context : Context) :
    Nat → List Surface.Function → List Core.Function →
      Option FunctionHeaders
  | _, [], [] => some ⟨[], []⟩
  | declaration, surface :: surfaceTail, core :: coreTail => do
      if noExternal : core.external = none then
        let parameters ← buildFunctionParameters context
          surface.parameters core.parameters
        let returned ← groundReturn? context surface.name surface.returnType
        let _returnMapped ← checkCoreTypeMapping? context returned.type core.returnType
        let tail ← buildFunctionHeaders context (declaration + 1)
          surfaceTail coreTail
        pure {
          schemes := {
            declaration
            parameterTypes := parameters.static
            returnType := returned.type.toTy
          } :: tail.schemes
          instances := {
            declaration
            function := core.id
            parameterTypes := parameters.ground
            returnType := returned.type
          } :: tail.instances
        }
      else none
  | _, _, _ => none

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

inductive FunctionsChecked (context : Context) :
    List Surface.Function → List Core.Function → Prop where
  | nil : FunctionsChecked context [] []
  | cons
      (head : CheckedFunctionBody context surfaceHead coreHead)
      (tail : FunctionsChecked context surfaceTail coreTail) :
      FunctionsChecked context (surfaceHead :: surfaceTail) (coreHead :: coreTail)

theorem FunctionsChecked.append
    (left : FunctionsChecked context surfaceLeft coreLeft)
    (right : FunctionsChecked context surfaceRight coreRight) :
    FunctionsChecked context (surfaceLeft ++ surfaceRight)
      (coreLeft ++ coreRight) := by
  induction left with
  | nil => exact right
  | cons head _ induction => exact .cons head induction

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
