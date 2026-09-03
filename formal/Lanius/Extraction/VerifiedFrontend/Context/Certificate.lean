import Lanius.Extraction.VerifiedFrontend.Context.Supported.Assembly
import Lanius.Extraction.VerifiedFrontend.Context.Functions.Assembly
import Lanius.Extraction.VerifiedFrontend.Context.Materialized.FinalCertificate

namespace Lanius.Extraction

set_option maxRecDepth 100000

open ArtifactPackContextChecker SurfaceElaborationChecker

theorem verifiedFrontendPack_context_found_kernel :
    ArtifactPackContextChecker.buildPackContext?
        verifiedFrontendPackDecodedKernel.units =
      some verifiedFrontendPackContextExplicitKernel := by
  change ArtifactPackContextChecker.buildPackContext?
    verifiedFrontendPackDecodedUnitsKernel =
      some verifiedFrontendPackContextExplicitKernel
  unfold ArtifactPackContextChecker.buildPackContext?
  rw [verifiedFrontendPack_context_supported_kernel]
  simp only [↓reduceIte]
  rw [verifiedFrontendPack_context_target_found_kernel]
  have allocationsNamed :
      allocateUnits verifiedFrontendPackDecodedUnitsKernel =
        verifiedFrontendPackAllocationsKernel := rfl
  rw [allocationsNamed]
  rw [verifiedFrontendPack_context_headers_found_kernel]
  rw [verifiedFrontendPack_context_imports_found_kernel]
  simp only [Option.bind_eq_bind, Option.bind_some]
  let namesExplicit : Lanius.Names.Environment := {
        modules := verifiedFrontendPackDecodedUnitsKernel.map (fun unit => unit.module)
        symbols := verifiedFrontendPackContextHeadersKernel.symbols
        imports := verifiedFrontendPackContextImportsKernel
      }
  have moduleNamesPresentExplicit :
      (modulesUniquePaths? namesExplicit).isSome = true := by
    simpa only [namesExplicit, verifiedFrontendPackContextNamesKernel] using
      verifiedFrontendPack_context_module_names_present_kernel
  let moduleNamesEvidenceExplicit :=
    (modulesUniquePaths? namesExplicit).get moduleNamesPresentExplicit
  have moduleNamesFoundExplicit :
      modulesUniquePaths? namesExplicit = some moduleNamesEvidenceExplicit :=
    parseOptionEqSomeGet moduleNamesPresentExplicit
  have symbolNamesPresentExplicit :
      (symbolsUnique? namesExplicit).isSome = true := by
    simpa only [namesExplicit, verifiedFrontendPackContextNamesKernel] using
      verifiedFrontendPack_context_symbol_names_present_kernel
  let symbolNamesEvidenceExplicit :=
    (symbolsUnique? namesExplicit).get symbolNamesPresentExplicit
  have symbolNamesFoundExplicit :
      symbolsUnique? namesExplicit = some symbolNamesEvidenceExplicit :=
    parseOptionEqSomeGet symbolNamesPresentExplicit
  change ((modulesUniquePaths? namesExplicit).bind fun modulePathsUnique =>
    (symbolsUnique? namesExplicit).bind fun symbolsUnique =>
      finishCertifiedPackContext verifiedFrontendPackContextTargetKernel
        namesExplicit verifiedFrontendPackContextHeadersKernel
        verifiedFrontendPackAllocationsKernel modulePathsUnique
        symbolsUnique) = some verifiedFrontendPackContextExplicitKernel
  rw [moduleNamesFoundExplicit, symbolNamesFoundExplicit]
  simp only [Option.bind_eq_bind, Option.bind_some]
  exact verifiedFrontendPack_finish_certified_context_found_kernel
    moduleNamesEvidenceExplicit symbolNamesEvidenceExplicit

theorem verifiedFrontendPack_context_checked_kernel :
    (ArtifactPackContextChecker.buildPackContext?
      verifiedFrontendPackDecodedKernel.units).isSome = true := by
  rw [verifiedFrontendPack_context_found_kernel]
  rfl

def verifiedFrontendPackContextKernel := verifiedFrontendPackContextMaterializedKernel

theorem verifiedFrontendPackContextKernel_eq :
    ArtifactPackContextChecker.buildPackContext?
        verifiedFrontendPackDecodedKernel.units =
      some verifiedFrontendPackContextKernel := by
  unfold verifiedFrontendPackContextKernel
  rw [verifiedFrontendPackContextMaterializedKernel_eq]
  exact verifiedFrontendPack_context_found_kernel

end Lanius.Extraction
