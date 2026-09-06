import Lanius.Extraction.VerifiedFrontend.Artifact.CanonicalTokens.Sources
import Lanius.Extraction.VerifiedFrontend.Artifact.CanonicalTokens.Tokens.Canonical
import Lanius.Extraction.VerifiedFrontend.Artifact.CanonicalTokens.Tokens.Raw
import Lanius.Extraction.VerifiedFrontend.Artifact.CanonicalTokens.Tokens.SemanticKinds
import Lanius.Extraction.VerifiedFrontend.Artifact.CanonicalTokens.Cache.Parse.Assembly
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
  -- The artifact and lookup view share one quoted node table.
  parse_nodes := verifiedFrontendCanonicalTokensParseNodeTree.flatten
  parse_root := verifiedFrontendCanonicalTokensParseRoot
  surface := verifiedFrontendCanonicalTokensSurface
  resolutions := verifiedFrontendCanonicalTokensResolutions
  types := verifiedFrontendCanonicalTokensTypes
  core_program := verifiedFrontendCanonicalTokensCoreProgram
  lowering := verifiedFrontendCanonicalTokensLowering
}
end Lanius.Extraction
