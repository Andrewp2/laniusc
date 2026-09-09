import Lanius.Extraction.TokenChecker

namespace Lanius.Extraction

open Lanius.Compiler Lanius.Compiler.Lexer

/-- A successful lexer trace passes the streaming artifact checker without
requiring an independent checker-success assumption. -/
theorem checkRawTokenTraceFrom_complete
    (trace : RawTokenPrefix source offset tokens finish)
    (atEnd : source.length ≤ finish) :
    checkRawTokenTraceFrom (source.drop offset) offset tokens = true := by
  induction trace with
  | empty => simp [checkRawTokenTraceFrom, List.drop_eq_nil_of_le atEnd]
  | @accepted offset token tokens finish beforeEnd scanned tail ih =>
      unfold scanOne at scanned
      cases found : scanOneAt (source.drop offset) 0 with
      | failure error => simp [found, OneTokenResult.shift] at scanned
      | token relative =>
          simp only [found, OneTokenResult.shift, OneTokenResult.token.injEq] at scanned
          subst token
          simpa [checkRawTokenTraceFrom, found, List.drop_drop, RawToken.shift] using ih atEnd

theorem checkRawTokenTrace_complete
    (trace : RawLexes source 0 (.success tokens)) :
    checkRawTokenTrace source tokens = true := by
  obtain ⟨finish, prefixTrace, atEnd⟩ := trace.success_witness
  simpa [checkRawTokenTrace] using checkRawTokenTraceFrom_complete prefixTrace atEnd

theorem decodeBytes_values (bytes : List Byte) :
    decodeBytes (bytes.map Fin.val) = some bytes := by
  induction bytes with
  | nil => rfl
  | cons byte bytes ih =>
      simp only [decodeBytes, List.mapM_map] at ih
      simp [decodeBytes, List.mapM_cons, decodeByte, byte.isLt, ih]

theorem decodeTokens_rows (tokens : List RawToken)
    (spans : ∀ token ∈ tokens, token.start ≤ token.finish) :
    decodeTokens (tokens.map fun t => ⟨t.kind.gpuCode, ⟨0, t.start, t.finish⟩⟩) =
      some tokens := by
  induction tokens with
  | nil => rfl
  | cons token tokens ih =>
      have bound := spans token List.mem_cons_self
      have tail := ih (fun t member => spans t (List.mem_cons_of_mem _ member))
      simp only [decodeTokens, List.mapM_map] at tail
      simp [decodeTokens, List.mapM_cons, decodeToken, Nat.not_lt.mpr bound,
        TokenKind.ofGpuCode_gpuCode, tail]

end Lanius.Extraction
