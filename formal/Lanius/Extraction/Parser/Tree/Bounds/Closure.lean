import Lanius.Extraction.Parser.Tree.Bounds.Cost

namespace Lanius.Extraction.ParserTreeBounds
open Lanius.Compiler.Parser

abbrev Potential := Nat → StateKey → Cost

/-- An upper bound for every derivation supported by this closed chart.
Only scans and completions accumulate resources: seeded/predicted prefixes
have no children. No backpointer choice or observed parse tree is trusted. -/
structure BoundedChart (grammar : IndexedGrammar) (tokens : List Nat)
    (workspace : LogicalWorkspace) (budget : Potential) : Prop where
  closed : ChartClosed grammar tokens workspace
  scan : ∀ (production : Fin grammar.productionCount) (dot origin position kind finish : Nat),
    workspace.containsKey position ⟨production, dot, origin⟩ →
    (grammar.productionAt production).rhs[dot]? = some kind →
    kind < grammar.grammar.n_kinds → scanTerminal grammar tokens position kind = some finish →
    (budget position ⟨production, dot, origin⟩).join Cost.terminal ≤
      budget finish ⟨production, dot + 1, origin⟩
  complete : ∀ (parent child : Fin grammar.productionCount) (dot origin middle finish : Nat),
    workspace.containsKey middle ⟨parent, dot, origin⟩ →
    (grammar.productionAt parent).rhs[dot]? = some (grammar.grammar.n_kinds + (grammar.productionAt child).lhs) →
    workspace.containsKey finish ⟨child, (grammar.productionAt child).rhs.length, middle⟩ →
    (budget middle ⟨parent, dot, origin⟩).join
      (budget finish ⟨child, (grammar.productionAt child).rhs.length, middle⟩).node ≤
      budget finish ⟨parent, dot + 1, origin⟩

namespace BoundedChart

private theorem advance_cons {grammar : IndexedGrammar} {workspace : LogicalWorkspace} {budget : Potential}
    {tree : Lanius.Compiler.Parser.ParseTree} {trees : List Lanius.Compiler.Parser.ParseTree}
    {start middle finish symbol : Nat} {symbols : List Nat}
    (head : ∀ (production : Fin grammar.productionCount) dot origin,
      workspace.containsKey start ⟨production, dot, origin⟩ →
      (grammar.productionAt production).rhs[dot]? = some symbol →
      workspace.containsKey middle ⟨production, dot + 1, origin⟩ ∧
      (budget start ⟨production, dot, origin⟩).join (treeCost tree) ≤ budget middle ⟨production, dot + 1, origin⟩)
    (tail : ∀ (production : Fin grammar.productionCount) dot origin rest,
      workspace.containsKey middle ⟨production, dot, origin⟩ →
      (grammar.productionAt production).rhs.drop dot = symbols ++ rest →
      workspace.containsKey finish ⟨production, dot + symbols.length, origin⟩ ∧
      (budget middle ⟨production, dot, origin⟩).join (forestCost trees) ≤
        budget finish ⟨production, dot + symbols.length, origin⟩)
    (production : Fin grammar.productionCount) (dot origin : Nat) (rest : List Nat)
    (waiting : workspace.containsKey start ⟨production, dot, origin⟩)
    (expected : (grammar.productionAt production).rhs.drop dot = (symbol :: symbols) ++ rest) :
    workspace.containsKey finish ⟨production, dot + (symbol :: symbols).length, origin⟩ ∧
    (budget start ⟨production, dot, origin⟩).join (forestCost (tree :: trees)) ≤
      budget finish ⟨production, dot + (symbol :: symbols).length, origin⟩ := by
  have first : (grammar.productionAt production).rhs[dot]? = some symbol := by
    have found := congrArg (fun values : List Nat => values[0]?) expected
    simpa only [List.getElem?_drop, Nat.add_zero, List.cons_append, List.getElem?_cons_zero] using found
  obtain ⟨next, headCost⟩ := head production dot origin waiting first
  have remaining : (grammar.productionAt production).rhs.drop (dot + 1) = symbols ++ rest := by
    have tailEq := congrArg List.tail expected
    simpa only [List.tail_drop, List.cons_append, List.tail_cons] using tailEq
  obtain ⟨done, tailCost⟩ := tail production (dot + 1) origin rest next remaining
  have combined := Cost.trans (Cost.join_mono headCost (Cost.refl (forestCost trees))) tailCost
  simpa only [forestCost, Cost.join_assoc, List.length_cons, Nat.add_assoc, Nat.add_comm 1] using
    And.intro done combined

/-- Consuming any recognized tree advances the same chart item and charges
its full storage/depth cost, even when the grammar admits multiple trees. -/
theorem advance_symbol (bounded : BoundedChart grammar tokens workspace budget)
    (recognized : ParseTreeRecognizesSymbol grammar tokens tree symbol start finish) :
    ∀ (production : Fin grammar.productionCount) dot origin,
      workspace.containsKey start ⟨production, dot, origin⟩ →
      (grammar.productionAt production).rhs[dot]? = some symbol →
      workspace.containsKey finish ⟨production, dot + 1, origin⟩ ∧
      (budget start ⟨production, dot, origin⟩).join (treeCost tree) ≤
        budget finish ⟨production, dot + 1, origin⟩ := by
  induction recognized using ParseTreeRecognizesSymbol.rec
      (motive_2 := fun trees symbols start finish _ =>
        ∀ (production : Fin grammar.productionCount) dot origin rest,
          workspace.containsKey start ⟨production, dot, origin⟩ →
          (grammar.productionAt production).rhs.drop dot = symbols ++ rest →
          workspace.containsKey finish ⟨production, dot + symbols.length, origin⟩ ∧
          (budget start ⟨production, dot, origin⟩).join (forestCost trees) ≤
            budget finish ⟨production, dot + symbols.length, origin⟩) with
  | terminal tokenIndex kindBound scanned =>
    intro production dot origin waiting expected
    exact ⟨bounded.closed.scan production dot origin _ _ _ waiting expected kindBound scanned,
      bounded.scan production dot origin _ _ _ waiting expected kindBound scanned⟩
  | nonterminal nonterminalBound productionBound lhs children ih =>
    intro production dot origin waiting expected
    let child : Fin grammar.productionCount := ⟨_, productionBound⟩
    have expectedChild : (grammar.productionAt production).rhs[dot]? =
        some (grammar.grammar.n_kinds + (grammar.productionAt child).lhs) := by
      simpa only [child, lhs] using expected
    have seeded := bounded.closed.predict production child dot origin _ waiting expectedChild
    obtain ⟨completed, childCost⟩ := ih child 0 _ [] seeded (by simp only [child, List.drop_zero, List.append_nil])
    simp only [Nat.zero_add] at childCost
    have forestBound := Cost.trans (Cost.right_le_join _ _) childCost
    refine ⟨bounded.closed.complete production child dot origin _ _ waiting expectedChild (by simpa using completed), ?_⟩
    exact Cost.trans (Cost.join_mono (Cost.refl _) (Cost.node_mono forestBound))
      (bounded.complete production child dot origin _ _ waiting expectedChild (by simpa using completed))
  | empty =>
    rename_i position production dot origin rest waiting expected
    simpa only [forestCost, Cost.join_zero, List.length_nil, Nat.add_zero] using And.intro waiting (Cost.refl _)
  | cons head tail headIH tailIH => exact advance_cons headIH tailIH _ _ _ _ ‹_› ‹_›

theorem advance_sequence (bounded : BoundedChart grammar tokens workspace budget)
    (recognized : ParseTreesRecognizeSequence grammar tokens trees symbols start finish) :
    ∀ (production : Fin grammar.productionCount) dot origin rest,
      workspace.containsKey start ⟨production, dot, origin⟩ →
      (grammar.productionAt production).rhs.drop dot = symbols ++ rest →
      workspace.containsKey finish ⟨production, dot + symbols.length, origin⟩ ∧
      (budget start ⟨production, dot, origin⟩).join (forestCost trees) ≤
        budget finish ⟨production, dot + symbols.length, origin⟩ := by
  induction trees generalizing symbols start with
  | nil =>
    cases recognized
    intro production dot origin rest waiting expected
    simpa only [forestCost, Cost.join_zero, List.length_nil, Nat.add_zero] using And.intro waiting (Cost.refl _)
  | cons tree trees ih =>
    cases recognized with
    | cons head tail => exact advance_cons (bounded.advance_symbol head) (ih tail)

/-- Bound the tree selected by the source parser using only its declarative
recognition proof and the input's bounded chart, not its emitted certificate. -/
theorem root (bounded : BoundedChart grammar tokens workspace budget)
    (parse : MaterializedParse grammar tokens) :
    ∃ production : Fin grammar.productionCount,
      (grammar.productionAt production).lhs = grammar.grammar.start_nonterminal ∧
      treeCost parse.tree ≤ (budget (finalPosition tokens.length)
        ⟨production, (grammar.productionAt production).rhs.length, 0⟩).node := by
  obtain ⟨tree, recognized⟩ := parse
  dsimp only
  generalize identity : grammar.grammar.n_kinds + grammar.grammar.start_nonterminal = symbol at recognized
  cases recognized with
  | terminal tokenIndex kindBound scanned => omega
  | nonterminal nonterminalBound productionBound lhs children =>
    let production : Fin grammar.productionCount := ⟨_, productionBound⟩
    have start : (grammar.productionAt production).lhs = grammar.grammar.start_nonterminal := by
      dsimp only [production]
      omega
    have seeded := bounded.closed.seed production start
    obtain ⟨_, finished⟩ := bounded.advance_sequence children production 0 0 [] seeded
      (by simp only [production, List.drop_zero, List.append_nil])
    simp only [Nat.zero_add] at finished
    refine ⟨production, start, ?_⟩
    exact Cost.node_mono (Cost.trans (Cost.right_le_join _ _) finished)

end BoundedChart
end Lanius.Extraction.ParserTreeBounds
