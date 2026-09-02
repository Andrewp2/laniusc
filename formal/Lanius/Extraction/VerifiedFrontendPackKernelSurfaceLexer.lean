import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerAssemblyTrace

namespace Lanius.Extraction

def verifiedFrontendLexerSurfaceKernel : CheckedSurfaceArtifact
    verifiedFrontendLexerArtifact :=
  verifiedFrontendLexerCheckedSurfaceTraceKernel

theorem verifiedFrontendLexer_surface_checked_kernel :
    SurfaceArtifactValid verifiedFrontendLexerArtifact :=
  verifiedFrontendLexer_surface_trace_valid_kernel

end Lanius.Extraction
