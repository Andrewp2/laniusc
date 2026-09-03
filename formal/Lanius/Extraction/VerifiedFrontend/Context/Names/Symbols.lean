import Lanius.Extraction.VerifiedFrontend.Context.Names.Assembly
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
theorem verifiedFrontendPack_context_symbol_names_present_kernel :
    (SurfaceElaborationChecker.symbolsUnique?
      verifiedFrontendPackContextNamesKernel).isSome = true := by
  with_unfolding_all rfl
def verifiedFrontendPackContextSymbolNamesEvidenceKernel :=
  (SurfaceElaborationChecker.symbolsUnique?
    verifiedFrontendPackContextNamesKernel).get
      verifiedFrontendPack_context_symbol_names_present_kernel
end Lanius.Extraction
