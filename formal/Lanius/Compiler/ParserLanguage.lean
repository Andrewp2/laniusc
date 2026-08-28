import Lanius.Compiler.ParserWorkspace
import Lanius.Compiler.ParserGrammar

namespace Lanius.Compiler.Parser

/-! # Declarative parser language

The recognizer operates over a token-position lattice rather than a fixed
terminal word. Ordinary token boundaries are even positions. A physical split
token such as `>>` may instead be consumed as two virtual component terminals,
with the intermediate boundary at an odd position. Keeping this behavior in
the declarative grammar layer prevents the extracted implementation and its
workspace encoding from becoming the definition of accepted syntax.

`RecognizesSymbol` and `RecognizesSequence` form a parse-tree-style semantics
for the indexed context-free grammar. This is the specification to which the
Earley workspace will be related; it is independent of production indexes by
left-hand side, state IDs, chart links, and backpointer encodings.
-/

/-- One terminal transition in the source parser's token lattice. -/
def scanTerminalStep
    (splitTokenKind splitComponentKind rawKind canonicalKind position : Nat) :
    Option Nat :=
  if position % 2 = 1 then
    if rawKind = splitTokenKind ∧ canonicalKind = splitComponentKind then
      some (position + 1)
    else
      none
  else if rawKind = canonicalKind then
    some (position + 2)
  else if rawKind = splitTokenKind ∧ canonicalKind = splitComponentKind then
    some (position + 1)
  else
    none

/-- Consume semantic terminal `semanticKind` at lattice position `position`.
    Absence means that terminal cannot consume the current physical token. -/
def scanTerminal
    (grammar : IndexedGrammar) (tokens : List Nat)
    (position semanticKind : Nat) : Option Nat :=
  match tokens[position / 2]?, grammar.grammar.canonical_kinds[semanticKind]? with
  | some rawKind, some canonicalKind =>
      scanTerminalStep grammar.grammar.split_token_kind
        grammar.grammar.split_component_kind rawKind canonicalKind position
  | _, _ => none

/-- A successful terminal scan remains inside the finite token lattice. -/
theorem scanTerminal_some_le_finalPosition
    (grammar : IndexedGrammar) (tokens : List Nat)
    (position semanticKind nextPosition : Nat)
    (scanned : scanTerminal grammar tokens position semanticKind =
      some nextPosition) :
    nextPosition ≤ finalPosition tokens.length := by
  unfold scanTerminal at scanned
  split at scanned <;> try contradiction
  rename_i rawKind canonicalKind tokenFound canonicalFound
  have tokenIndexBound := List.getElem?_eq_some_iff.mp tokenFound |>.1
  unfold scanTerminalStep at scanned
  split at scanned <;> split at scanned <;>
    simp_all [finalPosition] <;> omega

/-- A successful scan strictly advances its lattice position. -/
theorem scanTerminal_some_gt
    (scanned : scanTerminal grammar tokens position semanticKind =
      some nextPosition) :
    position < nextPosition := by
  unfold scanTerminal at scanned
  split at scanned <;> try contradiction
  unfold scanTerminalStep at scanned
  split at scanned <;> split at scanned <;> simp_all <;> omega

mutual

  /-- A grammar symbol recognizes one half-open token-lattice span. Terminals
      use `scanTerminal`; nonterminals select a source grammar production and
      recognize its entire right-hand side. -/
  inductive RecognizesSymbol (grammar : IndexedGrammar) (tokens : List Nat) :
      Nat → Nat → Nat → Prop where
    | terminal
        (kindBound : semanticKind < grammar.grammar.n_kinds)
        (scanned : scanTerminal grammar tokens start semanticKind = some finish) :
        RecognizesSymbol grammar tokens semanticKind start finish
    | nonterminal
        (nonterminalBound : nonterminal < grammar.grammar.n_nonterminals)
        (productionBound : productionId < grammar.productionCount)
        (lhs : (grammar.productionAt ⟨productionId, productionBound⟩).lhs =
          nonterminal)
        (body : RecognizesSequence grammar tokens
          (grammar.productionAt ⟨productionId, productionBound⟩).rhs
          start finish) :
        RecognizesSymbol grammar tokens
          (grammar.grammar.n_kinds + nonterminal) start finish

  /-- A right-hand side recognizes by partitioning its span in source order.
      The empty production recognizes an empty span. -/
  inductive RecognizesSequence (grammar : IndexedGrammar) (tokens : List Nat) :
      List Nat → Nat → Nat → Prop where
    | empty : RecognizesSequence grammar tokens [] position position
    | cons
        (head : RecognizesSymbol grammar tokens symbol start middle)
        (tail : RecognizesSequence grammar tokens symbols middle finish) :
        RecognizesSequence grammar tokens (symbol :: symbols) start finish

end

/-- The grammar accepts a token buffer when its start nonterminal recognizes
    the complete token lattice. -/
def RecognizesInput (grammar : IndexedGrammar) (tokens : List Nat) : Prop :=
  RecognizesSymbol grammar tokens
    (grammar.grammar.n_kinds + grammar.grammar.start_nonterminal)
    0 (finalPosition tokens.length)

theorem RecognizesSequence.append_symbol
    (recognizedPrefix : RecognizesSequence grammar tokens symbols start middle)
    (last : RecognizesSymbol grammar tokens symbol middle finish) :
    RecognizesSequence grammar tokens (symbols ++ [symbol]) start finish :=
  match recognizedPrefix with
  | .empty => .cons last .empty
  | .cons head tail => .cons head (tail.append_symbol last)

theorem RecognizesSequence.append
    (left : RecognizesSequence grammar tokens leftSymbols start middle)
    (right : RecognizesSequence grammar tokens rightSymbols middle finish) :
    RecognizesSequence grammar tokens (leftSymbols ++ rightSymbols)
      start finish :=
  match left with
  | .empty => right
  | .cons head tail => .cons head (tail.append right)

end Lanius.Compiler.Parser
