import Lanius.Extraction.Frontend.Storage.Tokens

namespace Lanius.Extraction.Frontend
open Lanius.Compiler Lanius.Compiler.Lexer

def encodedInteriorBytes (tokens : List Token) : Nat :=
  (tokens.map fun token => token.span.finish - token.span.start - 1).sum

theorem decode_length {α β : Type} {decode : α → Option β}
    {input : List α} {output : List β}
    (decoded : input.mapM decode = some output) : output.length = input.length := by
  induction input generalizing output with
  | nil => have same : [] = output := Option.some.inj decoded; subst output; rfl
  | cons head tail ih =>
      simp only [List.mapM_cons] at decoded
      cases first : decode head with
      | none => simp [first] at decoded
      | some value =>
          cases rest : tail.mapM decode with
          | none => simp [first, rest] at decoded
          | some values =>
              have same : value :: values = output := by simpa [first, rest] using decoded
              subst output
              simp only [List.length_cons, ih rest]

private theorem decoded_interiors (decoded : decodeTokens encoded = some tokens) :
    streamInteriorBytes tokens = encodedInteriorBytes encoded := by
  induction encoded generalizing tokens with
  | nil =>
      have same : [] = tokens := Option.some.inj decoded
      subst tokens
      rfl
  | cons head tail ih =>
      simp only [decodeTokens, List.mapM_cons] at decoded
      cases first : decodeToken head with
      | none => simp [first] at decoded
      | some token =>
          cases rest : tail.mapM decodeToken with
          | none => simp [first, rest] at decoded
          | some tokensTail =>
              have same : token :: tokensTail = tokens := by simpa [first, rest] using decoded
              subst tokens
              have span : tokenInteriorBytes token = head.span.finish - head.span.start - 1 := by
                rcases head with ⟨kind, ⟨file, start, finish⟩⟩
                simp only [decodeToken] at first
                by_cases wrongFile : file != 0
                · simp [wrongFile] at first
                simp only [wrongFile, Bool.false_eq_true, ↓reduceIte] at first
                by_cases backwards : start > finish
                · simp [backwards] at first
                simp only [backwards, ↓reduceIte] at first
                cases found : TokenKind.ofGpuCode kind with
                | none => simp [found] at first
                | some decodedKind =>
                    have same : ({kind := decodedKind, start, finish} : RawToken) = token := by
                      simpa [found] using first
                    subst token
                    rfl
              have tailEq := ih rest
              simp only [streamInteriorBytes, encodedInteriorBytes, List.map_cons, List.sum_cons] at tailEq ⊢
              rw [span, tailEq]

/-- Input-domain evidence derived from an already checked unit. The checker
below only inspects lengths and spans; it never invokes tokenization, parsing,
Surface reconstruction, or Core lowering again. -/
def ArtifactTokenStorage (artifact : Artifact) (rawWords canonicalWords kindWords : Nat) : Prop :=
  ∀ source tokens, decodeSingleSource artifact.sources = some source →
    decodeTokens artifact.tokens = some tokens →
    TokenStorage source tokens rawWords canonicalWords kindWords

/-- A source-only resource condition. Token witnesses are logical evidence,
not another token stream computed by the resource checker. -/
def SourceTokenStorage (file : SourceFile) (rawWords canonicalWords kindWords : Nat) : Prop :=
  ∃ source tokens, decodeBytes file.bytes = some source ∧
    TokenStorage source tokens rawWords canonicalWords kindWords

theorem ArtifactTokenStorage.source
    (storage : ArtifactTokenStorage artifact rawWords canonicalWords kindWords)
    (valid : TokenArtifactValid artifact) (member : file ∈ artifact.sources) :
    SourceTokenStorage file rawWords canonicalWords kindWords := by
  obtain ⟨source, tokens, _, sourceDecoded, tokensDecoded, _⟩ := valid
  have fits := storage source tokens sourceDecoded tokensDecoded
  cases sources : artifact.sources with
  | nil => simp [sources] at member
  | cons head tail =>
      cases tail with
      | cons _ _ => simp [sources, decodeSingleSource] at sourceDecoded
      | nil =>
          have same : file = head := by simpa only [sources, List.mem_singleton] using member
          subst file
          exact ⟨source, tokens, by simpa only [sources, decodeSingleSource] using sourceDecoded, fits⟩

def checkArtifactTokenStorage? (artifact : Artifact) (valid : TokenArtifactValid artifact)
    (rawWords canonicalWords kindWords : Nat) :
    Option (PLift (ArtifactTokenStorage artifact rawWords canonicalWords kindWords)) :=
  match sources : artifact.sources with
  | [sourceFile] =>
      let budget := sourceFile.bytes.length - encodedInteriorBytes artifact.tokens
      if fits : 3 * budget ≤ rawWords ∧ 3 * budget ≤ canonicalWords ∧ artifact.tokens.length ≤ kindWords then
        some ⟨by
          intro source tokens sourceDecoded tokensDecoded
          obtain ⟨checkedSource, checkedTokens, _, checkedBytes, checkedRows, lexical, _⟩ := valid
          have sourceEq := Option.some.inj (checkedBytes.symm.trans sourceDecoded)
          have tokensEq := Option.some.inj (checkedRows.symm.trans tokensDecoded)
          subst checkedSource
          subst checkedTokens
          have bytesDecoded : decodeBytes sourceFile.bytes = some source := by
            simpa only [sources, decodeSingleSource] using sourceDecoded
          have bytesLength := decode_length bytesDecoded
          have tokensLength := decode_length tokensDecoded
          have budgetEq : rawTokenBudget source.length tokens = budget := by
            simp only [rawTokenBudget, bytesLength, decoded_interiors tokensDecoded, budget]
          exact ⟨lexical, by simpa only [budgetEq] using fits.1,
            by simpa only [budgetEq] using fits.2.1,
            by simpa only [tokensLength] using fits.2.2⟩⟩
      else none
  | _ => none

end Lanius.Extraction.Frontend
