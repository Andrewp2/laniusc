import Lanius.X86.Word

namespace Lanius.X86

/-- The emitter uses nonnegative image offsets below 2 GiB. This ensures
subtraction is exact in i32, including backward transfers. -/
def relativeDisplacement (next target : Nat) : Int := (target : Int) - (next : Int)

theorem relativeDisplacement_fits (next target : Nat)
    (nextBound : next ≤ 2147483647) (targetBound : target ≤ 2147483647) :
    -2147483648 ≤ relativeDisplacement next target ∧
      relativeDisplacement next target < 2147483648 := by
  unfold relativeDisplacement
  omega

theorem relativeDisplacement_signed (next target : Nat)
    (nextBound : next ≤ 2147483647) (targetBound : target ≤ 2147483647) :
    (BitVec.ofInt 32 (relativeDisplacement next target)).toInt =
      relativeDisplacement next target := by
  obtain ⟨lower, upper⟩ := relativeDisplacement_fits next target nextBound targetBound
  exact BitVec.toInt_ofInt_eq_self (by decide) lower upper

/-- The architectural near-relative target calculation. Instruction decoding,
canonical-address checks, and call-stack effects are separate obligations. -/
def nearTarget (next : BitVec 64) (displacement : BitVec 32) : BitVec 64 :=
  next + BitVec.ofInt 64 displacement.toInt

theorem nearTarget_relocated (base : Int) (next target : Nat)
    (nextBound : next ≤ 2147483647) (targetBound : target ≤ 2147483647) :
    nearTarget (BitVec.ofInt 64 (base + next))
      (BitVec.ofInt 32 (relativeDisplacement next target)) =
      BitVec.ofInt 64 (base + target) := by
  unfold nearTarget
  rw [relativeDisplacement_signed next target nextBound targetBound, ← BitVec.ofInt_add]
  congr 1
  unfold relativeDisplacement
  omega

/-- A patched little-endian displacement reaches the requested offset at
any image base. This includes modulo-2^64 RIP arithmetic. -/
theorem patchedTarget (memory : ByteMemory) (base : Int) (field target : Nat)
    (fieldBound : field + 4 ≤ 2147483647) (targetBound : target ≤ 2147483647) :
    nearTarget (BitVec.ofInt 64 (base + (field + 4 : Nat)))
      (readWord (writeWord memory field
        (BitVec.ofInt 32 (relativeDisplacement (field + 4) target))) field) =
      BitVec.ofInt 64 (base + target) := by
  rw [readWord_writeWord]
  exact nearTarget_relocated base (field + 4) target fieldBound targetBound

/-- The subtraction-based buffer check used by the Lanius emitter is the
ordinary range condition, without first computing a possibly overflowing sum. -/
theorem reservation_iff (capacity cursor count : Int) :
    (0 ≤ capacity ∧ 0 ≤ cursor ∧ 0 ≤ count ∧ cursor ≤ capacity ∧ count ≤ capacity - cursor) ↔
      (0 ≤ cursor ∧ 0 ≤ count ∧ cursor + count ≤ capacity) := by omega

end Lanius.X86
