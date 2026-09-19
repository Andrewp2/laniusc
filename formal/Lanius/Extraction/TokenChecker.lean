import Lanius.Compiler.LexerCanonical
import Lanius.Extraction.Artifact

namespace Lanius.Extraction

open Lanius.Compiler
open Lanius.Compiler.Lexer

def decodeByte (value : Nat) : Option Byte :=
  if inRange : value < 256 then some ⟨value, inRange⟩ else none

def decodeBytes (values : List Nat) : Option (List Byte) :=
  values.mapM decodeByte

theorem decodeBytes_append (left right : List Nat) :
    decodeBytes (left ++ right) =
      match decodeBytes left, decodeBytes right with
      | some decodedLeft, some decodedRight =>
          some (decodedLeft ++ decodedRight)
      | _, _ => none := by
  simp only [decodeBytes, List.mapM_append]
  cases List.mapM decodeByte left <;> cases List.mapM decodeByte right <;> rfl

def decodeSingleSource : List SourceFile → Option (List Byte)
  | [source] => decodeBytes source.bytes
  | _ => none

def decodeToken : Token → Option RawToken
  | ⟨code, ⟨file, start, finish⟩⟩ => do
    if file != 0 then none else
    if start > finish then none else
    let kind ← TokenKind.ofGpuCode code
    pure ⟨kind, start, finish⟩

def decodeTokens (tokens : List Token) : Option (List RawToken) :=
  tokens.mapM decodeToken


/-- Prefix scanner used to split large raw-token certificates.  Unlike
`checkRawTokenTraceFrom`, it returns the unconsumed suffix instead of requiring
the segment to reach end-of-file. -/
def scanRawTokenSegment : List Byte → Nat → List RawToken →
    Option (List Byte × Nat)
  | remaining, offset, [] => some (remaining, offset)
  | remaining, offset, token :: tokens =>
      match scanOneAt remaining 0 with
      | .failure _ => none
      | .token relative =>
          if relative.shift offset == token then
            scanRawTokenSegment (remaining.drop relative.finish)
              (offset + relative.finish) tokens
          else none

def checkRawTokenTraceFrom : List Byte → Nat → List RawToken → Bool
  | remaining, offset, tokens =>
      match scanRawTokenSegment remaining offset tokens with
      | some (suffix, _) => suffix.isEmpty
      | none => false

def checkRawTokenTrace (source : List Byte) (tokens : List RawToken) : Bool :=
  checkRawTokenTraceFrom source 0 tokens

theorem scanRawTokenSegment_append (remaining : List Byte) (offset : Nat)
    (left right : List RawToken) :
    scanRawTokenSegment remaining offset (left ++ right) =
      match scanRawTokenSegment remaining offset left with
      | none => none
      | some (nextRemaining, nextOffset) =>
          scanRawTokenSegment nextRemaining nextOffset right := by
  induction left generalizing remaining offset with
  | nil => rfl
  | cons token tokens inductionHypothesis =>
      simp only [List.cons_append, scanRawTokenSegment]
      cases scanned : scanOneAt remaining 0 with
      | failure => simp
      | token relative =>
          cases matched : (relative.shift offset == token) with
          | false => simp [matched]
          | true =>
              simp [matched, inductionHypothesis]


theorem checkRawTokenTraceFrom_eq_segment
    (remaining : List Byte) (offset : Nat) (tokens : List RawToken) :
    checkRawTokenTraceFrom remaining offset tokens =
      match scanRawTokenSegment remaining offset tokens with
      | some (nextRemaining, _) => nextRemaining.isEmpty
      | none => false := by
  rfl

private theorem scanRawTokenSegment_sound
    (remainingEquals : remaining = source.drop offset)
    (accepted : scanRawTokenSegment remaining offset tokens = some ([], finish)) :
    RawLexes source offset (.success tokens) := by
  induction tokens generalizing remaining offset with
  | nil =>
      obtain ⟨rfl, rfl⟩ := Option.some.inj (by
        simpa only [scanRawTokenSegment] using accepted)
      have lengths := congrArg List.length remainingEquals
      simp at lengths
      exact .done (by omega)
  | cons token tokens inductionHypothesis =>
      simp only [scanRawTokenSegment] at accepted
      cases relativeFound : scanOneAt remaining 0 with
      | failure error => simp [relativeFound] at accepted
      | token relative =>
          simp only [relativeFound] at accepted
          cases matched : (relative.shift offset == token) with
          | false => simp [matched] at accepted
          | true =>
              cases beq_iff_eq.mp matched
              have scanned : scanOne source offset = .token (relative.shift offset) := by
                unfold scanOne
                rw [← remainingEquals, relativeFound]
                rfl
              have beforeEnd : offset < source.length := by
                have sourceLengths := congrArg List.length remainingEquals; simp at sourceLengths
                have remainingNonempty := scanOneAt_token_before_end relativeFound
                omega
              have tailEquals : remaining.drop relative.finish =
                  source.drop (offset + relative.finish) := by
                simpa [remainingEquals, List.drop_drop]
              simp only [beq_self_eq_true, ↓reduceIte] at accepted
              exact .accepted beforeEnd scanned
                (inductionHypothesis tailEquals accepted)

theorem checkRawTokenTraceFrom_sound
    (remainingEquals : remaining = source.drop offset)
    (accepted : checkRawTokenTraceFrom remaining offset tokens = true) :
    RawLexes source offset (.success tokens) := by
  unfold checkRawTokenTraceFrom at accepted
  cases scanned : scanRawTokenSegment remaining offset tokens with
  | none => simp [scanned] at accepted
  | some result =>
      cases result with
      | mk suffix finish =>
          have suffixEmpty : suffix = [] := by simpa [scanned] using accepted
          subst suffix
          exact scanRawTokenSegment_sound remainingEquals scanned

theorem checkRawTokenTrace_sound
    (accepted : checkRawTokenTrace source tokens = true) :
    RawLexes source 0 (.success tokens) := by
  exact checkRawTokenTraceFrom_sound (source := source) (remaining := source)
    (by simp) accepted

def tokenByteValuesFromRemaining
    (remaining : List Byte) (width : Nat) : List Nat :=
  (remaining.take width).map Fin.val

def canonicalKindFromRemaining
    (remaining : List Byte) (width : Nat) (token : RawToken) : TokenKind :=
  if token.kind = .identifier then
    (exactKeywordKind (tokenByteValuesFromRemaining remaining width)
      keywordRules).getD .identifier
  else token.kind

def filterRetagTokensFromTrace :
    List Byte → Nat → List RawToken → List RawToken
  | _, _, [] => []
  | remaining, offset, token :: tokens =>
      let width := token.finish - offset
      let tail := filterRetagTokensFromTrace (remaining.drop width)
        token.finish tokens
      if isTriviaKind token.kind then tail
      else { token with kind :=
        canonicalKindFromRemaining remaining width token } :: tail

def canonicalizeTokensFromTrace
    (source : List Byte) (tokens : List RawToken) : List RawToken :=
  retagInclusiveRanges (filterRetagTokensFromTrace source 0 tokens)

theorem canonicalKindFromRemaining_eq
    (remainingEquals : remaining = source.drop offset)
    (tokenStarts : token.start = offset) :
    canonicalKindFromRemaining remaining (token.finish - offset) token =
      canonicalKind source token := by
  simp [canonicalKindFromRemaining, canonicalKind, tokenByteValuesFromRemaining,
    tokenByteValues, remainingEquals, tokenStarts]

theorem filterRetagTokensFromTrace_eq
    (trace : RawTokenPrefix source offset tokens finish) :
    filterRetagTokensFromTrace (source.drop offset) offset tokens =
      filterRetagTokens source tokens := by
  induction trace with
  | empty => rfl
  | @accepted offset token tokens finish beforeEnd scanned tail
      inductionHypothesis =>
      have tokenStarts : token.start = offset := scanOne_token_start scanned
      have advances : offset < token.finish := scanOne_token_advances scanned
      have kindEquals := canonicalKindFromRemaining_eq
        (remaining := source.drop offset) (source := source) rfl tokenStarts
      have tailRemaining :
          (source.drop offset).drop (token.finish - offset) =
            source.drop token.finish := by
        rw [List.drop_drop]
        congr 1 <;> omega
      by_cases trivia : isTriviaKind token.kind = true <;>
        simp [filterRetagTokensFromTrace, filterRetagTokens,
          canonicalizeToken, trivia, tailRemaining, inductionHypothesis,
          kindEquals]

theorem canonicalizeTokensFromTrace_eq
    (trace : RawTokenPrefix source 0 tokens finish) :
    canonicalizeTokensFromTrace source tokens =
      canonicalizeTokens source tokens := by
  unfold canonicalizeTokensFromTrace canonicalizeTokens
  simpa only [List.drop_zero] using
    congrArg retagInclusiveRanges (filterRetagTokensFromTrace_eq trace)

/-- The exact bytes have the claimed canonical stream. When raw token rows
are supplied, retain their checked lexical meaning too: later resource proofs
must not rerun the lexer or trust an unauthenticated raw-token count. -/
def TokenArtifactValid (artifact : Artifact) : Prop :=
  ∃ source tokens,
    artifact.schema_version = schemaVersion ∧
    decodeSingleSource artifact.sources = some source ∧
    decodeTokens artifact.tokens = some tokens ∧
    lexCanonical source = .success tokens ∧
    ∀ rawRows, artifact.raw_tokens = some rawRows →
      ∃ rawTokens, decodeTokens rawRows = some rawTokens ∧ lexRaw source = .success rawTokens


/-- Executable checker for the source/token portion of an extraction artifact. -/
def checkTokenArtifact (artifact : Artifact) : Bool :=
  if artifact.schema_version != schemaVersion then false
  else match decodeSingleSource artifact.sources, artifact.raw_tokens,
      decodeTokens artifact.tokens with
    | some source, some rawRows, some tokens =>
        match decodeTokens rawRows with
        | some rawTokens =>
            checkRawTokenTrace source rawTokens &&
            canonicalizeTokensFromTrace source rawTokens == tokens
        | none => false
    | some source, none, some tokens => lexCanonical source == .success tokens
    | _, _, _ => false


theorem checkTokenArtifact_sound {artifact : Artifact}
    (accepted : checkTokenArtifact artifact = true) :
    TokenArtifactValid artifact := by
  unfold checkTokenArtifact at accepted
  split at accepted
  · simp at accepted
  · rename_i versionMatches
    have versionEqual : artifact.schema_version = schemaVersion := by
      simpa using versionMatches
    split at accepted
    · rename_i source rawRows tokens sourceDecoded rawRowsFound tokensDecoded
      split at accepted
      · rename_i rawTokens rawTokensDecoded
        simp only [Bool.and_eq_true, beq_iff_eq] at accepted
        have rawTrace := checkRawTokenTrace_sound accepted.1
        have rawResult := (lexRaw_sound source).functional rawTrace
        obtain ⟨finish, rawPrefix, _⟩ := rawTrace.success_witness
        have canonicalized : canonicalizeTokens source rawTokens = tokens := by
          simpa [canonicalizeTokensFromTrace_eq rawPrefix] using accepted.2
        have canonical : lexCanonical source = .success tokens := by
          simpa [lexCanonical, rawResult, canonicalizeRawResult, canonicalized]
        refine ⟨source, tokens, versionEqual, sourceDecoded, tokensDecoded, canonical, ?_⟩
        intro rows found
        rcases Option.some.inj (rawRowsFound.symm.trans found) with rfl
        exact ⟨rawTokens, rawTokensDecoded, rawResult⟩
      · simp at accepted
    · rename_i source tokens sourceDecoded rawRowsMissing tokensDecoded
      exact ⟨source, tokens, versionEqual, sourceDecoded, tokensDecoded,
        by simpa using accepted, by simp [rawRowsMissing]⟩
    · simp at accepted

private def emptyArtifact (sourceBytes : List Nat) (tokens : List Token) : Artifact :=
  {
    schema_version := schemaVersion
    sources := [{ path := "test.lani", bytes := sourceBytes }]
    tokens := tokens
    raw_tokens := none
    semantic_token_kinds := []
    parse_nodes := []
    parse_root := none
    surface := none
    resolutions := []
    types := []
    core_program := none
    lowering := []
  }

private def letArtifact : Artifact :=
  emptyArtifact [108, 101, 116, 32, 120, 32, 61, 32, 49, 50, 59] [
    ⟨68, ⟨0, 0, 3⟩⟩,
    ⟨1, ⟨0, 4, 5⟩⟩,
    ⟨8, ⟨0, 6, 7⟩⟩,
    ⟨2, ⟨0, 8, 10⟩⟩,
    ⟨37, ⟨0, 10, 11⟩⟩
  ]

example : checkTokenArtifact letArtifact = true := by native_decide

example :
    checkTokenArtifact
      (emptyArtifact [108, 101, 116] [⟨1, ⟨0, 0, 3⟩⟩]) = false := by
  native_decide

end Lanius.Extraction
