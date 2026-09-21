import Lanius.Compiler.EligibilityCheck
import Lanius.Compiler.SourcePackCheck
import Lanius.Extraction.SyntaxCheck.Soundness

namespace Lanius.Compiler.FrontendCheck

open Lanius
open Lanius.Declarations
open Lanius.Extraction

inductive Failure where
  | compact (stage : SyntaxCheck.PackCheckStage)
  | sourcePack
  | eligibility (failure : EligibilityCheck.Failure)
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
  eligibility : EligibilityCheck.Checked (SourcePackCheck.declaredPack compact)
  eligibilityAccepted :
    EligibilityCheck.check (SourcePackCheck.declaredPack compact) = .ok eligibility
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
          match eligibilityAccepted :
              EligibilityCheck.check (SourcePackCheck.declaredPack compact) with
          | .error failure => .error (.eligibility failure)
          | .ok eligibility =>
              let sound := SyntaxCheck.checkCompactSourcePack_sound compactAccepted
              .ok {
                compact
                compactAccepted
                sourcePackAccepted
                sourcePackEvidence
                eligibility
                eligibilityAccepted
                decoded := sound.1
                schema := sound.2.1
                sourceIdentity := sound.2.2.1
                surfaceAlignment := SourcePackCheck.surface_alignment compact
              }

end Lanius.Compiler.FrontendCheck
