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

end Lanius.Extraction.CompactOutput
