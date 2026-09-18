import Lanius.X86.Buffer.Relative

namespace Lanius.X86.Buffer.Relative

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.X86.Control

@[simp] theorem emittedValues_length :
    (emittedValues transfer values cursor target).length = values.length := by
  simp [emittedValues]

theorem emittedValues_frame (transfer : Transfer)
    (outside : index < cursor ∨ cursor + transfer.size ≤ index) :
    (emittedValues transfer values cursor target)[index]? = values[index]? := by
  have headerSize := transfer.header_length
  rw [emittedValues, writtenWord_frame (by omega), headerValues_bytes,
    writtenBytes_frame (by omega)]

/-- The complete instruction window is its opcode header followed by exactly
four displacement bytes. The proof accounts for both source write phases. -/
theorem emittedValues_bytes (transfer : Transfer) (room : cursor + transfer.size ≤ values.length) :
    byteSlice (emittedValues transfer values cursor target) cursor transfer.size =
      transfer.header.map UInt8.ofNat ++ i32Bytes (relativeDisplacement (cursor + transfer.size) target) := by
  have headerSize := transfer.header_length
  have field : cursor + transfer.size - 4 = cursor + transfer.header.length := by omega
  apply List.ext_getElem?
  intro index
  by_cases within : index < transfer.size
  · rw [byteSlice_get within]
    by_cases header : index < transfer.header.length
    · rw [emittedValues, writtenWord_frame (by omega), headerValues_bytes,
        writtenBytes_lane (by omega) header,
        List.getElem?_append_left (by simpa only [List.length_map] using header)]
      simp only [Option.map_some, List.getElem?_map, List.getElem?_eq_getElem header,
        Int.toNat_natCast]
    · rw [List.getElem?_append_right (by simp only [List.length_map]; omega), List.length_map]
      have bytes := writtenWord_byteSlice (values := headerValues transfer values cursor)
        (position := cursor + transfer.size - 4)
        (word := relativeDisplacement (cursor + transfer.size) target)
        (by simp only [headerValues_length]; omega)
      have lane := congrArg (fun bytes : List UInt8 => bytes[index - transfer.header.length]?) bytes
      rw [byteSlice_get (by omega)] at lane
      have sameIndex : cursor + transfer.size - 4 + (index - transfer.header.length) = cursor + index := by omega
      simpa only [sameIndex, emittedValues] using lane
  · rw [List.getElem?_eq_none (by simp only [byteSlice, List.length_map, List.length_take]; omega)]
    rw [List.getElem?_eq_none (by simp only [List.length_append, List.length_map, i32Bytes_length]; omega)]

theorem emittedValues_decode (transfer : Transfer) (room : cursor + transfer.size ≤ values.length) :
    Control.decode (byteSlice (emittedValues transfer values cursor target) cursor transfer.size) =
      some (transfer.instruction (BitVec.ofInt 32 (relativeDisplacement (cursor + transfer.size) target)),
        transfer.size) := by
  rw [emittedValues_bytes transfer room]
  simpa only [List.append_nil] using transfer.decode (relativeDisplacement (cursor + transfer.size) target) []

/-- Read the displacement from the actual instruction window and apply
near-relative RIP arithmetic. Executable/canonical-address validity remains a
separate layout obligation, as do conditional selection and CALL's stack effect. -/
theorem emittedValues_target (transfer : Transfer) (room : cursor + transfer.size ≤ values.length)
    (cursorBound : cursor + transfer.size ≤ 2147483647) (targetBound : target ≤ 2147483647) (base : Int) :
    (Control.displacement? ((byteSlice (emittedValues transfer values cursor target) cursor transfer.size).drop
      transfer.header.length)).map
        (nearTarget (BitVec.ofInt 64 (base + (cursor + transfer.size : Nat)))) =
      some (BitVec.ofInt 64 (base + target)) := by
  rw [emittedValues_bytes transfer room]
  have dropped : (transfer.header.map UInt8.ofNat ++ i32Bytes (relativeDisplacement (cursor + transfer.size) target)).drop
      transfer.header.length = i32Bytes (relativeDisplacement (cursor + transfer.size) target) := by
    simpa only [List.length_map] using List.drop_left (l₁ := transfer.header.map UInt8.ofNat)
      (l₂ := i32Bytes (relativeDisplacement (cursor + transfer.size) target))
  rw [dropped]
  have decoded := displacement?_i32Bytes (relativeDisplacement (cursor + transfer.size) target) []
  simp only [List.append_nil] at decoded
  rw [decoded, Option.map_some, nearTarget_relocated base _ _ cursorBound targetBound]

end Lanius.X86.Buffer.Relative

namespace Lanius.X86.Control

/-- The public byte-emission contract, separate from execution of the emitted
machine instruction. The instruction window is read from `emitted` itself. -/
structure Transfer.Emission (transfer : Transfer) (original : List Int) (cursor target : Nat)
    (emitted : List Int) : Prop where
  length : emitted.length = original.length
  decoded : Control.decode (Buffer.byteSlice emitted cursor transfer.size) =
    some (transfer.instruction (BitVec.ofInt 32 (relativeDisplacement (cursor + transfer.size) target)), transfer.size)
  frame : ∀ index, index < cursor ∨ cursor + transfer.size ≤ index → emitted[index]? = original[index]?
  targetAddress : ∀ base : Int,
    (displacement? ((Buffer.byteSlice emitted cursor transfer.size).drop transfer.header.length)).map
      (nearTarget (BitVec.ofInt 64 (base + (cursor + transfer.size : Nat)))) =
        some (BitVec.ofInt 64 (base + target))

theorem Transfer.emission (transfer : Transfer) {values : List Int} (room : cursor + transfer.size ≤ values.length)
    (cursorBound : cursor + transfer.size ≤ 2147483647) (targetBound : target ≤ 2147483647) :
    transfer.Emission values cursor target (Buffer.Relative.emittedValues transfer values cursor target) :=
  ⟨Buffer.Relative.emittedValues_length, Buffer.Relative.emittedValues_decode transfer room,
    fun _ outside => Buffer.Relative.emittedValues_frame transfer outside,
    Buffer.Relative.emittedValues_target transfer room cursorBound targetBound⟩

end Lanius.X86.Control
