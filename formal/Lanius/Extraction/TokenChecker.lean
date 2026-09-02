import Lanius.Compiler.LexerCanonical
import Lanius.Extraction.Artifact

namespace Lanius.Extraction

open Lanius.Compiler
open Lanius.Compiler.Lexer

def decodeByte (value : Nat) : Option Byte :=
  if inRange : value < 256 then some ⟨value, inRange⟩ else none

def decodeBytes (values : List Nat) : Option (List Byte) :=
  values.mapM decodeByte

def decodeSingleSource : List SourceFile → Option (List Byte)
  | [source] => decodeBytes source.bytes
  | _ => none

def decodeToken (token : Token) : Option RawToken := do
  if token.span.file != 0 then none else
  if token.span.start > token.span.finish then none else
  let kind ← TokenKind.ofGpuCode token.kind
  pure ⟨kind, token.span.start, token.span.finish⟩

def decodeTokens (tokens : List Token) : Option (List RawToken) :=
  tokens.mapM decodeToken

def checkRawTokenTraceFrom : List Byte → Nat → List RawToken → Bool
  | remaining, _, [] => remaining.isEmpty
  | remaining, offset, token :: tokens =>
      match scanOneAt remaining 0 with
      | .failure _ => false
      | .token relative =>
          relative.shift offset == token &&
          checkRawTokenTraceFrom (remaining.drop relative.finish)
            (offset + relative.finish) tokens

def checkRawTokenTrace (source : List Byte) (tokens : List RawToken) : Bool :=
  checkRawTokenTraceFrom source 0 tokens

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
      | failure error => simp only [scanned]
      | token relative =>
          simp only [scanned]
          cases matched : (relative.shift offset == token) with
          | false => simp only [matched, Bool.false_eq_true, ↓reduceIte]
          | true =>
              simp only [matched, ↓reduceIte]
              exact inductionHypothesis _ _

theorem checkRawTokenTraceFrom_eq_segment
    (remaining : List Byte) (offset : Nat) (tokens : List RawToken) :
    checkRawTokenTraceFrom remaining offset tokens =
      match scanRawTokenSegment remaining offset tokens with
      | some (nextRemaining, _) => nextRemaining.isEmpty
      | none => false := by
  induction tokens generalizing remaining offset with
  | nil => rfl
  | cons token tokens inductionHypothesis =>
      simp only [checkRawTokenTraceFrom, scanRawTokenSegment]
      cases scanned : scanOneAt remaining 0 with
      | failure error => simp only [scanned]
      | token relative =>
          simp only [scanned]
          cases matched : (relative.shift offset == token) with
          | false =>
              simp only [matched, Bool.false_and, Bool.false_eq_true,
                ↓reduceIte]
          | true =>
              simp only [matched, Bool.true_and, ↓reduceIte]
              exact inductionHypothesis _ _

theorem checkRawTokenTraceFrom_sound
    (remainingEquals : remaining = source.drop offset)
    (accepted : checkRawTokenTraceFrom remaining offset tokens = true) :
    RawLexes source offset (.success tokens) := by
  induction tokens generalizing remaining offset with
  | nil =>
      simp [checkRawTokenTraceFrom] at accepted
      have lengths := congrArg List.length remainingEquals
      simp [accepted] at lengths
      exact .done (by omega)
  | cons token tokens inductionHypothesis =>
      unfold checkRawTokenTraceFrom at accepted
      cases relativeFound : scanOneAt remaining 0 with
      | failure error => simp [relativeFound] at accepted
      | token relative =>
          simp only [relativeFound, Bool.and_eq_true, beq_iff_eq] at accepted
          have sameToken : relative.shift offset = token := accepted.1
          subst token
          have scanned :
              scanOne source offset = .token (relative.shift offset) := by
            unfold scanOne
            rw [← remainingEquals, relativeFound]
            rfl
          have remainingNonempty : 0 < remaining.length :=
            scanOneAt_token_before_end relativeFound
          have sourceLengths := congrArg List.length remainingEquals
          simp at sourceLengths
          have beforeEnd : offset < source.length := by omega
          have tailEquals :
              remaining.drop relative.finish =
                source.drop (offset + relative.finish) := by
            rw [remainingEquals, List.drop_drop]
          exact .accepted beforeEnd scanned
            (inductionHypothesis tailEquals accepted.2)

theorem checkRawTokenTrace_sound
    (accepted : checkRawTokenTrace source tokens = true) :
    RawLexes source 0 (.success tokens) := by
  apply checkRawTokenTraceFrom_sound (source := source) (remaining := source)
  · simp
  · exact accepted

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
        (remaining := source.drop offset) (source := source)
        (offset := offset) (token := token) rfl tokenStarts
      have tailRemaining :
          (source.drop offset).drop (token.finish - offset) =
            source.drop token.finish := by
        rw [List.drop_drop]
        congr 1
        omega
      by_cases trivia : isTriviaKind token.kind = true
      · simp [filterRetagTokensFromTrace, filterRetagTokens,
          canonicalizeToken, trivia, tailRemaining, inductionHypothesis]
      · simp [filterRetagTokensFromTrace, filterRetagTokens,
          canonicalizeToken, trivia, tailRemaining, inductionHypothesis,
          kindEquals]

theorem canonicalizeTokensFromTrace_eq
    (trace : RawTokenPrefix source 0 tokens finish) :
    canonicalizeTokensFromTrace source tokens =
      canonicalizeTokens source tokens := by
  unfold canonicalizeTokensFromTrace canonicalizeTokens
  have filtered := filterRetagTokensFromTrace_eq trace
  simp at filtered
  rw [filtered]

/-- The semantic statement certified by the first extraction checker: the
    artifact's exact bytes have exactly the claimed canonical token stream. -/
def TokenArtifactValid (artifact : Artifact) : Prop :=
  ∃ source tokens,
    artifact.schema_version = schemaVersion ∧
    decodeSingleSource artifact.sources = some source ∧
    decodeTokens artifact.tokens = some tokens ∧
    lexCanonical source = .success tokens

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

/-! Independent raw-trace certificate phases.  Generated artifacts carry a
complete raw trace, so source decoding, raw scanning, and canonical retagging
can be reduced in separate modules and checked in parallel. -/

def checkTokenArtifactTraceHeader (artifact : Artifact) : Bool :=
  artifact.schema_version == schemaVersion &&
    match decodeSingleSource artifact.sources, artifact.raw_tokens,
        decodeTokens artifact.tokens with
    | some _, some rawRows, some _ => (decodeTokens rawRows).isSome
    | _, _, _ => false

def checkTokenArtifactRawTrace (artifact : Artifact) : Bool :=
  match decodeSingleSource artifact.sources, artifact.raw_tokens with
  | some source, some rawRows =>
      match decodeTokens rawRows with
      | some rawTokens => checkRawTokenTrace source rawTokens
      | none => false
  | _, _ => false

def checkTokenArtifactCanonicalTrace (artifact : Artifact) : Bool :=
  match decodeSingleSource artifact.sources, artifact.raw_tokens,
      decodeTokens artifact.tokens with
  | some source, some rawRows, some tokens =>
      match decodeTokens rawRows with
      | some rawTokens =>
          canonicalizeTokensFromTrace source rawTokens == tokens
      | none => false
  | _, _, _ => false

theorem checkTokenArtifact_of_trace_phases {artifact : Artifact}
    (header : checkTokenArtifactTraceHeader artifact = true)
    (raw : checkTokenArtifactRawTrace artifact = true)
    (canonical : checkTokenArtifactCanonicalTrace artifact = true) :
    checkTokenArtifact artifact = true := by
  unfold checkTokenArtifactTraceHeader at header
  simp only [Bool.and_eq_true, beq_iff_eq] at header
  rcases header with ⟨version, header⟩
  cases sourceFound : decodeSingleSource artifact.sources with
  | none => simp [sourceFound] at header
  | some source =>
      cases rawRowsFound : artifact.raw_tokens with
      | none => simp [sourceFound, rawRowsFound] at header
      | some rawRows =>
          cases tokensFound : decodeTokens artifact.tokens with
          | none => simp [sourceFound, rawRowsFound, tokensFound] at header
          | some tokens =>
              cases rawTokensFound : decodeTokens rawRows with
              | none =>
                  simp [sourceFound, rawRowsFound, tokensFound,
                    rawTokensFound] at header
              | some rawTokens =>
                  unfold checkTokenArtifactRawTrace at raw
                  unfold checkTokenArtifactCanonicalTrace at canonical
                  simp only [sourceFound, rawRowsFound, tokensFound,
                    rawTokensFound] at raw canonical
                  unfold checkTokenArtifact
                  simp [version, sourceFound, rawRowsFound, tokensFound,
                    rawTokensFound, raw, canonical]

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
        have rawResult : lexRaw source = .success rawTokens :=
          (lexRaw_sound source).functional rawTrace
        obtain ⟨finish, rawPrefix, _⟩ := rawTrace.success_witness
        have canonicalized : canonicalizeTokens source rawTokens = tokens := by
          rw [← canonicalizeTokensFromTrace_eq rawPrefix]
          exact accepted.2
        have canonical : lexCanonical source = .success tokens := by
          unfold lexCanonical
          rw [rawResult]
          simp [canonicalizeRawResult, canonicalized]
        exact ⟨source, tokens, versionEqual, sourceDecoded, tokensDecoded, canonical⟩
      · simp at accepted
    · rename_i source tokens sourceDecoded rawRowsMissing tokensDecoded
      exact ⟨source, tokens, versionEqual, sourceDecoded, tokensDecoded,
        by simpa using accepted⟩
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
