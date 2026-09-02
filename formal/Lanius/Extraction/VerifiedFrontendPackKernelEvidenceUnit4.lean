import Lanius.Extraction.VerifiedFrontendPackKernelEvidenceUnit4RemainderCertificate
import Lanius.Extraction.VerifiedFrontendPackKernelEvidenceUnit4TypeLookupsCertificate
import Lanius.Extraction.VerifiedFrontendPackKernelEvidenceUnit4LoweringLookupsCertificate

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0

theorem verifiedFrontendCanonicalTokens_evidence_checked_kernel :
    CompleteChecker.checkUnitEvidenceStructureMaterialized
      verifiedFrontendPackSurfaceNodeCountsKernel 4
      verifiedFrontendCanonicalTokensArtifact verifiedFrontendCanonicalTokensSurfaceKernel
      verifiedFrontendCanonicalTokensEvidenceNodeIndexesKernel = true := by
  with_unfolding_all
    change (CompleteChecker.checkUnitEvidenceStructureCachedBase
      verifiedFrontendPackSurfaceNodeCountsKernel 4
      verifiedFrontendCanonicalTokensArtifact
      verifiedFrontendCanonicalTokensSurfaceKernel &&
      typedLoweringRowsHaveTypeEvidenceMaterialized
        verifiedFrontendCanonicalTokensTypeNodeIndexDataKernel
        verifiedFrontendCanonicalTokensArtifact.lowering &&
      typeRowsHaveLoweringEvidenceMaterialized
        verifiedFrontendCanonicalTokensLoweringNodeIndexDataKernel
        verifiedFrontendCanonicalTokensArtifact.types) = true
    simp only [
      verifiedFrontendCanonicalTokens_evidence_remainder_checked_kernel,
      verifiedFrontendCanonicalTokens_type_lookups_checked_kernel,
      verifiedFrontendCanonicalTokens_lowering_lookups_checked_kernel,
      Bool.true_and]

theorem verifiedFrontendCanonicalTokens_evidence_valid_kernel :
    CompleteChecker.UnitEvidenceValid
      verifiedFrontendPackSurfaceNodeCountsKernel 4
      verifiedFrontendCanonicalTokensArtifact :=
  CompleteChecker.checkUnitEvidenceStructureMaterialized_sound
    verifiedFrontendCanonicalTokens_evidence_checked_kernel

end Lanius.Extraction
