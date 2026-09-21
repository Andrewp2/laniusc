import Lanius.Compiler.ProgramLowering
import Lanius.Compiler.ImportSynthesis
import Lanius.Compiler.SourcePackCheck

namespace Lanius.Compiler.SourceCoreBoundary

open Lanius
open Lanius.Extraction

def checkedUnitSources :
    {units : List Artifact} → SyntaxCheck.CheckedUnits units → List SourceFile
  | _, .nil => []
  | _, .cons head tail => head.source :: checkedUnitSources tail

def checkedSurfaceFiles :
    {units : List Artifact} → SyntaxCheck.CheckedUnits units → List Surface.File :=
  SourcePackCheck.surfaceFiles

def reconstructedSurfaces :
  {units : List Artifact} → SyntaxCheck.CheckedUnits units → Prop
  | _, .nil => True
  | artifact :: _, .cons head tail =>
      (decodeReconstructedSurface artifact = some head.surface.surface) ∧
        reconstructedSurfaces tail

theorem checkedUnitSources_eq_units :
    ∀ {units : List Artifact} (checked : SyntaxCheck.CheckedUnits units),
      checkedUnitSources checked = units.flatMap (fun artifact => artifact.sources)
  | _, .nil => rfl
  | _, .cons head tail => by
      simp [checkedUnitSources, head.sourceFound,
        checkedUnitSources_eq_units tail]

theorem checkedUnits_reconstructed :
    ∀ {units : List Artifact} (checked : SyntaxCheck.CheckedUnits units),
      reconstructedSurfaces checked
  | _, .nil => by simp [reconstructedSurfaces]
  | _, .cons head tail =>
      ⟨head.surface.reconstructed, checkedUnits_reconstructed tail⟩

structure SourceCoreBoundary
    (encoded : String) (expectedSources : List SourceFile)
    (checked : SyntaxCheck.CheckedSourcePack encoded expectedSources) where
  lowering : ProgramLowering.ProgramLowering
  packMatches : lowering.pack = SourcePackCheck.declaredPack checked
  importCollection : ImportSynthesis.Checked lowering.pack
  importCollectionAccepted :
    ImportSynthesis.check lowering.pack = some importCollection
  importsMatch : lowering.imports = importCollection.imports

theorem SourceCoreBoundary.importsAreCovered
    {encoded : String} {expectedSources : List Extraction.SourceFile}
    {checked : SyntaxCheck.CheckedSourcePack encoded expectedSources}
    (boundary : SourceCoreBoundary encoded expectedSources checked) :
    Declarations.ImportCollectionCovers boundary.lowering.pack boundary.lowering.imports := by
  rw [boundary.importsMatch]
  exact ImportSynthesis.check_sound boundary.importCollectionAccepted

theorem SourceCoreBoundary.surfaceAlignment
    {encoded : String} {expectedSources : List SourceFile}
    {checked : SyntaxCheck.CheckedSourcePack encoded expectedSources}
    (boundary : SourceCoreBoundary encoded expectedSources checked) :
    checkedSurfaceFiles checked.units =
      boundary.lowering.pack.files.map (fun file => file.contents) := by
  rw [boundary.packMatches]
  exact (SourcePackCheck.surface_alignment checked).symm

theorem accepted_to_core
    {encoded : String} {expectedSources : List SourceFile}
    {checked : SyntaxCheck.CheckedSourcePack encoded expectedSources}
    (accepted : SyntaxCheck.checkCompactSourcePack encoded expectedSources = .ok checked)
    (boundary : SourceCoreBoundary encoded expectedSources checked) :
    decodeCompactPack? encoded = some checked.compact.pack ∧
      checked.compact.pack.schema_version = schemaVersion ∧
      checkedUnitSources checked.units = expectedSources ∧
      reconstructedSurfaces checked.units ∧
      checkedSurfaceFiles checked.units =
        boundary.lowering.pack.files.map (fun file => file.contents) ∧
      ProgramLowering.SupportedMonomorphic boundary.lowering.pack ∧
      Typing.ProgramWellTyped boundary.lowering.program := by
  have sound := SyntaxCheck.checkCompactSourcePack_sound accepted
  have sources : checkedUnitSources checked.units =
      compactPackSources checked.compact.pack := by
    simpa [compactPackSources] using checkedUnitSources_eq_units checked.units
  exact ⟨sound.1, sound.2.1, sources.trans sound.2.2.1,
    checkedUnits_reconstructed checked.units, boundary.surfaceAlignment,
    boundary.lowering.eligible, boundary.lowering.wellTyped⟩

end Lanius.Compiler.SourceCoreBoundary
