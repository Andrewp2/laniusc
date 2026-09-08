import Lanius.Extraction.BufferCopy.Loop
import Lanius.Extraction.CanonicalTokens.Compaction.Invariant

namespace Lanius.Extraction.BufferCopy

open Lanius.Compiler Lanius.Compiler.Lexer
open Lanius.Extraction.CanonicalTokens CanonicalizeModel Compaction

/-- The contiguous copy reads the raw records already emitted by the lexer;
spare source capacity is never treated as a token. -/
theorem raw_selected (raw : List RawToken) (unused : List Int) (index : Nat) (value : Int)
    (selected : (encodeTokens raw)[index]? = some value) :
    (encodeTokens raw ++ unused)[index * Scale.plain.factor]? = some value := by
  have bound : index < (encodeTokens raw).length := by
    by_cases inside : index < (encodeTokens raw).length
    · exact inside
    · rw [List.getElem?_eq_none (by omega)] at selected
      contradiction
  simpa only [Scale.factor, Nat.mul_one, List.getElem?_append_left bound] using selected

def tokenKinds (tokens : List RawToken) : List Int :=
  tokens.map (fun token => Int.ofNat token.kind.gpuCode)

/-- After compaction, every third word is the corresponding semantic token
kind. The untouched suffix cannot affect this selection. -/
theorem kinds_selected (raw canonical : List RawToken) (unused : List Int)
    (index : Nat) (value : Int)
    (selected : (tokenKinds canonical)[index]? = some value) :
    (compactedBuffer raw unused canonical)[index * Scale.triple.factor]? = some value := by
  simp only [tokenKinds, List.getElem?_map, Option.map_eq_some_iff] at selected
  obtain ⟨token, tokenSelected, rfl⟩ := selected
  have bound : index < canonical.length := by
    by_cases inside : index < canonical.length
    · exact inside
    · rw [List.getElem?_eq_none (by omega)] at tokenSelected
      contradiction
  have row := (encoded_row canonical [] index token tokenSelected).1
  have wordBound : 3 * index < (encodeTokens canonical).length := by
    rw [encoded_length]
    omega
  simpa only [compactedBuffer, Scale.factor, Nat.mul_comm index 3,
    replacePrefix_written _ _ _ wordBound, List.append_nil] using row

/-- Exact canonicalizer input after copying the raw-token words. -/
theorem raw_buffer (untouched : List Int) (raw : List RawToken) :
    buffer untouched (encodeTokens raw) =
      encodeTokens raw ++ untouched.drop (3 * raw.length) := by
  simp only [buffer, encoded_length]

end Lanius.Extraction.BufferCopy
