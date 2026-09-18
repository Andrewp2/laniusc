import Lanius.Extraction.Parser.Tree.Bounds.Closure
import Lanius.Compiler.Parser.Envelope.Check
import Std.Data.TreeMap.Lemmas

namespace Lanius.Extraction.ParserTreeBounds
open Lanius.Compiler.Parser
attribute [local instance] lexOrd

abbrev Costs := Std.TreeMap Envelope.Item Cost
abbrev Summaries := Std.TreeMap (Nat × Nat) (Std.TreeMap Nat Cost)

def potential (costs : Costs) (position : Nat) (key : StateKey) : Cost :=
  costs.getD (Envelope.item position key) Cost.zero

def summaryAt (summaries : Summaries) (origin nonterminal : Nat) : Std.TreeMap Nat Cost :=
  summaries.getD (origin, nonterminal) ∅

def Cost.maximum (left right : Cost) : Cost :=
  ⟨max left.nodes right.nodes, max left.words right.words, max left.depth right.depth⟩

/-- Group completed-tree bounds by span/nonterminal. This builder is not
trusted: every completed item is checked against the resulting summary. -/
def buildSummaries (grammar : IndexedGrammar) (items : List Envelope.Item) (costs : Costs) : Summaries := Id.run do
  let productions := grammar.grammar.productions.toArray
  let mut summaries : Summaries := ∅
  for entry in items do
    if let some production := productions[entry.2.1]? then
      if entry.2.2.1 == production.rhs.length then
        let row := summaryAt summaries entry.2.2.2 production.lhs
        let cost := (costs.getD entry Cost.zero).node
        summaries := summaries.insert (entry.2.2.2, production.lhs)
          (row.insert entry.1 (cost.maximum (row.getD entry.1 Cost.zero)))
  return summaries

private def checkItem (grammar : Lanius.Extraction.Grammar)
    (productions : Array Lanius.Extraction.Production) (tokens canonical : Array Nat)
    (costs : Costs) (summaries : Summaries) (entry : Envelope.Item) : Bool :=
  match productions[entry.2.1]? with
  | none => false
  | some production =>
    let here := costs.getD entry Cost.zero
    (if entry.2.2.1 = production.rhs.length then
      match (summaryAt summaries entry.2.2.2 production.lhs)[entry.1]? with
      | none => false
      | some upper => decide (here.node ≤ upper)
     else true) &&
    match production.rhs[entry.2.2.1]? with
    | none => true
    | some symbol =>
      if symbol < grammar.n_kinds then
        match scanTerminalArray grammar.split_token_kind grammar.split_component_kind tokens canonical entry.1 symbol with
        | none => true
        | some finish => decide (here.join Cost.terminal ≤ costs.getD (finish, entry.2.1, entry.2.2.1 + 1, entry.2.2.2) Cost.zero)
      else
        (summaryAt summaries entry.1 (symbol - grammar.n_kinds)).toList.all fun (finish, upper) =>
          decide (here.join upper ≤ costs.getD (finish, entry.2.1, entry.2.2.1 + 1, entry.2.2.2) Cost.zero)

def checkWithSummaries (grammar : IndexedGrammar) (tokens : List Nat) (items : List Envelope.Item)
    (costs : Costs) (summaries : Summaries) : Bool :=
  let productions := grammar.grammar.productions.toArray
  let tokens := tokens.toArray
  let canonical := grammar.grammar.canonical_kinds.toArray
  items.all (checkItem grammar.grammar productions tokens canonical costs summaries)

def checkCosts (grammar : IndexedGrammar) (tokens : List Nat) (items : List Envelope.Item) (costs : Costs) : Bool :=
  checkWithSummaries grammar tokens items costs (buildSummaries grammar items costs)

theorem checkCosts_grammar_congr {left right : IndexedGrammar} (same : left.grammar = right.grammar) :
    checkCosts left tokens items costs = checkCosts right tokens items costs := by
  cases left
  cases right
  cases same
  rfl

private theorem checked_item (checked : checkWithSummaries grammar tokens items costs summaries = true)
    (present : (Envelope.workspace items).containsKey position key) :
    checkItem grammar.grammar grammar.grammar.productions.toArray tokens.toArray
      grammar.grammar.canonical_kinds.toArray costs summaries (Envelope.item position key) = true :=
  List.all_eq_true.mp checked _ (Envelope.contains_iff.mp present)

private theorem production_found {grammar : IndexedGrammar} (production : Fin grammar.productionCount) :
    grammar.grammar.productions.toArray[production.val]? = some (grammar.productionAt production) := by
  simp [IndexedGrammar.productionAt, IndexedGrammar.productionCount]

/-- Validate the summaries as well as the transition budgets. Even an
untrusted summary cannot omit an expensive alternative derivation. -/
theorem checkWithSummaries_bounded
    (closed : ChartClosed grammar tokens (Envelope.workspace items))
    (checked : checkWithSummaries grammar tokens items costs summaries = true) :
    BoundedChart grammar tokens (Envelope.workspace items) (potential costs) where
  closed := closed
  scan production dot origin position kind finish waiting expected terminal scanned := by
    have valid := checked_item checked waiting
    simp only [checkItem, Envelope.item, production_found, expected, terminal, ↓reduceIte,
      scanTerminalArray_eq, scanned] at valid
    exact of_decide_eq_true (Bool.and_eq_true_iff.mp valid).2
  complete parent child dot origin middle finish waiting expected completed := by
    have parentValid := checked_item checked waiting
    have nonterminal : ¬ grammar.grammar.n_kinds + (grammar.productionAt child).lhs < grammar.grammar.n_kinds := by omega
    simp only [checkItem, Envelope.item, production_found, expected, nonterminal, ↓reduceIte,
      Nat.add_sub_cancel_left] at parentValid
    have advances := (Bool.and_eq_true_iff.mp parentValid).2
    have childValid := checked_item checked completed
    simp only [checkItem, Envelope.item, production_found, ↓reduceIte] at childValid
    have coverage := (Bool.and_eq_true_iff.mp childValid).1
    cases found : (summaryAt summaries middle (grammar.productionAt child).lhs)[finish]? with
    | none => simp only [found, Bool.false_eq_true] at coverage
    | some upper =>
      rw [found] at coverage
      have childBound : (potential costs finish ⟨child, (grammar.productionAt child).rhs.length, middle⟩).node ≤ upper := by
        simpa only [potential, Envelope.item] using of_decide_eq_true coverage
      have advanced := of_decide_eq_true (List.all_eq_true.mp advances (finish, upper)
        (Std.TreeMap.mem_toList_iff_getElem?_eq_some.mpr found))
      exact Cost.trans (Cost.join_mono (Cost.refl _) childBound) advanced

theorem checkCosts_bounded (closed : ChartClosed grammar tokens (Envelope.workspace items))
    (checked : checkCosts grammar tokens items costs = true) :
    BoundedChart grammar tokens (Envelope.workspace items) (potential costs) :=
  checkWithSummaries_bounded closed checked

/-- Root budgets cover every complete start production, not just whichever
one the candidate proposer observed. -/
def checkRoots (grammar : IndexedGrammar) (tokens : List Nat) (costs : Costs)
    (recordWords nodeSlots depth : Nat) : Bool :=
  grammar.grammar.productions.zipIdx.all fun (production, id) =>
    if production.lhs = grammar.grammar.start_nonterminal then
      let bound := (potential costs (finalPosition tokens.length) ⟨id, production.rhs.length, 0⟩).node
      decide (bound.nodes ≤ nodeSlots ∧ bound.words ≤ recordWords + 3 ∧ bound.depth ≤ depth)
    else true

theorem checkRoots_grammar_congr {left right : IndexedGrammar} (same : left.grammar = right.grammar) :
    checkRoots left tokens costs recordWords nodeSlots depth =
      checkRoots right tokens costs recordWords nodeSlots depth := by
  cases left
  cases right
  cases same
  rfl

theorem checkRoots_fits (bounded : BoundedChart grammar tokens workspace (potential costs))
    (roots : checkRoots grammar tokens costs recordWords nodeSlots depth = true)
    (parse : MaterializedParse grammar tokens) : Fits parse.tree recordWords nodeSlots depth := by
  obtain ⟨production, start, treeBound⟩ := bounded.root parse
  have member : (grammar.productionAt production, production.val) ∈ grammar.grammar.productions.zipIdx := by
    simp [List.mem_zipIdx_iff_getElem?, IndexedGrammar.productionAt, IndexedGrammar.productionCount]
  have checked := List.all_eq_true.mp roots _ member
  simp only [start, ↓reduceIte] at checked
  have fits := of_decide_eq_true checked
  exact Fits.of_cost treeBound fits.1 fits.2.1 fits.2.2

end Lanius.Extraction.ParserTreeBounds
