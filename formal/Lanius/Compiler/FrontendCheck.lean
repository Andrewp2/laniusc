import Lanius.Compiler.SourcePackCheck
import Lanius.Extraction.SyntaxCheck.Soundness

namespace Lanius.Compiler.FrontendCheck

open Lanius
open Lanius.Declarations
open Lanius.Extraction

inductive Failure where
  | compact (stage : SyntaxCheck.PackCheckStage)
  | sourcePack
deriving DecidableEq, Repr

structure CheckedFrontend (encoded : String)
    (expectedSources : List Extraction.SourceFile) where
  compact : SyntaxCheck.CheckedSourcePack encoded expectedSources
  compactAccepted :
    SyntaxCheck.checkCompactSourcePack encoded expectedSources = .ok compact
  sourcePackEvidence :
    ProofOf (SourcePackWellFormed (SourcePackCheck.declaredPack compact))
  sourcePackAccepted :
    SourcePackCheck.check compact = some sourcePackEvidence
  decoded : decodeCompactPack? encoded = some compact.compact.pack
  schema : compact.compact.pack.schema_version = schemaVersion
  sourceIdentity : compactPackSources compact.compact.pack = expectedSources
  surfaceAlignment :
    (SourcePackCheck.declaredPack compact).files.map (fun file => file.contents) =
      SourcePackCheck.surfaceFiles compact.units

def check (encoded : String) (expectedSources : List Extraction.SourceFile) :
    Except Failure (CheckedFrontend encoded expectedSources) :=
  match compactAccepted : SyntaxCheck.checkCompactSourcePack encoded expectedSources with
  | .error stage => .error (.compact stage)
  | .ok compact =>
      match sourcePackAccepted : SourcePackCheck.check compact with
      | none => .error .sourcePack
      | some sourcePackEvidence =>
          let sound := SyntaxCheck.checkCompactSourcePack_sound compactAccepted
          .ok {
            compact
            compactAccepted
            sourcePackAccepted
            sourcePackEvidence
            decoded := sound.1
            schema := sound.2.1
            sourceIdentity := sound.2.2.1
            surfaceAlignment := SourcePackCheck.surface_alignment compact
          }

/-! The direct-Lean frontend carries structured syntax evidence, not a
    compact wire image. It reuses the same syntax and source-pack checks. -/

inductive TypedFailure where
  | syntax (stage : SyntaxCheck.TypedPackCheckStage)
  | sourcePack
deriving DecidableEq, Repr

structure CheckedTypedFrontend (pack : ArtifactPack)
    (expectedSources : List Extraction.SourceFile) where
  typedSyntax : SyntaxCheck.CheckedTypedSourcePack pack expectedSources
  syntaxAccepted : SyntaxCheck.checkTypedSourcePack pack expectedSources = .ok typedSyntax
  sourcePackEvidence :
    ProofOf (SourcePackWellFormed (SourcePackCheck.declaredTypedPack typedSyntax))
  sourcePackAccepted :
    checkSourcePackWellFormed (SourcePackCheck.declaredTypedPack typedSyntax) =
      some sourcePackEvidence

def checkTyped (pack : ArtifactPack)
    (expectedSources : List Extraction.SourceFile) :
    Except TypedFailure (CheckedTypedFrontend pack expectedSources) :=
  match syntaxAccepted : SyntaxCheck.checkTypedSourcePack pack expectedSources with
  | .error stage => .error (.syntax stage)
  | .ok typedSyntax =>
      match sourcePackAccepted :
          checkSourcePackWellFormed (SourcePackCheck.declaredTypedPack typedSyntax) with
      | none => .error .sourcePack
      | some sourcePackEvidence =>
          .ok { typedSyntax, syntaxAccepted, sourcePackEvidence, sourcePackAccepted }

end Lanius.Compiler.FrontendCheck
