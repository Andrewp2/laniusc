import Lanius.Semantics
import Lanius.Memory.Allocation
import Lanius.Semantics.NativeStore

namespace Lanius.Semantics

open Lanius.Core Lanius.Memory

/-- Existing readable bytes keep their values; newly allocated bytes may be
    added. This covers allocation and writes confined to fresh storage. -/
def HeapReads (before after : Heap) : Prop :=
  ∀ pointer offset byte, before.loadByte pointer offset = .ok byte →
    after.loadByte pointer offset = .ok byte

theorem HeapReads.refl (heap : Heap) : HeapReads heap heap := fun _ _ _ read => read

theorem HeapReads.trans (first : HeapReads before middle) (second : HeapReads middle after) :
    HeapReads before after := fun _ _ _ read => second _ _ _ (first _ _ _ read)

/-- Preserve the reference fragment, not all readable bytes in the mutable heap. -/
theorem HeapReads.afterWrites (reads : HeapReads reference before)
    (write : HeapWritesOn before after allowed)
    (apart : ∀ pointer offset byte, reference.loadByte pointer offset = .ok byte →
      ¬allowed (pointer + offset)) : HeapReads reference after := by
  intro pointer offset byte read
  rw [write.outside _ _ (apart _ _ _ read)]
  exact reads _ _ _ read

theorem HeapReads.appendI32 : HeapReads heap (heap.appendI32 bytes owned budget) :=
  fun _ _ _ read => Heap.appendI32_oldRead read

/-- A proved native-slot write confined to fresh storage retains all reads
    from the old heap. No encoding or rereading of its old values is needed. -/
theorem HeapReads.writeRegionFresh (reads : HeapReads original before)
    (below : HeapBlocksBelowNext original) (fresh : original.nextAddress ≤ address)
    (write : HeapRegionWrite before after address size) : HeapReads original after := by
  intro pointer offset byte read
  have aliasRead := Heap.loadByte_alias read (show (pointer + offset) + 0 = pointer + offset by omega)
  have inside := (Heap.Readable.of_loadBytes (show original.loadBytes (pointer + offset) 1 = .ok [byte] from
    by simp [Heap.loadBytes, loadBytesFrom, aliasRead])).belowNext (by decide) below
  rw [write.outside _ _ (Or.inl (by dsimp only [Address] at *; omega))]
  exact reads _ _ _ read

theorem HeapReads.writeFresh (reads : HeapReads original before)
    (below : HeapBlocksBelowNext original) (fresh : original.nextAddress ≤ address)
    (write : BytesWrite before after address bytes) : HeapReads original after :=
  reads.writeRegionFresh below fresh (HeapRegionWrite.ofBytes write)

theorem HeapReads.loadBytes (reads : HeapReads before after)
    (loaded : before.loadBytes pointer count = .ok bytes) :
    after.loadBytes pointer count = .ok bytes := by
  have length := (loadBytesFrom_spec loaded).1
  rw [← length]
  apply loadBytesFrom_of_reads
  intro index byte found
  exact reads _ _ _ (by simpa using Heap.loadBytes_get loaded found)

theorem HeapReads.readable (reads : HeapReads before after) (readable : before.Readable pointer count) :
    after.Readable pointer count := by
  intro index inside
  obtain ⟨byte, loaded⟩ := readable index inside
  exact ⟨byte, reads _ _ _ loaded⟩

private def Refines {α : Type} (before after : Except Trap α) : Prop :=
  ∀ value, before = .ok value → after = .ok value

private theorem Refines.refl (value : Except Trap α) : Refines value value := fun _ same => same

private theorem Refines.bind (head : Refines before after)
    (tail : ∀ value, Refines (left value) (right value)) :
    Refines (before.bind left) (after.bind right) := by
  intro value result
  cases h : before with
  | error reason => simp [h, Except.bind] at result
  | ok item =>
      rw [head item h]
      exact tail item value (by simpa [h, Except.bind] using result)

private theorem Refines.mapM (items : List α)
    (each : ∀ item, Refines (left item) (right item)) :
    Refines (items.mapM left) (items.mapM right) := by
  induction items with
  | nil => exact .refl _
  | cons item items ih =>
      simp only [List.mapM_cons]
      apply Refines.bind (each item)
      intro value
      apply Refines.bind ih
      intro rest
      exact .refl _

private theorem Refines.branch [Decidable condition]
    (yes : Refines leftTrue rightTrue) (no : Refines leftFalse rightFalse) :
    Refines (if condition then leftTrue else leftFalse) (if condition then rightTrue else rightFalse) := by
  by_cases condition <;> simp only [*, ↓reduceIte] <;> assumption

private theorem HeapReads.natLE (reads : HeapReads before after) :
    Refines (loadNatLE before pointer width) (loadNatLE after pointer width) :=
  Refines.bind (fun _ loaded => reads.loadBytes loaded) (fun _ => .refl _)

/-- Native snapshots, including nested structures, enums, strings and slice
    descriptors, survive any extension of the original byte reads. -/
theorem HeapReads.nativeValue (reads : HeapReads before after)
    (loaded : readNativeValue fuel program before type address = .ok value) :
    readNativeValue fuel program after type address = .ok value := by
  suffices Refines (readNativeValue fuel program before type address)
      (readNativeValue fuel program after type address) from this _ loaded
  clear loaded value
  induction fuel generalizing type address with
  | zero => exact .refl _
  | succ fuel ih =>
      cases type with
      | scalar scalar =>
          cases scalar with
          | signed integer => cases integer <;> simp only [readNativeValue] <;>
              first | exact .refl _ | exact Refines.bind reads.natLE (fun _ => .refl _)
          | unsigned integer => cases integer <;> simp only [readNativeValue] <;>
              first | exact .refl _ | exact Refines.bind reads.natLE (fun _ => .refl _)
          | bool => exact Refines.bind reads.natLE (fun _ => .refl _)
          | rawPtr => exact Refines.bind reads.natLE (fun _ => .refl _)
          | string =>
              apply Refines.bind reads.natLE; intro pointer
              apply Refines.bind (.refl _); intro below
              apply Refines.bind reads.natLE; intro length
              exact Refines.bind (fun _ loaded => reads.loadBytes loaded) (fun _ => .refl _)
          | _ => exact .refl _
      | slice element =>
          simp only [readNativeValue]
          split
          · exact .refl _
          · exact Refines.bind reads.natLE (fun _ => Refines.bind (.refl _) (fun _ =>
              Refines.bind reads.natLE (fun _ => Refines.bind (.refl _) (fun _ =>
                Refines.bind reads.natLE (fun _ => .refl _)))))
      | «structure» id =>
          simp only [readNativeValue]
          split <;> first | exact .refl _ | skip
          apply Refines.bind
          · apply Refines.mapM; intro field
            split <;> first | exact .refl _ | skip
            split <;> first | exact .refl _ | exact Refines.bind (.refl _) (fun _ => ih)
          · intro fields; exact .refl _
      | enumeration id =>
          simp only [readNativeValue]
          split <;> first | exact .refl _ | skip
          apply Refines.bind reads.natLE; intro variant
          split <;> first | exact .refl _ | skip
          apply Refines.bind
          · apply Refines.mapM; intro field
            split <;> first | exact .refl _ | skip
            split <;> first | exact .refl _ | exact Refines.bind (.refl _) (fun _ => ih)
          · intro fields; exact .refl _
      | _ => exact .refl _

theorem HeapReads.rawSlice (reads : HeapReads before.heap after.heap)
    (loaded : readRawSliceIndex program before element address length index = .ok value) :
    readRawSliceIndex program after element address length index = .ok value := by
  by_cases bound : index ≥ length
  · simp [readRawSliceIndex, bound] at loaded
  · simp only [readRawSliceIndex, bound, ↓reduceIte] at loaded ⊢
    cases location : rawSliceElementAddress? program element address index with
    | error reason => rw [location] at loaded; contradiction
    | ok base =>
        rw [location] at loaded
        change readNativeValue NativeLayout.maxDepth program before.heap element base = .ok value at loaded
        change readNativeValue NativeLayout.maxDepth program after.heap element base = .ok value
        exact reads.nativeValue loaded

/-- A native i32 read survives writes confined to a disjoint region. -/
theorem readRawSliceIndex_i32_afterRegionWrite (write : HeapRegionWrite before.heap after.heap address size)
    (bound : position < count) (readable : before.heap.Readable (pointer + position * 4) 4)
    (outside : pointer + position * 4 + 4 ≤ address ∨ address + size ≤ pointer + position * 4)
    (read : readRawSliceIndex program before (.scalar (.signed .i32)) pointer count position = .ok value) :
    readRawSliceIndex program after (.scalar (.signed .i32)) pointer count position = .ok value := by
  obtain ⟨values, loaded⟩ := readable.loadBytes
  have preserved := write.loadBytes loaded outside
  have notBound : ¬position ≥ count := Nat.not_le_of_lt bound
  simp only [readRawSliceIndex, notBound, ↓reduceIte] at read ⊢
  change readNativeValue NativeLayout.maxDepth program before.heap (.scalar (.signed .i32))
    (pointer + position * 4) = .ok value at read
  change readNativeValue NativeLayout.maxDepth program after.heap (.scalar (.signed .i32))
    (pointer + position * 4) = .ok value
  simpa only [readNativeValue, NativeLayout.maxDepth, loadNatLE, loaded, preserved] using read

/-- Different endpoint words are independent, even though the table itself
    is mutable. Only the scalar read is transported here, not the whole heap. -/
theorem readRawSliceIndex_i32_disjoint (write : BytesWrite before.heap after.heap address bytes)
    (bound : position < count) (readable : before.heap.Readable (pointer + position * 4) 4)
    (outside : address + bytes.length ≤ pointer + position * 4 ∨ pointer + position * 4 + 4 ≤ address)
    (read : readRawSliceIndex program before (.scalar (.signed .i32)) pointer count position = .ok value) :
    readRawSliceIndex program after (.scalar (.signed .i32)) pointer count position = .ok value :=
  readRawSliceIndex_i32_afterRegionWrite (HeapRegionWrite.ofBytes write) bound readable outside.symm read

/-- An indexed word store changes exactly one logical element. The old value
    is needed only at other indices, so this also extends an initialized prefix. -/
theorem readRawSliceIndex_i32_afterStore {pointer index position capacity : Nat}
    (write : BytesWrite before.heap after.heap (pointer + index * 4) (i32Bytes value))
    (represented : (BitVec.ofInt 32 value).toInt = value)
    (bound : position < capacity) (room : before.heap.Readable (pointer + position * 4) 4)
    (old : position ≠ index → readRawSliceIndex program before (.scalar (.signed .i32))
      pointer capacity position = .ok (.signed .i32 previous)) :
    readRawSliceIndex program after (.scalar (.signed .i32)) pointer capacity position =
      .ok (.signed .i32 (if position = index then value else previous)) := by
  by_cases same : position = index
  · subst position
    have loaded : after.heap.loadBytes (pointer + index * 4) 4 = .ok (i32Bytes value) := by
      simpa only [i32Bytes, List.length_map, List.length_range] using write.loadBytes
    simpa only [represented, ↓reduceIte] using
      readRawSliceIndex_i32Bytes program after
        (word := BitVec.ofInt 32 value) bound (by simpa only [represented] using loaded)
  · simp only [same, ↓reduceIte]
    have apart : pointer + index * 4 + 4 ≤ pointer + position * 4 ∨
        pointer + position * 4 + 4 ≤ pointer + index * 4 := by omega
    exact readRawSliceIndex_i32_disjoint (pointer := pointer) (count := capacity) (position := position) write bound room
      (by simpa only [i32Bytes, List.length_map, List.length_range] using apart) (old same)

/-- Frame a whole i32 table through a disjoint region write. This is a memory
    rule only: the meaning of its values remains the client's responsibility. -/
theorem i32Table_afterRegionWrite {pointer address size count capacity : Nat} {values : Nat → Int}
    (write : HeapRegionWrite before.heap after.heap address size)
    (storage : count ≤ capacity) (room : before.heap.Readable pointer (count * 4))
    (separate : pointer + count * 4 ≤ address ∨ address + size ≤ pointer)
    (read : ∀ index, index < count → readRawSliceIndex program before
      (.scalar (.signed .i32)) pointer capacity index = .ok (.signed .i32 (values index))) :
    ∀ index, index < count → readRawSliceIndex program after
      (.scalar (.signed .i32)) pointer capacity index = .ok (.signed .i32 (values index)) := by
  intro index inside
  exact readRawSliceIndex_i32_afterRegionWrite write (Nat.lt_of_lt_of_le inside storage)
    (room.subrange (start := index * 4) (length := 4) (by omega)) (by omega) (read index inside)

end Lanius.Semantics
