import Lanius.X86.Storage.String
import Lanius.Memory.Borrowed

namespace Lanius.X86.Storage.String

open Machine

/-- A successful native allocation must reserve an identity even for an
empty string. These are obligations on the allocator, not consequences of
the flat byte-memory model or of equal string contents. -/
structure Reservation (base : Machine.Address) (length : Nat) : Prop where
  nonnull : base ≠ 0
  aligned : base.toNat % 4 = 0
  bounded : base.toNat + max length 1 ≤ 2^64

def Separated (left : Machine.Address) (leftLength : Nat)
    (right : Machine.Address) (rightLength : Nat) : Prop :=
  left.toNat + max leftLength 1 ≤ right.toNat ∨
    right.toNat + max rightLength 1 ≤ left.toNat

theorem Separated.symm (separate : Separated left leftLength right rightLength) :
    Separated right rightLength left leftLength := Or.symm separate

theorem Separated.different (separate : Separated left leftLength right rightLength) :
    left ≠ right := by
  intro same
  subst right
  unfold Separated at separate
  omega

theorem Separated.lanes (separate : Separated left leftLength right rightLength)
    (leftBound : left.toNat + leftLength ≤ 2^64)
    (rightBound : right.toNat + rightLength ≤ 2^64)
    (i j : Nat) (ib : i < leftLength) (jb : j < rightLength) :
    left + BitVec.ofNat 64 i ≠ right + BitVec.ofNat 64 j := by
  intro same
  have numbers := congrArg BitVec.toNat same
  simp only [BitVec.toNat_add, BitVec.toNat_ofNat] at numbers
  unfold Separated at separate
  omega

/-- Postcondition required of the runtime's byte-copy loop. It does not
assert that the unverified allocator or emitted loop establishes it. The
frame covers every address, including code, old heap blocks, and descriptors. -/
structure CopyResult (before after : Memory) (source destination : Machine.Address) (length : Nat) : Prop where
  reserved : Reservation destination length
  copied : ∀ index, index < length →
    after (destination + BitVec.ofNat 64 index) = before (source + BitVec.ofNat 64 index)
  frame : ∀ candidate, (∀ index, index < length → candidate ≠ destination + BitVec.ofNat 64 index) →
    after candidate = before candidate

theorem CopyResult.contents (result : CopyResult before after source destination bytes.length)
    (sourceBytes : Bytes before source bytes) : Bytes after destination bytes := by
  refine ⟨Nat.le_trans (Nat.add_le_add_left (Nat.le_max_left _ _) _) result.reserved.bounded, ?_⟩
  intro index inside
  exact (result.copied index inside).trans (sourceBytes.contents index inside)

theorem CopyResult.preserve (result : CopyResult before after source destination length)
    (old : Bytes before base original)
    (separate : Separated base original.length destination length) :
    Bytes after base original := by
  apply old.frame
  intro index inside
  apply result.frame
  intro written bound
  exact separate.lanes old.bounded
    (Nat.le_trans (Nat.add_le_add_left (Nat.le_max_left _ _) _) result.reserved.bounded)
    index written inside bound

/-- A fresh data copy retains the original immutable descriptor and bytes,
and initializes the independently mutable destination with the same UTF-8.
The source may be any content-based descriptor, not only a pooled literal. -/
theorem Represents.copy_data (stored : Represents before descriptor text)
    (result : CopyResult before after stored.pointer destination (Lanius.World.utf8Bytes text).length)
    (dataSeparate : Separated stored.pointer (Lanius.World.utf8Bytes text).length
      destination (Lanius.World.utf8Bytes text).length)
    (descriptorSeparate : ∀ word : Fin 2, ∀ lane : Fin 8, ∀ index,
      index < (Lanius.World.utf8Bytes text).length →
      Machine.Copy.address descriptor word.val + BitVec.ofNat 64 lane.val ≠ destination + BitVec.ofNat 64 index) :
    Represents after descriptor text ∧ Bytes after destination (Lanius.World.utf8Bytes text) ∧
      stored.pointer ≠ destination := by
  refine ⟨?_, result.contents stored.data, dataSeparate.different⟩
  apply stored.frame
  · intro word lane
    exact result.frame _ (descriptorSeparate word lane)
  · intro index inside
    apply result.frame
    intro written bound
    exact dataSeparate.lanes stored.data.bounded
      (Nat.le_trans (Nat.add_le_add_left (Nat.le_max_left _ _) _) result.reserved.bounded)
      index written inside bound

/-- Mutating one copy cannot mutate another represented byte sequence.
In particular, the other sequence may be the immutable literal or an earlier
copy of identical text. Zero-length allocations stay distinct by `different`. -/
theorem Bytes.store_separate (stored : Bytes memory base original)
    (destinationBound : destination.toNat + length ≤ 2^64)
    (separate : Separated base original.length destination length)
    (inside : index < length) (byte : UInt8) :
    Bytes (writeByte memory (destination + BitVec.ofNat 64 index) byte) base original := by
  apply stored.frame
  intro other bound
  apply writeByte_frame
  exact separate.lanes stored.bounded destinationBound other index bound inside

namespace Core

open Lanius.Memory Lanius.Semantics Lanius.Properties

/-- The exact Core contract is a new protected borrowed block, not an alias
of the immutable literal and not reuse of a previous equal-content copy. -/
structure Mapped (before after : Lanius.Semantics.State) (text : _root_.String) (pointer : Nat) : Prop where
  execution : mapStringDataPtr before text = .done (.pointer pointer) after
  heap : HeapWellFormed after.heap
  block : after.heap.block? pointer = some {
    base := pointer, size := (Lanius.World.utf8Bytes text).length,
    alignment := 4, bytes := Lanius.World.utf8Bytes text, owned := false }
  contents : after.heap.loadBytes pointer (Lanius.World.utf8Bytes text).length =
    .ok (Lanius.World.utf8Bytes text)
  fresh : ∀ old ∈ before.heap.blocks, old.base < pointer
  frontier : after.heap.nextAddress = pointer + max (Lanius.World.utf8Bytes text).length 1
  stateFrame : after = { before with heap := after.heap }
  blocks : after.heap.blocks = before.heap.blocks ++ [{
    base := pointer, size := (Lanius.World.utf8Bytes text).length,
    alignment := 4, bytes := Lanius.World.utf8Bytes text, owned := false }]
  budget : after.heap.remaining = before.heap.remaining

theorem map_correct (wellFormed : HeapWellFormed before.heap) :
    ∃ pointer after, Mapped before after text pointer := by
  let bytes := Lanius.World.utf8Bytes text
  let pointer := alignUp (max before.heap.nextAddress 1) 4
  let block : Block := {
    base := pointer
    size := bytes.length
    alignment := 4
    bytes := bytes
    owned := false }
  let heap : Heap := { before.heap with
    blocks := before.heap.blocks ++ [block]
    nextAddress := pointer + max bytes.length 1 }
  have mapped : before.heap.mapBorrowed bytes 4 = .allocated pointer heap := rfl
  have preserved := mapBorrowed_preserves_heap_well_formed (bytes := bytes) (alignment := 4) wellFormed
  rw [mapped] at preserved
  refine ⟨pointer, { before with heap }, ?_⟩
  refine ⟨?_, preserved, Heap.mapped_borrowed_block wellFormed mapped,
    Heap.loadBytes_mapped_borrowed wellFormed mapped, ?_, rfl, rfl, rfl, rfl⟩
  · rfl
  · intro old member
    have below := wellFormed.blocksBelowNext old member
    have aligned : max before.heap.nextAddress 1 ≤ pointer := alignUp_ge _ _ (by decide)
    change old.base + max old.size 1 ≤ before.heap.nextAddress at below
    change old.base < pointer
    have positive : 0 < max old.size 1 := Nat.lt_of_lt_of_le Nat.zero_lt_one (Nat.le_max_right _ _)
    calc
      old.base < old.base + max old.size 1 := Nat.lt_add_of_pos_right positive
      _ ≤ before.heap.nextAddress := below
      _ ≤ max before.heap.nextAddress 1 := Nat.le_max_left _ _
      _ ≤ pointer := aligned

/-- Calling on the same text twice returns two distinct identities, even
for the empty string. No allocator-budget hypothesis is needed in Core:
`mapBorrowed` leaves that budget unchanged. -/
theorem Mapped.distinct (first : Mapped before middle firstText left)
    (second : Mapped middle after secondText right) : left < right := by
  have member := List.mem_of_find?_eq_some first.block
  exact second.fresh _ member

theorem Mapped.old_block (mapped : Mapped before after text pointer)
    (found : before.heap.block? identity = some old) : after.heap.block? identity = some old := by
  simp only [Heap.block?] at found ⊢
  simp only [mapped.blocks, List.find?_append, found, Option.or]

theorem two_calls (wellFormed : HeapWellFormed before.heap) (text : _root_.String) :
    ∃ left middle right after, Mapped before middle text left ∧ Mapped middle after text right ∧ left < right := by
  obtain ⟨left, middle, first⟩ := map_correct (text := text) wellFormed
  obtain ⟨right, after, second⟩ := map_correct (text := text) first.heap
  exact ⟨left, middle, right, after, first, second, first.distinct second⟩

/-- A raw Core pointer denotes a block identity; its native address need
not equal that identity numerically. A whole-heap injection must eventually
compose these per-block witnesses and preserve pointer comparisons. -/
structure BorrowedAt (heap : Heap) (memory : Machine.Memory) (identity : Nat)
    (address : Machine.Address) (bytes : List UInt8) : Prop where
  block : heap.block? identity = some {
    base := identity, size := bytes.length, alignment := 4, bytes := bytes, owned := false }
  allocation : Reservation address bytes.length
  contents : Bytes memory address bytes

/-- Connect actual Core evaluation to the native copy's required memory
postcondition. This proves the storage/refinement boundary, not that the
unverified mmap allocator and emitted byte loop satisfy `CopyResult`. -/
theorem Mapped.realize (mapped : Mapped before after text identity)
    (sourceBytes : Bytes nativeBefore source (Lanius.World.utf8Bytes text))
    (copied : CopyResult nativeBefore nativeAfter source address (Lanius.World.utf8Bytes text).length) :
    BorrowedAt after.heap nativeAfter identity address (Lanius.World.utf8Bytes text) :=
  ⟨mapped.block, copied.reserved, copied.contents sourceBytes⟩

theorem BorrowedAt.frame (represented : BorrowedAt heap before identity address bytes)
    (same : ∀ index, index < bytes.length →
      after (address + BitVec.ofNat 64 index) = before (address + BitVec.ofNat 64 index)) :
    BorrowedAt heap after identity address bytes :=
  ⟨represented.block, represented.allocation, represented.contents.frame same⟩

end Core
end Lanius.X86.Storage.String
