import Lanius.Extraction.CompactOutput.Chunks

namespace Lanius.Extraction.CompactOutput.Word

/-- Even an unconditionally executed later field cannot write after the
previous field returned the capacity-error sentinel. -/
theorem appendAll_sentinel (capacity value : Nat) (rest : List Nat) (original : List Int) :
    appendAll capacity (value :: rest) (-1) original = .full original := by
  simp [appendAll, nextPosition, appended]

theorem appendAll_word_sentinel (capacity value : Nat) (original : List Int) :
    appendAll capacity (hexDigits value 8) (-1) original = .full original := by
  rw [hexDigits, appendAll_sentinel]

/-- Consecutive nonempty fields may call the next writer without testing the
previous result. The combined wire contents still match one flat sequence. -/
theorem appendAll_following_word (capacity value : Nat) (first : List Nat)
    (position : Int) (original : List Int) :
    appendAll capacity (first ++ hexDigits value 8) position original =
      appendAll capacity (hexDigits value 8)
        (appendAll capacity first position original).position
        (appendAll capacity first position original).contents := by
  rw [appendAll_append]
  cases result : appendAll capacity first position original with
  | done cursor contents => rfl
  | full contents =>
    exact (appendAll_word_sentinel capacity value contents).symm

end Lanius.Extraction.CompactOutput.Word
