import Lanius.Extraction.Frontend.Storage.Artifact
import Lanius.Extraction.ArtifactPackChecker

namespace Lanius.Extraction.Frontend

def SourcesTokenStorage (sources : List SourceFile) (rawWords canonicalWords kindWords : Nat) : Prop :=
  ∀ file ∈ sources, SourceTokenStorage file rawWords canonicalWords kindWords

/-- Reuse the already accepted units. Only the numeric span/length bounds
are computed; the existing lexical proofs supply the source witnesses. -/
def checkUnitsTokenStorage? (rawWords canonicalWords kindWords : Nat) :
    {artifacts : List Artifact} → ArtifactPackChecker.CheckedUnitSurfaces artifacts →
      Option (PLift (SourcesTokenStorage (artifacts.flatMap (·.sources)) rawWords canonicalWords kindWords))
  | [], .nil => some ⟨by intro file member; cases member⟩
  | artifact :: _, .cons head tail => do
      let stored ← checkArtifactTokenStorage? artifact head.valid.1.1 rawWords canonicalWords kindWords
      let rest ← checkUnitsTokenStorage? rawWords canonicalWords kindWords tail
      pure ⟨by
        intro file member
        simp only [List.flatMap_cons, List.mem_append] at member
        rcases member with here | later
        · exact stored.down.source head.valid.1.1 here
        · exact rest.down file later⟩

end Lanius.Extraction.Frontend
