import Lanius.Compiler.Parser.Envelope.Workspace
import Lanius.Compiler.Parser.Scan
import Std.Data.TreeSet.Lemmas
import Std.Data.TreeMap.Basic

namespace Lanius.Compiler.Parser.Envelope

attribute [local instance] lexOrd

/-- Lookup accelerators, not trusted claims. The checker validates coverage
of every production and completed item before using either index. -/
structure Index where
  predictions : Std.TreeMap Nat (Std.TreeSet Nat) := ∅
  completions : Std.TreeMap (Nat × Nat) (Std.TreeSet Nat) := ∅

def Index.predicted (index : Index) (nonterminal : Nat) : Std.TreeSet Nat :=
  index.predictions.getD nonterminal ∅

def Index.finished (index : Index) (origin nonterminal : Nat) : Std.TreeSet Nat :=
  index.completions.getD (origin, nonterminal) ∅

/-- Index construction does not recognize any new items. Its result is
independently checked, so its correctness is not a premise of acceptance. -/
def buildIndex (grammar : IndexedGrammar) (items : List Item) : Index := Id.run do
  let mut index : Index := {}
  for (production, id) in grammar.grammar.productions.zipIdx do
    index := { index with
      predictions := index.predictions.insert production.lhs ((index.predicted production.lhs).insert id) }
  let productions := grammar.grammar.productions.toArray
  for entry in items do
    if let some production := productions[entry.2.1]? then
      if entry.2.2.1 = production.rhs.length then
        index := { index with
          completions := index.completions.insert (entry.2.2.2, production.lhs)
            ((index.finished entry.2.2.2 production.lhs).insert entry.1) }
  return index

private def checkItem (grammar : Lanius.Extraction.Grammar)
    (productions : Array Lanius.Extraction.Production) (tokens canonical : Array Nat)
    (seen : Std.TreeSet Item) (index : Index) (entry : Item) : Bool :=
  match productions[entry.2.1]? with
  | none => false
  | some production =>
    (if entry.2.2.1 = production.rhs.length then
      (index.finished entry.2.2.2 production.lhs).contains entry.1 else true) &&
    match production.rhs[entry.2.2.1]? with
    | none => true
    | some symbol =>
      if symbol < grammar.n_kinds then
        match scanTerminalArray grammar.split_token_kind grammar.split_component_kind
            tokens canonical entry.1 symbol with
        | none => true
        | some finish => seen.contains (finish, entry.2.1, entry.2.2.1 + 1, entry.2.2.2)
      else
        ((index.predicted (symbol - grammar.n_kinds)).toList.all fun child =>
          seen.contains (entry.1, child, 0, entry.1)) &&
        ((index.finished entry.1 (symbol - grammar.n_kinds)).toList.all fun finish =>
          seen.contains (finish, entry.2.1, entry.2.2.1 + 1, entry.2.2.2))

/-- Finite closure validation. Random-access grammar/token tables and
balanced item/span indexes avoid list-prefix lookup and an all-state-pairs
completion check. Nullable completions and split-token scans use the same
rules as the source parser. -/
def checkWithIndex (grammar : IndexedGrammar) (tokens : List Nat)
    (items : List Item) (index : Index) : Bool :=
  let seen := Std.TreeSet.ofList items
  let productions := grammar.grammar.productions.toArray
  let tokens := tokens.toArray
  let canonical := grammar.grammar.canonical_kinds.toArray
  (grammar.grammar.productions.zipIdx.all fun (production, id) =>
    (if production.lhs = grammar.grammar.start_nonterminal then seen.contains (0, id, 0, 0) else true) &&
    (index.predicted production.lhs).contains id) &&
  items.all (checkItem grammar.grammar productions tokens canonical seen index)

def check (grammar : IndexedGrammar) (tokens : List Nat) (items : List Item) : Bool :=
  checkWithIndex grammar tokens items (buildIndex grammar items)

theorem check_grammar_congr {left right : IndexedGrammar} (same : left.grammar = right.grammar) :
    check left tokens items = check right tokens items := by
  cases left
  cases right
  cases same
  rfl

private theorem seen_iff : (Std.TreeSet.ofList items).contains (item position key) = true ↔
    (workspace items).containsKey position key := by
  simp [contains_iff]

private theorem production_found {grammar : IndexedGrammar} (production : Fin grammar.productionCount) :
    grammar.grammar.productions.toArray[production.val]? = some (grammar.productionAt production) := by
  simp [IndexedGrammar.productionAt, IndexedGrammar.productionCount]

private theorem row_checked (checked : checkWithIndex grammar tokens items index = true)
    (production : Fin grammar.productionCount) :
    (if (grammar.productionAt production).lhs = grammar.grammar.start_nonterminal then
      (Std.TreeSet.ofList items).contains (0, production.val, 0, 0) else true) = true ∧
    (index.predicted (grammar.productionAt production).lhs).contains production.val = true := by
  have rows := (Bool.and_eq_true_iff.mp checked).1
  have member : (grammar.productionAt production, production.val) ∈ grammar.grammar.productions.zipIdx := by
    simp [List.mem_zipIdx_iff_getElem?, IndexedGrammar.productionAt, IndexedGrammar.productionCount]
  exact Bool.and_eq_true_iff.mp (List.all_eq_true.mp rows _ member)

private theorem item_checked (checked : checkWithIndex grammar tokens items index = true)
    (present : (workspace items).containsKey position key) :
    checkItem grammar.grammar grammar.grammar.productions.toArray tokens.toArray
      grammar.grammar.canonical_kinds.toArray (Std.TreeSet.ofList items) index (item position key) = true :=
  List.all_eq_true.mp (Bool.and_eq_true_iff.mp checked).2 _ (contains_iff.mp present)

/-- Acceptance proves all four existing chart-closure rules, even if the
supplied accelerators are malicious. In particular, deleting a completed
span from the index cannot make a missing completion obligation disappear. -/
theorem checkWithIndex_closed (checked : checkWithIndex grammar tokens items index = true) :
    ChartClosed grammar tokens (workspace items) where
  seed production start := by
    have seeded := (row_checked checked production).1
    simp only [start, ↓reduceIte] at seeded
    exact seen_iff.mp seeded
  predict parent child dot origin position waiting expected := by
    have parentChecked := (item_checked checked waiting)
    have nonterminal : ¬ grammar.grammar.n_kinds + (grammar.productionAt child).lhs < grammar.grammar.n_kinds := by omega
    simp only [checkItem, item, production_found, expected, nonterminal,
      ↓reduceIte, Nat.add_sub_cancel_left] at parentChecked
    have predictions := (Bool.and_eq_true_iff.mp (Bool.and_eq_true_iff.mp parentChecked).2).1
    apply seen_iff.mp
    exact List.all_eq_true.mp predictions _
      (Std.TreeSet.mem_toList.mpr (Std.TreeSet.contains_iff_mem.mp (row_checked checked child).2))
  scan production dot origin position kind finish waiting expected terminal scanned := by
    have checkedItem := item_checked checked waiting
    simp only [checkItem, item, production_found, expected, terminal, ↓reduceIte, scanTerminalArray_eq, scanned] at checkedItem
    exact seen_iff.mp (Bool.and_eq_true_iff.mp checkedItem).2
  complete parent child dot origin middle finish waiting expected completed := by
    have parentChecked := item_checked checked waiting
    have nonterminal : ¬ grammar.grammar.n_kinds + (grammar.productionAt child).lhs < grammar.grammar.n_kinds := by omega
    simp only [checkItem, item, production_found, expected, nonterminal,
      ↓reduceIte, Nat.add_sub_cancel_left] at parentChecked
    have completions := (Bool.and_eq_true_iff.mp (Bool.and_eq_true_iff.mp parentChecked).2).2
    have childChecked := item_checked checked completed
    simp only [checkItem, item, production_found, ↓reduceIte] at childChecked
    have covered := (Bool.and_eq_true_iff.mp childChecked).1
    exact seen_iff.mp (List.all_eq_true.mp completions _
      (Std.TreeSet.mem_toList.mpr (Std.TreeSet.contains_iff_mem.mp covered)))

theorem check_closed (checked : check grammar tokens items = true) :
    ChartClosed grammar tokens (workspace items) := checkWithIndex_closed checked

/-- The checked envelope bounds the actual source-generated workspace;
accepting a certificate never assumes that the source parser succeeded. -/
theorem checked_length_le (checked : check grammar tokens items = true)
    (generated : WorkspaceGenerated grammar tokens actual)
    (valid : WorkspaceWellFormed actual) : actual.states.length ≤ items.length := by
  simpa only [states_length] using generated.length_le valid (check_closed checked) (chartSound items)

/-- A finite source-independent resource certificate. Extra candidate items
are allowed, but count against capacity. -/
structure Checked (grammar : IndexedGrammar) (tokens : List Nat) (capacity : Nat) where
  items : List Item
  closed : check grammar tokens items = true
  fits : items.length < capacity

def check? (grammar : IndexedGrammar) (tokens : List Nat) (capacity : Nat)
    (items : List Item) : Option (Checked grammar tokens capacity) :=
  if fits : items.length < capacity then
    if closed : check grammar tokens items = true then some ⟨items, closed, fits⟩ else none
  else none

theorem Checked.states_lt (certificate : Checked grammar tokens capacity)
    (generated : WorkspaceGenerated grammar tokens actual)
    (valid : WorkspaceWellFormed actual) : actual.states.length < capacity :=
  Nat.lt_of_le_of_lt (checked_length_le certificate.closed generated valid) certificate.fits

end Lanius.Compiler.Parser.Envelope
