import Lanius.Extraction.CompactDecode.Fields
import Lanius.Extraction.CompactDecode.Repeat
import Lanius.Extraction.CompactOutput.Assignments.Loop

namespace Lanius.Extraction.CompactDecode

open CompactOutput SemanticTokens Lanius.Compiler.Lexer

theorem readAssignment_encoding (assignment : Assignment)
    (firstFit : assignment.first < 4294967296)
    (secondFit : (Assignments.secondWord assignment + 1).toNat < 4294967296)
    (encoded : EncodedAt bytes offset
      (Assignments.encoding assignment.first (Assignments.secondWord assignment))) :
    readSemanticKind.run {bytes, offset} =
      some (assignment.code, {bytes, offset := offset + 16}) := by
  have run := readSemanticKind_fields firstFit secondFit encoded
  cases assignment with
  | mk first second =>
    cases second <;>
      simpa [Assignments.secondWord, Assignment.code, packedFlag, packedKindBase] using run

theorem reads_assignments (assignments : List Assignment)
    (fits : ∀ a ∈ assignments, a.first < 4294967296 ∧
      (Assignments.secondWord a + 1).toNat < 4294967296)
    (encoded : EncodedAt bytes offset (Assignments.encodeAll assignments)) :
    Reads readSemanticKind {bytes, offset} (assignments.map Assignment.code)
      {bytes, offset := offset + assignments.length * 16} := by
  induction assignments generalizing offset with
  | nil => exact Reads.nil
  | cons a assignments ih =>
    have fit := fits a List.mem_cons_self
    have head := readAssignment_encoding a fit.1 fit.2 encoded.left
    have rest := encoded.right
    simp only [Assignments.encoding, List.length_append, hexDigits_length] at rest
    have tail := ih (fun a h => fits a (List.mem_cons_of_mem _ h)) rest
    simpa [Nat.add_mul, Nat.add_assoc, Nat.add_comm, Nat.add_left_comm] using Reads.cons head tail

theorem reads_tokens (tokens : List RawToken)
    (fits : ∀ t ∈ tokens, t.kind.gpuCode < 4294967296 ∧ t.start < 4294967296 ∧ t.finish < 4294967296)
    (encoded : EncodedAt bytes offset (tokens.flatMap Tokens.encoding)) :
    Reads readToken {bytes, offset}
      (tokens.map fun t => ⟨t.kind.gpuCode, ⟨0, t.start, t.finish⟩⟩)
      {bytes, offset := offset + tokens.length * 24} := by
  induction tokens generalizing offset with
  | nil => exact Reads.nil
  | cons t tokens ih =>
    have fit := fits t List.mem_cons_self
    have head := readToken_encoding t fit.1 fit.2.1 fit.2.2 encoded.left
    have rest := encoded.right
    simp only [Tokens.encoding, List.length_append, hexDigits_length] at rest
    have tail := ih (fun t h => fits t (List.mem_cons_of_mem _ h)) rest
    simpa [Nat.add_mul, Nat.add_assoc, Nat.add_comm, Nat.add_left_comm] using Reads.cons head tail

theorem readAssignments_encoding (assignments : List Assignment)
    (fits : ∀ a ∈ assignments, a.first < 4294967296 ∧
      (Assignments.secondWord a + 1).toNat < 4294967296)
    (encoded : EncodedAt bytes offset (Assignments.encodeAll assignments)) :
    (readMany assignments.length readSemanticKind).run {bytes, offset} =
      some (assignments.map Assignment.code, {bytes, offset := offset + assignments.length * 16}) := by
  simpa only [List.length_map] using (reads_assignments assignments fits encoded).readMany

theorem readTokens_encoding (tokens : List RawToken)
    (fits : ∀ t ∈ tokens, t.kind.gpuCode < 4294967296 ∧ t.start < 4294967296 ∧ t.finish < 4294967296)
    (encoded : EncodedAt bytes offset (tokens.flatMap Tokens.encoding)) :
    (readMany tokens.length readToken).run {bytes, offset} =
      some (tokens.map (fun t => ⟨t.kind.gpuCode, ⟨0, t.start, t.finish⟩⟩),
        {bytes, offset := offset + tokens.length * 24}) := by
  simpa only [List.length_map] using (reads_tokens tokens fits encoded).readMany

end Lanius.Extraction.CompactDecode
