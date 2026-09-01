import Lanius.Extraction.ArtifactQuote

open Lean

namespace Lanius.Extraction

set_option maxRecDepth 100000

private def verifiedFrontendLexerSources :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/lexer.lani", sources

private def verifiedFrontendLexerTokens :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/lexer.lani", tokens

private def verifiedFrontendLexerRawTokens :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/lexer.lani", raw_tokens

private def verifiedFrontendLexerSemanticTokenKinds :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/lexer.lani", semantic_token_kinds

def verifiedFrontendLexerParseNodes0 :=
  artifact_pack_unit_parse_nodes%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/lexer.lani", 0, 1000

def verifiedFrontendLexerParseNodes1 :=
  artifact_pack_unit_parse_nodes%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/lexer.lani", 1000, 1000

def verifiedFrontendLexerParseNodes2 :=
  artifact_pack_unit_parse_nodes%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/lexer.lani", 2000, 1000

def verifiedFrontendLexerParseNodes3 :=
  artifact_pack_unit_parse_nodes%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/lexer.lani", 3000, 1000

def verifiedFrontendLexerParseNodes4 :=
  artifact_pack_unit_parse_nodes%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/lexer.lani", 4000, 1000

def verifiedFrontendLexerParseNodes5 :=
  artifact_pack_unit_parse_nodes%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/lexer.lani", 5000, 1000

def verifiedFrontendLexerParseNodes6 :=
  artifact_pack_unit_parse_nodes%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/lexer.lani", 6000, 991

def verifiedFrontendLexerNodeChunks : List (List ParseNode) := [
  verifiedFrontendLexerParseNodes0,
  verifiedFrontendLexerParseNodes1,
  verifiedFrontendLexerParseNodes2,
  verifiedFrontendLexerParseNodes3,
  verifiedFrontendLexerParseNodes4,
  verifiedFrontendLexerParseNodes5,
  verifiedFrontendLexerParseNodes6
]

private def verifiedFrontendLexerParseNodes :=
  verifiedFrontendLexerNodeChunks.flatten

private def verifiedFrontendLexerParseRoot :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/lexer.lani", parse_root

private def verifiedFrontendLexerSurface :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/lexer.lani", surface

private def verifiedFrontendLexerResolutions :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/lexer.lani", resolutions

private def verifiedFrontendLexerTypes :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/lexer.lani", types

private def verifiedFrontendLexerCoreProgram :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/lexer.lani", core_program

private def verifiedFrontendLexerLowering :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/lexer.lani", lowering

def verifiedFrontendLexerArtifact : Artifact := {
  schema_version := schemaVersion
  sources := verifiedFrontendLexerSources
  tokens := verifiedFrontendLexerTokens
  raw_tokens := verifiedFrontendLexerRawTokens
  semantic_token_kinds := verifiedFrontendLexerSemanticTokenKinds
  parse_nodes := verifiedFrontendLexerParseNodes
  parse_node_chunks := some verifiedFrontendLexerNodeChunks
  parse_root := verifiedFrontendLexerParseRoot
  surface := verifiedFrontendLexerSurface
  resolutions := verifiedFrontendLexerResolutions
  types := verifiedFrontendLexerTypes
  core_program := verifiedFrontendLexerCoreProgram
  lowering := verifiedFrontendLexerLowering
}

private def verifiedFrontendTokenScanSources :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/token_scan.lani", sources

private def verifiedFrontendTokenScanTokens :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/token_scan.lani", tokens

private def verifiedFrontendTokenScanRawTokens :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/token_scan.lani", raw_tokens

private def verifiedFrontendTokenScanSemanticTokenKinds :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/token_scan.lani", semantic_token_kinds

private def verifiedFrontendTokenScanParseNodes :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/token_scan.lani", parse_nodes

private def verifiedFrontendTokenScanParseRoot :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/token_scan.lani", parse_root

private def verifiedFrontendTokenScanSurface :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/token_scan.lani", surface

private def verifiedFrontendTokenScanResolutions :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/token_scan.lani", resolutions

private def verifiedFrontendTokenScanTypes :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/token_scan.lani", types

private def verifiedFrontendTokenScanCoreProgram :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/token_scan.lani", core_program

private def verifiedFrontendTokenScanLowering :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/token_scan.lani", lowering

def verifiedFrontendTokenScanArtifact : Artifact := {
  schema_version := schemaVersion
  sources := verifiedFrontendTokenScanSources
  tokens := verifiedFrontendTokenScanTokens
  raw_tokens := verifiedFrontendTokenScanRawTokens
  semantic_token_kinds := verifiedFrontendTokenScanSemanticTokenKinds
  parse_nodes := verifiedFrontendTokenScanParseNodes
  parse_root := verifiedFrontendTokenScanParseRoot
  surface := verifiedFrontendTokenScanSurface
  resolutions := verifiedFrontendTokenScanResolutions
  types := verifiedFrontendTokenScanTypes
  core_program := verifiedFrontendTokenScanCoreProgram
  lowering := verifiedFrontendTokenScanLowering
}

private def verifiedFrontendDigitsSources :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/digits.lani", sources

private def verifiedFrontendDigitsTokens :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/digits.lani", tokens

private def verifiedFrontendDigitsRawTokens :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/digits.lani", raw_tokens

private def verifiedFrontendDigitsSemanticTokenKinds :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/digits.lani", semantic_token_kinds

private def verifiedFrontendDigitsParseNodes :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/digits.lani", parse_nodes

private def verifiedFrontendDigitsParseRoot :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/digits.lani", parse_root

private def verifiedFrontendDigitsSurface :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/digits.lani", surface

private def verifiedFrontendDigitsResolutions :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/digits.lani", resolutions

private def verifiedFrontendDigitsTypes :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/digits.lani", types

private def verifiedFrontendDigitsCoreProgram :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/digits.lani", core_program

private def verifiedFrontendDigitsLowering :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/digits.lani", lowering

def verifiedFrontendDigitsArtifact : Artifact := {
  schema_version := schemaVersion
  sources := verifiedFrontendDigitsSources
  tokens := verifiedFrontendDigitsTokens
  raw_tokens := verifiedFrontendDigitsRawTokens
  semantic_token_kinds := verifiedFrontendDigitsSemanticTokenKinds
  parse_nodes := verifiedFrontendDigitsParseNodes
  parse_root := verifiedFrontendDigitsParseRoot
  surface := verifiedFrontendDigitsSurface
  resolutions := verifiedFrontendDigitsResolutions
  types := verifiedFrontendDigitsTypes
  core_program := verifiedFrontendDigitsCoreProgram
  lowering := verifiedFrontendDigitsLowering
}

private def verifiedFrontendTokenSources :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/token.lani", sources

private def verifiedFrontendTokenTokens :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/token.lani", tokens

private def verifiedFrontendTokenRawTokens :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/token.lani", raw_tokens

private def verifiedFrontendTokenSemanticTokenKinds :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/token.lani", semantic_token_kinds

private def verifiedFrontendTokenParseNodes :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/token.lani", parse_nodes

private def verifiedFrontendTokenParseRoot :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/token.lani", parse_root

private def verifiedFrontendTokenSurface :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/token.lani", surface

private def verifiedFrontendTokenResolutions :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/token.lani", resolutions

private def verifiedFrontendTokenTypes :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/token.lani", types

private def verifiedFrontendTokenCoreProgram :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/token.lani", core_program

private def verifiedFrontendTokenLowering :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/token.lani", lowering

def verifiedFrontendTokenArtifact : Artifact := {
  schema_version := schemaVersion
  sources := verifiedFrontendTokenSources
  tokens := verifiedFrontendTokenTokens
  raw_tokens := verifiedFrontendTokenRawTokens
  semantic_token_kinds := verifiedFrontendTokenSemanticTokenKinds
  parse_nodes := verifiedFrontendTokenParseNodes
  parse_root := verifiedFrontendTokenParseRoot
  surface := verifiedFrontendTokenSurface
  resolutions := verifiedFrontendTokenResolutions
  types := verifiedFrontendTokenTypes
  core_program := verifiedFrontendTokenCoreProgram
  lowering := verifiedFrontendTokenLowering
}

private def verifiedFrontendCanonicalTokensSources :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/canonical_tokens.lani", sources

private def verifiedFrontendCanonicalTokensTokens :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/canonical_tokens.lani", tokens

private def verifiedFrontendCanonicalTokensRawTokens :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/canonical_tokens.lani", raw_tokens

private def verifiedFrontendCanonicalTokensSemanticTokenKinds :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/canonical_tokens.lani", semantic_token_kinds

private def verifiedFrontendCanonicalTokensParseNodes :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/canonical_tokens.lani", parse_nodes

private def verifiedFrontendCanonicalTokensParseRoot :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/canonical_tokens.lani", parse_root

private def verifiedFrontendCanonicalTokensSurface :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/canonical_tokens.lani", surface

private def verifiedFrontendCanonicalTokensResolutions :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/canonical_tokens.lani", resolutions

private def verifiedFrontendCanonicalTokensTypes :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/canonical_tokens.lani", types

private def verifiedFrontendCanonicalTokensCoreProgram :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/canonical_tokens.lani", core_program

private def verifiedFrontendCanonicalTokensLowering :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/canonical_tokens.lani", lowering

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

private def verifiedFrontendDecimalSources :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/decimal.lani", sources

private def verifiedFrontendDecimalTokens :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/decimal.lani", tokens

private def verifiedFrontendDecimalRawTokens :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/decimal.lani", raw_tokens

private def verifiedFrontendDecimalSemanticTokenKinds :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/decimal.lani", semantic_token_kinds

private def verifiedFrontendDecimalParseNodes :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/decimal.lani", parse_nodes

private def verifiedFrontendDecimalParseRoot :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/decimal.lani", parse_root

private def verifiedFrontendDecimalSurface :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/decimal.lani", surface

private def verifiedFrontendDecimalResolutions :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/decimal.lani", resolutions

private def verifiedFrontendDecimalTypes :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/decimal.lani", types

private def verifiedFrontendDecimalCoreProgram :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/decimal.lani", core_program

private def verifiedFrontendDecimalLowering :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/decimal.lani", lowering

def verifiedFrontendDecimalArtifact : Artifact := {
  schema_version := schemaVersion
  sources := verifiedFrontendDecimalSources
  tokens := verifiedFrontendDecimalTokens
  raw_tokens := verifiedFrontendDecimalRawTokens
  semantic_token_kinds := verifiedFrontendDecimalSemanticTokenKinds
  parse_nodes := verifiedFrontendDecimalParseNodes
  parse_root := verifiedFrontendDecimalParseRoot
  surface := verifiedFrontendDecimalSurface
  resolutions := verifiedFrontendDecimalResolutions
  types := verifiedFrontendDecimalTypes
  core_program := verifiedFrontendDecimalCoreProgram
  lowering := verifiedFrontendDecimalLowering
}

private def verifiedFrontendNumberSources :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/number.lani", sources

private def verifiedFrontendNumberTokens :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/number.lani", tokens

private def verifiedFrontendNumberRawTokens :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/number.lani", raw_tokens

private def verifiedFrontendNumberSemanticTokenKinds :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/number.lani", semantic_token_kinds

private def verifiedFrontendNumberParseNodes :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/number.lani", parse_nodes

private def verifiedFrontendNumberParseRoot :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/number.lani", parse_root

private def verifiedFrontendNumberSurface :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/number.lani", surface

private def verifiedFrontendNumberResolutions :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/number.lani", resolutions

private def verifiedFrontendNumberTypes :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/number.lani", types

private def verifiedFrontendNumberCoreProgram :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/number.lani", core_program

private def verifiedFrontendNumberLowering :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/number.lani", lowering

def verifiedFrontendNumberArtifact : Artifact := {
  schema_version := schemaVersion
  sources := verifiedFrontendNumberSources
  tokens := verifiedFrontendNumberTokens
  raw_tokens := verifiedFrontendNumberRawTokens
  semantic_token_kinds := verifiedFrontendNumberSemanticTokenKinds
  parse_nodes := verifiedFrontendNumberParseNodes
  parse_root := verifiedFrontendNumberParseRoot
  surface := verifiedFrontendNumberSurface
  resolutions := verifiedFrontendNumberResolutions
  types := verifiedFrontendNumberTypes
  core_program := verifiedFrontendNumberCoreProgram
  lowering := verifiedFrontendNumberLowering
}

private def verifiedFrontendSymbolSources :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/symbol.lani", sources

private def verifiedFrontendSymbolTokens :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/symbol.lani", tokens

private def verifiedFrontendSymbolRawTokens :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/symbol.lani", raw_tokens

private def verifiedFrontendSymbolSemanticTokenKinds :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/symbol.lani", semantic_token_kinds

private def verifiedFrontendSymbolParseNodes :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/symbol.lani", parse_nodes

private def verifiedFrontendSymbolParseRoot :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/symbol.lani", parse_root

private def verifiedFrontendSymbolSurface :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/symbol.lani", surface

private def verifiedFrontendSymbolResolutions :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/symbol.lani", resolutions

private def verifiedFrontendSymbolTypes :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/symbol.lani", types

private def verifiedFrontendSymbolCoreProgram :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/symbol.lani", core_program

private def verifiedFrontendSymbolLowering :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/symbol.lani", lowering

def verifiedFrontendSymbolArtifact : Artifact := {
  schema_version := schemaVersion
  sources := verifiedFrontendSymbolSources
  tokens := verifiedFrontendSymbolTokens
  raw_tokens := verifiedFrontendSymbolRawTokens
  semantic_token_kinds := verifiedFrontendSymbolSemanticTokenKinds
  parse_nodes := verifiedFrontendSymbolParseNodes
  parse_root := verifiedFrontendSymbolParseRoot
  surface := verifiedFrontendSymbolSurface
  resolutions := verifiedFrontendSymbolResolutions
  types := verifiedFrontendSymbolTypes
  core_program := verifiedFrontendSymbolCoreProgram
  lowering := verifiedFrontendSymbolLowering
}

private def verifiedFrontendRawLexerSources :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/raw_lexer.lani", sources

private def verifiedFrontendRawLexerTokens :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/raw_lexer.lani", tokens

private def verifiedFrontendRawLexerRawTokens :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/raw_lexer.lani", raw_tokens

private def verifiedFrontendRawLexerSemanticTokenKinds :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/raw_lexer.lani", semantic_token_kinds

private def verifiedFrontendRawLexerParseNodes :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/raw_lexer.lani", parse_nodes

private def verifiedFrontendRawLexerParseRoot :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/raw_lexer.lani", parse_root

private def verifiedFrontendRawLexerSurface :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/raw_lexer.lani", surface

private def verifiedFrontendRawLexerResolutions :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/raw_lexer.lani", resolutions

private def verifiedFrontendRawLexerTypes :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/raw_lexer.lani", types

private def verifiedFrontendRawLexerCoreProgram :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/raw_lexer.lani", core_program

private def verifiedFrontendRawLexerLowering :=
  artifact_pack_unit_field%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/raw_lexer.lani", lowering

def verifiedFrontendRawLexerArtifact : Artifact := {
  schema_version := schemaVersion
  sources := verifiedFrontendRawLexerSources
  tokens := verifiedFrontendRawLexerTokens
  raw_tokens := verifiedFrontendRawLexerRawTokens
  semantic_token_kinds := verifiedFrontendRawLexerSemanticTokenKinds
  parse_nodes := verifiedFrontendRawLexerParseNodes
  parse_root := verifiedFrontendRawLexerParseRoot
  surface := verifiedFrontendRawLexerSurface
  resolutions := verifiedFrontendRawLexerResolutions
  types := verifiedFrontendRawLexerTypes
  core_program := verifiedFrontendRawLexerCoreProgram
  lowering := verifiedFrontendRawLexerLowering
}

/-- The authoritative frontend pack is assembled from the same named unit
    values consumed by unit-level implementation proofs. -/
def verifiedFrontendPack : ArtifactPack := {
  schema_version := schemaVersion
  units := [
    verifiedFrontendLexerArtifact,
    verifiedFrontendTokenScanArtifact,
    verifiedFrontendDigitsArtifact,
    verifiedFrontendTokenArtifact,
    verifiedFrontendCanonicalTokensArtifact,
    verifiedFrontendDecimalArtifact,
    verifiedFrontendNumberArtifact,
    verifiedFrontendSymbolArtifact,
    verifiedFrontendRawLexerArtifact
  ]
}

def verifiedFrontendSourcePaths : List String := [
  "lexer.lani",
  "token_scan.lani",
  "digits.lani",
  "token.lani",
  "canonical_tokens.lani",
  "decimal.lani",
  "number.lani",
  "symbol.lani",
  "raw_lexer.lani"
]

def verifiedFrontendSourceTexts : List String := [
  include_str ".." / ".." / ".." / "verified_compiler" / "src" /
    "verified" / "lexer.lani",
  include_str ".." / ".." / ".." / "verified_compiler" / "src" /
    "verified" / "token_scan.lani",
  include_str ".." / ".." / ".." / "verified_compiler" / "src" /
    "verified" / "digits.lani",
  include_str ".." / ".." / ".." / "verified_compiler" / "src" /
    "verified" / "token.lani",
  include_str ".." / ".." / ".." / "verified_compiler" / "src" /
    "verified" / "canonical_tokens.lani",
  include_str ".." / ".." / ".." / "verified_compiler" / "src" /
    "verified" / "decimal.lani",
  include_str ".." / ".." / ".." / "verified_compiler" / "src" /
    "verified" / "number.lani",
  include_str ".." / ".." / ".." / "verified_compiler" / "src" /
    "verified" / "symbol.lani",
  include_str ".." / ".." / ".." / "verified_compiler" / "src" /
    "verified" / "raw_lexer.lani"
]

def sourceTextBytes (source : String) : List Nat :=
  source.toUTF8.toList.map UInt8.toNat

def verifiedFrontendExtractedSources : List SourceFile :=
  verifiedFrontendPack.units.flatMap (·.sources)

theorem verifiedFrontendPack_lexer_unit :
    verifiedFrontendPack.units[0]? = some verifiedFrontendLexerArtifact := by
  rfl

theorem verifiedFrontendPack_digits_unit :
    verifiedFrontendPack.units[2]? = some verifiedFrontendDigitsArtifact := by
  rfl

/-- Both the ordered file set and every byte are tracked by Lean, so changing a
    verified frontend source without regenerating the pack invalidates this
    theorem. -/
theorem verifiedFrontendPack_tracks_sources :
    verifiedFrontendExtractedSources.map (·.path) =
        verifiedFrontendSourcePaths.map
          ("verified_compiler/src/verified/" ++ ·) ∧
      verifiedFrontendExtractedSources.map (·.bytes) =
        verifiedFrontendSourceTexts.map sourceTextBytes := by
  native_decide

end Lanius.Extraction
