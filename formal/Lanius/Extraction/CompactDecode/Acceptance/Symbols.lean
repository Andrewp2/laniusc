import Lanius.Extraction.CompactDecode.Acceptance.Origins

namespace Lanius.Extraction.CompactDecode

open Lanius.Compiler.Parser SemanticTokens ParserTreeLayout

/-- Grammar identity of a child reference in its containing record array. -/
def ChildSymbol (grammar : IndexedGrammar) (records : List RecordVisit)
    (nodeBase symbol : Nat) : ChildVisit → Prop
  | .token use => symbol = use.kind ∧ symbol < grammar.grammar.n_kinds
  | .node id _ _ => nodeBase ≤ id ∧ ∃ record production,
      records[id - nodeBase]? = some record ∧
      grammar.grammar.production? record.production = some production ∧
      symbol = grammar.grammar.n_kinds + production.lhs ∧
      production.lhs < grammar.grammar.n_nonterminals

theorem ChildSymbol.frame {before records : List RecordVisit}
    (typed : ChildSymbol grammar records (nodeBase + before.length) symbol child)
    (after : List RecordVisit) :
    ChildSymbol grammar (before ++ records ++ after) nodeBase symbol child := by
  cases child with
  | token use => exact typed
  | node id start finish =>
      obtain ⟨lower, record, production, found, lookup, symbolEq, bound⟩ := typed
      refine ⟨by omega, record, production, ?_, lookup, symbolEq, bound⟩
      have indexBound := (List.getElem?_eq_some_iff.mp found).1
      rw [List.getElem?_append_left (by simp only [List.length_append]; omega),
        List.getElem?_append_right (by omega)]
      simpa only [Nat.sub_sub] using found

theorem tree_reference_symbol
    (recognized : ParseTreeRecognizesSymbol grammar tokens tree symbol start finish)
    (nodeBase wordBase : Nat) :
    ChildSymbol grammar (treeVisits grammar tokens nodeBase wordBase start tree).1 nodeBase symbol
      (treeVisits grammar tokens nodeBase wordBase start tree).2 := by
  cases recognized with
  | terminal tokenEq kindBound scanned => exact ⟨rfl, kindBound⟩
  | nonterminal ntBound prodBound lhs recognized =>
      rename_i nonterminal production children
      have lengths := congrArg List.length (forest_visits_layout (grammar := grammar) (tokens := tokens)
        children nodeBase (wordBase + 4 + children.length * 3) start).1
      simp only [List.length_map] at lengths
      let root : RecordVisit := ⟨wordBase, production, start, finish,
        (forestVisits grammar tokens nodeBase (wordBase + 4 + children.length * 3) start children).2⟩
      refine ⟨by omega, root, grammar.productionAt ⟨production, prodBound⟩, ?_,
        List.getElem?_eq_getElem prodBound, ?_, ?_⟩
      · simp only [treeVisits, Nat.add_sub_cancel_left]
        rw [← lengths]
        simp [root]
      · simp only [lhs]
      · simpa only [lhs] using ntBound

inductive ChildSymbols (grammar : IndexedGrammar) (records : List RecordVisit) (nodeBase : Nat) :
    List Nat → List ChildVisit → Prop
  | nil : ChildSymbols grammar records nodeBase [] []
  | cons (head : ChildSymbol grammar records nodeBase symbol child)
      (tail : ChildSymbols grammar records nodeBase symbols children) :
      ChildSymbols grammar records nodeBase (symbol :: symbols) (child :: children)

theorem ChildSymbols.frame {before records : List RecordVisit}
    (typed : ChildSymbols grammar records (nodeBase + before.length) symbols children)
    (after : List RecordVisit) :
    ChildSymbols grammar (before ++ records ++ after) nodeBase symbols children := by
  induction typed with
  | nil => exact .nil
  | cons head tail ih => exact .cons (head.frame after) ih

theorem forest_reference_symbols
    (recognized : ParseTreesRecognizeSequence grammar tokens trees symbols start finish)
    (nodeBase wordBase : Nat) :
    ChildSymbols grammar (forestVisits grammar tokens nodeBase wordBase start trees).1 nodeBase
      symbols (forestVisits grammar tokens nodeBase wordBase start trees).2 := by
  induction trees generalizing symbols start finish nodeBase wordBase with
  | nil => cases recognized; exact .nil
  | cons tree trees ih =>
    cases recognized with
    | @cons _ symbol start middle _ symbols finish head tail =>
      let first := treeVisits grammar tokens nodeBase wordBase start tree
      let layout := treeFrom nodeBase wordBase tree
      let rest := forestVisits grammar tokens (nodeBase + layout.offsets.length)
        (wordBase + layout.words.length) first.2.finish trees
      obtain ⟨_, _, _, _, firstFinish, _, _, _⟩ := tree_visits_sound head nodeBase wordBase
      have lengthEq : first.1.length = layout.offsets.length := by
        have lengths := congrArg List.length (tree_visits_layout (grammar := grammar) (tokens := tokens)
          tree nodeBase wordBase start).1
        simpa only [List.length_map] using lengths
      have headSymbol := tree_reference_symbol head nodeBase wordBase
      have tailSymbols : ChildSymbols grammar rest.1 (nodeBase + first.1.length) symbols rest.2 := by
        dsimp only [rest]
        rw [firstFinish, lengthEq]
        exact ih tail (nodeBase + layout.offsets.length) (wordBase + layout.words.length)
      change ChildSymbols grammar (first.1 ++ rest.1) nodeBase
        (symbol :: symbols) (first.2 :: rest.2)
      constructor
      · simpa only [List.length_nil, Nat.add_zero, List.nil_append] using
          headSymbol.frame (before := []) rest.1
      · simpa only [List.append_nil] using tailSymbols.frame (before := first.1) []

end Lanius.Extraction.CompactDecode
