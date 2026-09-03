import Lanius.Extraction.VerifiedFrontend.Surface.Decimal.Assembly
import Lanius.Extraction.ArtifactPackContextChecker
import Lanius.Extraction.ParseChunks
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
theorem verifiedFrontendDecimal_checked_surface_value_kernel :
    verifiedFrontendDecimalSurfaceKernel.surface = verifiedFrontendDecimalDecodedSurfaceKernel := by
  rfl
theorem verifiedFrontendDecimal_module_path_present_kernel :
    (ArtifactPackContextChecker.declaredModulePath? verifiedFrontendDecimalDecodedSurfaceKernel).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendDecimalModulePathKernel :=
  (ArtifactPackContextChecker.declaredModulePath? verifiedFrontendDecimalDecodedSurfaceKernel).get
    verifiedFrontendDecimal_module_path_present_kernel
theorem verifiedFrontendDecimal_module_path_found_kernel :
    ArtifactPackContextChecker.declaredModulePath? verifiedFrontendDecimalDecodedSurfaceKernel =
      some verifiedFrontendDecimalModulePathKernel :=
  parseOptionEqSomeGet verifiedFrontendDecimal_module_path_present_kernel
theorem verifiedFrontendDecimal_checked_module_path_found_kernel :
    ArtifactPackContextChecker.declaredModulePath? verifiedFrontendDecimalSurfaceKernel.surface =
      some verifiedFrontendDecimalModulePathKernel := by
  rw [verifiedFrontendDecimal_checked_surface_value_kernel]
  exact verifiedFrontendDecimal_module_path_found_kernel
theorem verifiedFrontendDecimal_core_program_present_kernel :
    (verifiedFrontendDecimalArtifact.core_program.map CoreDecode.program).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendDecimalCoreProgramKernel :=
  (verifiedFrontendDecimalArtifact.core_program.map CoreDecode.program).get
    verifiedFrontendDecimal_core_program_present_kernel
theorem verifiedFrontendDecimal_core_program_found_kernel :
    verifiedFrontendDecimalArtifact.core_program.map CoreDecode.program =
      some verifiedFrontendDecimalCoreProgramKernel :=
  parseOptionEqSomeGet verifiedFrontendDecimal_core_program_present_kernel
theorem verifiedFrontendDecimal_surface_decoded_kernel :
    decodeReconstructedSurface verifiedFrontendDecimalArtifact = some verifiedFrontendDecimalDecodedSurfaceKernel :=
  calc
    decodeReconstructedSurface verifiedFrontendDecimalArtifact =
        decodeReconstructedSurfaceView verifiedFrontendDecimalArtifact verifiedFrontendDecimalSurfaceKernel.view :=
      (decodeReconstructedSurfaceView_eq verifiedFrontendDecimalArtifact verifiedFrontendDecimalSurfaceKernel.view).symm
    _ = some verifiedFrontendDecimalSurfaceKernel.surface := verifiedFrontendDecimalSurfaceKernel.surfaceFound
    _ = some verifiedFrontendDecimalDecodedSurfaceKernel := congrArg some verifiedFrontendDecimal_checked_surface_value_kernel
def verifiedFrontendDecimalProgramUnitKernel : ArtifactPackContextChecker.ProgramUnit := {
  artifact := verifiedFrontendDecimalArtifact
  moduleId := 5
  modulePath := verifiedFrontendDecimalModulePathKernel
  surface := verifiedFrontendDecimalDecodedSurfaceKernel
  surfaceDecoded := verifiedFrontendDecimal_surface_decoded_kernel
  moduleDeclared := verifiedFrontendDecimal_module_path_found_kernel
  core := verifiedFrontendDecimalCoreProgramKernel
  coreDecoded := verifiedFrontendDecimal_core_program_found_kernel
}
end Lanius.Extraction
