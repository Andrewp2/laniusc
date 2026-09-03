import Lanius.Extraction.VerifiedFrontend.Surface.RawLexer.Assembly
import Lanius.Extraction.ArtifactPackContextChecker
import Lanius.Extraction.ParseChunks
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
theorem verifiedFrontendRawLexer_checked_surface_value_kernel :
    verifiedFrontendRawLexerSurfaceKernel.surface = verifiedFrontendRawLexerDecodedSurfaceKernel := by
  rfl
theorem verifiedFrontendRawLexer_module_path_present_kernel :
    (ArtifactPackContextChecker.declaredModulePath? verifiedFrontendRawLexerDecodedSurfaceKernel).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendRawLexerModulePathKernel :=
  (ArtifactPackContextChecker.declaredModulePath? verifiedFrontendRawLexerDecodedSurfaceKernel).get
    verifiedFrontendRawLexer_module_path_present_kernel
theorem verifiedFrontendRawLexer_module_path_found_kernel :
    ArtifactPackContextChecker.declaredModulePath? verifiedFrontendRawLexerDecodedSurfaceKernel =
      some verifiedFrontendRawLexerModulePathKernel :=
  parseOptionEqSomeGet verifiedFrontendRawLexer_module_path_present_kernel
theorem verifiedFrontendRawLexer_checked_module_path_found_kernel :
    ArtifactPackContextChecker.declaredModulePath? verifiedFrontendRawLexerSurfaceKernel.surface =
      some verifiedFrontendRawLexerModulePathKernel := by
  rw [verifiedFrontendRawLexer_checked_surface_value_kernel]
  exact verifiedFrontendRawLexer_module_path_found_kernel
theorem verifiedFrontendRawLexer_core_program_present_kernel :
    (verifiedFrontendRawLexerArtifact.core_program.map CoreDecode.program).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendRawLexerCoreProgramKernel :=
  (verifiedFrontendRawLexerArtifact.core_program.map CoreDecode.program).get
    verifiedFrontendRawLexer_core_program_present_kernel
theorem verifiedFrontendRawLexer_core_program_found_kernel :
    verifiedFrontendRawLexerArtifact.core_program.map CoreDecode.program =
      some verifiedFrontendRawLexerCoreProgramKernel :=
  parseOptionEqSomeGet verifiedFrontendRawLexer_core_program_present_kernel
theorem verifiedFrontendRawLexer_surface_decoded_kernel :
    decodeReconstructedSurface verifiedFrontendRawLexerArtifact = some verifiedFrontendRawLexerDecodedSurfaceKernel :=
  calc
    decodeReconstructedSurface verifiedFrontendRawLexerArtifact =
        decodeReconstructedSurfaceView verifiedFrontendRawLexerArtifact verifiedFrontendRawLexerSurfaceKernel.view :=
      (decodeReconstructedSurfaceView_eq verifiedFrontendRawLexerArtifact verifiedFrontendRawLexerSurfaceKernel.view).symm
    _ = some verifiedFrontendRawLexerSurfaceKernel.surface := verifiedFrontendRawLexerSurfaceKernel.surfaceFound
    _ = some verifiedFrontendRawLexerDecodedSurfaceKernel := congrArg some verifiedFrontendRawLexer_checked_surface_value_kernel
def verifiedFrontendRawLexerProgramUnitKernel : ArtifactPackContextChecker.ProgramUnit := {
  artifact := verifiedFrontendRawLexerArtifact
  moduleId := 8
  modulePath := verifiedFrontendRawLexerModulePathKernel
  surface := verifiedFrontendRawLexerDecodedSurfaceKernel
  surfaceDecoded := verifiedFrontendRawLexer_surface_decoded_kernel
  moduleDeclared := verifiedFrontendRawLexer_module_path_found_kernel
  core := verifiedFrontendRawLexerCoreProgramKernel
  coreDecoded := verifiedFrontendRawLexer_core_program_found_kernel
}
end Lanius.Extraction
