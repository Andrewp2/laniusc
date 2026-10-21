import Lanius.Semantics.Typing.Projection
import Lanius.Semantics.Assignment

namespace Lanius.Semantics

open Lanius.Core

private theorem setValue_read_same (read : values[index]? = some value) :
    setValue values index value = values := by
  obtain ⟨bound, same⟩ := List.getElem?_eq_some_iff.mp read
  rw [setValue_eq_set, ← same, List.set_getElem_self bound]

/-- Writing an existing projected value reconstructs exactly the original
    aggregate, at any struct/array depth. No typing or unchanged-root premise. -/
theorem replaceProjectedValue_read_same (read : projectedValue root projections = .ok value) :
    replaceProjectedValue root projections value = .ok root := by
  induction projections generalizing root with
  | nil => cases read; rfl
  | cons projection rest ih =>
    cases root <;> cases projection <;> simp only [projectedValue] at read <;> try cases read
    case «structure».field id fields field =>
      cases found : fields[field]? with
      | none => simp only [found] at read; cases read
      | some old =>
        have tail : projectedValue old rest = .ok value := by simpa only [projectedValue, found] using read
        simp only [replaceProjectedValue, found, ih tail, setValue_read_same found]
    case array.index elements index =>
      cases found : elements[index]? with
      | none => simp only [found] at read; cases read
      | some old =>
        have tail : projectedValue old rest = .ok value := by simpa only [projectedValue, found] using read
        simp only [replaceProjectedValue, found, ih tail, setValue_read_same found]

private theorem replaceCell_contents_same
    (same : ∀ entry ∈ cells, entry.id = cell → entry.value = some value) :
    replaceCell cells cell value = cells := by
  induction cells with
  | nil => rfl
  | cons head rest ih =>
    have tail := ih (fun entry member => same entry (by simp [member]))
    unfold replaceCell
    split
    · rename_i equal
      have contents := same head (by simp) (by simpa only [beq_iff_eq] using equal)
      have unchanged : { head with value := some value } = head := by cases head; simp_all
      rw [unchanged, tail]
    · rw [tail]

theorem replaceCell_read_same (unique : (cells.map Cell.id).Nodup)
    (found : cells.find? (fun entry => entry.id == cell) = some { id := cell, value := some value }) :
    replaceCell cells cell value = cells := by
  have pairwise : cells.Pairwise (fun left right => left.id = right.id → left = right) :=
    (List.pairwise_map.mp unique).imp (fun different same => (different same).elim)
  have injective := List.Pairwise.forall_of_forall_of_flip (fun _ _ _ => rfl) pairwise
    (pairwise.imp (fun same equal => (same equal.symm).symm))
  apply replaceCell_contents_same
  intro entry member equal
  have same := injective member (List.mem_of_find?_eq_some found) equal
  rw [same]

/-- Native refresh writes back the same aggregate when its decoded bytes
    match the live projection. Unique cell identities prevent hidden duplicates. -/
theorem writeResolvedPlace_read_same (unique : (state.cells.map Cell.id).Nodup)
    (read : readCellProjection state place.root place.projections = .ok value) :
    writeResolvedPlace state place value = .ok state := by
  cases found : state.cellEntry? place.root with
  | none => simp only [readCellProjection, found] at read; cases read
  | some entry =>
    rcases entry with ⟨id, contents⟩
    have idEqual : id = place.root := by simpa only [beq_iff_eq] using List.find?_some found
    subst id
    cases contents with
    | none => simp only [readCellProjection, found] at read; cases read
    | some root =>
      have projected : projectedValue root place.projections = .ok value := by
        simpa only [readCellProjection, found] using read
      have replaced := replaceCell_read_same unique found
      cases path : place.projections with
      | nil =>
        have same : root = value := by simpa only [path, projectedValue, Except.ok.injEq] using projected
        subst value
        simp only [writeResolvedPlace, path, State.assignCell, found, Option.isSome_some,
          ↓reduceIte, replaced]
      | cons head tail =>
        rw [path] at projected
        simp only [writeResolvedPlace, path, replaceProjectedValue_read_same projected,
          State.assignCell, found, Option.isSome_some, ↓reduceIte, replaced]

#print axioms writeResolvedPlace_read_same

end Lanius.Semantics
