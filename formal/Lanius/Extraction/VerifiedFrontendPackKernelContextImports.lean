import Lanius.Extraction.ArtifactPackContextPhaseChunks
import Lanius.Extraction.VerifiedFrontendPackKernelContextImportsUnit0
import Lanius.Extraction.VerifiedFrontendPackKernelContextImportsUnit1
import Lanius.Extraction.VerifiedFrontendPackKernelContextImportsUnit2
import Lanius.Extraction.VerifiedFrontendPackKernelContextImportsUnit3
import Lanius.Extraction.VerifiedFrontendPackKernelContextImportsUnit4
import Lanius.Extraction.VerifiedFrontendPackKernelContextImportsUnit5
import Lanius.Extraction.VerifiedFrontendPackKernelContextImportsUnit6
import Lanius.Extraction.VerifiedFrontendPackKernelContextImportsUnit7
import Lanius.Extraction.VerifiedFrontendPackKernelContextImportsUnit8

namespace Lanius.Extraction

open ArtifactPackContextChecker

def verifiedFrontendPackContextImportsKernel : List Names.Import := [
  ⟨4, 3⟩,
  ⟨5, 3⟩, ⟨5, 2⟩, ⟨5, 1⟩,
  ⟨6, 2⟩, ⟨6, 5⟩, ⟨6, 1⟩,
  ⟨7, 3⟩,
  ⟨8, 0⟩, ⟨8, 6⟩, ⟨8, 7⟩, ⟨8, 3⟩, ⟨8, 1⟩
]

theorem verifiedFrontendPack_context_imports_found_kernel :
    collectPackImports verifiedFrontendPackDecodedUnitsKernel
      verifiedFrontendPackDecodedUnitsKernel =
        some verifiedFrontendPackContextImportsKernel := by
  unfold verifiedFrontendPackDecodedUnitsKernel verifiedFrontendPackDecodedKernel
    verifiedFrontendPackDecodedExplicitKernel
  apply collectPackImports_cons_of _ _ _ [] _
    verifiedFrontendLexer_context_imports_kernel
  apply collectPackImports_cons_of _ _ _ [] _
    verifiedFrontendTokenScan_context_imports_kernel
  apply collectPackImports_cons_of _ _ _ [] _
    verifiedFrontendDigits_context_imports_kernel
  apply collectPackImports_cons_of _ _ _ [] _
    verifiedFrontendToken_context_imports_kernel
  apply collectPackImports_cons_of _ _ _ [⟨4, 3⟩] _
    verifiedFrontendCanonicalTokens_context_imports_kernel
  apply collectPackImports_cons_of _ _ _ [⟨5, 3⟩, ⟨5, 2⟩, ⟨5, 1⟩] _
    verifiedFrontendDecimal_context_imports_kernel
  apply collectPackImports_cons_of _ _ _ [⟨6, 2⟩, ⟨6, 5⟩, ⟨6, 1⟩] _
    verifiedFrontendNumber_context_imports_kernel
  apply collectPackImports_cons_of _ _ _ [⟨7, 3⟩] _
    verifiedFrontendSymbol_context_imports_kernel
  apply collectPackImports_cons_of _ _ _ [⟨8, 0⟩, ⟨8, 6⟩, ⟨8, 7⟩,
    ⟨8, 3⟩, ⟨8, 1⟩] _ verifiedFrontendRawLexer_context_imports_kernel
  simp only [collectPackImports, verifiedFrontendPackContextImportsKernel]

theorem verifiedFrontendPack_context_imports_present_kernel :
    (collectPackImports verifiedFrontendPackDecodedUnitsKernel
      verifiedFrontendPackDecodedUnitsKernel).isSome = true := by
  rw [verifiedFrontendPack_context_imports_found_kernel]
  rfl

end Lanius.Extraction
