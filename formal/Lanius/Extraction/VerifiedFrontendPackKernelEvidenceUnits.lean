import Lanius.Extraction.VerifiedFrontendPackKernelEvidenceUnit0
import Lanius.Extraction.VerifiedFrontendPackKernelEvidenceUnit1
import Lanius.Extraction.VerifiedFrontendPackKernelEvidenceUnit2
import Lanius.Extraction.VerifiedFrontendPackKernelEvidenceUnit3
import Lanius.Extraction.VerifiedFrontendPackKernelEvidenceUnit4
import Lanius.Extraction.VerifiedFrontendPackKernelEvidenceUnit5
import Lanius.Extraction.VerifiedFrontendPackKernelEvidenceUnit6
import Lanius.Extraction.VerifiedFrontendPackKernelEvidenceUnit7
import Lanius.Extraction.VerifiedFrontendPackKernelEvidenceUnit8

namespace Lanius.Extraction

theorem verifiedFrontendPackEvidenceTail9Kernel :
    CompleteChecker.UnitsEvidenceValid
      verifiedFrontendPackSurfaceNodeCountsKernel 9 [] := .nil 9

theorem verifiedFrontendPackEvidenceTail8Kernel :
    CompleteChecker.UnitsEvidenceValid verifiedFrontendPackSurfaceNodeCountsKernel 8
      [verifiedFrontendRawLexerArtifact] :=
  .cons verifiedFrontendRawLexer_evidence_valid_kernel
    verifiedFrontendPackEvidenceTail9Kernel

theorem verifiedFrontendPackEvidenceTail7Kernel :
    CompleteChecker.UnitsEvidenceValid verifiedFrontendPackSurfaceNodeCountsKernel 7
      [verifiedFrontendSymbolArtifact, verifiedFrontendRawLexerArtifact] :=
  .cons verifiedFrontendSymbol_evidence_valid_kernel
    verifiedFrontendPackEvidenceTail8Kernel

theorem verifiedFrontendPackEvidenceTail6Kernel :
    CompleteChecker.UnitsEvidenceValid verifiedFrontendPackSurfaceNodeCountsKernel 6
      [verifiedFrontendNumberArtifact, verifiedFrontendSymbolArtifact,
        verifiedFrontendRawLexerArtifact] :=
  .cons verifiedFrontendNumber_evidence_valid_kernel
    verifiedFrontendPackEvidenceTail7Kernel

theorem verifiedFrontendPackEvidenceTail5Kernel :
    CompleteChecker.UnitsEvidenceValid verifiedFrontendPackSurfaceNodeCountsKernel 5
      [verifiedFrontendDecimalArtifact, verifiedFrontendNumberArtifact,
        verifiedFrontendSymbolArtifact, verifiedFrontendRawLexerArtifact] :=
  .cons verifiedFrontendDecimal_evidence_valid_kernel
    verifiedFrontendPackEvidenceTail6Kernel

theorem verifiedFrontendPackEvidenceTail4Kernel :
    CompleteChecker.UnitsEvidenceValid verifiedFrontendPackSurfaceNodeCountsKernel 4
      [verifiedFrontendCanonicalTokensArtifact, verifiedFrontendDecimalArtifact,
        verifiedFrontendNumberArtifact, verifiedFrontendSymbolArtifact,
        verifiedFrontendRawLexerArtifact] :=
  .cons verifiedFrontendCanonicalTokens_evidence_valid_kernel
    verifiedFrontendPackEvidenceTail5Kernel

theorem verifiedFrontendPackEvidenceTail3Kernel :
    CompleteChecker.UnitsEvidenceValid verifiedFrontendPackSurfaceNodeCountsKernel 3
      [verifiedFrontendTokenArtifact, verifiedFrontendCanonicalTokensArtifact,
        verifiedFrontendDecimalArtifact, verifiedFrontendNumberArtifact,
        verifiedFrontendSymbolArtifact, verifiedFrontendRawLexerArtifact] :=
  .cons verifiedFrontendToken_evidence_valid_kernel
    verifiedFrontendPackEvidenceTail4Kernel

theorem verifiedFrontendPackEvidenceTail2Kernel :
    CompleteChecker.UnitsEvidenceValid verifiedFrontendPackSurfaceNodeCountsKernel 2
      [verifiedFrontendDigitsArtifact, verifiedFrontendTokenArtifact,
        verifiedFrontendCanonicalTokensArtifact, verifiedFrontendDecimalArtifact,
        verifiedFrontendNumberArtifact, verifiedFrontendSymbolArtifact,
        verifiedFrontendRawLexerArtifact] :=
  .cons verifiedFrontendDigits_evidence_valid_kernel
    verifiedFrontendPackEvidenceTail3Kernel

theorem verifiedFrontendPackEvidenceTail1Kernel :
    CompleteChecker.UnitsEvidenceValid verifiedFrontendPackSurfaceNodeCountsKernel 1
      [verifiedFrontendTokenScanArtifact, verifiedFrontendDigitsArtifact,
        verifiedFrontendTokenArtifact, verifiedFrontendCanonicalTokensArtifact,
        verifiedFrontendDecimalArtifact, verifiedFrontendNumberArtifact,
        verifiedFrontendSymbolArtifact, verifiedFrontendRawLexerArtifact] :=
  .cons verifiedFrontendTokenScan_evidence_valid_kernel
    verifiedFrontendPackEvidenceTail2Kernel

theorem verifiedFrontendPackUnitsEvidenceValidKernel :
    CompleteChecker.UnitsEvidenceValid
      verifiedFrontendPackSurfaceNodeCountsKernel 0 verifiedFrontendPack.units :=
  .cons verifiedFrontendLexer_evidence_valid_kernel
    verifiedFrontendPackEvidenceTail1Kernel

theorem verifiedFrontendPack_surface_node_counts_found_kernel :
    CompleteChecker.collectSurfaceNodeCounts? verifiedFrontendPack.units =
      some verifiedFrontendPackSurfaceNodeCountsKernel := by
  rw [CompleteChecker.collectSurfaceNodeCountsCached
    verifiedFrontendPackSurfaceDataKernel]
  rw [verifiedFrontendPackSurfaceNodeCountsKernel_eq]

end Lanius.Extraction
