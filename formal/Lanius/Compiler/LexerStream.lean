import Lanius.Compiler.Lexer
import Lanius.Compiler.LexerNumbers
import Lanius.Compiler.LexerSymbols

namespace Lanius.Compiler.Lexer

def doubleQuote : Byte := ⟨34, by omega⟩
def singleQuote : Byte := ⟨39, by omega⟩

structure RawToken where
  kind : TokenKind
  start : Nat
  finish : Nat
deriving DecidableEq, Repr

inductive OneTokenResult where
  | token (value : RawToken)
  | failure (errorOffset : Nat)
deriving DecidableEq, Repr

def tokenFromNumber (start : Nat) : NumberScanResult → OneTokenResult
  | .success kind finish => .token ⟨kind, start, finish⟩
  | .failure error => .failure error

theorem tokenFromNumber_deterministic
    (start : Nat) (number : NumberScanResult) {left right : OneTokenResult}
    (leftResult : tokenFromNumber start number = left)
    (rightResult : tokenFromNumber start number = right) :
    left = right := by
  exact leftResult.symm.trans rightResult

def tokenFromDelimited
    (kind : TokenKind) (start : Nat) : ScanEnd → OneTokenResult
  | .success finish => .token ⟨kind, start, finish⟩
  | .failure error => .failure error

theorem tokenFromDelimited_deterministic
    (kind : TokenKind) (start : Nat) (scan : ScanEnd) {left right : OneTokenResult}
    (leftResult : tokenFromDelimited kind start scan = left)
    (rightResult : tokenFromDelimited kind start scan = right) :
    left = right := by
  exact leftResult.symm.trans rightResult

def scanFixedSymbol (source : List Byte) (start : Nat) : OneTokenResult :=
  match matchSymbolHead (source.drop start) with
  | none => .failure start
  | some rule =>
      if rule.kind = .lineComment then
        .token ⟨rule.kind, start, scanLineCommentEnd source start⟩
      else if rule.kind = .blockComment then
        tokenFromDelimited rule.kind start (scanBlockCommentEnd source start)
      else
        .token ⟨rule.kind, start, start + rule.spelling.length⟩

theorem scanFixedSymbol_token_advances
    {source : List Byte} {start : Nat} {token : RawToken}
    (result : scanFixedSymbol source start = .token token) :
    start < token.finish := by
  unfold scanFixedSymbol at result
  cases matched : matchSymbolHead (source.drop start) with
  | none => simp [matched] at result
  | some rule =>
      simp only [matched] at result
      by_cases lineComment : rule.kind = .lineComment
      · simp [lineComment, scanLineCommentEnd] at result
        subst token
        change start < start + 2 +
          (splitPrefix (fun byte : Byte => byte.val != 10)
            (source.drop (start + 2))).1.length
        omega
      · simp only [lineComment, if_false] at result
        by_cases blockComment : rule.kind = .blockComment
        · simp only [blockComment, if_true] at result
          cases blockScan : scanBlockCommentEnd source start with
          | failure error => simp [tokenFromDelimited, blockScan] at result
          | success finish =>
              simp [tokenFromDelimited, blockScan] at result
              cases result
              unfold scanBlockCommentEnd at blockScan
              have bounds := scanBlockBody_result_bounds
                (source.drop (start + 2)) (start + 2)
              rw [blockScan] at bounds
              exact Nat.lt_of_lt_of_le (by omega) bounds.1
        · simp [blockComment] at result
          cases result
          have selected := (matchSymbolHead_spec matched).1
          have nonempty := symbolRules_spelling_length_pos selected
          change start < start + rule.spelling.length
          omega

def scanSymbol (source : List Byte) (start : Nat) : OneTokenResult :=
  match source[start]? with
  | none => .failure start
  | some first =>
      if first.val = 46 then
        match source[start + 1]? with
        | some following =>
            if isDecimalDigit following then
              tokenFromNumber start (scanLeadingDotNumber source start)
            else
              scanFixedSymbol source start
        | none => scanFixedSymbol source start
      else
        scanFixedSymbol source start

theorem scanSymbol_deterministic
    (source : List Byte) (start : Nat) {left right : OneTokenResult}
    (leftResult : scanSymbol source start = left)
    (rightResult : scanSymbol source start = right) :
    left = right := by
  exact leftResult.symm.trans rightResult

theorem scanSymbol_token_advances
    {source : List Byte} {start : Nat} {token : RawToken}
    (result : scanSymbol source start = .token token) :
    start < token.finish := by
  unfold scanSymbol at result
  cases firstAt : source[start]? with
  | none => simp [firstAt] at result
  | some first =>
      simp only [firstAt] at result
      by_cases isDot : first.val = 46
      · simp only [isDot, if_true] at result
        cases followingAt : source[start + 1]? with
        | none =>
            simp only [followingAt] at result
            exact scanFixedSymbol_token_advances result
        | some following =>
            simp only [followingAt] at result
            by_cases decimal : isDecimalDigit following = true
            · simp only [decimal, if_true] at result
              unfold tokenFromNumber at result
              cases number : scanLeadingDotNumber source start with
              | failure error => simp [number] at result
              | success kind finish =>
                  simp [number] at result
                  cases result
                  exact scanLeadingDotNumber_success_end_after_start number
            · simp only [decimal] at result
              exact scanFixedSymbol_token_advances result
      · simp only [isDot] at result
        exact scanFixedSymbol_token_advances result

/-- Total one-token dispatcher. EOF is not a token; calling at EOF returns a
    failure at EOF, while the stream driver treats EOF as successful completion. -/
def scanOne (source : List Byte) (start : Nat) : OneTokenResult :=
  match source[start]? with
  | none => .failure start
  | some first =>
      match classifyStart first with
      | .identifier =>
          .token ⟨.identifier, start, scanIdentifierEnd source start⟩
      | .decimalNumber => tokenFromNumber start (scanNumber source start)
      | .whitespace =>
          .token ⟨.whitespace, start, scanWhitespaceEnd source start⟩
      | .stringLiteral =>
          tokenFromDelimited .string start
            (scanQuotedEnd source start doubleQuote)
      | .characterLiteral =>
          tokenFromDelimited .character start
            (scanQuotedEnd source start singleQuote)
      | .symbol => scanSymbol source start
      | .invalid => .failure start

theorem scanOne_deterministic
    (source : List Byte) (start : Nat) {left right : OneTokenResult}
    (leftResult : scanOne source start = left)
    (rightResult : scanOne source start = right) :
    left = right := by
  exact leftResult.symm.trans rightResult

theorem scanOne_token_advances
    {source : List Byte} {start : Nat} {token : RawToken}
    (result : scanOne source start = .token token) :
    start < token.finish := by
  unfold scanOne at result
  cases firstAt : source[start]? with
  | none => simp [firstAt] at result
  | some first =>
      simp only [firstAt] at result
      cases startClass : classifyStart first with
      | identifier =>
          simp [startClass] at result
          subst token
          change start < scanIdentifierEnd source start
          exact scanIdentifierEnd_after_start source start
      | decimalNumber =>
          simp only [startClass] at result
          unfold tokenFromNumber at result
          cases number : scanNumber source start with
          | failure error => simp [number] at result
          | success kind finish =>
              simp [number] at result
              subst token
              change start < finish
              exact scanNumber_success_end_after_start number
      | whitespace =>
          simp [startClass] at result
          subst token
          change start < scanWhitespaceEnd source start
          exact scanWhitespaceEnd_after_start source start
      | stringLiteral =>
          simp only [startClass] at result
          unfold tokenFromDelimited at result
          cases quoted : scanQuotedEnd source start doubleQuote with
          | failure error => simp [quoted] at result
          | success finish =>
              simp [quoted] at result
              subst token
              unfold scanQuotedEnd at quoted
              have bounds := scanQuotedBody_result_bounds doubleQuote false
                (source.drop (start + 1)) (start + 1)
              rw [quoted] at bounds
              change start < finish
              omega
      | characterLiteral =>
          simp only [startClass] at result
          unfold tokenFromDelimited at result
          cases quoted : scanQuotedEnd source start singleQuote with
          | failure error => simp [quoted] at result
          | success finish =>
              simp [quoted] at result
              subst token
              unfold scanQuotedEnd at quoted
              have bounds := scanQuotedBody_result_bounds singleQuote false
                (source.drop (start + 1)) (start + 1)
              rw [quoted] at bounds
              change start < finish
              omega
      | symbol =>
          simp only [startClass] at result
          exact scanSymbol_token_advances result
      | invalid => simp [startClass] at result

inductive RawLexResult where
  | success (tokens : List RawToken)
  | failure (acceptedPrefix : List RawToken) (errorOffset : Nat)
  | fuelExhausted (acceptedPrefix : List RawToken) (sourceOffset : Nat)
deriving DecidableEq, Repr

def RawLexResult.prepend (token : RawToken) : RawLexResult → RawLexResult
  | .success tokens => .success (token :: tokens)
  | .failure accepted error => .failure (token :: accepted) error
  | .fuelExhausted accepted offset => .fuelExhausted (token :: accepted) offset

theorem RawLexResult.prepend_deterministic
    (token : RawToken) (result : RawLexResult) {left right : RawLexResult}
    (leftResult : result.prepend token = left)
    (rightResult : result.prepend token = right) :
    left = right := by
  exact leftResult.symm.trans rightResult

def lexRawFromFuel
    (source : List Byte) : Nat → Nat → RawLexResult
  | 0, offset => .fuelExhausted [] offset
  | fuel + 1, offset =>
      if source.length ≤ offset then .success []
      else
        match scanOne source offset with
        | .failure error => .failure [] error
        | .token token =>
            (lexRawFromFuel source fuel token.finish).prepend token

theorem lexRawFromFuel_deterministic
    (source : List Byte) (fuel offset : Nat) {left right : RawLexResult}
    (leftResult : lexRawFromFuel source fuel offset = left)
    (rightResult : lexRawFromFuel source fuel offset = right) :
    left = right := by
  exact leftResult.symm.trans rightResult

theorem lexRawFromFuel_ne_exhausted
    (source : List Byte) {fuel offset : Nat}
    (enoughFuel : source.length - offset < fuel) :
    ∀ acceptedPrefix exhaustedAt,
      lexRawFromFuel source fuel offset ≠
        .fuelExhausted acceptedPrefix exhaustedAt := by
  induction fuel generalizing offset with
  | zero => omega
  | succ fuel inductionHypothesis =>
      intro acceptedPrefix exhaustedAt
      rw [lexRawFromFuel]
      by_cases atEnd : source.length ≤ offset
      · simp [atEnd]
      · have beforeEnd : offset < source.length := by omega
        rw [if_neg atEnd]
        cases scanned : scanOne source offset with
        | failure error => simp
        | token token =>
            have advances := scanOne_token_advances scanned
            have tailFuel : source.length - token.finish < fuel := by omega
            have tailNotExhausted := inductionHypothesis tailFuel
            cases tailResult : lexRawFromFuel source fuel token.finish with
            | success tokens => simp [tailResult, RawLexResult.prepend]
            | failure accepted error => simp [tailResult, RawLexResult.prepend]
            | fuelExhausted accepted exhaustedAt =>
                exact False.elim (tailNotExhausted accepted exhaustedAt tailResult)

def lexRaw (source : List Byte) : RawLexResult :=
  lexRawFromFuel source (source.length + 1) 0

theorem lexRaw_ne_exhausted (source : List Byte) :
    ∀ acceptedPrefix exhaustedAt,
      lexRaw source ≠ .fuelExhausted acceptedPrefix exhaustedAt := by
  unfold lexRaw
  apply lexRawFromFuel_ne_exhausted
  simp

theorem lexRaw_deterministic
    (source : List Byte) {left right : RawLexResult}
    (leftResult : lexRaw source = left)
    (rightResult : lexRaw source = right) :
    left = right := by
  exact leftResult.symm.trans rightResult

/-- Declarative stream execution. Each constructor either completes at EOF,
    exposes the first failed token scan, or accepts one token and continues at
    its exclusive end. No constructor can skip a failed byte. -/
inductive RawLexes (source : List Byte) : Nat → RawLexResult → Prop
  | done (atEnd : source.length ≤ offset) :
      RawLexes source offset (.success [])
  | failed (beforeEnd : offset < source.length)
      (scanned : scanOne source offset = .failure errorOffset) :
      RawLexes source offset (.failure [] errorOffset)
  | accepted (beforeEnd : offset < source.length)
      (scanned : scanOne source offset = .token token)
      (tail : RawLexes source token.finish result) :
      RawLexes source offset (result.prepend token)

theorem RawLexes.functional
    {source : List Byte} {offset : Nat} {leftResult rightResult : RawLexResult}
    (left : RawLexes source offset leftResult)
    (right : RawLexes source offset rightResult) :
    leftResult = rightResult := by
  induction left generalizing rightResult with
  | done leftAtEnd =>
      cases right with
      | done => rfl
      | failed rightBeforeEnd => omega
      | accepted rightBeforeEnd => omega
  | failed leftBeforeEnd leftScanned =>
      cases right with
      | done rightAtEnd => omega
      | failed rightBeforeEnd rightScanned =>
          have sameError := scanOne_deterministic source _
            leftScanned rightScanned
          cases sameError
          rfl
      | accepted rightBeforeEnd rightScanned =>
          rw [leftScanned] at rightScanned
          contradiction
  | accepted leftBeforeEnd leftScanned leftTail inductionHypothesis =>
      cases right with
      | done rightAtEnd => omega
      | failed rightBeforeEnd rightScanned =>
          rw [leftScanned] at rightScanned
          contradiction
      | accepted rightBeforeEnd rightScanned rightTail =>
          have sameToken := scanOne_deterministic source _
            leftScanned rightScanned
          cases sameToken
          exact congrArg (RawLexResult.prepend _) (inductionHypothesis rightTail)

inductive RawTokenPrefix (source : List Byte) : Nat → List RawToken → Nat → Prop
  | empty (offset) : RawTokenPrefix source offset [] offset
  | accepted (beforeEnd : offset < source.length)
      (scanned : scanOne source offset = .token token)
      (tail : RawTokenPrefix source token.finish tokens finish) :
      RawTokenPrefix source offset (token :: tokens) finish

/-- A failed stream consists of a successfully scanned token prefix followed
    immediately by the failed `scanOne` invocation. This is the formal
    first-failure property: there is no skipped byte or discarded token between
    the accepted prefix and the reported error. -/
theorem RawLexes.failure_witness
    {source : List Byte} {offset : Nat} {result : RawLexResult}
    (scan : RawLexes source offset result) :
    match result with
    | .failure acceptedPrefix errorOffset =>
        ∃ failureStart,
          RawTokenPrefix source offset acceptedPrefix failureStart ∧
          failureStart < source.length ∧
          scanOne source failureStart = .failure errorOffset
    | .success _ | .fuelExhausted _ _ => True := by
  induction scan with
  | done => trivial
  | failed beforeEnd scanned =>
      exact ⟨_, .empty _, beforeEnd, scanned⟩
  | @accepted _ token tailResult beforeEnd scanned tail inductionHypothesis =>
      cases tailResult with
      | success tokens => trivial
      | failure acceptedPrefix errorOffset =>
          change ∃ failureStart,
            RawTokenPrefix source _ acceptedPrefix failureStart ∧
            failureStart < source.length ∧
            scanOne source failureStart = .failure errorOffset at inductionHypothesis
          obtain ⟨failureStart, prefixScan, failureInBounds, failedScan⟩ :=
            inductionHypothesis
          exact ⟨failureStart, .accepted beforeEnd scanned prefixScan,
            failureInBounds, failedScan⟩
      | fuelExhausted acceptedPrefix sourceOffset => trivial

theorem RawLexes.success_witness
    {source : List Byte} {offset : Nat} {result : RawLexResult}
    (scan : RawLexes source offset result) :
    match result with
    | .success tokens =>
        ∃ finish,
          RawTokenPrefix source offset tokens finish ∧ source.length ≤ finish
    | .failure _ _ | .fuelExhausted _ _ => True := by
  induction scan with
  | done atEnd => exact ⟨_, .empty _, atEnd⟩
  | failed => trivial
  | @accepted _ token tailResult beforeEnd scanned tail inductionHypothesis =>
      cases tailResult with
      | success tokens =>
          change (∃ finish, RawTokenPrefix source token.finish tokens finish ∧
            source.length ≤ finish) at inductionHypothesis
          obtain ⟨finish, prefixScan, atEnd⟩ := inductionHypothesis
          exact ⟨finish, .accepted beforeEnd scanned prefixScan, atEnd⟩
      | failure acceptedPrefix errorOffset => trivial
      | fuelExhausted acceptedPrefix sourceOffset => trivial

theorem lexRawFromFuel_sound
    (source : List Byte) {fuel offset : Nat}
    (enoughFuel : source.length - offset < fuel) :
    RawLexes source offset (lexRawFromFuel source fuel offset) := by
  induction fuel generalizing offset with
  | zero => omega
  | succ fuel inductionHypothesis =>
      rw [lexRawFromFuel]
      by_cases atEnd : source.length ≤ offset
      · rw [if_pos atEnd]
        exact .done atEnd
      · rw [if_neg atEnd]
        have beforeEnd : offset < source.length := by omega
        cases scanned : scanOne source offset with
        | failure error => exact .failed beforeEnd scanned
        | token token =>
            have advances := scanOne_token_advances scanned
            have tailFuel : source.length - token.finish < fuel := by omega
            exact .accepted beforeEnd scanned (inductionHypothesis tailFuel)

theorem lexRaw_sound (source : List Byte) :
    RawLexes source 0 (lexRaw source) := by
  unfold lexRaw
  apply lexRawFromFuel_sound
  simp

theorem lexRaw_failure_is_first
    {source : List Byte} {acceptedPrefix : List RawToken} {errorOffset : Nat}
    (result : lexRaw source = .failure acceptedPrefix errorOffset) :
    ∃ failureStart,
      RawTokenPrefix source 0 acceptedPrefix failureStart ∧
      failureStart < source.length ∧
      scanOne source failureStart = .failure errorOffset := by
  have sound := lexRaw_sound source
  rw [result] at sound
  exact sound.failure_witness

theorem lexRaw_success_consumes_source
    {source : List Byte} {tokens : List RawToken}
    (result : lexRaw source = .success tokens) :
    ∃ finish,
      RawTokenPrefix source 0 tokens finish ∧ source.length ≤ finish := by
  have sound := lexRaw_sound source
  rw [result] at sound
  exact sound.success_witness

theorem lexRaw_mixed_prefix_then_first_failure :
    lexRaw ([97, 98, 99, 32, 49, 50, 46, 46, 51, 52, 32,
      47, 47, 120, 10, 34, 111, 107, 34, 32, 64] : List Byte) =
      .failure [
        ⟨.identifier, 0, 3⟩,
        ⟨.whitespace, 3, 4⟩,
        ⟨.integer, 4, 6⟩,
        ⟨.dotDot, 6, 8⟩,
        ⟨.integer, 8, 10⟩,
        ⟨.whitespace, 10, 11⟩,
        ⟨.lineComment, 11, 14⟩,
        ⟨.whitespace, 14, 15⟩,
        ⟨.string, 15, 19⟩,
        ⟨.whitespace, 19, 20⟩
      ] 20 := by
  native_decide

theorem lexRaw_unterminated_string_fails_at_newline :
    lexRaw ([34, 97, 10, 98] : List Byte) = .failure [] 2 := by
  native_decide

theorem lexRaw_empty_source :
    lexRaw ([] : List Byte) = .success [] := by
  native_decide

end Lanius.Compiler.Lexer
