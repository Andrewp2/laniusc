import Lanius.Extraction.VerifiedFrontend.Context.Base
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
theorem verifiedFrontendNumber_context_imports_kernel :
    ArtifactPackContextChecker.collectUnitImports verifiedFrontendPackDecodedUnitsKernel
      verifiedFrontendNumberProgramUnitKernel verifiedFrontendNumberProgramUnitKernel.surface.items =
        some [⟨6, 2⟩, ⟨6, 5⟩, ⟨6, 1⟩] := by
  with_unfolding_all rfl
end Lanius.Extraction
