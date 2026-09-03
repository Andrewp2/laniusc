import Lanius.Extraction.VerifiedFrontend.Assembly.Units.Unit0
import Lanius.Extraction.VerifiedFrontend.Assembly.Units.Unit1
import Lanius.Extraction.VerifiedFrontend.Assembly.Units.Unit2
import Lanius.Extraction.VerifiedFrontend.Assembly.Units.Unit3
import Lanius.Extraction.VerifiedFrontend.Assembly.Units.Unit4
import Lanius.Extraction.VerifiedFrontend.Assembly.Units.Unit5
import Lanius.Extraction.VerifiedFrontend.Assembly.Units.Unit6
import Lanius.Extraction.VerifiedFrontend.Assembly.Units.Unit7
import Lanius.Extraction.VerifiedFrontend.Assembly.Units.Unit8
import Lanius.Extraction.VerifiedFrontend.Context.Certificate

namespace Lanius.Extraction

open ArtifactPackContextChecker

def verifiedFrontendPackUnitsMaterializedKernel :
    SurfaceElaborationChecker.Evidence
      (UnitsChecked verifiedFrontendPackContextMaterializedKernel
        verifiedFrontendPackDecodedKernel.units) :=
  ⟨.cons verifiedFrontendLexerUnitKernel.proof
    (.cons verifiedFrontendTokenScanUnitKernel.proof
      (.cons verifiedFrontendDigitsUnitKernel.proof
        (.cons verifiedFrontendTokenUnitKernel.proof
          (.cons verifiedFrontendCanonicalTokensUnitKernel.proof
            (.cons verifiedFrontendDecimalUnitKernel.proof
              (.cons verifiedFrontendNumberUnitKernel.proof
                (.cons verifiedFrontendSymbolUnitKernel.proof
                  (.cons verifiedFrontendRawLexerUnitKernel.proof .nil))))))))⟩

theorem verifiedFrontendPackUnitsMaterializedKernel_eq :
    checkUnits verifiedFrontendPackContextMaterializedKernel
        verifiedFrontendPackDecodedKernel.units =
      some verifiedFrontendPackUnitsMaterializedKernel := by
  change checkUnits verifiedFrontendPackContextMaterializedKernel
    [verifiedFrontendLexerProgramUnitKernel,
      verifiedFrontendTokenScanProgramUnitKernel,
      verifiedFrontendDigitsProgramUnitKernel,
      verifiedFrontendTokenProgramUnitKernel,
      verifiedFrontendCanonicalTokensProgramUnitKernel,
      verifiedFrontendDecimalProgramUnitKernel,
      verifiedFrontendNumberProgramUnitKernel,
      verifiedFrontendSymbolProgramUnitKernel,
      verifiedFrontendRawLexerProgramUnitKernel] =
        some verifiedFrontendPackUnitsMaterializedKernel
  apply checkUnits_cons_of verifiedFrontendLexerUnitKernel_eq
  apply checkUnits_cons_of verifiedFrontendTokenScanUnitKernel_eq
  apply checkUnits_cons_of verifiedFrontendDigitsUnitKernel_eq
  apply checkUnits_cons_of verifiedFrontendTokenUnitKernel_eq
  apply checkUnits_cons_of verifiedFrontendCanonicalTokensUnitKernel_eq
  apply checkUnits_cons_of verifiedFrontendDecimalUnitKernel_eq
  apply checkUnits_cons_of verifiedFrontendNumberUnitKernel_eq
  apply checkUnits_cons_of verifiedFrontendSymbolUnitKernel_eq
  apply checkUnits_cons_of verifiedFrontendRawLexerUnitKernel_eq
  rfl

theorem verifiedFrontendPack_units_checked_materialized_kernel :
    (checkUnits verifiedFrontendPackContextMaterializedKernel
      verifiedFrontendPackDecodedKernel.units).isSome = true := by
  rw [verifiedFrontendPackUnitsMaterializedKernel_eq]
  rfl

def verifiedFrontendPackUnitsKernel :
    SurfaceElaborationChecker.Evidence
      (UnitsChecked verifiedFrontendPackContextKernel
        verifiedFrontendPackDecodedKernel.units) :=
  verifiedFrontendPackUnitsMaterializedKernel

theorem verifiedFrontendPack_units_checked_kernel :
    (checkUnits verifiedFrontendPackContextKernel
      verifiedFrontendPackDecodedKernel.units).isSome = true := by
  change (checkUnits verifiedFrontendPackContextMaterializedKernel
    verifiedFrontendPackDecodedKernel.units).isSome = true
  exact verifiedFrontendPack_units_checked_materialized_kernel

theorem verifiedFrontendPackUnitsKernel_eq :
    checkUnits verifiedFrontendPackContextKernel
        verifiedFrontendPackDecodedKernel.units =
      some verifiedFrontendPackUnitsKernel := by
  change checkUnits verifiedFrontendPackContextMaterializedKernel
      verifiedFrontendPackDecodedKernel.units =
    some verifiedFrontendPackUnitsMaterializedKernel
  exact verifiedFrontendPackUnitsMaterializedKernel_eq

end Lanius.Extraction
