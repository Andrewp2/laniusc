import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceTokenScan
import Lanius.Extraction.ArtifactPackContextChecker
import Lanius.Extraction.ParseChunks
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
theorem verifiedFrontendTokenScan_checked_surface_value_kernel :
    verifiedFrontendTokenScanSurfaceKernel.surface = verifiedFrontendTokenScanDecodedSurfaceKernel := by
  rfl
theorem verifiedFrontendTokenScan_module_path_present_kernel :
    (ArtifactPackContextChecker.declaredModulePath? verifiedFrontendTokenScanDecodedSurfaceKernel).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendTokenScanModulePathKernel :=
  (ArtifactPackContextChecker.declaredModulePath? verifiedFrontendTokenScanDecodedSurfaceKernel).get
    verifiedFrontendTokenScan_module_path_present_kernel
theorem verifiedFrontendTokenScan_module_path_found_kernel :
    ArtifactPackContextChecker.declaredModulePath? verifiedFrontendTokenScanDecodedSurfaceKernel =
      some verifiedFrontendTokenScanModulePathKernel :=
  parseOptionEqSomeGet verifiedFrontendTokenScan_module_path_present_kernel
theorem verifiedFrontendTokenScan_checked_module_path_found_kernel :
    ArtifactPackContextChecker.declaredModulePath? verifiedFrontendTokenScanSurfaceKernel.surface =
      some verifiedFrontendTokenScanModulePathKernel := by
  rw [verifiedFrontendTokenScan_checked_surface_value_kernel]
  exact verifiedFrontendTokenScan_module_path_found_kernel
theorem verifiedFrontendTokenScan_core_program_present_kernel :
    (verifiedFrontendTokenScanArtifact.core_program.map CoreDecode.program).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendTokenScanCoreProgramKernel :=
  (verifiedFrontendTokenScanArtifact.core_program.map CoreDecode.program).get
    verifiedFrontendTokenScan_core_program_present_kernel
theorem verifiedFrontendTokenScan_core_program_found_kernel :
    verifiedFrontendTokenScanArtifact.core_program.map CoreDecode.program =
      some verifiedFrontendTokenScanCoreProgramKernel :=
  parseOptionEqSomeGet verifiedFrontendTokenScan_core_program_present_kernel
theorem verifiedFrontendTokenScan_surface_decoded_kernel :
    decodeReconstructedSurface verifiedFrontendTokenScanArtifact = some verifiedFrontendTokenScanDecodedSurfaceKernel :=
  calc
    decodeReconstructedSurface verifiedFrontendTokenScanArtifact =
        decodeReconstructedSurfaceView verifiedFrontendTokenScanArtifact verifiedFrontendTokenScanSurfaceKernel.view :=
      (decodeReconstructedSurfaceView_eq verifiedFrontendTokenScanArtifact verifiedFrontendTokenScanSurfaceKernel.view).symm
    _ = some verifiedFrontendTokenScanSurfaceKernel.surface := verifiedFrontendTokenScanSurfaceKernel.surfaceFound
    _ = some verifiedFrontendTokenScanDecodedSurfaceKernel := congrArg some verifiedFrontendTokenScan_checked_surface_value_kernel
def verifiedFrontendTokenScanProgramUnitKernel : ArtifactPackContextChecker.ProgramUnit := {
  artifact := verifiedFrontendTokenScanArtifact
  moduleId := 1
  modulePath := verifiedFrontendTokenScanModulePathKernel
  surface := verifiedFrontendTokenScanDecodedSurfaceKernel
  surfaceDecoded := verifiedFrontendTokenScan_surface_decoded_kernel
  moduleDeclared := verifiedFrontendTokenScan_module_path_found_kernel
  core := verifiedFrontendTokenScanCoreProgramKernel
  coreDecoded := verifiedFrontendTokenScan_core_program_found_kernel
}
end Lanius.Extraction
