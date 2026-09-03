import Lanius.Extraction.VerifiedFrontend.Artifact.CanonicalTokens.Sources
import Lanius.Extraction.VerifiedFrontend.Artifact.CanonicalTokens.Tokens.Canonical
import Lanius.Extraction.VerifiedFrontend.Artifact.CanonicalTokens.Tokens.Raw
import Lanius.Extraction.VerifiedFrontend.Artifact.CanonicalTokens.Tokens.SemanticKinds
import Lanius.Extraction.VerifiedFrontend.Artifact.CanonicalTokens.ParseNodes.Assembly
import Lanius.Extraction.VerifiedFrontend.Artifact.CanonicalTokens.Parse.Root
import Lanius.Extraction.VerifiedFrontend.Artifact.CanonicalTokens.Surface
import Lanius.Extraction.VerifiedFrontend.Artifact.CanonicalTokens.Resolutions
import Lanius.Extraction.VerifiedFrontend.Artifact.CanonicalTokens.Types
import Lanius.Extraction.VerifiedFrontend.Artifact.CanonicalTokens.Core.Program
import Lanius.Extraction.VerifiedFrontend.Artifact.CanonicalTokens.Lowering

namespace Lanius.Extraction
def verifiedFrontendCanonicalTokensArtifact : Artifact := {
  schema_version := schemaVersion
  sources := verifiedFrontendCanonicalTokensSources
  tokens := verifiedFrontendCanonicalTokensTokens
  raw_tokens := verifiedFrontendCanonicalTokensRawTokens
  semantic_token_kinds := verifiedFrontendCanonicalTokensSemanticTokenKinds
  parse_nodes := verifiedFrontendCanonicalTokensParseNodes
  parse_root := verifiedFrontendCanonicalTokensParseRoot
  surface := verifiedFrontendCanonicalTokensSurface
  resolutions := verifiedFrontendCanonicalTokensResolutions
  types := verifiedFrontendCanonicalTokensTypes
  core_program := verifiedFrontendCanonicalTokensCoreProgram
  lowering := verifiedFrontendCanonicalTokensLowering
}
end Lanius.Extraction
