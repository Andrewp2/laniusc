import Lanius.Extraction.VerifiedFrontend.Surface.Number.Assembly
import Lanius.Extraction.ArtifactPackContextChecker
import Lanius.Extraction.ParseChunks
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
theorem verifiedFrontendNumber_checked_surface_value_kernel :
    verifiedFrontendNumberSurfaceKernel.surface = verifiedFrontendNumberDecodedSurfaceKernel := by
  rfl
theorem verifiedFrontendNumber_module_path_present_kernel :
    (ArtifactPackContextChecker.declaredModulePath? verifiedFrontendNumberDecodedSurfaceKernel).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendNumberModulePathKernel :=
  (ArtifactPackContextChecker.declaredModulePath? verifiedFrontendNumberDecodedSurfaceKernel).get
    verifiedFrontendNumber_module_path_present_kernel
theorem verifiedFrontendNumber_module_path_found_kernel :
    ArtifactPackContextChecker.declaredModulePath? verifiedFrontendNumberDecodedSurfaceKernel =
      some verifiedFrontendNumberModulePathKernel :=
  parseOptionEqSomeGet verifiedFrontendNumber_module_path_present_kernel
theorem verifiedFrontendNumber_checked_module_path_found_kernel :
    ArtifactPackContextChecker.declaredModulePath? verifiedFrontendNumberSurfaceKernel.surface =
      some verifiedFrontendNumberModulePathKernel := by
  rw [verifiedFrontendNumber_checked_surface_value_kernel]
  exact verifiedFrontendNumber_module_path_found_kernel
theorem verifiedFrontendNumber_core_program_present_kernel :
    (verifiedFrontendNumberArtifact.core_program.map CoreDecode.program).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendNumberCoreProgramKernel :=
  (verifiedFrontendNumberArtifact.core_program.map CoreDecode.program).get
    verifiedFrontendNumber_core_program_present_kernel
theorem verifiedFrontendNumber_core_program_found_kernel :
    verifiedFrontendNumberArtifact.core_program.map CoreDecode.program =
      some verifiedFrontendNumberCoreProgramKernel :=
  parseOptionEqSomeGet verifiedFrontendNumber_core_program_present_kernel
theorem verifiedFrontendNumber_surface_decoded_kernel :
    decodeReconstructedSurface verifiedFrontendNumberArtifact = some verifiedFrontendNumberDecodedSurfaceKernel :=
  calc
    decodeReconstructedSurface verifiedFrontendNumberArtifact =
        decodeReconstructedSurfaceView verifiedFrontendNumberArtifact verifiedFrontendNumberSurfaceKernel.view :=
      (decodeReconstructedSurfaceView_eq verifiedFrontendNumberArtifact verifiedFrontendNumberSurfaceKernel.view).symm
    _ = some verifiedFrontendNumberSurfaceKernel.surface := verifiedFrontendNumberSurfaceKernel.surfaceFound
    _ = some verifiedFrontendNumberDecodedSurfaceKernel := congrArg some verifiedFrontendNumber_checked_surface_value_kernel
def verifiedFrontendNumberProgramUnitKernel : ArtifactPackContextChecker.ProgramUnit := {
  artifact := verifiedFrontendNumberArtifact
  moduleId := 6
  modulePath := verifiedFrontendNumberModulePathKernel
  surface := verifiedFrontendNumberDecodedSurfaceKernel
  surfaceDecoded := verifiedFrontendNumber_surface_decoded_kernel
  moduleDeclared := verifiedFrontendNumber_module_path_found_kernel
  core := verifiedFrontendNumberCoreProgramKernel
  coreDecoded := verifiedFrontendNumber_core_program_found_kernel
}
end Lanius.Extraction
