import Lanius.Compiler.ParserTree
import Lanius.Extraction.ParseChecker

namespace Lanius.Extraction

open Lanius.Compiler.Parser

/-! # Semantic token rows from checked parse trees

The recognizer consumes raw lexer kinds through a half-step token lattice. The
artifact checker instead stores the semantic grammar kind chosen for each
physical token, packing the two virtual `>` terminals of a split `>>` token
into one word. The materialized parse tree already records those choices, so
this module derives the artifact rows from that tree rather than trusting a
second contextual-classification pass.
-/

def parseTreeTerminalLeaves : ParseTree → List (Nat × Nat)
  | .terminal tokenIndex semanticKind => [(tokenIndex, semanticKind)]
  | .nonterminal _ _ _ _ children => children.flatMap parseTreeTerminalLeaves

/-- The terminal frontier of a parse tree consumes one contiguous interval of
    the parser's token lattice. This judgment deliberately retains the chosen
    semantic grammar kind, not merely the canonical lexer kind. -/
inductive TerminalLeavesRecognize
    (grammar : IndexedGrammar) (tokens : List Nat) :
    List (Nat × Nat) → Nat → Nat → Prop where
  | empty (position : Nat) :
      TerminalLeavesRecognize grammar tokens [] position position
  | cons
      (tokenIndexEq : tokenIndex = start / 2)
      (kindBound : semanticKind < grammar.grammar.n_kinds)
      (scanned : scanTerminal grammar tokens start semanticKind = some middle)
      (tail : TerminalLeavesRecognize grammar tokens leaves middle finish) :
      TerminalLeavesRecognize grammar tokens
        ((tokenIndex, semanticKind) :: leaves) start finish

theorem TerminalLeavesRecognize.append
    (initial : TerminalLeavesRecognize grammar tokens left start middle)
    (suffix : TerminalLeavesRecognize grammar tokens right middle finish) :
    TerminalLeavesRecognize grammar tokens (left ++ right) start finish := by
  induction initial with
  | empty => simpa using suffix
  | cons tokenIndexEq kindBound scanned tail ih =>
      rename_i tokenId nodeStart kind nodeMiddle remaining nodeFinish
      exact .cons tokenIndexEq kindBound scanned (ih suffix)

mutual

  def parseTreeRecognition_terminalLeavesRecognize
      (recognized : ParseTreeRecognizesSymbol grammar tokens
        tree symbol start finish) :
      TerminalLeavesRecognize grammar tokens
        (parseTreeTerminalLeaves tree) start finish :=
    match recognized with
    | .terminal tokenIndexEq kindBound scanned =>
        by
          simpa [parseTreeTerminalLeaves] using
            TerminalLeavesRecognize.cons tokenIndexEq kindBound scanned (.empty _)
    | .nonterminal _ _ _ childrenRecognize =>
        by
          simpa [parseTreeTerminalLeaves] using
            parseTreesRecognition_terminalLeavesRecognize childrenRecognize

  def parseTreesRecognition_terminalLeavesRecognize
      (recognized : ParseTreesRecognizeSequence grammar tokens
        trees symbols start finish) :
      TerminalLeavesRecognize grammar tokens
        (trees.flatMap parseTreeTerminalLeaves) start finish :=
    match recognized with
    | .empty => .empty _
    | .cons head tail =>
        (parseTreeRecognition_terminalLeavesRecognize head).append
          (parseTreesRecognition_terminalLeavesRecognize tail)

end

theorem MaterializedParse.terminalLeavesRecognize
    (parse : MaterializedParse grammar tokens) :
    TerminalLeavesRecognize grammar tokens
      (parseTreeTerminalLeaves parse.tree) 0 (finalPosition tokens.length) :=
  parseTreeRecognition_terminalLeavesRecognize parse.recognizes

def packSemanticKinds (inner outer : Nat) : Nat :=
  packedFlag + inner + outer * packedKindBase

theorem packSemanticKinds_isPacked
    (innerBound : inner < packedKindBase)
    (outerBound : outer < packedKindBase) :
    isPackedSemanticKind (packSemanticKinds inner outer) = true := by
  unfold packedKindBase at innerBound outerBound
  have lower : 2147483648 ≤ 2147483648 + inner + outer * 32768 := by omega
  have upper : 2147483648 + inner + outer * 32768 < 4294967296 := by
    omega
  simp [isPackedSemanticKind, packSemanticKinds, packedFlag, packedLimit,
    packedKindBase, lower, upper]

@[simp] theorem packedInnerKind_packSemanticKinds
    (innerBound : inner < packedKindBase) :
    packedInnerKind (packSemanticKinds inner outer) = inner := by
  have innerSmall : inner < 32768 := by
    simpa [packedKindBase] using innerBound
  rw [packedInnerKind, packSemanticKinds]
  change (2147483648 + inner + outer * 32768) % 32768 = inner
  rw [Nat.add_mul_mod_self_right]
  rw [Nat.add_mod]
  have flagMod : 2147483648 % 32768 = 0 := by decide
  rw [flagMod, Nat.mod_eq_of_lt innerSmall]
  simpa only [Nat.zero_add] using Nat.mod_eq_of_lt innerSmall

@[simp] theorem packedOuterKind_packSemanticKinds
    (innerBound : inner < packedKindBase)
    (outerBound : outer < packedKindBase) :
    packedOuterKind (packSemanticKinds inner outer) = outer := by
  rw [packedOuterKind, packSemanticKinds]
  change ((2147483648 + inner + outer * 32768) / 32768) % 32768 = outer
  rw [Nat.add_mul_div_right]
  · have innerSmall : inner < 32768 := innerBound
    have outerSmall : outer < 32768 := outerBound
    have baseQuotient : (2147483648 + inner) / 32768 = 65536 := by
      apply Nat.div_eq_of_lt_le
      · omega
      · omega
    rw [baseQuotient]
    rw [Nat.add_mod]
    have quotientMod : 65536 % 32768 = 0 := by decide
    rw [quotientMod, Nat.mod_eq_of_lt outerSmall]
    simpa only [Nat.zero_add] using Nat.mod_eq_of_lt outerSmall
  · decide

/-- A successful parser terminal scan has exactly one of the two supported
    shapes: an ordinary whole-token step, or one half of the designated split
    token. -/
theorem scanTerminal_some_shape
    (scanned : scanTerminal grammar tokens start semanticKind = some finish) :
    ∃ rawKind canonicalKind,
      tokens[start / 2]? = some rawKind ∧
      grammar.grammar.canonical_kinds[semanticKind]? = some canonicalKind ∧
      ((start % 2 = 0 ∧ rawKind = canonicalKind ∧ finish = start + 2) ∨
       (rawKind = grammar.grammar.split_token_kind ∧
        canonicalKind = grammar.grammar.split_component_kind ∧
        finish = start + 1)) := by
  unfold scanTerminal at scanned
  split at scanned <;> try contradiction
  rename_i rawKind canonicalKind tokenFound canonicalFound
  refine ⟨rawKind, canonicalKind, tokenFound, canonicalFound, ?_⟩
  unfold scanTerminalStep at scanned
  split at scanned <;> split at scanned <;> simp_all

/-- Replay the checked terminal frontier as a small state machine. At an even
    lattice position there is no pending split half. Consuming the first half
    of a split token stores its semantic kind; consuming the odd-position
    second half emits one packed artifact row. The function uses
    `scanTerminal` itself, so it cannot silently acquire a second definition
    of contextual token classification. -/
def encodeTerminalLeavesState
    (grammar : IndexedGrammar) (tokens : List Nat) :
    Nat → Option Nat → List (Nat × Nat) →
      Option (List Nat × Option Nat)
  | _, pending, [] => some ([], pending)
  | position, pending, (tokenIndex, semanticKind) :: leaves => do
      if tokenIndex != position / 2 then none else
      let next ← scanTerminal grammar tokens position semanticKind
      match pending with
      | none =>
          if next = position + 2 then
            let encoded ← encodeTerminalLeavesState grammar tokens next none leaves
            some (semanticKind :: encoded.1, encoded.2)
          else if next = position + 1 then
            encodeTerminalLeavesState grammar tokens next (some semanticKind) leaves
          else
            none
      | some innerKind =>
          if next != position + 1 then none else
          let encoded ← encodeTerminalLeavesState grammar tokens next none leaves
          some (packSemanticKinds innerKind semanticKind :: encoded.1, encoded.2)

/-- The pending half is present exactly at the one odd lattice boundary inside
    a physical split token. -/
inductive PendingSplitMatches : Nat → Option Nat → Prop where
  | even (positionEven : position % 2 = 0) :
      PendingSplitMatches position none
  | odd (positionOdd : position % 2 = 1) :
      PendingSplitMatches position (some innerKind)

def pendingSplitWidth : Option Nat → Nat
  | none => 0
  | some _ => 1

/-- Replaying a recognized terminal frontier cannot fail, and it preserves the
    pending-half/parity invariant. -/
theorem TerminalLeavesRecognize.encodeTerminalLeavesState_succeeds
    (recognized : TerminalLeavesRecognize grammar tokens leaves start finish)
    (pendingMatches : PendingSplitMatches start pending) :
    ∃ semanticKinds finalPending,
      encodeTerminalLeavesState grammar tokens start pending leaves =
        some (semanticKinds, finalPending) ∧
      PendingSplitMatches finish finalPending ∧
      start + 2 * semanticKinds.length + pendingSplitWidth finalPending =
        finish + pendingSplitWidth pending := by
  induction recognized generalizing pending
  case empty position =>
      exact ⟨[], pending, by simp [encodeTerminalLeavesState], pendingMatches,
        by simp⟩
  case cons tokenId nodeStart kind nodeMiddle remaining nodeFinish
      tokenIndexEq kindBound scanned tail ih =>
      obtain ⟨rawKind, canonicalKind, tokenFound, canonicalFound,
          whole | split⟩ := scanTerminal_some_shape scanned
      · rcases whole with ⟨startEven, rawCanonical, middleEq⟩
        cases pendingMatches with
        | even _ =>
            have middleEven : nodeMiddle % 2 = 0 := by omega
            obtain ⟨semanticKinds, finalPending, encoded, finalMatches, spanSize⟩ :=
              ih (.even middleEven)
            refine ⟨kind :: semanticKinds, finalPending, ?_, finalMatches, ?_⟩
            simp [encodeTerminalLeavesState, tokenIndexEq, scanned, middleEq]
            rw [← middleEq, encoded]
            simp
            simp [pendingSplitWidth] at spanSize ⊢
            omega
        | odd startOdd => omega
      · rcases split with ⟨rawSplit, canonicalSplit, middleEq⟩
        cases pendingMatches with
        | even startEven =>
            have middleOdd : nodeMiddle % 2 = 1 := by omega
            obtain ⟨semanticKinds, finalPending, encoded, finalMatches, spanSize⟩ :=
              ih (.odd (innerKind := kind) middleOdd)
            refine ⟨semanticKinds, finalPending, ?_, finalMatches, ?_⟩
            simp [encodeTerminalLeavesState, tokenIndexEq, scanned, middleEq]
            simpa [middleEq] using encoded
            simp [pendingSplitWidth] at spanSize ⊢
            omega
        | @odd innerKind startOdd =>
            have middleEven : nodeMiddle % 2 = 0 := by omega
            obtain ⟨semanticKinds, finalPending, encoded, finalMatches, spanSize⟩ :=
              ih (.even middleEven)
            refine ⟨packSemanticKinds innerKind kind :: semanticKinds,
              finalPending, ?_, finalMatches, ?_⟩
            simp [encodeTerminalLeavesState, tokenIndexEq, scanned, middleEq]
            rw [← middleEq, encoded]
            simp
            simp [pendingSplitWidth] at spanSize ⊢
            omega

def semanticKindsFromParseTree
    (grammar : IndexedGrammar) (tokens : List Nat)
    (tree : ParseTree) : Option (List Nat) := do
  let encoded ← encodeTerminalLeavesState grammar tokens 0 none
    (parseTreeTerminalLeaves tree)
  if encoded.2.isSome then none
  else if encoded.1.length = tokens.length then some encoded.1
  else none

def MaterializedParse.semanticKinds?
    (parse : MaterializedParse grammar tokens) : Option (List Nat) :=
  semanticKindsFromParseTree grammar tokens parse.tree

/-- Complete checked parses always produce exactly one semantic artifact row
    per physical token and cannot end with an unmatched split half. -/
theorem MaterializedParse.semanticKinds?_eq_some
    (parse : MaterializedParse grammar tokens) :
    ∃ semanticKinds,
      MaterializedParse.semanticKinds? parse = some semanticKinds ∧
      semanticKinds.length = tokens.length := by
  obtain ⟨semanticKinds, finalPending, encoded, finalMatches, spanSize⟩ :=
    TerminalLeavesRecognize.encodeTerminalLeavesState_succeeds
      (MaterializedParse.terminalLeavesRecognize parse) (.even (by decide))
  cases finalMatches with
  | even finishEven =>
      have lengthEq : semanticKinds.length = tokens.length := by
        simp [pendingSplitWidth, finalPosition] at spanSize
        omega
      refine ⟨semanticKinds, ?_, lengthEq⟩
      simp [MaterializedParse.semanticKinds?, semanticKindsFromParseTree,
        encoded, lengthEq]
  | odd finishOdd =>
      simp [finalPosition] at finishOdd

end Lanius.Extraction
