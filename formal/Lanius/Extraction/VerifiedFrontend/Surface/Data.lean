import Lanius.Extraction.VerifiedFrontend.Pack
import Lanius.Extraction.VerifiedFrontend.Surface.Lexer.Assembly
import Lanius.Extraction.VerifiedFrontend.Surface.TokenScan.Assembly
import Lanius.Extraction.VerifiedFrontend.Surface.Digits.Assembly
import Lanius.Extraction.VerifiedFrontend.Surface.Token.Assembly
import Lanius.Extraction.VerifiedFrontend.Surface.CanonicalTokens.Assembly
import Lanius.Extraction.VerifiedFrontend.Surface.Decimal.Assembly
import Lanius.Extraction.VerifiedFrontend.Surface.Number.Assembly
import Lanius.Extraction.VerifiedFrontend.Surface.Symbol.Assembly
import Lanius.Extraction.VerifiedFrontend.Surface.RawLexer.Assembly
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
