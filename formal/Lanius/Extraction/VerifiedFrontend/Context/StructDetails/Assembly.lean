import Lanius.Extraction.VerifiedFrontend.Context.StructDetails.Unit0
import Lanius.Extraction.VerifiedFrontend.Context.StructDetails.Unit1
import Lanius.Extraction.VerifiedFrontend.Context.StructDetails.Unit2
import Lanius.Extraction.VerifiedFrontend.Context.StructDetails.Unit3
import Lanius.Extraction.VerifiedFrontend.Context.StructDetails.Unit4
import Lanius.Extraction.VerifiedFrontend.Context.StructDetails.Unit5
import Lanius.Extraction.VerifiedFrontend.Context.StructDetails.Unit6
import Lanius.Extraction.VerifiedFrontend.Context.StructDetails.Unit7
import Lanius.Extraction.VerifiedFrontend.Context.StructDetails.Unit8

namespace Lanius.Extraction
set_option maxRecDepth 100000
open ArtifactPackContextChecker
def verifiedFrontendPackContextStructDetailsKernel :
    ArtifactContextChecker.StructDetails :=
  appendStructDetails verifiedFrontendLexerContextStructDetailsKernel
    (appendStructDetails verifiedFrontendTokenScanContextStructDetailsKernel
      (appendStructDetails verifiedFrontendDigitsContextStructDetailsKernel
        (appendStructDetails verifiedFrontendTokenContextStructDetailsKernel
          (appendStructDetails verifiedFrontendCanonicalTokensContextStructDetailsKernel
            (appendStructDetails verifiedFrontendDecimalContextStructDetailsKernel
              (appendStructDetails verifiedFrontendNumberContextStructDetailsKernel
                (appendStructDetails verifiedFrontendSymbolContextStructDetailsKernel
                  (appendStructDetails verifiedFrontendRawLexerContextStructDetailsKernel ⟨[], []⟩))))))))
theorem verifiedFrontendPack_context_struct_details_found_kernel :
    buildPackStructDetails verifiedFrontendPackTypeContextKernel
      verifiedFrontendPackAllocationsKernel =
        some verifiedFrontendPackContextStructDetailsKernel := by
  rw [verifiedFrontendPack_allocations_explicit_kernel]
  unfold verifiedFrontendPackAllocationsExplicitKernel
  apply buildPackStructDetails_cons_of _ _ _ _ _
    verifiedFrontendLexer_context_struct_details_found_kernel
  apply buildPackStructDetails_cons_of _ _ _ _ _
    verifiedFrontendTokenScan_context_struct_details_found_kernel
  apply buildPackStructDetails_cons_of _ _ _ _ _
    verifiedFrontendDigits_context_struct_details_found_kernel
  apply buildPackStructDetails_cons_of _ _ _ _ _
    verifiedFrontendToken_context_struct_details_found_kernel
  apply buildPackStructDetails_cons_of _ _ _ _ _
    verifiedFrontendCanonicalTokens_context_struct_details_found_kernel
  apply buildPackStructDetails_cons_of _ _ _ _ _
    verifiedFrontendDecimal_context_struct_details_found_kernel
  apply buildPackStructDetails_cons_of _ _ _ _ _
    verifiedFrontendNumber_context_struct_details_found_kernel
  apply buildPackStructDetails_cons_of _ _ _ _ _
    verifiedFrontendSymbol_context_struct_details_found_kernel
  apply buildPackStructDetails_cons_of _ _ _ _ _
    verifiedFrontendRawLexer_context_struct_details_found_kernel
  simp only [buildPackStructDetails, verifiedFrontendPackContextStructDetailsKernel]
def verifiedFrontendPackDeclarationContextKernel : Lanius.SurfaceElaboration.Context := {
  verifiedFrontendPackTypeContextKernel with
  fields := verifiedFrontendPackContextStructDetailsKernel.fields
  structConstructors := verifiedFrontendPackContextStructDetailsKernel.constructors
}
end Lanius.Extraction
