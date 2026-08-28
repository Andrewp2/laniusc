import Lanius.Basic

namespace Lanius.Compiler.Lexer

/-- A source byte. Lanius source locations and token spans are byte-based, as
    they are in the GPU compiler. -/
abbrev Byte := Fin 256

inductive StartClass where
  | identifier
  | decimalNumber
  | whitespace
  | symbol
  | stringLiteral
  | characterLiteral
  | invalid
deriving DecidableEq, Repr

/-- Stable tags used by the executable Lanius implementation. The current
    x86 backend does not yet emit enum-valued returns, so the compiler source
    uses this explicit representation at its module boundary. -/
def StartClass.code : StartClass → Nat
  | .identifier => 1
  | .decimalNumber => 2
  | .whitespace => 3
  | .symbol => 4
  | .stringLiteral => 5
  | .characterLiteral => 6
  | .invalid => 7

def isIdentifierStart (byte : Byte) : Bool :=
  (97 <= byte.val && byte.val <= 122) ||
    (65 <= byte.val && byte.val <= 90) || byte.val == 95

def isDecimalDigit (byte : Byte) : Bool :=
  48 <= byte.val && byte.val <= 57

def isIdentifierContinue (byte : Byte) : Bool :=
  isIdentifierStart byte || isDecimalDigit byte

def isWhitespace (byte : Byte) : Bool :=
  byte.val == 32 || byte.val == 9 || byte.val == 10 || byte.val == 13

def symbolBytes : List Nat :=
  [40, 41, 43, 42, 61, 45, 47, 33, 91, 93, 123, 125,
   60, 62, 38, 124, 37, 94, 126, 44, 59, 58, 63, 46]

def isSymbolStart (byte : Byte) : Bool :=
  symbolBytes.contains byte.val

/-- Executable specification of start-byte classification. Its branch order
    is observable because quotes have dedicated scanners rather than being
    ordinary punctuation. `LexerProgram` separately proves that executing the
    represented Lanius function implements this definition. -/
def classifyStart (byte : Byte) : StartClass :=
  if isIdentifierStart byte then .identifier
  else if isDecimalDigit byte then .decimalNumber
  else if isWhitespace byte then .whitespace
  else if byte.val == 34 then .stringLiteral
  else if byte.val == 39 then .characterLiteral
  else if isSymbolStart byte then .symbol
  else .invalid

def classifyStartCode (byte : Byte) : Nat :=
  (classifyStart byte).code

/-- Declarative start-byte classification. This does not call the executable
    classifier, so equivalence establishes both completeness and exclusivity
    of its branch structure. -/
def StartsAs (byte : Byte) : StartClass → Prop
  | .identifier => isIdentifierStart byte = true
  | .decimalNumber =>
      isIdentifierStart byte = false ∧ isDecimalDigit byte = true
  | .whitespace =>
      isIdentifierStart byte = false ∧ isDecimalDigit byte = false ∧
      isWhitespace byte = true
  | .stringLiteral =>
      isIdentifierStart byte = false ∧ isDecimalDigit byte = false ∧
      isWhitespace byte = false ∧ byte.val = 34
  | .characterLiteral =>
      isIdentifierStart byte = false ∧ isDecimalDigit byte = false ∧
      isWhitespace byte = false ∧ byte.val != 34 ∧ byte.val = 39
  | .symbol =>
      isIdentifierStart byte = false ∧ isDecimalDigit byte = false ∧
      isWhitespace byte = false ∧ byte.val != 34 ∧ byte.val != 39 ∧
      isSymbolStart byte = true
  | .invalid =>
      isIdentifierStart byte = false ∧
      isDecimalDigit byte = false ∧
      isWhitespace byte = false ∧
      byte.val != 34 ∧ byte.val != 39 ∧ isSymbolStart byte = false

instance (byte : Byte) (category : StartClass) : Decidable (StartsAs byte category) := by
  cases category <;> unfold StartsAs <;> infer_instance

/-- The executable specification returns exactly the declaratively specified
    start class. `LexerProgram.classifyStartFunction_correct` is the distinct
    implementation theorem for the represented Lanius function. -/
theorem classifyStart_spec (byte : Byte) (category : StartClass) :
    classifyStart byte = category ↔ StartsAs byte category := by
  unfold classifyStart
  by_cases identifier : isIdentifierStart byte = true
  · cases category <;> simp [identifier, StartsAs]
  by_cases decimal : isDecimalDigit byte = true
  · cases category <;> simp [identifier, decimal, StartsAs]
  by_cases whitespace : isWhitespace byte = true
  · cases category <;> simp [identifier, decimal, whitespace, StartsAs]
  by_cases stringQuote : byte.val = 34
  · cases category <;>
      simp [identifier, decimal, whitespace, stringQuote, StartsAs]
  by_cases characterQuote : byte.val = 39
  · cases category <;>
      simp [identifier, decimal, whitespace, characterQuote, StartsAs]
  by_cases symbol : isSymbolStart byte = true
  · cases category <;>
      simp [identifier, decimal, whitespace, stringQuote, characterQuote, symbol, StartsAs]
  · cases category <;>
      simp [identifier, decimal, whitespace, stringQuote, characterQuote, symbol, StartsAs]

theorem StartClass.code_injective : Function.Injective StartClass.code := by
  intro left right equalCodes
  cases left <;> cases right <;> simp [StartClass.code] at equalCodes <;> rfl

/-- Function-level contract for the representation actually returned by the
    Lanius source. -/
theorem classifyStartCode_spec (byte : Byte) (category : StartClass) :
    classifyStartCode byte = category.code ↔ StartsAs byte category := by
  rw [classifyStartCode, StartClass.code_injective.eq_iff, classifyStart_spec]

theorem StartsAs.functional
    {byte : Byte} {left right : StartClass}
    (leftMatches : StartsAs byte left) (rightMatches : StartsAs byte right) :
    left = right := by
  rw [← classifyStart_spec] at leftMatches rightMatches
  exact leftMatches.symm.trans rightMatches

theorem classifyStart_deterministic
    (byte : Byte) {left right : StartClass}
    (leftResult : classifyStart byte = left)
    (rightResult : classifyStart byte = right) :
    left = right := by
  exact leftResult.symm.trans rightResult

theorem classifyStart_invalid_iff (byte : Byte) :
    classifyStart byte = .invalid ↔
      isIdentifierStart byte = false ∧
      isDecimalDigit byte = false ∧
      isWhitespace byte = false ∧
      byte.val != 34 ∧ byte.val != 39 ∧ isSymbolStart byte = false := by
  exact classifyStart_spec byte .invalid

/-! ## Maximal identifier scanning -/

/-- Split the longest prefix accepted by `accept`. This is the sequential
    operation implemented by the in-Lanius compiler's scanner loops. -/
def splitPrefix (accept : Byte → Bool) : List Byte → List Byte × List Byte
  | [] => ([], [])
  | byte :: rest =>
      if accept byte then
        let split := splitPrefix accept rest
        (byte :: split.1, split.2)
      else
        ([], byte :: rest)

def BoundaryRejected (accept : Byte → Bool) : List Byte → Prop
  | [] => True
  | byte :: _ => accept byte = false

structure MaximalPrefix
    (accept : Byte → Bool) (input acceptedPrefix suffix : List Byte) : Prop where
  reconstructs : acceptedPrefix ++ suffix = input
  accepts : ∀ byte, byte ∈ acceptedPrefix → accept byte = true
  stopsAtFirstRejection : BoundaryRejected accept suffix

theorem splitPrefix_reconstructs (accept : Byte → Bool) (input : List Byte) :
    (splitPrefix accept input).1 ++ (splitPrefix accept input).2 = input := by
  induction input with
  | nil => rfl
  | cons byte rest inductionHypothesis =>
      simp only [splitPrefix]
      by_cases accepted : accept byte = true
      · simp [accepted, inductionHypothesis]
      · simp [accepted]

theorem splitPrefix_accepts (accept : Byte → Bool) (input : List Byte) :
    ∀ byte, byte ∈ (splitPrefix accept input).1 → accept byte = true := by
  induction input with
  | nil => simp [splitPrefix]
  | cons first rest inductionHypothesis =>
      simp only [splitPrefix]
      by_cases accepted : accept first = true
      · simp only [accepted, if_true, List.mem_cons]
        intro byte membership
        cases membership with
        | inl isFirst => simpa [isFirst] using accepted
        | inr inRest => exact inductionHypothesis byte inRest
      · simp [accepted]

theorem splitPrefix_stops (accept : Byte → Bool) (input : List Byte) :
    BoundaryRejected accept (splitPrefix accept input).2 := by
  induction input with
  | nil => trivial
  | cons byte rest inductionHypothesis =>
      simp only [splitPrefix]
      by_cases accepted : accept byte = true
      · simp [accepted, inductionHypothesis]
      · simp [accepted, BoundaryRejected]

theorem splitPrefix_spec (accept : Byte → Bool) (input : List Byte) :
    MaximalPrefix accept input
      (splitPrefix accept input).1 (splitPrefix accept input).2 := by
  exact {
    reconstructs := splitPrefix_reconstructs accept input
    accepts := splitPrefix_accepts accept input
    stopsAtFirstRejection := splitPrefix_stops accept input
  }

theorem splitPrefix_length_le (accept : Byte → Bool) (input : List Byte) :
    (splitPrefix accept input).1.length ≤ input.length := by
  have reconstructs := splitPrefix_reconstructs accept input
  have lengths := congrArg List.length reconstructs
  simp only [List.length_append] at lengths
  omega

def scanIdentifierEnd (source : List Byte) (start : Nat) : Nat :=
  start + 1 +
    (splitPrefix isIdentifierContinue (source.drop (start + 1))).1.length

def IdentifierEndSpec
    (source : List Byte) (start finish : Nat) : Prop :=
  let split := splitPrefix isIdentifierContinue (source.drop (start + 1))
  finish = start + 1 + split.1.length ∧
    MaximalPrefix isIdentifierContinue (source.drop (start + 1)) split.1 split.2

theorem scanIdentifierEnd_spec (source : List Byte) (start : Nat) :
    IdentifierEndSpec source start (scanIdentifierEnd source start) := by
  exact ⟨rfl, splitPrefix_spec isIdentifierContinue (source.drop (start + 1))⟩

theorem IdentifierEndSpec.functional
    {source : List Byte} {start left right : Nat}
    (leftResult : IdentifierEndSpec source start left)
    (rightResult : IdentifierEndSpec source start right) :
    left = right := by
  exact leftResult.1.trans rightResult.1.symm

theorem scanIdentifierEnd_after_start (source : List Byte) (start : Nat) :
    start < scanIdentifierEnd source start := by
  unfold scanIdentifierEnd
  omega

theorem scanIdentifierEnd_le_source_length
    (source : List Byte) (start : Nat) (startInBounds : start < source.length) :
    scanIdentifierEnd source start ≤ source.length := by
  have prefixBound := splitPrefix_length_le isIdentifierContinue
    (source.drop (start + 1))
  simp only [List.length_drop] at prefixBound
  unfold scanIdentifierEnd
  omega

def scanWhitespaceEnd (source : List Byte) (start : Nat) : Nat :=
  start + 1 +
    (splitPrefix isWhitespace (source.drop (start + 1))).1.length

def WhitespaceEndSpec
    (source : List Byte) (start finish : Nat) : Prop :=
  let split := splitPrefix isWhitespace (source.drop (start + 1))
  finish = start + 1 + split.1.length ∧
    MaximalPrefix isWhitespace (source.drop (start + 1)) split.1 split.2

theorem scanWhitespaceEnd_spec (source : List Byte) (start : Nat) :
    WhitespaceEndSpec source start (scanWhitespaceEnd source start) := by
  exact ⟨rfl, splitPrefix_spec isWhitespace (source.drop (start + 1))⟩

theorem WhitespaceEndSpec.functional
    {source : List Byte} {start left right : Nat}
    (leftResult : WhitespaceEndSpec source start left)
    (rightResult : WhitespaceEndSpec source start right) :
    left = right := by
  exact leftResult.1.trans rightResult.1.symm

theorem scanWhitespaceEnd_after_start (source : List Byte) (start : Nat) :
    start < scanWhitespaceEnd source start := by
  unfold scanWhitespaceEnd
  omega

theorem scanWhitespaceEnd_le_source_length
    (source : List Byte) (start : Nat) (startInBounds : start < source.length) :
    scanWhitespaceEnd source start ≤ source.length := by
  have prefixBound := splitPrefix_length_le isWhitespace
    (source.drop (start + 1))
  simp only [List.length_drop] at prefixBound
  unfold scanWhitespaceEnd
  omega

/-! ## Delimited tokens and first-failure positions -/

inductive ScanEnd where
  | success (endOffset : Nat)
  | failure (errorOffset : Nat)
deriving DecidableEq, Repr

def scanQuotedBody (delimiter : Byte) : Bool → List Byte → Nat → ScanEnd
  | _, [], offset => .failure offset
  | true, _byte :: rest, offset =>
      scanQuotedBody delimiter false rest (offset + 1)
  | false, byte :: rest, offset =>
      if byte.val = 10 then .failure offset
      else if byte = delimiter then .success (offset + 1)
      else if byte.val = 92 then
        scanQuotedBody delimiter true rest (offset + 1)
      else
        scanQuotedBody delimiter false rest (offset + 1)

def scanQuotedEnd (source : List Byte) (start : Nat) (delimiter : Byte) : ScanEnd :=
  scanQuotedBody delimiter false (source.drop (start + 1)) (start + 1)

inductive QuotedBodyScan (delimiter : Byte) : Bool → List Byte → Nat → ScanEnd → Prop
  | eof : QuotedBodyScan delimiter escaping [] offset (.failure offset)
  | escaped (byte : Byte) (rest : List Byte)
      (tailScan : QuotedBodyScan delimiter false rest (offset + 1) result) :
      QuotedBodyScan delimiter true (byte :: rest) offset result
  | newline (byte : Byte) (rest : List Byte) (isNewline : byte.val = 10) :
      QuotedBodyScan delimiter false (byte :: rest) offset (.failure offset)
  | close (byte : Byte) (rest : List Byte)
      (notNewline : byte.val ≠ 10) (isDelimiter : byte = delimiter) :
      QuotedBodyScan delimiter false (byte :: rest) offset (.success (offset + 1))
  | beginEscape (byte : Byte) (rest : List Byte)
      (notNewline : byte.val ≠ 10) (notDelimiter : byte ≠ delimiter)
      (isEscape : byte.val = 92)
      (tailScan : QuotedBodyScan delimiter true rest (offset + 1) result) :
      QuotedBodyScan delimiter false (byte :: rest) offset result
  | ordinary (byte : Byte) (rest : List Byte)
      (notNewline : byte.val ≠ 10) (notDelimiter : byte ≠ delimiter)
      (notEscape : byte.val ≠ 92)
      (tailScan : QuotedBodyScan delimiter false rest (offset + 1) result) :
      QuotedBodyScan delimiter false (byte :: rest) offset result

theorem scanQuotedBody_spec
    (delimiter : Byte) (escaping : Bool) (input : List Byte) (offset : Nat) :
    QuotedBodyScan delimiter escaping input offset
      (scanQuotedBody delimiter escaping input offset) := by
  induction input generalizing escaping offset with
  | nil => exact .eof
  | cons byte rest inductionHypothesis =>
      cases escaping with
      | true =>
          exact .escaped byte rest
            (inductionHypothesis (escaping := false) (offset := offset + 1))
      | false =>
          by_cases newline : byte.val = 10
          · rw [scanQuotedBody, if_pos newline]
            exact .newline byte rest newline
          by_cases closes : byte = delimiter
          · rw [scanQuotedBody, if_neg newline, if_pos closes]
            exact .close byte rest newline closes
          by_cases escape : byte.val = 92
          · rw [scanQuotedBody, if_neg newline, if_neg closes, if_pos escape]
            exact .beginEscape byte rest newline closes escape
              (inductionHypothesis (escaping := true) (offset := offset + 1))
          · rw [scanQuotedBody, if_neg newline, if_neg closes, if_neg escape]
            exact .ordinary byte rest newline closes escape
              (inductionHypothesis (escaping := false) (offset := offset + 1))

theorem QuotedBodyScan.executes
    (scan : QuotedBodyScan delimiter escaping input offset result) :
    scanQuotedBody delimiter escaping input offset = result := by
  induction scan with
  | eof => rfl
  | escaped _ _ _ inductionHypothesis =>
      rw [scanQuotedBody]
      exact inductionHypothesis
  | newline _ _ isNewline =>
      rw [scanQuotedBody, if_pos isNewline]
  | close _ _ notNewline isDelimiter =>
      rw [scanQuotedBody, if_neg notNewline, if_pos isDelimiter]
  | beginEscape _ _ notNewline notDelimiter isEscape _ inductionHypothesis =>
      rw [scanQuotedBody, if_neg notNewline, if_neg notDelimiter, if_pos isEscape]
      exact inductionHypothesis
  | ordinary _ _ notNewline notDelimiter notEscape _ inductionHypothesis =>
      rw [scanQuotedBody, if_neg notNewline, if_neg notDelimiter, if_neg notEscape]
      exact inductionHypothesis

theorem QuotedBodyScan.functional
    (left : QuotedBodyScan delimiter escaping input offset leftResult)
    (right : QuotedBodyScan delimiter escaping input offset rightResult) :
    leftResult = rightResult := by
  exact left.executes.symm.trans right.executes

theorem scanQuotedBody_result_bounds
    (delimiter : Byte) (escaping : Bool) (input : List Byte) (offset : Nat) :
    match scanQuotedBody delimiter escaping input offset with
    | .success endOffset | .failure endOffset =>
        offset ≤ endOffset ∧ endOffset ≤ offset + input.length := by
  induction input generalizing escaping offset with
  | nil => simp [scanQuotedBody]
  | cons byte rest inductionHypothesis =>
      cases escaping with
      | true =>
          rw [scanQuotedBody]
          have tailBound := inductionHypothesis false (offset + 1)
          cases tailResult : scanQuotedBody delimiter false rest (offset + 1) <;>
            simp [tailResult] at tailBound ⊢ <;> omega
      | false =>
          by_cases newline : byte.val = 10
          · simp [scanQuotedBody, newline]
          by_cases closes : byte = delimiter
          · have delimiterNotNewline : delimiter.val ≠ 10 := by
              simpa [closes] using newline
            simp [scanQuotedBody, closes, delimiterNotNewline]
          by_cases escape : byte.val = 92
          · rw [scanQuotedBody, if_neg newline, if_neg closes, if_pos escape]
            have tailBound := inductionHypothesis true (offset + 1)
            cases tailResult : scanQuotedBody delimiter true rest (offset + 1) <;>
              simp [tailResult] at tailBound ⊢ <;> omega
          · rw [scanQuotedBody, if_neg newline, if_neg closes, if_neg escape]
            have tailBound := inductionHypothesis false (offset + 1)
            cases tailResult : scanQuotedBody delimiter false rest (offset + 1) <;>
              simp [tailResult] at tailBound ⊢ <;> omega

theorem QuotedBodyScan.result_bounds
    (scan : QuotedBodyScan delimiter escaping input offset result) :
    match result with
    | .success endOffset | .failure endOffset =>
        offset ≤ endOffset ∧ endOffset ≤ offset + input.length := by
  have bounds := scanQuotedBody_result_bounds delimiter escaping input offset
  have execution := scan.executes
  cases result with
  | success endOffset =>
      change offset ≤ endOffset ∧ endOffset ≤ offset + input.length
      rw [execution] at bounds
      exact bounds
  | failure errorOffset =>
      change offset ≤ errorOffset ∧ errorOffset ≤ offset + input.length
      rw [execution] at bounds
      exact bounds

theorem QuotedBodyScan.failure_offset_unique
    (left : QuotedBodyScan delimiter escaping input offset (.failure leftOffset))
    (right : QuotedBodyScan delimiter escaping input offset (.failure rightOffset)) :
    leftOffset = rightOffset := by
  have resultsEqual := left.functional right
  exact ScanEnd.failure.inj resultsEqual

def scanLineCommentEnd (source : List Byte) (start : Nat) : Nat :=
  start + 2 +
    (splitPrefix (fun byte => byte.val != 10) (source.drop (start + 2))).1.length

def LineCommentEndSpec (source : List Byte) (start finish : Nat) : Prop :=
  let accept := fun byte : Byte => byte.val != 10
  let split := splitPrefix accept (source.drop (start + 2))
  finish = start + 2 + split.1.length ∧
    MaximalPrefix accept (source.drop (start + 2)) split.1 split.2

theorem scanLineCommentEnd_spec (source : List Byte) (start : Nat) :
    LineCommentEndSpec source start (scanLineCommentEnd source start) := by
  exact ⟨rfl, splitPrefix_spec (fun byte : Byte => byte.val != 10)
    (source.drop (start + 2))⟩

theorem LineCommentEndSpec.functional
    {source : List Byte} {start left right : Nat}
    (leftResult : LineCommentEndSpec source start left)
    (rightResult : LineCommentEndSpec source start right) :
    left = right := by
  exact leftResult.1.trans rightResult.1.symm

def scanBlockBody : List Byte → Nat → ScanEnd
  | [], offset => .failure offset
  | byte :: rest, offset =>
      match rest with
      | [] => .failure (offset + 1)
      | next :: _tail =>
          if byte.val = 42 ∧ next.val = 47 then .success (offset + 2)
          else scanBlockBody rest (offset + 1)

def scanBlockCommentEnd (source : List Byte) (start : Nat) : ScanEnd :=
  scanBlockBody (source.drop (start + 2)) (start + 2)

inductive BlockBodyScan : List Byte → Nat → ScanEnd → Prop
  | eof : BlockBodyScan [] offset (.failure offset)
  | finalByte (byte : Byte) : BlockBodyScan [byte] offset (.failure (offset + 1))
  | close (star slash : Byte) (rest : List Byte)
      (isStar : star.val = 42) (isSlash : slash.val = 47) :
      BlockBodyScan (star :: slash :: rest) offset (.success (offset + 2))
  | step (byte next : Byte) (rest : List Byte)
      (notClose : ¬(byte.val = 42 ∧ next.val = 47))
      (tailScan : BlockBodyScan (next :: rest) (offset + 1) result) :
      BlockBodyScan (byte :: next :: rest) offset result

theorem scanBlockBody_spec (input : List Byte) (offset : Nat) :
    BlockBodyScan input offset (scanBlockBody input offset) := by
  induction input generalizing offset with
  | nil => exact .eof
  | cons byte rest inductionHypothesis =>
      cases rest with
      | nil => exact .finalByte byte
      | cons next tail =>
          by_cases closes : byte.val = 42 ∧ next.val = 47
          · simpa [scanBlockBody, closes] using
              (BlockBodyScan.close (offset := offset) byte next tail closes.1 closes.2)
          · simpa [scanBlockBody, closes] using
              (BlockBodyScan.step byte next tail closes
                (inductionHypothesis (offset := offset + 1)))

theorem BlockBodyScan.executes
    (scan : BlockBodyScan input offset result) :
    scanBlockBody input offset = result := by
  induction scan with
  | eof => rfl
  | finalByte => rfl
  | close _ _ _ isStar isSlash => simp [scanBlockBody, isStar, isSlash]
  | step _ _ _ notClose _ inductionHypothesis =>
      rw [scanBlockBody, if_neg notClose]
      exact inductionHypothesis

theorem BlockBodyScan.functional
    (left : BlockBodyScan input offset leftResult)
    (right : BlockBodyScan input offset rightResult) :
    leftResult = rightResult := by
  exact left.executes.symm.trans right.executes

theorem scanBlockBody_result_bounds (input : List Byte) (offset : Nat) :
    match scanBlockBody input offset with
    | .success endOffset | .failure endOffset =>
        offset ≤ endOffset ∧ endOffset ≤ offset + input.length := by
  induction input generalizing offset with
  | nil => simp [scanBlockBody]
  | cons byte rest inductionHypothesis =>
      cases rest with
      | nil => simp [scanBlockBody]
      | cons next tail =>
          by_cases closes : byte.val = 42 ∧ next.val = 47
          · simp [scanBlockBody, closes]
          · rw [scanBlockBody, if_neg closes]
            have tailBound := inductionHypothesis (offset + 1)
            cases tailResult : scanBlockBody (next :: tail) (offset + 1) <;>
              simp [tailResult] at tailBound ⊢ <;> omega

theorem BlockBodyScan.result_bounds
    (scan : BlockBodyScan input offset result) :
    match result with
    | .success endOffset | .failure endOffset =>
        offset ≤ endOffset ∧ endOffset ≤ offset + input.length := by
  have bounds := scanBlockBody_result_bounds input offset
  have execution := scan.executes
  cases result with
  | success endOffset =>
      change offset ≤ endOffset ∧ endOffset ≤ offset + input.length
      rw [execution] at bounds
      exact bounds
  | failure errorOffset =>
      change offset ≤ errorOffset ∧ errorOffset ≤ offset + input.length
      rw [execution] at bounds
      exact bounds

theorem BlockBodyScan.failure_offset_unique
    (left : BlockBodyScan input offset (.failure leftOffset))
    (right : BlockBodyScan input offset (.failure rightOffset)) :
    leftOffset = rightOffset := by
  have resultsEqual := left.functional right
  exact ScanEnd.failure.inj resultsEqual

end Lanius.Compiler.Lexer
