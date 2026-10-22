import Lanius.Semantics.NativeEncoding
import Lanius.Memory.Read
import Lanius.Memory.StoreSame
import Lanius.Memory.Footprint
import Lanius.Semantics.Native.Codec

namespace Lanius.Semantics

open Lanius Lanius.Core Lanius.Memory

/-- A mutable native slot, including its frame over aliases, padding and
    allocation metadata. This is proof-only memory information, not IR. -/
structure HeapRegionWrite (before after : Heap) (address size : Nat) : Prop where
  outside : ∀ pointer offset, pointer + offset < address ∨ address + size ≤ pointer + offset →
    after.loadByte pointer offset = before.loadByte pointer offset
  readable : ∀ pointer count, before.Readable pointer count → after.Readable pointer count
  unique : HeapBlockBasesUnique after
  frontier : after.nextAddress = before.nextAddress
  budget : after.remaining = before.remaining
  layout : after.blocks.map (fun block => { block with bytes := [] }) =
    before.blocks.map (fun block => { block with bytes := [] })

theorem HeapRegionWrite.refl (heap : Heap) (unique : HeapBlockBasesUnique heap) :
    HeapRegionWrite heap heap address size :=
  ⟨fun _ _ _ => rfl, fun _ _ read => read, unique, rfl, rfl, rfl⟩

/-- The interval is exact; padding outside it is not granted write permission. -/
theorem HeapRegionWrite.footprint (write : HeapRegionWrite before after address size) :
    HeapWritesOn before after (fun location => address ≤ location ∧ location < address + size) :=
  ⟨fun _ _ apart => write.outside _ _ (by dsimp only [Address] at *; omega),
    write.readable, write.unique, write.frontier, write.budget, write.layout⟩

theorem HeapRegionWrite.ofBytes (effect : BytesWrite before after address bytes) :
    HeapRegionWrite before after address bytes.length := by
  refine ⟨?_, fun _ _ => effect.readable, effect.unique, effect.frontier, effect.budget, effect.layout⟩
  intro pointer offset apart
  rw [effect.reads]
  split
  · rw [List.getElem?_eq_none (by dsimp only [Address] at *; omega)]
  · rfl

theorem HeapRegionWrite.enlarge (effect : HeapRegionWrite before after inner size)
    (lower : outer ≤ inner) (upper : inner + size ≤ outer + capacity) :
    HeapRegionWrite before after outer capacity :=
  ⟨fun _ _ apart => effect.outside _ _ (by omega),
    effect.readable, effect.unique, effect.frontier, effect.budget, effect.layout⟩

theorem HeapRegionWrite.trans (first : HeapRegionWrite before middle address size)
    (second : HeapRegionWrite middle after address size) : HeapRegionWrite before after address size :=
  ⟨fun _ _ apart => (second.outside _ _ apart).trans (first.outside _ _ apart),
    fun _ _ read => second.readable _ _ (first.readable _ _ read), second.unique,
    second.frontier.trans first.frontier, second.budget.trans first.budget,
    second.layout.trans first.layout⟩

theorem HeapRegionWrite.below (write : HeapRegionWrite before after address size)
    (below : HeapBlocksBelowNext before) : HeapBlocksBelowNext after := by
  intro block member
  have masked : { block with bytes := [] } ∈ after.blocks.map (fun item => { item with bytes := [] }) :=
    List.mem_map.mpr ⟨block, member, rfl⟩
  rw [write.layout] at masked
  obtain ⟨old, oldMember, same⟩ := List.mem_map.mp masked
  have shape := congrArg (fun item : Block => item.base + max item.size 1) same
  simpa only [write.frontier, shape] using below old oldMember

theorem HeapRegionWrite.loadBytes (effect : HeapRegionWrite before after address size)
    (loaded : before.loadBytes pointer count = .ok bytes)
    (apart : pointer + count ≤ address ∨ address + size ≤ pointer) :
    after.loadBytes pointer count = .ok bytes := by
  apply Heap.loadBytes_congr loaded
  intro index bound
  exact effect.outside _ _ (by omega)

/-- Successful byte reads confined to a native slot survive a later heap. -/
def ReadsWithin (before after : Heap) (address size : Nat) : Prop :=
  ∀ pointer count bytes, address ≤ pointer → pointer + count ≤ address + size →
    before.loadBytes pointer count = .ok bytes → after.loadBytes pointer count = .ok bytes

theorem ReadsWithin.narrow (reads : ReadsWithin before after outer capacity)
    (lower : outer ≤ address) (upper : address + size ≤ outer + capacity) :
    ReadsWithin before after address size :=
  fun _ _ _ left right => reads _ _ _ (by omega) (by omega)

/-- A value justified by bytes in its own slot. This strengthens read-back:
    unrelated stores can preserve it without decoding it a second time.
    Native words descend from a value's word 0 at `address`, so its slot of
    `size` bytes is the one ending at `address + 8`. -/
def NativeSnapshot (fuel : Nat) (program : Program) (heap : Heap) (type : Ty)
    (address : Nat) (value : Value) (size : Nat) : Prop :=
  ∀ other, ReadsWithin heap other (address + 8 - size) size →
    readNativeValue fuel program other type address = .ok value

theorem NativeSnapshot.read (snapshot : NativeSnapshot fuel program heap type address value size) :
    readNativeValue fuel program heap type address = .ok value := snapshot heap (fun _ _ _ _ _ read => read)

theorem NativeSnapshot.enlarge (snapshot : NativeSnapshot fuel program heap type address value size)
    (larger : size ≤ capacity) : NativeSnapshot fuel program heap type address value capacity :=
  fun _ reads => snapshot _ (reads.narrow (by omega) (by omega))

theorem NativeSnapshot.afterWrite (snapshot : NativeSnapshot fuel program before type pointer value count)
    (effect : HeapRegionWrite before after address size)
    (apart : pointer + 8 - count + count ≤ address ∨ address + size ≤ pointer + 8 - count) :
    NativeSnapshot fuel program after type pointer value count := by
  intro other reads
  apply snapshot other
  intro location width bytes lower upper loaded
  apply reads _ _ _ lower upper
  exact effect.loadBytes loaded (by omega)

theorem NativeSnapshot.i32 (word : BitVec 32)
    (loaded : heap.loadBytes address 4 = .ok (i32Bytes word.toInt)) :
    NativeSnapshot (fuel + 1) program heap (.scalar (.signed .i32)) address (.signed .i32 word.toInt) 8 := by
  intro other reads
  have loaded := reads _ _ _ (by omega) (by omega) loaded
  simp only [readNativeValue, loadNatLE, loaded]
  change Except.ok (Value.signed .i32 (if decodeNatLE (i32Bytes word.toInt) ≥ 2 ^ 31 then
    Int.ofNat (decodeNatLE (i32Bytes word.toInt)) - 2 ^ 32 else
    Int.ofNat (decodeNatLE (i32Bytes word.toInt)))) = _
  rw [decodeNatLE_i32Bytes]
  congr 2
  simp [BitVec.toInt_eq_msb_cond, BitVec.msb_eq_decide]

theorem NativeSnapshot.enumEmpty {id : TypeId}
    (declaration : program.enumeration? id = some enumeration)
    (variant : enumeration.variants[ordinal]? = some []) (fits : ordinal < 256 ^ 4)
    (loaded : heap.loadBytes address 4 = .ok (encodeNatLE 4 ordinal)) :
    NativeSnapshot (fuel + 1) program heap (.enumeration id) address (.enumeration id ordinal []) 8 := by
  intro other reads
  have loaded := reads _ _ _ (by omega) (by omega) loaded
  simp only [readNativeValue, declaration, loadNatLE_of_encoded loaded fits]
  dsimp only [Bind.bind, Except.bind]
  simp [variant]
  rfl

theorem NativeSnapshot.enumSingle {id : TypeId}
    (declaration : program.enumeration? id = some enumeration)
    (variant : enumeration.variants[ordinal]? = some [type]) (fits : ordinal < 256 ^ 4)
    (tag : heap.loadBytes address 4 = .ok (encodeNatLE 4 ordinal)) (above : 8 ≤ address)
    (payload : NativeSnapshot fuel program heap type (address - 8) value size) :
    NativeSnapshot (fuel + 1) program heap (.enumeration id) address (.enumeration id ordinal [value]) (8 + size) := by
  intro other reads
  have tag := reads _ _ _ (by omega) (by omega) tag
  have payload := payload other (reads.narrow (by omega) (by omega))
  simp only [readNativeValue, declaration, loadNatLE_of_encoded tag fits]
  dsimp only [Bind.bind, Except.bind]
  simp only [variant]
  simp [NativeLayout.wordBytes, List.range_succ, wordBelow, above]
  rw [payload]
  rfl

theorem writeNativeValue_enumEmpty_same {id : TypeId}
    (declaration : program.enumeration? id = some enumeration)
    (variant : enumeration.variants[ordinal]? = some [])
    (unique : HeapBlockBasesUnique heap)
    (loaded : heap.loadBytes address 4 = .ok (encodeNatLE 4 ordinal)) :
    writeNativeValue (fuel + 1) program state heap (.enumeration id) address
      (.enumeration id ordinal []) = .ok heap := by
  have written := Heap.storeBytes_same (pointer := address) (bytes := encodeNatLE 4 ordinal) unique (by
    simpa only [encodeNatLE, List.length_map, List.length_range] using loaded)
  simp [writeNativeValue, declaration, variant, written]

/-- The reusable native-store contract: valid storage suffices to execute
    the real store, read back the value, and preserve everything outside it.
    Constructors below prove this contract; callers need not decode bytes.
    The slot is the `size` bytes ending at `address + 8` (see `NativeSnapshot`). -/
def NativeStoreSpec (fuel : Nat) (program : Program) (type : Ty) (value : Value) (size : Nat) : Prop :=
  ∀ (state : State) (heap : Heap) (address : Nat), size ≤ address + 8 →
    heap.Readable (address + 8 - size) size → HeapBlockBasesUnique heap →
    ∃ after, writeNativeValue fuel program state heap type address value = .ok after ∧
      NativeSnapshot fuel program after type address value size ∧
      HeapRegionWrite heap after (address + 8 - size) size

theorem NativeStoreSpec.enlarge (store : NativeStoreSpec fuel program type value size)
    (larger : size ≤ capacity) : NativeStoreSpec fuel program type value capacity := by
  intro state heap address fits readable unique
  have inner := readable.subrange (start := capacity - size) (length := size) (by omega)
  rw [show address + 8 - capacity + (capacity - size) = address + 8 - size by omega] at inner
  obtain ⟨after, written, read, effect⟩ := store state heap address (by omega) inner unique
  exact ⟨after, written, read.enlarge larger, effect.enlarge (by omega) (by omega)⟩

theorem NativeStoreSpec.i32 (word : BitVec 32) :
    NativeStoreSpec (fuel + 1) program (.scalar (.signed .i32)) (.signed .i32 word.toInt) 8 := by
  intro state heap address _ readable unique
  rw [Nat.add_sub_cancel] at readable ⊢
  obtain ⟨after, stored, effect⟩ := Heap.storeBytes_of_readable (i32Bytes word.toInt) unique
    (by simpa only [Heap.Readable, i32Bytes, List.length_map, List.length_range, Nat.add_zero] using
      readable.subrange (start := 0) (length := 4) (by omega))
  refine ⟨after, stored, ?_, (HeapRegionWrite.ofBytes effect).enlarge (Nat.le_refl _) (by
    simp only [i32Bytes, List.length_map, List.length_range]; omega)⟩
  have loaded : after.loadBytes address 4 = .ok (i32Bytes word.toInt) := by
    simpa only [i32Bytes, List.length_map, List.length_range] using effect.loadBytes
  exact NativeSnapshot.i32 word loaded

theorem NativeStoreSpec.boolean (value : Bool) :
    NativeStoreSpec (fuel + 1) program (.scalar .bool) (.boolean value) 8 := by
  intro state heap address _ readable unique
  rw [Nat.add_sub_cancel] at readable ⊢
  obtain ⟨after, stored, effect⟩ := Heap.storeBytes_of_readable
    (encodeNatLE 4 (if value then 1 else 0)) unique
    (by simpa only [Heap.Readable, encodeNatLE, List.length_map, List.length_range, Nat.add_zero] using
      readable.subrange (start := 0) (length := 4) (by omega))
  refine ⟨after, stored, ?_, (HeapRegionWrite.ofBytes effect).enlarge (Nat.le_refl _) (by
    simp only [encodeNatLE, List.length_map, List.length_range]; omega)⟩
  have loaded : after.loadBytes address 4 = .ok (encodeNatLE 4 (if value then 1 else 0)) := by
    simpa only [encodeNatLE, List.length_map, List.length_range] using effect.loadBytes
  intro other reads
  have loaded := reads _ _ _ (by omega) (by omega) loaded
  have decoded := loadNatLE_of_encoded loaded (by cases value <;> decide)
  cases value <;> simp [readNativeValue, decoded] <;> rfl

theorem NativeStoreSpec.enumEmpty {id : TypeId}
    (declaration : program.enumeration? id = some enumeration)
    (variant : enumeration.variants[ordinal]? = some []) (fits : ordinal < 256 ^ 4) :
    NativeStoreSpec (fuel + 1) program (.enumeration id) (.enumeration id ordinal []) 8 := by
  intro state heap address _ readable unique
  rw [Nat.add_sub_cancel] at readable ⊢
  obtain ⟨after, stored, effect⟩ := Heap.storeBytes_of_readable (encodeNatLE 4 ordinal) unique
    (by simpa only [Heap.Readable, encodeNatLE, List.length_map, List.length_range, Nat.add_zero] using
      readable.subrange (start := 0) (length := 4) (by omega))
  have loaded : after.loadBytes address 4 = .ok (encodeNatLE 4 ordinal) := by
    simpa only [encodeNatLE, List.length_map, List.length_range] using effect.loadBytes
  refine ⟨after, ?_, ?_, (HeapRegionWrite.ofBytes effect).enlarge (Nat.le_refl _) (by
    simp only [encodeNatLE, List.length_map, List.length_range]; omega)⟩
  · simp [writeNativeValue, declaration, variant, stored]
  · exact NativeSnapshot.enumEmpty declaration variant fits loaded

theorem NativeStoreSpec.enumSingle {id : TypeId}
    (declaration : program.enumeration? id = some enumeration)
    (variant : enumeration.variants[ordinal]? = some [type]) (fits : ordinal < 256 ^ 4) (wide : 8 ≤ size)
    (payload : NativeStoreSpec fuel program type value size) :
    NativeStoreSpec (fuel + 1) program (.enumeration id) (.enumeration id ordinal [value]) (8 + size) := by
  intro state heap address room readable unique
  rw [show address + 8 - (8 + size) = address - size by omega] at readable ⊢
  have tagRoom := readable.subrange (start := size) (length := 4) (by omega)
  rw [show address - size + size = address by omega] at tagRoom
  obtain ⟨tagged, tagStore, tagEffect⟩ := Heap.storeBytes_of_readable (encodeNatLE 4 ordinal) unique
    (by simpa only [Heap.Readable, encodeNatLE, List.length_map, List.length_range] using tagRoom)
  have tagRead : tagged.loadBytes address 4 = .ok (encodeNatLE 4 ordinal) := by
    simpa only [encodeNatLE, List.length_map, List.length_range] using tagEffect.loadBytes
  have payloadRoom := (tagEffect.readable readable).subrange (start := 0) (length := size) (by omega)
  rw [Nat.add_zero, show address - size = address - 8 + 8 - size by omega] at payloadRoom
  obtain ⟨after, payloadStore, payloadSnapshot, payloadEffect⟩ := payload state tagged (address - 8)
    (by omega) payloadRoom tagEffect.unique
  have tagPreserved := payloadEffect.loadBytes tagRead (Or.inr (by omega))
  refine ⟨after, ?_, ?_, ((HeapRegionWrite.ofBytes tagEffect).enlarge (by omega) (by
      simp only [encodeNatLE, List.length_map, List.length_range]; omega)).trans
    (payloadEffect.enlarge (by omega) (by omega))⟩
  · simp only [writeNativeValue, declaration, variant, tagStore]
    dsimp only [Bind.bind, Except.bind]
    simpa [NativeLayout.wordBytes, List.range_succ, List.foldlM, wordBelow,
      show 8 ≤ address by omega] using payloadStore
  · exact NativeSnapshot.enumSingle declaration variant fits tagPreserved (by omega) payloadSnapshot

end Lanius.Semantics
