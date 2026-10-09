import Lanius.Semantics.NativeStore

namespace Lanius.Semantics

open Lanius.Core Lanius.Memory

def nativeSliceSupported (program : Program) : Ty → Bool
  | .scalar (.signed .i32) => true
  | .structure id => (program.structure? id).isSome
  | .enumeration id => (program.enumeration? id).isSome
  | _ => false

/-- Copy a supported raw slice's pointer and length, without touching its
    referent. Both words must fit their actual 64-bit native representation.
    Referent validity is a separate producer/consumer obligation. -/
theorem NativeStoreSpec.rawSlice
    (supported : nativeSliceSupported program element = true)
    (pointerFits : pointer < 256 ^ 8) (lengthFits : length < 256 ^ 8) :
    NativeStoreSpec (fuel + 1) program (.slice element) (.rawSlice element pointer length) 16 := by
  intro state heap address readable unique
  obtain ⟨middle, pointerStore, pointerEffect⟩ := Heap.storeBytes_of_readable (pointer := address) (encodeNatLE 8 pointer) unique
    (by simpa only [Heap.Readable, Nat.add_zero, encodeNatLE, List.length_map, List.length_range] using
      readable.subrange (start := 0) (length := 8) (by omega))
  obtain ⟨after, lengthStore, lengthEffect⟩ := Heap.storeBytes_of_readable (encodeNatLE 8 length) pointerEffect.unique
    (by simpa only [Heap.Readable, encodeNatLE, List.length_map, List.length_range] using
      (pointerEffect.readable readable).subrange (start := 8) (length := 8) (by omega))
  have pointerRead : middle.loadBytes address 8 = .ok (encodeNatLE 8 pointer) := by
    simpa only [encodeNatLE, List.length_map, List.length_range] using pointerEffect.loadBytes
  have pointerRead : after.loadBytes address 8 = .ok (encodeNatLE 8 pointer) :=
    (HeapRegionWrite.ofBytes lengthEffect).loadBytes pointerRead (Or.inl (by omega))
  have lengthRead : after.loadBytes (address + 8) 8 = .ok (encodeNatLE 8 length) := by
    simpa only [encodeNatLE, List.length_map, List.length_range] using lengthEffect.loadBytes
  refine ⟨after, ?_, ?_, ((HeapRegionWrite.ofBytes pointerEffect).enlarge (Nat.le_refl _) (by
    simp only [encodeNatLE, List.length_map, List.length_range]; omega)).trans
      ((HeapRegionWrite.ofBytes lengthEffect).enlarge (by omega) (by
        simp only [encodeNatLE, List.length_map, List.length_range]; omega))⟩
  · simp only [writeNativeValue, bne_self_eq_false, Bool.false_eq_true, ↓reduceIte, pointerStore]
    exact lengthStore
  · intro other reads
    have pointerRead := reads _ _ _ (Nat.le_refl _) (by omega) pointerRead
    have lengthRead := reads _ _ _ (by omega) (by omega) lengthRead
    simp only [readNativeValue]
    change (if !nativeSliceSupported program element then .error .typeMismatch else do
        let pointer ← loadNatLE other address 8
        let length ← loadNatLE other (address + 8) 8
        pure (Value.rawSlice element pointer length)) = .ok (.rawSlice element pointer length)
    simp only [supported, Bool.not_true, Bool.false_eq_true, ↓reduceIte,
      loadNatLE_of_encoded pointerRead pointerFits, loadNatLE_of_encoded lengthRead lengthFits]
    rfl

end Lanius.Semantics
