import Lanius.Compiler.Lexer.Storage
import Lanius.Extraction.Frontend.Call

namespace Lanius.Extraction.Frontend
open Lanius Lanius.Core Lanius.Semantics Lanius.Compiler Lanius.Compiler.Lexer
open Lanius.Extraction.RawLexer.LexInto

/-- Lexical validity and concrete storage bounds, independent of the result
of the Lanius extractor. The budget uses certified canonical spans, so no
second raw-lexer run is needed to establish these conditions. -/
structure TokenStorage (source : List Byte) (tokens : List RawToken)
    (rawWords canonicalWords kindWords : Nat) : Prop where
  lexical : lexCanonical source = .success tokens
  rawFits : 3 * rawTokenBudget source.length tokens ≤ rawWords
  canonicalFits : 3 * rawTokenBudget source.length tokens ≤ canonicalWords
  kindsFit : tokens.length ≤ kindWords

theorem TokenStorage.realizes {request : Model.Request}
    (storage : TokenStorage request.source tokens rawWords canonicalWords kindWords)
    (capacity : request.capacity = rawWords / 3) :
    ∃ raw, request.outcome = .completed raw ∧ canonicalizeTokens request.source raw = tokens ∧
      3 * raw.length ≤ canonicalWords := by
  obtain ⟨raw, lexed, canonicalized, bound⟩ := lexCanonical_raw_budget storage.lexical
  have fits : raw.length ≤ request.capacity := by have := storage.rawFits; omega
  exact ⟨raw, Model.successful_unbounded_stream_preserved lexed fits, canonicalized,
    Nat.le_trans (Nat.mul_le_mul_left 3 bound) storage.canonicalFits⟩

/-- Under the lexical/storage domain, the source-linked frontend reaches
the parser phase: neither lexer nor token-buffer failure can be returned.
Parser, tree, and output limits are deliberately not hidden in this domain. -/
theorem SyntaxData.Post.no_token_failure {data : SyntaxData} {tokens : List RawToken}
    (post : data.Post stage detail count nodes words position before after)
    (valid : data.Valid)
    (storage : TokenStorage data.request.source tokens data.records.length data.canonical.length data.kinds.length) :
    stage ≠ 2 ∧ stage ≠ 3 ∧ count = tokens.length := by
  obtain ⟨raw, completed, canonicalized, fits⟩ := storage.realizes valid.wordCapacity
  have rawEq : data.raw = raw := by simp only [SyntaxData.raw, completed, Model.emittedTokens]
  have tokensEq : data.tokens = tokens := by simp only [SyntaxData.tokens, rawEq, canonicalized]
  rcases post with early | ⟨_, _, countEq, _, full | ⟨_, _, _, _, _, _, parsed, _⟩⟩
  · have impossible := early.1
    simp only [completed, lexerEarlyPost] at impossible
    omega
  · have noRoom := full.1
    simp only [rawEq, canonicalized] at noRoom
    have := storage.kindsFit
    omega
  · have countSame : count = tokens.length := by simpa only [rawEq, canonicalized] using countEq
    rcases parsed with ⟨parserStage, _⟩ | ⟨root, treeStage, _, _⟩
    · exact ⟨by omega, by omega, countSame⟩
    · unfold extractionTreeStage at treeStage
      split at treeStage <;> exact ⟨by omega, by omega, countSame⟩

end Lanius.Extraction.Frontend
