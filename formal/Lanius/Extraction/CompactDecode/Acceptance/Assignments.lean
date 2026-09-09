import Lanius.Extraction.SemanticTokens.Assignment

namespace Lanius.Extraction.CompactDecode

open SemanticTokens

variable {assignments : List Assignment}

/-- Recover the exact assignment, not only its validity, from collection. -/
theorem assignments_lookup
    (computed : assignmentsFrom? uses start count = some assignments)
    (found : assignments[index]? = some assignment) :
    assignmentAt? uses (start + index) = some assignment := by
  induction count generalizing start assignments index with
  | zero => simp [assignmentsFrom?] at computed; subst assignments; simp at found
  | succ count ih =>
      cases head : assignmentAt? uses start <;> cases tail : assignmentsFrom? uses (start + 1) count <;>
        simp [assignmentsFrom?, head, tail] at computed
      subst assignments
      cases index with
      | zero => simpa using head.trans found
      | succ index =>
          simpa only [Nat.add_assoc, Nat.add_comm 1 index] using ih tail found

theorem assignment_advance_whole
    (found : assignments[token]? = some (Assignment.mk kind none))
    (bound : kind < 32768) :
    advanceTerminal (assignments.map Assignment.code) (2 * token) kind = some (2 * token + 2) := by
  have small : ¬ packedFlag ≤ kind := by simp only [packedFlag]; omega
  simp [advanceTerminal, List.getElem?_map, found, Assignment.code, isPackedSemanticKind, small]

theorem assignment_advance_first
    (found : assignments[token]? = some (Assignment.mk first (some second)))
    (firstBound : first < 32768) (secondBound : second < 32768) :
    advanceTerminal (assignments.map Assignment.code) (2 * token) first = some (2 * token + 1) := by
  obtain ⟨packed, inner, outer⟩ := packed_parts firstBound secondBound
  simp [advanceTerminal, List.getElem?_map, found, Assignment.code, packed, inner]

theorem assignment_advance_second
    (found : assignments[token]? = some (Assignment.mk first (some second)))
    (firstBound : first < 32768) (secondBound : second < 32768) :
    advanceTerminal (assignments.map Assignment.code) (2 * token + 1) second = some (2 * token + 2) := by
  obtain ⟨packed, inner, outer⟩ := packed_parts firstBound secondBound
  have index : (2 * token + 1) / 2 = token := by omega
  have parity : (2 * token + 1) % 2 = 1 := by omega
  simp [advanceTerminal, List.getElem?_map, index, parity, found, Assignment.code, packed, outer,
    show 2 * token + 1 + 1 = 2 * token + 2 from by omega]

end Lanius.Extraction.CompactDecode
