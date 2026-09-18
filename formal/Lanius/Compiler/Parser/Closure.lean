import Lanius.Compiler.ParserModel

namespace Lanius.Compiler.Parser

/-! The language-to-chart direction of parser correctness. These are closure
conditions on the existing logical workspace, not a second parsing algorithm.
The source-loop proof must establish them on normal completion; they are not
assumptions that an extractor caller may substitute for valid input.

Completion includes zero-width children. The source implements that case with
both its completion loop and its replay of earlier nullable completions.
Scanning uses the existing physical-token lattice, including odd positions.
-/

/-- The four obligations a fully processed, sufficiently large chart must
satisfy. State identities and backpointers are deliberately absent: duplicate
suppression may retain any sound derivation of the same key. -/
structure ChartClosed (grammar : IndexedGrammar) (tokens : List Nat)
    (workspace : LogicalWorkspace) : Prop where
  seed : ∀ production : Fin grammar.productionCount,
    (grammar.productionAt production).lhs = grammar.grammar.start_nonterminal →
    workspace.containsKey 0 ⟨production, 0, 0⟩
  predict : ∀ (parent child : Fin grammar.productionCount) (dot origin position : Nat),
    workspace.containsKey position ⟨parent, dot, origin⟩ →
    (grammar.productionAt parent).rhs[dot]? =
      some (grammar.grammar.n_kinds + (grammar.productionAt child).lhs) →
    workspace.containsKey position ⟨child, 0, position⟩
  scan : ∀ (production : Fin grammar.productionCount) (dot origin position kind finish : Nat),
    workspace.containsKey position ⟨production, dot, origin⟩ →
    (grammar.productionAt production).rhs[dot]? = some kind →
    kind < grammar.grammar.n_kinds →
    scanTerminal grammar tokens position kind = some finish →
    workspace.containsKey finish ⟨production, dot + 1, origin⟩
  complete : ∀ (parent child : Fin grammar.productionCount) (dot origin middle finish : Nat),
    workspace.containsKey middle ⟨parent, dot, origin⟩ →
    (grammar.productionAt parent).rhs[dot]? =
      some (grammar.grammar.n_kinds + (grammar.productionAt child).lhs) →
    workspace.containsKey finish ⟨child, (grammar.productionAt child).rhs.length, middle⟩ →
    workspace.containsKey finish ⟨parent, dot + 1, origin⟩

namespace ChartClosed

private theorem advance_cons {grammar : IndexedGrammar} {workspace : LogicalWorkspace}
    {start middle finish symbol : Nat} {symbols : List Nat}
    (head : ∀ (production : Fin grammar.productionCount) dot origin,
      workspace.containsKey start ⟨production, dot, origin⟩ →
      (grammar.productionAt production).rhs[dot]? = some symbol →
      workspace.containsKey middle ⟨production, dot + 1, origin⟩)
    (tail : ∀ (production : Fin grammar.productionCount) dot origin rest,
      workspace.containsKey middle ⟨production, dot, origin⟩ →
      (grammar.productionAt production).rhs.drop dot = symbols ++ rest →
      workspace.containsKey finish ⟨production, dot + symbols.length, origin⟩)
    (production : Fin grammar.productionCount) (dot origin : Nat) (rest : List Nat)
    (waiting : workspace.containsKey start ⟨production, dot, origin⟩)
    (expected : (grammar.productionAt production).rhs.drop dot = (symbol :: symbols) ++ rest) :
    workspace.containsKey finish ⟨production, dot + (symbol :: symbols).length, origin⟩ := by
  have headFound : (grammar.productionAt production).rhs[dot]? = some symbol := by
    have first := congrArg (fun values : List Nat => values[0]?) expected
    simpa only [List.getElem?_drop, Nat.add_zero, List.cons_append, List.getElem?_cons_zero] using first
  have next := head production dot origin waiting headFound
  have remaining : (grammar.productionAt production).rhs.drop (dot + 1) = symbols ++ rest := by
    have tailEq := congrArg List.tail expected
    simpa only [List.tail_drop, List.cons_append, List.tail_cons] using tailEq
  have done := tail production (dot + 1) origin rest next remaining
  simpa only [List.length_cons, Nat.add_assoc, Nat.add_comm 1] using done

/-- Any declaratively recognized symbol advances a waiting chart item.
Recursive and nullable nonterminals use their finite grammar derivation,
not an assumption that the recognizer accepted them. -/
theorem advance_symbol (recognized : RecognizesSymbol grammar tokens symbol start finish)
    (closed : ChartClosed grammar tokens workspace) :
    ∀ (production : Fin grammar.productionCount) (dot origin : Nat),
      workspace.containsKey start ⟨production, dot, origin⟩ →
      (grammar.productionAt production).rhs[dot]? = some symbol →
      workspace.containsKey finish ⟨production, dot + 1, origin⟩ := by
  induction recognized using RecognizesSymbol.rec
      (motive_2 := fun symbols start finish _ =>
        ∀ (production : Fin grammar.productionCount) dot origin rest,
          workspace.containsKey start ⟨production, dot, origin⟩ →
          (grammar.productionAt production).rhs.drop dot = symbols ++ rest →
          workspace.containsKey finish ⟨production, dot + symbols.length, origin⟩) with
  | terminal kindBound scanned =>
      intro production dot origin waiting expected
      exact closed.scan production dot origin _ _ _ waiting expected kindBound scanned
  | nonterminal nonterminalBound productionBound lhs body ih =>
      intro production dot origin waiting expected
      let child : Fin grammar.productionCount := ⟨_, productionBound⟩
      have expectedChild : (grammar.productionAt production).rhs[dot]? =
          some (grammar.grammar.n_kinds + (grammar.productionAt child).lhs) := by
        simpa only [child, lhs] using expected
      have seeded := closed.predict production child dot origin _ waiting expectedChild
      have completed := ih child 0 _ [] seeded (by simp only [child, List.drop_zero, List.append_nil])
      exact closed.complete production child dot origin _ _ waiting expectedChild (by simpa using completed)
  | empty =>
      rename_i position production dot origin rest waiting expected
      simpa using waiting
  | cons head tail headIH tailIH =>
      exact advance_cons headIH tailIH _ _ _ _ ‹_› ‹_›

/-- Recognizing a sequence advances exactly its length along a production.
The unconsumed suffix stays arbitrary, so this applies inside any rule. -/
theorem advance_sequence (recognized : RecognizesSequence grammar tokens symbols start finish)
    (closed : ChartClosed grammar tokens workspace) :
    ∀ (production : Fin grammar.productionCount) dot origin rest,
      workspace.containsKey start ⟨production, dot, origin⟩ →
      (grammar.productionAt production).rhs.drop dot = symbols ++ rest →
      workspace.containsKey finish ⟨production, dot + symbols.length, origin⟩ := by
  induction symbols generalizing start with
  | nil =>
      cases recognized
      intro production dot origin rest waiting _
      simpa using waiting
  | cons headSymbol tailSymbols ih =>
      cases recognized with
      | cons head tail => exact advance_cons (advance_symbol head closed) (ih tail)

/-- A root is an actual key in the final chart, not merely an unrelated
derivation of the same input. -/
def HasRoot (grammar : IndexedGrammar) (tokens : List Nat) (workspace : LogicalWorkspace) : Prop :=
  ∃ production : Fin grammar.productionCount,
    (grammar.productionAt production).lhs = grammar.grammar.start_nonterminal ∧
    workspace.containsKey (finalPosition tokens.length)
      ⟨production, (grammar.productionAt production).rhs.length, 0⟩

/-- The missing converse of state soundness: closure turns any valid input
into a complete start item. Establishing closure for the actual source loops
and proving its root search finds the item are separate runtime obligations. -/
theorem contains_root (closed : ChartClosed grammar tokens workspace)
    (recognized : RecognizesInput grammar tokens) : HasRoot grammar tokens workspace := by
  unfold RecognizesInput at recognized
  generalize identity : grammar.grammar.n_kinds + grammar.grammar.start_nonterminal = symbol at recognized
  cases recognized with
  | terminal bound _ => omega
  | nonterminal nonterminalBound productionBound lhs body =>
      let production : Fin grammar.productionCount := ⟨_, productionBound⟩
      have startLhs : (grammar.productionAt production).lhs = grammar.grammar.start_nonterminal := by
        dsimp only [production]
        omega
      have seeded := closed.seed production startLhs
      have completed := advance_sequence body closed production 0 0 [] seeded
        (by simp only [production, List.drop_zero, List.append_nil])
      exact ⟨production, startLhs, by simpa using completed⟩

end ChartClosed
end Lanius.Compiler.Parser
