import Lanius.Extraction.VerifiedFrontend.Surface.Lexer.Assembly
import Lanius.Extraction.ArtifactPackContextChecker
import Lanius.Extraction.ParseChunks
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
theorem verifiedFrontendLexer_checked_surface_value_kernel :
    verifiedFrontendLexerSurfaceKernel.surface = verifiedFrontendLexerSurfaceTraceKernel := by
  rfl
theorem verifiedFrontendLexer_module_path_present_kernel :
    (ArtifactPackContextChecker.declaredModulePath? verifiedFrontendLexerSurfaceTraceKernel).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendLexerModulePathKernel :=
  (ArtifactPackContextChecker.declaredModulePath? verifiedFrontendLexerSurfaceTraceKernel).get
    verifiedFrontendLexer_module_path_present_kernel
theorem verifiedFrontendLexer_module_path_found_kernel :
    ArtifactPackContextChecker.declaredModulePath? verifiedFrontendLexerSurfaceTraceKernel =
      some verifiedFrontendLexerModulePathKernel :=
  parseOptionEqSomeGet verifiedFrontendLexer_module_path_present_kernel
theorem verifiedFrontendLexer_checked_module_path_found_kernel :
    ArtifactPackContextChecker.declaredModulePath? verifiedFrontendLexerSurfaceKernel.surface =
      some verifiedFrontendLexerModulePathKernel := by
  rw [verifiedFrontendLexer_checked_surface_value_kernel]
  exact verifiedFrontendLexer_module_path_found_kernel
theorem verifiedFrontendLexer_core_program_present_kernel :
    (verifiedFrontendLexerArtifact.core_program.map CoreDecode.program).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendLexerCoreProgramKernel :=
  (verifiedFrontendLexerArtifact.core_program.map CoreDecode.program).get
    verifiedFrontendLexer_core_program_present_kernel
theorem verifiedFrontendLexer_core_program_found_kernel :
    verifiedFrontendLexerArtifact.core_program.map CoreDecode.program =
      some verifiedFrontendLexerCoreProgramKernel :=
  parseOptionEqSomeGet verifiedFrontendLexer_core_program_present_kernel
theorem verifiedFrontendLexer_surface_decoded_kernel :
    decodeReconstructedSurface verifiedFrontendLexerArtifact = some verifiedFrontendLexerSurfaceTraceKernel :=
  calc
    decodeReconstructedSurface verifiedFrontendLexerArtifact =
        decodeReconstructedSurfaceView verifiedFrontendLexerArtifact verifiedFrontendLexerSurfaceKernel.view :=
      (decodeReconstructedSurfaceView_eq verifiedFrontendLexerArtifact verifiedFrontendLexerSurfaceKernel.view).symm
    _ = some verifiedFrontendLexerSurfaceKernel.surface := verifiedFrontendLexerSurfaceKernel.surfaceFound
    _ = some verifiedFrontendLexerSurfaceTraceKernel := congrArg some verifiedFrontendLexer_checked_surface_value_kernel
def verifiedFrontendLexerProgramUnitKernel : ArtifactPackContextChecker.ProgramUnit := {
  artifact := verifiedFrontendLexerArtifact
  moduleId := 0
  modulePath := verifiedFrontendLexerModulePathKernel
  surface := verifiedFrontendLexerSurfaceTraceKernel
  surfaceDecoded := verifiedFrontendLexer_surface_decoded_kernel
  moduleDeclared := verifiedFrontendLexer_module_path_found_kernel
  core := verifiedFrontendLexerCoreProgramKernel
  coreDecoded := verifiedFrontendLexer_core_program_found_kernel
}
end Lanius.Extraction
