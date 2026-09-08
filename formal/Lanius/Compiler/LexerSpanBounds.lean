import Lanius.Compiler.LexerStream
import Lanius.Compiler.LexerNumberBounds

namespace Lanius.Compiler.Lexer

theorem startsWith_length_le {expected actual : List Nat}
    (matched : startsWith expected actual = true) : expected.length ≤ actual.length := by
  induction expected generalizing actual with
  | nil => simp
  | cons first rest induction =>
      cases actual with
      | nil => contradiction
      | cons head tail =>
          have restMatched := (Bool.and_eq_true_iff.mp matched).2
          exact Nat.succ_le_succ (induction restMatched)

private theorem comment_spelling_length (rule : SymbolRule) (member : rule ∈ symbolRules)
    (comment : rule.kind = .lineComment ∨ rule.kind = .blockComment) : rule.spelling.length = 2 := by
  have checked : symbolRules.all (fun rule =>
      if rule.kind = .lineComment ∨ rule.kind = .blockComment then decide (rule.spelling.length = 2) else true) = true := by
    decide
  have selected := List.all_eq_true.mp checked rule member
  simpa only [comment, if_true, decide_eq_true_eq] using selected

theorem scanFixedSymbol_token_end_le
    {source : List Byte} {start : Nat} {token : RawToken}
    (result : scanFixedSymbol source start = .token token) : token.finish ≤ source.length := by
  unfold scanFixedSymbol at result
  cases matched : matchSymbolHead (source.drop start) with
  | none => simp [matched] at result
  | some rule =>
      have selected := matchSymbolHead_spec matched
      have lengthBound := startsWith_length_le selected.2.1
      simp only [List.length_map, List.length_drop] at lengthBound
      have positive := symbolRules_spelling_length_pos selected.1
      simp only [matched] at result
      by_cases lineComment : rule.kind = .lineComment
      · have two := comment_spelling_length rule selected.1 (Or.inl lineComment)
        simp only [lineComment, if_true, OneTokenResult.token.injEq] at result
        cases result
        have consumed := splitPrefix_length_le (fun byte : Byte => byte.val != 10)
          (source.drop (start + 2))
        simp only [List.length_drop] at consumed
        change start + 2 + _ ≤ source.length
        omega
      · simp only [lineComment, if_false] at result
        by_cases blockComment : rule.kind = .blockComment
        · have two := comment_spelling_length rule selected.1 (Or.inr blockComment)
          simp only [blockComment, if_true, tokenFromDelimited] at result
          cases scanned : scanBlockCommentEnd source start with
          | failure error => simp [scanned] at result
          | success finish =>
              simp only [scanned, OneTokenResult.token.injEq] at result
              cases result
              have bounds := scanBlockBody_result_bounds (source.drop (start + 2)) (start + 2)
              change scanBlockBody (source.drop (start + 2)) (start + 2) = .success finish at scanned
              rw [scanned] at bounds
              simp only [List.length_drop] at bounds
              change finish ≤ source.length
              omega
        · simp only [blockComment, if_false, OneTokenResult.token.injEq] at result
          cases result
          change start + rule.spelling.length ≤ source.length
          omega

theorem scanSymbol_token_end_le
    {source : List Byte} {start : Nat} {token : RawToken}
    (result : scanSymbol source start = .token token) : token.finish ≤ source.length := by
  unfold scanSymbol at result
  repeat' first | contradiction | split at result
  all_goals first
    | exact scanFixedSymbol_token_end_le result
    | skip
  all_goals
    unfold tokenFromNumber at result
    repeat' first | contradiction | split at result
    all_goals grind only [→ scanLeadingDotNumber_success_end_le]

private theorem quoted_success_end_le {source : List Byte} {start finish : Nat} {delimiter : Byte}
    (inside : start < source.length)
    (result : scanQuotedEnd source start delimiter = .success finish) : finish ≤ source.length := by
  have bounds := scanQuotedBody_result_bounds delimiter false (source.drop (start + 1)) (start + 1)
  change scanQuotedBody delimiter false (source.drop (start + 1)) (start + 1) = .success finish at result
  rw [result] at bounds
  simp only [List.length_drop] at bounds
  omega

theorem scanOneAt_token_end_le
    {source : List Byte} {start : Nat} {token : RawToken}
    (result : scanOneAt source start = .token token) : token.finish ≤ source.length := by
  have inside := scanOneAt_token_before_end result
  unfold scanOneAt at result
  repeat' first | contradiction | split at result
  all_goals first
    | exact scanSymbol_token_end_le result
    | (cases result; exact scanIdentifierEnd_le_source_length source start inside)
    | (cases result; exact scanWhitespaceEnd_le_source_length source start inside)
    | skip
  all_goals
    simp only [tokenFromNumber, tokenFromDelimited] at result
    repeat' first | contradiction | split at result
    all_goals grind only [→ scanNumber_success_end_le, → quoted_success_end_le]

theorem scanOne_token_end_le
    {source : List Byte} {start : Nat} {token : RawToken}
    (inside : start ≤ source.length)
    (result : scanOne source start = .token token) : token.finish ≤ source.length := by
  unfold scanOne at result
  cases scanned : scanOneAt (source.drop start) 0 with
  | failure error => simp [scanned, OneTokenResult.shift] at result
  | token relative =>
      have bound := scanOneAt_token_end_le scanned
      simp only [scanned, OneTokenResult.shift, OneTokenResult.token.injEq] at result
      cases result
      simp only [RawToken.shift, List.length_drop] at bound ⊢
      omega

def RawLexResult.ValidSpans (sourceLength : Nat) : RawLexResult → Prop
  | .success tokens | .failure tokens _ | .fuelExhausted tokens _ =>
      ∀ token ∈ tokens, token.start ≤ token.finish ∧ token.finish ≤ sourceLength

theorem lexRawFromFuel_validSpans (source : List Byte) (fuel offset : Nat) :
    (lexRawFromFuel source fuel offset).ValidSpans source.length := by
  induction fuel generalizing offset with
  | zero => simp [lexRawFromFuel, RawLexResult.ValidSpans]
  | succ fuel induction =>
      simp only [lexRawFromFuel]
      split
      · simp [RawLexResult.ValidSpans]
      · rename_i beforeEnd
        cases scanned : scanOne source offset with
        | failure error => simp [RawLexResult.ValidSpans]
        | token head =>
            have startBound : head.start ≤ head.finish := by
              rw [scanOne_token_start scanned]
              exact Nat.le_of_lt (scanOne_token_advances scanned)
            have endBound := scanOne_token_end_le (Nat.le_of_lt (Nat.lt_of_not_ge beforeEnd)) scanned
            have tailSpans := induction head.finish
            cases tail : lexRawFromFuel source fuel head.finish <;>
              simp only [tail, RawLexResult.prepend, RawLexResult.ValidSpans] at tailSpans ⊢
            all_goals
              intro token member
              rcases List.mem_cons.mp member with rfl | member
              · exact ⟨startBound, endBound⟩
              · exact tailSpans token member

theorem lexRaw_validSpans (source : List Byte) : (lexRaw source).ValidSpans source.length :=
  lexRawFromFuel_validSpans source (source.length + 1) 0

end Lanius.Compiler.Lexer
