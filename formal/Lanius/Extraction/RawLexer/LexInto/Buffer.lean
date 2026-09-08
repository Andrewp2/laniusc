import Lanius.Extraction.RawLexer.LexInto.Model
import Lanius.Extraction.CanonicalTokens.Compaction.Invariant

namespace Lanius.Extraction.RawLexer.LexInto

open Lanius Lanius.Compiler Lanius.Compiler.Lexer Lanius.Semantics
open CanonicalTokens.Compaction CanonicalTokens.CanonicalizeModel

/-- The lexer's three stores append an encoded row to the written prefix,
without changing the caller's remaining storage. -/
theorem writeTokens_prefix (original : List Int) (completed pending : List RawToken)
    (fits : 3 * (completed.length + pending.length) ≤ original.length) :
    Model.writeTokens (replacePrefix original (encodeTokens completed)) completed.length pending =
      replacePrefix original (encodeTokens (completed ++ pending)) := by
  induction pending generalizing completed with
  | nil => simp [Model.writeTokens]
  | cons token rest induction =>
      have room : (encodeTokens completed).length + 3 ≤ original.length := by
        simp only [encoded_length, List.length_cons] at *
        omega
      have row : Model.writeToken (replacePrefix original (encodeTokens completed))
          completed.length token =
          replacePrefix original (encodeTokens (completed ++ [token])) := by
        have pushed := replacePrefix_push_row original (encodeTokens completed)
          (Int.ofNat token.kind.gpuCode) (Int.ofNat token.start) (Int.ofNat token.finish) room
        rw [encoded_length] at pushed
        simpa [Model.writeToken, setI32Value, writeRow, encoded_append,
          encodeTokens, encodeToken] using pushed
      rw [Model.writeTokens, row]
      have tailFits : 3 * ((completed ++ [token]).length + rest.length) ≤ original.length := by
        simp only [List.length_append, List.length_cons, List.length_nil] at *
        omega
      simpa [List.append_assoc] using induction (completed ++ [token]) tailFits

/-- This is precisely the raw-token prefix and spare-capacity format required
by the proved in-place canonicalizer, including lexer failure prefixes. -/
theorem run_records_prefix (source : List Byte) (capacity : Nat) (records : List Int)
    (size : 3 * capacity ≤ records.length) :
    (Model.run source capacity records).records =
      encodeTokens (Model.emittedTokens (Model.lexInto source capacity)) ++
        records.drop (3 * (Model.emittedTokens (Model.lexInto source capacity)).length) := by
  rw [Model.run_records]
  have fits : 3 * (([] : List RawToken).length + (Model.emittedTokens (Model.lexInto source capacity)).length) ≤ records.length := by
    simpa only [List.length_nil, Nat.zero_add] using
      (Nat.le_trans (Nat.mul_le_mul_left 3 (Model.emittedTokens_length_le_capacity source capacity)) size)
  simpa [replacePrefix, encoded_length, (show encodeTokens ([] : List RawToken) = [] from rfl)] using
    writeTokens_prefix records [] (Model.emittedTokens (Model.lexInto source capacity)) fits

/-- The source uses floor division to convert word capacity to token capacity.
    Spare words beyond that capacity survive every normal lexer outcome. -/
theorem run_records_spare (source : List Byte) (capacity : Nat) (records : List Int)
    (fits : 3 * capacity ≤ records.length) :
    (Model.run source capacity records).records.drop (3 * capacity) = records.drop (3 * capacity) := by
  rw [run_records_prefix source capacity records fits]
  have written := Nat.mul_le_mul_left 3 (Model.emittedTokens_length_le_capacity source capacity)
  rw [List.drop_append, encoded_length]
  have empty : (encodeTokens (Model.emittedTokens (Model.lexInto source capacity))).drop (3 * capacity) = [] :=
    List.drop_eq_nil_of_le (by simpa only [encoded_length] using written)
  rw [empty, List.nil_append, List.drop_drop]
  congr 1
  omega

end Lanius.Extraction.RawLexer.LexInto
