import Lanius.Extraction.VerifiedFrontend.Context.Materialized.Type.Certificate
import Lanius.Extraction.ArtifactPackContextPhaseChunks

namespace Lanius.Extraction

open ArtifactContextChecker

def verifiedFrontendPackMaterializedStructDetails
    (fieldOffset fieldCount constructorIndex : Nat) : StructDetails :=
  ⟨(verifiedFrontendPackContextTablesLiteralKernel.fields.drop fieldOffset).take
      fieldCount,
    (verifiedFrontendPackContextTablesLiteralKernel.structConstructors.drop
      constructorIndex).take 1⟩

end Lanius.Extraction
