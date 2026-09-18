import Lanius.X86.Transport.Core
import Lanius.X86.Machine.Immediate

namespace Lanius.X86.Transport

open Lanius.Core

/-- The unsigned transport retains two signed i32 encodings, not two
nonnegative integers. Their bit patterns reconstruct the original usize. -/
theorem literal_usize_iff : literal? (.unsigned .usize value) = some words ↔
    value < 2 ^ 64 ∧ words =
      [3, (BitVec.ofNat 32 value).toInt, (BitVec.ofNat 32 (value / 2 ^ 32)).toInt] := by
  by_cases bounded : value < 2 ^ 64
  · simp [literal?, bounded, eq_comm]
  · simp [literal?, bounded]

theorem expression_usize_iff : expression? program (.value (.unsigned .usize value)) = some words ↔
    value < 2 ^ 64 ∧ words =
      [0, 3, (BitVec.ofNat 32 value).toInt, (BitVec.ofNat 32 (value / 2 ^ 32)).toInt] := by
  by_cases bounded : value < 2 ^ 64
  · simp [expression?, literal?, bounded, eq_comm]
  · simp [expression?, literal?, bounded]

/-- The emitted low/high words recover all 64 bits, including either signed
transport word's sign bit. The range comes from successful serialization. -/
theorem usize_word (bounded : value < 2 ^ 64) :
    Machine.Immediate.word (BitVec.ofNat 32 value).toInt
      (BitVec.ofNat 32 (value / 2 ^ 32)).toInt = BitVec.ofNat 64 value := by
  unfold Machine.Immediate.word
  simp only [BitVec.ofInt_toInt, BitVec.toNat_ofNat]
  have highBound : value / 2 ^ 32 < 2 ^ 32 := by omega
  rw [Nat.mod_eq_of_lt highBound]
  congr 1
  omega

/-- This bridge consumes the serializer's actual output, not independent
assumptions that an arbitrary pair of input words denotes a usize value. -/
theorem usize_serialized
    (serialized : literal? (.unsigned .usize value) = some [3, low, high]) :
    value < 2 ^ 64 ∧ Machine.Immediate.word low high = BitVec.ofNat 64 value := by
  obtain ⟨bounded, words⟩ := literal_usize_iff.mp serialized
  simp only [List.cons.injEq, true_and, and_true] at words
  obtain ⟨rfl, rfl⟩ := words
  exact ⟨bounded, usize_word bounded⟩

/-- The four words consumed by unsigned-literal lowering, at an arbitrary
input cursor with an untouched enclosing transport suffix. -/
theorem usize_window {transport : List Int}
    (serialized : expression? program (.value (.unsigned .usize value)) = some words)
    (window : transport.drop position = words ++ suffix) :
    value < 2 ^ 64 ∧ position + 4 ≤ transport.length ∧
    transport[position]? = some 0 ∧ transport[position + 1]? = some 3 ∧
    transport[position + 2]? = some (BitVec.ofNat 32 value).toInt ∧
    transport[position + 3]? = some (BitVec.ofNat 32 (value / 2 ^ 32)).toInt ∧
    Machine.Immediate.word (BitVec.ofNat 32 value).toInt
      (BitVec.ofNat 32 (value / 2 ^ 32)).toInt = BitVec.ofNat 64 value := by
  obtain ⟨bounded, rfl⟩ := expression_usize_iff.mp serialized
  have remaining := congrArg List.length window
  simp only [List.length_drop, List.length_append, List.length_cons, List.length_nil] at remaining
  refine ⟨bounded, by omega, ?_, ?_, ?_, ?_, usize_word bounded⟩
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

end Lanius.X86.Transport
