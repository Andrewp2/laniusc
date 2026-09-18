import Lanius.Extraction.CompactDecode.Unit
import Lanius.Extraction.CompactOutput.Unit.Arguments
import Lanius.Extraction.Parser.Tree.Bounds.Cost

namespace Lanius.Extraction.CompactOutput.Size
open Lanius.Compiler.Parser Lanius.Extraction.SemanticTokens Lanius.Extraction.ParserTreeLayout

/-- Wire records have four eight-digit fields and sixteen digits per child.
The in-memory layout instead uses four words and three words per child.
This exact conversion avoids rounding each record or trusting an emitted tree. -/
def treeBytes (recordWords nodes : Nat) : Nat := (16 * recordWords + 32 * nodes) / 3

def unitBytes (pathBytes sourceBytes rawTokens tokens recordWords nodes : Nat) : Nat :=
  40 + 2 * pathBytes + 2 * sourceBytes + 24 * rawTokens + 40 * tokens + treeBytes recordWords nodes

mutual
  theorem tree_encoding_size (tree : Lanius.Compiler.Parser.ParseTree) (nodeBase wordBase position : Nat) :
      3 * (Nodes.encodeAll (treeVisits grammar tokens nodeBase wordBase position tree).1).length =
        16 * treeWords tree + 32 * (treeFrom nodeBase wordBase tree).offsets.length := by
    cases tree with
    | terminal token kind => rfl
    | nonterminal production nonterminal start finish children =>
      have nested := forest_encoding_size (grammar := grammar) (tokens := tokens) children
        nodeBase (wordBase + 4 + children.length * 3) start
      simp only [treeVisits, Nodes.encodeAll, List.flatMap_append, List.flatMap_cons, List.flatMap_nil,
        List.append_nil, List.length_append, CompactDecode.record_encoding_length, forest_visits_length,
        treeWords, treeFrom, List.length_singleton]
      change 3 * ((Nodes.encodeAll (forestVisits grammar tokens nodeBase
        (wordBase + 4 + children.length * 3) start children).1).length + (32 + children.length * 16)) = _
      omega
  termination_by sizeOf tree

  theorem forest_encoding_size (trees : List Lanius.Compiler.Parser.ParseTree) (nodeBase wordBase position : Nat) :
      3 * (Nodes.encodeAll (forestVisits grammar tokens nodeBase wordBase position trees).1).length =
        16 * forestWords trees + 32 * (forestFrom nodeBase wordBase trees).offsets.length := by
    cases trees with
    | nil => rfl
    | cons tree trees =>
      have head := tree_encoding_size (grammar := grammar) (tokens := tokens) tree nodeBase wordBase position
      have tail := forest_encoding_size (grammar := grammar) (tokens := tokens) trees
        (nodeBase + (treeFrom nodeBase wordBase tree).offsets.length)
        (wordBase + (treeFrom nodeBase wordBase tree).words.length)
        (treeVisits grammar tokens nodeBase wordBase position tree).2.finish
      simp only [forestVisits, Nodes.encodeAll, List.flatMap_append, List.length_append, forestWords, forestFrom]
      change 3 * ((Nodes.encodeAll (treeVisits grammar tokens nodeBase wordBase position tree).1).length +
        (Nodes.encodeAll (forestVisits grammar tokens
          (nodeBase + (treeFrom nodeBase wordBase tree).offsets.length)
          (wordBase + (treeFrom nodeBase wordBase tree).words.length)
          (treeVisits grammar tokens nodeBase wordBase position tree).2.finish trees).1).length) = _
      omega
  termination_by sizeOf trees
end

theorem collection_encoding_size (collection : CollectionRecords grammar tokens tree nodeBase wordBase) :
    (Nodes.encodeAll collection.records).length =
      treeBytes (treeFrom nodeBase wordBase tree).words.length (treeFrom nodeBase wordBase tree).offsets.length := by
  have size := tree_encoding_size (grammar := grammar) (tokens := tokens.map Token.kind) tree nodeBase wordBase 0
  rw [← collection.recordsEq] at size
  rw [treeBytes, tree_words_length]
  omega

theorem treeBytes_mono (words : firstWords ≤ secondWords) (nodes : firstNodes ≤ secondNodes) :
    treeBytes firstWords firstNodes ≤ treeBytes secondWords secondNodes := by
  unfold treeBytes
  omega

theorem emission_encoding_size {emission : Unit.Emission}
    (result : FrontendResult emission.data emission.count emission.nodes emission.words extracted)
    (collection : CollectionRecords emission.data.grammar (artifactTokens emission.data.tokens) result.parse.tree 0 0) :
    (emission.encoding collection.assignments collection.records).length =
      unitBytes emission.path.length emission.data.request.source.length emission.data.raw.length
        emission.data.tokens.length emission.words emission.nodes := by
  simp only [Unit.Emission.encoding, List.length_append, hexDigits_length, Bytes.encoding_length,
    List.length_map, Tokens.encodeAll, CompactDecode.tokens_encoding_length,
    CompactDecode.assignments_encoding_length, collection.lengthEq, artifactTokens, List.length_map,
    collection_encoding_size, ← result.nodesEq, ← result.wordsEq, unitBytes]
  omega

end Lanius.Extraction.CompactOutput.Size
