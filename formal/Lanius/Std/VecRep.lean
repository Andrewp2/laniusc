import Lanius.Std.VecTemplate
import Lanius.Std.CoreRun
import Lanius.Semantics.NativeStore

/-! # A Core vector represents a list

`VecRep P T size vec h v xs`: the Core value `v` is a `Vec<T>` whose storage
in heap `h` holds the elements `xs`, read with Core's own
`readRawSliceIndex` through the view `slots(v)` builds. Each element's read
depends only on the bytes of its own slot (`ReadsWithin`), so a store to one
element or outside the buffer keeps the others.

Element types (`ElemKind`): packed `i32` (size 4, element i at
`storage + 4i`), or a struct or enum of `w` native words (size `8w`, element
0 at the top of the storage, element i `8wi` bytes below it), as
`core::mem::typed_slice_from_storage` lays them out. -/

namespace Lanius.Std

open Lanius Lanius.Core Lanius.Semantics Lanius.Memory

/-- The element types the templates cover, with `core::mem::size_of<T>()`. -/
inductive ElemKind (P : Program) : Ty → Nat → Prop
  | i32 : ElemKind P i32Ty 4
  | structure {id w : Nat} (layout : NativeLayout.valueWords? P (.structure id) = some w)
      (positive : 0 < w) (bounded : w ≤ 4096) : ElemKind P (.structure id) (8 * w)
  | enumeration {id w : Nat} (layout : NativeLayout.valueWords? P (.enumeration id) = some w)
      (positive : 0 < w) (bounded : w ≤ 4096) : ElemKind P (.enumeration id) (8 * w)

/-- Which slot of the storage element `i` of `cap` occupies, counting slots up
from the storage pointer. -/
def slotIndex (T : Ty) (cap i : Nat) : Nat := if T = i32Ty then i else cap - 1 - i

/-- The first byte of element `i`'s slot. -/
def slotLo (T : Ty) (size p cap i : Nat) : Nat := p + size * slotIndex T cap i

/-- The descriptor address of `typed_slice_from_storage(p, cap)`. -/
def viewAddr (T : Ty) (size p cap : Nat) : Nat :=
  if T = i32Ty ∨ cap = 0 then p else p + size * cap - 8

/-- A slot's first byte from the address of the value in it: an `i32` is at
the start of its slot, a nominal value's word 0 is the top word. -/
def slotOf (T : Ty) (size base : Nat) : Nat := if T = i32Ty then base else base + 8 - size

/-- Where element `i` is read: `slotLo` for `i32`, the slot's top word else. -/
def elemBase (T : Ty) (size p cap i : Nat) : Nat :=
  if T = i32Ty then slotLo T size p cap i else slotLo T size p cap i + size - 8

/-- A block's allocation metadata, without its bytes. -/
def Block.shape (block : Block) : Block := { block with bytes := [] }

/-- `n` bytes at `p`: the start of a live, owned, 8-aligned block of exactly
`n` bytes, all readable, below the 64-bit address limit. -/
def Buffer (h : Heap) (p n : Nat) : Prop :=
  (h.containingBlock? p).map Block.shape =
      some { base := p, size := n, alignment := 8, bytes := [], live := true, owned := true } ∧
    h.Readable p n ∧ p % 8 = 0 ∧ p + n < 2 ^ 64

/-- `v` is a `Vec<T>` (struct id `vec`) holding `xs` in heap `h`. -/
def VecRep (P : Program) (T : Ty) (size : Nat) (vec : TypeId) (h : Heap) (v : Value)
    (xs : List Value) : Prop :=
  ∃ p cap : Nat, v = .structure vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap] ∧
    xs.length ≤ cap ∧ cap < 2 ^ 31 ∧ (0 < cap → Buffer h p (size * cap)) ∧
    ∀ i (inside : i < xs.length) (other : State),
      ReadsWithin h other.heap (slotLo T size p cap i) size →
        readRawSliceIndex P other T (viewAddr T size p cap) cap i = .ok xs[i]

/-- A value that a store of `T` writes and reads back from its slot alone. -/
def ElemStore (P : Program) (T : Ty) (size : Nat) (x : Value) : Prop :=
  ∀ (st : State) (h : Heap) (base : Nat), size ≤ base + 8 →
    h.Readable (slotOf T size base) size → HeapBlockBasesUnique h →
    ∃ h', writeNativeValue NativeLayout.maxDepth P st h T base x = .ok h' ∧
      (∀ other : Heap, ReadsWithin h' other (slotOf T size base) size →
        readNativeValue NativeLayout.maxDepth P other T base = .ok x) ∧
      HeapRegionWrite h h' (slotOf T size base) size

theorem ElemStore.i32 (P : Program) (word : BitVec 32) :
    ElemStore P i32Ty 4 (.signed .i32 word.toInt) := by
  intro st h base _ readable unique
  have slot : slotOf i32Ty 4 base = base := if_pos rfl
  rw [slot] at readable ⊢
  obtain ⟨h', stored, effect⟩ := Heap.storeBytes_of_readable (i32Bytes word.toInt) unique
    (by simpa only [Heap.Readable, i32Bytes, List.length_map, List.length_range, Nat.add_zero] using readable)
  refine ⟨h', stored, ?_, ?_⟩
  · intro other reads
    have loaded : h'.loadBytes base 4 = .ok (i32Bytes word.toInt) := by
      simpa only [i32Bytes, List.length_map, List.length_range] using effect.loadBytes
    have loaded := reads _ _ _ (Nat.le_refl _) (Nat.le_refl _) loaded
    simp only [i32Ty, NativeLayout.maxDepth, readNativeValue, loadNatLE, loaded]
    change Except.ok (Value.signed .i32 (if decodeNatLE (i32Bytes word.toInt) ≥ 2 ^ 31 then
      Int.ofNat (decodeNatLE (i32Bytes word.toInt)) - 2 ^ 32 else
      Int.ofNat (decodeNatLE (i32Bytes word.toInt)))) = _
    rw [decodeNatLE_i32Bytes]
    congr 2
    simp [BitVec.toInt_eq_msb_cond, BitVec.msb_eq_decide]
  · simpa only [i32Bytes, List.length_map, List.length_range] using HeapRegionWrite.ofBytes effect

/-- A nominal element with a proved native store (`NativeStoreSpec`, e.g.
`NativeStoreSpec.record`) is storable. -/
theorem ElemStore.ofNative {P : Program} {T : Ty} {size : Nat} {x : Value} (nominal : T ≠ i32Ty)
    (spec : NativeStoreSpec NativeLayout.maxDepth P T x size) : ElemStore P T size x := by
  intro st h base room readable unique
  simp only [slotOf, if_neg nominal] at readable ⊢
  exact spec st h base room readable unique

/-! ## Layout facts -/

theorem ElemKind.size_pos {P : Program} {T : Ty} {size : Nat} (kind : ElemKind P T size) : 0 < size := by
  cases kind <;> omega

theorem ElemKind.size_le {P : Program} {T : Ty} {size : Nat} (kind : ElemKind P T size) :
    size ≤ 32768 := by
  cases kind <;> omega

theorem ElemKind.size_eight {P : Program} {T : Ty} {size : Nat} (kind : ElemKind P T size)
    (nominal : T ≠ i32Ty) : 8 ≤ size := by
  cases kind with
  | i32 => exact absurd rfl nominal
  | «structure» _ positive _ => omega
  | enumeration _ positive _ => omega

theorem slotIndex_lt {T : Ty} {cap i : Nat} (inside : i < cap) : slotIndex T cap i < cap := by
  unfold slotIndex; split <;> omega

theorem slotIndex_inj {T : Ty} {cap i j : Nat} (hi : i < cap) (hj : j < cap)
    (same : slotIndex T cap i = slotIndex T cap j) : i = j := by
  unfold slotIndex at same; split at same <;> omega

theorem slotOf_elemBase {T : Ty} {size p cap i : Nat} (eight : T ≠ i32Ty → 8 ≤ size) :
    slotOf T size (elemBase T size p cap i) = slotLo T size p cap i := by
  unfold slotOf elemBase
  by_cases h : T = i32Ty
  · simp [h]
  · have := eight h
    simp only [h, if_false]
    omega

/-- The nominal view's arithmetic: element `i` of `cap` has word 0 at
`viewAddr - 8wi`, which is `elemBase`. -/
private theorem nominal_arith {w p cap i : Nat} (positive : 0 < w) (inside : i < cap) :
    (i * w + w - 1) * 8 ≤ p + 8 * w * cap - 8 ∧
    p + 8 * w * cap - 8 - i * w * 8 = p + 8 * w * (cap - 1 - i) + 8 * w - 8 := by
  have h1 : (cap - 1 - i) + i + 1 = cap := by omega
  have h2 : 8 * w * cap = 8 * w * (cap - 1 - i) + 8 * w * i + 8 * w := by
    conv => lhs; rw [← h1]
    rw [Nat.mul_add, Nat.mul_add, Nat.mul_one]
  have h3 : i * w * 8 = 8 * w * i := by rw [Nat.mul_comm i w, Nat.mul_comm (w * i) 8, ← Nat.mul_assoc]
  have h4 : (i * w + w - 1) * 8 = 8 * w * i + 8 * w - 8 := by
    rw [Nat.sub_mul, Nat.add_mul, h3, Nat.mul_comm w 8, Nat.one_mul]
  have : 8 ≤ 8 * w := by omega
  rw [h2, h4, h3]
  omega

/-- Element `i` of the storage view is at `elemBase`. -/
theorem elementAddress {P : Program} {T : Ty} {size p cap i : Nat} (kind : ElemKind P T size)
    (inside : i < cap) :
    rawSliceElementAddress? P T (viewAddr T size p cap) i = .ok (elemBase T size p cap i) := by
  cases kind with
  | i32 =>
      simp [rawSliceElementAddress?, viewAddr, elemBase, slotLo, slotIndex, i32Ty, Nat.mul_comm]
  | «structure» layout positive _ =>
      have ne : cap ≠ 0 := by omega
      obtain ⟨room, address⟩ := nominal_arith (p := p) positive inside
      apply rawSliceElementAddress_of_layout (by rfl) layout positive
      · simpa only [viewAddr, i32Ty, ne, reduceCtorEq, false_or, if_false] using room
      · simpa only [viewAddr, elemBase, slotLo, slotIndex, i32Ty, ne, reduceCtorEq, false_or,
          if_false] using address
  | enumeration layout positive _ =>
      have ne : cap ≠ 0 := by omega
      obtain ⟨room, address⟩ := nominal_arith (p := p) positive inside
      apply rawSliceElementAddress_of_layout (by rfl) layout positive
      · simpa only [viewAddr, i32Ty, ne, reduceCtorEq, false_or, if_false] using room
      · simpa only [viewAddr, elemBase, slotLo, slotIndex, i32Ty, ne, reduceCtorEq, false_or,
          if_false] using address

theorem readRawSliceIndex_elem {P : Program} {T : Ty} {size p cap i : Nat} (st : State)
    (kind : ElemKind P T size) (inside : i < cap) :
    readRawSliceIndex P st T (viewAddr T size p cap) cap i =
      readNativeValue NativeLayout.maxDepth P st.heap T (elemBase T size p cap i) := by
  simp only [readRawSliceIndex, Nat.not_le_of_lt inside, if_false, elementAddress kind inside]
  rfl

theorem ReadsWithin.refl (h : Heap) (lo n : Nat) : ReadsWithin h h lo n :=
  fun _ _ _ _ _ read => read

theorem ReadsWithin.trans {a b c : Heap} {lo n : Nat} (first : ReadsWithin a b lo n)
    (second : ReadsWithin b c lo n) : ReadsWithin a c lo n :=
  fun pointer count bytes lower upper read => second pointer count bytes lower upper (first pointer count bytes lower upper read)

/-- A region write keeps reads within any range apart from it. -/
theorem HeapRegionWrite.readsApart {h h' : Heap} {lo n lo' n' : Nat} (effect : HeapRegionWrite h h' lo n)
    (apart : lo' + n' ≤ lo ∨ lo + n ≤ lo') : ReadsWithin h h' lo' n' :=
  fun _ _ _ lower upper read => effect.loadBytes read (by omega)

/-- Slots of different elements do not overlap. -/
theorem slots_apart {T : Ty} {size p cap i j : Nat} (hi : i < cap) (hj : j < cap) (ne : i ≠ j) :
    slotLo T size p cap j + size ≤ slotLo T size p cap i ∨ slotLo T size p cap i + size ≤ slotLo T size p cap j := by
  unfold slotLo
  have different : slotIndex T cap i ≠ slotIndex T cap j := fun same => ne (slotIndex_inj hi hj same)
  rcases Nat.lt_or_gt_of_ne different with lt | lt
  · right
    have := Nat.mul_le_mul_left size (Nat.succ_le_of_lt lt)
    rw [Nat.mul_succ] at this
    omega
  · left
    have := Nat.mul_le_mul_left size (Nat.succ_le_of_lt lt)
    rw [Nat.mul_succ] at this
    omega

/-- A slot lies inside the buffer. -/
theorem slot_inside {T : Ty} {size p cap i : Nat} (inside : i < cap) :
    p ≤ slotLo T size p cap i ∧ slotLo T size p cap i + size ≤ p + size * cap := by
  unfold slotLo
  have := Nat.mul_le_mul_left size (Nat.succ_le_of_lt (slotIndex_lt (T := T) inside))
  rw [Nat.mul_succ] at this
  omega

/-! ## Region writes keep the buffer -/

theorem containingBlock_shape {h h' : Heap} (layout : h'.blocks.map Block.shape = h.blocks.map Block.shape)
    (a : Nat) : (h'.containingBlock? a).map Block.shape = (h.containingBlock? a).map Block.shape := by
  unfold Heap.containingBlock?
  have key : ∀ (xs ys : List Block), xs.map Block.shape = ys.map Block.shape →
      (xs.find? fun block => block.live && block.base ≤ a && a < block.base + block.size).map Block.shape =
      (ys.find? fun block => block.live && block.base ≤ a && a < block.base + block.size).map Block.shape := by
    intro xs
    induction xs with
    | nil => intro ys same; cases ys with
      | nil => rfl
      | cons _ _ => simp at same
    | cons x xs ih =>
      intro ys same
      cases ys with
      | nil => simp at same
      | cons y ys =>
        simp only [List.map_cons, List.cons.injEq] at same
        obtain ⟨head, tail⟩ := same
        have live := congrArg (fun b : Block => b.live) head
        have base := congrArg (fun b : Block => b.base) head
        have size := congrArg (fun b : Block => b.size) head
        simp only [Block.shape] at live base size
        simp only [List.find?_cons, live, base, size]
        split
        · simp [head]
        · exact ih ys tail
  exact key _ _ layout

theorem Buffer.afterWrite {h h' : Heap} {p n lo m : Nat} (buffer : Buffer h p n)
    (effect : HeapRegionWrite h h' lo m) : Buffer h' p n := by
  obtain ⟨found, readable, aligned, bound⟩ := buffer
  refine ⟨?_, fun _ inside => ?_, aligned, bound⟩
  · rw [containingBlock_shape effect.layout p]; exact found
  · exact effect.readable _ _ readable _ inside

end Lanius.Std
