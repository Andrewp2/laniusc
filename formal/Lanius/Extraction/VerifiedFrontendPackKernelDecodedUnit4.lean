import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceCanonicalTokens
import Lanius.Extraction.ArtifactPackContextChecker
import Lanius.Extraction.ParseChunks
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
theorem verifiedFrontendCanonicalTokens_checked_surface_value_kernel :
    verifiedFrontendCanonicalTokensSurfaceKernel.surface = verifiedFrontendCanonicalTokensDecodedSurfaceKernel := by
  rfl
theorem verifiedFrontendCanonicalTokens_module_path_present_kernel :
    (ArtifactPackContextChecker.declaredModulePath? verifiedFrontendCanonicalTokensDecodedSurfaceKernel).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendCanonicalTokensModulePathKernel :=
  (ArtifactPackContextChecker.declaredModulePath? verifiedFrontendCanonicalTokensDecodedSurfaceKernel).get
    verifiedFrontendCanonicalTokens_module_path_present_kernel
theorem verifiedFrontendCanonicalTokens_module_path_found_kernel :
    ArtifactPackContextChecker.declaredModulePath? verifiedFrontendCanonicalTokensDecodedSurfaceKernel =
      some verifiedFrontendCanonicalTokensModulePathKernel :=
  parseOptionEqSomeGet verifiedFrontendCanonicalTokens_module_path_present_kernel
theorem verifiedFrontendCanonicalTokens_checked_module_path_found_kernel :
    ArtifactPackContextChecker.declaredModulePath? verifiedFrontendCanonicalTokensSurfaceKernel.surface =
      some verifiedFrontendCanonicalTokensModulePathKernel := by
  rw [verifiedFrontendCanonicalTokens_checked_surface_value_kernel]
  exact verifiedFrontendCanonicalTokens_module_path_found_kernel
theorem verifiedFrontendCanonicalTokens_core_program_present_kernel :
    (verifiedFrontendCanonicalTokensArtifact.core_program.map CoreDecode.program).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendCanonicalTokensCoreProgramKernel :=
  (verifiedFrontendCanonicalTokensArtifact.core_program.map CoreDecode.program).get
    verifiedFrontendCanonicalTokens_core_program_present_kernel
theorem verifiedFrontendCanonicalTokens_core_program_found_kernel :
    verifiedFrontendCanonicalTokensArtifact.core_program.map CoreDecode.program =
      some verifiedFrontendCanonicalTokensCoreProgramKernel :=
  parseOptionEqSomeGet verifiedFrontendCanonicalTokens_core_program_present_kernel
theorem verifiedFrontendCanonicalTokens_surface_decoded_kernel :
    decodeReconstructedSurface verifiedFrontendCanonicalTokensArtifact = some verifiedFrontendCanonicalTokensDecodedSurfaceKernel :=
  calc
    decodeReconstructedSurface verifiedFrontendCanonicalTokensArtifact =
        decodeReconstructedSurfaceView verifiedFrontendCanonicalTokensArtifact verifiedFrontendCanonicalTokensSurfaceKernel.view :=
      (decodeReconstructedSurfaceView_eq verifiedFrontendCanonicalTokensArtifact verifiedFrontendCanonicalTokensSurfaceKernel.view).symm
    _ = some verifiedFrontendCanonicalTokensSurfaceKernel.surface := verifiedFrontendCanonicalTokensSurfaceKernel.surfaceFound
    _ = some verifiedFrontendCanonicalTokensDecodedSurfaceKernel := congrArg some verifiedFrontendCanonicalTokens_checked_surface_value_kernel
def verifiedFrontendCanonicalTokensProgramUnitKernel : ArtifactPackContextChecker.ProgramUnit := {
  artifact := verifiedFrontendCanonicalTokensArtifact
  moduleId := 4
  modulePath := verifiedFrontendCanonicalTokensModulePathKernel
  surface := verifiedFrontendCanonicalTokensDecodedSurfaceKernel
  surfaceDecoded := verifiedFrontendCanonicalTokens_surface_decoded_kernel
  moduleDeclared := verifiedFrontendCanonicalTokens_module_path_found_kernel
  core := verifiedFrontendCanonicalTokensCoreProgramKernel
  coreDecoded := verifiedFrontendCanonicalTokens_core_program_found_kernel
}
end Lanius.Extraction
