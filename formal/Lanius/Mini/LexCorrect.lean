import Lanius.Mini.FrontLex

/-! The verified compiler's lexer (`lex_source` in `formal/lani/mini/frontend.lani`,
extracted as `lexSource`) is the Lean lexer: on a file's byte values it gives
`lexTokens` of the file (`lexSource_eq`). Each extracted function is proved
equal to the Lean function of the same shape, on byte values and with token
kinds as laniusc's codes. -/

namespace Lanius.Mini

open Lanius.Compiler Lanius.Compiler.Lexer

/-- A file's byte values. -/
abbrev vals (l : List Byte) : List Nat := l.map Fin.val

/-! ## Bytes and lists -/

set_option maxRecDepth 20000

theorem identStart_eq (b : Byte) : lxIdentStart b.val = isIdentifierStart b := by revert b; decide
theorem digit_eq (b : Byte) : lxDigit b.val = isDecimalDigit b := by revert b; decide
theorem identContinue_eq (b : Byte) : lxIdentContinue b.val = isIdentifierContinue b := by revert b; decide
theorem space_eq (b : Byte) : lxSpace b.val = isWhitespace b := by revert b; decide
theorem symbolStart_eq (b : Byte) : lxSymbolStart b.val = isSymbolStart b := by revert b; decide

theorem lxDrop_eq : ∀ (l : List Nat) (n : Nat), lxDrop l n = l.drop n
  | [], 0 => by simp [lxDrop]
  | [], n + 1 => by simp [lxDrop]
  | _ :: _, 0 => by simp [lxDrop]
  | _ :: more, n + 1 => by simp [lxDrop, lxDrop_eq more n]

theorem lxTake_eq : ∀ (l : List Nat) (n : Nat), lxTake l n = l.take n
  | [], 0 => by simp [lxTake]
  | [], n + 1 => by simp [lxTake]
  | _ :: _, 0 => by simp [lxTake]
  | _ :: more, n + 1 => by simp [lxTake, lxTake_eq more n]

theorem vals_drop (l : List Byte) (n : Nat) : (vals l).drop n = vals (l.drop n) := by
  simp [vals, List.map_drop]

theorem vals_take (l : List Byte) (n : Nat) : (vals l).take n = vals (l.take n) := by
  simp [vals, List.map_take]

theorem vals_get (l : List Byte) (n : Nat) : (vals l)[n]? = byteValueAt l n := by
  simp [vals, byteValueAt]

theorem lxIsByte_eq (o : Option Nat) (v : Nat) : lxIsByte o v = decide (o = some v) := by
  cases o <;> simp [lxIsByte]

/-! ## Runs and ends -/

theorem identRun_eq : ∀ l : List Byte, lxIdentRun (vals l) = (splitPrefix isIdentifierContinue l).1.length
  | [] => by simp [lxIdentRun, splitPrefix]
  | b :: more => by
    simp only [vals, List.map_cons, lxIdentRun, splitPrefix, identContinue_eq]
    split <;> simp_all [identRun_eq more]

theorem spaceRun_eq : ∀ l : List Byte, lxSpaceRun (vals l) = (splitPrefix isWhitespace l).1.length
  | [] => by simp [lxSpaceRun, splitPrefix]
  | b :: more => by
    simp only [vals, List.map_cons, lxSpaceRun, splitPrefix, space_eq]
    split <;> simp_all [spaceRun_eq more]

theorem lineRun_eq : ∀ l : List Byte, lxLineRun (vals l) = (splitPrefix (fun byte : Byte => byte.val != 10) l).1.length
  | [] => by simp [lxLineRun, splitPrefix]
  | b :: more => by
    simp only [vals, List.map_cons, lxLineRun, splitPrefix]
    by_cases h : b.val = 10
    · simp [h]
    · simp [h, lineRun_eq more]

theorem identEnd_eq (s : List Byte) (start : Nat) : lxIdentEnd (vals s) start = scanIdentifierEnd s start := by
  simp only [lxIdentEnd, scanIdentifierEnd, scanEnd, lxDrop_eq, vals_drop, identRun_eq]

theorem spaceEnd_eq (s : List Byte) (start : Nat) : lxSpaceEnd (vals s) start = scanWhitespaceEnd s start := by
  simp only [lxSpaceEnd, scanWhitespaceEnd, scanEnd, lxDrop_eq, vals_drop, spaceRun_eq]

theorem lineEnd_eq (s : List Byte) (start : Nat) : lxLineEnd (vals s) start = scanLineCommentEnd s start := by
  simp only [lxLineEnd, scanLineCommentEnd, scanEnd, lxDrop_eq, vals_drop, lineRun_eq]

/-! ## Quoted bodies and block comments -/

def endScan : ScanEnd → Scan
  | .success finish => .scanDone finish
  | .failure error => .scanFail error

theorem quoted_eq (d : Byte) : ∀ (escaping : Bool) (l : List Byte) (offset : Nat),
    lxQuoted d.val escaping (vals l) offset = endScan (scanQuotedBody d escaping l offset)
  | _, [], _ => by cases ‹Bool› <;> simp [lxQuoted, scanQuotedBody, endScan]
  | true, b :: more, offset => by
    simp only [vals, List.map_cons, lxQuoted, scanQuotedBody, if_true]
    exact quoted_eq d false more (offset + 1)
  | false, b :: more, offset => by
    simp only [vals, List.map_cons, lxQuoted, scanQuotedBody, Bool.false_eq_true, if_false]
    by_cases nl : b.val = 10
    · simp [nl, endScan]
    · simp only [nl, if_false]
      by_cases same : b = d
      · simp [same, endScan]
      · have : b.val ≠ d.val := fun h => same (Fin.ext h)
        simp only [this, same, if_false]
        by_cases esc : b.val = 92
        · simp only [esc, if_true]
          exact quoted_eq d true more (offset + 1)
        · simp only [esc, if_false]
          exact quoted_eq d false more (offset + 1)

theorem block_eq : ∀ (l : List Byte) (offset : Nat), lxBlock (vals l) offset = endScan (scanBlockBody l offset)
  | [], _ => by simp [lxBlock, scanBlockBody, endScan]
  | [_], _ => by simp [lxBlock, scanBlockBody, endScan]
  | b :: next :: tail, offset => by
    have ih := block_eq (next :: tail) (offset + 1)
    simp only [vals, List.map_cons] at ih ⊢
    simp only [lxBlock, scanBlockBody]
    by_cases close : b.val = 42 ∧ next.val = 47
    · simp [close, endScan]
    · have : (decide (b.val = 42) && decide (next.val = 47)) = false := by
        simp only [Bool.and_eq_false_iff, decide_eq_false_iff_not]
        by_cases h : b.val = 42
        · exact .inr fun h' => close ⟨h, h'⟩
        · exact .inl h
      simp only [this, close, Bool.false_eq_true, if_false]
      exact ih

theorem blockEnd_eq (s : List Byte) (start : Nat) :
    lxBlockEnd (vals s) start = endScan (scanBlockCommentEnd s start) := by
  simp only [lxBlockEnd, scanBlockCommentEnd, lxDrop_eq, vals_drop, block_eq]

theorem quotedEnd_eq (s : List Byte) (start : Nat) (d : Byte) :
    lxQuoted d.val false (lxDrop (vals s) (start + 1)) (start + 1) = endScan (scanQuotedEnd s start d) := by
  simp only [scanQuotedEnd, lxDrop_eq, vals_drop, quoted_eq]

/-! ## Digits -/

theorem baseDigit_eq (b : Byte) (base : Nat) : lxBaseDigit b.val base = isDigitForBase b base := by
  simp only [lxBaseDigit, isDigitForBase]

def digitScan : DigitScanResult → Scan
  | .success finish => .scanDone finish
  | .failure error => .scanFail error

theorem digitTail_eq (base : Nat) : ∀ (n : Nat) (l : List Byte), l.length ≤ n → ∀ offset,
    lxDigitTail base (vals l) offset = digitScan (scanDigitTail base l offset) := by
  intro n
  induction n with
  | zero =>
    intro l len offset
    cases l with
    | nil => rw [scanDigitTail.eq_def]; simp [lxDigitTail, digitScan]
    | cons _ _ => simp at len
  | succ n ih =>
    intro l len offset
    cases l with
    | nil => rw [scanDigitTail.eq_def]; simp [lxDigitTail, digitScan]
    | cons b more =>
      simp only [List.length_cons] at len
      simp only [vals, List.map_cons]
      rw [lxDigitTail.eq_def, scanDigitTail.eq_def]
      simp only [baseDigit_eq]
      by_cases digit : isDigitForBase b base = true
      · simp only [digit, if_true]
        exact ih more (by omega) (offset + 1)
      · simp only [digit, Bool.false_eq_true, if_false]
        by_cases sep : b.val = 95
        · simp only [sep, if_true, beq_self_eq_true]
          cases more with
          | nil => simp [digitScan]
          | cons next after =>
            simp only [List.length_cons] at len
            simp only [List.map_cons, baseDigit_eq]
            by_cases d2 : isDigitForBase next base = true
            · simp only [d2, if_true]
              exact ih after (by omega) (offset + 2)
            · simp [d2, digitScan]
        · have : (b.val == 95) = false := by simp [sep]
          simp [sep, this, digitScan]

theorem digitRun_eq (s : List Byte) (start base : Nat) :
    lxDigitRun (vals s) start base = digitScan (scanDigitRun s start base) := by
  simp only [lxDigitRun, scanDigitRun, lxDrop_eq, vals_drop]
  cases h : s.drop start with
  | nil => simp [digitScan]
  | cons first rest =>
    simp only [vals, List.map_cons, baseDigit_eq]
    split
    · exact digitTail_eq base _ rest (Nat.le_refl _) _
    · simp [digitScan]

/-! ## Numbers -/

def numScan : NumberScanResult → NumScan
  | .success kind finish => .numDone kind.gpuCode finish
  | .failure error => .numFail error

theorem exponentDigits_eq (s : List Byte) (e : Nat) : lxExponentDigits (vals s) e = exponentDigitsStart s e := by
  simp only [lxExponentDigits, exponentDigitsStart, vals_get, Bool.beq_eq_decide_eq]
  cases byteValueAt s (e + 1) <;> rfl

theorem exponent_eq (s : List Byte) (e : Nat) : lxExponent (vals s) e = numScan (scanExponent s e) := by
  simp only [lxExponent, scanExponent, exponentDigits_eq, digitRun_eq]
  cases scanDigitRun s (exponentDigitsStart s e) 10 <;> rfl

/-- What follows a fraction's digits, as `finishDecimal` and
`scanLeadingDotNumber` read it. -/
def afterFraction (s : List Byte) (fe : Nat) : NumberScanResult :=
  match byteValueAt s fe with
  | some exponent =>
      if decide (exponent = 101) || decide (exponent = 69) then scanExponent s fe else .success .float fe
  | none => .success .float fe

theorem afterFraction_eq (s : List Byte) (fe : Nat) : lxAfterFraction (vals s) fe = numScan (afterFraction s fe) := by
  simp only [lxAfterFraction, afterFraction, vals_get]
  cases byteValueAt s fe with
  | none => rfl
  | some x =>
    simp only
    split
    · exact exponent_eq s fe
    · rfl

theorem fractionDigits_eq (s : List Byte) (r : DigitScanResult) :
    lxFractionDigits (vals s) (digitScan r) = numScan (match r with
      | .failure error => .failure error
      | .success fe => afterFraction s fe) := by
  cases r with
  | failure error => rfl
  | success fe => exact afterFraction_eq s fe

theorem leadingDot_eq (s : List Byte) (start : Nat) :
    lxLeadingDot (vals s) start = numScan (scanLeadingDotNumber s start) := by
  simp only [lxLeadingDot, digitRun_eq, fractionDigits_eq]
  simp only [scanLeadingDotNumber, Bool.beq_eq_decide_eq]
  rfl

theorem finishDecimal_eq (s : List Byte) (ie : Nat) : lxFinishDecimal (vals s) ie = numScan (finishDecimal s ie) := by
  simp only [lxFinishDecimal, finishDecimal, vals_get, lxIsByte_eq, Bool.beq_eq_decide_eq, bne]
  cases byteValueAt s ie with
  | none => rfl
  | some next =>
    simp only
    by_cases e : (decide (next = 101) || decide (next = 69)) = true
    · simp only [e, if_true]
      exact exponent_eq s ie
    · simp only [e, Bool.false_eq_true, if_false]
      by_cases dot : next = 46
      · simp only [dot, decide_true, Bool.not_true, Bool.false_eq_true, if_false, ne_eq, not_true_eq_false]
        by_cases two : byteValueAt s (ie + 1) = some 46
        · simp only [two, decide_true, if_true]
          rfl
        · simp only [two, decide_false, Bool.false_eq_true, if_false, lxFraction, vals_get]
          cases byteValueAt s (ie + 1) with
          | none => rfl
          | some first =>
            simp only
            by_cases digit : (decide (48 ≤ first) && decide (first ≤ 57)) = true
            · simp only [digit, if_true, digitRun_eq, fractionDigits_eq]
              rfl
            · simp only [digit, Bool.false_eq_true, if_false]
              by_cases ex : (decide (first = 101) || decide (first = 69)) = true
              · simp only [ex, if_true]
                exact exponent_eq s (ie + 1)
              · simp only [ex, Bool.false_eq_true, if_false]
                rfl
      · simp only [dot, decide_false, Bool.not_false, if_true, ne_eq, not_false_eq_true]
        rfl

theorem prefixedBase_eq (s : List Byte) (start : Nat) : lxPrefixedBase (vals s) start = prefixedBase s start := by
  simp only [lxPrefixedBase, prefixedBase, vals_get, lxIsByte_eq, Bool.beq_eq_decide_eq, bne, lxBaseOf]
  by_cases zero : byteValueAt s start = some 48
  · simp only [zero, decide_true, Bool.not_true, Bool.false_eq_true, if_false]
    cases byteValueAt s (start + 1) <;> rfl
  · simp only [zero, decide_false, Bool.not_false, if_true]

theorem number_eq (s : List Byte) (start : Nat) : lxNumber (vals s) start = numScan (scanNumber s start) := by
  simp only [lxNumber, scanNumber, prefixedBase_eq]
  cases prefixedBase s start with
  | some base =>
    simp only [digitRun_eq]
    cases scanDigitRun s (start + 2) base <;> rfl
  | none =>
    simp only [digitRun_eq]
    cases scanDigitRun s start 10 with
    | success ie => exact finishDecimal_eq s ie
    | failure error => rfl

/-! ## Symbols -/

def symRule (rule : SymbolRule) : SymRule := { spelling := rule.spelling, kind := rule.kind.gpuCode }

theorem code_eq_iff (k k' : TokenKind) : k.gpuCode = k'.gpuCode ↔ k = k' :=
  ⟨fun h => TokenKind.gpuCode_injective h, congrArg _⟩

theorem startsWith_eq : ∀ (e a : List Nat), lxStartsWith e a = startsWith e a
  | [], _ => by simp [lxStartsWith, startsWith]
  | _ :: _, [] => by simp [lxStartsWith, startsWith]
  | x :: er, y :: ar => by simp [lxStartsWith, startsWith, startsWith_eq er ar, Bool.beq_eq_decide_eq]

theorem best_eq (input : List Nat) : ∀ rules : List SymbolRule,
    lxBest (rules.map symRule) input = (bestMatching rules input).map symRule
  | [] => rfl
  | rule :: more => by
    simp only [List.map_cons, lxBest, bestMatching, best_eq input more, lxBestAt, SymbolRule.matches]
    rw [show (symRule rule).spelling = rule.spelling from rfl, startsWith_eq]
    by_cases h : startsWith rule.spelling input = true
    · simp only [h, if_true]
      cases bestMatching more input with
      | none => rfl
      | some current =>
        simp only [Option.map_some, lxLonger, chooseLonger]
        show some (if current.spelling.length < rule.spelling.length then symRule rule else symRule current) = _
        split <;> rfl
    · simp only [h, Bool.false_eq_true, if_false]

theorem symbolRules_eq : lxSymbolRules = symbolRules.map symRule := rfl

theorem sameText_eq : ∀ a b : List Nat, sameText a b = decide (a = b)
  | [], [] => rfl
  | [], _ :: _ => by simp [sameText]
  | _ :: _, [] => by simp [sameText]
  | x :: a, y :: b => by simp [sameText, sameText_eq a b]

def raw (token : RawToken) : RawTok := { kind := token.kind.gpuCode, start := token.start, finish := token.finish }

def oneTok : OneTokenResult → OneTok
  | .token token => .oneDone (raw token)
  | .failure error => .oneFail error

theorem delimited_eq (kind : TokenKind) (start : Nat) (e : ScanEnd) :
    lxDelimited kind.gpuCode start (endScan e) = oneTok (tokenFromDelimited kind start e) := by
  cases e <;> rfl

theorem fromNumber_eq (start : Nat) (n : NumberScanResult) :
    lxFromNumber start (numScan n) = oneTok (tokenFromNumber start n) := by
  cases n <;> rfl

theorem vals_getElem (l : List Byte) (n : Nat) : (vals l)[n]? = l[n]?.map Fin.val := by
  simp [vals]

theorem fixed_eq (s : List Byte) (start : Nat) :
    lxFixed lxSymbolRules (vals s) start = oneTok (scanFixedSymbol s start) := by
  simp only [lxFixed, scanFixedSymbol, matchSymbolHead, lxDrop_eq, lxTake_eq, vals_drop, vals_take,
    symbolRules_eq, best_eq]
  cases bestMatching symbolRules ((List.take 3 (List.drop start s)).map Fin.val) with
  | none => rfl
  | some rule =>
    simp only [Option.map_some, lxFixedAt]
    rw [show (symRule rule).kind = rule.kind.gpuCode from rfl, show (symRule rule).spelling = rule.spelling from rfl]
    by_cases lc : rule.kind = .lineComment
    · simp only [lc, show TokenKind.lineComment.gpuCode = 10 from rfl, if_true, lineEnd_eq]
      rfl
    · have lc' : rule.kind.gpuCode ≠ 10 := fun h => lc ((code_eq_iff _ .lineComment).mp h)
      simp only [lc, lc', if_false]
      by_cases bc : rule.kind = .blockComment
      · simp only [bc, show TokenKind.blockComment.gpuCode = 11 from rfl, if_true, blockEnd_eq]
        exact delimited_eq .blockComment start _
      · have bc' : rule.kind.gpuCode ≠ 11 := fun h => bc ((code_eq_iff _ .blockComment).mp h)
        simp only [bc, bc', if_false]
        rfl

theorem symbol_eq (s : List Byte) (start : Nat) :
    lxSymbol lxSymbolRules (vals s) start = oneTok (scanSymbol s start) := by
  simp only [lxSymbol, scanSymbol, vals_getElem]
  cases s[start]? with
  | none => rfl
  | some first =>
    simp only [Option.map_some, lxSymbolAt]
    by_cases dot : first.val = 46
    · simp only [dot, if_true, vals_getElem]
      cases s[start + 1]? with
      | none => exact fixed_eq s start
      | some following =>
        simp only [Option.map_some, lxDotAt, digit_eq]
        split
        · rw [leadingDot_eq, fromNumber_eq]
        · exact fixed_eq s start
    · simp only [dot, if_false]
      exact fixed_eq s start

theorem oneAt_eq (s : List Byte) (start : Nat) :
    lxOneAt lxSymbolRules (vals s) start = oneTok (scanOneAt s start) := by
  simp only [lxOneAt, scanOneAt, vals_getElem]
  cases s[start]? with
  | none => rfl
  | some first =>
    simp only [Option.map_some, lxOneFirst, classifyStart, identStart_eq, digit_eq, space_eq, symbolStart_eq,
      Bool.beq_eq_decide_eq]
    by_cases i : isIdentifierStart first = true
    · simp only [i, if_true, identEnd_eq]
      rfl
    · simp only [i, Bool.false_eq_true, if_false]
      by_cases d : isDecimalDigit first = true
      · simp only [d, if_true, number_eq, fromNumber_eq]
      · simp only [d, Bool.false_eq_true, if_false]
        by_cases w : isWhitespace first = true
        · simp only [w, if_true, spaceEnd_eq]
          rfl
        · simp only [w, Bool.false_eq_true, if_false]
          by_cases q : first.val = 34
          · simp only [q, decide_true, if_true]
            rw [show (34 : Nat) = doubleQuote.val from rfl, quotedEnd_eq]
            exact delimited_eq .string start _
          · simp only [q, decide_false, Bool.false_eq_true, if_false]
            by_cases c : first.val = 39
            · simp only [c, decide_true, if_true]
              rw [show (39 : Nat) = singleQuote.val from rfl, quotedEnd_eq]
              exact delimited_eq .character start _
            · simp only [c, decide_false, Bool.false_eq_true, if_false]
              by_cases y : isSymbolStart first = true
              · simp only [y, if_true]
                exact symbol_eq s start
              · simp only [y, Bool.false_eq_true, if_false]
                rfl

/-! ## The stream -/

def rawResult : RawLexResult → Option (List RawTok)
  | .success tokens => some (tokens.map raw)
  | .failure _ _ => none
  | .fuelExhausted _ _ => none

theorem prepend_eq (token : RawToken) (r : RawLexResult) :
    rawResult (r.prepend token) = lxPrepend (raw token) (rawResult r) := by
  cases r <;> rfl

theorem raw_eq : ∀ (fuel : Nat) (rest : List Byte) (offset : Nat),
    lxRaw lxSymbolRules (vals rest) fuel offset = rawResult (lexRawFromRest rest fuel offset)
  | 0, rest, offset => by cases rest <;> simp [lxRaw, lexRawFromRest, rawResult]
  | fuel + 1, [], offset => by simp [lxRaw, lexRawFromRest, rawResult]
  | fuel + 1, b :: more, offset => by
    rw [lxRaw.eq_def]
    simp only [Nat.add_one_ne_zero, if_false, lexRawFromRest]
    have one := oneAt_eq (b :: more) 0
    simp only [vals, List.map_cons] at one ⊢
    rw [one]
    cases scanOneAt (b :: more) 0 with
    | failure error => rfl
    | token token =>
      simp only [oneTok, OneTokenResult.shift, RawToken.shift, prepend_eq]
      have ih := raw_eq fuel ((b :: more).drop (offset + token.finish - offset)) (offset + token.finish)
      have dropped := vals_drop (b :: more) (offset + token.finish - offset)
      simp only [vals] at ih dropped
      simp only [show (raw token).finish = token.finish from rfl, lxDrop_eq, Nat.add_sub_cancel, ← List.map_cons,
        dropped, ih]
      rfl

/-! ## Canonical tokens -/

def kwRule (rule : KeywordRule) : SymRule := { spelling := rule.spelling, kind := rule.kind.gpuCode }

theorem keywordRules_eq : lxKeywordRules = keywordRules.map kwRule := rfl

theorem trivia_eq (k : TokenKind) : lxTrivia k.gpuCode = isTriviaKind k := by
  cases k <;> rfl

theorem keyword_eq (spelling : List Nat) : ∀ rules : List KeywordRule,
    lxKeyword spelling (rules.map kwRule) = (exactKeywordKind spelling rules).map TokenKind.gpuCode
  | [] => rfl
  | rule :: more => by
    simp only [List.map_cons, lxKeyword, exactKeywordKind, sameText_eq]
    rw [show (kwRule rule).spelling = rule.spelling from rfl]
    by_cases h : spelling = rule.spelling
    · simp only [h, decide_true, if_true]
      rfl
    · simp only [h, decide_false, Bool.false_eq_true, if_false]
      exact keyword_eq spelling more

theorem dropTo_vals (source rest : List Byte) (pos target : Nat) :
    lxDropTo (vals source) (vals rest) pos target = vals (dropTo source rest pos target) := by
  simp only [lxDropTo, dropTo, lxDrop_eq, vals_drop]
  split <;> rfl

theorem filter_eq (source : List Byte) : ∀ (tokens : List RawToken) (rest : List Byte) (pos : Nat),
    lxFilter lxKeywordRules (vals source) (vals rest) pos (tokens.map raw) =
      (filterRetagFrom source rest pos tokens).map raw
  | [], _, _ => rfl
  | t :: more, rest, pos => by
    simp only [List.map_cons, lxFilter, filterRetagFrom, dropTo_vals]
    rw [show (raw t).kind = t.kind.gpuCode from rfl, show (raw t).start = t.start from rfl, trivia_eq]
    split
    · exact filter_eq source more _ _
    · simp only [List.map_cons, filter_eq source more]
      congr 1
      simp only [raw, lxCanonicalKind, RawTok.mk.injEq, and_true]
      by_cases ident : t.kind = .identifier
      · simp only [ident, show TokenKind.identifier.gpuCode = 1 from rfl, if_true, lxTake_eq, vals_take,
          keywordRules_eq, keyword_eq, tokenBytesFrom]
        cases exactKeywordKind (List.map Fin.val (List.take (t.finish - t.start) (dropTo source rest pos t.start)))
          keywordRules <;> rfl
      · have ident' : t.kind.gpuCode ≠ 1 := fun h => ident ((code_eq_iff _ .identifier).mp h)
        simp only [ident, ident', if_false]

theorem ranges_eq : ∀ tokens : List RawToken, lxRanges (tokens.map raw) = (retagInclusiveRanges tokens).map raw
  | [] => rfl
  | [_] => rfl
  | current :: next :: rest => by
    have ih := ranges_eq (next :: rest)
    rw [List.map_cons, List.map_cons, lxRanges.eq_def]
    simp only []
    rw [← List.map_cons, ih]
    simp only [retagInclusiveRanges, List.map_cons]
    congr 1
    simp only [lxRangePair, isInclusiveRangePair, raw]
    by_cases dd : current.kind = .dotDot
    · by_cases eq : next.kind = .assign
      · simp only [dd, eq, show TokenKind.dotDot.gpuCode = 182 from rfl, show TokenKind.assign.gpuCode = 8 from rfl,
          decide_true, Bool.true_and]
        by_cases st : next.start = current.finish <;> simp [st, dd, eq, TokenKind.gpuCode]
      · have eq' : next.kind.gpuCode ≠ 8 := fun h => eq ((code_eq_iff _ .assign).mp h)
        simp [eq, eq']
    · have dd' : current.kind.gpuCode ≠ 182 := fun h => dd ((code_eq_iff _ .dotDot).mp h)
      simp [dd, dd']

theorem tokens_eq (source : List Byte) : ∀ (tokens : List RawToken) (rest : List Byte) (pos : Nat),
    lxTokens (vals source) (vals rest) pos (tokens.map raw) = toTokensFrom source rest pos tokens
  | [], _, _ => rfl
  | t :: more, rest, pos => by
    simp only [List.map_cons, lxTokens, toTokensFrom, dropTo_vals, tokens_eq source more]
    congr 1
    simp only [lxToken, lxTokenText, lxAsText, toTokenAt, tokenBytesFrom, lxTake_eq, vals_take, sameText_eq, raw]
    by_cases ident : t.kind = .identifier
    · simp only [ident, show TokenKind.identifier.gpuCode = 1 from rfl, decide_true, Bool.true_and, true_and]
      split <;> simp_all
    · have ident' : t.kind.gpuCode ≠ 1 := fun h => ident ((code_eq_iff _ .identifier).mp h)
      simp [ident, ident']

/-- The verified compiler's lexer is the Lean lexer. -/
theorem lexSource_eq (source : List Byte) : lexSource (vals source) = lexTokens source := by
  rw [lexTokens_eq_fast]
  simp only [lexSource, lexTokensFast, lexCanonical, lexRaw_eq_fast, lexRawFast, List.length_map, raw_eq]
  cases lexRawFromRest source (source.length + 1) 0 with
  | success tokens =>
    simp only [rawResult, canonicalizeRawResult, canonicalizeTokens, filterRetagTokens_eq_fast, filterRetagFast,
      filter_eq, ranges_eq, tokens_eq]
  | failure _ _ => rfl
  | fuelExhausted _ _ => rfl

end Lanius.Mini
