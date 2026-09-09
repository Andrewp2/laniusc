import Lanius.Extraction.CompactDecode.Acceptance.Assignments
import Lanius.Extraction.SemanticTokens.Order
import Lanius.Extraction.SemanticTokens.Records

namespace Lanius.Extraction.CompactDecode

open Lanius.Compiler.Parser SemanticTokens

variable {assignments : List Assignment}

theorem path_assignment_advance
    (path : ScanPath grammar tokens uses 0 (finalPosition tokens.length))
    (kindsBound : grammar.grammar.n_kinds ≤ 32768)
    (member : use ∈ uses)
    (found : assignments[use.token]? = some assignment)
    (computed : assignmentAt? uses use.token = some assignment) :
    advanceTerminal (assignments.map Assignment.code) use.position use.kind = some use.finish := by
  have valid := (path.member member).1
  have kindBound : use.kind < 32768 := Nat.lt_of_lt_of_le valid.kindBound kindsBound
  have own := findUse_of_member path.positions_unique member
  rcases valid.shape with whole | first | second
  · obtain ⟨position, finish, _⟩ := whole
    have absent : findUse? uses (2 * use.token + 1) = none := by
      apply List.find?_eq_none.mpr
      intro other otherMember otherPosition
      have atPosition : other.position = 2 * use.token + 1 := by simpa using otherPosition
      exact path.no_inside member otherMember (by omega) (by omega)
    rw [position] at own
    simp [assignmentAt?, own, absent] at computed
    subst assignment
    simpa only [position, finish] using assignment_advance_whole found kindBound
  · obtain ⟨position, finish, _⟩ := first
    obtain ⟨next, nextMember, nextPosition⟩ := path.next_use member
      (by have bound := valid.tokenBound; simp only [finalPosition]; omega)
    have nextFound := findUse_of_member path.positions_unique nextMember
    have nextAt : next.position = 2 * use.token + 1 := by omega
    rw [nextAt] at nextFound
    rw [position] at own
    simp [assignmentAt?, own, nextFound] at computed
    subst assignment
    have nextBound := (path.member nextMember).1.kindBound
    simpa only [position, finish] using assignment_advance_first found kindBound
      (Nat.lt_of_lt_of_le nextBound kindsBound)
  · obtain ⟨position, finish, _⟩ := second
    obtain ⟨first, firstMember, firstAt⟩ := path.first_slot valid.tokenBound
    have firstFound := findUse_of_member path.positions_unique firstMember
    rw [firstAt] at firstFound
    rw [position] at own
    simp [assignmentAt?, firstFound, own] at computed
    subst assignment
    have firstBound := (path.member firstMember).1.kindBound
    simpa only [position, finish, show 2 * use.token + 1 + 1 = 2 * use.token + 2 from by omega] using
      assignment_advance_second found (Nat.lt_of_lt_of_le firstBound kindsBound) kindBound

/-- Every terminal occurrence collected from the selected parse advances the
artifact checker exactly as it advanced the parser, regardless of record order. -/
theorem collection_terminal_advance
    (parse : MaterializedParse grammar (tokens.map Token.kind))
    (collection : CollectionRecords grammar tokens parse.tree 0 0)
    (kindsBound : grammar.grammar.n_kinds ≤ 32768)
    (member : use ∈ collection.records.flatMap RecordVisit.uses) :
    advanceTerminal (collection.assignments.map Assignment.code) use.position use.kind = some use.finish := by
  obtain ⟨uses, path, _, order, _, _⟩ := selected_tree_visits parse 0 0
  rw [← collection.recordsEq] at order
  have useMember := order.mem_iff.mpr member
  have valid := (path.member useMember).1
  have bound : use.token < collection.assignments.length := by
    rw [collection.lengthEq]
    simpa only [List.length_map] using valid.tokenBound
  have found := List.getElem?_eq_getElem bound
  have computed : assignmentsFrom? uses 0 tokens.length = some collection.assignments :=
    (assignmentsFrom_permutation path.positions_unique order).trans collection.computed
  have atToken := assignments_lookup computed found
  exact path_assignment_advance path kindsBound useMember found (by simpa using atToken)

end Lanius.Extraction.CompactDecode
