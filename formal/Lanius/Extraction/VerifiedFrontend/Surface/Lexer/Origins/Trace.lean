import Lanius.Extraction.VerifiedFrontend.Surface.Lexer.Origins.Claims
import Lanius.Extraction.VerifiedFrontend.Surface.Lexer.Origins.Ids
import Lanius.Extraction.VerifiedFrontend.Surface.Lexer.Origins.Nodes
import Lanius.Extraction.VerifiedFrontend.Surface.Lexer.Origins.Spellings
import Lanius.Extraction.VerifiedFrontend.Surface.Lexer.Origins.Coverage

namespace Lanius.Extraction

theorem verifiedFrontendLexer_origins_trace_checked_kernel :
    verifiedFrontendLexerOrigins.valid verifiedFrontendLexerArtifact
      verifiedFrontendLexerView = true :=
  SurfaceOrigins.valid_of_components verifiedFrontendLexerView
    verifiedFrontendLexerOrigins
    verifiedFrontendLexer_origin_trace_ids_dense_kernel
    verifiedFrontendLexer_node_origin_trace_checked_kernel
    verifiedFrontendLexer_spelling_origin_trace_checked_kernel
    verifiedFrontendLexer_origin_trace_coverage_checked_kernel

end Lanius.Extraction
