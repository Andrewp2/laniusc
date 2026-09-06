import Lanius.Extraction.KernelReduction
import Lanius.Extraction.VerifiedFrontend.Surface.Lexer.Parse.Token
import Lanius.Extraction.ParseChecker
import Lanius.Extraction.ParseChunks
import Lanius.Extraction.VerifiedFrontend.Surface.Lexer.Parse.Nodes

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendLexer_semantic_kinds_checked_kernel :
    semanticKindsValid laniusGrammar verifiedFrontendLexerArtifact.tokens
      verifiedFrontendLexerArtifact.semantic_token_kinds = true := by
  kernel_rfl

end Lanius.Extraction

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

kernel_parse_root verifiedFrontendLexer_parse_root_present_kernel,
  verifiedFrontendLexerParseRootKernel,
  verifiedFrontendLexerParseRootKernel_eq,
  verifiedFrontendLexer_root_shape_checked_kernel for
  verifiedFrontendLexerArtifact, verifiedFrontendLexerView

end Lanius.Extraction
