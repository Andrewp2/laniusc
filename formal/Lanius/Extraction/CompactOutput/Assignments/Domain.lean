import Lanius.Extraction.SemanticTokens.Assignment
import Lanius.Extraction.CompactOutput.Assignments.Fields

namespace Lanius.Extraction.CompactOutput.Assignments

open Lanius.Extraction.SemanticTokens

def secondWord (assignment : Assignment) : Int :=
  match assignment.second with | none => -1 | some value => value

/-- The serializer's arithmetic premise follows from the collector's semantic
validity, rather than becoming a new unchecked assumption at the handoff. -/
theorem field_bounds (assignment : Assignment) (valid : assignment.Valid grammar raw)
    (kindsBound : grammar.n_kinds ≤ 32768) :
    assignment.first ≤ 2147483647 ∧ -1 ≤ secondWord assignment ∧
      secondWord assignment < 2147483647 := by
  obtain ⟨first, second⟩ := assignment
  cases second with
  | none =>
    simp only [Assignment.Valid] at valid
    simp only [secondWord]
    omega
  | some second =>
    simp only [Assignment.Valid] at valid
    simp only [secondWord]
    omega

theorem stored_fields (assignment : Assignment) :
    assignment.words = [Int.ofNat assignment.first, secondWord assignment] := by
  cases assignment with
  | mk first second => cases second <;> rfl

end Lanius.Extraction.CompactOutput.Assignments
