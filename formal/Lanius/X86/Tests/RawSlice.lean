import Lanius.X86.Storage.Heap.Allocate
import Lanius.X86.Storage.Heap.Store
import Lanius.X86.Storage.Slice.Raw
import Lanius.X86.Storage.Slice.Descriptor
import Lanius.X86.Storage.Slice.Allocate
import Lanius.X86.Lower.Slice.Raw
import Lanius.X86.Lower.Slice.Raw.Reject
import Lean.Elab.Term
import Lean.Util.CollectAxioms

namespace Lanius.X86.Tests.RawSlice

open Lanius.Core Lanius.Semantics Lanius.Properties

private def initialLocations : Storage.Locations where
  slice := fun _ _ _ => 0
  string := fun _ => 0
  pointer := fun pointer => if pointer = 0 then some 0 else none
  pointer_null := rfl
  pointer_eq_null := by
    intro pointer mapped
    split at mapped
    · assumption
    · contradiction

private theorem empty_related (memory : Machine.Memory) :
    Storage.Heap.Correspondence {} memory initialLocations := by
  refine ⟨Lanius.Properties.empty_heap_well_formed, ?_, ?_, ?_, ?_⟩
  · intro block member
    contradiction
  · intro block member
    contradiction
  · intro pointer native mapped nonnull
    simp [initialLocations, nonnull] at mapped
  · intro block member
    contradiction

-- Code, descriptor, and data deliberately occupy different native ranges.
-- The allocator effect below is a concrete memory contract, not an execution
-- proof for the operating system's allocator.
private def readCode := Machine.Index.bytes true 0 ++ Lower.Slice.loadBytes
private theorem readCode_length : readCode.length = 49 := by decide
private def fullCode := Storage.Slice.Descriptor.bytes 2 3 11 ++ readCode
private theorem fullCode_length : fullCode.length = 63 := by decide
private def initialMemory (address : Machine.Address) : UInt8 :=
  if 0x2ff2 ≤ address.toNat ∧ address.toNat < 0x2ff2 + fullCode.length then
    fullCode[address.toNat - 0x2ff2]!
  else if address = 0x4001 then 32 else 0

private theorem full_code_loaded : Machine.CodeAt initialMemory 0x2ff2 fullCode := by
  intro index inside
  have indexBound : index < 63 := by simpa only [fullCode_length] using inside
  have address : (0x2ff2 + BitVec.ofNat 64 index).toNat = 0x2ff2 + index := by
    simp [BitVec.toNat_add, BitVec.toNat_ofNat]
    omega
  simp only [initialMemory, address, Nat.le_add_right, true_and, Nat.add_lt_add_iff_left,
    if_pos inside, Nat.add_sub_cancel_left, getElem!_pos fullCode index inside]

private theorem code_loaded : Machine.CodeAt initialMemory 0x3000 readCode := full_code_loaded.suffix

private def allocation : Lanius.Memory.Heap := {
  blocks := [Storage.Heap.allocatedBlock 4 8 4], nextAddress := 12 }
private def signedBlock : Lanius.Memory.Block := {
  base := 4, size := 8, alignment := 4, bytes := [0, 0, 0, 0, 0, 0, 0, 128] }
private def signedHeap : Lanius.Memory.Heap := { allocation with blocks := [signedBlock] }
private def signedMemory := Storage.Heap.writeByte initialMemory 0x1007 128
private def before : State := { heap := signedHeap }
private def borrowedHeap : Lanius.Memory.Heap := {
  signedHeap with blocks := [{ signedBlock with owned := false }] }
private def mappedState : State := {
  heap := borrowedHeap
  cells := [{ id := 0, value := some (.array (signedI32Values [0, -2147483648])) }]
  nextCell := 1
  i32ArrayViews := [{ address := 4, root := 0, projections := [], length := 2 }] }

private theorem allocated : ({} : Lanius.Memory.Heap).allocate 8 4 = .allocated 4 allocation := by cbv
private theorem initialized : allocation.storeByte 4 7 128 = .ok signedHeap := by cbv
private theorem mapped : mapRawI32Slice before 4 2 =
    .done (.slice (.scalar (.signed .i32)) 0 [] 0 2) mappedState := by cbv

private theorem allocation_effect : Storage.Heap.AllocationEffect initialMemory initialMemory
    0x1000 8 4 { base := 0x1000, size := 8 } := by
  refine ⟨by decide, by decide, by decide, by decide, ?_, fun _ _ => rfl⟩
  intro offset inside
  have cases : offset = 0 ∨ offset = 1 ∨ offset = 2 ∨ offset = 3 ∨
      offset = 4 ∨ offset = 5 ∨ offset = 6 ∨ offset = 7 := by omega
  rcases cases with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl <;> cbv

/-- This fixture obtains the raw-slice bridge from an actual allocation and
byte store. In particular, packed i32 reads are not supplied as assumptions. -/
theorem allocated_and_mapped :
    ({} : Lanius.Memory.Heap).allocate 8 4 = .allocated 4 allocation ∧
    allocation.storeByte 4 7 128 = .ok signedHeap ∧
    ∃ locations, locations.pointer 4 = some 0x1000 ∧
      Storage.Slice.Raw.Constructed before mappedState 4 2
        signedMemory 0x1000 locations [0, -2147483648] := by
  refine ⟨allocated, initialized, ?_⟩
  obtain ⟨locations, allocatedRelated, pointer, _, _, _⟩ :=
    (empty_related initialMemory).allocate allocated (by decide) allocation_effect (by simp)
  obtain ⟨storedHeap, stored, _, _, _, related⟩ := allocatedRelated.store_byte
    (block := Storage.Heap.allocatedBlock 4 8 4) (by simp [allocation]) pointer
    (start := 0) (offset := 7) (by decide) 128
  have heapEq : signedHeap = storedHeap := Except.ok.inj (initialized.symm.trans stored)
  subst storedHeap
  have correspondence : Storage.Heap.Correspondence signedHeap signedMemory locations := by
    simpa [signedMemory, Storage.Heap.allocatedBlock] using related
  have wellFormed : StateWellFormed before := by
    refine ⟨correspondence.wellFormed, ?_, ?_, ?_⟩ <;>
      simp [before, CellIdsUnique, CellIdsBelowNext, LocalsReferenceCells]
  obtain ⟨after, values, constructed⟩ := Storage.Slice.Raw.map (count := 2) wellFormed correspondence
    (block := signedBlock) (by cbv) pointer (by decide) (by decide)
  have afterEq : mappedState = after := by
    have run := constructed.run
    change mapRawI32Slice before 4 2 =
      .done (.slice (.scalar (.signed .i32)) 0 [] 0 2) after at run
    rw [mapped] at run
    cases run
    rfl
  subst after
  have arrays : signedI32Values [0, -2147483648] = signedI32Values values :=
    Value.array.inj (Except.ok.inj constructed.read)
  have valuesEq : [0, -2147483648] = values :=
    (List.map_inj_right (fun _ _ equal => (Value.signed.inj equal).2)).mp arrays
  subst values
  exact ⟨locations, pointer, constructed⟩

-- Raw construction requires the entire exact block, not just a readable
-- prefix. Negative lengths are rejected before any ownership change.
example : mapRawI32Slice before 4 (-1) = .trapped .rawMemoryBounds before := by cbv
example : mapRawI32Slice before 4 1 = .trapped .rawMemoryBounds before := by cbv
example : mapRawI32Slice before 4 3 = .trapped .rawMemoryBounds before := by cbv

private def widerAligned : State := { heap := {
  blocks := [Storage.Heap.allocatedBlock 8 8 8], nextAddress := 16 } }
example : mapRawI32Slice widerAligned 8 2 = .trapped .rawMemoryBounds widerAligned := by cbv
example : mappedState.heap.deallocate 4 8 4 = .error .allocatorContract := by cbv
example : mappedState.heap.reallocate 4 8 0 4 = .trapped .allocatorContract mappedState.heap := by cbv

-- Duplicate-view snapshots: a second raw mapping preserves the old cell
-- and current heap bytes. This does not establish future alias coherence.
private def aliasState : State := { mappedState with
  cells := mappedState.cells ++ [{ id := 1, value := some (.array (signedI32Values [0, -2147483648])) }]
  nextCell := 2
  i32ArrayViews := mappedState.i32ArrayViews ++ [{ address := 4, root := 1, projections := [], length := 2 }] }

theorem mapping_retains_snapshot :
    ∃ after values locations,
      Storage.Slice.Raw.Constructed mappedState after 4 2 signedMemory 0x1000 locations values ∧
      after.cellEntry? 0 = mappedState.cellEntry? 0 ∧
      after.heap.loadByte 4 7 = .ok 128 := by
  obtain ⟨locations, pointer, first⟩ := allocated_and_mapped.2.2
  obtain ⟨after, values, second⟩ := Storage.Slice.Raw.map (count := 2) first.wellFormed first.correspondence
    (block := { signedBlock with owned := false }) (by cbv)
    pointer (by decide) (by decide)
  refine ⟨after, values, locations, second, second.oldCells 0 (by decide), ?_⟩
  have known : mapRawI32Slice mappedState 4 2 =
      .done (.slice (.scalar (.signed .i32)) 1 [] 0 2) aliasState := by cbv
  have afterEq : aliasState = after := by
    have run := second.run
    change mapRawI32Slice mappedState 4 2 =
      .done (.slice (.scalar (.signed .i32)) 1 [] 0 2) after at run
    rw [known] at run
    cases run
    rfl
  rw [← afterEq]
  cbv

private def emptyAllocation : Lanius.Memory.Heap := {
  blocks := [Storage.Heap.allocatedBlock 4 0 4], nextAddress := 5 }
private def emptyBefore : State := { heap := emptyAllocation }
private def emptyAfter : State := {
  heap := { emptyAllocation with blocks := [{ Storage.Heap.allocatedBlock 4 0 4 with owned := false }] }
  cells := [{ id := 0, value := some (.array []) }]
  nextCell := 1
  i32ArrayViews := [{ address := 4, root := 0, projections := [], length := 0 }] }

/-- A zero-length allocation has a mapped nonnull identity but no readable
element. Its real raw constructor still creates a valid empty slice. -/
theorem empty_allocated_and_mapped :
    ({} : Lanius.Memory.Heap).allocate 0 4 = .allocated 4 emptyAllocation ∧
    ∃ locations, locations.pointer 4 = some 0x1000 ∧
      Storage.Slice.Raw.Constructed emptyBefore emptyAfter 4 0 initialMemory 0x1000 locations [] ∧
      emptyAfter.heap.loadByte 4 0 = .error .rawMemoryBounds := by
  have allocationRun : ({} : Lanius.Memory.Heap).allocate 0 4 = .allocated 4 emptyAllocation := by cbv
  refine ⟨allocationRun, ?_⟩
  have effect : Storage.Heap.AllocationEffect initialMemory initialMemory
      0x1000 0 4 { base := 0x1000, size := 1 } :=
    ⟨by decide, by decide, by decide, by decide, by omega, fun _ _ => rfl⟩
  obtain ⟨locations, after, values, constructed, _, _, _, _⟩ :=
    Storage.Slice.Allocate.construct (count := 0) empty_state_well_formed
      (empty_related initialMemory) allocationRun (by decide) effect (by simp)
  have known : mapRawI32Slice emptyBefore 4 0 =
      .done (.slice (.scalar (.signed .i32)) 0 [] 0 0) emptyAfter := by cbv
  have afterEq : emptyAfter = after := by
    have run := constructed.run
    change mapRawI32Slice emptyBefore 4 0 =
      .done (.slice (.scalar (.signed .i32)) 0 [] 0 0) after at run
    rw [known] at run
    cases run
    rfl
  subst after
  have valuesEq := List.eq_nil_of_length_eq_zero constructed.length
  subst values
  exact ⟨locations, constructed.pointer, constructed, by cbv⟩

private def descriptorMemory := Storage.Slice.Descriptor.written signedMemory 0x2000 0x1000 2

private theorem signed_code : Machine.CodeAt signedMemory 0x3000 readCode := by
  intro index inside
  have indexBound : index < 49 := by simpa only [readCode_length] using inside
  change (if 0x3000 + BitVec.ofNat 64 index = 0x1007 then 128
    else initialMemory (0x3000 + BitVec.ofNat 64 index)) = _
  rw [if_neg]
  · exact code_loaded index inside
  · intro equal
    have numbers := congrArg BitVec.toNat equal
    simp [BitVec.toNat_add, BitVec.toNat_ofNat] at numbers
    omega

private theorem signed_full_code : Machine.CodeAt signedMemory 0x2ff2 fullCode := by
  intro index inside
  have indexBound : index < 63 := by simpa only [fullCode_length] using inside
  change (if 0x2ff2 + BitVec.ofNat 64 index = 0x1007 then 128
    else initialMemory (0x2ff2 + BitVec.ofNat 64 index)) = _
  rw [if_neg]
  · exact full_code_loaded index inside
  · intro equal
    have numbers := congrArg BitVec.toNat equal
    simp [BitVec.toNat_add, BitVec.toNat_ofNat] at numbers
    omega

private theorem descriptor_code : Machine.CodeAt descriptorMemory 0x3000 readCode := by
  intro index inside
  have indexBound : index < 49 := by simpa only [readCode_length] using inside
  unfold descriptorMemory
  rw [Storage.Slice.Descriptor.written_frame]
  · exact signed_code index inside
  · intro lane equal
    have laneBound := lane.isLt
    have numbers := congrArg BitVec.toNat equal
    simp [BitVec.toNat_add, BitVec.toNat_ofNat] at numbers
    omega

private def layout : Frame.Layout := {
  base := 0x4008, slots := 1, belowBase := by decide, addressBound := by decide }
private def slot : Fin layout.slots := ⟨0, by decide⟩
private def native : Machine.State := {
  registers := fun register => if register = 0 then 1 else if register = 2 then 0x1000
    else if register = 3 then 2 else if register = 5 then 0x4008 else if register = 11 then 0x2000 else 0
  rip := 0x2ff2
  memory := signedMemory
  flags := 0x202 }

/-- Allocation, byte initialization, Core raw construction, separate native
descriptor stores, and the decoded bounds/address/load sequence are connected
here. The signed result is checked against an independent Core execution. -/
theorem allocated_descriptor_read :
    ∃ after, Machine.Steps 10 native after ∧
      Evaluates {} before
        (.index (Lower.Slice.Raw.expression 4 2) (.value (.signed .i32 1)))
        (.signed .i32 (-2147483648)) mappedState ∧
      ((after.registers 0).setWidth 32).toInt = -2147483648 ∧
      after.memory = descriptorMemory := by
  obtain ⟨locations, pointer, constructed⟩ := allocated_and_mapped.2.2
  have separate : ∀ block ∈ mappedState.heap.blocks, ∀ base,
      locations.pointer block.base = some base → ∀ offset, offset < block.size →
      Storage.Slice.Descriptor.Outside 0x2000 (base + BitVec.ofNat 64 offset) := by
    intro block member base mapped offset inside
    have sameBlock : block = { signedBlock with owned := false } := by
      simpa [mappedState, borrowedHeap, signedHeap, allocation] using member
    subst block
    have sameBase : 0x1000 = base := Option.some.inj (pointer.symm.trans mapped)
    subst base
    intro lane equal
    have offsetBound : offset < 8 := inside
    have laneBound := lane.isLt
    have numbers := congrArg BitVec.toNat equal
    simp [BitVec.toNat_add, BitVec.toNat_ofNat] at numbers
    omega
  have known : Evaluates {} before
      (.index (Lower.Slice.Raw.expression 4 2) (.value (.signed .i32 1)))
      (.signed .i32 (-2147483648)) mappedState := ⟨4, by cbv⟩
  obtain ⟨after, steps, evaluated, memory⟩ := Lower.Slice.Raw.read_initialized
    (native := native) constructed {} (.signed 1) 1 (by decide) (by cbv) rfl
    layout slot (by decide) rfl 2 3 11 rfl rfl (by decide) (by cbv)
    (by
      intro savedLane descriptorLane equal
      have savedBound := savedLane.isLt
      have descriptorBound := descriptorLane.isLt
      have numbers := congrArg BitVec.toNat equal
      simp [native, layout, slot, Frame.Layout.address, Frame.Layout.offset,
        BitVec.toNat_add, BitVec.toNat_ofNat] at numbers
      omega)
    signed_full_code
    (by
      intro index inside lane equal
      have indexBound : index < 63 := inside
      have laneBound := lane.isLt
      have numbers := congrArg BitVec.toNat equal
      simp [native, BitVec.toNat_add, BitVec.toNat_ofNat] at numbers
      omega)
    separate
  have result := (Lanius.Fuel.evaluates_deterministic evaluated known).1
  exact ⟨after, steps, known, (Value.signed.inj result).2, memory⟩

example : Machine.read64 descriptorMemory 0x2000 = 0x1000 ∧
    Machine.read64 descriptorMemory 0x2008 = 2 :=
  Storage.Slice.Descriptor.written_words _ _ _ _

theorem descriptor_represents :
    ∃ locations, Storage.Represents locations descriptorMemory 0x2000
      (.slice (.scalar (.signed .i32)) 0 [] 0 2) ∧
      locations.pointer 4 = some 0x1000 ∧
      Storage.Slice.Represents descriptorMemory 0x1000 [0, -2147483648] := by
  obtain ⟨locations, pointer, constructed⟩ := allocated_and_mapped.2.2
  refine ⟨Storage.Slice.Descriptor.install locations 0 [] 0 0x1000,
    Storage.Slice.Descriptor.written_represents _ _ _ _ _ _ _ _ (by decide), pointer, ?_⟩
  apply Storage.Slice.Descriptor.written_backing constructed.packed
  intro index inside lane header
  have indexBound : index < 2 := inside
  have laneBound := lane.isLt
  have headerBound := header.isLt
  intro equal
  have numbers := congrArg BitVec.toNat equal
  simp [Storage.Slice.address, BitVec.toNat_add, BitVec.toNat_ofNat] at numbers
  omega

-- The machine stores do not reject overlap. This intentionally invalid
-- placement overwrites the sign-bit element with the descriptor's pointer.
example : Machine.read32 (Storage.Slice.Descriptor.written signedMemory 0x1004 0x1000 2)
    0x1004 = 0x1000 := by cbv

theorem overlapping_descriptor_corrupts_backing :
    ¬ Storage.Slice.Represents (Storage.Slice.Descriptor.written signedMemory 0x1004 0x1000 2)
      0x1000 [0, -2147483648] := by
  intro represented
  have second := represented.elements 1 (by decide)
  have numbers := congrArg BitVec.toNat second
  change 4096 = 2147483648 at numbers
  contradiction

private def mutationBefore : State := { mappedState with locals := [(7, 0)] }
private def mutationAfter : State := { mutationBefore with
  cells := [{ id := 0, value := some (.array (signedI32Values [0, 17])) }] }
private def mutationIndex : Expr :=
  .matchValue (.assign .set (.index (.local 7) (.value (.signed .i32 1)))
    (.value (.signed .i32 17))) [(.wildcard, .value (.signed .i32 1))]
private def mutationNative : Machine.State := {
  registers := fun register => if register = 0 then 0x1004 else 0
  rip := 0x302b
  memory := Machine.write32 signedMemory 0x1004 17
  flags := 0x202 }

/-- The index expression actually updates the shared Core array before it
returns its index. The final decoded MOV must use that post-effect backing,
not the sign-bit value captured when evaluating the slice descriptor. This
tests the read continuation, not code generation for the mutation itself. -/
theorem reads_mutated_backing :
    Evaluates {} mutationBefore
      (.index (.value (.slice (.scalar (.signed .i32)) 0 [] 0 2)) mutationIndex)
      (.signed .i32 17) mutationAfter ∧
    Machine.Step mutationNative (mutationNative.load32 0 0 0 Lower.Slice.loadBytes.length) ∧
    (((mutationNative.load32 0 0 0 Lower.Slice.loadBytes.length).registers 0).setWidth 32).toInt = 17 := by
  obtain ⟨_, _, constructed⟩ := allocated_and_mapped.2.2
  have packed : Storage.Slice.Represents mutationNative.memory 0x1000 [0, 17] := by
    simpa [mutationNative, Storage.Slice.address] using constructed.packed.store 1 (by decide) 17 (by decide)
  have loaded : Machine.CodeAt mutationNative.memory mutationNative.rip Lower.Slice.loadBytes := by
    apply Machine.CodeAt.write32
      (show Machine.CodeAt signedMemory 0x302b Lower.Slice.loadBytes from signed_code.suffix)
    intro index inside lane equal
    have indexBound : index < 6 := inside
    have laneBound := lane.isLt
    have numbers := congrArg BitVec.toNat equal
    simp [BitVec.toNat_add, BitVec.toNat_ofNat] at numbers
    omega
  have result := Lower.Slice.index_refines {} mutationBefore mutationBefore mutationAfter
    (.value (.slice (.scalar (.signed .i32)) 0 [] 0 2)) mutationIndex 0 [] [0, 17] 0 2 1
    (.signed .i32 1) (by decide) (by decide) ⟨1, rfl⟩ ⟨6, by cbv⟩ (by cbv) (by cbv)
    mutationNative 0x1000 packed rfl loaded
  have observed : (((mutationNative.load32 0 0 0 Lower.Slice.loadBytes.length).registers 0).setWidth 32).toInt = 17 := by cbv
  exact ⟨observed ▸ result.1, result.2.1, observed⟩

example : readCellProjection mutationBefore 0 [] =
    .ok (.array (signedI32Values [0, -2147483648])) ∧
    readCellProjection mutationAfter 0 [] = .ok (.array (signedI32Values [0, 17])) := by cbv

run_elab do
  let standard := [``propext, ``Classical.choice, ``Quot.sound]
  for name in [``Storage.Heap.Correspondence.protect_success,
      ``Storage.Heap.Correspondence.protect_exact, ``Storage.Heap.borrowed_deallocate,
      ``Storage.Heap.borrowed_reallocate, ``Storage.Heap.Array.bytes_window,
      ``Storage.Heap.Array.values_signed, ``Storage.Heap.Array.values_get,
      ``Storage.Heap.Array.decode_values, ``Storage.Heap.Correspondence.load_bytes_from,
      ``Storage.Heap.Correspondence.load_bytes, ``Storage.Heap.Correspondence.array,
      ``Storage.Heap.Correspondence.array_exists, ``Storage.Slice.Raw.map,
      ``Storage.Slice.Allocate.construct,
      ``Storage.Slice.Raw.map_signed, ``Storage.Slice.Raw.rejects_negative,
      ``Storage.Slice.Raw.Constructed.frameMemory, ``Storage.Slice.Descriptor.install_other,
      ``Storage.Slice.Descriptor.install_pointer, ``Storage.Slice.Descriptor.written_words,
      ``Storage.Slice.Descriptor.written_represents, ``Storage.Slice.Descriptor.written_frame,
      ``Storage.Slice.Descriptor.written_backing, ``Storage.Slice.Descriptor.written_heap,
      ``Storage.Slice.Descriptor.run_fields, ``Storage.Slice.Descriptor.steps,
      ``Storage.Slice.Descriptor.constructs, ``Storage.Slice.Descriptor.preserves_caller,
      ``Lower.Slice.Raw.Descriptor.describe, ``Lower.Slice.Raw.Descriptor.initializes,
      ``Lower.Slice.Raw.expression_evaluates, ``Lower.Slice.Raw.read_constructed,
      ``Lower.Slice.Raw.read_initialized,
      ``Lower.Slice.Raw.reject_constructed, ``Lower.Slice.Raw.reject_initialized,
      ``allocated_and_mapped, ``mapping_retains_snapshot,
      ``empty_allocated_and_mapped, ``allocated_descriptor_read, ``descriptor_represents,
      ``overlapping_descriptor_corrupts_backing, ``reads_mutated_backing] do
    for assumption in ← Lean.collectAxioms name do
      unless standard.contains assumption do
        throwError "raw-slice theorem {name} adds unexpected axiom {assumption}"
  Lean.logInfo "Kernel-only raw-slice checks: actual allocation/store/map, signed packed backing, pointer-length descriptor and decoded indexed read, empty allocation, exact size/alignment/negative-length rejection, duplicate-view snapshots, descriptor overlap corruption, and post-index mutation; standard axioms only"

end Lanius.X86.Tests.RawSlice
