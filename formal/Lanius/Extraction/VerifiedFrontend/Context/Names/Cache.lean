import Lanius.Extraction.VerifiedFrontend.Context.Names.Modules
import Lanius.Extraction.VerifiedFrontend.Context.Names.Symbols

namespace Lanius.Extraction

/-- Opaque boundary for the module-name certificate cached in elaboration contexts.
This prevents computational proofs from reopening the proof-producing checker. -/
theorem verifiedFrontendPackContextModuleNamesUniqueKernel :
    Lanius.Names.ModulesHaveUniquePaths verifiedFrontendPackContextNamesKernel :=
  verifiedFrontendPackContextModuleNamesEvidenceKernel.proof

/-- Opaque boundary for the symbol-name certificate cached in elaboration contexts.
This prevents computational proofs from reopening the proof-producing checker. -/
theorem verifiedFrontendPackContextSymbolNamesUniqueKernel :
    Lanius.Names.SymbolsAreUnique verifiedFrontendPackContextNamesKernel :=
  verifiedFrontendPackContextSymbolNamesEvidenceKernel.proof

end Lanius.Extraction
