import Lanius.Extraction.SemanticTokens.Assignment

namespace Lanius.Extraction.SemanticTokens

open Lanius.Compiler.Parser

theorem ScanPath.assignments_from (path : ScanPath grammar tokens uses 0 (finalPosition tokens.length))
    (capacity : start + count ≤ tokens.length) :
    ∃ assignments, assignmentsFrom? uses start count = some assignments ∧ assignments.length = count ∧
      (∀ index raw, tokens[start + index]? = some raw → index < count →
        ∃ assignment, assignments[index]? = some assignment ∧ assignment.Valid grammar.grammar raw) := by
  induction count generalizing start with
  | zero => exact ⟨[], rfl, rfl, by intro index raw found bound; omega⟩
  | succ count ih =>
      have firstBound : start < tokens.length := by omega
      have firstFound := List.getElem?_eq_getElem firstBound
      obtain ⟨first, firstComputed, firstValid⟩ := path.assignment firstBound firstFound
      obtain ⟨rest, restComputed, restLength, restValid⟩ := ih (start := start + 1) (by omega)
      refine ⟨first :: rest, by simp [assignmentsFrom?, firstComputed, restComputed], by simp [restLength], ?_⟩
      intro index raw found bound
      cases index with
      | zero =>
          have rawEq : tokens[start] = raw := by
            have same := firstFound.symm.trans (by simpa only [Nat.add_zero] using found)
            exact Option.some.inj same
          exact ⟨first, rfl, rawEq ▸ firstValid⟩
      | succ index =>
          have foundNext : tokens[(start + 1) + index]? = some raw := by
            simpa only [Nat.add_assoc, Nat.add_comm 1 index] using found
          obtain ⟨assignment, assignmentFound, valid⟩ := restValid index raw foundNext (by omega)
          exact ⟨assignment, assignmentFound, valid⟩

theorem assignments_words_length (assignments : List Assignment) :
    (assignments.flatMap Assignment.words).length = 2 * assignments.length := by
  induction assignments with
  | nil => rfl
  | cons assignment rest ih => simp [Assignment.words, ih, Nat.mul_add]

/-- The existing Boolean checker follows from per-token assignment semantics.
Token spans are irrelevant to this part of the checker and remain unchanged. -/
theorem semanticKinds_of_assignments (grammar : Grammar) (kindsBound : grammar.n_kinds ≤ 32768)
    (tokens : List Token) (assignments : List Assignment) (lengthEq : assignments.length = tokens.length)
    (valid : ∀ (index : Nat) (token : Token), tokens[index]? = some token →
      ∃ assignment : Assignment, assignments[index]? = some assignment ∧ assignment.Valid grammar token.kind) :
    semanticKindsValid grammar tokens (assignments.map Assignment.code) = true := by
  induction tokens generalizing assignments with
  | nil =>
      have empty : assignments = [] := List.eq_nil_of_length_eq_zero lengthEq
      simp [semanticKindsValid, empty]
  | cons token tokens ih =>
      cases assignments with
      | nil => simp at lengthEq
      | cons assignment assignments =>
          obtain ⟨first, found, firstValid⟩ := valid 0 token rfl
          have same : first = assignment := by simpa using found.symm
          subst first
          have head := firstValid.matches kindsBound
          have tail := ih assignments (by simpa using lengthEq) (by
            intro index item found
            exact valid (index + 1) item found)
          simpa [semanticKindsValid, head] using tail

/-- The selected complete-input parse determines a full semantic assignment
vector. Its packed codes satisfy the actual compact artifact checker. This is
the logical target for collect, not a premise that collect already succeeded. -/
theorem selected_tree_assignments (tokens : List Token)
    (parse : MaterializedParse grammar (tokens.map Token.kind))
    (kindsBound : grammar.grammar.n_kinds ≤ 32768) :
    ∃ uses assignments,
      ScanPath grammar (tokens.map Token.kind) uses 0 (finalPosition tokens.length) ∧
      uses.map Use.leaf = treeLeaves parse.tree ∧
      (uses.map Use.slot).Nodup ∧
      assignmentsFrom? uses 0 tokens.length = some assignments ∧
      assignments.length = tokens.length ∧
      (assignments.flatMap Assignment.words).length = 2 * tokens.length ∧
      semanticKindsValid grammar.grammar tokens (assignments.map Assignment.code) = true := by
  obtain ⟨uses, path, leaves⟩ := tree_scan parse.recognizes
  obtain ⟨assignments, computed, lengthEq, valid⟩ := path.assignments_from
    (start := 0) (count := tokens.length) (by simp)
  refine ⟨uses, assignments, ?_, leaves, path.slots_unique, computed, lengthEq,
    by rw [assignments_words_length, lengthEq], ?_⟩
  · simpa only [List.length_map] using path
  · apply semanticKinds_of_assignments grammar.grammar kindsBound tokens assignments lengthEq
    intro index token found
    have rawFound : (tokens.map Token.kind)[0 + index]? = some token.kind := by simp [found]
    exact valid index token.kind rawFound (List.getElem?_eq_some_iff.mp found).1

end Lanius.Extraction.SemanticTokens
