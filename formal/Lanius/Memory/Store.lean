import Lanius.Properties
import Lanius.Memory.Bytes

namespace Lanius.Memory

open Lanius

theorem setByte_get_same (bytes : List UInt8) (index : Nat) (byte : UInt8)
    (within : index < bytes.length) :
    (setByte bytes index byte)[index]? = some byte := by
  induction bytes generalizing index with
  | nil => simp at within
  | cons head tail ih =>
      cases index with
      | zero => rfl
      | succ index =>
          simpa [setByte] using ih index (by simpa using within)

theorem setByte_get_other (bytes : List UInt8) (index queried : Nat) (byte : UInt8)
    (different : queried ≠ index) :
    (setByte bytes index byte)[queried]? = bytes[queried]? := by
  induction bytes generalizing index queried with
  | nil => simp [setByte]
  | cons head tail ih =>
      cases index <;> cases queried <;> simp_all [setByte]

/-- Changing a block's bytes cannot change which allocation contains an
address. Base uniqueness is enough; the search order remains unchanged. -/
private theorem findContaining_replaceBytes
    (blocks : List Block) (original : Block) (bytes : List UInt8) (address : Nat)
    (unique : ∀ block ∈ blocks, block.base = original.base → block = original) :
    (replaceBlock blocks { original with bytes }).find?
        (fun block => block.live && block.base ≤ address &&
          address < block.base + block.size) =
      (blocks.find? (fun block => block.live && block.base ≤ address &&
          address < block.base + block.size)).map
        (fun block => if block.base == original.base then
          { original with bytes } else block) := by
  induction blocks with
  | nil => rfl
  | cons head tail ih =>
      have tailUnique : ∀ block ∈ tail,
          block.base = original.base → block = original := by
        intro block member same
        exact unique block (by simp [member]) same
      by_cases same : head.base = original.base
      · have eq := unique head (by simp) same
        subst head
        cases contains : original.live && decide (original.base ≤ address) &&
            decide (address < original.base + original.size) <;>
          simp [replaceBlock, List.find?, ih tailUnique, contains]
      · cases contains : head.live && decide (head.base ≤ address) &&
            decide (address < head.base + head.size) <;>
          simp [replaceBlock, same, List.find?, ih tailUnique, contains]

theorem Heap.containingBlock_replaceBytes
    {heap : Heap} (wellFormed : HeapWellFormed heap)
    (original : Block) (member : original ∈ heap.blocks)
    (bytes : List UInt8) (address : Nat) :
    ({ heap with blocks := replaceBlock heap.blocks { original with bytes } } :
      Heap).containingBlock? address =
      (heap.containingBlock? address).map
        (fun block => if block.base == original.base then
          { original with bytes } else block) := by
  apply findContaining_replaceBytes
  intro block blockMember same
  exact wellFormed.blockBasesUnique block blockMember original member same

theorem Heap.loadByte_after_store_same
    {heap after : Heap} {pointer offset : Nat} {byte : UInt8}
    (wellFormed : HeapWellFormed heap)
    (stored : heap.storeByte pointer offset byte = .ok after) :
    after.loadByte pointer offset = .ok byte := by
  cases found : heap.containingBlock? (pointer + offset) with
  | none =>
      simp only [Heap.storeByte, found] at stored
      split at stored <;> try contradiction
      split at stored <;> contradiction
  | some block =>
      have member := List.mem_of_find?_eq_some found
      have present := List.find?_some
        (p := fun candidate : Block => candidate.live &&
          candidate.base ≤ pointer + offset &&
          pointer + offset < candidate.base + candidate.size) found
      have bound : pointer + offset - block.base < block.bytes.length := by
        have shape := wellFormed.blocksWellFormed block member
        change (block.live && decide (block.base ≤ pointer + offset) &&
          decide (pointer + offset < block.base + block.size)) = true at present
        simp only [Bool.and_eq_true, decide_eq_true_eq] at present
        have lower : block.base ≤ pointer + offset := present.1.2
        have upper : pointer + offset < block.base + block.size := present.2
        rcases shape with ⟨_, _, size, _⟩
        rw [size]
        exact (Nat.sub_lt_iff_lt_add' lower).mpr upper
      simp only [Heap.storeByte, found, Except.ok.injEq] at stored
      subst after
      have foundAfter := Heap.containingBlock_replaceBytes wellFormed block
        member (setByte block.bytes (pointer + offset - block.base) byte)
        (pointer + offset)
      rw [found] at foundAfter
      simp only [Option.map_some, BEq.rfl, if_true] at foundAfter
      simp only [Heap.loadByte, foundAfter]
      rw [setByte_get_same block.bytes _ byte bound]

theorem Heap.containingBlock_bounds {heap : Heap} {address : Nat} {block : Block}
    (found : heap.containingBlock? address = some block) :
    block.base ≤ address ∧ address < block.base + block.size := by
  have present := List.find?_some
    (p := fun candidate : Block => candidate.live && candidate.base ≤ address &&
      address < candidate.base + candidate.size) found
  change (block.live && decide (block.base ≤ address) &&
    decide (address < block.base + block.size)) = true at present
  simp only [Bool.and_eq_true, decide_eq_true_eq] at present
  exact ⟨present.1.2, present.2⟩

/-- A byte store preserves every successful read at a different address.
This is the framing fact needed while synchronizing several raw views. -/
theorem Heap.loadByte_after_store_other
    {heap after : Heap} {pointer offset query queryOffset : Nat}
    {byte previous : UInt8}
    (wellFormed : HeapWellFormed heap)
    (stored : heap.storeByte pointer offset byte = .ok after)
    (loaded : heap.loadByte query queryOffset = .ok previous)
    (different : query + queryOffset ≠ pointer + offset) :
    after.loadByte query queryOffset = .ok previous := by
  cases found : heap.containingBlock? (pointer + offset) with
  | none =>
      simp only [Heap.storeByte, found] at stored
      split at stored <;> try contradiction
      split at stored <;> contradiction
  | some original =>
      have member := List.mem_of_find?_eq_some found
      cases queried : heap.containingBlock? (query + queryOffset) with
      | none =>
          simp only [Heap.loadByte, queried] at loaded
          split at loaded <;> try contradiction
          split at loaded <;> contradiction
      | some block =>
          have queryMember := List.mem_of_find?_eq_some queried
          simp only [Heap.storeByte, found, Except.ok.injEq] at stored
          subst after
          have foundAfter := Heap.containingBlock_replaceBytes wellFormed original
            member (setByte original.bytes (pointer + offset - original.base) byte)
            (query + queryOffset)
          rw [queried] at foundAfter
          by_cases same : block.base = original.base
          · have identical := wellFormed.blockBasesUnique block queryMember
              original member same
            subst block
            simp only [Option.map_some, BEq.rfl, if_true] at foundAfter
            simp only [Heap.loadByte, foundAfter]
            have otherOffset : query + queryOffset - original.base ≠
                pointer + offset - original.base := by
              have firstBounds := Heap.containingBlock_bounds
                (heap := heap) (address := pointer + offset) (block := original) found
              have queryBounds := Heap.containingBlock_bounds
                (heap := heap) (address := query + queryOffset) (block := original) queried
              intro equalOffsets
              apply different
              calc
                query + queryOffset = query + queryOffset - original.base +
                    original.base := (Nat.sub_add_cancel queryBounds.1).symm
                _ = pointer + offset - original.base + original.base :=
                    congrArg (· + original.base) equalOffsets
                _ = pointer + offset := Nat.sub_add_cancel firstBounds.1
            rw [setByte_get_other original.bytes _ _ byte otherOffset]
            simpa only [Heap.loadByte, queried] using loaded
          · simp only [Option.map_some, beq_iff_eq, same, if_false] at foundAfter
            rw [Heap.loadByte, foundAfter]
            rw [Heap.loadByte, queried] at loaded
            exact loaded

theorem storeBytesFrom_preserves_read_outside
    {heap after : Heap} {pointer offset query queryOffset : Nat}
    {bytes : List UInt8} {previous : UInt8}
    (wellFormed : HeapWellFormed heap)
    (stored : storeBytesFrom heap pointer offset bytes = .ok after)
    (loaded : heap.loadByte query queryOffset = .ok previous)
    (outside : query + queryOffset < pointer + offset ∨
      pointer + offset + bytes.length ≤ query + queryOffset) :
    after.loadByte query queryOffset = .ok previous := by
  induction bytes generalizing heap offset with
  | nil =>
      simp only [storeBytesFrom, Except.ok.injEq] at stored
      subst after
      exact loaded
  | cons byte rest ih =>
      cases first : heap.storeByte pointer offset byte with
      | error reason => simp [storeBytesFrom, first] at stored
      | ok middle =>
          have preserved := Heap.loadByte_after_store_other wellFormed first
            loaded (by simp only [List.length_cons] at outside; omega)
          have remaining : storeBytesFrom middle pointer (offset + 1) rest =
              .ok after := by simpa only [storeBytesFrom, first] using stored
          exact ih (Lanius.Properties.storeByte_preserves_heap_well_formed
            wellFormed first) remaining preserved
            (by simp only [List.length_cons] at outside; omega)

theorem storeBytesFrom_reads_written
    {heap after : Heap} {pointer offset index : Nat}
    {bytes : List UInt8} {byte : UInt8}
    (wellFormed : HeapWellFormed heap)
    (stored : storeBytesFrom heap pointer offset bytes = .ok after)
    (selected : bytes[index]? = some byte) :
    after.loadByte pointer (offset + index) = .ok byte := by
  induction bytes generalizing heap offset index with
  | nil => simp at selected
  | cons head tail ih =>
      cases first : heap.storeByte pointer offset head with
      | error reason => simp [storeBytesFrom, first] at stored
      | ok middle =>
          have middleWellFormed :=
            Lanius.Properties.storeByte_preserves_heap_well_formed wellFormed first
          have remaining : storeBytesFrom middle pointer (offset + 1) tail =
              .ok after := by simpa only [storeBytesFrom, first] using stored
          cases index with
          | zero =>
              simp only [List.getElem?_cons_zero, Option.some.injEq] at selected
              subst byte
              have loaded := Heap.loadByte_after_store_same wellFormed first
              simpa only [Nat.add_zero] using
                storeBytesFrom_preserves_read_outside middleWellFormed remaining
                  loaded (Or.inl (by omega))
          | succ index =>
              have chosen : tail[index]? = some byte := by simpa using selected
              simpa only [Nat.add_assoc, Nat.add_comm, Nat.add_left_comm] using
                ih middleWellFormed remaining chosen

theorem loadBytesFrom_of_reads
    {heap : Heap} {pointer offset : Nat} (bytes : List UInt8)
    (read : ∀ index byte, bytes[index]? = some byte →
      heap.loadByte pointer (offset + index) = .ok byte) :
    loadBytesFrom heap pointer offset bytes.length = .ok bytes := by
  induction bytes generalizing offset with
  | nil => rfl
  | cons head tail ih =>
      have first : heap.loadByte pointer offset = .ok head := by
        simpa using read 0 head rfl
      have rest : loadBytesFrom heap pointer (offset + 1) tail.length =
          .ok tail := by
        apply ih
        intro index byte chosen
        simpa only [Nat.add_assoc, Nat.add_comm, Nat.add_left_comm] using
          read (index + 1) byte (by simpa using chosen)
      simp [loadBytesFrom, first, rest]

/-- Whole-buffer read-after-write correctness for the authoritative heap.
Together with the non-overlap lemma this justifies packed-view synchronization,
not merely heap-shape preservation. -/
theorem Heap.loadBytes_after_store
    {heap after : Heap} {pointer : Nat} {bytes : List UInt8}
    (wellFormed : HeapWellFormed heap)
    (stored : heap.storeBytes pointer bytes = .ok after) :
    after.loadBytes pointer bytes.length = .ok bytes := by
  apply loadBytesFrom_of_reads
  intro index byte selected
  exact storeBytesFrom_reads_written wellFormed stored selected

/-- A disjoint byte write preserves an entire previously readable buffer. -/
theorem Heap.loadBytes_after_store_disjoint
    {heap after : Heap} {pointer query count : Nat} {written bytes : List UInt8}
    (wellFormed : HeapWellFormed heap)
    (stored : heap.storeBytes pointer written = .ok after)
    (loaded : heap.loadBytes query count = .ok bytes)
    (disjoint : query + count ≤ pointer ∨ pointer + written.length ≤ query) :
    after.loadBytes query count = .ok bytes := by
  have preserve : ∀ offset count bytes,
      loadBytesFrom heap query offset count = .ok bytes →
      (query + offset + count ≤ pointer ∨ pointer + written.length ≤ query + offset) →
      loadBytesFrom after query offset count = .ok bytes := by
    intro offset count
    induction count generalizing offset with
    | zero => intro bytes loaded _; simpa [loadBytesFrom] using loaded
    | succ count induction =>
        intro bytes loaded apart
        cases first : heap.loadByte query offset with
        | error reason => simp [loadBytesFrom, first] at loaded
        | ok byte =>
            cases rest : loadBytesFrom heap query (offset + 1) count with
            | error reason => simp [loadBytesFrom, first, rest] at loaded
            | ok tail =>
                have firstAfter := storeBytesFrom_preserves_read_outside wellFormed stored first
                  (by simp only [Nat.add_zero]; omega)
                have restAfter := induction (offset + 1) tail rest (by omega)
                simpa [loadBytesFrom, first, rest, firstAfter, restAfter] using loaded
  exact preserve 0 count bytes loaded (by simpa using disjoint)

end Lanius.Memory
