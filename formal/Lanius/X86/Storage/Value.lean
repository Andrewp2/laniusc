import Lanius.Core
import Lanius.X86.Machine.Copy

namespace Lanius.X86.Storage

open Lanius.Core

/-- Native addresses are a proof parameter, not a runtime translation table
or permission to dereference. Raw Core pointers have a partial mapping:
unmapped addresses are not representable, and null is preserved and reflected.
Live bounded allocations and pointer injectivity are separate heap invariants. -/
structure Locations where
  slice : CellId → List ValueProjection → Nat → Machine.Address
  string : String → Machine.Address
  pointer : Nat → Option Machine.Address
  pointer_null : pointer 0 = some 0
  pointer_eq_null : ∀ value, pointer value = some 0 → value = 0

/-- Distinct represented Core addresses have distinct native addresses.
Storage and copying alone do not establish this heap-correspondence invariant. -/
def Locations.PointerInjective (locations : Locations) : Prop :=
  ∀ ⦃left right : Nat⦄ ⦃native : Machine.Address⦄,
    locations.pointer left = some native → locations.pointer right = some native → left = right

theorem Locations.pointer_null_iff (locations : Locations)
    (mapped : locations.pointer value = some native) : native = 0 ↔ value = 0 := by
  constructor
  · intro zero
    exact locations.pointer_eq_null value (zero ▸ mapped)
  · intro zero
    subst value
    rw [locations.pointer_null] at mapped
    exact (Option.some.inj mapped).symm

/-- Native pointer equality agrees with Core address equality only after
the heap correspondence supplies injectivity; no numeric identity is needed. -/
theorem Locations.pointer_eq_iff (locations : Locations) (injective : locations.PointerInjective)
    (leftMapped : locations.pointer left = some leftNative)
    (rightMapped : locations.pointer right = some rightNative) :
    leftNative = rightNative ↔ left = right := by
  constructor
  · intro same
    exact injective (same ▸ leftMapped) rightMapped
  · intro same
    subst right
    exact Option.some.inj (leftMapped.symm.trans rightMapped)

/-- Padding above an i32 or bool is not part of the Core value. Whole-word
copies must preserve meaningful low bits, not assume initialized padding. -/
inductive Word where
  | low (value : BitVec 32)
  | full (value : BitVec 64)
  | padding

def Word.holds : Word → BitVec 64 → Prop
  | .low value, actual => actual.setWidth 32 = value
  | .full value, actual => actual = value
  | .padding, _ => True

/-- The internal value layout: one word per scalar, two for a descriptor,
and concatenated struct fields. Packed i32 arrays are heap data, not padded
value words. Unsupported Core kinds are rejected rather than reinterpreted. -/
def shape (locations : Locations) : Value → Option (List Word)
  | .signed .i32 value => if -2147483648 ≤ value ∧ value ≤ 2147483647 then
      some [.low (BitVec.ofInt 32 value)] else none
  | .boolean value => some [.low (if value then 1 else 0)]
  | .unsigned .usize value => if value < 2^64 then some [.full (BitVec.ofNat 64 value)] else none
  | .pointer value => (locations.pointer value).map fun native => [.full native]
  | .slice (.scalar (.signed .i32)) cell path start length =>
      if length < 2^64 then some [.full (locations.slice cell path start), .full (BitVec.ofNat 64 length)] else none
  | .string value => if value.utf8ByteSize < 2^64 then
      some [.full (locations.string value), .full (BitVec.ofNat 64 value.utf8ByteSize)] else none
  | .structure _ values => do
      let fields ← values.mapM (shape locations)
      pure (if fields.flatten.isEmpty then [.padding] else fields.flatten)
  | _ => none

def Stored (memory : Machine.Memory) (address : Machine.Address) (words : List Word) : Prop :=
  ∀ index, ∀ bound : index < words.length,
    words[index].holds (Machine.read64 memory (Machine.Copy.address address index))

def Represents (locations : Locations) (memory : Machine.Memory) (address : Machine.Address) (value : Value) : Prop :=
  ∃ words, shape locations value = some words ∧ Stored memory address words

@[simp] theorem shape_pointer : shape locations (.pointer value) =
    (locations.pointer value).map (fun native => [.full native]) := by simp [shape]

theorem shape_pointer_some (mapped : locations.pointer value = some native) :
    shape locations (.pointer value) = some [.full native] := by
  simp only [shape_pointer, mapped, Option.map_some]

theorem shape_pointer_none (unmapped : locations.pointer value = none) :
    shape locations (.pointer value) = none := by
  simp only [shape_pointer, unmapped, Option.map_none]

@[simp] theorem shape_null (locations : Locations) : shape locations (.pointer 0) = some [.full 0] :=
  shape_pointer_some locations.pointer_null

theorem shape_usize : shape locations (.unsigned .usize value) =
    if value < 2^64 then some [.full (BitVec.ofNat 64 value)] else none := by simp [shape]

theorem shape_usize_some (bounded : value < 2^64) :
    shape locations (.unsigned .usize value) = some [.full (BitVec.ofNat 64 value)] := by
  simp only [shape_usize, if_pos bounded]

theorem shape_usize_none (unbounded : 2^64 ≤ value) :
    shape locations (.unsigned .usize value) = none := by
  simp only [shape_usize, if_neg (Nat.not_lt.mpr unbounded)]

theorem Stored.full_iff : Stored memory address [.full value] ↔ Machine.read64 memory address = value := by
  constructor
  · intro stored
    simpa [Word.holds, Machine.Copy.address] using stored 0 (by simp)
  · intro stored index bound
    have zero : index = 0 := by simpa using bound
    subst index
    simpa [Word.holds, Machine.Copy.address] using stored

/-- The bits of a pointer word come from its explicit mapping, never the
abstract Core address. This contract alone grants no memory-access rights. -/
theorem Represents.pointer_iff : Represents locations memory address (.pointer value) ↔
    ∃ native, locations.pointer value = some native ∧ Machine.read64 memory address = native := by
  unfold Represents
  cases mapped : locations.pointer value <;> simp [mapped, Stored.full_iff]

theorem Represents.null_iff (locations : Locations) :
    Represents locations memory address (.pointer 0) ↔ Machine.read64 memory address = 0 := by
  rw [Represents.pointer_iff]
  simp [locations.pointer_null]

/-- Unlike pointers, usize values keep their numerical meaning independently
of every address assignment in Locations. -/
theorem Represents.usize_iff : Represents locations memory address (.unsigned .usize value) ↔
    value < 2^64 ∧ Machine.read64 memory address = BitVec.ofNat 64 value := by
  unfold Represents
  by_cases bounded : value < 2^64 <;> simp [shape, bounded, Stored.full_iff]

theorem Stored.low (stored : Stored memory address [.low value]) :
    Machine.read32 memory address = value := by
  have first := stored 0 (by simp)
  simpa [Word.holds, Machine.Copy.address, Machine.read64_low] using first

theorem Stored.descriptor (stored : Stored memory address [.full pointer, .full length]) :
    Machine.read64 memory address = pointer ∧ Machine.read64 memory (address + 8) = length := by
  have first := stored 0 (by simp)
  have second := stored 1 (by simp)
  simpa [Word.holds, Machine.Copy.address] using And.intro first second

/-- Copying the emitted MOV64 sequence preserves the same Core value at a
new address. The source representation, all other bytes, and all registers
except R10 survive. In particular a slice keeps its pointer *and* length;
this does not duplicate or change the backing array. -/
theorem copy_value (locations : Locations) (value : Value) (words : List Word) (before : Machine.State)
    (encoded : shape locations value = some words) (bounded : words.length ≤ 4096)
    (stored : Stored before.memory (before.registers 0) words)
    (loaded : Machine.CodeAt before.memory before.rip (Machine.Copy.bytes 0 words.length))
    (separate : Machine.Copy.Separated (before.registers 0) (before.registers 11) 0 words.length)
    (codeSeparate : ∀ index, index < (Machine.Copy.bytes 0 words.length).length →
      Machine.Copy.Outside (before.registers 11) 0 words.length (before.rip + BitVec.ofNat 64 index)) :
    ∃ after, Machine.Copy.Result before after 0 words.length ∧
      Represents locations after.memory (before.registers 11) value ∧
      Represents locations after.memory (before.registers 0) value := by
  obtain ⟨after, result⟩ := Machine.Copy.correct words.length before 0 (by omega) loaded separate codeSeparate
  refine ⟨after, result, ⟨words, encoded, ?_⟩, ⟨words, encoded, ?_⟩⟩
  · intro index bound
    have copied := result.copied index bound
    simp only [Nat.zero_add] at copied
    rw [copied]
    exact stored index bound
  · intro index bound
    have unchanged : Machine.read64 after.memory (Machine.Copy.address (before.registers 0) index) =
        Machine.read64 before.memory (Machine.Copy.address (before.registers 0) index) := by
      apply Machine.read64_congr
      intro lane
      apply result.frame
      simpa using separate index bound lane
    rw [unchanged]
    exact stored index bound

end Lanius.X86.Storage
