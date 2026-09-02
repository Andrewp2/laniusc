import Lanius.Extraction.CoreTypingChecker

namespace Lanius.Extraction.ArtifactPackChecker

open Lanius
open Lanius.Core
open Lanius.Extraction

abbrev Evidence := CoreTyping.Evidence

/-! ## Source-pack certificate assembly

Each unit is checked against its own bytes, tokens, parse tree, and reconstructed
Surface tree. Core identities, however, belong to the complete source pack. The
wire fragments are therefore concatenated before density, canonical-value, and
typing checks run. This prevents a cross-file call from being accepted merely
because its callee ID happened to denote a different file-local function.
-/

inductive UnitsSurfaceValid : List Artifact → Prop where
  | nil : UnitsSurfaceValid []
  | cons
      (head : SurfaceArtifactValid artifact)
      (tail : UnitsSurfaceValid artifacts) :
      UnitsSurfaceValid (artifact :: artifacts)

def checkUnitSurfaces :
    (artifacts : List Artifact) → Option (Evidence (UnitsSurfaceValid artifacts))
  | [] => some ⟨.nil⟩
  | head :: tail => do
      if accepted : checkSurfaceArtifact head = true then
        let checkedTail ← checkUnitSurfaces tail
        pure ⟨.cons (checkSurfaceArtifact_sound accepted) checkedTail.proof⟩
      else none

/-- Reusable data returned by the single-reconstruction surface checker for
every pack unit. -/
inductive CheckedUnitSurfaces : (artifacts : List Artifact) → Type where
  | nil : CheckedUnitSurfaces []
  | cons
      (head : CheckedSurfaceArtifact artifact)
      (tail : CheckedUnitSurfaces artifacts) :
      CheckedUnitSurfaces (artifact :: artifacts)

theorem CheckedUnitSurfaces.valid :
    {artifacts : List Artifact} → CheckedUnitSurfaces artifacts →
      UnitsSurfaceValid artifacts
  | [], .nil => .nil
  | _ :: _, .cons head tail => .cons head.valid tail.valid

def CheckedUnitSurfaces.nodeCounts :
    {artifacts : List Artifact} → CheckedUnitSurfaces artifacts → List Nat
  | [], .nil => []
  | _ :: _, .cons head tail => head.claims.nodes.length :: tail.nodeCounts

def checkUnitSurfacesCached :
    (artifacts : List Artifact) → Option (CheckedUnitSurfaces artifacts)
  | [] => some .nil
  | head :: tail => do
      let checkedHead ← checkSurfaceArtifact? head
      let checkedTail ← checkUnitSurfacesCached tail
      pure (.cons checkedHead checkedTail)

def appendCorePrograms? (left right : CoreProgram) : Option CoreProgram := do
  if _sameTarget : left.target == right.target then
    pure {
      target := left.target
      structures := left.structures ++ right.structures
      enumerations := left.enumerations ++ right.enumerations
      constants := left.constants ++ right.constants
      functions := left.functions ++ right.functions
    }
  else none

def appendArtifactCore? (program : CoreProgram) (artifact : Artifact) :
    Option CoreProgram := do
  let fragment ← artifact.core_program
  appendCorePrograms? program fragment

def mergeCorePrograms? : List Artifact → Option CoreProgram
  | [] => none
  | head :: tail => do
      let first ← head.core_program
      tail.foldlM appendArtifactCore? first

structure CheckedArtifactPack (pack : ArtifactPack) where
  schema : pack.schema_version = schemaVersion
  surfaceData : CheckedUnitSurfaces pack.units
  surfaces : UnitsSurfaceValid pack.units
  wire : CoreProgram
  merged : mergeCorePrograms? pack.units = some wire
  nodeIdsDense : CoreNodeIdsDense wire
  valuesCanonical : coreProgramValuesCanonical wire = true
  program : Core.Program
  decoded : program = CoreDecode.program wire
  wellTyped : Typing.ProgramWellTyped program

def checkArtifactPack? (pack : ArtifactPack) : Option (CheckedArtifactPack pack) := do
  if schema : pack.schema_version = schemaVersion then
    let surfaceData ← checkUnitSurfacesCached pack.units
    match merged : mergeCorePrograms? pack.units with
    | none => none
    | some wire => do
        if dense : coreNodeIdsDense wire = true then
          if canonical : coreProgramValuesCanonical wire = true then
            let program := CoreDecode.program wire
            let typed ← CoreTyping.checkProgram program
            pure {
              schema
              surfaceData
              surfaces := surfaceData.valid
              wire
              merged
              nodeIdsDense := coreNodeIdsDense_sound dense
              valuesCanonical := canonical
              program
              decoded := rfl
              wellTyped := typed.proof
            }
          else none
        else none
  else none

end Lanius.Extraction.ArtifactPackChecker
