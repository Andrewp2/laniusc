import Lanius.Compiler.FrontendCheck
import Lanius.Compiler.CatalogSynthesis
import Lanius.Compiler.ImportSynthesis

namespace Lanius.Compiler.FrontendBoundary

open Lanius
open Lanius.Declarations
open Lanius.Extraction

inductive Failure where
  | frontend (failure : FrontendCheck.Failure)
  | catalog
  | importSynthesis
  | imports (failure : ImportCheck.Failure)
deriving DecidableEq, Repr

abbrev frontendPack {encoded : String}
    {expectedSources : List Lanius.Extraction.SourceFile}
    (frontend : FrontendCheck.CheckedFrontend encoded expectedSources) : SourcePack :=
  SourcePackCheck.declaredPack frontend.compact

structure Checked (encoded : String)
    (expectedSources : List Lanius.Extraction.SourceFile) where
  frontend : FrontendCheck.CheckedFrontend encoded expectedSources
  frontendAccepted : FrontendCheck.check encoded expectedSources = .ok frontend
  catalog : CatalogSynthesis.Checked (frontendPack frontend)
  catalogAccepted : CatalogSynthesis.check (frontendPack frontend) = some catalog
  catalogSynthesized : CatalogSynthesis.synthesize? (frontendPack frontend) =
    some catalog.catalog
  imports : List CollectedImport
  importsSynthesized : ImportSynthesis.synthesize? (frontendPack frontend) = some imports
  importsEvidence : ImportCheck.Checked (frontendPack frontend) imports
  importsAccepted : ImportCheck.check (frontendPack frontend) imports = .ok importsEvidence

theorem catalog_check_synthesized {pack : SourcePack}
    {checked : CatalogSynthesis.Checked pack}
    (accepted : CatalogSynthesis.check pack = some checked) :
    CatalogSynthesis.synthesize? pack = some checked.catalog := by
  unfold CatalogSynthesis.check at accepted
  cases synthesis : CatalogSynthesis.synthesize? pack with
  | none => simp [synthesis] at accepted
  | some catalog =>
      cases evidence : checkCatalogWellFormed pack catalog with
      | none => simp [synthesis, evidence] at accepted
      | some evidence =>
          simp [synthesis, evidence] at accepted
          cases accepted
          rfl

def check (encoded : String)
    (expectedSources : List Lanius.Extraction.SourceFile) :
    Except Failure (Checked encoded expectedSources) :=
  match frontendAccepted : FrontendCheck.check encoded expectedSources with
  | .error failure => .error (.frontend failure)
  | .ok frontend =>
      let pack := frontendPack frontend
      match catalogAccepted : CatalogSynthesis.check pack with
      | none => .error .catalog
      | some catalog =>
          match importsGenerated : ImportSynthesis.synthesize? pack with
          | none => .error .importSynthesis
          | some imports =>
              match importsAccepted : ImportCheck.check pack imports with
              | .error failure => .error (.imports failure)
              | .ok importsEvidence =>
                  .ok {
                    frontend
                    frontendAccepted
                    catalog
                    catalogAccepted
                    catalogSynthesized := catalog_check_synthesized catalogAccepted
                    imports
                    importsSynthesized := importsGenerated
                    importsEvidence
                    importsAccepted
                  }

theorem checked_source_evidence {encoded : String}
    {expectedSources : List Lanius.Extraction.SourceFile}
    {checked : Checked encoded expectedSources} :
    decodeCompactPack? encoded = some checked.frontend.compact.compact.pack ∧
      compactPackSources checked.frontend.compact.compact.pack = expectedSources ∧
      SourcePackWellFormed (frontendPack checked.frontend) ∧
      CatalogWellFormed (frontendPack checked.frontend) checked.catalog.catalog ∧
      ImportCollectionCovers (frontendPack checked.frontend) checked.imports := by
  have compact := SyntaxCheck.checkCompactSourcePack_sound checked.frontend.compactAccepted
  have sourceWellFormed := FrontendCheck.CheckedFrontend.sourcePackEvidence checked.frontend
  exact ⟨compact.1, compact.2.2.1, sourceWellFormed.down,
    checked.catalog.wellFormed, checked.importsEvidence.covers⟩

/-! The structured frontend is the eventual input to direct Lean extraction.
    It shares catalog and import synthesis with the compact bootstrap path. -/

def typedFrontendPack {pack : ArtifactPack}
    {expectedSources : List Lanius.Extraction.SourceFile}
    (frontend : FrontendCheck.CheckedTypedFrontend pack expectedSources) :
    SourcePack :=
  SourcePackCheck.declaredTypedPack frontend.typedSyntax

inductive TypedFailure where
  | frontend (failure : FrontendCheck.TypedFailure)
  | catalog
  | importSynthesis
  | imports (failure : ImportCheck.Failure)
deriving DecidableEq, Repr

structure CheckedTyped (pack : ArtifactPack)
    (expectedSources : List Lanius.Extraction.SourceFile) where
  frontend : FrontendCheck.CheckedTypedFrontend pack expectedSources
  frontendAccepted : FrontendCheck.checkTyped pack expectedSources = .ok frontend
  catalog : CatalogSynthesis.Checked (typedFrontendPack frontend)
  catalogAccepted : CatalogSynthesis.check (typedFrontendPack frontend) = some catalog
  imports : List CollectedImport
  importsSynthesized : ImportSynthesis.synthesize? (typedFrontendPack frontend) = some imports
  importsEvidence : ImportCheck.Checked (typedFrontendPack frontend) imports
  importsAccepted : ImportCheck.check (typedFrontendPack frontend) imports = .ok importsEvidence

def checkTyped (pack : ArtifactPack)
    (expectedSources : List Lanius.Extraction.SourceFile) :
    Except TypedFailure (CheckedTyped pack expectedSources) :=
  match frontendAccepted : FrontendCheck.checkTyped pack expectedSources with
  | .error failure => .error (.frontend failure)
  | .ok frontend =>
      let sourcePack := typedFrontendPack frontend
      match catalogAccepted : CatalogSynthesis.check sourcePack with
      | none => .error .catalog
      | some catalog =>
          match importsSynthesized : ImportSynthesis.synthesize? sourcePack with
          | none => .error .importSynthesis
          | some imports =>
              match importsAccepted : ImportCheck.check sourcePack imports with
              | .error failure => .error (.imports failure)
              | .ok importsEvidence =>
                  .ok {
                    frontend
                    frontendAccepted
                    catalog
                    catalogAccepted
                    imports
                    importsSynthesized
                    importsEvidence
                    importsAccepted
                  }

theorem checked_typed_source_evidence {pack : ArtifactPack}
    {expectedSources : List Lanius.Extraction.SourceFile}
    (checked : CheckedTyped pack expectedSources) :
    compactPackSources pack = expectedSources ∧
      SourcePackWellFormed (typedFrontendPack checked.frontend) ∧
      CatalogWellFormed (typedFrontendPack checked.frontend) checked.catalog.catalog ∧
      ImportCollectionCovers (typedFrontendPack checked.frontend) checked.imports :=
  ⟨checked.frontend.typedSyntax.sourceIdentity,
    checked.frontend.sourcePackEvidence.down,
    checked.catalog.wellFormed, checked.importsEvidence.covers⟩

/-- The semantic checker starts from one authenticated source pack. Compact
    decoding and structured Lean syntax both construct this same input. -/
structure CoreInput where
  pack : SourcePack
  sourceWellFormed : SourcePackWellFormed pack
  catalog : CatalogSynthesis.Checked pack
  imports : List CollectedImport
  importsEvidence : ImportCheck.Checked pack imports

def coreInput {encoded : String}
    {expectedSources : List Lanius.Extraction.SourceFile}
    (checked : Checked encoded expectedSources) : CoreInput :=
  { pack := frontendPack checked.frontend
    sourceWellFormed := checked.frontend.sourcePackEvidence.down
    catalog := checked.catalog
    imports := checked.imports
    importsEvidence := checked.importsEvidence }

def typedCoreInput {pack : ArtifactPack}
    {expectedSources : List Lanius.Extraction.SourceFile}
    (checked : CheckedTyped pack expectedSources) : CoreInput :=
  { pack := typedFrontendPack checked.frontend
    sourceWellFormed := checked.frontend.sourcePackEvidence.down
    catalog := checked.catalog
    imports := checked.imports
    importsEvidence := checked.importsEvidence }

end Lanius.Compiler.FrontendBoundary
