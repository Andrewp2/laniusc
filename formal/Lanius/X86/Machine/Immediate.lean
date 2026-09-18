import Lanius.X86.Machine.Scalar
import Lanius.X86.Control.Emission

namespace Lanius.X86.Machine.Immediate

open Lanius.Core Lanius.Semantics Lanius.Properties

/-- The two emitted 32-bit words, interpreted without sign extension. -/
def word (low high : Int) : BitVec 64 :=
  BitVec.ofNat 64 ((BitVec.ofInt 32 low).toNat + 4294967296 * (BitVec.ofInt 32 high).toNat)

/-- The actual RAX encoding emitted by the 64-bit immediate source helper. -/
def bytes (low high : Int) : List UInt8 :=
  [72, 184] ++ i32Bytes low ++ i32Bytes high

@[simp] theorem bytes_length : (bytes low high).length = 10 := by
  simp [bytes, i32Bytes_length]

theorem word_toNat (low high : Int) :
    (word low high).toNat =
      (BitVec.ofInt 32 low).toNat + 4294967296 * (BitVec.ofInt 32 high).toNat := by
  have lowBound := (BitVec.ofInt 32 low).isLt
  have highBound := (BitVec.ofInt 32 high).isLt
  simp only [word, BitVec.toNat_ofNat]
  apply Nat.mod_eq_of_lt
  omega

theorem reads (low high : Int) (tail : List UInt8) :
    immediate64? (i32Bytes low ++ i32Bytes high ++ tail) = some (word low high) := by
  have dropped : (i32Bytes low ++ i32Bytes high ++ tail).drop 4 = i32Bytes high ++ tail := by
    rw [List.append_assoc, ← i32Bytes_length low, List.drop_append_length]
  simp only [immediate64?, dropped]
  simp [List.append_assoc, Control.displacement?_i32Bytes, word]

/-- Decoding consumes exactly ten bytes; subsequent code is irrelevant. -/
theorem decodes (low high : Int) (tail : List UInt8) :
    decode (bytes low high ++ tail) = some (.immediate64 0 (word low high), 10) := by
  have value := reads low high tail
  simp only [List.append_assoc] at value
  simp [bytes, List.append_assoc, decode, decodeOpcode, X86.Register.Rex.decode?,
    value, extendRegister]

theorem executes (before : State)
    (loaded : CodeAt before.memory before.rip (bytes low high)) :
    Step before (before.immediate64 0 (word low high) 10) := by
  exact .decoded (bytes low high) loaded (.immediate64 0 (word low high)) 10
    (by simpa using decodes low high []) rfl

/-- Full-width MOV preserves every other register, all memory, and all flags. -/
theorem fields (before : State) (destination : Register) (value : BitVec 64) (size : Nat) :
    (before.immediate64 destination value size).registers destination = value ∧
    (∀ register, register ≠ destination →
      (before.immediate64 destination value size).registers register = before.registers register) ∧
    (before.immediate64 destination value size).memory = before.memory ∧
    (before.immediate64 destination value size).flags = before.flags ∧
    (before.immediate64 destination value size).rip = before.rip + BitVec.ofNat 64 size := by
  refine ⟨by simp [State.immediate64], ?_, rfl, rfl, rfl⟩
  intro register different
  simp [State.immediate64, different]

/-- Execute the emitted window and retain the complete continuation code.
No source-language cast, range, or pointer representation is assumed here. -/
theorem preserves (before : State)
    (loaded : CodeAt before.memory before.rip (bytes low high ++ tail)) :
    ∃ after, Steps 1 before after ∧
      after.registers 0 = word low high ∧
      (∀ register, register ≠ 0 → after.registers register = before.registers register) ∧
      after.memory = before.memory ∧ after.flags = before.flags ∧
      after.rip = before.rip + 10 ∧ CodeAt after.memory after.rip tail := by
  refine ⟨before.immediate64 0 (word low high) 10,
    .cons (executes before loaded.prefix) (.refl _), ?_⟩
  have unchanged := fields before 0 (word low high) 10
  refine ⟨unchanged.1, unchanged.2.1, unchanged.2.2.1, unchanged.2.2.2.1,
    unchanged.2.2.2.2, ?_⟩
  simpa only [State.immediate64, bytes_length] using loaded.suffix

end Lanius.X86.Machine.Immediate
