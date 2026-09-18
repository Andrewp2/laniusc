import Lanius.X86.Storage.Heap

namespace Lanius.X86.Storage

namespace Locations

/-- Add one fresh allocation's identity range to the proof correspondence.
This is not emitted code or a runtime address-translation table. -/
def extend (locations : Locations) (fresh : Lanius.Memory.Block) (native : Machine.Address)
    (positive : 0 < fresh.base) (nonnull : native ≠ 0)
    (bounded : native.toNat + max fresh.size 1 ≤ 2^64) : Locations where
  slice := locations.slice
  string := locations.string
  pointer := fun pointer =>
    if fresh.base ≤ pointer ∧ pointer < fresh.base + max fresh.size 1 then
      some (native + BitVec.ofNat 64 (pointer - fresh.base))
    else locations.pointer pointer
  pointer_null := by simp [Nat.not_le.mpr positive, locations.pointer_null]
  pointer_eq_null := by
    intro pointer mapped
    split at mapped
    · rename_i inside
      have number := congrArg BitVec.toNat (Option.some.inj mapped)
      have nativePositive : 0 < native.toNat := by
        have notZero : native.toNat ≠ 0 := fun zero => nonnull (BitVec.eq_of_toNat_eq zero)
        omega
      change (native + BitVec.ofNat 64 (pointer - fresh.base)).toNat = 0 at number
      simp only [BitVec.toNat_add, BitVec.toNat_ofNat] at number
      simp only [Lanius.Address] at *
      omega
    · exact locations.pointer_eq_null pointer mapped

variable {locations : Locations} {fresh : Lanius.Memory.Block} {native : Machine.Address}
  {positive : 0 < fresh.base} {nonnull : native ≠ 0}
  {bounded : native.toNat + max fresh.size 1 ≤ 2^64} {pointer offset : Nat}

@[simp] theorem extend_slice : (locations.extend fresh native positive nonnull bounded).slice = locations.slice := rfl
@[simp] theorem extend_string : (locations.extend fresh native positive nonnull bounded).string = locations.string := rfl

theorem extend_outside (outside : ¬ (fresh.base ≤ pointer ∧ pointer < fresh.base + max fresh.size 1)) :
    (locations.extend fresh native positive nonnull bounded).pointer pointer = locations.pointer pointer := by
  simp only [extend, if_neg outside]

theorem extend_below (below : pointer < fresh.base) :
    (locations.extend fresh native positive nonnull bounded).pointer pointer = locations.pointer pointer :=
  extend_outside (fun inside => Nat.not_le.mpr below inside.1)

theorem extend_inside (inside : offset < max fresh.size 1) :
    (locations.extend fresh native positive nonnull bounded).pointer (fresh.base + offset) =
      some (native + BitVec.ofNat 64 offset) := by
  simp only [extend, if_pos (show fresh.base ≤ fresh.base + offset ∧
    fresh.base + offset < fresh.base + max fresh.size 1 from
      ⟨Nat.le_add_right _ _, Nat.add_lt_add_left inside _⟩), Nat.add_sub_cancel_left]

@[simp] theorem extend_base :
    (locations.extend fresh native positive nonnull bounded).pointer fresh.base = some native := by
  simpa using (extend_inside (locations := locations) (positive := positive) (nonnull := nonnull)
    (bounded := bounded) (offset := 0) (by omega))

end Locations

namespace Heap

variable {heap afterHeap : Lanius.Memory.Heap} {memory afterMemory : Machine.Memory}
  {locations : Locations} {fresh block : Lanius.Memory.Block} {native : Machine.Address}

private theorem old_below (related : Correspondence heap memory locations)
    (frontier : heap.nextAddress ≤ fresh.base) (member : block ∈ heap.blocks)
    (inside : offset < max block.size 1) : block.base + offset < fresh.base := by
  have below := related.wellFormed.blocksBelowNext block member
  change block.base + max block.size 1 ≤ heap.nextAddress at below
  exact Nat.lt_of_lt_of_le (Nat.add_lt_add_left inside block.base) (Nat.le_trans below frontier)

/-- Every previously mapped address lies below the fresh abstract range,
including the identity address of an empty allocation. -/
theorem Correspondence.extend_old (related : Correspondence heap memory locations)
    (fresh : Lanius.Memory.Block) (native : Machine.Address)
    (frontier : heap.nextAddress ≤ fresh.base) (positive : 0 < fresh.base)
    (nonnull : native ≠ 0) (bounded : native.toNat + max fresh.size 1 ≤ 2^64)
    (mapped : locations.pointer pointer = some address) :
    (locations.extend fresh native positive nonnull bounded).pointer pointer = some address := by
  have below : pointer < fresh.base := by
    by_cases zero : pointer = 0
    · exact zero ▸ positive
    · obtain ⟨block, base, offset, member, _, inside, equal, _⟩ := related.covered pointer address mapped zero
      rw [equal]
      exact old_below related frontier member inside
  rw [Locations.extend_below below]
  exact mapped

/-- Appending a represented fresh block preserves the whole heap/native
correspondence. Old byte framing and disjoint native identity ranges are
explicit allocation-effect obligations, not assumed allocator correctness. -/
theorem Correspondence.extend (related : Correspondence heap memory locations)
    (frontier : heap.nextAddress ≤ fresh.base)
    (appended : afterHeap.blocks = heap.blocks ++ [fresh])
    (wellFormed : Lanius.Memory.HeapWellFormed afterHeap)
    (represented : BlockRep fresh afterMemory native) (nonnull : native ≠ 0)
    (frame : ∀ block, block ∈ heap.blocks → ∀ base, locations.pointer block.base = some base →
      ∀ offset, offset < block.size → afterMemory (base + BitVec.ofNat 64 offset) = memory (base + BitVec.ofNat 64 offset))
    (separate : ∀ block, block ∈ heap.blocks → ∀ base, locations.pointer block.base = some base →
      base.toNat + max block.size 1 ≤ native.toNat ∨ native.toNat + max fresh.size 1 ≤ base.toNat) :
    Correspondence afterHeap afterMemory (locations.extend fresh native
      (Nat.lt_of_lt_of_le related.wellFormed.nextAddressPositive frontier) nonnull represented.nativeBound) := by
  let positive : 0 < fresh.base := Nat.lt_of_lt_of_le related.wellFormed.nextAddressPositive frontier
  let extended := locations.extend fresh native positive nonnull represented.nativeBound
  have splitMember (block : Lanius.Memory.Block) (member : block ∈ afterHeap.blocks) :
      block ∈ heap.blocks ∨ block = fresh := by simpa only [appended, List.mem_append, List.mem_singleton] using member
  have freshMember : fresh ∈ afterHeap.blocks := by simp [appended]
  have oldBase (block : Lanius.Memory.Block) (member : block ∈ heap.blocks) :
      extended.pointer block.base = locations.pointer block.base := by
    apply Locations.extend_below
    simpa using old_below related frontier member (offset := 0) (by omega)
  have freshBase : extended.pointer fresh.base = some native := Locations.extend_base
  refine ⟨wellFormed, ?_, ?_, ?_, ?_⟩
  · intro block member base mapped
    rcases splitMember block member with old | rfl
    · rw [oldBase block old] at mapped
      have previous := related.mappedBlock block old base mapped
      exact { previous with bytes := fun offset inside => by rw [frame block old base mapped offset inside]; exact previous.bytes offset inside }
    · rw [freshBase] at mapped
      cases Option.some.inj mapped
      exact represented
  · intro block member base mapped offset inside
    rcases splitMember block member with old | rfl
    · rw [oldBase block old] at mapped
      rw [Locations.extend_below (old_below related frontier old inside)]
      exact related.offsets block old base mapped offset inside
    · rw [freshBase] at mapped
      cases Option.some.inj mapped
      exact Locations.extend_inside inside
  · intro pointer address mapped nonzero
    by_cases inside : fresh.base ≤ pointer ∧ pointer < fresh.base + max fresh.size 1
    · have newMap : some (native + BitVec.ofNat 64 (pointer - fresh.base)) = some address := by
        simpa only [extended, Locations.extend, if_pos inside] using mapped
      exact ⟨fresh, native, pointer - fresh.base, freshMember, freshBase, by omega, (Nat.add_sub_of_le inside.1).symm,
        (Option.some.inj newMap).symm⟩
    · rw [Locations.extend_outside inside] at mapped
      obtain ⟨block, base, offset, member, baseMap, offsetBound, logical, physical⟩ :=
        related.covered pointer address mapped nonzero
      exact ⟨block, base, offset, by simp [appended, member], (oldBase block member).trans baseMap,
        offsetBound, logical, physical⟩
  · intro left leftMember leftBase leftMap right rightMember rightBase rightMap different
    rcases splitMember left leftMember with leftOld | rfl <;>
      rcases splitMember right rightMember with rightOld | rfl
    · rw [oldBase left leftOld] at leftMap
      rw [oldBase right rightOld] at rightMap
      exact related.disjoint left leftOld leftBase leftMap right rightOld rightBase rightMap different
    · rw [oldBase left leftOld] at leftMap
      rw [freshBase] at rightMap
      cases Option.some.inj rightMap
      exact separate left leftOld leftBase leftMap
    · rw [freshBase] at leftMap
      rw [oldBase right rightOld] at rightMap
      cases Option.some.inj leftMap
      exact (separate right rightOld rightBase rightMap).symm
    · exact False.elim (different rfl)

end Heap
end Lanius.X86.Storage
