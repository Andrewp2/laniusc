import Lanius.Extraction.CompactOutput.Word.Chunks

namespace Lanius.Extraction.CompactOutput.Unit

/-- Sequential calls agree on observable cursor and output even when an
empty serializer returns the incoming failure sentinel without an early exit. -/
theorem following_chunk (capacity : Nat) (first second : List Nat)
    (position : Int) (original : List Int) :
    let combined := appendAll capacity (first ++ second) position original
    let previous := appendAll capacity first position original
    let following := appendAll capacity second previous.position previous.contents
    combined.position = following.position ∧ combined.contents = following.contents := by
  dsimp only
  rw [appendAll_append]
  cases previous : appendAll capacity first position original with
  | done cursor contents => exact ⟨rfl, rfl⟩
  | full contents =>
    cases second with
    | nil => exact ⟨rfl, rfl⟩
    | cons value rest =>
      simp [AppendOutcome.resume, AppendOutcome.position, AppendOutcome.contents,
        Word.appendAll_sentinel]

theorem following_nonempty (capacity : Nat) (first second : List Nat)
    (position : Int) (original : List Int) (nonempty : second ≠ []) :
    appendAll capacity (first ++ second) position original =
      appendAll capacity second (appendAll capacity first position original).position
        (appendAll capacity first position original).contents := by
  rw [appendAll_append]
  cases previous : appendAll capacity first position original with
  | done cursor contents => rfl
  | full contents =>
    cases second with
    | nil => exact (nonempty rfl).elim
    | cons value rest => exact (Word.appendAll_sentinel capacity value rest contents).symm

end Lanius.Extraction.CompactOutput.Unit
