import Lanius.SurfaceElaboration

namespace Lanius.Compiler.SelectionCheck

/-- A finite lookup carries membership and uniqueness, so consumers do not
    each reconstruct the same filtering argument. Ambiguous rows are rejected. -/
structure Selected (values : List α) (predicate : α → Bool) where
  value : α
  member : value ∈ values
  accepted : predicate value = true
  unique : ∀ other ∈ values, predicate other = true → other = value

def check (values : List α) (predicate : α → Bool) :
    Option (Selected values predicate) :=
  match found : values.filter predicate with
  | [value] =>
      have member : value ∈ values.filter predicate := by rw [found]; simp
      some ⟨value, (List.mem_filter.mp member).1, (List.mem_filter.mp member).2,
        by
          intro other belongs accepted
          have filtered := List.mem_filter.mpr ⟨belongs, accepted⟩
          rw [found] at filtered
          exact List.mem_singleton.mp filtered⟩
  | _ => none

end Lanius.Compiler.SelectionCheck
