import Lanius.Extraction.VerifiedFrontendPack
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexer
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceTokenScan
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceDigits
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceToken
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceCanonicalTokens
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceDecimal
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceNumber
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceSymbol
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceRawLexer
import Lanius.Extraction.ArtifactPackChecker

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

theorem verifiedFrontendPack_surface_data_checked_kernel :
    ArtifactPackChecker.UnitsSurfaceValid verifiedFrontendPack.units :=
  verifiedFrontendPackSurfaceDataKernel.valid

end Lanius.Extraction
