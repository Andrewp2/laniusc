import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceSymbol
import Lanius.Extraction.ArtifactPackContextChecker
import Lanius.Extraction.ParseChunks
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
theorem verifiedFrontendSymbol_checked_surface_value_kernel :
    verifiedFrontendSymbolSurfaceKernel.surface = verifiedFrontendSymbolDecodedSurfaceKernel := by
  rfl
theorem verifiedFrontendSymbol_module_path_present_kernel :
    (ArtifactPackContextChecker.declaredModulePath? verifiedFrontendSymbolDecodedSurfaceKernel).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendSymbolModulePathKernel :=
  (ArtifactPackContextChecker.declaredModulePath? verifiedFrontendSymbolDecodedSurfaceKernel).get
    verifiedFrontendSymbol_module_path_present_kernel
theorem verifiedFrontendSymbol_module_path_found_kernel :
    ArtifactPackContextChecker.declaredModulePath? verifiedFrontendSymbolDecodedSurfaceKernel =
      some verifiedFrontendSymbolModulePathKernel :=
  parseOptionEqSomeGet verifiedFrontendSymbol_module_path_present_kernel
theorem verifiedFrontendSymbol_checked_module_path_found_kernel :
    ArtifactPackContextChecker.declaredModulePath? verifiedFrontendSymbolSurfaceKernel.surface =
      some verifiedFrontendSymbolModulePathKernel := by
  rw [verifiedFrontendSymbol_checked_surface_value_kernel]
  exact verifiedFrontendSymbol_module_path_found_kernel
theorem verifiedFrontendSymbol_core_program_present_kernel :
    (verifiedFrontendSymbolArtifact.core_program.map CoreDecode.program).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendSymbolCoreProgramKernel :=
  (verifiedFrontendSymbolArtifact.core_program.map CoreDecode.program).get
    verifiedFrontendSymbol_core_program_present_kernel
theorem verifiedFrontendSymbol_core_program_found_kernel :
    verifiedFrontendSymbolArtifact.core_program.map CoreDecode.program =
      some verifiedFrontendSymbolCoreProgramKernel :=
  parseOptionEqSomeGet verifiedFrontendSymbol_core_program_present_kernel
theorem verifiedFrontendSymbol_surface_decoded_kernel :
    decodeReconstructedSurface verifiedFrontendSymbolArtifact = some verifiedFrontendSymbolDecodedSurfaceKernel :=
  calc
    decodeReconstructedSurface verifiedFrontendSymbolArtifact =
        decodeReconstructedSurfaceView verifiedFrontendSymbolArtifact verifiedFrontendSymbolSurfaceKernel.view :=
      (decodeReconstructedSurfaceView_eq verifiedFrontendSymbolArtifact verifiedFrontendSymbolSurfaceKernel.view).symm
    _ = some verifiedFrontendSymbolSurfaceKernel.surface := verifiedFrontendSymbolSurfaceKernel.surfaceFound
    _ = some verifiedFrontendSymbolDecodedSurfaceKernel := congrArg some verifiedFrontendSymbol_checked_surface_value_kernel
def verifiedFrontendSymbolProgramUnitKernel : ArtifactPackContextChecker.ProgramUnit := {
  artifact := verifiedFrontendSymbolArtifact
  moduleId := 7
  modulePath := verifiedFrontendSymbolModulePathKernel
  surface := verifiedFrontendSymbolDecodedSurfaceKernel
  surfaceDecoded := verifiedFrontendSymbol_surface_decoded_kernel
  moduleDeclared := verifiedFrontendSymbol_module_path_found_kernel
  core := verifiedFrontendSymbolCoreProgramKernel
  coreDecoded := verifiedFrontendSymbol_core_program_found_kernel
}
end Lanius.Extraction
