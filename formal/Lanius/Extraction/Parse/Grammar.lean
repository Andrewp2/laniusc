import Lanius.Extraction.ArtifactCacheQuote
import Lanius.Extraction.GeneratedGrammar
import Lanius.Extraction.KernelReduction

namespace Lanius.Extraction.Parse

/-- Shared grammar data, authenticated once rather than searched linearly at
every node in every concrete program. This uses the existing sequence cache. -/
noncomputable def productions : Lanius.Data.SeqTree Production :=
  seq_tree% laniusGrammar.productions, 8

theorem productions_represent : productions.flatten = laniusGrammar.productions := by
  kernel_rfl

theorem productions_balanced : productions.WellFormed 8 :=
  Lanius.Data.SeqTree.wellFormed_sound (by decide +kernel)

/-- Includes out-of-range indices: the accelerated lookup cannot invent a rule. -/
theorem lookup_eq : productions.lookup = laniusGrammar.production? := by
  funext id
  rw [Lanius.Data.SeqTree.lookup_eq_flatten productions productions_balanced,
    productions_represent]
  rfl

end Lanius.Extraction.Parse
