import Lanius.Compiler.FrontendBoundary

namespace Lanius.Extraction

open Lanius
open Lanius.Compiler
open Lanius.Compiler.ProgramLowering
open Lanius.Declarations

/-! The compiler's explicit certificate mode still emits a compact syntax
    payload for the separate backend proof. `FrontendBoundary.check` binds
    that payload to the supplied source files and derives the frontend
    evidence. Ordinary extractor output is Lean Core, not this format. -/

def checkCompactFrontend (encoded : String) (expectedSources : List SourceFile) :
    Except FrontendBoundary.Failure
      (FrontendBoundary.Checked encoded expectedSources) :=
  FrontendBoundary.check encoded expectedSources

structure CompactFrontendEvidence (encoded : String)
    (expectedSources : List SourceFile)
    (checked : FrontendBoundary.Checked encoded expectedSources) : Prop where
  compact : SyntaxCheck.PackSound encoded expectedSources checked.frontend.compact
  decoded : decodeCompactPack? encoded = some checked.frontend.compact.compact.pack
  schema : checked.frontend.compact.compact.pack.schema_version = schemaVersion
  sourceIdentity :
    compactPackSources checked.frontend.compact.compact.pack = expectedSources
  sourcePackWellFormed :
    SourcePackWellFormed (FrontendBoundary.frontendPack checked.frontend)
  catalogWellFormed :
    CatalogWellFormed (FrontendBoundary.frontendPack checked.frontend)
      checked.catalog.catalog
  importsCovered :
    ImportCollectionCovers (FrontendBoundary.frontendPack checked.frontend)
      checked.imports
  surfaceAlignment :
    (FrontendBoundary.frontendPack checked.frontend).files.map
        (fun file => file.contents) =
      SourcePackCheck.surfaceFiles checked.frontend.compact.units

theorem checkCompactFrontend_sound
    {encoded : String} {expectedSources : List SourceFile}
    {checked : FrontendBoundary.Checked encoded expectedSources}
    (_accepted : checkCompactFrontend encoded expectedSources = .ok checked) :
    CompactFrontendEvidence encoded expectedSources checked := by
  have compact :=
    SyntaxCheck.checkCompactSourcePack_soundness checked.frontend.compactAccepted
  have frontend := FrontendBoundary.checked_source_evidence (checked := checked)
  exact {
    compact
    decoded := frontend.1
    schema := checked.frontend.schema
    sourceIdentity := frontend.2.1
    sourcePackWellFormed := frontend.2.2.1
    catalogWellFormed := frontend.2.2.2.1
    importsCovered := frontend.2.2.2.2
    surfaceAlignment := checked.frontend.surfaceAlignment
  }

end Lanius.Extraction
