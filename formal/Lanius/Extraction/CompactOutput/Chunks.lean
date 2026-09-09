import Lanius.Extraction.CompactOutput.Sequence
import Lanius.Extraction.CompactOutput.HexByte

namespace Lanius.Extraction.CompactOutput

/-- Resume only normally completed chunks. A full buffer retains its partial
contents and cannot be revived by a later chunk. -/
def AppendOutcome.resume (capacity : Nat) (values : List Nat) : AppendOutcome → AppendOutcome
  | .done position contents => appendAll capacity values position contents
  | .full contents => .full contents

theorem appendAll_append (capacity : Nat) (first second : List Nat)
    (position : Int) (original : List Int) :
    appendAll capacity (first ++ second) position original =
      (appendAll capacity first position original).resume capacity second := by
  induction first generalizing position original with
  | nil => rfl
  | cons value rest ih =>
    simp only [List.cons_append, appendAll]
    split
    · rfl
    · exact ih _ _

/-- The two actual byte calls agree with short-circuiting sequence emission,
even though the second call still executes after the first call fails. -/
theorem appendAll_hexByte (capacity value : Nat) (position : Int) (original : List Int) :
    appendAll capacity [hexDigit (value / 16), hexDigit (value % 16)] position original =
      if hexBytePosition capacity position < 0 then
        .full (hexByteOutput original capacity position value)
      else .done (hexBytePosition capacity position)
        (hexByteOutput original capacity position value) := by
  by_cases room : 0 ≤ position ∧ position < capacity
  · have nonnegative : ¬ position + 1 < 0 := by omega
    simp only [appendAll, nextPosition, appended, hexBytePosition, hexByteOutput,
      if_pos room, if_neg nonnegative]
  · simp [appendAll, nextPosition, appended, hexBytePosition, hexByteOutput, room]

end Lanius.Extraction.CompactOutput
