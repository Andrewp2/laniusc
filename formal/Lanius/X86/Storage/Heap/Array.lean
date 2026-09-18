import Lanius.X86.Storage.Heap
import Lanius.X86.Storage.Slice
import Lanius.Memory.Access
import Lanius.ExecutionRules

namespace Lanius.X86.Storage.Heap

open Lanius.Core Lanius.Semantics Lanius.Properties

namespace Array

/-- A finite native byte window, used only to state the correspondence. -/
def bytes (memory : Machine.Memory) (base : Machine.Address) (count : Nat) : List UInt8 :=
  List.ofFn (fun index : Fin count => memory (base + BitVec.ofNat 64 index.val))

@[simp] theorem bytes_length : (bytes memory base count).length = count := by simp [bytes]

theorem bytes_succ (memory : Machine.Memory) (base : Machine.Address) (count : Nat) :
    bytes memory base (count + 1) = memory base :: bytes memory (base + 1) count := by
  simp [bytes, List.ofFn_succ, BitVec.ofNat_add, BitVec.add_assoc, BitVec.add_comm]
  congr 1
  funext index
  congr 1
  rw [← BitVec.add_assoc, BitVec.add_comm base (BitVec.ofNat 64 index.val), BitVec.add_assoc]

/-- Subwindows retain the exact native addresses, not merely equal lengths. -/
theorem bytes_window (room : start + length ≤ count) :
    ((bytes memory base count).drop start).take length =
      bytes memory (base + BitVec.ofNat 64 start) length := by
  apply List.ext_getElem?
  intro index
  by_cases inside : index < length
  · rw [List.getElem?_take_of_lt inside, List.getElem?_drop]
    have within : start + index < count := by omega
    simp only [bytes, List.getElem?_ofFn, dif_pos within, dif_pos inside,
      BitVec.ofNat_add, BitVec.add_assoc]
  · rw [List.getElem?_eq_none (by simp only [List.length_take]; omega)]
    rw [List.getElem?_eq_none (by simp only [bytes_length]; omega)]

/-- Meaningful signed words selected by the actual recursive byte decoder. -/
def values : Nat → List UInt8 → List Int
  | 0, _ => []
  | count + 1, bytes => decodeI32 (bytes.take 4) :: values count (bytes.drop 4)

@[simp] theorem values_length {bytes : List UInt8} : (values count bytes).length = count := by
  induction count generalizing bytes with
  | zero => rfl
  | succ count ih => simp only [values, List.length_cons, ih]

theorem values_signed {bytes : List UInt8} : ∀ value ∈ values count bytes,
    -2147483648 ≤ value ∧ value ≤ 2147483647 := by
  induction count generalizing bytes with
  | zero => simp [values]
  | succ count ih =>
      intro value member
      rcases List.mem_cons.mp member with same | remaining
      · subst value
        simpa [Lanius.Typing.signedMin, Lanius.Typing.signedMax, SignedIntTy.bits] using
          decodeI32_in_range Target.x86_64 (bytes.take 4)
      · exact ih value remaining

theorem values_get {bytes : List UInt8} (inside : index < count) :
    (values count bytes)[index]'(by simpa using inside) = decodeI32 ((bytes.drop (index * 4)).take 4) := by
  induction count generalizing bytes index with
  | zero => omega
  | succ count ih =>
      cases index with
      | zero => simp [values]
      | succ index =>
          have tail := ih (bytes := bytes.drop 4) (index := index) (by omega)
          simp only [values, List.getElem_cons_succ]
          rw [tail, List.drop_drop]
          have shifted : 4 + index * 4 = (index + 1) * 4 := by omega
          rw [shifted]

/-- Exact byte length ensures the decoder succeeds, including the empty
case. This is an equation about decodeI32Array, not an assumed execution. -/
theorem decode_values {bytes : List UInt8} (exactLength : bytes.length = count * 4) :
    decodeI32Array count bytes = .ok (signedI32Values (values count bytes)) := by
  induction count generalizing bytes with
  | zero =>
      have empty : bytes = [] := List.eq_nil_of_length_eq_zero (by simpa using exactLength)
      subst bytes
      rfl
  | succ count ih =>
      have enough : ¬bytes.length < 4 := by omega
      have remaining : (bytes.drop 4).length = count * 4 := by simp only [List.length_drop]; omega
      rw [decodeI32Array, if_neg enough, ih remaining]
      rfl

end Array

/-- Read every byte of an arbitrary within-block window, deriving the exact
native byte sequence from the heap map rather than assuming a read result. -/
theorem Correspondence.load_bytes_from (related : Correspondence heap memory locations)
    (member : block ∈ heap.blocks) (mapped : locations.pointer block.base = some base)
    (room : start + offset + count ≤ block.size) :
    Lanius.Memory.loadBytesFrom heap (block.base + start) offset count =
      .ok (Array.bytes memory ((base + BitVec.ofNat 64 start) + BitVec.ofNat 64 offset) count) := by
  induction count generalizing offset with
  | zero => simp [Lanius.Memory.loadBytesFrom, Array.bytes]
  | succ count ih =>
      have first := related.load_byte member mapped (start := start) (offset := offset) (by omega)
      have remaining := ih (offset := offset + 1) (by omega)
      simp only [Lanius.Memory.loadBytesFrom, first, remaining, Array.bytes_succ]
      simp [BitVec.ofNat_add, BitVec.add_assoc]

theorem Correspondence.load_bytes (related : Correspondence heap memory locations)
    (member : block ∈ heap.blocks) (mapped : locations.pointer block.base = some base)
    (room : start + count ≤ block.size) :
    heap.loadBytes (block.base + start) count =
      .ok (Array.bytes memory (base + BitVec.ofNat 64 start) count) := by
  simpa [Lanius.Memory.Heap.loadBytes] using
    related.load_bytes_from member mapped (start := start) (offset := 0) room

/-- Decode a window actually read from the mapped heap into packed native
storage. Every native element is derived from byte agreement and the real
Core decoder. There is no per-element load premise. -/
theorem Correspondence.array (related : Correspondence heap memory locations)
    (member : block ∈ heap.blocks) (mapped : locations.pointer block.base = some base)
    (startInside : start < max block.size 1) (room : start + length * 4 ≤ block.size)
    (loaded : heap.loadBytes (block.base + start) (length * 4) = .ok bytes)
    (decoded : decodeI32Array length bytes = .ok elements) :
    ∃ values, elements = signedI32Values values ∧ values.length = length ∧
      Storage.Slice.Represents memory (base + BitVec.ofNat 64 start) values := by
  have exactLength := Lanius.Memory.Heap.loadBytes_length loaded
  have nativeBytes : bytes = Array.bytes memory (base + BitVec.ofNat 64 start) (length * 4) :=
    Except.ok.inj (loaded.symm.trans (related.load_bytes member mapped room))
  have valuesExact : elements = signedI32Values (Array.values length bytes) :=
    Except.ok.inj (decoded.symm.trans (Array.decode_values exactLength))
  refine ⟨Array.values length bytes, valuesExact, Array.values_length, ?_⟩
  have represented := related.mappedBlock block member base mapped
  refine ⟨?_, Array.values_signed, ?_⟩
  · rw [represented.address_toNat startInside, Array.values_length]
    have bounded := represented.nativeBound
    omega
  · intro index within
    have indexBound : index < length := by simpa only [Array.values_length] using within
    have wordRoom : start + index * 4 + 4 ≤ block.size := by omega
    have word := related.load_i32 member mapped (start := start + index * 4) wordRoom
    rw [related.load_bytes member mapped wordRoom] at word
    change Except.ok (decodeI32 (Array.bytes memory (base + BitVec.ofNat 64 (start + index * 4)) 4)) =
      Except.ok (Machine.read32 memory (base + BitVec.ofNat 64 (start + index * 4))).toInt at word
    have observed := Except.ok.inj word
    rw [Array.values_get indexBound, nativeBytes, Array.bytes_window (by omega)]
    simp only [Storage.Slice.address, BitVec.ofNat_add, BitVec.add_assoc] at observed ⊢
    rw [observed, BitVec.ofInt_toInt]

/-- The mapped extent alone supplies successful actual loading and decoding
plus the packed representation. Empty zero-sized allocations are included;
positive-sized one-past pointers remain outside the represented domain. -/
theorem Correspondence.array_exists (related : Correspondence heap memory locations)
    (member : block ∈ heap.blocks) (mapped : locations.pointer block.base = some base)
    (startInside : start < max block.size 1) (room : start + length * 4 ≤ block.size) :
    ∃ bytes values, heap.loadBytes (block.base + start) (length * 4) = .ok bytes ∧
      bytes.length = length * 4 ∧ decodeI32Array length bytes = .ok (signedI32Values values) ∧
      values.length = length ∧ Storage.Slice.Represents memory (base + BitVec.ofNat 64 start) values := by
  let bytes := Array.bytes memory (base + BitVec.ofNat 64 start) (length * 4)
  have loaded : heap.loadBytes (block.base + start) (length * 4) = .ok bytes :=
    related.load_bytes member mapped room
  have exactLength : bytes.length = length * 4 := Array.bytes_length
  have decoded := Array.decode_values exactLength
  obtain ⟨values, same, count, represented⟩ := related.array member mapped startInside room loaded decoded
  exact ⟨bytes, values, loaded, exactLength, decoded.trans (congrArg Except.ok same), count, represented⟩

end Lanius.X86.Storage.Heap
