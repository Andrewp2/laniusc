import Lanius.Extraction.Grammar

namespace Lanius.Compiler.Parser

open Lanius.Extraction

/-! # Packed parser grammar

The verified parser consumes a flat `i32` slice, while the parse checker and
algorithmic correctness statement use `Extraction.Grammar`. This module is
the semantic boundary between those representations. It deliberately records
the production index by left-hand side because the source parser consumes
that index directly; merely proving the production rows safe would not prove
that prediction implements the intended grammar.
-/

def grammarVersion : Nat := 1

def grammarHeaderWords : Nat := 17

structure IndexedGrammar where
  grammar : Grammar
  productionsByLhs : List (List Nat)
deriving DecidableEq, Repr

def IndexedGrammar.productionCount (grammar : IndexedGrammar) : Nat :=
  grammar.grammar.productions.length

def IndexedGrammar.productionAt (grammar : IndexedGrammar)
    (productionId : Fin grammar.productionCount) : Production :=
  grammar.grammar.productions.get ⟨productionId, by
    simpa [IndexedGrammar.productionCount] using productionId.isLt⟩

def IndexedGrammar.rhsSymbols (grammar : IndexedGrammar) : List Nat :=
  grammar.grammar.productions.flatMap (fun production => production.rhs)

def offsetsFrom (cursor : Nat) : List (List α) → List Nat
  | [] => []
  | row :: rows => cursor :: offsetsFrom (cursor + row.length) rows

def IndexedGrammar.rhsOffsets (grammar : IndexedGrammar) : List Nat :=
  offsetsFrom 0 (grammar.grammar.productions.map (fun production =>
    production.rhs))

def IndexedGrammar.rhsLengths (grammar : IndexedGrammar) : List Nat :=
  grammar.grammar.productions.map (fun production => production.rhs.length)

def IndexedGrammar.productionLhs (grammar : IndexedGrammar) : List Nat :=
  grammar.grammar.productions.map (fun production => production.lhs)

def IndexedGrammar.lhsOffsets (grammar : IndexedGrammar) : List Nat :=
  offsetsFrom 0 grammar.productionsByLhs

def IndexedGrammar.lhsCounts (grammar : IndexedGrammar) : List Nat :=
  grammar.productionsByLhs.map List.length

def IndexedGrammar.lhsProductions (grammar : IndexedGrammar) : List Nat :=
  grammar.productionsByLhs.flatten

def IndexedGrammar.productionIdsFor
    (grammar : IndexedGrammar) (nonterminal : Nat) : List Nat :=
  (List.range grammar.productionCount).filter fun productionId =>
    match grammar.grammar.production? productionId with
    | some production => production.lhs == nonterminal
    | none => false

/-- Semantic well-formedness is stronger than the source parser's memory-
    safety validation: the left-hand-side index must be complete as well as
    sound. This is what lets recognition over the packed index denote the
    language of `grammar`. -/
structure IndexedGrammar.WellFormed (grammar : IndexedGrammar) : Prop where
  kindCountPositive : 0 < grammar.grammar.n_kinds
  productionCountPositive : 0 < grammar.productionCount
  nonterminalCountPositive : 0 < grammar.grammar.n_nonterminals
  symbolDomainFitsI32 :
    grammar.grammar.n_kinds + grammar.grammar.n_nonterminals ≤ 2147483647
  startInBounds : grammar.grammar.start_nonterminal <
    grammar.grammar.n_nonterminals
  canonicalKindCount : grammar.grammar.canonical_kinds.length =
    grammar.grammar.n_kinds
  lhsIndexCount : grammar.productionsByLhs.length =
    grammar.grammar.n_nonterminals
  productionLhsInBounds : ∀ productionId production,
    grammar.grammar.production? productionId = some production →
      production.lhs < grammar.grammar.n_nonterminals
  rhsSymbolsInBounds : ∀ productionId production symbol,
    grammar.grammar.production? productionId = some production →
      symbol ∈ production.rhs →
      symbol < grammar.grammar.n_kinds + grammar.grammar.n_nonterminals
  lhsIndexExact : ∀ nonterminal,
    nonterminal < grammar.grammar.n_nonterminals →
      grammar.productionsByLhs[nonterminal]? =
        some (grammar.productionIdsFor nonterminal)

structure PackedGrammarLayout where
  wordLength : Nat
  canonicalKindsOffset : Nat
  productionLhsOffset : Nat
  rhsOffsetsOffset : Nat
  rhsLengthsOffset : Nat
  rhsSymbolsOffset : Nat
  lhsOffsetsOffset : Nat
  lhsCountsOffset : Nat
  lhsProductionsOffset : Nat
deriving DecidableEq, Repr

def natWords (values : List Nat) : List Int :=
  values.map Int.ofNat

/-- One variable-length table occupies a checked half-open range and contains
    exactly the logical rows claimed by the semantic grammar. Tables may have
    padding or arbitrary ordering in the physical buffer; no canonical
    placement assumption leaks into parser correctness. -/
def PackedTableAt (words : List Int) (offset : Nat)
    (values : List Nat) : Prop :=
  grammarHeaderWords ≤ offset ∧
    offset + values.length ≤ words.length ∧
    (words.drop offset).take values.length = natWords values

/-- The mathematical range predicate implemented by the parser's
    `range_valid` helper once its arguments have been shown to be ordinary
    nonnegative i32 values. -/
def PackedRangeValid (offset count wordLength : Nat) : Prop :=
  grammarHeaderWords ≤ offset ∧
    offset ≤ wordLength ∧
    count ≤ wordLength - offset

def HeaderWord (words : List Int) (index value : Nat) : Prop :=
  words[index]? = some (Int.ofNat value)

structure EncodesGrammar
    (layout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) : Prop where
  length : words.length = layout.wordLength
  headerPresent : grammarHeaderWords ≤ words.length
  version : HeaderWord words 0 grammarVersion
  kindCount : HeaderWord words 1 grammar.grammar.n_kinds
  productionCount : HeaderWord words 2 grammar.productionCount
  nonterminalCount : HeaderWord words 3 grammar.grammar.n_nonterminals
  startNonterminal : HeaderWord words 4 grammar.grammar.start_nonterminal
  splitTokenKind : HeaderWord words 5 grammar.grammar.split_token_kind
  splitComponentKind : HeaderWord words 6
    grammar.grammar.split_component_kind
  canonicalKindsOffset : HeaderWord words 7 layout.canonicalKindsOffset
  productionLhsOffset : HeaderWord words 8 layout.productionLhsOffset
  rhsOffsetsOffset : HeaderWord words 9 layout.rhsOffsetsOffset
  rhsLengthsOffset : HeaderWord words 10 layout.rhsLengthsOffset
  rhsSymbolsOffset : HeaderWord words 11 layout.rhsSymbolsOffset
  rhsSymbolCount : HeaderWord words 12 grammar.rhsSymbols.length
  lhsOffsetsOffset : HeaderWord words 13 layout.lhsOffsetsOffset
  lhsCountsOffset : HeaderWord words 14 layout.lhsCountsOffset
  lhsProductionsOffset : HeaderWord words 15 layout.lhsProductionsOffset
  lhsProductionCount : HeaderWord words 16 grammar.lhsProductions.length
  canonicalKinds : PackedTableAt words layout.canonicalKindsOffset
    grammar.grammar.canonical_kinds
  productionLhs : PackedTableAt words layout.productionLhsOffset
    grammar.productionLhs
  rhsOffsets : PackedTableAt words layout.rhsOffsetsOffset grammar.rhsOffsets
  rhsLengths : PackedTableAt words layout.rhsLengthsOffset grammar.rhsLengths
  rhsSymbols : PackedTableAt words layout.rhsSymbolsOffset grammar.rhsSymbols
  lhsOffsets : PackedTableAt words layout.lhsOffsetsOffset grammar.lhsOffsets
  lhsCounts : PackedTableAt words layout.lhsCountsOffset grammar.lhsCounts
  lhsProductions : PackedTableAt words layout.lhsProductionsOffset
    grammar.lhsProductions

theorem PackedTableAt.offset_in_bounds
    (encoded : PackedTableAt words offset values) :
    offset ≤ words.length := by
  rcases encoded with ⟨_, fits, _⟩
  omega

theorem PackedTableAt.range_valid
    (encoded : PackedTableAt words offset values) :
    PackedRangeValid offset values.length words.length := by
  rcases encoded with ⟨afterHeader, fits, _⟩
  constructor
  · exact afterHeader
  constructor <;> omega

theorem PackedTableAt.row_in_bounds
    (encoded : PackedTableAt words offset values)
    (rowBound : row < values.length) :
    offset + row < words.length := by
  rcases encoded with ⟨_, fits, _⟩
  omega

theorem PackedTableAt.getElem?
    (encoded : PackedTableAt words offset values)
    (rowBound : row < values.length) :
    words[offset + row]? =
      some (Int.ofNat (values.get ⟨row, rowBound⟩)) := by
  rcases encoded with ⟨_, fits, contents⟩
  have sameRow := congrArg (fun rows => rows[row]?) contents
  rw [List.getElem?_take_of_lt rowBound] at sameRow
  rw [List.getElem?_drop] at sameRow
  simpa [natWords, rowBound, Nat.add_comm] using sameRow

theorem PackedTableAt.get
    (encoded : PackedTableAt words offset values)
    (rowBound : row < values.length) :
    words.get ⟨offset + row, encoded.row_in_bounds rowBound⟩ =
      Int.ofNat (values.get ⟨row, rowBound⟩) := by
  have found := encoded.getElem? rowBound
  rw [List.getElem?_eq_getElem (encoded.row_in_bounds rowBound)] at found
  exact Option.some.inj found

theorem HeaderWord.index_in_bounds
    (header : HeaderWord words index value) :
    index < words.length := by
  exact List.getElem?_eq_some_iff.mp header |>.1

theorem HeaderWord.get
    (header : HeaderWord words index value) :
    words.get ⟨index, header.index_in_bounds⟩ = Int.ofNat value := by
  have bound := header.index_in_bounds
  unfold HeaderWord at header
  rw [List.getElem?_eq_getElem bound] at header
  exact Option.some.inj header

@[simp] theorem natWords_length (values : List Nat) :
    (natWords values).length = values.length := by
  simp [natWords]

@[simp] theorem offsetsFrom_length
    (cursor : Nat) (rows : List (List α)) :
    (offsetsFrom cursor rows).length = rows.length := by
  induction rows generalizing cursor with
  | nil => rfl
  | cons row rows inductionHypothesis =>
      simp [offsetsFrom, inductionHypothesis]

/-- The offset generated for a row leaves enough room for that entire row in
    the flattened table.  This is the arithmetic fact checked by both nested
    loops in `grammar_is_valid`. -/
theorem offsetsFrom_row_fits
    (cursor : Nat) (rows : List (List α))
    (row : Fin rows.length) :
    (offsetsFrom cursor rows).get
          ⟨row, by simpa using row.isLt⟩ +
        (rows.get row).length ≤
      cursor + rows.flatten.length := by
  induction rows generalizing cursor with
  | nil => exact Fin.elim0 row
  | cons head tail inductionHypothesis =>
      refine Fin.cases ?_ (fun tailRow => ?_) row
      · simp [offsetsFrom]
      · have fits := inductionHypothesis (cursor + head.length) tailRow
        simpa [offsetsFrom, Nat.add_assoc] using fits

/-- `offsetsFrom` is a cursor plus the flattened length of all preceding
    rows. This exposes the semantic meaning of an offset, not merely its
    bounds. -/
theorem offsetsFrom_get_eq_cursor_add_prefix
    (cursor : Nat) (rows : List (List α)) (row : Fin rows.length) :
    (offsetsFrom cursor rows).get
        ⟨row, by simpa using row.isLt⟩ =
      cursor + (rows.take row).flatten.length := by
  induction rows generalizing cursor with
  | nil => exact Fin.elim0 row
  | cons head tail inductionHypothesis =>
      refine Fin.cases ?_ (fun tailRow => ?_) row
      · simp [offsetsFrom]
      · have previous := inductionHypothesis (cursor + head.length) tailRow
        simpa [offsetsFrom, Nat.add_assoc] using previous

/-- Lookup through a flattened row table at its generated offset returns the
    corresponding element of that row. -/
theorem flatten_get_at_row
    (rows : List (List α)) (row index : Nat)
    (rowBound : row < rows.length)
    (indexBound : index < (rows.get ⟨row, rowBound⟩).length)
    (bound : (rows.take row).flatten.length + index < rows.flatten.length) :
    rows.flatten[(rows.take row).flatten.length + index] =
      (rows.get ⟨row, rowBound⟩)[index] := by
  induction rows generalizing row with
  | nil => simp at rowBound
  | cons head tail inductionHypothesis =>
      cases row with
      | zero =>
          have headIndexBound : index < head.length := by
            simpa using indexBound
          have appendBound : index < (head ++ tail.flatten).length := by
            simp
            omega
          have selected := List.getElem_append_left
            (bs := tail.flatten) (h' := appendBound) headIndexBound
          simpa using selected
      | succ tailRow =>
          have tailRowBound : tailRow < tail.length := by simpa using rowBound
          have tailIndexBound :
              index < (tail.get ⟨tailRow, tailRowBound⟩).length := by
            simpa using indexBound
          have tailBound :
              (tail.take tailRow).flatten.length + index <
                tail.flatten.length := by
            have normalized : head.length +
                ((tail.take tailRow).flatten.length + index) <
                head.length + tail.flatten.length := by
              simpa [Nat.add_assoc] using bound
            omega
          have previous := inductionHypothesis tailRow tailRowBound
            tailIndexBound tailBound
          have appendBound : head.length +
              ((tail.take tailRow).flatten.length + index) <
              (head ++ tail.flatten).length := by
            rw [List.length_append]
            omega
          have shifted :
              (head ++ tail.flatten)[head.length +
                ((tail.take tailRow).flatten.length + index)]'appendBound =
              tail.flatten[(tail.take tailRow).flatten.length + index] := by
            rw [List.getElem_append_right (by omega)]
            simp
          have selected := shifted.trans previous
          simpa [Nat.add_assoc] using selected

@[simp] theorem IndexedGrammar.rhsOffsets_length
    (grammar : IndexedGrammar) :
    grammar.rhsOffsets.length = grammar.productionCount := by
  simp [IndexedGrammar.rhsOffsets, IndexedGrammar.productionCount]

@[simp] theorem IndexedGrammar.rhsLengths_length
    (grammar : IndexedGrammar) :
    grammar.rhsLengths.length = grammar.productionCount := by
  simp [IndexedGrammar.rhsLengths, IndexedGrammar.productionCount]

@[simp] theorem IndexedGrammar.productionLhs_length
    (grammar : IndexedGrammar) :
    grammar.productionLhs.length = grammar.productionCount := by
  simp [IndexedGrammar.productionLhs, IndexedGrammar.productionCount]

@[simp] theorem IndexedGrammar.productionLhs_get
    (grammar : IndexedGrammar) (productionId : Fin grammar.productionCount) :
    grammar.productionLhs.get
        ⟨productionId, by simpa using productionId.isLt⟩ =
      (grammar.productionAt productionId).lhs := by
  simp [IndexedGrammar.productionLhs, IndexedGrammar.productionAt,
    IndexedGrammar.productionCount, List.get_eq_getElem]

@[simp] theorem IndexedGrammar.rhsLengths_get
    (grammar : IndexedGrammar) (productionId : Fin grammar.productionCount) :
    grammar.rhsLengths.get
        ⟨productionId, by simpa using productionId.isLt⟩ =
      (grammar.productionAt productionId).rhs.length := by
  simp [IndexedGrammar.rhsLengths, IndexedGrammar.productionAt,
    IndexedGrammar.productionCount, List.get_eq_getElem]

@[simp] theorem IndexedGrammar.lhsCounts_get
    (grammar : IndexedGrammar)
    (nonterminal : Fin grammar.productionsByLhs.length) :
    grammar.lhsCounts.get
        ⟨nonterminal, by
          simpa [IndexedGrammar.lhsCounts] using nonterminal.isLt⟩ =
      (grammar.productionsByLhs.get nonterminal).length := by
  simp [IndexedGrammar.lhsCounts, List.get_eq_getElem]

@[simp] theorem IndexedGrammar.lhsOffsets_length
    (grammar : IndexedGrammar) :
    grammar.lhsOffsets.length = grammar.productionsByLhs.length := by
  simp [IndexedGrammar.lhsOffsets]

@[simp] theorem IndexedGrammar.lhsCounts_length
    (grammar : IndexedGrammar) :
    grammar.lhsCounts.length = grammar.productionsByLhs.length := by
  simp [IndexedGrammar.lhsCounts]

theorem IndexedGrammar.lhsProductions_get_at_row
    (grammar : IndexedGrammar)
    (nonterminal : Fin grammar.productionsByLhs.length)
    (index : Fin (grammar.productionsByLhs.get nonterminal).length) :
    grammar.lhsProductions.get
        ⟨grammar.lhsOffsets.get
              ⟨nonterminal, by simpa using nonterminal.isLt⟩ + index,
          by
            have fits := offsetsFrom_row_fits 0 grammar.productionsByLhs
              nonterminal
            unfold IndexedGrammar.lhsOffsets IndexedGrammar.lhsProductions
            omega⟩ =
      (grammar.productionsByLhs.get nonterminal).get index := by
  have offsetEq := offsetsFrom_get_eq_cursor_add_prefix 0
    grammar.productionsByLhs nonterminal
  simp only [Nat.zero_add] at offsetEq
  have fits := offsetsFrom_row_fits 0 grammar.productionsByLhs nonterminal
  have bound : (grammar.productionsByLhs.take nonterminal).flatten.length +
      index < grammar.productionsByLhs.flatten.length := by
    rw [← offsetEq]
    omega
  have selected := flatten_get_at_row grammar.productionsByLhs
    nonterminal index nonterminal.isLt index.isLt bound
  have targetBound :
      (offsetsFrom 0 grammar.productionsByLhs).get
          ⟨nonterminal, by simpa using nonterminal.isLt⟩ + index <
        grammar.productionsByLhs.flatten.length := by
    rw [offsetEq]
    exact bound
  let targetIndex : Fin grammar.productionsByLhs.flatten.length :=
    ⟨(offsetsFrom 0 grammar.productionsByLhs).get
        ⟨nonterminal, by simpa using nonterminal.isLt⟩ + index, targetBound⟩
  let prefixIndex : Fin grammar.productionsByLhs.flatten.length :=
    ⟨(grammar.productionsByLhs.take nonterminal).flatten.length + index,
      bound⟩
  have indexEq : targetIndex = prefixIndex := by
    apply Fin.ext
    exact congrArg (fun value : Nat => value + (index : Nat)) offsetEq
  have same := congrArg grammar.productionsByLhs.flatten.get indexEq
  change grammar.productionsByLhs.flatten.get targetIndex =
    (grammar.productionsByLhs.get nonterminal).get index
  exact same.trans (by simpa [prefixIndex] using selected)

/-- All non-iterative checks at the front of `grammar_is_valid`, stated over
    the semantic grammar and its packed layout.  The production and
    nonterminal loops are deliberately separate contracts below: this keeps
    the eventual extracted execution proof aligned with the source control
    flow instead of hiding the whole validator behind one opaque predicate. -/
structure GrammarValidationPrelude
    (layout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) : Prop where
  headerPresent : grammarHeaderWords ≤ words.length
  versionMatches : HeaderWord words 0 grammarVersion
  kindCountPositive : 0 < grammar.grammar.n_kinds
  productionCountPositive : 0 < grammar.productionCount
  nonterminalCountPositive : 0 < grammar.grammar.n_nonterminals
  symbolDomainFitsI32 :
    grammar.grammar.n_kinds + grammar.grammar.n_nonterminals ≤ 2147483647
  startNonterminalInBounds : grammar.grammar.start_nonterminal <
    grammar.grammar.n_nonterminals
  canonicalKindsRange : PackedRangeValid layout.canonicalKindsOffset
    grammar.grammar.n_kinds words.length
  productionLhsRange : PackedRangeValid layout.productionLhsOffset
    grammar.productionCount words.length
  rhsOffsetsRange : PackedRangeValid layout.rhsOffsetsOffset
    grammar.productionCount words.length
  rhsLengthsRange : PackedRangeValid layout.rhsLengthsOffset
    grammar.productionCount words.length
  rhsSymbolsRange : PackedRangeValid layout.rhsSymbolsOffset
    grammar.rhsSymbols.length words.length
  lhsOffsetsRange : PackedRangeValid layout.lhsOffsetsOffset
    grammar.grammar.n_nonterminals words.length
  lhsCountsRange : PackedRangeValid layout.lhsCountsOffset
    grammar.grammar.n_nonterminals words.length
  lhsProductionsRange : PackedRangeValid layout.lhsProductionsOffset
    grammar.lhsProductions.length words.length

/-- Facts established by the production loop of `grammar_is_valid`, stated
    against dense production IDs. -/
structure ProductionValidationFacts (grammar : IndexedGrammar) : Prop where
  lhsInBounds : ∀ productionId : Fin grammar.productionCount,
    (grammar.productionAt productionId).lhs <
      grammar.grammar.n_nonterminals
  rhsRange : ∀ productionId : Fin grammar.productionCount,
    grammar.rhsOffsets.get
          ⟨productionId, by simpa using productionId.isLt⟩ +
        (grammar.productionAt productionId).rhs.length ≤
      grammar.rhsSymbols.length
  rhsSymbolsInBounds : ∀ productionId : Fin grammar.productionCount,
    ∀ symbol ∈ (grammar.productionAt productionId).rhs,
      symbol < grammar.grammar.n_kinds + grammar.grammar.n_nonterminals

/-- Every row in the flattened RHS table is a symbol from some production,
    so the per-production validation fact gives the direct bound needed by
    the extracted validator's flattened-table loop. -/
theorem ProductionValidationFacts.flattenedSymbolInBounds
    (facts : ProductionValidationFacts grammar)
    (index : Fin grammar.rhsSymbols.length) :
    grammar.rhsSymbols.get index <
      grammar.grammar.n_kinds + grammar.grammar.n_nonterminals := by
  have member : grammar.rhsSymbols.get index ∈ grammar.rhsSymbols :=
    List.get_mem _ _
  unfold IndexedGrammar.rhsSymbols at member
  rw [List.mem_flatMap] at member
  obtain ⟨production, productionMember, symbolMember⟩ := member
  obtain ⟨sourceId, sourceEq⟩ := List.get_of_mem productionMember
  let productionId : Fin grammar.productionCount :=
    ⟨sourceId, by
      simpa [IndexedGrammar.productionCount] using sourceId.isLt⟩
  have productionEq : grammar.productionAt productionId = production := by
    simpa [productionId, IndexedGrammar.productionAt,
      IndexedGrammar.productionCount] using sourceEq
  rw [← productionEq] at symbolMember
  exact facts.rhsSymbolsInBounds productionId _ symbolMember

/-- Facts established by the second validator loop.  Rows are named through
    their source-level nonterminal lookup, while the conclusion exposes both
    the packed-range bound and the semantic validity of every listed
    production. -/
structure NonterminalValidationFacts (grammar : IndexedGrammar) : Prop where
  indexRowCount : grammar.productionsByLhs.length =
    grammar.grammar.n_nonterminals
  rowRange : ∀ (nonterminal : Nat) (row : List Nat),
    grammar.productionsByLhs[nonterminal]? = some row →
      ∃ first,
        grammar.lhsOffsets[nonterminal]? = some first ∧
          first + row.length ≤ grammar.lhsProductions.length
  listedProductionValid : ∀ (nonterminal : Nat) (row : List Nat),
    nonterminal < grammar.grammar.n_nonterminals →
    grammar.productionsByLhs[nonterminal]? = some row →
    ∀ productionId ∈ row,
      ∃ productionBound : productionId < grammar.productionCount,
        (grammar.productionAt ⟨productionId, productionBound⟩).lhs =
          nonterminal

/-- Complete mathematical postcondition of a successful
    `grammar_is_valid` run.  The extracted execution proof can now be built
    phase by phase while consumers such as `recognize` depend on one stable
    semantic contract. -/
structure GrammarValidationFacts
    (layout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) : Prop where
  prelude : GrammarValidationPrelude layout grammar words
  productions : ProductionValidationFacts grammar
  nonterminals : NonterminalValidationFacts grammar

theorem EncodesGrammar.validation_prelude
    (encoded : EncodesGrammar layout grammar words)
    (wellFormed : grammar.WellFormed) :
    GrammarValidationPrelude layout grammar words := by
  refine {
    headerPresent := encoded.headerPresent
    versionMatches := encoded.version
    kindCountPositive := wellFormed.kindCountPositive
    productionCountPositive := wellFormed.productionCountPositive
    nonterminalCountPositive := wellFormed.nonterminalCountPositive
    symbolDomainFitsI32 := wellFormed.symbolDomainFitsI32
    startNonterminalInBounds := wellFormed.startInBounds
    canonicalKindsRange := ?_
    productionLhsRange := ?_
    rhsOffsetsRange := ?_
    rhsLengthsRange := ?_
    rhsSymbolsRange := encoded.rhsSymbols.range_valid
    lhsOffsetsRange := ?_
    lhsCountsRange := ?_
    lhsProductionsRange := encoded.lhsProductions.range_valid }
  · simpa [wellFormed.canonicalKindCount] using
      encoded.canonicalKinds.range_valid
  · simpa using encoded.productionLhs.range_valid
  · simpa using encoded.rhsOffsets.range_valid
  · simpa using encoded.rhsLengths.range_valid
  · simpa [wellFormed.lhsIndexCount] using encoded.lhsOffsets.range_valid
  · simpa [wellFormed.lhsIndexCount] using encoded.lhsCounts.range_valid

theorem IndexedGrammar.WellFormed.production_validation
    {grammar : IndexedGrammar} (wellFormed : grammar.WellFormed) :
    ProductionValidationFacts grammar := by
  refine {
    lhsInBounds := ?_
    rhsRange := ?_
    rhsSymbolsInBounds := ?_ }
  · intro productionId
    exact wellFormed.productionLhsInBounds productionId
      (grammar.productionAt productionId)
      (by
        unfold Lanius.Extraction.Grammar.production?
        rw [List.getElem?_eq_getElem (by
          simpa [IndexedGrammar.productionCount] using productionId.isLt)]
        simp [IndexedGrammar.productionAt, List.get_eq_getElem])
  · intro productionId
    let rows := grammar.grammar.productions.map (fun production =>
      production.rhs)
    let rowId : Fin rows.length := ⟨productionId, by
      simpa [rows, IndexedGrammar.productionCount] using productionId.isLt⟩
    have fits := offsetsFrom_row_fits 0 rows rowId
    simpa [rowId, rows, IndexedGrammar.rhsOffsets,
      IndexedGrammar.rhsSymbols, IndexedGrammar.productionCount,
      IndexedGrammar.productionAt, List.get_eq_getElem,
      Function.comp_def] using fits
  · intro productionId symbol member
    exact wellFormed.rhsSymbolsInBounds productionId
      (grammar.productionAt productionId) symbol
      (by
        unfold Lanius.Extraction.Grammar.production?
        rw [List.getElem?_eq_getElem (by
          simpa [IndexedGrammar.productionCount] using productionId.isLt)]
        simp [IndexedGrammar.productionAt, List.get_eq_getElem]) member

/-- The packed RHS offset for a production selects the same symbol as direct
    indexing into that production's semantic RHS row. -/
theorem IndexedGrammar.rhsSymbolAt
    (grammar : IndexedGrammar) (production dot : Nat)
    (productionBound : production < grammar.productionCount)
    (dotBound : dot <
      (grammar.productionAt ⟨production, productionBound⟩).rhs.length)
    (symbolRowBound :
      grammar.rhsOffsets.get ⟨production, by simpa using productionBound⟩ +
        dot < grammar.rhsSymbols.length) :
    let relative := grammar.rhsOffsets.get
      ⟨production, by simpa using productionBound⟩
    grammar.rhsSymbols.get ⟨relative + dot, symbolRowBound⟩ =
      (grammar.productionAt ⟨production, productionBound⟩).rhs.get
        ⟨dot, dotBound⟩ := by
  dsimp only
  let rows := grammar.grammar.productions.map (fun production => production.rhs)
  have rowBound : production < rows.length := by
    simpa [rows, IndexedGrammar.productionCount] using productionBound
  have indexBound : dot < (rows.get ⟨production, rowBound⟩).length := by
    simpa [rows, IndexedGrammar.productionAt, IndexedGrammar.productionCount,
      List.get_eq_getElem, Function.comp_def] using dotBound
  have offsetEq := offsetsFrom_get_eq_cursor_add_prefix 0 rows
    ⟨production, rowBound⟩
  have offsetEq' : grammar.rhsOffsets.get
      ⟨production, by simpa using productionBound⟩ =
      (rows.take production).flatten.length := by
    simpa [rows, IndexedGrammar.rhsOffsets,
      IndexedGrammar.productionCount] using offsetEq
  have flattenedBound : (rows.take production).flatten.length + dot <
      rows.flatten.length := by
    rw [← offsetEq']
    simpa [rows, IndexedGrammar.rhsSymbols, Function.comp_def] using
      symbolRowBound
  have selected := flatten_get_at_row rows production dot rowBound indexBound
    flattenedBound
  have flattenEq : grammar.rhsSymbols = rows.flatten := by
    rfl
  have indexEq : grammar.rhsOffsets.get
        ⟨production, by simpa using productionBound⟩ + dot =
      (rows.take production).flatten.length + dot :=
    congrArg (fun offset => offset + dot) offsetEq'
  have lhsEq := getElem_congr flattenEq indexEq symbolRowBound
  have rowEq : rows.get ⟨production, rowBound⟩ =
      (grammar.productionAt ⟨production, productionBound⟩).rhs := by
    simp [rows, IndexedGrammar.productionAt, List.get_eq_getElem]
  have rhsEq := getElem_congr
    (valid := fun (values : List Nat) index => index < values.length)
    rowEq rfl indexBound
  simp only [List.get_eq_getElem]
  exact lhsEq.trans (selected.trans rhsEq)

theorem IndexedGrammar.productionIdsFor_member
    {grammar : IndexedGrammar} {nonterminal productionId : Nat}
    (member : productionId ∈ grammar.productionIdsFor nonterminal) :
    ∃ productionBound : productionId < grammar.productionCount,
      (grammar.productionAt ⟨productionId, productionBound⟩).lhs =
        nonterminal := by
  unfold IndexedGrammar.productionIdsFor at member
  rcases List.mem_filter.mp member with ⟨inRange, selected⟩
  have productionBound : productionId < grammar.productionCount :=
    List.mem_range.mp inRange
  refine ⟨productionBound, ?_⟩
  have found : grammar.grammar.production? productionId =
      some (grammar.productionAt ⟨productionId, productionBound⟩) := by
    unfold Lanius.Extraction.Grammar.production?
    rw [List.getElem?_eq_getElem (by
      simpa [IndexedGrammar.productionCount] using productionBound)]
    rfl
  rw [found] at selected
  simpa using selected

theorem IndexedGrammar.WellFormed.nonterminal_validation
    {grammar : IndexedGrammar} (wellFormed : grammar.WellFormed) :
    NonterminalValidationFacts grammar := by
  refine {
    indexRowCount := wellFormed.lhsIndexCount
    rowRange := ?_
    listedProductionValid := ?_ }
  · intro nonterminal row rowFound
    rcases List.getElem?_eq_some_iff.mp rowFound with
      ⟨nonterminalBound, rowValue⟩
    let rowId : Fin grammar.productionsByLhs.length :=
      ⟨nonterminal, nonterminalBound⟩
    let first := grammar.lhsOffsets.get
      ⟨nonterminal, by simpa using nonterminalBound⟩
    refine ⟨first, ?_, ?_⟩
    · unfold IndexedGrammar.lhsOffsets first
      rw [List.getElem?_eq_getElem (by simpa using nonterminalBound)]
      simp [List.get_eq_getElem]
      rfl
    · have fits := offsetsFrom_row_fits 0 grammar.productionsByLhs rowId
      have rowEqual : grammar.productionsByLhs.get rowId = row := by
        simpa [rowId, List.get_eq_getElem] using rowValue
      rw [rowEqual] at fits
      simpa [first, rowId, IndexedGrammar.lhsOffsets,
        IndexedGrammar.lhsProductions] using fits
  · intro nonterminal row nonterminalBound rowFound productionId member
    have exactRow := wellFormed.lhsIndexExact nonterminal
      nonterminalBound
    rw [rowFound] at exactRow
    have rowEqual : row = grammar.productionIdsFor nonterminal :=
      Option.some.inj exactRow
    exact grammar.productionIdsFor_member (rowEqual ▸ member)

theorem EncodesGrammar.validation_facts
    (encoded : EncodesGrammar layout grammar words)
    (wellFormed : grammar.WellFormed) :
    GrammarValidationFacts layout grammar words := {
  prelude := encoded.validation_prelude wellFormed
  productions := wellFormed.production_validation
  nonterminals := wellFormed.nonterminal_validation
}

end Lanius.Compiler.Parser
