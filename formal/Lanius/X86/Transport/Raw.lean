import Lanius.X86.Transport.Local
import Lanius.X86.Transport.Literal

namespace Lanius.X86.Transport

open Lanius.Core

/-- Serialize the actual Core raw-slice constructor with a local pointer and
signed literal length. Local identity and every signed bit are retained.
Negative canonical lengths serialize too; their rejection belongs to execution,
not to transport. Unrepresentable identifiers and integers are rejected. -/
theorem expression_raw_iff :
    expression? program (.i32SliceFromRawParts (.local coreLocal) (.value (.signed .i32 low))) = some words ↔
      coreLocal ≤ 2147483647 ∧ (-2147483648 ≤ low ∧ low ≤ 2147483647) ∧
      words = [15, 1, (coreLocal : Int), 0, 1, low] := by
  by_cases localBound : coreLocal ≤ 2147483647 <;>
    by_cases signedBound : -2147483648 ≤ low ∧ low ≤ 2147483647 <;>
    simp [expression?, localId?, literal?, localBound, signedBound, eq_comm]

/-- Recover the exact six words consumed by the raw-expression compiler,
their bounds, and the untouched enclosing suffix from one actual serialized
Core expression. This does not execute or assume acceptance by a parser. -/
theorem raw_window {transport : List Int}
    (serialized : expression? program
      (.i32SliceFromRawParts (.local coreLocal) (.value (.signed .i32 low))) = some words)
    (window : transport.drop position = words ++ suffix) :
    coreLocal ≤ 2147483647 ∧ (-2147483648 ≤ low ∧ low ≤ 2147483647) ∧
    position + 6 ≤ transport.length ∧
    transport[position]? = some 15 ∧
    transport[position + 1]? = some 1 ∧
    transport[position + 2]? = some (coreLocal : Int) ∧
    transport[position + 3]? = some 0 ∧
    transport[position + 4]? = some 1 ∧
    transport[position + 5]? = some low ∧
    transport.drop (position + 6) = suffix := by
  obtain ⟨localBound, signedBound, rfl⟩ := expression_raw_iff.mp serialized
  have remaining := congrArg List.length window
  simp only [List.length_drop, List.length_append, List.length_cons, List.length_nil] at remaining
  refine ⟨localBound, signedBound, by omega, ?_, ?_, ?_, ?_, ?_, ?_, ?_⟩
  · have entry := congrArg (fun values : List Int => values[0]?) window
    simpa only [List.getElem?_drop, Nat.add_zero, List.cons_append, List.nil_append,
      List.getElem?_cons_zero] using entry
  · have entry := congrArg (fun values : List Int => values[1]?) window
    simpa only [List.getElem?_drop, List.cons_append, List.nil_append,
      List.getElem?_cons_succ, List.getElem?_cons_zero] using entry
  · have entry := congrArg (fun values : List Int => values[2]?) window
    simpa only [List.getElem?_drop, List.cons_append, List.nil_append,
      List.getElem?_cons_succ, List.getElem?_cons_zero] using entry
  · have entry := congrArg (fun values : List Int => values[3]?) window
    simpa only [List.getElem?_drop, List.cons_append, List.nil_append,
      List.getElem?_cons_succ, List.getElem?_cons_zero] using entry
  · have entry := congrArg (fun values : List Int => values[4]?) window
    simpa only [List.getElem?_drop, List.cons_append, List.nil_append,
      List.getElem?_cons_succ, List.getElem?_cons_zero] using entry
  · have entry := congrArg (fun values : List Int => values[5]?) window
    simpa only [List.getElem?_drop, List.cons_append, List.nil_append,
      List.getElem?_cons_succ, List.getElem?_cons_zero] using entry
  · have rest := congrArg (List.drop 6) window
    simpa [List.drop_drop, Nat.add_comm] using rest

end Lanius.X86.Transport
