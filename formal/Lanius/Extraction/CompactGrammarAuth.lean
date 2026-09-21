import Lanius.Extraction.GeneratedGrammar

namespace Lanius.Extraction

/-! The compact parser table is data, not a trusted `Grammar`.  This module
    decodes every table and checks the two index tables before exposing one. -/

def compactGrammarVersion : Nat := 1

def grammarOffsetsFrom (cursor : Nat) : List (List α) → List Nat
  | [] => []
  | row :: rows => cursor :: grammarOffsetsFrom (cursor + row.length) rows

def grammarRowsByLhs (grammar : Grammar) : List (List Nat) :=
  (List.range grammar.n_nonterminals).map fun lhs =>
    (List.range grammar.productions.length).filter fun id =>
      match grammar.productions[id]? with
      | some production => production.lhs == lhs
      | none => false

def packGrammar (grammar : Grammar) : List Int :=
  let rhsSymbols := grammar.productions.flatMap (fun production => production.rhs)
  let rhsOffsets := grammarOffsetsFrom 0 (grammar.productions.map (·.rhs))
  let rhsLengths := grammar.productions.map (·.rhs.length)
  let lhsRows := grammarRowsByLhs grammar
  let lhsOffsets := grammarOffsetsFrom 0 lhsRows
  let lhsCounts := lhsRows.map List.length
  let lhsProductions := lhsRows.flatten
  let tables := [grammar.canonical_kinds, grammar.productions.map (·.lhs),
    rhsOffsets, rhsLengths, rhsSymbols, lhsOffsets, lhsCounts, lhsProductions]
  let offsets := grammarOffsetsFrom 17 tables
  let header := [compactGrammarVersion, grammar.n_kinds, grammar.productions.length,
    grammar.n_nonterminals, grammar.start_nonterminal, grammar.split_token_kind,
    grammar.split_component_kind, offsets[0]!, offsets[1]!, offsets[2]!, offsets[3]!,
    offsets[4]!, rhsSymbols.length, offsets[5]!, offsets[6]!, offsets[7]!,
    lhsProductions.length]
  (header ++ tables.flatten).map Int.ofNat

def natWord? : Int → Option Nat
  | .ofNat value => some value
  | .negSucc _ => none

def readGrammarWord? (words : List Int) (index : Nat) : Option Nat :=
  words[index]?.bind natWord?

def readGrammarTable? (words : List Int) (offset count : Nat) : Option (List Nat) :=
  (List.range count).mapM fun index => readGrammarWord? words (offset + index)

def takeGrammarTable? (values : List Nat) (offset count : Nat) : Option (List Nat) :=
  if offset + count ≤ values.length then some ((values.drop offset).take count) else none

def decodeGrammar? (words : List Int) : Option Grammar := do
  let version ← readGrammarWord? words 0
  let nKinds ← readGrammarWord? words 1
  let productionCount ← readGrammarWord? words 2
  let nNonterminals ← readGrammarWord? words 3
  let start ← readGrammarWord? words 4
  let splitToken ← readGrammarWord? words 5
  let splitComponent ← readGrammarWord? words 6
  let canonicalOffset ← readGrammarWord? words 7
  let lhsOffset ← readGrammarWord? words 8
  let rhsOffsetsOffset ← readGrammarWord? words 9
  let rhsLengthsOffset ← readGrammarWord? words 10
  let rhsSymbolsOffset ← readGrammarWord? words 11
  let rhsSymbolCount ← readGrammarWord? words 12
  let lhsOffsetsOffset ← readGrammarWord? words 13
  let lhsCountsOffset ← readGrammarWord? words 14
  let lhsProductionsOffset ← readGrammarWord? words 15
  let lhsProductionCount ← readGrammarWord? words 16
  if version != compactGrammarVersion then none else
    let tables ← readGrammarTable? words canonicalOffset nKinds
    let productionLhs ← readGrammarTable? words lhsOffset productionCount
    let rhsOffsets ← readGrammarTable? words rhsOffsetsOffset productionCount
    let rhsLengths ← readGrammarTable? words rhsLengthsOffset productionCount
    let rhsSymbols ← readGrammarTable? words rhsSymbolsOffset rhsSymbolCount
    let lhsOffsets ← readGrammarTable? words lhsOffsetsOffset nNonterminals
    let lhsCounts ← readGrammarTable? words lhsCountsOffset nNonterminals
    let lhsProductions ← readGrammarTable? words lhsProductionsOffset lhsProductionCount
    let productions ← (List.range productionCount).mapM fun id => do
      let lhs := productionLhs[id]!
      let offset := rhsOffsets[id]!
      let count := rhsLengths[id]!
      let rhs ← takeGrammarTable? rhsSymbols offset count
      pure ⟨lhs, rhs⟩
    let grammar : Grammar := {
      n_kinds := nKinds
      n_nonterminals := nNonterminals
      start_nonterminal := start
      split_token_kind := splitToken
      split_component_kind := splitComponent
      canonical_kinds := tables
      productions }
    let rhsRows := productions.map (·.rhs)
    let lhsRows := grammarRowsByLhs grammar
    let expectedLhsOffsets := grammarOffsetsFrom 0 lhsRows
    let expectedLhsCounts := lhsRows.map List.length
    let expectedLhsProductions := lhsRows.flatten
    if rhsOffsets = grammarOffsetsFrom 0 rhsRows ∧
        rhsLengths = rhsRows.map List.length ∧
        lhsOffsets = expectedLhsOffsets ∧ lhsCounts = expectedLhsCounts ∧
        lhsProductions = expectedLhsProductions ∧
        words.length = lhsProductionsOffset + lhsProductionCount then
      pure grammar
    else none

def generatedGrammarWords : List Int := packGrammar laniusGrammar

theorem generatedGrammarWords_eq_pack :
    generatedGrammarWords = packGrammar laniusGrammar := rfl

structure CheckedGrammar where
  words : List Int
  grammar : Grammar

def checkGrammar? (words : List Int) : Option CheckedGrammar :=
  (decodeGrammar? words).map fun grammar => ⟨words, grammar⟩

theorem checkGrammar_sound {words : List Int} {checked : CheckedGrammar}
    (accepted : checkGrammar? words = some checked) :
    decodeGrammar? words = some checked.grammar := by
  have projected := congrArg (Option.map CheckedGrammar.grammar) accepted
  simpa [checkGrammar?] using projected

end Lanius.Extraction
