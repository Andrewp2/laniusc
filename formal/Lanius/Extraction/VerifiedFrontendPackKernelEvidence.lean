import Lanius.Extraction.VerifiedFrontendPackKernelEvidenceCoverage

namespace Lanius.Extraction

def verifiedFrontendPackEvidenceKernel :
    CompleteChecker.Evidence
      (CompleteChecker.PackEvidenceValid verifiedFrontendPack) :=
  ⟨⟨verifiedFrontendPackSurfaceNodeCountsKernel,
    verifiedFrontendPack_surface_node_counts_found_kernel,
    verifiedFrontendPackUnitsEvidenceValidKernel,
    verifiedFrontendPackWireKernel,
    verifiedFrontendPackWireKernel_eq,
    verifiedFrontendPack_lowering_covers_core_kernel⟩⟩

theorem verifiedFrontendPack_evidence_valid_kernel :
    CompleteChecker.PackEvidenceValid verifiedFrontendPack :=
  verifiedFrontendPackEvidenceKernel.proof

end Lanius.Extraction
