import Lanius.Extraction.VerifiedFrontend.Surface.Digits.Assembly
import Lanius.Extraction.ArtifactPackContextChecker
import Lanius.Extraction.ParseChunks
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
theorem verifiedFrontendDigits_checked_surface_value_kernel :
    verifiedFrontendDigitsSurfaceKernel.surface = verifiedFrontendDigitsDecodedSurfaceKernel := by
  rfl
theorem verifiedFrontendDigits_module_path_present_kernel :
    (ArtifactPackContextChecker.declaredModulePath? verifiedFrontendDigitsDecodedSurfaceKernel).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendDigitsModulePathKernel :=
  (ArtifactPackContextChecker.declaredModulePath? verifiedFrontendDigitsDecodedSurfaceKernel).get
    verifiedFrontendDigits_module_path_present_kernel
theorem verifiedFrontendDigits_module_path_found_kernel :
    ArtifactPackContextChecker.declaredModulePath? verifiedFrontendDigitsDecodedSurfaceKernel =
      some verifiedFrontendDigitsModulePathKernel :=
  parseOptionEqSomeGet verifiedFrontendDigits_module_path_present_kernel
theorem verifiedFrontendDigits_checked_module_path_found_kernel :
    ArtifactPackContextChecker.declaredModulePath? verifiedFrontendDigitsSurfaceKernel.surface =
      some verifiedFrontendDigitsModulePathKernel := by
  rw [verifiedFrontendDigits_checked_surface_value_kernel]
  exact verifiedFrontendDigits_module_path_found_kernel
theorem verifiedFrontendDigits_core_program_present_kernel :
    (verifiedFrontendDigitsArtifact.core_program.map CoreDecode.program).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendDigitsCoreProgramKernel :=
  (verifiedFrontendDigitsArtifact.core_program.map CoreDecode.program).get
    verifiedFrontendDigits_core_program_present_kernel
theorem verifiedFrontendDigits_core_program_found_kernel :
    verifiedFrontendDigitsArtifact.core_program.map CoreDecode.program =
      some verifiedFrontendDigitsCoreProgramKernel :=
  parseOptionEqSomeGet verifiedFrontendDigits_core_program_present_kernel
theorem verifiedFrontendDigits_surface_decoded_kernel :
    decodeReconstructedSurface verifiedFrontendDigitsArtifact = some verifiedFrontendDigitsDecodedSurfaceKernel :=
  calc
    decodeReconstructedSurface verifiedFrontendDigitsArtifact =
        decodeReconstructedSurfaceView verifiedFrontendDigitsArtifact verifiedFrontendDigitsSurfaceKernel.view :=
      (decodeReconstructedSurfaceView_eq verifiedFrontendDigitsArtifact verifiedFrontendDigitsSurfaceKernel.view).symm
    _ = some verifiedFrontendDigitsSurfaceKernel.surface := verifiedFrontendDigitsSurfaceKernel.surfaceFound
    _ = some verifiedFrontendDigitsDecodedSurfaceKernel := congrArg some verifiedFrontendDigits_checked_surface_value_kernel
def verifiedFrontendDigitsProgramUnitKernel : ArtifactPackContextChecker.ProgramUnit := {
  artifact := verifiedFrontendDigitsArtifact
  moduleId := 2
  modulePath := verifiedFrontendDigitsModulePathKernel
  surface := verifiedFrontendDigitsDecodedSurfaceKernel
  surfaceDecoded := verifiedFrontendDigits_surface_decoded_kernel
  moduleDeclared := verifiedFrontendDigits_module_path_found_kernel
  core := verifiedFrontendDigitsCoreProgramKernel
  coreDecoded := verifiedFrontendDigits_core_program_found_kernel
}
end Lanius.Extraction
