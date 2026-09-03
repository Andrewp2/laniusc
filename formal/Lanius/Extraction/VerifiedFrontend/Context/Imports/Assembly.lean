import Lanius.Extraction.ArtifactPackContextPhaseChunks
import Lanius.Extraction.VerifiedFrontend.Context.Imports.Unit0
import Lanius.Extraction.VerifiedFrontend.Context.Imports.Unit1
import Lanius.Extraction.VerifiedFrontend.Context.Imports.Unit2
import Lanius.Extraction.VerifiedFrontend.Context.Imports.Unit3
import Lanius.Extraction.VerifiedFrontend.Context.Imports.Unit4
import Lanius.Extraction.VerifiedFrontend.Context.Imports.Unit5
import Lanius.Extraction.VerifiedFrontend.Context.Imports.Unit6
import Lanius.Extraction.VerifiedFrontend.Context.Imports.Unit7
import Lanius.Extraction.VerifiedFrontend.Context.Imports.Unit8

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
