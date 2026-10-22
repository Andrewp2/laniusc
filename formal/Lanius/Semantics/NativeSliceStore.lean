import Lanius.Semantics.NativeStore

namespace Lanius.Semantics

open Lanius.Core Lanius.Memory

/-- A raw slice copy needs its element's native stride. -/
def nativeSliceSupported (program : Program) (element : Ty) : Bool :=
  (NativeLayout.elementStride? program element).isSome

private theorem strideWord_fits (stride : Int) : Int.toNat (stride % 2 ^ 64) < 256 ^ 8 := by
  have big : (256 : Nat) ^ 8 = 18446744073709551616 := by rfl
  have bigInt : (2 : Int) ^ 64 = 18446744073709551616 := by rfl
  rw [big, bigInt]
  omega

/-- Copy a supported raw slice's three words (data, length below it, then
    stride), without touching its referent. Both copied words must fit their
    actual 64-bit native representation. Referent validity is a separate
    producer/consumer obligation. -/
theorem NativeStoreSpec.rawSlice
    (supported : nativeSliceSupported program element = true)
    (pointerFits : pointer < 256 ^ 8) (lengthFits : length < 256 ^ 8) :
    NativeStoreSpec (fuel + 1) program (.slice element) (.rawSlice element pointer length) 24 := by
  intro state heap address room readable unique
  obtain ⟨stride, hs⟩ := Option.isSome_iff_exists.mp supported
  rw [show address + 8 - 24 = address - 16 by omega] at readable ⊢
  have pointerRoom := readable.subrange (start := 16) (length := 8) (by omega)
  rw [show address - 16 + 16 = address by omega] at pointerRoom
  obtain ⟨middle, pointerStore, pointerEffect⟩ := Heap.storeBytes_of_readable (pointer := address)
    (encodeNatLE 8 pointer) unique
    (by simpa only [Heap.Readable, encodeNatLE, List.length_map, List.length_range] using pointerRoom)
  have lengthRoom := (pointerEffect.readable readable).subrange (start := 8) (length := 8) (by omega)
  rw [show address - 16 + 8 = address - 8 by omega] at lengthRoom
  obtain ⟨upper, lengthStore, lengthEffect⟩ := Heap.storeBytes_of_readable (pointer := address - 8)
    (encodeNatLE 8 length) pointerEffect.unique
    (by simpa only [Heap.Readable, encodeNatLE, List.length_map, List.length_range] using lengthRoom)
  have strideRoom := (lengthEffect.readable (pointerEffect.readable readable)).subrange
    (start := 0) (length := 8) (by omega)
  rw [Nat.add_zero] at strideRoom
  obtain ⟨after, strideStore, strideEffect⟩ := Heap.storeBytes_of_readable (pointer := address - 16)
    (encodeNatLE 8 (Int.toNat (stride % 2 ^ 64))) lengthEffect.unique
    (by simpa only [Heap.Readable, encodeNatLE, List.length_map, List.length_range] using strideRoom)
  have pointerRead : middle.loadBytes address 8 = .ok (encodeNatLE 8 pointer) := by
    simpa only [encodeNatLE, List.length_map, List.length_range] using pointerEffect.loadBytes
  have pointerRead : upper.loadBytes address 8 = .ok (encodeNatLE 8 pointer) :=
    (HeapRegionWrite.ofBytes lengthEffect).loadBytes pointerRead (Or.inr (by
      simp only [encodeNatLE, List.length_map, List.length_range]; omega))
  have pointerRead : after.loadBytes address 8 = .ok (encodeNatLE 8 pointer) :=
    (HeapRegionWrite.ofBytes strideEffect).loadBytes pointerRead (Or.inr (by
      simp only [encodeNatLE, List.length_map, List.length_range]; omega))
  have lengthRead : upper.loadBytes (address - 8) 8 = .ok (encodeNatLE 8 length) := by
    simpa only [encodeNatLE, List.length_map, List.length_range] using lengthEffect.loadBytes
  have lengthRead : after.loadBytes (address - 8) 8 = .ok (encodeNatLE 8 length) :=
    (HeapRegionWrite.ofBytes strideEffect).loadBytes lengthRead (Or.inr (by
      simp only [encodeNatLE, List.length_map, List.length_range]; omega))
  have strideRead : after.loadBytes (address - 16) 8 = .ok (encodeNatLE 8 (Int.toNat (stride % 2 ^ 64))) := by
    simpa only [encodeNatLE, List.length_map, List.length_range] using strideEffect.loadBytes
  have above8 : (8 ≤ address) = True := eq_true (by omega)
  have above16 : (16 ≤ address) = True := eq_true (by omega)
  refine ⟨after, ?_, ?_, (((HeapRegionWrite.ofBytes pointerEffect).enlarge (by omega) (by
    simp only [encodeNatLE, List.length_map, List.length_range]; omega)).trans
      ((HeapRegionWrite.ofBytes lengthEffect).enlarge (by omega) (by
        simp only [encodeNatLE, List.length_map, List.length_range]; omega))).trans
      ((HeapRegionWrite.ofBytes strideEffect).enlarge (by omega) (by
        simp only [encodeNatLE, List.length_map, List.length_range]; omega))⟩
  · simp only [writeNativeValue, bne_self_eq_false, Bool.false_eq_true, ↓reduceIte, hs, pointerStore,
      wordBelow, above8, above16]
    dsimp only [Bind.bind, Except.bind]
    rw [lengthStore]
    exact strideStore
  · intro other reads
    have pointerRead := reads _ _ _ (by omega) (by omega) pointerRead
    have lengthRead := reads _ _ _ (by omega) (by omega) lengthRead
    have strideRead := reads _ _ _ (by omega) (by omega) strideRead
    simp only [readNativeValue, hs, wordBelow, above8, above16, ↓reduceIte,
      loadNatLE_of_encoded pointerRead pointerFits, loadNatLE_of_encoded lengthRead lengthFits,
      loadNatLE_of_encoded strideRead (strideWord_fits stride)]
    dsimp only [Bind.bind, Except.bind]
    rw [loadNatLE_of_encoded lengthRead lengthFits, loadNatLE_of_encoded strideRead (strideWord_fits stride)]
    simp only [↓reduceIte]
    rfl

end Lanius.Semantics
