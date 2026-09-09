import Lanius.Extraction.CompactDecode.Contracts

namespace Lanius.Extraction.CompactDecode

open Lanius.Compiler.Parser SemanticTokens CompactOutput

/-- Every collected node names an existing decoder production when the
parser and decoder share the same grammar. No per-record lookup is assumed. -/
theorem collection_productions
    (parse : MaterializedParse grammar (tokens.map Token.kind))
    (collection : CollectionRecords grammar tokens parse.tree 0 0)
    (sameGrammar : grammar.grammar = laniusGrammar) :
    ∀ record ∈ collection.records, ∃ production,
      laniusGrammar.production? record.production = some production := by
  intro record member
  have bound := tree_visits_productions parse.recognizes 0 0 record (collection.recordsEq ▸ member)
  have index : record.production < laniusGrammar.productions.length := by
    simpa only [IndexedGrammar.productionCount, sameGrammar] using bound
  exact ⟨laniusGrammar.productions[record.production], List.getElem?_eq_getElem index⟩

theorem storage_decode_same_grammar (storage : Unit.Storage emission result collection before)
    (wellFormed : Lanius.Properties.StateWellFormed before) (path : String)
    (pathBytes : path.toUTF8.toList.map UInt8.toNat = emission.path.map Fin.val)
    (sameGrammar : emission.data.grammar.grammar = laniusGrammar)
    (position : Nat) (positionEq : emission.position = position)
    (room : position + (emission.encoding collection.assignments collection.records).length ≤ emission.capacity)
    (backing : bytes.toList.map (fun b => Int.ofNat b.toNat) =
      (appendAll emission.capacity (emission.encoding collection.assignments collection.records)
        emission.position emission.original).contents.take
        (position + (emission.encoding collection.assignments collection.records).length)) :
    readArtifact.run {bytes, offset := position} =
      some ((emissionUnit emission path collection.assignments collection.records).artifact,
        {bytes, offset := position + (emission.encoding collection.assignments collection.records).length}) := by
  exact storage_decode_output storage wellFormed path pathBytes
    (collection_productions result.parse collection sameGrammar) position positionEq room backing

end Lanius.Extraction.CompactDecode
