import Lanius.Semantics.NativeRecordStore
import Lanius.Mini.ElementLayout
import Lanius.Faithful.Sim.Rel

/-! # Native stores of the scalars and of enums

Core writes a word scalar as its little-endian bytes and reads them back
(`NativeStoreSpec.bytes` and its instances); an enum is its tag word, then its
payload's fields below it, each by its own store (`NativeStoreSpec.variant`).
`words?` keeps its value with more fuel (`words_mono`). -/

namespace Lanius.Faithful

open Lanius.Mini
open Lanius.Core (Value)
open Lanius.Semantics
open Lanius.Memory

section
variable {fuel : Nat} {program : Core.Program}

/-- A one-word scalar that Core writes as `bytes` and reads back from them. -/
theorem NativeStoreSpec.bytes {ty : Core.Ty} {v : Value} (bytes : List UInt8) (len : bytes.length ≤ 8)
    (write : ∀ state heap address, writeNativeValue (fuel + 1) program state heap ty address v =
      heap.storeBytes address bytes)
    (read : ∀ heap address, heap.loadBytes address bytes.length = .ok bytes →
      readNativeValue (fuel + 1) program heap ty address = .ok v) :
    NativeStoreSpec (fuel + 1) program ty v 8 := by
  intro state heap address _ readable unique
  rw [Nat.add_sub_cancel] at readable ⊢
  obtain ⟨after, stored, effect⟩ := Heap.storeBytes_of_readable bytes unique
    (fun index inside => readable index (by omega))
  refine ⟨after, (write state heap address).trans stored, ?_,
    (HeapRegionWrite.ofBytes effect).enlarge (Nat.le_refl _) (by omega)⟩
  intro other reads
  exact read other address (reads _ _ _ (by omega) (by omega) effect.loadBytes)

theorem encodeNatLE_length (width value : Nat) : (encodeNatLE width value).length = width := by
  simp [encodeNatLE]

theorem NativeStoreSpec.rawPtr {a : Nat} (fits : a < 2 ^ 64) :
    NativeStoreSpec (fuel + 1) program (.scalar .rawPtr) (.pointer a) 8 :=
  NativeStoreSpec.bytes (encodeNatLE 8 a) (by simp [encodeNatLE_length]) (fun _ _ _ => rfl) fun heap address loaded => by
    rw [encodeNatLE_length] at loaded
    simp only [readNativeValue, loadNatLE_of_encoded loaded (by omega)]
    rfl

theorem NativeStoreSpec.isize {n : Int} (low : -2 ^ 63 ≤ n) (high : n < 2 ^ 63) :
    NativeStoreSpec (fuel + 1) program (.scalar (.signed .isize)) (.signed .isize n) 8 := by
  have nonneg := Int.emod_nonneg n (by decide : (2 : Int) ^ 64 ≠ 0)
  have lt := Int.emod_lt_of_pos n (by decide : (0 : Int) < 2 ^ 64)
  refine NativeStoreSpec.bytes (encodeNatLE 8 (Int.toNat (n % 2 ^ 64))) (by simp [encodeNatLE_length])
    (fun _ _ _ => rfl) fun heap address loaded => ?_
  rw [encodeNatLE_length] at loaded
  simp only [readNativeValue, loadNatLE_of_encoded loaded (by omega)]
  have : signed64 (Int.toNat (n % 2 ^ 64)) = n := by
    simp only [signed64, Int.ofNat_eq_natCast, Int.toNat_of_nonneg nonneg]
    split <;> omega
  exact congrArg (fun x => Except.ok (Value.signed .isize x)) this

theorem NativeStoreSpec.unsigned {k : UintTy} {n : Nat} (fits : n < 2 ^ k.width) :
    NativeStoreSpec (fuel + 1) program (.scalar (.unsigned k.toCore)) (.unsigned k.toCore n) 8 := by
  cases k with
  | uint8 =>
    simp only [UintTy.width] at fits
    refine NativeStoreSpec.bytes (encodeNatLE 4 n) (by simp [encodeNatLE_length]) (fun _ _ _ => rfl)
      fun heap address loaded => ?_
    rw [encodeNatLE_length] at loaded
    simp only [UintTy.toCore, readNativeValue, loadNatLE_of_encoded loaded (by omega)]
    dsimp only [Bind.bind, Except.bind]
    rw [if_pos fits]
    rfl
  | uint32 =>
    simp only [UintTy.width] at fits
    refine NativeStoreSpec.bytes (encodeNatLE 4 n) (by simp [encodeNatLE_length]) (fun _ _ _ => rfl)
      fun heap address loaded => ?_
    rw [encodeNatLE_length] at loaded
    simp only [UintTy.toCore, readNativeValue, loadNatLE_of_encoded loaded (by omega)]
    rfl
  | uint64 =>
    simp only [UintTy.width] at fits
    refine NativeStoreSpec.bytes (encodeNatLE 8 n) (by simp [encodeNatLE_length]) (fun _ _ _ => rfl)
      fun heap address loaded => ?_
    rw [encodeNatLE_length] at loaded
    simp only [UintTy.toCore, readNativeValue, loadNatLE_of_encoded loaded (by omega)]
    rfl
  | usize =>
    simp only [UintTy.width] at fits
    refine NativeStoreSpec.bytes (encodeNatLE 8 n) (by simp [encodeNatLE_length]) (fun _ _ _ => rfl)
      fun heap address loaded => ?_
    rw [encodeNatLE_length] at loaded
    simp only [UintTy.toCore, readNativeValue, loadNatLE_of_encoded loaded (by omega)]
    rfl

theorem NativeStoreSpec.i32range {n : Int} (low : -2 ^ 31 ≤ n) (high : n < 2 ^ 31) :
    NativeStoreSpec (fuel + 1) program (.scalar (.signed .i32)) (.signed .i32 n) 8 := by
  have same : (BitVec.ofInt 32 n).toInt = n := by
    rw [BitVec.toInt_ofInt]
    simp [Int.bmod]
    omega
  have := NativeStoreSpec.i32 (fuel := fuel) (program := program) (BitVec.ofInt 32 n)
  rwa [same] at this

/-- A scalar of a source type other than `unit`. -/
theorem NativeStoreSpec.sty {t : SrcType} {v : Value} (s : STy t v) (notUnit : t ≠ .unit) :
    NativeStoreSpec (fuel + 1) program t.toCore v 8 := by
  cases t with
  | i32 => obtain ⟨n, rfl, low, high⟩ := s; exact NativeStoreSpec.i32range low high
  | bool => obtain ⟨b, rfl⟩ := s; exact NativeStoreSpec.boolean b
  | uint k => obtain ⟨n, rfl, fits⟩ := s; exact NativeStoreSpec.unsigned fits
  | isize => obtain ⟨n, rfl, low, high⟩ := s; exact NativeStoreSpec.isize low high
  | unit => exact absurd rfl notUnit
  | struct => exact s.elim
  | enum => exact s.elim
  | ptr => exact s.elim
  | slice => exact s.elim

end

/-! ## More fuel for `words?` -/

theorem mapM_option_mono {α β : Type} {f g : α → Option β} (each : ∀ x y, f x = some y → g x = some y) :
    ∀ {l : List α} {r : List β}, l.mapM f = some r → l.mapM g = some r
  | [], r, h => h
  | a :: rest, r, h => by
    obtain ⟨b, bs, hb, hbs, rfl⟩ := mapM_option_cons h
    simp only [List.mapM_cons, each a b hb, mapM_option_mono each hbs]
    rfl

theorem words_mono {P : Core.Program} : ∀ (a : Nat) {b : Nat} {t : Core.Ty} {w : Nat},
    NativeLayout.words? a P t = some w → a ≤ b → NativeLayout.words? b P t = some w
  | 0, _, _, _, h, _ => by simp [NativeLayout.words?] at h
  | a + 1, b, t, w, h, le => by
    obtain ⟨b, rfl⟩ : ∃ b', b = b' + 1 := ⟨b - 1, by omega⟩
    have each : ∀ x y, NativeLayout.words? a P x = some y → NativeLayout.words? b P x = some y :=
      fun x y hx => words_mono a hx (by omega)
    unfold NativeLayout.words? at h ⊢
    dsimp only at h ⊢
    split at h
    all_goals first
      | exact h
      | (simp at h; done)
      | skip
    · simp only [bind, Option.bind_eq_some_iff] at h ⊢
      obtain ⟨d, hd, ws, hws, rest⟩ := h
      exact ⟨d, hd, ws, mapM_option_mono each hws, rest⟩
    · simp only [bind, Option.bind_eq_some_iff] at h ⊢
      obtain ⟨d, hd, ps, hps, rest⟩ := h
      refine ⟨d, hd, ps, mapM_option_mono (fun fields y hy => ?_) hps, rest⟩
      simp only [Option.bind_eq_some_iff] at hy ⊢
      obtain ⟨ws, hws, rest'⟩ := hy
      exact ⟨ws, mapM_option_mono each hws, rest'⟩

/-! ## Enums -/

private theorem wordBelow_le {address offset : Nat} (le : offset ≤ address) :
    wordBelow address offset = .ok (address - offset) := by
  simp [wordBelow, le]

private theorem foldlM_congr {indices : List Nat} {left right : Memory.Heap → Nat → Except Trap Memory.Heap}
    (same : ∀ index ∈ indices, ∀ current, left current index = right current index) (heap : Memory.Heap) :
    indices.foldlM left heap = indices.foldlM right heap := by
  induction indices generalizing heap with
  | nil => rfl
  | cons index rest ih =>
    simp only [List.foldlM_cons]
    rw [same index (by simp)]
    congr 1
    funext current
    exact ih (fun item member => same item (by simp [member])) current

private theorem mapM_range_get (values : List Value) {read : Nat → Except Trap Value}
    (found : ∀ index, index < values.length → read index = .ok ((values[index]?).getD .unit)) :
    (List.range values.length).mapM read = .ok values := by
  have all : ∀ indices : List Nat, (∀ index ∈ indices, index < values.length) →
      indices.mapM read = .ok (indices.map fun index => (values[index]?).getD .unit) := by
    intro indices inside
    induction indices with
    | nil => rfl
    | cons index rest ih =>
      simp only [List.mapM_cons, found index (inside index (by simp)),
        ih (fun member present => inside member (by simp [present])), List.map_cons]
      rfl
  rw [all _ (fun index member => List.mem_range.mp member)]
  congr 1
  apply List.ext_getElem
  · simp
  · intro index left right
    simp only [List.getElem_map, List.getElem_range, List.getElem?_eq_getElem (by simpa using left),
      Option.getD_some]

section
variable {fuel size k : Nat} {program : Core.Program} {id : Nat} {decl : Core.EnumDecl} {types : List Core.Ty}
  {values : List Value} {offset width : Nat → Nat}

/-- Variant `k` of an enum: its tag in word 0, payload field `index` at
`offset index` bytes below, each field by its own store. -/
theorem NativeStoreSpec.variant
    (declaration : program.enumeration? id = some decl)
    (variant : decl.variants[k]? = some types) (fits : k < 256 ^ 4)
    (length : values.length = types.length)
    (locations : ∀ index, index < values.length → ∃ widths,
      ((types.take index).mapM fun member => NativeLayout.words? (NativeLayout.maxDepth - 1) program member) =
        some widths ∧ NativeLayout.wordBytes * (1 + widths.foldl (· + ·) 0) = offset index)
    (above : ∀ index, index < values.length → 8 ≤ offset index)
    (bounds : ∀ index, index < values.length → offset index + width index ≤ size)
    (wide : ∀ index, index < values.length → 8 ≤ width index)
    (ordered : ∀ left right, left < right → right < values.length → offset left + width left ≤ offset right)
    (room : 8 ≤ size)
    (codecs : ∀ index, index < values.length →
      NativeStoreSpec fuel program ((types[index]?).getD .unit) ((values[index]?).getD .unit) (width index)) :
    NativeStoreSpec (fuel + 1) program (.enumeration id) (.enumeration id k values) size := by
  by_cases empty : values.length = 0
  · have nil : types = [] := List.eq_nil_of_length_eq_zero (by omega)
    have vnil : values = [] := List.eq_nil_of_length_eq_zero empty
    subst nil vnil
    exact (NativeStoreSpec.enumEmpty declaration variant fits).enlarge room
  intro state heap address fitsAt readable unique
  have deep : 8 ≤ address := by
    have := above 0 (by omega); have := wide 0 (by omega); have := bounds 0 (by omega)
    omega
  have tagRoom := readable.subrange (start := size - 8) (length := 4) (by omega)
  rw [show address + 8 - size + (size - 8) = address by omega] at tagRoom
  obtain ⟨tagged, tagStore, tagEffect⟩ := Heap.storeBytes_of_readable (encodeNatLE 4 k) unique
    (fun index inside => tagRoom index (by rw [encodeNatLE_length] at inside; exact inside))
  have tagRead : tagged.loadBytes address 4 = .ok (encodeNatLE 4 k) := by
    simpa only [encodeNatLE_length] using tagEffect.loadBytes
  have payloadRoom := (tagEffect.readable readable).subrange (start := 0) (length := size - 8) (by omega)
  rw [Nat.add_zero, show address + 8 - size = address - 8 + 8 - (size - 8) by omega] at payloadRoom
  obtain ⟨after, run, snapshots, payloadEffect⟩ := storeNativeFields (fuel := fuel) (program := program)
    (type := fun index => (types[index]?).getD .unit) (value := fun index => (values[index]?).getD .unit)
    (offset := fun index => offset index - 8) (width := width) (size := size - 8) values.length codecs wide
    (fun index inside => by have := bounds index inside; have := above index inside; omega)
    (fun left right lt inside => by
      have := ordered left right lt inside; have := above left (by omega); omega)
    state tagged (address - 8) (by omega) payloadRoom tagEffect.unique
  have tagKept := payloadEffect.loadBytes tagRead (Or.inr (by omega))
  have fieldAt : ∀ index, index < values.length → address - 8 - (offset index - 8) = address - offset index := by
    intro index inside
    have := above index inside; have := bounds index inside; have := wide index inside
    omega
  refine ⟨after, ?_, ?_, ((HeapRegionWrite.ofBytes tagEffect).enlarge (by omega) (by
      rw [encodeNatLE_length]; omega)).trans (payloadEffect.enlarge (by omega) (by omega))⟩
  · simp only [writeNativeValue, declaration, variant, bne_self_eq_false, Bool.false_eq_true, if_false, length]
    dsimp only [Bind.bind, Except.bind]
    rw [tagStore]
    dsimp only
    rw [← length]
    refine (foldlM_congr (fun index member current => ?_) tagged).trans run
    have inside := List.mem_range.mp member
    obtain ⟨widths, hw, ho⟩ := locations index inside
    rw [List.getElem?_eq_getElem (show index < types.length by omega),
      List.getElem?_eq_getElem inside]
    simp only [hw, ho]
    have := bounds index inside; have := wide index inside
    rw [wordBelow_le (by omega), fieldAt index inside]
    simp only [Option.getD_some]
  · intro other reads
    have tag := reads _ _ _ (by omega) (by omega) tagKept
    have decoded : ∀ index, index < values.length → readNativeValue fuel program other
        ((types[index]?).getD .unit) (address - offset index) = .ok ((values[index]?).getD .unit) := by
      intro index inside
      have := bounds index inside; have := wide index inside; have := above index inside
      rw [← fieldAt index inside]
      exact snapshots index inside other (reads.narrow (by omega) (by omega))
    simp only [readNativeValue, declaration, loadNatLE_of_encoded tag fits]
    dsimp only [Bind.bind, Except.bind]
    simp only [variant]
    rw [← length]
    rw [mapM_range_get values (read := _) ?found]
    · rfl
    intro index inside
    obtain ⟨widths, hw, ho⟩ := locations index inside
    have := bounds index inside; have := wide index inside
    have hd := decoded index inside
    rw [List.getElem?_eq_getElem (show index < types.length by omega)] at hd ⊢
    simp only [hw, ho]
    rw [wordBelow_le (by omega)]
    exact hd

end

end Lanius.Faithful
