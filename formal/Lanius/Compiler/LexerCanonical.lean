import Lanius.Compiler.LexerStream

namespace Lanius.Compiler.Lexer

def isTriviaKind : TokenKind → Bool
  | .whitespace | .lineComment | .blockComment => true
  | _ => false

structure KeywordRule where
  spelling : List Nat
  kind : TokenKind
deriving DecidableEq, Repr

def keywordRules : List KeywordRule := [
  ⟨[112, 117, 98], .pubKeyword⟩,
  ⟨[102, 110], .fnKeyword⟩,
  ⟨[105, 110], .inKeyword⟩,
  ⟨[108, 101, 116], .letKeyword⟩,
  ⟨[102, 111, 114], .forKeyword⟩,
  ⟨[114, 101, 116, 117, 114, 110], .returnKeyword⟩,
  ⟨[105, 102], .ifKeyword⟩,
  ⟨[101, 108, 115, 101], .elseKeyword⟩,
  ⟨[119, 104, 105, 108, 101], .whileKeyword⟩,
  ⟨[98, 114, 101, 97, 107], .breakKeyword⟩,
  ⟨[99, 111, 110, 116, 105, 110, 117, 101], .continueKeyword⟩,
  ⟨[116, 114, 117, 101], .trueKeyword⟩,
  ⟨[102, 97, 108, 115, 101], .falseKeyword⟩,
  ⟨[99, 111, 110, 115, 116], .constKeyword⟩,
  ⟨[101, 110, 117, 109], .enumKeyword⟩,
  ⟨[101, 120, 116, 101, 114, 110], .externKeyword⟩,
  ⟨[105, 109, 112, 111, 114, 116], .importKeyword⟩,
  ⟨[105, 109, 112, 108], .implKeyword⟩,
  ⟨[109, 97, 116, 99, 104], .matchKeyword⟩,
  ⟨[109, 111, 100, 117, 108, 101], .moduleKeyword⟩,
  ⟨[115, 101, 108, 102], .selfKeyword⟩,
  ⟨[115, 116, 114, 117, 99, 116], .structKeyword⟩,
  ⟨[116, 114, 97, 105, 116], .traitKeyword⟩,
  ⟨[116, 121, 112, 101], .typeKeyword⟩,
  ⟨[119, 104, 101, 114, 101], .whereKeyword⟩
]

def exactKeywordKind : List Nat → List KeywordRule → Option TokenKind
  | _, [] => none
  | spelling, rule :: rest =>
      if spelling = rule.spelling then some rule.kind
      else exactKeywordKind spelling rest

theorem exactKeywordKind_deterministic
    (spelling : List Nat) (rules : List KeywordRule) {left right : Option TokenKind}
    (leftResult : exactKeywordKind spelling rules = left)
    (rightResult : exactKeywordKind spelling rules = right) :
    left = right := by
  exact leftResult.symm.trans rightResult

theorem exactKeywordKind_sound
    {spelling : List Nat} {rules : List KeywordRule} {kind : TokenKind}
    (selected : exactKeywordKind spelling rules = some kind) :
    ∃ rule, rule ∈ rules ∧ rule.spelling = spelling ∧ rule.kind = kind := by
  induction rules with
  | nil => simp [exactKeywordKind] at selected
  | cons rule rest inductionHypothesis =>
      unfold exactKeywordKind at selected
      by_cases sameSpelling : spelling = rule.spelling
      · simp [sameSpelling] at selected
        subst kind
        exact ⟨rule, by simp, sameSpelling.symm, rfl⟩
      · rw [if_neg sameSpelling] at selected
        obtain ⟨found, member, sameSpelling, sameKind⟩ :=
          inductionHypothesis selected
        exact ⟨found, by simp [member], sameSpelling, sameKind⟩

theorem keywordRules_are_not_trivia
    {rule : KeywordRule} (member : rule ∈ keywordRules) :
    isTriviaKind rule.kind = false := by
  have allKept :
      keywordRules.all (fun candidate => !isTriviaKind candidate.kind) = true := by
    native_decide
  have selected := List.all_eq_true.mp allKept rule member
  simpa using selected

def tokenByteValues (source : List Byte) (token : RawToken) : List Nat :=
  ((source.drop token.start).take (token.finish - token.start)).map Fin.val

def canonicalKind (source : List Byte) (token : RawToken) : TokenKind :=
  if token.kind = .identifier then
    (exactKeywordKind (tokenByteValues source token) keywordRules).getD .identifier
  else
    token.kind

theorem canonicalKind_non_identifier
    (source : List Byte) (token : RawToken)
    (notIdentifier : token.kind ≠ .identifier) :
    canonicalKind source token = token.kind := by
  simp [canonicalKind, notIdentifier]

theorem canonicalKind_is_not_trivia
    (source : List Byte) (token : RawToken)
    (kept : isTriviaKind token.kind = false) :
    isTriviaKind (canonicalKind source token) = false := by
  by_cases identifier : token.kind = .identifier
  · unfold canonicalKind
    rw [if_pos identifier]
    cases selected : exactKeywordKind (tokenByteValues source token) keywordRules with
    | none => simp [Option.getD, isTriviaKind]
    | some kind =>
        simp only [Option.getD]
        obtain ⟨rule, member, _, sameKind⟩ := exactKeywordKind_sound selected
        subst kind
        exact keywordRules_are_not_trivia member
  · rw [canonicalKind_non_identifier source token identifier]
    exact kept

def canonicalizeToken (source : List Byte) (token : RawToken) : Option RawToken :=
  if isTriviaKind token.kind then none
  else some { token with kind := canonicalKind source token }

def filterRetagTokens (source : List Byte) : List RawToken → List RawToken
  | [] => []
  | token :: rest =>
      match canonicalizeToken source token with
      | none => filterRetagTokens source rest
      | some canonical => canonical :: filterRetagTokens source rest

inductive Canonicalizes (source : List Byte) : List RawToken → List RawToken → Prop
  | empty : Canonicalizes source [] []
  | dropsTrivia (trivia : isTriviaKind token.kind = true)
      (tail : Canonicalizes source rest canonicalRest) :
      Canonicalizes source (token :: rest) canonicalRest
  | keepsToken (kept : isTriviaKind token.kind = false)
      (tail : Canonicalizes source rest canonicalRest) :
      Canonicalizes source (token :: rest)
        ({ token with kind := canonicalKind source token } :: canonicalRest)

theorem filterRetagTokens_spec (source : List Byte) (tokens : List RawToken) :
    Canonicalizes source tokens (filterRetagTokens source tokens) := by
  induction tokens with
  | nil => exact .empty
  | cons token rest inductionHypothesis =>
      unfold filterRetagTokens canonicalizeToken
      by_cases trivia : isTriviaKind token.kind = true
      · rw [if_pos trivia]
        exact .dropsTrivia trivia inductionHypothesis
      · have kept : isTriviaKind token.kind = false := by
          cases value : isTriviaKind token.kind <;> simp_all
        rw [if_neg trivia]
        exact .keepsToken kept inductionHypothesis

theorem Canonicalizes.executes
    {source : List Byte} {raw canonical : List RawToken}
    (derivation : Canonicalizes source raw canonical) :
    filterRetagTokens source raw = canonical := by
  induction derivation with
  | empty => rfl
  | dropsTrivia trivia tail inductionHypothesis =>
      simp [filterRetagTokens, canonicalizeToken, trivia, inductionHypothesis]
  | keepsToken kept tail inductionHypothesis =>
      simp [filterRetagTokens, canonicalizeToken, kept, inductionHypothesis]

theorem Canonicalizes.functional
    {source : List Byte} {raw left right : List RawToken}
    (leftDerivation : Canonicalizes source raw left)
    (rightDerivation : Canonicalizes source raw right) :
    left = right := by
  exact leftDerivation.executes.symm.trans rightDerivation.executes

theorem Canonicalizes.contains_no_trivia
    {source : List Byte} {raw canonical : List RawToken}
    (derivation : Canonicalizes source raw canonical) :
    ∀ token, token ∈ canonical → isTriviaKind token.kind = false := by
  induction derivation with
  | empty => simp
  | dropsTrivia _ _ inductionHypothesis => exact inductionHypothesis
  | keepsToken kept _ inductionHypothesis =>
      intro selected membership
      simp only [List.mem_cons] at membership
      rcases membership with isHead | inTail
      · subst selected
        exact canonicalKind_is_not_trivia source _ kept
      · exact inductionHypothesis selected inTail

def isInclusiveRangePair (current next : RawToken) : Bool :=
  current.kind = .dotDot && next.kind = .assign && next.start = current.finish

def retagInclusiveRanges : List RawToken → List RawToken
  | [] => []
  | [token] => [token]
  | current :: next :: rest =>
      let current :=
        if isInclusiveRangePair current next then
          { current with kind := .dotDotEqual }
        else
          current
      current :: retagInclusiveRanges (next :: rest)

inductive InclusiveRangeRetags : List RawToken → List RawToken → Prop
  | empty : InclusiveRangeRetags [] []
  | singleton (token) : InclusiveRangeRetags [token] [token]
  | inclusive (pairMatches : isInclusiveRangePair current next = true)
      (tail : InclusiveRangeRetags (next :: rest) outputTail) :
      InclusiveRangeRetags (current :: next :: rest)
        ({ current with kind := .dotDotEqual } :: outputTail)
  | ordinary (doesNotMatch : isInclusiveRangePair current next = false)
      (tail : InclusiveRangeRetags (next :: rest) outputTail) :
      InclusiveRangeRetags (current :: next :: rest) (current :: outputTail)

theorem retagInclusiveRanges_spec (tokens : List RawToken) :
    InclusiveRangeRetags tokens (retagInclusiveRanges tokens) := by
  induction tokens with
  | nil => exact .empty
  | cons current tail inductionHypothesis =>
      cases tail with
      | nil => exact .singleton current
      | cons next rest =>
          by_cases pairMatches : isInclusiveRangePair current next = true
          · simp [retagInclusiveRanges, pairMatches]
            exact .inclusive pairMatches inductionHypothesis
          · have doesNotMatch : isInclusiveRangePair current next = false := by
              cases value : isInclusiveRangePair current next <;> simp_all
            simp [retagInclusiveRanges, pairMatches]
            exact .ordinary doesNotMatch inductionHypothesis

theorem InclusiveRangeRetags.executes
    {input output : List RawToken}
    (derivation : InclusiveRangeRetags input output) :
    retagInclusiveRanges input = output := by
  induction derivation with
  | empty => rfl
  | singleton => rfl
  | inclusive pairMatches tail inductionHypothesis =>
      simp [retagInclusiveRanges, pairMatches, inductionHypothesis]
  | ordinary doesNotMatch tail inductionHypothesis =>
      simp [retagInclusiveRanges, doesNotMatch, inductionHypothesis]

theorem InclusiveRangeRetags.functional
    {input left right : List RawToken}
    (leftDerivation : InclusiveRangeRetags input left)
    (rightDerivation : InclusiveRangeRetags input right) :
    left = right := by
  exact leftDerivation.executes.symm.trans rightDerivation.executes

theorem retagInclusiveRanges_contains_no_trivia
    {tokens : List RawToken}
    (inputKept : ∀ token, token ∈ tokens → isTriviaKind token.kind = false) :
    ∀ token, token ∈ retagInclusiveRanges tokens → isTriviaKind token.kind = false := by
  induction tokens with
  | nil => simp [retagInclusiveRanges]
  | cons current tail inductionHypothesis =>
      cases tail with
      | nil =>
          simpa [retagInclusiveRanges] using inputKept
      | cons next rest =>
          intro selected membership
          simp only [retagInclusiveRanges, List.mem_cons] at membership
          rcases membership with isHead | inTail
          · subst selected
            split
            · simp [isTriviaKind]
            · exact inputKept current (by simp)
          · apply inductionHypothesis
            · intro token inNext
              exact inputKept token (by simp [inNext])
            · exact inTail

def canonicalizeTokens (source : List Byte) (tokens : List RawToken) : List RawToken :=
  retagInclusiveRanges (filterRetagTokens source tokens)

inductive CanonicalTokenStream
    (source : List Byte) : List RawToken → List RawToken → Prop
  | composed (filteredTokens : List RawToken)
      (filtered : Canonicalizes source raw filteredTokens)
      (ranges : InclusiveRangeRetags filteredTokens canonical) :
      CanonicalTokenStream source raw canonical

theorem canonicalizeTokens_spec (source : List Byte) (tokens : List RawToken) :
    CanonicalTokenStream source tokens (canonicalizeTokens source tokens) := by
  exact .composed (filterRetagTokens source tokens)
    (filterRetagTokens_spec source tokens)
    (retagInclusiveRanges_spec (filterRetagTokens source tokens))

theorem CanonicalTokenStream.functional
    {source : List Byte} {raw left right : List RawToken}
    (leftDerivation : CanonicalTokenStream source raw left)
    (rightDerivation : CanonicalTokenStream source raw right) :
    left = right := by
  cases leftDerivation with
  | composed leftFiltered leftFilter leftRanges =>
    cases rightDerivation with
    | composed rightFiltered rightFilter rightRanges =>
      have sameFiltered := leftFilter.functional rightFilter
      subst rightFiltered
      exact leftRanges.functional rightRanges

theorem canonicalizeTokens_contains_no_trivia
    (source : List Byte) (tokens : List RawToken) :
    ∀ token, token ∈ canonicalizeTokens source tokens →
      isTriviaKind token.kind = false := by
  unfold canonicalizeTokens
  apply retagInclusiveRanges_contains_no_trivia
  exact (filterRetagTokens_spec source tokens).contains_no_trivia

def canonicalizeRawResult (source : List Byte) : RawLexResult → RawLexResult
  | .success tokens => .success (canonicalizeTokens source tokens)
  | .failure accepted error =>
      .failure (canonicalizeTokens source accepted) error
  | .fuelExhausted accepted offset =>
      .fuelExhausted (canonicalizeTokens source accepted) offset

def lexCanonical (source : List Byte) : RawLexResult :=
  canonicalizeRawResult source (lexRaw source)

theorem lexCanonical_deterministic
    (source : List Byte) {left right : RawLexResult}
    (leftResult : lexCanonical source = left)
    (rightResult : lexCanonical source = right) :
    left = right := by
  exact leftResult.symm.trans rightResult

theorem lexCanonical_ne_exhausted (source : List Byte) :
    ∀ acceptedPrefix exhaustedAt,
      lexCanonical source ≠ .fuelExhausted acceptedPrefix exhaustedAt := by
  intro acceptedPrefix exhaustedAt exhausted
  unfold lexCanonical canonicalizeRawResult at exhausted
  cases rawResult : lexRaw source with
  | success tokens => simp [rawResult] at exhausted
  | failure accepted error => simp [rawResult] at exhausted
  | fuelExhausted rawPrefix rawOffset =>
      exact lexRaw_ne_exhausted source rawPrefix rawOffset rawResult

theorem lexCanonical_failure_origin
    {source : List Byte} {acceptedPrefix : List RawToken} {errorOffset : Nat}
    (result : lexCanonical source = .failure acceptedPrefix errorOffset) :
    ∃ rawPrefix,
      lexRaw source = .failure rawPrefix errorOffset ∧
      canonicalizeTokens source rawPrefix = acceptedPrefix := by
  unfold lexCanonical canonicalizeRawResult at result
  cases rawResult : lexRaw source with
  | success tokens => simp [rawResult] at result
  | failure rawPrefix rawError =>
      simp [rawResult] at result
      rcases result with ⟨prefixEqual, errorEqual⟩
      subst acceptedPrefix
      subst errorOffset
      exact ⟨rawPrefix, rfl, rfl⟩
  | fuelExhausted rawPrefix rawOffset => simp [rawResult] at result

theorem lexCanonical_success_contains_no_trivia
    {source : List Byte} {tokens : List RawToken}
    (result : lexCanonical source = .success tokens) :
    ∀ token, token ∈ tokens → isTriviaKind token.kind = false := by
  unfold lexCanonical canonicalizeRawResult at result
  cases rawResult : lexRaw source with
  | success rawTokens =>
      simp [rawResult] at result
      subst tokens
      exact canonicalizeTokens_contains_no_trivia source rawTokens
  | failure accepted error => simp [rawResult] at result
  | fuelExhausted accepted offset => simp [rawResult] at result

theorem lexCanonical_keywords_and_trivia :
    lexCanonical ([108, 101, 116, 32, 108, 101, 116, 116, 101, 114,
      32, 102, 110] : List Byte) =
      .success [
        ⟨.letKeyword, 0, 3⟩,
        ⟨.identifier, 4, 10⟩,
        ⟨.fnKeyword, 11, 13⟩
      ] := by
  native_decide

theorem lexCanonical_inclusive_range_retag :
    lexCanonical ([49, 46, 46, 61, 50] : List Byte) =
      .success [
        ⟨.integer, 0, 1⟩,
        ⟨.dotDotEqual, 1, 3⟩,
        ⟨.assign, 3, 4⟩,
        ⟨.integer, 4, 5⟩
      ] := by
  native_decide

end Lanius.Compiler.Lexer
