import Lanius.Memory.Store

namespace Lanius.Memory

open Lanius.Properties

theorem Heap.mapped_borrowed_block
    (wellFormed : HeapWellFormed heap)
    (mapped : heap.mapBorrowed bytes alignment = .allocated address after) :
    after.block? address = some {
      base := address, size := bytes.length, alignment, bytes, owned := false } := by
  unfold Heap.mapBorrowed at mapped
  split at mapped
  · contradiction
  · cases mapped
    rename_i alignmentNotInvalid
    have valid : validAlignment alignment = true := by simpa using alignmentNotInvalid
    have frontier := Nat.le_trans (Nat.le_max_left heap.nextAddress 1)
      (alignUp_ge (max heap.nextAddress 1) alignment
        (valid_alignment_is_nonzero alignment valid))
    have found := block?_append_fresh (block := {
      base := alignUp (max heap.nextAddress 1) alignment,
      size := bytes.length, alignment, bytes, owned := false }) wellFormed frontier
    simpa only [Heap.block?] using found

/-- Every byte of a newly mapped borrowed block is readable, regardless of
the contents of earlier allocations. No padding outside the block is exposed. -/
theorem Heap.loadBytes_mapped_borrowed
    (wellFormed : HeapWellFormed heap)
    (mapped : heap.mapBorrowed bytes alignment = .allocated address after) :
    after.loadBytes address bytes.length = .ok bytes := by
  unfold Heap.mapBorrowed at mapped
  split at mapped
  · contradiction
  · cases mapped
    rename_i alignmentNotInvalid
    have valid : validAlignment alignment = true := by simpa using alignmentNotInvalid
    have aligned := alignUp_ge (max heap.nextAddress 1) alignment
      (valid_alignment_is_nonzero alignment valid)
    apply loadBytesFrom_of_reads
    intro index byte selected
    have bound := (List.getElem?_eq_some_iff.mp selected).1
    have oldMissing : heap.blocks.find? (fun block =>
        block.live && block.base ≤ alignUp (max heap.nextAddress 1) alignment + index &&
          alignUp (max heap.nextAddress 1) alignment + index < block.base + block.size) = none := by
      apply List.find?_eq_none.mpr
      intro block member
      have below := wellFormed.blocksBelowNext block member
      change block.base + max block.size 1 ≤ heap.nextAddress at below
      have above : block.base + block.size ≤ alignUp (max heap.nextAddress 1) alignment + index := by
        calc
          block.base + block.size ≤ block.base + max block.size 1 := Nat.add_le_add_left (Nat.le_max_left _ _) _
          _ ≤ heap.nextAddress := below
          _ ≤ max heap.nextAddress 1 := Nat.le_max_left _ _
          _ ≤ alignUp (max heap.nextAddress 1) alignment := aligned
          _ ≤ alignUp (max heap.nextAddress 1) alignment + index := Nat.le_add_right _ _
      simp [Nat.not_lt.mpr above]
    simp only [Heap.loadByte, Nat.zero_add, Heap.containingBlock?, List.find?_append, oldMissing,
      List.find?_cons, List.find?_nil]
    simpa [bound] using selected

/-- Protecting an already borrowed exact block leaves its bytes and metadata
unchanged. A partial or oversized view is still rejected by the memory API. -/
theorem Heap.protect_borrowed_identity
    (wellFormed : HeapWellFormed heap) (found : heap.block? address = some block)
    (live : block.live = true) (borrowed : block.owned = false) :
    heap.protectAsBorrowed address block.size block.alignment = .ok heap := by
  have unchanged : { block with owned := false } = block := by
    cases block
    simp_all
  have replaced : replaceBlock heap.blocks block = heap.blocks := by
    rw [replaceBlock_eq_map]
    calc
      _ = heap.blocks.map id := by
        apply List.map_congr_left
        intro candidate member
        by_cases same : candidate.base = block.base
        · have equal := wellFormed.blockBasesUnique candidate member block
            (List.mem_of_find?_eq_some found) same
          simp [equal]
        · simp [same]
      _ = heap.blocks := List.map_id heap.blocks
  simp only [Heap.protectAsBorrowed, found]
  rw [unchanged, replaced]
  simp [live]

end Lanius.Memory
