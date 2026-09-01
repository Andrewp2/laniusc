import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructLength

namespace Lanius.Extraction

theorem reconstructArtifactSurface_step
    {artifact : Artifact} {root fuel finish : Nat} {surface : SurfaceFile}
    (rootFound : artifact.parse_root = some root)
    (fuelFound : artifact.parse_nodes.length + 1 = fuel)
    (fileFound : (reconstructFile fuel artifact root).run 0 =
      some (surface, finish)) :
    reconstructArtifactSurface artifact = some surface := by
  unfold reconstructArtifactSurface
  rw [rootFound, fuelFound]
  simpa [fileFound]

theorem verifiedFrontendLexerReconstructedKernel_eq :
    reconstructArtifactSurface verifiedFrontendLexerArtifact =
      some verifiedFrontendLexerReconstructedKernel := by
  exact reconstructArtifactSurface_step
    verifiedFrontendLexer_parse_root_value_kernel
    (by rw [verifiedFrontendLexer_parse_nodes_length_kernel] :
      verifiedFrontendLexerArtifact.parse_nodes.length + 1 = 6992)
    verifiedFrontendLexer_reconstruct_file_kernel

end Lanius.Extraction
