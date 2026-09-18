import Lanius.X86.Storage.Slice
import Lanius.X86.Storage.Heap.Store
import Lanius.X86.Frame.Word

namespace Lanius.X86.Storage.Slice.Descriptor

open Lanius.Core Machine

/-- Install the backing pointer of one Core slice view. The raw-pointer map
and every other view are unchanged; the descriptor's address is not a map entry. -/
def install (locations : Locations) (root : CellId) (path : List ValueProjection)
    (start : Nat) (data : Machine.Address) : Locations :=
  { locations with slice := fun cell projections origin =>
      if cell = root ∧ projections = path ∧ origin = start then data
      else locations.slice cell projections origin }

@[simp] theorem install_slice (locations : Locations) (root : CellId)
    (path : List ValueProjection) (start : Nat) (data : Machine.Address) :
    (install locations root path start data).slice root path start = data := by
  simp [install]

theorem install_other (locations : Locations) (root cell : CellId)
    (path projections : List ValueProjection) (start origin : Nat) (data : Machine.Address)
    (different : ¬ (cell = root ∧ projections = path ∧ origin = start)) :
    (install locations root path start data).slice cell projections origin =
      locations.slice cell projections origin := by
  simp [install, different]

@[simp] theorem install_pointer (locations : Locations) (root : CellId)
    (path : List ValueProjection) (start : Nat) (data : Machine.Address) :
    (install locations root path start data).pointer = locations.pointer := rfl

/-- The two-word native memory effect, usable independently of any emitter.
Architectural addresses are modular; the safe instruction theorem below also
requires the destination's entire sixteen-byte extent to be nonwrapping. -/
def written (memory : Machine.Memory) (destination data : Machine.Address)
    (count : Nat) : Machine.Memory :=
  write64 (write64 memory destination data) (destination + 8) (BitVec.ofNat 64 count)

def Outside (destination candidate : Machine.Address) : Prop :=
  ∀ lane : Fin 16, candidate ≠ destination + BitVec.ofNat 64 lane.val

private theorem halves (destination : Machine.Address) (i j : Fin 8) :
    destination + BitVec.ofNat 64 i.val ≠ destination + 8 + BitVec.ofNat 64 j.val := by
  have ib := i.isLt
  have jb := j.isLt
  simpa [BitVec.ofNat_add, BitVec.add_assoc] using
    offset_ne destination i.val (8 + j.val) (by omega) (by omega) (by omega)

theorem written_words (memory : Machine.Memory) (destination data : Machine.Address) (count : Nat) :
    read64 (written memory destination data count) destination = data ∧
    read64 (written memory destination data count) (destination + 8) = BitVec.ofNat 64 count := by
  constructor
  · rw [written, read64_frame _ _ _ _ (halves destination), read64_write64]
  · exact read64_write64 _ _ _

theorem written_frame (memory : Machine.Memory) (destination data : Machine.Address)
    (count : Nat) (candidate : Machine.Address) (outside : Outside destination candidate) :
    written memory destination data count candidate = memory candidate := by
  have left : ∀ lane : Fin 8, candidate ≠ destination + BitVec.ofNat 64 lane.val := by
    intro lane
    exact outside ⟨lane.val, by have := lane.isLt; omega⟩
  have right : ∀ lane : Fin 8, candidate ≠ destination + 8 + BitVec.ofNat 64 lane.val := by
    intro lane
    simpa [BitVec.ofNat_add, BitVec.add_assoc] using
      outside ⟨8 + lane.val, by have := lane.isLt; omega⟩
  rw [written, write64_frame _ _ _ _ right, write64_frame _ _ _ _ left]

/-- Construct representation rather than assume it. This applies directly to
the fresh `root = before.nextCell`, empty-path, zero-start view created by Raw.map. -/
theorem written_represents (locations : Locations) (memory : Machine.Memory)
    (destination data : Machine.Address) (root : CellId) (path : List ValueProjection)
    (start count : Nat) (bounded : count < 2^64) :
    Storage.Represents (install locations root path start data)
      (written memory destination data count) destination
      (.slice (.scalar (.signed .i32)) root path start count) := by
  refine ⟨[.full data, .full (BitVec.ofNat 64 count)], ?_, ?_⟩
  · simp [Storage.shape, bounded]
  · intro index inside
    have cases : index = 0 ∨ index = 1 := by simp only [List.length_cons, List.length_nil] at inside; omega
    rcases cases with rfl | rfl
    · simpa [Machine.Copy.address, Word.holds] using (written_words memory destination data count).1
    · simpa [Machine.Copy.address, Word.holds] using (written_words memory destination data count).2

/-- Explicit backing separation preserves all packed elements, including the
zero-length case, which requires no readable backing bytes. -/
theorem written_backing (stored : Slice.Represents memory data values)
    (destination : Machine.Address) (count : Nat)
    (separate : ∀ index, index < values.length → ∀ lane : Fin 4,
      Outside destination (Slice.address data index + BitVec.ofNat 64 lane.val)) :
    Slice.Represents (written memory destination data count) data values := by
  apply stored.frame
  intro index inside lane
  exact written_frame _ _ _ _ _ (separate index inside lane)

/-- Descriptor storage is private storage separate from every mapped heap byte.
No Core heap block, pointer mapping, extent, liveness, or ownership fact changes. -/
theorem written_heap (related : Heap.Correspondence heap memory locations)
    (destination data : Machine.Address) (root : CellId) (path : List ValueProjection)
    (start count : Nat)
    (separate : ∀ block, block ∈ heap.blocks → ∀ base,
      locations.pointer block.base = some base → ∀ offset, offset < block.size →
      Outside destination (base + BitVec.ofNat 64 offset)) :
    Heap.Correspondence heap (written memory destination data count)
      (install locations root path start data) := by
  refine ⟨related.wellFormed, ?_, related.offsets, related.covered, related.disjoint⟩
  intro block member base mapped
  apply (related.mappedBlock block member base mapped).frame
  intro offset inside
  exact written_frame _ _ _ _ _ (separate block member base mapped offset inside)

/-- A descriptor-initializer instruction window, not a claim that the current
raw-slice compiler emits these two stores consecutively. That compiler evaluates
the length and checks its sign between saving the pointer and saving the length. -/
def bytes (pointer length destination : Machine.Register) : List UInt8 :=
  memoryBytes .w64 false pointer destination 0 ++ memoryBytes .w64 false length destination 8

def run (before : State) (pointer length destination : Machine.Register) : State :=
  let first := before.store64 pointer destination (BitVec.ofInt 32 0)
    (memoryBytes .w64 false pointer destination 0).length
  first.store64 length destination (BitVec.ofInt 32 8)
    (memoryBytes .w64 false length destination 8).length

theorem run_fields (before : State) (pointer length destination : Machine.Register)
    (count : Nat) (lengthValue : before.registers length = BitVec.ofNat 64 count) :
    (run before pointer length destination).memory =
      written before.memory (before.registers destination) (before.registers pointer) count ∧
    (run before pointer length destination).registers = before.registers ∧
    (run before pointer length destination).flags = before.flags ∧
    (run before pointer length destination).rip = before.rip + BitVec.ofNat 64 (bytes pointer length destination).length := by
  simp [run, State.store64, written, lengthValue, bytes, BitVec.ofNat_add, BitVec.add_assoc]

theorem steps (before : State) (pointer length destination : Machine.Register)
    (loaded : CodeAt before.memory before.rip (bytes pointer length destination))
    (codeSeparate : ∀ index, index < (bytes pointer length destination).length →
      Outside (before.registers destination) (before.rip + BitVec.ofNat 64 index)) :
    Steps 2 before (run before pointer length destination) := by
  let middle := before.store64 pointer destination (BitVec.ofInt 32 0)
    (memoryBytes .w64 false pointer destination 0).length
  have firstStep : Step before middle := .decoded _ loaded.prefix _ _
    (by simpa only [List.append_nil] using memory_decodes .w64 false pointer destination 0 []) rfl
  have preserved : CodeAt middle.memory before.rip (bytes pointer length destination) := by
    change CodeAt (write64 before.memory _ _) _ _
    apply loaded.write64
    intro index inside lane
    simpa using codeSeparate index inside ⟨lane.val, by have := lane.isLt; omega⟩
  have secondCode : CodeAt middle.memory middle.rip (memoryBytes .w64 false length destination 8) := preserved.suffix
  have secondStep : Step middle (run before pointer length destination) := .decoded _ secondCode _ _
    (by simpa only [List.append_nil] using memory_decodes .w64 false length destination 8 []) rfl
  exact .cons firstStep (.cons secondStep (.refl _))

/-- Two actual decoded MOV64 instructions create a nonwrapping descriptor,
retaining the following instruction bytes. Raw pointer mappings remain unchanged
by `install_pointer`; `run_fields` supplies all-register and flag preservation. -/
theorem constructs (locations : Locations) (before : State)
    (pointer length destination : Machine.Register) (root : CellId)
    (path : List ValueProjection) (start count : Nat) (tail : List UInt8)
    (countBound : count < 2^64) (destinationBound : (before.registers destination).toNat + 16 ≤ 2^64)
    (lengthValue : before.registers length = BitVec.ofNat 64 count)
    (loaded : CodeAt before.memory before.rip (bytes pointer length destination ++ tail))
    (codeSeparate : ∀ index, index < (bytes pointer length destination ++ tail).length →
      Outside (before.registers destination) (before.rip + BitVec.ofNat 64 index)) :
    Steps 2 before (run before pointer length destination) ∧
    ((run before pointer length destination).registers destination).toNat + 16 ≤ 2^64 ∧
    Storage.Represents (install locations root path start (before.registers pointer))
      (run before pointer length destination).memory (before.registers destination)
      (.slice (.scalar (.signed .i32)) root path start count) ∧
    CodeAt (run before pointer length destination).memory
      (run before pointer length destination).rip tail := by
  have fields := run_fields before pointer length destination count lengthValue
  refine ⟨steps before pointer length destination loaded.prefix ?_, ?_, ?_, ?_⟩
  · intro index inside
    exact codeSeparate index (by simp only [List.length_append]; omega)
  · rw [fields.2.1]
    exact destinationBound
  · rw [fields.1]
    exact written_represents locations _ _ _ root path start count countBound
  · rw [fields.2.2.2]
    apply CodeAt.suffix
    rw [fields.1]
    intro index inside
    rw [written_frame _ _ _ _ _ (codeSeparate index inside)]
    exact loaded index inside

/-- The initializer preserves the caller's saved header under explicit byte
separation. It also preserves every register and every flag, not merely ABI-saved ones. -/
theorem preserves_caller (frame : Frame.BodyFrame entry started before)
    (pointer length destination : Machine.Register)
    (separate : ∀ header : Fin 16,
      Outside (before.registers destination) (started.registers 5 + BitVec.ofNat 64 header.val)) :
    Frame.BodyFrame entry started (run before pointer length destination) := by
  unfold run
  apply Frame.BodyFrame.write64
  · apply frame.write64
    intro header lane
    simpa using separate header ⟨lane.val, by have := lane.isLt; omega⟩
  · intro header lane
    simpa [State.store64, BitVec.ofNat_add, BitVec.add_assoc] using
      separate header ⟨8 + lane.val, by have := lane.isLt; omega⟩

end Lanius.X86.Storage.Slice.Descriptor
