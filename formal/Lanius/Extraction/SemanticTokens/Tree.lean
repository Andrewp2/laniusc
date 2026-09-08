import Lanius.Extraction.SemanticTokens.Model
import Lanius.Compiler.ParserRoot

namespace Lanius.Extraction.SemanticTokens

open Lanius.Compiler.Parser

mutual
  def treeLeaves : Lanius.Compiler.Parser.ParseTree → List (Nat × Nat)
    | .terminal token kind => [(token, kind)]
    | .nonterminal _ _ _ _ children => forestLeaves children

  def forestLeaves : List Lanius.Compiler.Parser.ParseTree → List (Nat × Nat)
    | [] => []
    | tree :: trees => treeLeaves tree ++ forestLeaves trees
end

def Use.leaf (use : Use) : Nat × Nat := (use.token, use.kind)

mutual
  /-- The selected derivation supplies all terminal positions and scans; these
  are not inferred from a separately accepted semantic-token certificate. -/
  theorem tree_scan (recognized : ParseTreeRecognizesSymbol grammar tokens tree symbol start finish) :
      ∃ uses, ScanPath grammar tokens uses start finish ∧ uses.map Use.leaf = treeLeaves tree := by
    cases recognized with
    | terminal tokenEq kindBound scanned =>
        exact ⟨[⟨start, finish, _, _⟩], .cons ⟨tokenEq, kindBound, scanned⟩ .nil, rfl⟩
    | nonterminal _ _ _ children => exact forest_scan children

  theorem forest_scan (recognized : ParseTreesRecognizeSequence grammar tokens trees symbols start finish) :
      ∃ uses, ScanPath grammar tokens uses start finish ∧ uses.map Use.leaf = forestLeaves trees := by
    cases recognized with
    | empty => exact ⟨[], .nil, rfl⟩
    | cons head tail =>
        obtain ⟨first, firstPath, firstLeaves⟩ := tree_scan head
        obtain ⟨rest, restPath, restLeaves⟩ := forest_scan tail
        exact ⟨first ++ rest, firstPath.append restPath, by simp only [List.map_append, firstLeaves, restLeaves, forestLeaves]⟩
end

theorem selected_tree_scan (parse : MaterializedParse grammar tokens) :
    ∃ uses, ScanPath grammar tokens uses 0 (finalPosition tokens.length) ∧
      uses.map Use.leaf = treeLeaves parse.tree ∧
      (uses.map Use.slot).Nodup ∧
      (∀ token, token < tokens.length → ∃ use ∈ uses, use.position = 2 * token) := by
  obtain ⟨uses, path, leaves⟩ := tree_scan parse.recognizes
  exact ⟨uses, path, leaves, path.slots_unique, fun _ bound => path.first_slot bound⟩

end Lanius.Extraction.SemanticTokens
