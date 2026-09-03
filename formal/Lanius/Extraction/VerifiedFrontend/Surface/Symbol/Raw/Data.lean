import Lanius.Extraction.VerifiedFrontend.Artifact.Symbol.Artifact
import Lanius.Extraction.ParseChunks
namespace Lanius.Extraction
set_option maxRecDepth 100000
theorem verifiedFrontendSymbol_source_decoded_present_kernel :
    (decodeSingleSource verifiedFrontendSymbolArtifact.sources).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendSymbolDecodedSource : List Lanius.Compiler.Lexer.Byte :=
  (decodeSingleSource verifiedFrontendSymbolArtifact.sources).get
    verifiedFrontendSymbol_source_decoded_present_kernel
theorem verifiedFrontendSymbol_source_decoded_found_kernel :
    decodeSingleSource verifiedFrontendSymbolArtifact.sources =
      some verifiedFrontendSymbolDecodedSource :=
  parseOptionEqSomeGet verifiedFrontendSymbol_source_decoded_present_kernel
theorem verifiedFrontendSymbol_raw_rows_present_kernel :
    verifiedFrontendSymbolArtifact.raw_tokens.isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendSymbolRawRows : List Token :=
  verifiedFrontendSymbolArtifact.raw_tokens.get
    verifiedFrontendSymbol_raw_rows_present_kernel
theorem verifiedFrontendSymbol_raw_rows_found_kernel :
    verifiedFrontendSymbolArtifact.raw_tokens = some verifiedFrontendSymbolRawRows :=
  parseOptionEqSomeGet verifiedFrontendSymbol_raw_rows_present_kernel
theorem verifiedFrontendSymbol_raw_tokens_decoded_present_kernel :
    (decodeTokens verifiedFrontendSymbolRawRows).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendSymbolDecodedRawTokens : List Lanius.Compiler.Lexer.RawToken :=
  (decodeTokens verifiedFrontendSymbolRawRows).get
    verifiedFrontendSymbol_raw_tokens_decoded_present_kernel
theorem verifiedFrontendSymbol_raw_tokens_decoded_found_kernel :
    decodeTokens verifiedFrontendSymbolRawRows =
      some verifiedFrontendSymbolDecodedRawTokens :=
  parseOptionEqSomeGet verifiedFrontendSymbol_raw_tokens_decoded_present_kernel
end Lanius.Extraction
