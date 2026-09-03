import Lanius.Extraction.VerifiedFrontend.Artifact.TokenScan.Origins
import Lanius.Extraction.VerifiedFrontend.Surface.TokenScan.View
import Lanius.Extraction.KernelSurfacePhases

/-! Origin-path, density, and spelling-coverage certificates. -/

/-! Dense claim identifiers. -/
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendTokenScan_ids_dense_kernel :
    (verifiedFrontendTokenScanOrigins).claims.nodes.map (·.id) ==
      List.range (verifiedFrontendTokenScanOrigins).claims.nodes.length := by
  with_unfolding_all rfl
end Lanius.Extraction

/-! Node origins. -/
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendTokenScan_origin_nodes_checked_kernel :
    nodeOriginPathsValid verifiedFrontendTokenScanArtifact verifiedFrontendTokenScanView
      (verifiedFrontendTokenScanOrigins).claims.nodes (verifiedFrontendTokenScanOrigins).nodePaths = true := by
  with_unfolding_all rfl
end Lanius.Extraction

/-! Spelling origins. -/
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendTokenScan_origin_spellings_checked_kernel :
    spellingOriginPathsValid verifiedFrontendTokenScanArtifact verifiedFrontendTokenScanView
      (verifiedFrontendTokenScanOrigins).claims.spellings (verifiedFrontendTokenScanOrigins).spellingPaths = true := by
  with_unfolding_all rfl
end Lanius.Extraction

/-! Spelling coverage. -/
namespace Lanius.Extraction
set_option maxRecDepth 500000
set_option maxHeartbeats 0
theorem verifiedFrontendTokenScan_coverage_checked_kernel :
    spellingCoverageValid verifiedFrontendTokenScanArtifact (verifiedFrontendTokenScanOrigins).claims = true := by
  with_unfolding_all rfl
end Lanius.Extraction

/-! Origin certificate assembly. -/
namespace Lanius.Extraction
theorem verifiedFrontendTokenScan_origins_checked_kernel :
    (verifiedFrontendTokenScanOrigins).valid verifiedFrontendTokenScanArtifact verifiedFrontendTokenScanView = true :=
  SurfaceOrigins.valid_of_components verifiedFrontendTokenScanView verifiedFrontendTokenScanOrigins
    verifiedFrontendTokenScan_ids_dense_kernel verifiedFrontendTokenScan_origin_nodes_checked_kernel
    verifiedFrontendTokenScan_origin_spellings_checked_kernel verifiedFrontendTokenScan_coverage_checked_kernel
end Lanius.Extraction
