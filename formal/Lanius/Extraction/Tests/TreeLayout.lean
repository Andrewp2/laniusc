import Lanius.Extraction.Parser.Tree.Cursor

open Lanius.Compiler.Parser Lanius.Extraction.ParserTreeLayout

-- Terminals retain semantic kinds, but allocate neither records nor node IDs.
example : (treeFrom 5 7 (.terminal 2 23)).words = [] ∧
    (treeFrom 5 7 (.terminal 2 23)).offsets = [] ∧
    (treeFrom 5 7 (.terminal 2 23)).roots = .token 2 23 := by decide

-- Nullable productions still need one header, one node, and one call frame.
example : (treeFrom 5 7 (.nonterminal 3 8 0 0 [])).words = [3, 0, 0, 0] ∧
    (treeFrom 5 7 (.nonterminal 3 8 0 0 [])).offsets = [7] ∧
    treeDepth (.nonterminal 3 8 0 0 []) = 1 := by decide

-- Two occurrences of the same child expand separately. The intervening token
-- neither allocates a node nor advances the word cursor. Parent storage is first,
-- but its node ID is last; these are deliberately different orders.
private def repeated : Lanius.Compiler.Parser.ParseTree :=
  .nonterminal 9 10 0 1
    [.nonterminal 3 8 0 0 [], .terminal 0 23, .nonterminal 3 8 0 0 []]

example : (treeFrom 5 7 repeated).offsets = [20, 24, 7] ∧
    (treeFrom 5 7 repeated).roots = .state 7 ∧
    (treeFrom 5 7 repeated).words =
      [9, 0, 1, 3, 2, 5, -1, 1, 0, 23, 2, 6, -1, 3, 0, 0, 0, 3, 0, 0, 0] ∧
    treeWords repeated = 21 ∧ treeDepth repeated = 2 := by decide

#print axioms tree_references
#print axioms tree_words_length
#print axioms tree_node_lookup
#print axioms tree_depth_le_nodes

private def parent : EarleyState := {
  production := 9, dot := 3, origin := 0, position := 1, previous := none, child := .none }
private def done : Layout (List Child) :=
  forestFrom 5 20 [.nonterminal 3 8 0 0 [], .terminal 0 23]
private def nested : Layout Child := treeFrom 6 24 (.nonterminal 3 8 0 0 [])

-- Rewriting a later repeated occurrence changes only its payload, not an
-- already completed sibling or its stored descendant record.
example : partialWords parent done [.state 42] =
    [9, 0, 1, 3, 2, 5, -1, 1, 0, 23, 2, 42, -1, 3, 0, 0, 0] := by decide
example : (partialWords parent done [.state 42] ++ nested.words).set 11 6 =
    (treeFrom 5 7 repeated).words := by decide

-- The payload rewrite must frame unrelated caller storage on both sides.
example : ([991, 992] ++ partialWords parent done [.state 42] ++ nested.words ++ [993, 994]).set 13 6 =
    [991, 992] ++ (treeFrom 5 7 repeated).words ++ [993, 994] := by decide

#print axioms forest_snoc
#print axioms forest_prefix_lengths
#print axioms partialWords_initial
#print axioms partialWords_complete
#print axioms partialWords_state
#print axioms partialWords_head
#print axioms appended_root
