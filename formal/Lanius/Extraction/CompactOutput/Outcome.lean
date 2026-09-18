import Lanius.Extraction.CompactOutput.Sequence

namespace Lanius.Extraction.CompactOutput

theorem appendAll_done_nonnegative (values : List Nat) (nonempty : values ≠ [])
    (done : appendAll capacity values position original = .done result contents) : 0 ≤ result := by
  induction values generalizing position original with
  | nil => exact (nonempty rfl).elim
  | cons value rest ih =>
    simp only [appendAll] at done
    split at done
    · cases done
    · rename_i passed
      cases rest with
      | nil =>
        simp only [appendAll, AppendOutcome.done.injEq] at done
        omega
      | cons next tail => exact ih (by simp) done

/-- A completed append advances once for every byte, even when the initial
cursor is not known to be in range. Empty writers leave that cursor alone. -/
theorem appendAll_done_position (values : List Nat)
    (done : appendAll capacity values position original = .done result contents) :
    result = position + (values.length : Int) := by
  induction values generalizing position original with
  | nil =>
    simp only [appendAll, AppendOutcome.done.injEq] at done
    simpa using done.1.symm
  | cons value rest ih =>
    simp only [appendAll] at done
    split at done
    · cases done
    · rename_i passed
      have inside : 0 ≤ position ∧ position < capacity := by
        by_cases valid : 0 ≤ position ∧ position < capacity
        · exact valid
        · simp only [nextPosition, if_neg valid] at passed
          omega
      have tail := ih done
      simp only [nextPosition, if_pos inside, List.length_cons, Int.natCast_add, Int.natCast_one] at tail ⊢
      omega

/-- Successful nonempty writes establish their own start/end bounds. These
are consequences of the guards, not capacity assumptions supplied by callers. -/
theorem appendAll_done_bounds (values : List Nat) (nonempty : values ≠ [])
    (done : appendAll capacity values position original = .done result contents) :
    0 ≤ position ∧ result ≤ capacity := by
  induction values generalizing position original with
  | nil => exact (nonempty rfl).elim
  | cons value rest ih =>
    simp only [appendAll] at done
    split at done
    · cases done
    · rename_i passed
      have inside : 0 ≤ position ∧ position < capacity := by
        by_cases valid : 0 ≤ position ∧ position < capacity
        · exact valid
        · simp only [nextPosition, if_neg valid] at passed
          omega
      refine ⟨inside.1, ?_⟩
      cases rest with
      | nil =>
        simp only [appendAll, AppendOutcome.done.injEq, nextPosition, if_pos inside] at done
        omega
      | cons next tail => exact (ih (by simp) done).2

/-- The emitter's nonnegative return excludes a capacity failure and proves
enough room for the whole nonempty encoding. -/
theorem appendAll_nonnegative_bounds (values : List Nat) (nonempty : values ≠ [])
    (success : 0 ≤ (appendAll capacity values position original).position) :
    0 ≤ position ∧ position.toNat + values.length ≤ capacity := by
  cases outcome : appendAll capacity values position original with
  | full contents => simp only [outcome, AppendOutcome.position] at success; omega
  | done result contents =>
    have bounds := appendAll_done_bounds values nonempty outcome
    have advanced := appendAll_done_position values outcome
    have cast := Int.toNat_of_nonneg bounds.1
    exact ⟨bounds.1, by omega⟩

end Lanius.Extraction.CompactOutput
