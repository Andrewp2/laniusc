import Lanius.Extraction.CanonicalTokens.Kind.Execution
import Lanius.Extraction.CanonicalTokens.Dispatch.Lexer

namespace Lanius.Extraction.CanonicalTokens.Kind

open Lanius.Compiler Lanius.Compiler.Lexer

theorem code_identifier_iff (kind : TokenKind) :
    (Int.ofNat kind.gpuCode = 1) ↔ kind = .identifier := by
  cases kind <;> decide

/-- The callable helper's integer result is the independent lexer specification,
not just a second description of the extracted dispatcher. -/
theorem result_canonicalKind (source : List Byte) (token : RawToken) :
    result (source.map (fun byte => Int.ofNat byte.val)) (Int.ofNat token.kind.gpuCode)
      token.start (token.finish - token.start) = Int.ofNat (canonicalKind source token).gpuCode := by
  unfold result canonicalKind
  simp only [code_identifier_iff]
  by_cases identifier : token.kind = .identifier
  · simp only [if_pos identifier]
    rw [Dispatch.lookup_reference_lexer]
    have span :
        (((source.map (fun byte => Int.ofNat byte.val)).drop token.start).take
          (token.finish - token.start)).map Int.toNat = tokenByteValues source token := by
      simp [tokenByteValues, List.map_drop, List.map_take, List.map_map, Function.comp_def]
    rw [span]
    cases exactKeywordKind (tokenByteValues source token) keywordRules <;> rfl
  · simp only [if_neg identifier]

end Lanius.Extraction.CanonicalTokens.Kind
