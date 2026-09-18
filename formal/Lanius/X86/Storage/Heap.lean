import Lanius.Semantics
import Lanius.X86.Storage.Value

namespace Lanius.X86.Storage.Heap

/-- One represented live allocation. Reserving one identity address for a
zero-byte block does not authorize any byte access. The logical bound is
needed only to compare within-block addition with Core's wrapping pointers. -/
structure BlockRep (block : Lanius.Memory.Block) (memory : Machine.Memory)
    (base : Machine.Address) : Prop where
  live : block.live = true
  logicalBound : block.base + max block.size 1 ≤ 2 ^ 64
  nativeBound : base.toNat + max block.size 1 ≤ 2 ^ 64
  aligned : base.toNat % block.alignment = 0
  bytes : ∀ offset, offset < block.size →
    block.bytes[offset]? = some (memory (base + BitVec.ofNat 64 offset))

/-- A partial, proof-only correspondence, not a native address-translation
table. Unmapped Core blocks need not have native storage. Every nonnull
mapped address must belong to a mapped live block; offset closure and native
disjointness describe precisely the represented domain. Dangling/outside
locations have no representation. Core's numeric addresses do not track the
provenance of a forged integer coinciding with a valid live location. -/
structure Correspondence (heap : Lanius.Memory.Heap) (memory : Machine.Memory)
    (locations : Locations) : Prop where
  wellFormed : Lanius.Memory.HeapWellFormed heap
  mappedBlock : ∀ (block : Lanius.Memory.Block), block ∈ heap.blocks →
    ∀ base, locations.pointer block.base = some base → BlockRep block memory base
  offsets : ∀ (block : Lanius.Memory.Block), block ∈ heap.blocks →
    ∀ base, locations.pointer block.base = some base →
    ∀ offset, offset < max block.size 1 →
      locations.pointer (block.base + offset) = some (base + BitVec.ofNat 64 offset)
  covered : ∀ pointer native, locations.pointer pointer = some native → pointer ≠ 0 →
    ∃ block base offset, block ∈ heap.blocks ∧ locations.pointer block.base = some base ∧
      offset < max block.size 1 ∧ pointer = block.base + offset ∧ native = base + BitVec.ofNat 64 offset
  disjoint : ∀ (left : Lanius.Memory.Block), left ∈ heap.blocks →
    ∀ leftBase, locations.pointer left.base = some leftBase →
    ∀ (right : Lanius.Memory.Block), right ∈ heap.blocks →
    ∀ rightBase, locations.pointer right.base = some rightBase → left.base ≠ right.base →
      leftBase.toNat + max left.size 1 ≤ rightBase.toNat ∨
        rightBase.toNat + max right.size 1 ≤ leftBase.toNat

theorem BlockRep.address_toNat (represented : BlockRep block memory base)
    (inside : offset < max block.size 1) :
    (base + BitVec.ofNat 64 offset).toNat = base.toNat + offset := by
  have bounded := represented.nativeBound
  simp only [BitVec.toNat_add, BitVec.toNat_ofNat]
  omega

/-- Injectivity follows from live-block offset preservation and disjoint
native ranges, rather than being assumed by generic value storage. -/
theorem Correspondence.pointer_injective (related : Correspondence heap memory locations) :
    locations.PointerInjective := by
  intro left right native leftMapped rightMapped
  by_cases leftNull : left = 0
  · have nativeNull := (locations.pointer_null_iff leftMapped).2 leftNull
    have rightNull := (locations.pointer_null_iff rightMapped).1 nativeNull
    exact leftNull.trans rightNull.symm
  by_cases rightNull : right = 0
  · have nativeNull := (locations.pointer_null_iff rightMapped).2 rightNull
    exact False.elim (leftNull ((locations.pointer_null_iff leftMapped).1 nativeNull))
  obtain ⟨leftBlock, leftBase, leftOffset, leftMember, leftMap, leftInside, leftAddress, leftNative⟩ :=
    related.covered left native leftMapped leftNull
  obtain ⟨rightBlock, rightBase, rightOffset, rightMember, rightMap, rightInside, rightAddress, rightNative⟩ :=
    related.covered right native rightMapped rightNull
  have leftNumber := congrArg BitVec.toNat leftNative
  have rightNumber := congrArg BitVec.toNat rightNative
  rw [(related.mappedBlock leftBlock leftMember leftBase leftMap).address_toNat leftInside] at leftNumber
  rw [(related.mappedBlock rightBlock rightMember rightBase rightMap).address_toNat rightInside] at rightNumber
  by_cases same : leftBlock.base = rightBlock.base
  · have blocks := related.wellFormed.blockBasesUnique leftBlock leftMember rightBlock rightMember same
    subst rightBlock
    have bases : leftBase = rightBase := Option.some.inj (leftMap.symm.trans rightMap)
    subst rightBase
    omega
  · have separate := related.disjoint leftBlock leftMember leftBase leftMap
      rightBlock rightMember rightBase rightMap same
    rcases separate with separate | separate <;> omega

/-- Addition is preserved only while the resulting location remains inside
this represented block's identity range. In particular neither the logical
nor native machine-width addition wraps. This is not a theorem about
unrestricted pointer arithmetic or one-past pointers. -/
theorem Correspondence.within_add (related : Correspondence heap memory locations)
    (member : block ∈ heap.blocks) (mapped : locations.pointer block.base = some base)
    (inside : start + offset < max block.size 1) :
    locations.pointer (block.base + start + offset) =
      some ((base + BitVec.ofNat 64 start) + BitVec.ofNat 64 offset) ∧
    ((BitVec.ofNat 64 (block.base + start)) + BitVec.ofNat 64 offset).toNat = block.base + start + offset ∧
    ((base + BitVec.ofNat 64 start) + BitVec.ofNat 64 offset).toNat = base.toNat + start + offset := by
  have represented := related.mappedBlock block member base mapped
  refine ⟨?_, ?_, ?_⟩
  · simpa only [Nat.add_assoc, BitVec.ofNat_add, BitVec.add_assoc] using
      related.offsets block member base mapped (start + offset) inside
  · rw [← BitVec.ofNat_add]
    apply Nat.mod_eq_of_lt
    exact Nat.lt_of_lt_of_le
      (by simpa only [Nat.add_assoc] using Nat.add_lt_add_left inside block.base)
      represented.logicalBound
  · simpa only [BitVec.ofNat_add, BitVec.add_assoc, Nat.add_assoc] using represented.address_toNat inside

/-- The Core heap's actual lookup selects this live block for an in-bounds
byte. Global abstract disjointness excludes another block winning find?. -/
theorem containing_block (wellFormed : Lanius.Memory.HeapWellFormed heap)
    (member : block ∈ heap.blocks) (live : block.live = true) (inside : offset < block.size) :
    heap.containingBlock? (block.base + offset) = some block := by
  have selected : (block.live && block.base ≤ block.base + offset &&
      block.base + offset < block.base + block.size) = true := by simp [live, inside]
  cases found : heap.containingBlock? (block.base + offset) with
  | none =>
      have absent := List.find?_eq_none.mp found
      exact False.elim (absent block member selected)
  | some other =>
      have otherMember := List.mem_of_find?_eq_some found
      have bounds := List.find?_some found
      change (other.live && other.base ≤ block.base + offset &&
        block.base + offset < other.base + other.size) = true at bounds
      simp only [Bool.and_eq_true, decide_eq_true_eq] at bounds
      by_cases same : other = block
      · subst other
        rfl
      · have disjoint := wellFormed.blocksDisjoint other otherMember block member same
        rcases disjoint with first | second
        · exact False.elim (Nat.not_lt_of_ge (Nat.le_add_right block.base offset)
            (Nat.lt_of_lt_of_le bounds.2 first))
        · exact False.elim (Nat.not_le_of_gt inside
            (Nat.le_of_add_le_add_left (Nat.le_trans second bounds.1.2)))

/-- An actual Core byte read at any within-block pointer+offset returns the
byte at the translated native address. No cross-allocation read is admitted. -/
theorem Correspondence.load_byte (related : Correspondence heap memory locations)
    (member : block ∈ heap.blocks) (mapped : locations.pointer block.base = some base)
    (inside : start + offset < block.size) :
    heap.loadByte (block.base + start) offset =
      .ok (memory ((base + BitVec.ofNat 64 start) + BitVec.ofNat 64 offset)) := by
  have represented := related.mappedBlock block member base mapped
  have found := containing_block related.wellFormed member represented.live inside
  simp only [Lanius.Memory.Heap.loadByte, Nat.add_assoc, found, Nat.add_sub_cancel_left]
  rw [represented.bytes (start + offset) inside]
  simp only [BitVec.ofNat_add, BitVec.add_assoc]

/-- The exact four bytes read by Core and by the native MOV32 operand. -/
theorem Correspondence.load_bytes4 (related : Correspondence heap memory locations)
    (member : block ∈ heap.blocks) (mapped : locations.pointer block.base = some base)
    (inside : start + 4 ≤ block.size) :
    heap.loadBytes (block.base + start) 4 = .ok
      [memory (base + BitVec.ofNat 64 start),
       memory (base + BitVec.ofNat 64 start + 1),
       memory (base + BitVec.ofNat 64 start + 2),
       memory (base + BitVec.ofNat 64 start + 3)] := by
  have first := related.load_byte member mapped (start := start) (offset := 0) (by omega)
  have second := related.load_byte member mapped (start := start) (offset := 1) (by omega)
  have third := related.load_byte member mapped (start := start) (offset := 2) (by omega)
  have fourth := related.load_byte member mapped (start := start) (offset := 3) (by omega)
  simp [Lanius.Memory.Heap.loadBytes, Lanius.Memory.loadBytesFrom, first, second, third, fourth]

private theorem decode_native (memory : Machine.Memory) (address : Machine.Address) :
    Lanius.Semantics.decodeI32 [memory address, memory (address + 1), memory (address + 2), memory (address + 3)] =
      (Machine.read32 memory address).toInt := by
  have first := UInt8.toNat_lt (memory address)
  have second := UInt8.toNat_lt (memory (address + 1))
  have third := UInt8.toNat_lt (memory (address + 2))
  have fourth := UInt8.toNat_lt (memory (address + 3))
  simp only [Lanius.Semantics.decodeI32, Machine.read32, readBytes, BitVec.toInt_eq_toNat_cond,
    BitVec.toNat_ofNat, Int.ofNat_eq_natCast, Nat.mul_comm]
  split <;> split <;> omega

/-- Read and decode using the actual Core heap operations. The resulting
signed i32 equals the native MOV32 load's meaningful low 32 bits. -/
theorem Correspondence.load_i32 (related : Correspondence heap memory locations)
    (member : block ∈ heap.blocks) (mapped : locations.pointer block.base = some base)
    (inside : start + 4 ≤ block.size) :
    (heap.loadBytes (block.base + start) 4).map Lanius.Semantics.decodeI32 =
      .ok (Machine.read32 memory (base + BitVec.ofNat 64 start)).toInt := by
  rw [related.load_bytes4 member mapped inside]
  simp only [Except.map, decode_native]

end Lanius.X86.Storage.Heap
