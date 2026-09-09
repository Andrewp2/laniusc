import Lanius.Extraction.CompactDecode.Acceptance.Tokens
import Lanius.Extraction.CompactDecode.Emission

namespace Lanius.Extraction.CompactDecode

open Lanius.Compiler.Lexer CompactOutput

theorem emission_tokens_accepted (emission : Unit.Emission) (path : String)
    (assignments : List SemanticTokens.Assignment) (records : List SemanticTokens.RecordVisit)
    (lexed : lexRaw emission.data.request.source = .success emission.data.raw) :
    checkTokenArtifact (emissionUnit emission path assignments records).artifact = true := by
  have rawDecoded := decodeTokens_rows emission.data.raw
    (fun token member => (Unit.raw_fields emission.data token member).2.1)
  have canonicalDecoded := decodeTokens_rows emission.data.tokens
    (fun token member => (Unit.canonical_fields emission.data token member).2.1)
  have trace : RawLexes emission.data.request.source 0 (.success emission.data.raw) :=
    lexed ▸ lexRaw_sound emission.data.request.source
  obtain ⟨finish, prefixTrace, _⟩ := trace.success_witness
  have accepted := checkRawTokenTrace_complete trace
  have canonical := canonicalizeTokensFromTrace_eq prefixTrace
  simp only [checkTokenArtifact, emissionUnit, UnitData.artifact, Artifact.empty,
    bne_self_eq_false, Bool.false_eq_true, ↓reduceIte, decodeSingleSource,
    sourceArray_values, decodeBytes_values, rawDecoded, canonicalDecoded,
    accepted, Bool.true_and]
  rw [canonical]
  exact beq_self_eq_true _

theorem completed_lexRaw (request : RawLexer.LexInto.Model.Request)
    (completed : request.outcome = .completed raw) :
    lexRaw request.source = .success raw := by
  unfold RawLexer.LexInto.Model.Request.outcome RawLexer.LexInto.Model.lexInto
    RawLexer.LexInto.Model.limitResult at completed
  cases found : lexRaw request.source with
  | success tokens =>
      simp only [found, RawLexer.LexInto.Model.limitAccepted] at completed
      split at completed
      · cases completed
        rfl
      · contradiction
  | failure tokens error =>
      simp only [found, RawLexer.LexInto.Model.limitAccepted] at completed
      split at completed <;> contradiction
  | fuelExhausted tokens offset =>
      exact False.elim (lexRaw_ne_exhausted request.source tokens offset found)

/-- Successful execution of the public frontend supplies every lexical
premise of the emitted artifact checker. -/
theorem frontend_tokens_accepted (emission : Unit.Emission) (path : String)
    (assignments : List SemanticTokens.Assignment) (records : List SemanticTokens.RecordVisit)
    (post : emission.data.Post stage detail count nodes words position before after)
    (success : stage = 0) :
    checkTokenArtifact (emissionUnit emission path assignments records).artifact = true := by
  have completed := (Frontend.bodyPost.success post success).1
  exact emission_tokens_accepted emission path assignments records
    (completed_lexRaw emission.data.request completed)

end Lanius.Extraction.CompactDecode
