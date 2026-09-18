import Lanius.Compiler.LexerCanonical
import Lanius.Compiler.LexerSpanBounds

namespace Lanius.Compiler.Lexer

/-- Bytes inside a token cannot start another raw token. Canonicalization
preserves these spans even when it changes a token's kind. -/
def tokenInteriorBytes (token : RawToken) : Nat := token.finish - token.start - 1

def streamInteriorBytes (tokens : List RawToken) : Nat :=
  (tokens.map tokenInteriorBytes).sum

/-- An upper bound using already-certified canonical spans. Bytes outside
those spans are conservatively allowed to start one raw token each. -/
def rawTokenBudget (sourceLength : Nat) (canonical : List RawToken) : Nat :=
  sourceLength - streamInteriorBytes canonical

theorem RawTokenPrefix.consumed_bytes
    (trace : RawTokenPrefix source offset tokens finish) :
    offset + tokens.length + streamInteriorBytes tokens = finish := by
  induction trace with
  | empty => simp [streamInteriorBytes]
  | accepted beforeEnd scanned tail ih =>
      have start := scanOne_token_start scanned
      have advances := scanOne_token_advances scanned
      simp only [List.length_cons, streamInteriorBytes, List.map_cons, List.sum_cons] at ih ⊢
      simp only [tokenInteriorBytes] at ih ⊢
      omega

theorem RawTokenPrefix.finish_le_source
    (trace : RawTokenPrefix source offset tokens finish)
    (inside : offset ≤ source.length) : finish ≤ source.length := by
  induction trace with
  | empty => exact inside
  | accepted beforeEnd scanned tail ih =>
      exact ih (scanOne_token_end_le (Nat.le_of_lt beforeEnd) scanned)

theorem Canonicalizes.interior_le (canonicalized : Canonicalizes source raw canonical) :
    streamInteriorBytes canonical ≤ streamInteriorBytes raw := by
  induction canonicalized with
  | empty => exact Nat.le_refl _
  | dropsTrivia _ _ ih =>
      simp only [streamInteriorBytes, List.map_cons, List.sum_cons] at ih ⊢
      omega
  | keepsToken _ _ ih =>
      simp only [streamInteriorBytes, List.map_cons, List.sum_cons, tokenInteriorBytes] at ih ⊢
      omega

theorem InclusiveRangeRetags.interior_eq (retagged : InclusiveRangeRetags before after) :
    streamInteriorBytes after = streamInteriorBytes before := by
  induction retagged with
  | empty => rfl
  | singleton => rfl
  | inclusive _ _ ih =>
      simp only [streamInteriorBytes, List.map_cons, List.sum_cons, tokenInteriorBytes] at ih ⊢
      omega
  | ordinary _ _ ih =>
      simp only [streamInteriorBytes, List.map_cons, List.sum_cons] at ih ⊢
      omega

theorem canonicalizeTokens_interior_le (source : List Byte) (raw : List RawToken) :
    streamInteriorBytes (canonicalizeTokens source raw) ≤ streamInteriorBytes raw := by
  unfold canonicalizeTokens
  rw [(retagInclusiveRanges_spec _).interior_eq]
  exact (filterRetagTokens_spec source raw).interior_le

theorem rawTokenBudget_bounds
    (lexed : lexRaw source = .success raw) :
    raw.length ≤ rawTokenBudget source.length (canonicalizeTokens source raw) := by
  obtain ⟨finish, trace, _⟩ := lexRaw_success_consumes_source lexed
  have consumed := trace.consumed_bytes
  have bounded := trace.finish_le_source (Nat.zero_le _)
  have retained := canonicalizeTokens_interior_le source raw
  unfold rawTokenBudget
  omega

/-- Canonical validity already entails a raw stream. Recover that logical
witness without rerunning the lexer to discover or check token counts. -/
theorem lexCanonical_raw_budget (lexed : lexCanonical source = .success canonical) :
    ∃ raw, lexRaw source = .success raw ∧ canonicalizeTokens source raw = canonical ∧
      raw.length ≤ rawTokenBudget source.length canonical := by
  unfold lexCanonical at lexed
  cases rawResult : lexRaw source with
  | success raw =>
      rw [rawResult] at lexed
      have same : canonicalizeTokens source raw = canonical := RawLexResult.success.inj lexed
      exact ⟨raw, rfl, same, by simpa only [same] using rawTokenBudget_bounds rawResult⟩
  | failure raw offset => simp [rawResult, canonicalizeRawResult] at lexed
  | fuelExhausted raw offset => simp [rawResult, canonicalizeRawResult] at lexed

end Lanius.Compiler.Lexer
