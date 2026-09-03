import Lanius.Extraction.VerifiedFrontend.Surface.Lexer.Nodes.Assembly

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendLexer_parse_root_present_kernel :
    verifiedFrontendLexerArtifact.parse_root.isSome = true := by
  cbv

def verifiedFrontendLexerParseRootKernel :=
  verifiedFrontendLexerArtifact.parse_root.get
    verifiedFrontendLexer_parse_root_present_kernel

theorem verifiedFrontendLexerParseRootKernel_eq :
    verifiedFrontendLexerArtifact.parse_root =
      some verifiedFrontendLexerParseRootKernel := by
  generalize found : verifiedFrontendLexerArtifact.parse_root = result
  cases result <;> simp_all [verifiedFrontendLexerParseRootKernel]

theorem verifiedFrontendLexer_root_shape_checked_kernel :
    rootShapeValid laniusGrammar verifiedFrontendLexerArtifact.tokens.length
      verifiedFrontendLexerArtifact.parse_nodes
      verifiedFrontendLexerParseRootKernel = true := by
  cbv

end Lanius.Extraction
