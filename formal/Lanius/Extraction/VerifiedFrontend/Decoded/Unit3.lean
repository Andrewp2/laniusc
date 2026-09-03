import Lanius.Extraction.VerifiedFrontend.Surface.Token.Assembly
import Lanius.Extraction.ArtifactPackContextChecker
import Lanius.Extraction.ParseChunks
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
theorem verifiedFrontendToken_checked_surface_value_kernel :
    verifiedFrontendTokenSurfaceKernel.surface = verifiedFrontendTokenDecodedSurfaceKernel := by
  rfl
theorem verifiedFrontendToken_module_path_present_kernel :
    (ArtifactPackContextChecker.declaredModulePath? verifiedFrontendTokenDecodedSurfaceKernel).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendTokenModulePathKernel :=
  (ArtifactPackContextChecker.declaredModulePath? verifiedFrontendTokenDecodedSurfaceKernel).get
    verifiedFrontendToken_module_path_present_kernel
theorem verifiedFrontendToken_module_path_found_kernel :
    ArtifactPackContextChecker.declaredModulePath? verifiedFrontendTokenDecodedSurfaceKernel =
      some verifiedFrontendTokenModulePathKernel :=
  parseOptionEqSomeGet verifiedFrontendToken_module_path_present_kernel
theorem verifiedFrontendToken_checked_module_path_found_kernel :
    ArtifactPackContextChecker.declaredModulePath? verifiedFrontendTokenSurfaceKernel.surface =
      some verifiedFrontendTokenModulePathKernel := by
  rw [verifiedFrontendToken_checked_surface_value_kernel]
  exact verifiedFrontendToken_module_path_found_kernel
theorem verifiedFrontendToken_core_program_present_kernel :
    (verifiedFrontendTokenArtifact.core_program.map CoreDecode.program).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendTokenCoreProgramKernel :=
  (verifiedFrontendTokenArtifact.core_program.map CoreDecode.program).get
    verifiedFrontendToken_core_program_present_kernel
theorem verifiedFrontendToken_core_program_found_kernel :
    verifiedFrontendTokenArtifact.core_program.map CoreDecode.program =
      some verifiedFrontendTokenCoreProgramKernel :=
  parseOptionEqSomeGet verifiedFrontendToken_core_program_present_kernel
theorem verifiedFrontendToken_surface_decoded_kernel :
    decodeReconstructedSurface verifiedFrontendTokenArtifact = some verifiedFrontendTokenDecodedSurfaceKernel :=
  calc
    decodeReconstructedSurface verifiedFrontendTokenArtifact =
        decodeReconstructedSurfaceView verifiedFrontendTokenArtifact verifiedFrontendTokenSurfaceKernel.view :=
      (decodeReconstructedSurfaceView_eq verifiedFrontendTokenArtifact verifiedFrontendTokenSurfaceKernel.view).symm
    _ = some verifiedFrontendTokenSurfaceKernel.surface := verifiedFrontendTokenSurfaceKernel.surfaceFound
    _ = some verifiedFrontendTokenDecodedSurfaceKernel := congrArg some verifiedFrontendToken_checked_surface_value_kernel
def verifiedFrontendTokenProgramUnitKernel : ArtifactPackContextChecker.ProgramUnit := {
  artifact := verifiedFrontendTokenArtifact
  moduleId := 3
  modulePath := verifiedFrontendTokenModulePathKernel
  surface := verifiedFrontendTokenDecodedSurfaceKernel
  surfaceDecoded := verifiedFrontendToken_surface_decoded_kernel
  moduleDeclared := verifiedFrontendToken_module_path_found_kernel
  core := verifiedFrontendTokenCoreProgramKernel
  coreDecoded := verifiedFrontendToken_core_program_found_kernel
}
end Lanius.Extraction
