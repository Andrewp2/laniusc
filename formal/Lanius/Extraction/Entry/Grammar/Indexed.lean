import Lanius.Compiler.ParserGrammar
import Lanius.Extraction.GeneratedGrammar

namespace Lanius.Extraction.Entry.Grammar
open Lanius.Compiler.Parser

def indexedLanius : IndexedGrammar :=
  let base : IndexedGrammar := ⟨laniusGrammar, []⟩
  ⟨laniusGrammar, (List.range laniusGrammar.n_nonterminals).map base.productionIdsFor⟩

private theorem productionBounds : ∀ production ∈ laniusGrammar.productions,
    production.lhs < laniusGrammar.n_nonterminals ∧
      ∀ symbol ∈ production.rhs, symbol < laniusGrammar.n_kinds + laniusGrammar.n_nonterminals := by
  decide +kernel

set_option maxRecDepth 4096 in
/-- The exact grammar used by startup has a complete production index and
bounded symbols. Index completeness follows from its construction, not a
native check of all index rows. -/
theorem indexedLanius_wellFormed : indexedLanius.WellFormed := by
  refine ⟨by decide, by decide, by decide, by decide, by decide, by decide, ?_, ?_, ?_, ?_⟩
  · simp only [indexedLanius, List.length_map, List.length_range]
  · intro id production found
    exact (productionBounds production (List.mem_of_getElem? found)).1
  · intro id production symbol found member
    exact (productionBounds production (List.mem_of_getElem? found)).2 symbol member
  · intro nonterminal bound
    change nonterminal < laniusGrammar.n_nonterminals at bound
    change ((List.range laniusGrammar.n_nonterminals).map
      (IndexedGrammar.productionIdsFor ⟨laniusGrammar, []⟩))[nonterminal]? = _
    rw [List.getElem?_map, List.getElem?_range bound]
    rfl

end Lanius.Extraction.Entry.Grammar
