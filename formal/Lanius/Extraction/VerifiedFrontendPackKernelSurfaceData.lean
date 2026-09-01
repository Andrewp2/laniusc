import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceRawLexer

namespace Lanius.Extraction

def verifiedFrontendPackSurfaceDataKernel :
    ArtifactPackChecker.CheckedUnitSurfaces verifiedFrontendPack.units :=
  .cons verifiedFrontendLexerSurfaceKernel
    (.cons verifiedFrontendTokenScanSurfaceKernel
    (.cons verifiedFrontendDigitsSurfaceKernel
    (.cons verifiedFrontendTokenSurfaceKernel
    (.cons verifiedFrontendCanonicalTokensSurfaceKernel
    (.cons verifiedFrontendDecimalSurfaceKernel
    (.cons verifiedFrontendNumberSurfaceKernel
    (.cons verifiedFrontendSymbolSurfaceKernel
    (.cons verifiedFrontendRawLexerSurfaceKernel .nil))))))))

theorem verifiedFrontendPackSurfaceDataKernel_eq :
    ArtifactPackChecker.checkUnitSurfacesCached verifiedFrontendPack.units =
      some verifiedFrontendPackSurfaceDataKernel := by
  simp only [verifiedFrontendPack, ArtifactPackChecker.checkUnitSurfacesCached]
  rw [verifiedFrontendLexerSurfaceKernel_eq]
  rw [verifiedFrontendTokenScanSurfaceKernel_eq]
  rw [verifiedFrontendDigitsSurfaceKernel_eq]
  rw [verifiedFrontendTokenSurfaceKernel_eq]
  rw [verifiedFrontendCanonicalTokensSurfaceKernel_eq]
  rw [verifiedFrontendDecimalSurfaceKernel_eq]
  rw [verifiedFrontendNumberSurfaceKernel_eq]
  rw [verifiedFrontendSymbolSurfaceKernel_eq]
  rw [verifiedFrontendRawLexerSurfaceKernel_eq]
  rfl

theorem verifiedFrontendPack_surface_data_checked_kernel :
    (ArtifactPackChecker.checkUnitSurfacesCached
      verifiedFrontendPack.units).isSome = true := by
  rw [verifiedFrontendPackSurfaceDataKernel_eq]
  rfl

end Lanius.Extraction
