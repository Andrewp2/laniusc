import Lanius.X86.Storage.Value
import Lanius.World

namespace Lanius.X86.Storage.String

open Machine

/-- Contents do not identify an allocation. Equal immutable literals may be
emitted at different addresses, while `stringDataPtr` allocates a fresh copy. -/
structure Bytes (memory : Memory) (base : Machine.Address) (bytes : List UInt8) : Prop where
  bounded : base.toNat + bytes.length ≤ 2^64
  contents : ∀ index, ∀ inside : index < bytes.length,
    memory (base + BitVec.ofNat 64 index) = bytes[index]

theorem Bytes.frame (stored : Bytes before base bytes)
    (same : ∀ index, index < bytes.length →
      after (base + BitVec.ofNat 64 index) = before (base + BitVec.ofNat 64 index)) :
    Bytes after base bytes :=
  ⟨stored.bounded, fun index inside => (same index inside).trans (stored.contents index inside)⟩

theorem Bytes.lane (stored : Bytes memory base bytes) (inside : index < bytes.length) :
    (base + BitVec.ofNat 64 index).toNat = base.toNat + index := by
  have bounded := stored.bounded
  simp only [BitVec.toNat_add, BitVec.toNat_ofNat]
  omega

/-- Mathematical byte-store effect; matching this effect to an emitted
instruction is a separate machine/execution obligation. -/
def writeByte (memory : Memory) (address : Machine.Address) (byte : UInt8) : Memory :=
  fun candidate => if candidate = address then byte else memory candidate

theorem writeByte_frame (different : candidate ≠ address) :
    writeByte memory address byte candidate = memory candidate := by
  simp [writeByte, different]

theorem Bytes.store (stored : Bytes memory base bytes)
    (inside : index < bytes.length) (byte : UInt8) :
    Bytes (writeByte memory (base + BitVec.ofNat 64 index) byte) base (bytes.set index byte) := by
  refine ⟨by simpa using stored.bounded, ?_⟩
  intro other bound
  have original : other < bytes.length := by simpa using bound
  by_cases same : other = index
  · subst other
    simp [writeByte]
  · have bound := stored.bounded
    have disjoint := offset_ne base other index (by omega) (by omega) same
    simpa [writeByte, disjoint, List.getElem_set, Ne.symm same] using stored.contents other original

theorem bytes_length (text : _root_.String) :
    (Lanius.World.utf8Bytes text).length = text.utf8ByteSize := by
  simp only [Lanius.World.utf8Bytes, Array.length_toList]
  rfl

/-- A string descriptor denotes its UTF-8 contents, not a canonical address.
The surrounding heap relation must supply mapping and immutability. -/
structure Represents (memory : Memory) (descriptor : Machine.Address) (text : _root_.String) : Prop where
  lengthBound : text.utf8ByteSize < 2^64
  byteLength : read64 memory (descriptor + 8) = BitVec.ofNat 64 text.utf8ByteSize
  data : Bytes memory (read64 memory descriptor) (Lanius.World.utf8Bytes text)

def Represents.pointer (_stored : Represents memory descriptor text) : Machine.Address :=
  read64 memory descriptor

/-- The old global `Locations.string` choice remains usable when literals
are pooled. It is a specialization, not a uniqueness requirement on contents. -/
theorem of_canonical (stored : Storage.Represents locations memory descriptor (.string text))
    (data : Bytes memory (locations.string text) (Lanius.World.utf8Bytes text)) :
    Represents memory descriptor text := by
  obtain ⟨words, encoded, stored⟩ := stored
  simp only [shape] at encoded
  split at encoded
  · rename_i bounded
    cases encoded
    refine ⟨bounded, stored.descriptor.2, ?_⟩
    rwa [stored.descriptor.1]
  · contradiction

theorem Represents.frame (stored : Represents before descriptor text)
    (descriptorSame : ∀ word : Fin 2, ∀ lane : Fin 8,
      after (Machine.Copy.address descriptor word.val + BitVec.ofNat 64 lane.val) =
        before (Machine.Copy.address descriptor word.val + BitVec.ofNat 64 lane.val))
    (dataSame : ∀ index, index < (Lanius.World.utf8Bytes text).length →
      after (stored.pointer + BitVec.ofNat 64 index) = before (stored.pointer + BitVec.ofNat 64 index)) :
    Represents after descriptor text := by
  refine ⟨stored.lengthBound, ?_, ?_⟩
  · rw [read64_congr after before (descriptor + 8) (by simpa [Machine.Copy.address] using descriptorSame ⟨1, by decide⟩)]
    exact stored.byteLength
  · rw [read64_congr after before descriptor (by simpa [Machine.Copy.address] using descriptorSame ⟨0, by decide⟩)]
    exact stored.data.frame dataSame

/-- The emitted two-word MOV64 sequence preserves the content-based string
relation, without imposing literal pooling. This copies only the descriptor;
the distinct fresh buffer required by `stringDataPtr` is handled separately. -/
theorem copy_descriptor (before : Machine.State)
    (stored : Represents before.memory (before.registers 0) text)
    (loaded : CodeAt before.memory before.rip (Machine.Copy.bytes 0 2))
    (separate : Machine.Copy.Separated (before.registers 0) (before.registers 11) 0 2)
    (codeSeparate : ∀ index, index < (Machine.Copy.bytes 0 2).length →
      Machine.Copy.Outside (before.registers 11) 0 2 (before.rip + BitVec.ofNat 64 index))
    (dataSeparate : ∀ index, index < (Lanius.World.utf8Bytes text).length →
      Machine.Copy.Outside (before.registers 11) 0 2 (stored.pointer + BitVec.ofNat 64 index)) :
    ∃ after, Machine.Copy.Result before after 0 2 ∧
      Represents after.memory (before.registers 11) text ∧
      Represents after.memory (before.registers 0) text := by
  obtain ⟨after, result⟩ := Machine.Copy.correct 2 before 0 (by decide) loaded separate codeSeparate
  have data := stored.data.frame (fun index inside => result.frame _ (dataSeparate index inside))
  have pointer : read64 after.memory (before.registers 11) = stored.pointer := by
    simpa [Machine.Copy.address, Represents.pointer] using result.copied 0 (by decide)
  have length : read64 after.memory (before.registers 11 + 8) = BitVec.ofNat 64 text.utf8ByteSize := by
    simpa [Machine.Copy.address] using (result.copied 1 (by decide)).trans stored.byteLength
  refine ⟨after, result, ⟨stored.lengthBound, length, ?_⟩, ?_⟩
  · rw [pointer]
    exact data
  · apply stored.frame
    · intro word lane
      exact result.frame _ (by simpa using separate word.val word.isLt lane)
    · intro index inside
      exact result.frame _ (dataSeparate index inside)

end Lanius.X86.Storage.String
