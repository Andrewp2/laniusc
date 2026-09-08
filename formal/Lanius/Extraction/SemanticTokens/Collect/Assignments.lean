import Lanius.Extraction.SemanticTokens.Collect.Written

namespace Lanius.Extraction.SemanticTokens.Collect

open Lanius.Compiler.Parser

/-- The signed word at a lattice position: an unassigned second half stays -1. -/
def assignmentWord (uses : List Use) (position : Nat) : Int :=
  ((findUse? uses position).map (fun use => Int.ofNat use.kind)).getD (-1)

theorem writeUses_present (unique : (uses.map Use.slot).Nodup)
    (member : use ∈ uses) (bound : use.slot < values.length) :
    (writeUses values uses)[use.slot]? = some (Int.ofNat use.kind) := by
  induction uses generalizing values with
  | nil => simp at member
  | cons first rest ih =>
      have distinct := List.nodup_cons.mp unique
      rcases List.mem_cons.mp member with rfl | later
      · have absent : ∀ next ∈ rest, next.slot ≠ use.slot := by
          intro next member same
          exact distinct.1 (List.mem_map.mpr ⟨next, member, same⟩)
        change (writeUses (values.set use.slot use.kind) rest)[use.slot]? = _
        rw [writeUses_untouched absent, List.getElem?_set_self bound]
        rfl
      · exact ih distinct.2 later (by simpa only [List.length_set] using bound)

theorem written_word (unique : (uses.map Use.slot).Nodup)
    (positions : ∀ use ∈ uses, use.slot = use.position)
    (bound : position < count * 2) :
    (written original count uses)[position]? = some (assignmentWord uses position) := by
  cases found : findUse? uses position with
  | none =>
      have absent : ∀ use ∈ uses, use.slot ≠ position := by
        intro use member same
        have notFound := List.find?_eq_none.mp found use member
        simp [← positions use member, same] at notFound
      rw [written, writeUses_untouched absent]
      simp [initialized, BufferCopy.buffer, List.getElem?_append_left
        (show position < (List.replicate (count * 2) (-1 : Int)).length from by simpa using bound),
        bound, assignmentWord, found]
  | some use =>
      have member := List.mem_of_find?_eq_some found
      have atPosition : use.slot = position :=
        (positions use member).trans (by simpa using List.find?_some found)
      have room : use.slot < (initialized original (count * 2)).length := by
        simp only [initialized, BufferCopy.buffer, List.length_append, List.length_replicate]
        omega
      simpa only [written, atPosition, assignmentWord, found, Option.map_some, Option.getD_some] using
        writeUses_present unique member room

theorem assignmentAt_words (computed : assignmentAt? uses token = some assignment) :
    assignment.words = [assignmentWord uses (2 * token), assignmentWord uses (2 * token + 1)] := by
  cases first : findUse? uses (2 * token) with
  | none => simp [assignmentAt?, first] at computed
  | some use =>
      simp [assignmentAt?, first] at computed
      subst assignment
      cases second : findUse? uses (2 * token + 1) <;>
        simp [Assignment.words, assignmentWord, first, second]

theorem assignmentsFrom_length (computed : assignmentsFrom? uses start count = some assignments) :
    assignments.length = count := by
  induction count generalizing start assignments with
  | zero => simpa [assignmentsFrom?] using congrArg (Option.map List.length) computed.symm
  | succ count ih =>
      cases head : assignmentAt? uses start <;> cases tail : assignmentsFrom? uses (start + 1) count <;>
        simp [assignmentsFrom?, head, tail] at computed
      subst assignments
      simp [ih tail]

/-- Logical collection reads its two words per token in source order, even
when the writes that produced them occurred in a different record order. -/
theorem assignmentsFrom_word (computed : assignmentsFrom? uses start count = some assignments)
    (bound : index < count * 2) :
    (assignments.flatMap Assignment.words)[index]? = some (assignmentWord uses (2 * start + index)) := by
  induction count generalizing start assignments index with
  | zero => omega
  | succ count ih =>
      cases head : assignmentAt? uses start <;> cases tail : assignmentsFrom? uses (start + 1) count <;>
        simp [assignmentsFrom?, head, tail] at computed
      subst assignments
      rw [List.flatMap_cons, assignmentAt_words head]
      cases index with
      | zero => simp
      | succ index =>
          cases index with
          | zero => simp
          | succ index =>
              simpa only [List.cons_append, List.nil_append, List.getElem?_cons_succ,
                show 2 * (start + 1) + index = 2 * start + (index + 1 + 1) from by omega] using
                ih tail (index := index) (by omega)

/-- Exact physical output, including its untouched capacity suffix. The
collector's computed assignment vector is derived from its writes, not assumed. -/
theorem written_assignments (computed : assignmentsFrom? uses 0 count = some assignments)
    (unique : (uses.map Use.slot).Nodup)
    (positions : ∀ use ∈ uses, use.slot = use.position)
    (bounded : ∀ use ∈ uses, use.slot < count * 2) :
    written original count uses = assignments.flatMap Assignment.words ++ original.drop (count * 2) := by
  have lengthEq : (assignments.flatMap Assignment.words).length = count * 2 := by
    rw [assignments_words_length, assignmentsFrom_length computed]
    omega
  apply List.ext_getElem?
  intro index
  by_cases inside : index < count * 2
  · rw [written_word unique positions inside,
      List.getElem?_append_left (by omega), assignmentsFrom_word computed inside]
    simp
  · have absent : ∀ use ∈ uses, use.slot ≠ index := by
      intro use member
      have bound := bounded use member
      omega
    rw [written, writeUses_untouched absent]
    simp only [initialized, BufferCopy.buffer,
      List.getElem?_append_right (by simpa using Nat.le_of_not_lt inside :
        (List.replicate (count * 2) (-1 : Int)).length ≤ index),
      List.getElem?_append_right (by omega : (assignments.flatMap Assignment.words).length ≤ index),
      lengthEq, List.length_replicate]

theorem _root_.Lanius.Extraction.SemanticTokens.CollectionRecords.use_properties
    {data : CollectionRecords grammar tokens tree nodeBase wordBase}
    (member : use ∈ data.records.flatMap RecordVisit.uses) :
    use.slot = use.position ∧ use.slot < tokens.length * 2 := by
  obtain ⟨record, recordMember, useMember⟩ := List.mem_flatMap.mp member
  obtain ⟨child, childMember, useMember⟩ := List.mem_flatMap.mp useMember
  cases child with
  | node => simp [ChildVisit.uses] at useMember
  | token found =>
      have same : use = found := by simpa [ChildVisit.uses] using useMember
      subst found
      obtain ⟨valid, atPosition, _, finish⟩ := data.token_child recordMember childMember
      have advances := valid.advances
      exact ⟨atPosition, by simp only [finalPosition] at finish; omega⟩

theorem _root_.Lanius.Extraction.SemanticTokens.CollectionRecords.written
    {data : CollectionRecords grammar tokens tree nodeBase wordBase}
    (original : List Int) :
    written original tokens.length (data.records.flatMap RecordVisit.uses) =
      data.assignments.flatMap Assignment.words ++ original.drop (tokens.length * 2) :=
  written_assignments data.computed data.unique
    (fun _ member => (data.use_properties member).1)
    (fun _ member => (data.use_properties member).2)

end Lanius.Extraction.SemanticTokens.Collect
