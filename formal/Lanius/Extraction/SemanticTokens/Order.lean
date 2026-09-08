import Lanius.Extraction.SemanticTokens.Specification

namespace Lanius.Extraction.SemanticTokens

theorem findUse_of_member (unique : (uses.map Use.position).Nodup) (member : use ∈ uses) :
    findUse? uses use.position = some use := by
  induction uses with
  | nil => simp at member
  | cons first rest ih =>
      have distinct := List.nodup_cons.mp unique
      rcases List.mem_cons.mp member with rfl | later
      · simp [findUse?]
      · have different : first.position ≠ use.position := by
          intro same
          exact distinct.1 (List.mem_map.mpr ⟨use, later, same.symm⟩)
        simpa [findUse?, different] using ih distinct.2 later

/-- Position-keyed assignment lookup is invariant under traversal order when
positions are unique. This is the bridge from source order to record postorder. -/
theorem findUse_permutation (unique : (uses.map Use.position).Nodup) (order : uses.Perm reordered) :
    findUse? uses position = findUse? reordered position := by
  have reorderedUnique := (order.map Use.position).nodup unique
  cases found : findUse? uses position with
  | none =>
      have noneThere : findUse? reordered position = none := by
        apply List.find?_eq_none.mpr
        intro use member
        exact List.find?_eq_none.mp found use (order.mem_iff.mpr member)
      exact noneThere.symm
  | some use =>
      have member := List.mem_of_find?_eq_some found
      have atPosition : use.position = position := by simpa using List.find?_some found
      have result := findUse_of_member reorderedUnique (order.mem_iff.mp member)
      simpa only [atPosition] using result.symm

theorem assignmentAt_permutation (unique : (uses.map Use.position).Nodup) (order : uses.Perm reordered) :
    assignmentAt? uses token = assignmentAt? reordered token := by
  simp only [assignmentAt?, findUse_permutation unique order]

theorem assignmentsFrom_permutation (unique : (uses.map Use.position).Nodup) (order : uses.Perm reordered) :
    assignmentsFrom? uses start count = assignmentsFrom? reordered start count := by
  induction count generalizing start with
  | zero => rfl
  | succ count ih => simp only [assignmentsFrom?, assignmentAt_permutation unique order, ih]

end Lanius.Extraction.SemanticTokens
