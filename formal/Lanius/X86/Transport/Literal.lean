import Lanius.X86.Transport.Core

namespace Lanius.X86.Transport

open Lanius.Core

/-- A successful signed literal transport retains the exact Core value;
out-of-range integers are rejected rather than silently truncated. -/
theorem literal_i32_iff : literal? (.signed .i32 low) = some words ↔
    (-2147483648 ≤ low ∧ low ≤ 2147483647) ∧ words = [1, low] := by
  by_cases bounded : -2147483648 ≤ low ∧ low ≤ 2147483647
  · simp [literal?, bounded, eq_comm]
  · simp [literal?, bounded]

theorem expression_i32_iff : expression? program (.value (.signed .i32 low)) = some words ↔
    (-2147483648 ≤ low ∧ low ≤ 2147483647) ∧ words = [0, 1, low] := by
  by_cases bounded : -2147483648 ≤ low ∧ low ≤ 2147483647
  · simp [expression?, literal?, bounded, eq_comm]
  · simp [expression?, literal?, bounded]

/-- The common three-word literal window. Reading it does not reparse its suffix. -/
theorem literal_window {transport : List Int}
    (window : transport.drop position = [0, kind, low] ++ suffix) :
    position + 3 ≤ transport.length ∧ transport[position]? = some 0 ∧
      transport[position + 1]? = some kind ∧ transport[position + 2]? = some low := by
  have remaining := congrArg List.length window
  simp only [List.length_drop, List.length_append, List.length_cons, List.length_nil] at remaining
  refine ⟨by omega, ?_, ?_, ?_⟩
  · have entry := congrArg (fun values : List Int => values[0]?) window
    simpa only [List.getElem?_drop, Nat.add_zero, List.cons_append, List.nil_append,
      List.getElem?_cons_zero] using entry
  · have entry := congrArg (fun values : List Int => values[1]?) window
    simpa only [List.getElem?_drop, List.cons_append, List.nil_append,
      List.getElem?_cons_succ, List.getElem?_cons_zero] using entry
  · have entry := congrArg (fun values : List Int => values[2]?) window
    simpa only [List.getElem?_drop, List.cons_append, List.nil_append,
      List.getElem?_cons_succ, List.getElem?_cons_zero] using entry

theorem i32_window {transport : List Int}
    (serialized : expression? program (.value (.signed .i32 low)) = some words)
    (window : transport.drop position = words ++ suffix) :
    (-2147483648 ≤ low ∧ low ≤ 2147483647) ∧
    position + 3 ≤ transport.length ∧ transport[position]? = some 0 ∧
      transport[position + 1]? = some 1 ∧ transport[position + 2]? = some low := by
  obtain ⟨bounded, rfl⟩ := expression_i32_iff.mp serialized
  exact ⟨bounded, literal_window window⟩

theorem bool_window {transport : List Int}
    (serialized : expression? program (.value (.boolean value)) = some words)
    (window : transport.drop position = words ++ suffix) :
    position + 3 ≤ transport.length ∧ transport[position]? = some 0 ∧
      transport[position + 1]? = some 2 ∧ transport[position + 2]? = some (if value then 1 else 0) := by
  have wordsExact : words = [0, 2, if value then 1 else 0] := by
    simpa [expression?, literal?, eq_comm] using serialized
  exact literal_window (wordsExact ▸ window)

end Lanius.X86.Transport
