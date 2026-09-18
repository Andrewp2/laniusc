import Lanius.Extraction.Parser.Tree.Bounds.Propose
import Lean.Util.CollectAxioms

namespace Lanius.Extraction.Tests.Parser.TreeBounds
open Lanius.Compiler.Parser Lanius.Compiler.Parser.Envelope
open Lanius.Extraction.ParserTreeBounds
attribute [local instance] lexOrd

-- Both the nullable and token derivations must be bounded, regardless of
-- which one a proposer includes in its observed output tree.
private def grammar : IndexedGrammar := ⟨{
  n_kinds := 1, n_nonterminals := 2, start_nonterminal := 0,
  split_token_kind := 44, split_component_kind := 13, canonical_kinds := [7],
  productions := [⟨0, [2]⟩, ⟨1, [0]⟩, ⟨1, []⟩] }, []⟩
private def items : List Item :=
  [(0,0,0,0), (0,1,0,0), (0,2,0,0), (0,0,1,0), (2,1,1,0), (2,0,1,0)]
private def costs : Costs :=
  (∅ : Costs).insert (0,0,1,0) ⟨1,7,1⟩ |>.insert (2,1,1,0) ⟨0,3,0⟩ |>.insert (2,0,1,0) ⟨1,10,1⟩

example : checkCosts grammar [7] items costs = true := by decide
example : checkRoots grammar [7] costs 14 2 2 = true := by decide
example : checkRoots grammar [7] costs 13 2 2 = false := by decide
example : checkRoots grammar [7] costs 14 1 2 = false := by decide
example : checkRoots grammar [7] costs 14 2 1 = false := by decide
example : checkCosts grammar [7] items (costs.insert (2,0,1,0) ⟨0,10,1⟩) = false := by decide
example : checkCosts grammar [7] items (costs.insert (2,0,1,0) ⟨1,9,1⟩) = false := by decide
example : checkCosts grammar [7] items (costs.insert (2,0,1,0) ⟨1,10,0⟩) = false := by decide
example : checkCosts grammar [7] items (costs.erase (0,0,1,0)) = false := by decide
example : checkWithSummaries grammar [7] items costs ∅ = false := by decide
example : checkWithSummaries grammar [7] items costs
    ((buildSummaries grammar items costs).insert (0,1) ((∅ : Std.TreeMap Nat Cost).insert 2 ⟨1,10,1⟩)) = false := by decide

-- A cyclic nullable grammar admits arbitrarily deep finite trees. No finite
-- upper bound may be certified merely by choosing its shallow epsilon tree.
private def cyclic : IndexedGrammar := ⟨{
  n_kinds := 1, n_nonterminals := 1, start_nonterminal := 0,
  split_token_kind := 44, split_component_kind := 13, canonical_kinds := [7],
  productions := [⟨0, [1]⟩, ⟨0, []⟩] }, []⟩
private def cyclicItems : List Item := [(0,0,0,0), (0,1,0,0), (0,0,1,0)]
example : check cyclic [] cyclicItems = true := by decide
example : checkCosts cyclic [] cyclicItems
    ((∅ : Costs).insert (0,0,1,0) ⟨1000,1000,1000⟩) = false := by decide

private def splitGrammar : IndexedGrammar := ⟨{
  n_kinds := 1, n_nonterminals := 1, start_nonterminal := 0,
  split_token_kind := 44, split_component_kind := 13, canonical_kinds := [13],
  productions := [⟨0, [0,0]⟩] }, []⟩
private def splitItems : List Item := [(0,0,0,0), (1,0,1,0), (2,0,2,0)]

#eval (do
  for candidate in [items, items.reverse, items ++ items] do
    let .ok proposed := proposeCosts grammar [7] candidate
      | throw (IO.userError "acyclic envelope proposal failed")
    unless checkCosts grammar [7] candidate proposed && checkRoots grammar [7] proposed 14 2 2 do
      throw (IO.userError "proposed costs failed exact-fit checks")
  for bound in [:3] do
    let undersized := costs.insert (2,0,1,0) ⟨1,10,bound⟩
    unless checkCosts grammar [7] items undersized == (bound >= 1) do
      throw (IO.userError "depth boundary is not monotone")
  let .error .cyclicDependencies := proposeCosts cyclic [] cyclicItems
    | throw (IO.userError "cyclic nullable dependencies accepted")
  let .error .missingAdvance := proposeCosts grammar [7] (items.filter (· != (2,0,1,0)))
    | throw (IO.userError "missing required completion accepted")
  let .ok split := proposeCosts splitGrammar [44] splitItems
    | throw (IO.userError "split-token proposal failed")
  unless checkCosts splitGrammar [44] splitItems split && checkRoots splitGrammar [44] split 10 1 1 do
    throw (IO.userError "two split-token references did not fit exactly")
  unless !checkRoots splitGrammar [44] split 9 1 1 do
    throw (IO.userError "underallocated split-token storage accepted")
  IO.println "Tree budgets cover nullable alternatives, split tokens, exact resource edges, and reordered/duplicate candidates; forged summaries, missing transitions, and cycles are rejected." : IO Unit)

run_elab do
  for name in (← Lean.getEnv).allImportedModuleNames do
    if (`Lanius.Extraction.VerifiedFrontend).isPrefixOf name then
      throwError "General resource checking imports concrete frontend module {name}"
  let standard := #[``propext, ``Classical.choice, ``Quot.sound]
  for name in #[``treeCost_layout, ``forestCost_layout, ``Fits.of_cost,
      ``BoundedChart.advance_symbol, ``BoundedChart.advance_sequence, ``BoundedChart.root,
      ``checkWithSummaries_bounded, ``checkCosts_bounded, ``checkRoots_fits] do
    for assumption in ← Lean.collectAxioms name do
      unless standard.contains assumption do
        throwError "Tree resource theorem {name} adds unexpected axiom {assumption}"
  Lean.logInfo "Tree resource proofs use only standard Lean axioms."

end Lanius.Extraction.Tests.Parser.TreeBounds
