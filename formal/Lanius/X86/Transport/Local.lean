import Lanius.X86.Transport.Core

namespace Lanius.X86.Transport

open Lanius.Core

/-- Accepted local identifiers fit the actual signed transport field and
retain their Core identity; no independent integer-to-local mapping is used. -/
theorem local_id_iff : localId? coreLocal = some key ↔
    coreLocal ≤ 2147483647 ∧ key = (coreLocal : Int) := by
  by_cases bounded : coreLocal ≤ 2147483647
  · simp [localId?, bounded, eq_comm]
  · simp [localId?, bounded]

theorem expression_local_iff : expression? program (.local coreLocal) = some words ↔
    coreLocal ≤ 2147483647 ∧ words = [1, (coreLocal : Int)] := by
  by_cases bounded : coreLocal ≤ 2147483647
  · simp [expression?, localId?, bounded, eq_comm]
  · simp [expression?, localId?, bounded]

/-- Recover the real LOCAL tag, exact Core local key, and both read bounds
from one serialized expression window. An enclosing suffix is untouched. -/
theorem local_window {transport : List Int}
    (serialized : expression? program (.local coreLocal) = some words)
    (window : transport.drop position = words ++ suffix) :
    coreLocal ≤ 2147483647 ∧ position + 2 ≤ transport.length ∧
    transport[position]? = some 1 ∧ transport[position + 1]? = some (coreLocal : Int) := by
  obtain ⟨bounded, rfl⟩ := expression_local_iff.mp serialized
  have remaining := congrArg List.length window
  simp only [List.length_drop, List.length_append, List.length_cons, List.length_nil] at remaining
  refine ⟨bounded, by omega, ?_, ?_⟩
  · have entry := congrArg (fun values : List Int => values[0]?) window
    simpa only [List.getElem?_drop, Nat.add_zero, List.cons_append, List.nil_append,
      List.getElem?_cons_zero] using entry
  · have entry := congrArg (fun values : List Int => values[1]?) window
    simpa only [List.getElem?_drop, List.cons_append, List.nil_append,
      List.getElem?_cons_succ, List.getElem?_cons_zero] using entry

end Lanius.X86.Transport
