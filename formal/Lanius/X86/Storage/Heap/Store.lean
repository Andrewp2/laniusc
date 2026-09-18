import Lanius.X86.Storage.Heap
import Lanius.Memory.Store

namespace Lanius.X86.Storage.Heap

/-- A native byte-memory update, not an assumed machine instruction. -/
def writeByte (memory : Machine.Memory) (address : Machine.Address) (byte : UInt8) : Machine.Memory :=
  fun candidate => if candidate = address then byte else memory candidate

theorem BlockRep.frame (represented : BlockRep block before base)
    (same : ∀ offset, offset < block.size →
      after (base + BitVec.ofNat 64 offset) = before (base + BitVec.ofNat 64 offset)) :
    BlockRep block after base := by
  refine ⟨represented.live, represented.logicalBound, represented.nativeBound, represented.aligned, ?_⟩
  intro offset inside
  rw [same offset inside]
  exact represented.bytes offset inside

theorem BlockRep.store (represented : BlockRep block memory base)
    (length : block.bytes.length = block.size) (inside : offset < block.size) (byte : UInt8) :
    BlockRep { block with bytes := Lanius.Memory.setByte block.bytes offset byte }
      (writeByte memory (base + BitVec.ofNat 64 offset) byte) base := by
  refine ⟨represented.live, represented.logicalBound, represented.nativeBound, represented.aligned, ?_⟩
  intro index within
  change (Lanius.Memory.setByte block.bytes offset byte)[index]? = _
  change index < block.size at within
  by_cases same : index = offset
  · subst index
    rw [Lanius.Memory.setByte_get_same block.bytes offset byte (by omega)]
    simp [writeByte]
  · rw [Lanius.Memory.setByte_get_other block.bytes offset index byte same, represented.bytes index within]
    have bounds := represented.nativeBound
    have different := Machine.offset_ne base index offset (by omega) (by omega) same
    simp [writeByte, different]

private theorem replace_map (blocks : List Lanius.Memory.Block) (replacement : Lanius.Memory.Block) :
    Lanius.Memory.replaceBlock blocks replacement =
      blocks.map (fun block => if block.base == replacement.base then replacement else block) := by
  induction blocks with
  | nil => rfl
  | cons head tail ih => simp only [Lanius.Memory.replaceBlock, List.map_cons, ih]

private theorem replaced_member {blocks : List Lanius.Memory.Block}
    {original replacement : Lanius.Memory.Block}
    (member : original ∈ blocks) (same : original.base = replacement.base) :
    replacement ∈ Lanius.Memory.replaceBlock blocks replacement := by
  rw [replace_map]
  apply List.mem_map.mpr
  exact ⟨original, member, by simp [same]⟩

private theorem unchanged_member {blocks : List Lanius.Memory.Block}
    {original replacement : Lanius.Memory.Block}
    (member : original ∈ blocks) (different : original.base ≠ replacement.base) :
    original ∈ Lanius.Memory.replaceBlock blocks replacement := by
  rw [replace_map]
  apply List.mem_map.mpr
  exact ⟨original, member, by simp [different]⟩

private theorem changed_or_original {blocks : List Lanius.Memory.Block}
    {current replacement : Lanius.Memory.Block}
    (member : current ∈ Lanius.Memory.replaceBlock blocks replacement) :
    current = replacement ∨ current ∈ blocks ∧ current.base ≠ replacement.base := by
  rw [replace_map] at member
  obtain ⟨original, present, same⟩ := List.mem_map.mp member
  by_cases hit : original.base = replacement.base
  · exact Or.inl (by simpa [hit] using same.symm)
  · have equal : original = current := by simpa [hit] using same
    rw [← equal]
    exact Or.inr ⟨present, hit⟩

private theorem original_metadata {heap : Lanius.Memory.Heap}
    {current changed : Lanius.Memory.Block} {bytes : List UInt8}
    (member : current ∈ Lanius.Memory.replaceBlock heap.blocks
      { changed with bytes := bytes }) (changedMember : changed ∈ heap.blocks) :
    ∃ original, original ∈ heap.blocks ∧ current.base = original.base ∧ current.size = original.size := by
  rcases changed_or_original member with same | ⟨present, _⟩
  · subst current
    exact ⟨changed, changedMember, rfl, rfl⟩
  · exact ⟨current, present, rfl, rfl⟩

/-- Distinct mapped allocations cannot alias even at the individual byte
updated by a raw store. The proof uses the represented native extents. -/
theorem Correspondence.byte_disjoint (related : Correspondence heap memory locations)
    (leftMember : left ∈ heap.blocks) (leftMapped : locations.pointer left.base = some leftBase)
    (rightMember : right ∈ heap.blocks) (rightMapped : locations.pointer right.base = some rightBase)
    (different : left.base ≠ right.base) (leftInside : leftOffset < left.size)
    (rightInside : rightOffset < right.size) :
    leftBase + BitVec.ofNat 64 leftOffset ≠ rightBase + BitVec.ofNat 64 rightOffset := by
  intro equal
  have numbers := congrArg BitVec.toNat equal
  have leftRep := related.mappedBlock left leftMember leftBase leftMapped
  have rightRep := related.mappedBlock right rightMember rightBase rightMapped
  rw [leftRep.address_toNat (by omega), rightRep.address_toNat (by omega)] at numbers
  have disjoint := related.disjoint left leftMember leftBase leftMapped right rightMember rightBase rightMapped different
  rcases disjoint with first | second <;> omega

/-- Execute Core's actual within-block byte store and preserve the complete
partial heap correspondence under a matching native byte update. The map,
allocation identities, extents, liveness and ownership are unchanged. This
does not assert an execution of any not-yet-modeled store-byte instruction. -/
theorem Correspondence.store_byte (related : Correspondence heap memory locations)
    (member : block ∈ heap.blocks) (mapped : locations.pointer block.base = some base)
    (inside : start + offset < block.size) (byte : UInt8) :
    ∃ after, heap.storeByte (block.base + start) offset byte = .ok after ∧
      after.blocks = Lanius.Memory.replaceBlock heap.blocks
        { block with bytes := Lanius.Memory.setByte block.bytes (start + offset) byte } ∧
      after.nextAddress = heap.nextAddress ∧ after.remaining = heap.remaining ∧
      Correspondence after (writeByte memory (base + BitVec.ofNat 64 (start + offset)) byte) locations := by
  let updated : Lanius.Memory.Block :=
    { block with bytes := Lanius.Memory.setByte block.bytes (start + offset) byte }
  let after : Lanius.Memory.Heap := { heap with blocks := Lanius.Memory.replaceBlock heap.blocks updated }
  let native := writeByte memory (base + BitVec.ofNat 64 (start + offset)) byte
  have represented := related.mappedBlock block member base mapped
  have selected := containing_block related.wellFormed member represented.live inside
  have stored : heap.storeByte (block.base + start) offset byte = .ok after := by
    simp only [Lanius.Memory.Heap.storeByte, Nat.add_assoc, selected, Nat.add_sub_cancel_left]
    rfl
  have updatedRep : BlockRep updated native base :=
    represented.store (related.wellFormed.blocksWellFormed block member).2.2.1 inside byte
  refine ⟨after, stored, rfl, rfl, rfl, ?_⟩
  refine ⟨Lanius.Properties.storeByte_preserves_heap_well_formed related.wellFormed stored, ?_, ?_, ?_, ?_⟩
  · intro candidate candidateMember candidateBase candidateMapped
    rcases changed_or_original candidateMember with same | ⟨oldMember, different⟩
    · subst candidate
      have sameBase : base = candidateBase := Option.some.inj (mapped.symm.trans candidateMapped)
      subst candidateBase
      exact updatedRep
    · apply (related.mappedBlock candidate oldMember candidateBase candidateMapped).frame
      intro query queryInside
      have separate := related.byte_disjoint oldMember candidateMapped member mapped different queryInside inside
      exact if_neg separate
  · intro candidate candidateMember candidateBase candidateMapped query queryInside
    obtain ⟨original, oldMember, sameBase, sameSize⟩ := original_metadata candidateMember member
    rw [sameBase] at candidateMapped ⊢
    rw [sameSize] at queryInside
    exact related.offsets original oldMember candidateBase candidateMapped query queryInside
  · intro pointer target pointerMapped notNull
    obtain ⟨original, originalBase, query, oldMember, oldMap, queryInside, pointerValue, targetValue⟩ :=
      related.covered pointer target pointerMapped notNull
    by_cases same : original.base = block.base
    · have sameBlock := related.wellFormed.blockBasesUnique original oldMember block member same
      subst original
      exact ⟨updated, originalBase, query, replaced_member member rfl, oldMap, queryInside, pointerValue, targetValue⟩
    · exact ⟨original, originalBase, query, unchanged_member oldMember same, oldMap, queryInside, pointerValue, targetValue⟩
  · intro left leftMember leftBase leftMapped right rightMember rightBase rightMapped different
    obtain ⟨oldLeft, oldLeftMember, leftIdentity, leftSize⟩ := original_metadata leftMember member
    obtain ⟨oldRight, oldRightMember, rightIdentity, rightSize⟩ := original_metadata rightMember member
    rw [leftIdentity] at leftMapped
    rw [rightIdentity] at rightMapped
    rw [leftIdentity, rightIdentity] at different
    rw [leftSize, rightSize]
    exact related.disjoint oldLeft oldLeftMember leftBase leftMapped oldRight oldRightMember rightBase rightMapped different

/-- Sequential native byte updates, in the same order as Core's bulk store. -/
def writeBytes (memory : Machine.Memory) (address : Machine.Address) : List UInt8 → Machine.Memory
  | [] => memory
  | byte :: rest => writeBytes (writeByte memory address byte) (address + 1) rest

/-- Core's four storage bytes give exactly the memory effect used by MOV32,
including negative values and addresses at the machine-width wrap boundary. -/
theorem writeBytes_i32 (memory : Machine.Memory) (address : Machine.Address) (value : Int) :
    writeBytes memory address (Lanius.Semantics.i32Bytes value) =
      Machine.write32 memory address (BitVec.ofInt 32 value) := by
  rw [← wordBytes_core]
  funext candidate
  simp only [WordBytes.toBytes, writeBytes, writeByte, Machine.write32, BitVec.add_assoc]
  by_cases low : candidate = address
  · subst candidate; simp
  by_cases second : candidate = address + 1
  · subst candidate; simp_all [BitVec.add_right_inj]
  by_cases third : candidate = address + 2
  · subst candidate; simp_all [BitVec.add_right_inj]
  simp_all

private theorem Correspondence.store_bytes_from (related : Correspondence heap memory locations)
    (member : block ∈ heap.blocks) (mapped : locations.pointer block.base = some base)
    (inside : start + offset + bytes.length ≤ block.size) :
    ∃ after, Lanius.Memory.storeBytesFrom heap (block.base + start) offset bytes = .ok after ∧
      after.nextAddress = heap.nextAddress ∧ after.remaining = heap.remaining ∧
      Correspondence after (writeBytes memory (base + BitVec.ofNat 64 (start + offset)) bytes) locations := by
  induction bytes generalizing heap memory block offset with
  | nil => exact ⟨heap, rfl, rfl, rfl, related⟩
  | cons byte bytes ih =>
    have room : start + offset < block.size := by simp only [List.length_cons] at inside; omega
    obtain ⟨next, stored, blocks, frontier, budget, nextRelated⟩ := related.store_byte member mapped room byte
    let updated : Lanius.Memory.Block :=
      { block with bytes := Lanius.Memory.setByte block.bytes (start + offset) byte }
    have nextMember : updated ∈ next.blocks := by
      rw [blocks]
      exact replaced_member member rfl
    obtain ⟨after, finished, nextFrontier, nextBudget, afterRelated⟩ :=
      ih nextRelated nextMember mapped (offset := offset + 1)
        (by simp only [List.length_cons] at inside; exact (by omega : start + (offset + 1) + bytes.length ≤ block.size))
    refine ⟨after, ?_, nextFrontier.trans frontier, nextBudget.trans budget, ?_⟩
    · simpa only [Lanius.Memory.storeBytesFrom, stored] using finished
    · simpa only [writeBytes, Nat.add_assoc, BitVec.ofNat_add, BitVec.add_assoc,
        BitVec.ofNat_eq_ofNat] using afterRelated

/-- Execute the actual Core bulk store within one represented allocation.
The pointer map and complete heap correspondence survive, including other
allocations; no successful-store or per-byte native-read premise is required. -/
theorem Correspondence.store_bytes (related : Correspondence heap memory locations)
    (member : block ∈ heap.blocks) (mapped : locations.pointer block.base = some base)
    (inside : start + bytes.length ≤ block.size) :
    ∃ after, heap.storeBytes (block.base + start) bytes = .ok after ∧
      after.nextAddress = heap.nextAddress ∧ after.remaining = heap.remaining ∧
      Correspondence after (writeBytes memory (base + BitVec.ofNat 64 start) bytes) locations := by
  simpa only [Lanius.Memory.Heap.storeBytes, Nat.add_zero] using
    related.store_bytes_from member mapped (offset := 0) (by simpa using inside)

/-- A successful Core i32 store and matching native word store preserve the
same pointer map and full heap relation. Success follows from the live block
and bounds, rather than being assumed. -/
theorem Correspondence.store_i32 (related : Correspondence heap memory locations)
    (member : block ∈ heap.blocks) (mapped : locations.pointer block.base = some base)
    (inside : start + 4 ≤ block.size) (value : Int) :
    ∃ after, heap.storeBytes (block.base + start) (Lanius.Semantics.i32Bytes value) = .ok after ∧
      after.nextAddress = heap.nextAddress ∧ after.remaining = heap.remaining ∧
      Correspondence after (Machine.write32 memory (base + BitVec.ofNat 64 start)
        (BitVec.ofInt 32 value)) locations := by
  simpa only [writeBytes_i32] using related.store_bytes member mapped
    (bytes := Lanius.Semantics.i32Bytes value) (by simpa [Lanius.Semantics.i32Bytes] using inside)

/-- Decode the backend's actual disp32 MOV bytes and relate its native store
to Core's bulk write. Register preparation and code loading remain explicit;
the theorem derives both executions and the resulting heap relation. -/
theorem Correspondence.store_i32_step (related : Correspondence heap before.memory locations)
    (member : block ∈ heap.blocks) (mapped : locations.pointer block.base = some base)
    (inside : start + 4 ≤ block.size) (source register : Machine.Register) (displacement value : Int)
    (address : before.registers register + (BitVec.ofInt 32 displacement).signExtend 64 =
      base + BitVec.ofNat 64 start)
    (operand : (before.registers source).setWidth 32 = BitVec.ofInt 32 value)
    (loaded : Machine.CodeAt before.memory before.rip
      (Machine.memoryBytes .w32 false source register displacement)) :
    let native := before.store32 source register (BitVec.ofInt 32 displacement)
      (Machine.memoryBytes .w32 false source register displacement).length
    ∃ after, heap.storeBytes (block.base + start) (Lanius.Semantics.i32Bytes value) = .ok after ∧
      Machine.Step before native ∧ Correspondence after native.memory locations ∧
      after.nextAddress = heap.nextAddress ∧ after.remaining = heap.remaining := by
  obtain ⟨after, stored, frontier, budget, afterRelated⟩ := related.store_i32 member mapped inside value
  refine ⟨after, stored, .decoded _ loaded (.store32 source register (BitVec.ofInt 32 displacement)) _ ?_ rfl,
    ?_, frontier, budget⟩
  · simpa [Machine.memoryInstruction] using Machine.memory_decodes .w32 false source register displacement []
  · simpa only [Machine.State.store32, address, operand] using afterRelated

end Lanius.X86.Storage.Heap
