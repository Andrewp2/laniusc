import Lanius.Extraction.ArtifactQuote

namespace Lanius.Extraction

set_option maxRecDepth 1000000

def verifiedParserSourceText : String :=
  include_str ".." / ".." / ".." / ".." / ".." / "verified_compiler" / "src" /
    "verified" / "parser.lani"

def verifiedParserSchemaVersion : Nat :=
  artifact_field% (include_str ".." / ".." / "Artifacts" / "parser.json"), schema_version

def verifiedParserSources : List SourceFile :=
  artifact_field% (include_str ".." / ".." / "Artifacts" / "parser.json"), sources

def verifiedParserTokens : List Token :=
  artifact_field% (include_str ".." / ".." / "Artifacts" / "parser.json"), tokens

def verifiedParserSemanticTokenKinds : List Nat :=
  artifact_field%
    (include_str ".." / ".." / "Artifacts" / "parser.json"), semantic_token_kinds

def verifiedParserParseNodes0 : List ParseNode :=
  artifact_parse_nodes% (include_str ".." / ".." / "Artifacts" / "parser.json"), 0, 6474

def verifiedParserParseNodes1 : List ParseNode :=
  artifact_parse_nodes% (include_str ".." / ".." / "Artifacts" / "parser.json"), 6474, 6474

def verifiedParserParseNodes2 : List ParseNode :=
  artifact_parse_nodes% (include_str ".." / ".." / "Artifacts" / "parser.json"), 12948, 6474

def verifiedParserParseNodes3 : List ParseNode :=
  artifact_parse_nodes% (include_str ".." / ".." / "Artifacts" / "parser.json"), 19422, 6474

def verifiedParserParseNodes : List ParseNode :=
  verifiedParserParseNodes0 ++ verifiedParserParseNodes1 ++
    verifiedParserParseNodes2 ++ verifiedParserParseNodes3

def verifiedParserParseRoot : Option ParseNodeId :=
  artifact_field% (include_str ".." / ".." / "Artifacts" / "parser.json"), parse_root

def verifiedParserSurface : Option SurfaceFile :=
  artifact_field% (include_str ".." / ".." / "Artifacts" / "parser.json"), surface

def verifiedParserResolutions : List ResolutionEvidence :=
  artifact_field% (include_str ".." / ".." / "Artifacts" / "parser.json"), resolutions

def verifiedParserTypes : List TypeEvidence :=
  artifact_field% (include_str ".." / ".." / "Artifacts" / "parser.json"), types

def verifiedParserCoreTarget : CoreTarget :=
  artifact_core_field% (include_str ".." / ".." / "Artifacts" / "parser.json"), target

def verifiedParserCoreStructures : List CoreStructDecl :=
  artifact_core_field% (include_str ".." / ".." / "Artifacts" / "parser.json"), structures

def verifiedParserCoreEnumerations : List CoreEnumDecl :=
  artifact_core_field% (include_str ".." / ".." / "Artifacts" / "parser.json"), enumerations

def verifiedParserCoreConstants : List CoreConstant :=
  artifact_core_field% (include_str ".." / ".." / "Artifacts" / "parser.json"), constants

def verifiedParserCoreFunctions : List CoreFunction :=
  artifact_core_field% (include_str ".." / ".." / "Artifacts" / "parser.json"), functions

def verifiedParserCoreProgram : CoreProgram := {
  target := verifiedParserCoreTarget
  structures := verifiedParserCoreStructures
  enumerations := verifiedParserCoreEnumerations
  constants := verifiedParserCoreConstants
  functions := verifiedParserCoreFunctions
}

def verifiedParserCoreProgramWire : Option CoreProgram :=
  some verifiedParserCoreProgram

def verifiedParserLowering : List LoweringEvidence :=
  artifact_field% (include_str ".." / ".." / "Artifacts" / "parser.json"), lowering

/-- The parser artifact is a small record of independently compiled quoted
    fields. It is definitionally the JSON artifact, but no single declaration
    contains the entire constructor tree. -/
def verifiedParserArtifact : Artifact := {
  schema_version := verifiedParserSchemaVersion
  sources := verifiedParserSources
  tokens := verifiedParserTokens
  semantic_token_kinds := verifiedParserSemanticTokenKinds
  parse_nodes := verifiedParserParseNodes
  parse_root := verifiedParserParseRoot
  surface := verifiedParserSurface
  resolutions := verifiedParserResolutions
  types := verifiedParserTypes
  core_program := verifiedParserCoreProgramWire
  lowering := verifiedParserLowering
}

def verifiedParserCore : Lanius.Core.Program :=
  match verifiedParserCoreProgramWire with
  | some wire => CoreDecode.program wire
  | none => {}

end Lanius.Extraction
