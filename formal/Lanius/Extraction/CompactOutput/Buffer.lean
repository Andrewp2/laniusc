import Lanius.Extraction.CompactOutput.Sequence

namespace Lanius.Extraction.CompactOutput

/-- With sufficient capacity, the byte sequence replaces precisely its
destination interval, preserving the original prefix and suffix. -/
theorem appendAll_success (capacity position : Nat) (values : List Nat) (original : List Int)
    (room : position + values.length ≤ capacity) (storage : capacity ≤ original.length) :
    appendAll capacity values position original =
      .done (position + values.length : Nat)
        (original.take position ++ values.map Int.ofNat ++ original.drop (position + values.length)) := by
  induction values generalizing position original with
  | nil => simp [appendAll]
  | cons value rest ih =>
    have inside : 0 ≤ (position : Int) ∧ (position : Int) < capacity := by
      simp only [List.length_cons] at room
      omega
    have next : nextPosition capacity position = (position + 1 : Nat) := by
      simp only [nextPosition, if_pos inside, Int.natCast_add, Int.natCast_one]
    have wrote : appended original capacity position value = original.set position value := by
      simp only [appended, if_pos inside, Int.toNat_natCast]
    have notFailed : ¬ ((position + 1 : Nat) : Int) < 0 := by omega
    rw [appendAll, next, if_neg notFailed, wrote]
    have continued := ih (position + 1) (original.set position value)
      (by simp only [List.length_cons] at room; omega) (by simpa only [List.length_set] using storage)
    have takeSet : (original.set position (Int.ofNat value)).take (position + 1) = original.take position ++ [Int.ofNat value] := by
      have bounded : position < (original.set position (Int.ofNat value)).length := by
        simp only [List.length_set, List.length_cons] at *
        omega
      rw [List.take_succ_eq_append_getElem bounded, List.take_set,
        List.set_eq_of_length_le (show (original.take position).length ≤ position by
          simp only [List.length_take]; exact Nat.min_le_left _ _)]
      simp
    have dropSet : (original.set position (Int.ofNat value)).drop (position + 1 + rest.length) =
        original.drop (position + 1 + rest.length) := by
      rw [List.drop_set, if_pos (by omega)]
    have lengthEq : position + 1 + rest.length = position + (value :: rest).length := by simp; omega
    simp only [Int.ofNat_eq_natCast] at takeSet dropSet
    rw [takeSet, dropSet] at continued
    simpa only [lengthEq, List.map_cons, List.append_assoc, List.singleton_append, Int.ofNat_eq_natCast] using continued

end Lanius.Extraction.CompactOutput
