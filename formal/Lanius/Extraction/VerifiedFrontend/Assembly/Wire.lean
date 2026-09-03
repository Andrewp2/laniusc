import Lanius.Extraction.VerifiedFrontend.Pack
import Lanius.Extraction.ArtifactPackChecker

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 0
set_option cbv.maxSteps 100000000
set_option cbv.warning false

theorem verifiedFrontendPack_wire_checked_kernel :
    (ArtifactPackChecker.mergeCorePrograms?
      verifiedFrontendPack.units).isSome = true := by
  cbv

def verifiedFrontendPackWireKernel :=
  (ArtifactPackChecker.mergeCorePrograms?
    verifiedFrontendPack.units).get verifiedFrontendPack_wire_checked_kernel

theorem verifiedFrontendPackWireKernel_eq :
    ArtifactPackChecker.mergeCorePrograms? verifiedFrontendPack.units =
      some verifiedFrontendPackWireKernel := by
  generalize found : ArtifactPackChecker.mergeCorePrograms?
    verifiedFrontendPack.units = result
  cases result <;> simp_all [verifiedFrontendPackWireKernel]

end Lanius.Extraction
