import Lanius.Extraction.VerifiedFrontend.Artifact.CanonicalTokens.Artifact
import Lanius.Extraction.ParseChunks

namespace Lanius.Extraction
set_option maxRecDepth 500000

theorem verifiedFrontendCanonicalTokens_source_decoded_present_kernel :
    (decodeSingleSource verifiedFrontendCanonicalTokensArtifact.sources).isSome =
      true := by
  with_unfolding_all rfl

def verifiedFrontendCanonicalTokensDecodedSource :
    List Lanius.Compiler.Lexer.Byte :=
  (decodeSingleSource verifiedFrontendCanonicalTokensArtifact.sources).get
    verifiedFrontendCanonicalTokens_source_decoded_present_kernel

theorem verifiedFrontendCanonicalTokens_source_decoded_found_kernel :
    decodeSingleSource verifiedFrontendCanonicalTokensArtifact.sources =
      some verifiedFrontendCanonicalTokensDecodedSource :=
  parseOptionEqSomeGet verifiedFrontendCanonicalTokens_source_decoded_present_kernel

theorem verifiedFrontendCanonicalTokens_raw_rows_present_kernel :
    verifiedFrontendCanonicalTokensArtifact.raw_tokens.isSome = true := by
  with_unfolding_all rfl

def verifiedFrontendCanonicalTokensRawRows : List Token :=
  verifiedFrontendCanonicalTokensArtifact.raw_tokens.get
    verifiedFrontendCanonicalTokens_raw_rows_present_kernel

theorem verifiedFrontendCanonicalTokens_raw_rows_found_kernel :
    verifiedFrontendCanonicalTokensArtifact.raw_tokens =
      some verifiedFrontendCanonicalTokensRawRows :=
  parseOptionEqSomeGet verifiedFrontendCanonicalTokens_raw_rows_present_kernel

theorem verifiedFrontendCanonicalTokens_raw_tokens_decoded_present_kernel :
    (decodeTokens verifiedFrontendCanonicalTokensRawRows).isSome = true := by
  with_unfolding_all rfl

def verifiedFrontendCanonicalTokensDecodedRawTokens :
    List Lanius.Compiler.Lexer.RawToken :=
  (decodeTokens verifiedFrontendCanonicalTokensRawRows).get
    verifiedFrontendCanonicalTokens_raw_tokens_decoded_present_kernel

theorem verifiedFrontendCanonicalTokens_raw_tokens_decoded_found_kernel :
    decodeTokens verifiedFrontendCanonicalTokensRawRows =
      some verifiedFrontendCanonicalTokensDecodedRawTokens :=
  parseOptionEqSomeGet
    verifiedFrontendCanonicalTokens_raw_tokens_decoded_present_kernel

end Lanius.Extraction
