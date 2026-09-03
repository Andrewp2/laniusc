import Lanius.Extraction.VerifiedFrontend.Surface.Lexer.Root
import Lanius.Extraction.VerifiedFrontend.Surface.Lexer.Parse.Assembly
import Lanius.Extraction.VerifiedFrontend.Surface.Lexer.Semantic
import Lanius.Extraction.SurfaceReconstruct

namespace Lanius.Extraction

set_option maxRecDepth 100000

theorem verifiedFrontendLexerParseValidKernel :
    ParseArtifactValid verifiedFrontendLexerArtifact :=
  ⟨checkTokenArtifact_sound verifiedFrontendLexer_token_checked_kernel,
    verifiedFrontendLexer_semantic_kinds_checked_kernel,
    checkNodesFrom_sound verifiedFrontendLexer_parse_nodes_checked_kernel,
    verifiedFrontendLexerParseRootKernel,
    verifiedFrontendLexerParseRootKernel_eq,
    rootShapeValid_sound verifiedFrontendLexer_root_shape_checked_kernel⟩

theorem verifiedFrontendLexer_parse_checked_kernel :
    checkParseArtifact verifiedFrontendLexerArtifact = true := by
  unfold checkParseArtifact
  rw [verifiedFrontendLexer_token_checked_kernel]
  rw [verifiedFrontendLexer_semantic_kinds_checked_kernel]
  rw [verifiedFrontendLexer_parse_nodes_checked_kernel]
  rw [verifiedFrontendLexerParseRootKernel_eq]
  exact verifiedFrontendLexer_root_shape_checked_kernel

theorem verifiedFrontendLexer_parse_view_checked_kernel :
    checkParseArtifactView verifiedFrontendLexerArtifact
      verifiedFrontendLexerView = true := by
  rw [checkParseArtifactView_eq]
  exact verifiedFrontendLexer_parse_checked_kernel

end Lanius.Extraction
