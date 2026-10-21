import Lanius.Semantics.NativeSnapshotFrame
import Lanius.Memory.Allocated
import Lanius.Memory.BorrowRange

namespace Lanius.Semantics

open Lanius Lanius.Core Lanius.Memory

/-- Read-only allocation shape does not assert allocator ownership. -/
def blockShape (block : Block) : Block := { block with bytes := [], owned := false }

/-- A capability established by an earlier borrow makes a repeated borrow
    an actual no-op. No initially-unowned hypothesis is imposed on callers. -/
theorem _root_.Lanius.Memory.Heap.borrowBlock_eq_of_unowned
    {heap : Heap} {pointer : Address} {block : Block}
    (found : heap.containingBlock? pointer = some block)
    (unique : HeapBlockBasesUnique heap) (owned : block.owned = false) :
    heap.borrowBlock block.base = heap := by
  have member := List.mem_of_find?_eq_some found
  have blocks : (heap.borrowBlock block.base).blocks = heap.blocks := by
    change heap.blocks.map (fun other =>
      { other with owned := if other.base == block.base then false else other.owned }) = heap.blocks
    calc
      _ = heap.blocks.map id := List.map_congr_left (fun other belongs => by
        by_cases same : other.base = block.base
        · have equal := unique other belongs block member same
          subst other
          simp only [BEq.rfl, ↓reduceIte]
          cases block
          cases owned
          rfl
        · simp only [beq_eq_false_iff_ne.mpr same, Bool.false_eq_true, ↓reduceIte]
          rfl)
      _ = _ := List.map_id heap.blocks
  cases heap
  exact congrArg (fun blocks => Heap.mk blocks _ _) blocks

/-- The existing byte-write contract already retains allocator bounds. -/
theorem _root_.Lanius.Memory.HeapWritesOn.below (write : HeapWritesOn before after allowed)
    (below : HeapBlocksBelowNext before) : HeapBlocksBelowNext after := by
  intro block member
  have masked : { block with bytes := [] } ∈ after.blocks.map (fun item => { item with bytes := [] }) :=
    List.mem_map.mpr ⟨block, member, rfl⟩
  rw [write.layout] at masked
  obtain ⟨old, oldMember, same⟩ := List.mem_map.mp masked
  have shape := congrArg (fun item : Block => item.base + max item.size 1) same
  change old.base + max old.size 1 = block.base + max block.size 1 at shape
  rw [write.frontier, ← shape]
  exact below old oldMember

/-- Successful containing-block observations, with an explicit projection.
    In particular, shape and ownership are different observations. -/
def BlockObservation (project : Block → α) (observed : Address → Prop) (before after : Heap) : Prop :=
  ∀ pointer block, observed pointer → before.containingBlock? pointer = some block →
    ∃ current, after.containingBlock? pointer = some current ∧ project current = project block

namespace BlockObservation

theorem refl : BlockObservation project observed heap heap :=
  fun _ block _ found => ⟨block, found, rfl⟩

theorem trans (first : BlockObservation project observed before middle)
    (second : BlockObservation project observed middle after) :
    BlockObservation project observed before after := by
  intro pointer block selected found
  obtain ⟨current, atCurrent, same⟩ := first pointer block selected found
  obtain ⟨final, atFinal, retained⟩ := second pointer current selected atCurrent
  exact ⟨final, atFinal, retained.trans same⟩

theorem restrict (frame : BlockObservation project observed before after)
    (covered : ∀ pointer, selected pointer → observed pointer) :
    BlockObservation project selected before after :=
  fun pointer block inside found => frame pointer block (covered pointer inside) found

/-- Byte-only metadata equality is discharged once at the effect boundary. -/
theorem ofLayout (stable : ∀ block, project { block with bytes := [] } = project block)
    (layout : after.blocks.map (fun block => { block with bytes := [] }) =
      before.blocks.map (fun block => { block with bytes := [] })) :
    BlockObservation project observed before after := by
  intro pointer block _ found
  let mask : Block → Block := fun block => { block with bytes := [] }
  let predicate : Block → Bool := fun block =>
    block.live && block.base ≤ pointer && pointer < block.base + block.size
  have unchanged : predicate ∘ mask = predicate := rfl
  have queried : (after.containingBlock? pointer).map mask = some (mask block) := by
    calc
      (after.containingBlock? pointer).map mask = (after.blocks.map mask).find? predicate := by
        simp only [Heap.containingBlock?, List.find?_map, unchanged]
        rfl
      _ = (before.blocks.map mask).find? predicate := by rw [layout]
      _ = (before.containingBlock? pointer).map mask := by
        simp only [Heap.containingBlock?, List.find?_map, unchanged]
        rfl
      _ = some (mask block) := by rw [found]; rfl
  cases current : after.containingBlock? pointer with
  | none => simp only [current, Option.map_none] at queried; cases queried
  | some value =>
      have same : mask value = mask block :=
        Option.some.inj (by simpa only [current, Option.map_some] using queried)
      exact ⟨value, rfl, (stable value).symm.trans ((congrArg project same).trans (stable block))⟩

theorem appendI32 : BlockObservation project observed heap (heap.appendI32 bytes owned budget) := by
  intro pointer block _ found
  refine ⟨block, ?_, rfl⟩
  simp only [Heap.containingBlock?, Heap.appendI32, List.find?_append] at found ⊢
  rw [found, Option.some_or]

theorem borrowBlock
    (stable : ∀ pointer block, observed pointer → heap.containingBlock? pointer = some block →
      project { block with owned := if block.base == base then false else block.owned } = project block) :
    BlockObservation project observed heap (heap.borrowBlock base) := by
  intro pointer block selected found
  refine ⟨{ block with owned := if block.base == base then false else block.owned }, ?_,
    stable pointer block selected found⟩
  rw [Heap.containingBlock?_borrowBlock, found]
  rfl

end BlockObservation

/-- Three independent observations. A readable container need not own its
    allocation; an ownership capability must request the stronger observation. -/
structure Footprint where
  bytes : Address → Prop
  blocks : Address → Prop
  ownership : Address → Prop

namespace Footprint

def empty : Footprint := ⟨fun _ => False, fun _ => False, fun _ => False⟩
def union (left right : Footprint) : Footprint :=
  ⟨fun p => left.bytes p ∨ right.bytes p, fun p => left.blocks p ∨ right.blocks p,
    fun p => left.ownership p ∨ right.ownership p⟩
def iUnion (family : ι → Footprint) : Footprint :=
  ⟨fun p => ∃ i, (family i).bytes p, fun p => ∃ i, (family i).blocks p,
    fun p => ∃ i, (family i).ownership p⟩

structure Subset (small large : Footprint) : Prop where
  bytes : ∀ p, small.bytes p → large.bytes p
  blocks : ∀ p, small.blocks p → large.blocks p
  ownership : ∀ p, small.ownership p → large.ownership p

theorem Subset.refl (footprint : Footprint) : Subset footprint footprint :=
  ⟨fun _ h => h, fun _ h => h, fun _ h => h⟩

end Footprint

/-- A sound heap-only frame: selected contents and metadata survive, as do
    existing readable permissions. It says nothing about locals or the world. -/
structure HeapFrame (footprint : Footprint) (before after : Heap) : Prop where
  bytes : ∀ pointer offset byte, footprint.bytes (pointer + offset) →
    before.loadByte pointer offset = .ok byte → after.loadByte pointer offset = .ok byte
  readable : ∀ pointer width, before.Readable pointer width → after.Readable pointer width
  blocks : BlockObservation blockShape footprint.blocks before after
  ownership : BlockObservation Block.owned footprint.ownership before after

namespace HeapFrame

theorem refl (footprint : Footprint) (heap : Heap) : HeapFrame footprint heap heap :=
  ⟨fun _ _ _ _ read => read, fun _ _ read => read, .refl, .refl⟩

theorem trans (first : HeapFrame footprint before middle) (second : HeapFrame footprint middle after) :
    HeapFrame footprint before after :=
  ⟨fun p o b inside read => second.bytes p o b inside (first.bytes p o b inside read),
    fun p n read => second.readable p n (first.readable p n read),
    first.blocks.trans second.blocks, first.ownership.trans second.ownership⟩

theorem restrict (frame : HeapFrame large before after) (covered : Footprint.Subset small large) :
    HeapFrame small before after :=
  ⟨fun p o b inside read => frame.bytes p o b (covered.bytes _ inside) read,
    frame.readable, frame.blocks.restrict covered.blocks, frame.ownership.restrict covered.ownership⟩

theorem ofWrites (written : HeapWritesOn before after allowed)
    (apart : ∀ address, footprint.bytes address → ¬allowed address) : HeapFrame footprint before after := by
  refine ⟨?_, written.readable, BlockObservation.ofLayout (fun _ => rfl) written.layout,
    BlockObservation.ofLayout (fun _ => rfl) written.layout⟩
  intro pointer offset byte inside read
  rw [written.outside pointer offset (apart _ inside)]
  exact read

theorem appendI32 {bytes : List UInt8} : HeapFrame footprint heap (heap.appendI32 bytes owned budget) :=
  ⟨fun _ _ _ _ read => Heap.appendI32_oldRead read,
    fun p n read i bound => by
      obtain ⟨byte, loaded⟩ := read i bound
      exact ⟨byte, Heap.appendI32_oldRead loaded⟩,
    .appendI32, .appendI32⟩

/-- Borrowing retains shape even for an initially owned block. Only an
    explicitly requested ownership observation needs a preservation premise. -/
theorem borrowBlock
    (ownership : ∀ pointer block, footprint.ownership pointer →
      heap.containingBlock? pointer = some block → block.base ≠ base ∨ block.owned = false) :
    HeapFrame footprint heap (heap.borrowBlock base) := by
  refine ⟨?_, ?_, BlockObservation.borrowBlock (fun _ _ _ _ => rfl),
    BlockObservation.borrowBlock ?_⟩
  · intro pointer offset byte _ read
    rw [Heap.loadByte_borrowBlock]
    exact read
  · intro pointer width read index bound
    obtain ⟨byte, loaded⟩ := read index bound
    exact ⟨byte, by rw [Heap.loadByte_borrowBlock]; exact loaded⟩
  · intro pointer block selected found
    change (if block.base == base then false else block.owned) = block.owned
    rcases ownership pointer block selected found with different | borrowed
    · simp only [beq_eq_false_iff_ne.mpr different, Bool.false_eq_true, ↓reduceIte]
    · split
      · exact borrowed.symm
      · rfl

/-- Fresh allocation and its borrow retain every original observation,
    including owned capabilities for old blocks. -/
theorem allocatedBorrowed (below : HeapBlocksBelowNext heap) (positive : 0 < alignment) :
    HeapFrame footprint heap
      ((heap.allocatedBytes size alignment budget).borrowBlock (heap.allocationAddress alignment)) := by
  have old (pointer : Address) (block : Block) (found : heap.containingBlock? pointer = some block) :
      (heap.allocatedBytes size alignment budget).containingBlock? pointer = some block := by
    simp only [Heap.containingBlock?, Heap.allocatedBytes, List.find?_append] at found ⊢
    rw [found, Option.some_or]
  have different (block : Block) (member : block ∈ heap.blocks) :
      block.base ≠ heap.allocationAddress alignment := by
    have bound := below block member
    have fresh := heap.allocationAddress_ge positive
    dsimp only [Address] at *
    omega
  have metadata {α : Type} (project : Block → α) (observed : Address → Prop) :
      BlockObservation project observed heap
        ((heap.allocatedBytes size alignment budget).borrowBlock (heap.allocationAddress alignment)) := by
    intro pointer block _ found
    refine ⟨block, ?_, rfl⟩
    rw [Heap.containingBlock?_borrowBlock, old pointer block found]
    change some { block with owned := if block.base == heap.allocationAddress alignment then false else block.owned } = some block
    simp only [beq_eq_false_iff_ne.mpr (different block (List.mem_of_find?_eq_some found)),
      Bool.false_eq_true, ↓reduceIte]
  refine ⟨?_, ?_, metadata _ _, metadata _ _⟩
  · intro pointer offset byte _ read
    rw [Heap.loadByte_borrowBlock]
    exact Heap.allocatedBytes_oldRead read
  · intro pointer width read index bound
    obtain ⟨byte, loaded⟩ := read index bound
    exact ⟨byte, by rw [Heap.loadByte_borrowBlock]; exact Heap.allocatedBytes_oldRead loaded⟩

theorem loadBytes {bytes : List UInt8} (frame : HeapFrame footprint before after)
    (loaded : before.loadBytes pointer width = .ok bytes)
    (covered : ∀ address, pointer ≤ address → address < pointer + width → footprint.bytes address) :
    after.loadBytes pointer width = .ok bytes := by
  have length := (loadBytesFrom_spec loaded).1
  rw [← length]
  apply loadBytesFrom_of_reads
  intro index byte found
  rw [Nat.zero_add]
  have inside := (List.getElem?_eq_some_iff.mp found).1
  exact frame.bytes pointer index byte (covered _ (by omega) (by omega)) (Heap.loadBytes_get loaded found)

theorem snapshot (frame : HeapFrame footprint before after)
    (snapshot : NativeSnapshot fuel program before type base value size)
    (covered : ∀ address, base ≤ address → address < base + size → footprint.bytes address) :
    NativeSnapshot fuel program after type base value size := by
  intro other within
  apply snapshot other
  intro pointer width bytes lower upper loaded
  apply within pointer width bytes lower upper
  exact frame.loadBytes loaded (fun address left right => covered address (by omega) (by omega))

end HeapFrame

#print axioms HeapFrame.ofWrites
#print axioms HeapFrame.borrowBlock
#print axioms HeapFrame.allocatedBorrowed
#print axioms HeapFrame.snapshot
#print axioms Heap.borrowBlock_eq_of_unowned
#print axioms HeapWritesOn.below

end Lanius.Semantics
