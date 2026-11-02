module

public import Lanius.Mini.Source

/-! Frame memory and the places Core's references name (F5, SEMANTIC_DECISIONS
"Addressed locals").

A reference in Core names a cell and a projection path into its value. When
the verified compiler passes a reference, the value at that place lives in
frame memory, one 64-bit word per slot from an address: the same layout the
value has in a function's slots, so `ty.HoldsAt v (hp.words address) 0` says
the words represent it. `FrameCorr` carries those places beside `Corr` and
`HeapCorr`: each one's value is in Core's cell, its words are in the mini
heap between the frame pointer and the top, and nothing else writes there.
-/

@[expose] public section

namespace Lanius.Mini

open Lanius.Core (Value ValueProjection)
open Lanius.Semantics (State)

/-! ## Bytes and words -/

theorem Heap.write_bytes (hp : Heap) (address : Nat) (byte : UInt8) (a : Nat) :
    (hp.write address byte).bytes a = if a = address then byte else hp.bytes a := rfl

/-- `writeLE` changes the `count` bytes from `address` and no others. -/
theorem Heap.writeLE_bytes_outside : ∀ (hp : Heap) (address value count a : Nat),
    (a < address ∨ address + count ≤ a) → (hp.writeLE address value count).bytes a = hp.bytes a
  | _, _, _, 0, _, _ => rfl
  | hp, address, value, count + 1, a, outside => by
    simp only [Heap.writeLE]
    rw [Heap.writeLE_bytes_outside _ _ _ _ _ (by omega), Heap.write_bytes, if_neg (by omega)]

theorem Heap.readLE_congr {hp hp' : Heap} : ∀ {address count : Nat},
    (∀ a, address ≤ a → a < address + count → hp'.bytes a = hp.bytes a) →
    hp'.readLE address count = hp.readLE address count
  | _, 0, _ => rfl
  | address, count + 1, same => by
    simp only [Heap.readLE]
    rw [same address (Nat.le_refl _) (by omega),
      Heap.readLE_congr (fun a lo hi => same a (by omega) (by omega))]

/-- Reading back what `writeLE` wrote gives the value's low `count` bytes. -/
theorem Heap.readLE_writeLE : ∀ (hp : Heap) (address value count : Nat),
    (hp.writeLE address value count).readLE address count = value % 256 ^ count
  | _, _, value, 0 => by simp [Heap.readLE, Heap.writeLE, Nat.mod_one]
  | hp, address, value, count + 1 => by
    simp only [Heap.writeLE, Heap.readLE]
    rw [Heap.writeLE_bytes_outside _ _ _ _ _ (.inl (Nat.lt_succ_self _)), Heap.write_bytes, if_pos rfl,
      Heap.readLE_writeLE, UInt8.toNat_ofNat']
    have split : value % 256 ^ (count + 1) = value % 256 + 256 * (value / 256 % 256 ^ count) := by
      rw [Nat.pow_succ', Nat.mod_mul]
    rw [split]

/-- The 8-byte words of the mini heap from `address`, as slots. -/
def Heap.words (hp : Heap) (address : Nat) : Env :=
  fun slot => BitVec.ofNat 64 (hp.readLE (address + 8 * slot) 8)

/-- The words of two heaps agree where their bytes do. -/
theorem Heap.words_congr {hp hp' : Heap} {address count : Nat}
    (same : ∀ a, address ≤ a → a < address + 8 * count → hp'.bytes a = hp.bytes a) :
    ∀ i < count, hp'.words address (0 + i) = hp.words address (0 + i) := by
  intro i lt
  simp only [Heap.words, Nat.zero_add]
  rw [Heap.readLE_congr (fun a lo hi => same a (by omega) (by omega))]

/-- A value's representation in words depends only on its words' bytes. -/
theorem SrcType.HoldsAt.words_congr {ty : SrcType} {v : Value} {hp hp' : Heap} {address : Nat}
    (holds : ty.HoldsAt v (hp.words address) 0)
    (same : ∀ a, address ≤ a → a < address + 8 * ty.size → hp'.bytes a = hp.bytes a) :
    ty.HoldsAt v (hp'.words address) 0 :=
  holds.congr (Heap.words_congr same)

/-! ## Storing slots as words -/

/-- `count` slots of `env` from `slot`, stored as 8-byte words from `address`:
what a call does before it passes a place's address. -/
def Heap.storeSlots (hp : Heap) (address : Nat) (env : Env) (slot : Nat) : Nat → Heap
  | 0 => hp
  | count + 1 => (hp.writeLE address (env slot).toNat 8).storeSlots (address + 8) env (slot + 1) count

theorem Heap.storeSlots_bytes_outside : ∀ (hp : Heap) (address : Nat) (env : Env) (slot count a : Nat),
    (a < address ∨ address + 8 * count ≤ a) → (hp.storeSlots address env slot count).bytes a = hp.bytes a
  | _, _, _, _, 0, _, _ => rfl
  | hp, address, env, slot, count + 1, a, outside => by
    simp only [Heap.storeSlots]
    rw [Heap.storeSlots_bytes_outside _ _ _ _ _ _ (by omega), Heap.writeLE_bytes_outside _ _ _ _ _ (by omega)]

theorem Heap.storeSlots_top : ∀ (hp : Heap) (address : Nat) (env : Env) (slot count : Nat),
    (hp.storeSlots address env slot count).top = hp.top ∧ (hp.storeSlots address env slot count).fsp = hp.fsp ∧
      (hp.storeSlots address env slot count).limit = hp.limit ∧
      (hp.storeSlots address env slot count).cursor = hp.cursor ∧
      (hp.storeSlots address env slot count).io = hp.io
  | _, _, _, _, 0 => ⟨rfl, rfl, rfl, rfl, rfl⟩
  | hp, address, env, slot, count + 1 => by
    simp only [Heap.storeSlots]
    obtain ⟨t, f, l, c, i⟩ := Heap.storeSlots_top (hp.writeLE address (env slot).toNat 8) (address + 8) env (slot + 1) count
    rw [t, f, l, c, i, (Heap.writeLE_top _ _ _ _).1, (Heap.writeLE_top _ _ _ _).2, (Heap.writeLE_limit _ _ _ _).1,
      (Heap.writeLE_limit _ _ _ _).2, Heap.writeLE_io]
    exact ⟨rfl, rfl, rfl, rfl, rfl⟩

/-- The stored words are the slots. -/
theorem Heap.storeSlots_words : ∀ (hp : Heap) (address : Nat) (env : Env) (slot count i : Nat), i < count →
    (hp.storeSlots address env slot count).words address i = env (slot + i)
  | _, _, _, _, 0, _, lt => absurd lt (Nat.not_lt_zero _)
  | hp, address, env, slot, count + 1, 0, _ => by
    simp only [Heap.words, Heap.storeSlots, Nat.mul_zero, Nat.add_zero]
    rw [Heap.readLE_congr (hp := hp.writeLE address (env slot).toNat 8)
      (fun a _ hi => Heap.storeSlots_bytes_outside _ _ _ _ _ _ (.inl hi)), Heap.readLE_writeLE]
    apply BitVec.eq_of_toNat_eq
    simp only [BitVec.toNat_ofNat]
    have := (env slot).isLt
    rw [Nat.mod_eq_of_lt (show (env slot).toNat < 256 ^ 8 by simpa using this), Nat.mod_eq_of_lt this]
  | hp, address, env, slot, count + 1, i + 1, lt => by
    have := Heap.storeSlots_words (hp.writeLE address (env slot).toNat 8) (address + 8) env (slot + 1) count i (by omega)
    simp only [Heap.words, Heap.storeSlots] at this ⊢
    rw [show address + 8 * (i + 1) = address + 8 + 8 * i by omega, this, Nat.add_right_comm, Nat.add_assoc]

/-- A value in slots, stored as words, is represented by the words. -/
theorem SrcType.HoldsAt.storeSlots {ty : SrcType} {v : Value} {env : Env} {slot : Nat}
    (holds : ty.HoldsAt v env slot) (hp : Heap) (address : Nat) :
    ty.HoldsAt v ((hp.storeSlots address env slot ty.size).words address) 0 :=
  holds.congr fun i lt => by rw [Nat.zero_add, Heap.storeSlots_words _ _ _ _ _ _ lt]

/-- A value in words, loaded into slots, is represented by the slots. -/
theorem SrcType.HoldsAt.loadSlots {ty : SrcType} {v : Value} {hp : Heap} {address : Nat}
    (holds : ty.HoldsAt v (hp.words address) 0) {env : Env} {slot : Nat}
    (loaded : ∀ i < ty.size, env (slot + i) = hp.words address i) : ty.HoldsAt v env slot :=
  holds.congr fun i lt => by rw [Nat.zero_add]; exact loaded i lt

/-! ## The correspondence -/

/-- How a place's value sits in its bytes: a slot per 8-byte word (the
referent of a reference), or laniusc's native element layout (an array local
passed as a slice: i32 at stride 4, u8 at stride 1, other scalars as words,
structs as laniusc lays them out; SEMANTIC_DECISIONS, "Addressed locals"),
which the slice passing defines. -/
inductive PlaceLayout where
  | words
  | slice
deriving DecidableEq

/-- A place a reference names, held in frame memory: Core's cell `cell` at
the projection path `projections` holds a value of `ty`, laid out by `layout`
from `address`. -/
structure Addressed where
  cell : Nat
  projections : List ValueProjection
  ty : SrcType
  address : Nat
  layout : PlaceLayout := .words

/-- The bytes a place takes from its address: a word per slot. A slice
layout's extent comes with the slice passing; until then no slice place holds
(`Addressed.Holds`). -/
def Addressed.extent (x : Addressed) : Nat :=
  match x.layout with
  | .words => 8 * x.ty.size
  | .slice => 8 * x.ty.size

/-- The bytes a place takes. -/
def Addressed.Covers (x : Addressed) (a : Nat) : Prop := x.address ≤ a ∧ a < x.address + x.extent

/-- Core's value at the place is represented by its bytes: by its words, a
slot each, in the word layout. -/
def Addressed.Holds (st : State) (hp : Heap) (x : Addressed) : Prop :=
  match x.layout with
  | .words => ∃ v, Semantics.readCellProjection st x.cell x.projections = .ok v ∧
      x.ty.HoldsAt v (hp.words x.address) 0
  | .slice => False

/-- The addressed places of the activations: each one's value is represented
by its words, which lie between the frame pointer and the heap's top. -/
structure FrameCorr (places : List Addressed) (st : State) (hp : Heap) : Prop where
  holds : ∀ x ∈ places, x.Holds st hp
  inside : ∀ x ∈ places, hp.fsp ≤ x.address ∧ x.address + x.extent ≤ hp.top

theorem FrameCorr.nil (st : State) (hp : Heap) : FrameCorr [] st hp :=
  ⟨fun _ mem => by simp at mem, fun _ mem => by simp at mem⟩

/-- Changes to bytes no place covers, to the frame pointer downward, to the
cursor or the trace, and to Core cells no place names keep the correspondence. -/
theorem FrameCorr.congr {places : List Addressed} {st st' : State} {hp hp' : Heap}
    (fc : FrameCorr places st hp)
    (cells : ∀ x ∈ places, st'.cellEntry? x.cell = st.cellEntry? x.cell)
    (bytes : ∀ x ∈ places, ∀ a, x.Covers a → hp'.bytes a = hp.bytes a)
    (fsp : hp'.fsp ≤ hp.fsp) (top : hp'.top = hp.top) :
    FrameCorr places st' hp' := by
  refine ⟨fun x mem => ?_, fun x mem => ?_⟩
  · have held := fc.holds x mem
    unfold Addressed.Holds at held ⊢
    cases hl : x.layout <;> simp only [hl] at held ⊢
    obtain ⟨v, read, holds⟩ := held
    refine ⟨v, ?_, holds.words_congr fun a lo hi => bytes x mem a ⟨lo, by simpa [Addressed.extent, hl] using hi⟩⟩
    simp only [Semantics.readCellProjection, cells x mem] at read ⊢
    exact read
  · have := fc.inside x mem
    exact ⟨Nat.le_trans fsp this.1, top ▸ this.2⟩

/-- A store below the frame pointer, or below the limit, misses every place. -/
theorem FrameCorr.writeLE_below {places : List Addressed} {st : State} {hp : Heap}
    (fc : FrameCorr places st hp) {address value count : Nat} (below : address + count ≤ hp.fsp) :
    FrameCorr places st (hp.writeLE address value count) :=
  fc.congr (fun _ _ => rfl)
    (fun x mem a covers => Heap.writeLE_bytes_outside _ _ _ _ _ (.inr (by
      have := fc.inside x mem; unfold Addressed.Covers at covers; omega)))
    (Nat.le_of_eq (Heap.writeLE_top _ _ _ _).2) (Heap.writeLE_top _ _ _ _).1

/-- `frame` lowers the frame pointer and keeps every place. -/
theorem FrameCorr.frame {places : List Addressed} {st : State} {hp : Heap}
    (fc : FrameCorr places st hp) (bytes : Nat) :
    FrameCorr places st { hp with fsp := hp.fsp - bytes } :=
  fc.congr (fun _ _ => rfl) (fun _ _ _ _ => rfl) (Nat.sub_le _ _) rfl

/-- A place's words are below the top, and so below `2 ^ 62` with the heap. -/
theorem FrameCorr.covers_top {places : List Addressed} {st : State} {hp : Heap}
    (fc : FrameCorr places st hp) {x : Addressed} (mem : x ∈ places) {a : Nat} (covers : x.Covers a) :
    hp.fsp ≤ a ∧ a < hp.top := by
  have := fc.inside x mem
  unfold Addressed.Covers at covers
  omega


/-- A reference parameter's value and slot: a reference to the place `R`
names, and the place's address. -/
def RefHolds (R : Option Addressed) (ty : SrcType) (v : Value) (bits : BitVec 64) : Prop :=
  ∃ x referent, ty = .ref referent ∧ R = some x ∧ x.ty = referent ∧
    v = .reference x.ty.toCore x.cell x.projections ∧ bits = BitVec.ofNat 64 x.address

/-- Only a reference type's value is a reference parameter's. -/
theorem RefHolds.isRef {R : Option Addressed} {ty : SrcType} {v : Value} {bits : BitVec 64}
    (h : RefHolds R ty v bits) : ∃ referent, ty = .ref referent :=
  let ⟨_, referent, eq, _⟩ := h
  ⟨referent, eq⟩

/-! ## An activation's frame memory

Each function's activation takes one frame block at entry, below the frame
pointer it was called with, for the places it passes by reference; while its
body runs the frame pointer stays at the block's start. A function whose
first parameter is a reference reads and writes the place the reference
names, which lies in a caller's frame memory above the block. -/

/-- An activation's view of frame memory: the frame pointer while its body
runs, its frame block's size in bytes from there, and the place its
reference parameter names, if it has one. -/
structure Act where
  fsp : Nat
  bytes : Nat
  self : Option Addressed

/-- An activation with no block and no reference parameter. -/
def Act.plain (fsp : Nat) : Act := ⟨fsp, 0, none⟩

/-- Activation `A`'s frame memory at Core's `st` and the mini heap `hp`: the
frame pointer is its body's, its block lies between the limit and the top,
and the place its reference parameter names holds Core's value there, in the
word layout, above the block. -/
structure Frames (A : Act) (st : State) (hp : Heap) : Prop where
  fsp : hp.fsp = A.fsp
  limit : hp.limit ≤ A.fsp
  block : A.fsp + A.bytes ≤ hp.top
  self : ∀ x, A.self = some x → x.layout = .words ∧ x.Holds st hp ∧ A.fsp + A.bytes ≤ x.address ∧
    x.address + x.extent ≤ hp.top

/-- From `hp` to `hp'` activation `A` kept the top and every byte from the
end of its block up that its place does not cover. -/
structure FrameKept (A : Act) (hp hp' : Heap) : Prop where
  top : hp'.top = hp.top
  bytes : ∀ a, A.fsp + A.bytes ≤ a → a < hp.top → (∀ x, A.self = some x → ¬x.Covers a) →
    hp'.bytes a = hp.bytes a

theorem FrameKept.refl (A : Act) (hp : Heap) : FrameKept A hp hp := ⟨rfl, fun _ _ _ _ => rfl⟩

theorem FrameKept.trans {A : Act} {a b c : Heap} (first : FrameKept A a b) (second : FrameKept A b c) :
    FrameKept A a c :=
  ⟨second.top.trans first.top, fun x lo hi out =>
    (second.bytes x lo (first.top ▸ hi) out).trans (first.bytes x lo hi out)⟩

theorem FrameKept.of_bytes {A : Act} {hp hp' : Heap} (top : hp'.top = hp.top) (bytes : hp'.bytes = hp.bytes) :
    FrameKept A hp hp' :=
  ⟨top, fun a _ _ _ => by rw [bytes]⟩

/-- A store that ends at or below the block's start keeps the frame memory. -/
theorem FrameKept.writeLE_below {A : Act} {hp : Heap} {address value count : Nat}
    (below : address + count ≤ A.fsp) : FrameKept A hp (hp.writeLE address value count) :=
  ⟨(Heap.writeLE_top _ _ _ _).1, fun a lo _ _ =>
    Heap.writeLE_bytes_outside _ _ _ _ _ (.inr (by omega))⟩

/-- Frame memory as it was, for the cells of the place as they were. -/
theorem Frames.congr {A : Act} {st st' : State} {hp hp' : Heap} (fr : Frames A st hp)
    (cells : ∀ x, A.self = some x → st'.cellEntry? x.cell = st.cellEntry? x.cell)
    (fsp : hp'.fsp = hp.fsp) (limit : hp'.limit = hp.limit) (top : hp'.top = hp.top)
    (bytes : ∀ x, A.self = some x → ∀ a, x.Covers a → hp'.bytes a = hp.bytes a) :
    Frames A st' hp' := by
  refine ⟨fsp.trans fr.fsp, limit ▸ fr.limit, top ▸ fr.block, fun x found => ?_⟩
  obtain ⟨words, held, above, inside⟩ := fr.self x found
  have corr : FrameCorr [x] st' hp' :=
    FrameCorr.congr (st := st) (hp := hp) ⟨fun y mem => by simp at mem; subst mem; exact held,
      fun y mem => by simp at mem; subst mem; exact ⟨fr.fsp ▸ (by omega), inside⟩⟩
      (fun y mem => by simp at mem; subst mem; exact cells y found)
      (fun y mem a covers => by simp at mem; subst mem; exact bytes y found a covers)
      (Nat.le_of_eq fsp) top
  exact ⟨words, corr.holds x (by simp), above, top ▸ inside⟩

/-- A store that ends at or below the block's start keeps the frame memory. -/
theorem Frames.writeLE_below {A : Act} {st : State} {hp : Heap} (fr : Frames A st hp)
    {address value count : Nat} (below : address + count ≤ A.fsp) :
    Frames A st (hp.writeLE address value count) :=
  fr.congr (fun _ _ => rfl) (Heap.writeLE_top _ _ _ _).2 (Heap.writeLE_limit _ _ _ _).1
    (Heap.writeLE_top _ _ _ _).1 fun x found a covers =>
      Heap.writeLE_bytes_outside _ _ _ _ _ (.inr (by
        have := (fr.self x found).2.2.1; unfold Addressed.Covers at covers; omega))

/-! ## Cells changed within a path -/

theorem setValue_length : ∀ (vs : List Value) (i : Nat) (v : Value), (Semantics.setValue vs i v).length = vs.length
  | [], _, _ => rfl
  | _ :: _, 0, _ => rfl
  | _ :: rest, i + 1, v => by simp [Semantics.setValue, setValue_length rest i v]

theorem setValue_get? : ∀ (vs : List Value) (i : Nat) (v : Value) (j : Nat),
    (Semantics.setValue vs i v)[j]? = if j = i then (vs[j]?.map fun _ => v) else vs[j]?
  | [], _, _, _ => by simp [Semantics.setValue]
  | _ :: _, 0, _, 0 => by simp [Semantics.setValue]
  | _ :: _, 0, _, j + 1 => by simp [Semantics.setValue]
  | _ :: _, i + 1, _, 0 => by simp [Semantics.setValue]
  | _ :: rest, i + 1, v, j + 1 => by
    simp only [Semantics.setValue, List.getElem?_cons_succ, setValue_get? rest i v j]
    simp

theorem setValue_setValue : ∀ (vs : List Value) (i : Nat) (v w : Value),
    Semantics.setValue (Semantics.setValue vs i v) i w = Semantics.setValue vs i w
  | [], _, _, _ => rfl
  | _ :: _, 0, _, _ => rfl
  | _ :: rest, i + 1, v, w => by simp [Semantics.setValue, setValue_setValue rest i v w]

/-- Replacing at a path twice is replacing once with the second value. -/
theorem replaceProjectedValue_twice : ∀ (ps : List ValueProjection) {v v1 v2 u u' : Value},
    Semantics.replaceProjectedValue v ps u = .ok v1 → Semantics.replaceProjectedValue v1 ps u' = .ok v2 →
    Semantics.replaceProjectedValue v ps u' = .ok v2
  | [], _, _, _, _, _, _, second => by simpa [Semantics.replaceProjectedValue] using second
  | .field f :: rest, v, v1, v2, u, u', first, second => by
    cases v
    case «structure» id fields =>
      simp only [Semantics.replaceProjectedValue] at first ⊢
      cases found : fields[f]? with
      | none => simp [found] at first
      | some old =>
        simp only [found] at first ⊢
        split at first
        · rename_i upd inner
          simp only [Except.ok.injEq] at first
          subst first
          simp only [Semantics.replaceProjectedValue, setValue_get?, found, Option.map_some, ite_true] at second
          split at second
          · rename_i upd2 inner2
            simp only [Except.ok.injEq] at second
            subst second
            simp only [replaceProjectedValue_twice rest inner inner2, setValue_setValue]
          · simp at second
        · simp at first
    all_goals simp [Semantics.replaceProjectedValue] at first
  | .index i :: rest, v, v1, v2, u, u', first, second => by
    cases v
    case array elements =>
      simp only [Semantics.replaceProjectedValue] at first ⊢
      cases found : elements[i]? with
      | none => simp [found] at first
      | some old =>
        simp only [found] at first ⊢
        split at first
        · rename_i upd inner
          simp only [Except.ok.injEq] at first
          subst first
          simp only [Semantics.replaceProjectedValue, setValue_get?, found, Option.map_some, ite_true] at second
          split at second
          · rename_i upd2 inner2
            simp only [Except.ok.injEq] at second
            subst second
            simp only [replaceProjectedValue_twice rest inner inner2, setValue_setValue]
          · simp at second
        · simp at first
    all_goals simp [Semantics.replaceProjectedValue] at first

/-- A cell entry that changed, if at all, only at the path `ps`. -/
def Within (ps : List ValueProjection) (e e' : Option Semantics.Cell) : Prop :=
  e' = e ∨ ∃ c v u v', e = some ⟨c, some v⟩ ∧ e' = some ⟨c, some v'⟩ ∧
    Semantics.replaceProjectedValue v ps u = .ok v'

theorem Within.refl (ps : List ValueProjection) (e : Option Semantics.Cell) : Within ps e e := .inl rfl

theorem Within.trans {ps : List ValueProjection} {a b c : Option Semantics.Cell} (first : Within ps a b)
    (second : Within ps b c) : Within ps a c := by
  rcases first with rfl | ⟨k, v, u, v1, rfl, rfl, r1⟩
  · exact second
  · rcases second with rfl | ⟨k', w, u', v2, eq, rfl, r2⟩
    · exact .inr ⟨k, v, u, v1, rfl, rfl, r1⟩
    · simp only [Option.some.injEq, Semantics.Cell.mk.injEq] at eq
      obtain ⟨rfl, rfl⟩ := eq
      exact .inr ⟨k, v, u', v2, rfl, rfl, replaceProjectedValue_twice ps r1 r2⟩

/-- From `st` to `st'` the cells below `base` stayed as they were, but for the
cell of `A`'s place, which changed only at the place's path; and the next
cell did not go down. -/
structure KeepsOut (A : Act) (base : Nat) (st st' : State) : Prop where
  cells : ∀ c < base, (∀ x, A.self = some x → c ≠ x.cell) → st'.cellEntry? c = st.cellEntry? c
  within : ∀ x, A.self = some x → Within x.projections (st.cellEntry? x.cell) (st'.cellEntry? x.cell)
  next : st.nextCell ≤ st'.nextCell

theorem KeepsOut.refl (A : Act) (base : Nat) (st : State) : KeepsOut A base st st :=
  ⟨fun _ _ _ => rfl, fun _ _ => Within.refl _ _, Nat.le_refl _⟩

theorem KeepsOut.trans {A : Act} {base : Nat} {a b c : State} (first : KeepsOut A base a b)
    (second : KeepsOut A base b c) : KeepsOut A base a c :=
  ⟨fun k below out => (second.cells k below out).trans (first.cells k below out),
    fun x found => (first.within x found).trans (second.within x found), Nat.le_trans first.next second.next⟩

theorem KeepsOut.lower {A : Act} {base low : Nat} {st st' : State} (keeps : KeepsOut A base st st')
    (le : low ≤ base) : KeepsOut A low st st' :=
  ⟨fun c below out => keeps.cells c (Nat.lt_of_lt_of_le below le) out, keeps.within, keeps.next⟩

end Lanius.Mini
