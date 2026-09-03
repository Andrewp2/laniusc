import Lanius.Extraction.CompleteChecker
import Lanius.Extraction.VerifiedFrontend.Parser.Artifact

namespace Lanius.Extraction

set_option maxRecDepth 1000000

/-!
The parser artifact is large enough that compiling its complete decision
procedure dominates downstream Lean rebuilds. Keep the accepted dependent
certificate behind this module boundary: changes to execution proofs can then
reuse the `.olean` instead of regenerating the native checker declaration.
-/

/-- The first reusable stage is the parser's checked located Surface tree. -/
theorem verifiedParser_scoped_surface_accepted :
    (ScopedSurface.checkArtifact? verifiedParserArtifact).isSome = true := by
  native_decide

def verifiedParserScopedArtifact :
    ScopedSurface.CheckedArtifact verifiedParserArtifact :=
  (ScopedSurface.checkArtifact? verifiedParserArtifact).get
    verifiedParser_scoped_surface_accepted

/-- Acceptance is deliberately through the complete checker: source bytes,
    token spans, production-labelled parse tree, reconstructed Surface syntax,
    tagged lexical-resolution paths, type/lowering evidence, and Core typing
    are one boundary. The checker consumes the exact scoped value above. -/
theorem verifiedParserArtifact_completely_checked :
    (CompleteChecker.extendScopedArtifact? verifiedParserArtifact
      verifiedParserScopedArtifact).isSome = true := by
  native_decide

def verifiedParserChecked :
    CompleteChecker.CheckedArtifact verifiedParserArtifact
      verifiedParserScopedArtifact :=
  (CompleteChecker.extendScopedArtifact? verifiedParserArtifact
    verifiedParserScopedArtifact).get verifiedParserArtifact_completely_checked

end Lanius.Extraction
