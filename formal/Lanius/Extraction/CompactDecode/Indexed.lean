import Lanius.Extraction.CompactDecode.Unit
import Lanius.Extraction.Parse.Grammar

namespace Lanius.Extraction.CompactDecode

/-- Decode node metadata using the already authenticated grammar index. The
wire reader and reference artifact are unchanged; even invalid production IDs
have exactly their reference result. -/
noncomputable def UnitData.indexedArtifact (data : UnitData) : Artifact :=
  { data.artifact with parse_nodes := data.nodes.map fun record =>
      ⟨record.production, ((Parse.productions.lookup record.production).map (·.lhs)).getD 0,
        record.start, record.finish, record.children.map decodedChild⟩ }

theorem UnitData.indexedArtifact_eq (data : UnitData) : data.indexedArtifact = data.artifact := by
  simp only [indexedArtifact, Parse.lookup_eq]
  rfl

end Lanius.Extraction.CompactDecode
