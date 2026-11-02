module

public import Lanius.Mini.Source
import all Lanius.Mini.Compiler.P.Lists_empty
import all Lanius.Mini.Compiler.P.SrcType_size

@[expose] public section

/-! Frame memory and the places Core's references name (F5, SEMANTIC_DECISIONS
"Addressed locals").

A reference in Core names a cell and a projection path into its value. When
the verified compiler passes a reference, the value at that place lives in
frame memory, one 64-bit word per slot from an address: the same layout the
value has in a function's slots, so `ty.HoldsAt places v (hp.words address) 0` says
the words represent it. `FrameCorr` carries those places beside `Corr` and
`HeapCorr`: each one's value is in Core's cell, its words are in the mini
heap between the frame pointer and the top, and nothing else writes there.
-/

namespace Lanius.Mini

variable {bud : Budget} {places : List Addressed}

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
    (holds : ty.HoldsAt places v (hp.words address) 0)
    (same : ∀ a, address ≤ a → a < address + 8 * ty.size → hp'.bytes a = hp.bytes a) :
    ty.HoldsAt places v (hp'.words address) 0 :=
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
    (holds : ty.HoldsAt places v env slot) (hp : Heap) (address : Nat) :
    ty.HoldsAt places v ((hp.storeSlots address env slot ty.size).words address) 0 :=
  holds.congr fun i lt => by rw [Nat.zero_add, Heap.storeSlots_words _ _ _ _ _ _ lt]

/-- A value in words, loaded into slots, is represented by the slots. -/
theorem SrcType.HoldsAt.loadSlots {ty : SrcType} {v : Value} {hp : Heap} {address : Nat}
    (holds : ty.HoldsAt places v (hp.words address) 0) {env : Env} {slot : Nat}
    (loaded : ∀ i < ty.size, env (slot + i) = hp.words address i) : ty.HoldsAt places v env slot :=
  holds.congr fun i lt => by rw [Nat.zero_add]; exact loaded i lt

/-! ## The correspondence -/

/-- The bytes a place's block takes: 8 for each slot of its type. -/
def Addressed.Covers (x : Addressed) (a : Nat) : Prop := x.address ≤ a ∧ a < x.address + 8 * x.ty.size

/-- Where slot `s` of a place's value lies, and how many bytes it takes. A
place that is not sliced has one 8-byte word per slot, upward from its
address. A sliced one, an array passed as a slice, has the slice layout: an
`i32` element in 4 bytes and a `u8` element in 1, upward from the address,
and the slots of other elements in 8-byte words running down from the
pointer, the block's top word. -/
def Addressed.slotBytes (x : Addressed) (s : Nat) : Nat × Nat :=
  if x.sliced then
    match x.ty with
    | .array .i32 _ => (x.address + 4 * s, 4)
    | .array (.uint .uint8) _ => (x.address + s, 1)
    | _ => (x.address + 8 * (x.ty.size - 1 - s), 8)
  else (x.address + 8 * s, 8)

/-- A place's value as slots, read from the mini heap in its layout. -/
def Addressed.view (x : Addressed) (hp : Heap) : Env :=
  fun s => BitVec.ofNat 64 (hp.readLE (x.slotBytes s).1 (x.slotBytes s).2)

/-- Each slot of a place lies in its block. -/
theorem Addressed.slotBytes_inside (x : Addressed) {s : Nat} (lt : s < x.ty.size) :
    x.address ≤ (x.slotBytes s).1 ∧ (x.slotBytes s).1 + (x.slotBytes s).2 ≤ x.address + 8 * x.ty.size := by
  unfold Addressed.slotBytes
  split
  · split
    · rename_i n h
      rw [h] at lt ⊢
      simp only [SrcType.size] at lt ⊢
      omega
    · rename_i n h
      rw [h] at lt ⊢
      simp only [SrcType.size] at lt ⊢
      omega
    · simp only
      omega
  · simp only
    omega

/-- A place that is not sliced: its words. -/
theorem Addressed.view_words {x : Addressed} (h : x.sliced = false) (hp : Heap) : x.view hp = hp.words x.address := by
  funext s
  simp [Addressed.view, Addressed.slotBytes, h, Heap.words]

/-- A sliced array of `i32`: element `s` is the 4 bytes `4 * s` above the
pointer, as a raw slice's. -/
theorem Addressed.view_i32 {x : Addressed} (h : x.sliced = true) {n : Nat} (ty : x.ty = .array .i32 n)
    (hp : Heap) (s : Nat) : x.view hp s = BitVec.ofNat 64 (hp.readLE (x.pointer + 4 * s) 4) := by
  simp [Addressed.view, Addressed.slotBytes, Addressed.pointer, h, ty]

/-- A sliced array of `u8`: element `s` is the byte `s` above the pointer. -/
theorem Addressed.view_u8 {x : Addressed} (h : x.sliced = true) {n : Nat} (ty : x.ty = .array (.uint .uint8) n)
    (hp : Heap) (s : Nat) : x.view hp s = BitVec.ofNat 64 (hp.readLE (x.pointer + s) 1) := by
  simp [Addressed.view, Addressed.slotBytes, Addressed.pointer, h, ty]

/-- A sliced array of other elements: slot `s` is the word `8 * s` below the
pointer, so element `i` of `w` slots starts `8 * w * i` below it, as a raw
slice's (`NativeLayout.elementBase?`). -/
theorem Addressed.view_word {x : Addressed} (h : x.sliced = true)
    (other : ∀ n, x.ty ≠ .array .i32 n ∧ x.ty ≠ .array (.uint .uint8) n) (hp : Heap) {s : Nat}
    (lt : s < x.ty.size) : x.view hp s = BitVec.ofNat 64 (hp.readLE (x.pointer - 8 * s) 8) := by
  have pointer : x.pointer = x.address + 8 * (x.ty.size - 1) := by
    unfold Addressed.pointer
    split
    · rename_i n e; exact absurd e (other n).1
    · rename_i n e; exact absurd e (other n).2
    · rfl
  have bytes : x.slotBytes s = (x.address + 8 * (x.ty.size - 1 - s), 8) := by
    unfold Addressed.slotBytes
    rw [if_pos h]
    split
    · rename_i n e; exact absurd e (other n).1
    · rename_i n e; exact absurd e (other n).2
    · rfl
  simp only [Addressed.view, bytes, pointer]
  congr 2
  omega

/-- A place's slots agree in two heaps whose bytes agree on its block. -/
theorem Addressed.view_congr {x : Addressed} {hp hp' : Heap} (same : ∀ a, x.Covers a → hp'.bytes a = hp.bytes a) :
    ∀ i < x.ty.size, x.view hp' (0 + i) = x.view hp (0 + i) := by
  intro i lt
  have inside := x.slotBytes_inside lt
  simp only [Addressed.view, Nat.zero_add]
  rw [Heap.readLE_congr (fun a lo hi => same a ⟨by omega, by omega⟩)]

/-- Core's value at the place is represented by its slots in its layout. -/
def Addressed.Holds (places : List Addressed) (st : State) (hp : Heap) (x : Addressed) : Prop :=
  ∃ v, Semantics.readCellProjection st x.cell x.projections = .ok v ∧ x.ty.HoldsAt places v (x.view hp) 0

/-- A caller's `i32` or `u8` array passed as a slice: the only addressed
places so far (F5's references will add others). Their values hold no
slice, so whether they are represented does not depend on the places. -/
def Addressed.Packed (x : Addressed) : Prop :=
  x.sliced = true ∧ x.projections = [] ∧
    ∃ element n, x.ty = .array element n ∧ (element = .i32 ∨ element = .uint .uint8)

/-- The frame memory an activation may use, fixed per function (TRUSTED_BASE
"Frame room"): its own block, the `block` bytes from the frame pointer up,
and `room` bytes below the frame pointer, down to the limit, for its
callees' blocks. -/
structure Budget where
  room : Nat
  block : Nat

/-- The addressed places of the activations: each one's value is represented
by its words, which lie in frame memory, above the activation's block (and
the limit) and below the heap's top. The activation's callees have their
room below the frame pointer. -/
structure FrameCorr (bud : Budget) (places : List Addressed) (st : State) (hp : Heap) : Prop where
  holds : ∀ x ∈ places, x.Holds places st hp
  inside : ∀ x ∈ places, hp.fsp + bud.block ≤ x.address ∧ hp.limit ≤ x.address ∧ x.address + 8 * x.ty.size ≤ hp.top
  /-- Every block is below `2 ^ 62`, so its addresses add without wrapping. -/
  small : ∀ x ∈ places, x.address + 8 * x.ty.size < 2 ^ 62
  /-- Two different places name different cells and have blocks apart. -/
  apart : ∀ x ∈ places, ∀ y ∈ places, x ≠ y →
    x.cell ≠ y.cell ∧ (x.address + 8 * x.ty.size ≤ y.address ∨ y.address + 8 * y.ty.size ≤ x.address)
  /-- Every place is a packed array passed as a slice. -/
  packed : ∀ x ∈ places, x.Packed
  /-- The callees' room lies above the limit, for an activation with any
  frame memory at all (one with none needs no frame memory, which a heap
  without any, as the self compiler's, has). -/
  room : 0 < bud.room + bud.block → hp.limit + bud.room ≤ hp.fsp
  /-- The activation's block lies below the top, for an activation with
  any frame memory: its loads and stores reach it. -/
  ceiling : 0 < bud.room + bud.block → hp.fsp + bud.block ≤ hp.top
  /-- Frame memory ends below `2 ^ 62`, for an activation with any frame
  memory: a block taken from it is `small`. -/
  bounded : 0 < bud.room + bud.block → hp.top < 2 ^ 62

theorem FrameCorr.nil (st : State) {hp : Heap} (room : 0 < bud.room + bud.block → hp.limit + bud.room ≤ hp.fsp)
    (ceiling : 0 < bud.room + bud.block → hp.fsp + bud.block ≤ hp.top)
    (bounded : 0 < bud.room + bud.block → hp.top < 2 ^ 62) :
    FrameCorr bud [] st hp :=
  ⟨fun _ mem => by simp at mem, fun _ mem => by simp at mem, fun _ mem => by simp at mem,
    fun _ mem => by simp at mem, fun _ mem => by simp at mem, room, ceiling, bounded⟩

/-- No places, and `need` bytes of frame memory room when `need` is positive:
where a program's run starts. -/
theorem FrameCorr.start (st : State) {hp : Heap} {need : Nat}
    (frameRoom : 0 < need → hp.limit + need ≤ hp.fsp ∧ hp.fsp ≤ hp.top ∧ hp.top < 2 ^ 62) :
    FrameCorr ⟨need, 0⟩ [] st hp :=
  FrameCorr.nil st (fun pos => (frameRoom (by simpa using pos)).1)
    (fun pos => by simpa using (frameRoom (by simpa using pos)).2.1)
    fun pos => (frameRoom (by simpa using pos)).2.2

/-- No places, and no frame memory needed. -/
theorem FrameCorr.empty (st : State) (hp : Heap) : FrameCorr ⟨0, 0⟩ [] st hp :=
  FrameCorr.nil st (fun pos => absurd pos (by decide)) (fun pos => absurd pos (by decide))
    fun pos => absurd pos (by decide)

/-- Changes to bytes no place covers, to the cursor or the trace, and to Core cells no place names keep the correspondence. -/
theorem FrameCorr.congr {st st' : State} {hp hp' : Heap}
    (fc : FrameCorr bud places st hp)
    (cells : ∀ x ∈ places, st'.cellEntry? x.cell = st.cellEntry? x.cell)
    (bytes : ∀ x ∈ places, ∀ a, x.Covers a → hp'.bytes a = hp.bytes a)
    (fsp : hp'.fsp = hp.fsp) (limit : hp'.limit = hp.limit) (top : hp'.top = hp.top) :
    FrameCorr bud places st' hp' := by
  refine ⟨fun x mem => ?_, fun x mem => ?_, fc.small, fc.apart, fc.packed, by rw [fsp, limit]; exact fc.room,
    by rw [fsp, top]; exact fc.ceiling, by rw [top]; exact fc.bounded⟩
  · obtain ⟨v, read, holds⟩ := fc.holds x mem
    refine ⟨v, ?_, holds.congr (Addressed.view_congr (bytes x mem))⟩
    simp only [Semantics.readCellProjection, cells x mem] at read ⊢
    exact read
  · have := fc.inside x mem
    exact ⟨fsp ▸ this.1, limit ▸ this.2.1, top ▸ this.2.2⟩

/-- A heap that differs only below the limit, with the same limit, top and
frame pointer, and Core cells no place names, keep the correspondence: the
bump heap is not frame memory. -/
theorem FrameCorr.low {st st' : State} {hp hp' : Heap} (fc : FrameCorr bud places st hp)
    (cells : ∀ x ∈ places, st'.cellEntry? x.cell = st.cellEntry? x.cell)
    (bytes : ∀ a, hp.limit ≤ a → hp'.bytes a = hp.bytes a)
    (fsp : hp'.fsp = hp.fsp) (limit : hp'.limit = hp.limit) (top : hp'.top = hp.top) :
    FrameCorr bud places st' hp' :=
  fc.congr cells (fun x mem a covers => bytes a (by
      have := fc.inside x mem; unfold Addressed.Covers at covers; omega))
    fsp limit top

/-- A store below the frame pointer misses every place. -/
theorem FrameCorr.writeLE_below {st : State} {hp : Heap}
    (fc : FrameCorr bud places st hp) {address value count : Nat} (below : address + count ≤ hp.fsp) :
    FrameCorr bud places st (hp.writeLE address value count) :=
  fc.congr (fun _ _ => rfl)
    (fun x mem a covers => Heap.writeLE_bytes_outside _ _ _ _ _ (.inr (by
      have := fc.inside x mem; unfold Addressed.Covers at covers; omega)))
    (Heap.writeLE_top _ _ _ _).2 (Heap.writeLE_limit _ _ _ _).1 (Heap.writeLE_top _ _ _ _).1

/-- A store below the limit, into the bump heap, misses every place. -/
theorem FrameCorr.writeLE_low {st : State} {hp : Heap}
    (fc : FrameCorr bud places st hp) {address value count : Nat} (below : address + count ≤ hp.limit) :
    FrameCorr bud places st (hp.writeLE address value count) :=
  fc.congr (fun _ _ => rfl)
    (fun x mem a covers => Heap.writeLE_bytes_outside _ _ _ _ _ (.inr (by
      have := fc.inside x mem; unfold Addressed.Covers at covers; omega)))
    (Heap.writeLE_top _ _ _ _).2 (Heap.writeLE_limit _ _ _ _).1 (Heap.writeLE_top _ _ _ _).1

/-- A byte store below the limit misses every place. -/
theorem FrameCorr.write_low {st : State} {hp : Heap}
    (fc : FrameCorr bud places st hp) {address : Nat} {byte : UInt8} (below : address < hp.limit) :
    FrameCorr bud places st (hp.write address byte) :=
  fc.congr (fun _ _ => rfl)
    (fun x mem a covers => by
      have := fc.inside x mem; unfold Addressed.Covers at covers
      rw [Heap.write_bytes, if_neg (by omega)])
    rfl rfl rfl

/-- `hp'` differs from `hp` only below the limit, in the bump heap: what a
store into Core's heap does. -/
structure Heap.LowOnly (hp hp' : Heap) : Prop where
  bytes : ∀ a, hp.limit ≤ a → hp'.bytes a = hp.bytes a
  fsp : hp'.fsp = hp.fsp
  limit : hp'.limit = hp.limit
  top : hp'.top = hp.top

theorem Heap.LowOnly.refl (hp : Heap) : hp.LowOnly hp := ⟨fun _ _ => rfl, rfl, rfl, rfl⟩

theorem Heap.LowOnly.trans {a b c : Heap} (first : a.LowOnly b) (second : b.LowOnly c) : a.LowOnly c :=
  ⟨fun x le => (second.bytes x (first.limit ▸ le)).trans (first.bytes x le), second.fsp.trans first.fsp,
    second.limit.trans first.limit, second.top.trans first.top⟩

theorem Heap.LowOnly.writeLE {hp : Heap} {address value count : Nat} (below : address + count ≤ hp.limit) :
    hp.LowOnly (hp.writeLE address value count) :=
  ⟨fun _ le => Heap.writeLE_bytes_outside _ _ _ _ _ (.inr (by omega)), (Heap.writeLE_top _ _ _ _).2,
    (Heap.writeLE_limit _ _ _ _).1, (Heap.writeLE_top _ _ _ _).1⟩

theorem Heap.LowOnly.write {hp : Heap} {address : Nat} {byte : UInt8} (below : address < hp.limit) :
    hp.LowOnly (hp.write address byte) :=
  ⟨fun _ le => by rw [Heap.write_bytes, if_neg (by omega)], rfl, rfl, rfl⟩

/-- The places hold over a change below the limit. -/
theorem FrameCorr.lowOnly {st : State} {hp hp' : Heap} (fc : FrameCorr bud places st hp) (low : hp.LowOnly hp') :
    FrameCorr bud places st hp' :=
  fc.low (fun _ _ => rfl) low.bytes low.fsp low.limit low.top

/-- Core's heap is not frame memory. -/
theorem FrameCorr.withHeap {st : State} {hp : Heap} (fc : FrameCorr bud places st hp) (heap : Memory.Heap) :
    FrameCorr bud places { st with heap } hp :=
  fc.congr (fun _ _ => rfl) (fun _ _ _ _ => rfl) rfl rfl rfl

/-- `frame` lowers the frame pointer and keeps every place: the bytes come
out of the room, and the new block is at most what was handed out over the
old one. -/
theorem FrameCorr.frame {st : State} {hp : Heap}
    (fc : FrameCorr bud places st hp) {bud' : Budget} (bytes : Nat) (room : bytes + bud'.room ≤ bud.room)
    (block : bud'.block ≤ bytes + bud.block) :
    FrameCorr bud' places st { hp with fsp := hp.fsp - bytes } := by
  have room' := fc.room
  have ceiling' := fc.ceiling
  have bounded' := fc.bounded
  refine ⟨fun x mem => ?_, fun x mem => ?_, fc.small, fc.apart, fc.packed, fun pos => ?_, fun pos => ?_,
    fun pos => bounded' (by omega)⟩
  · obtain ⟨v, read, holds⟩ := fc.holds x mem
    exact ⟨v, read, holds.congr (Addressed.view_congr fun _ _ => rfl)⟩
  · have inside := fc.inside x mem
    exact ⟨by show hp.fsp - bytes + _ ≤ _; omega, inside.2⟩
  · have := room' (by omega)
    show hp.limit + bud'.room ≤ hp.fsp - bytes
    omega
  · have := room' (by omega)
    have := ceiling' (by omega)
    show hp.fsp - bytes + bud'.block ≤ hp.top
    omega

/-- A call's return gives the caller's frame pointer back, and with it the
caller's budget: its block below every place and its room above the limit. -/
theorem FrameCorr.restore {bud' : Budget} {st : State} {hp : Heap}
    (fc : FrameCorr bud' places st hp) {fsp : Nat} (above : ∀ x ∈ places, fsp + bud.block ≤ x.address)
    (room : 0 < bud.room + bud.block → hp.limit + bud.room ≤ fsp)
    (ceiling : 0 < bud.room + bud.block → fsp + bud.block ≤ hp.top)
    (bounded : 0 < bud.room + bud.block → hp.top < 2 ^ 62) :
    FrameCorr bud places st { hp with fsp := fsp } :=
  ⟨fun x mem => by
      obtain ⟨v, read, holds⟩ := fc.holds x mem
      exact ⟨v, read, holds.congr (Addressed.view_congr fun _ _ => rfl)⟩,
    fun x mem => ⟨above x mem, (fc.inside x mem).2⟩, fc.small, fc.apart, fc.packed, room, ceiling, bounded⟩

/-- After a call: the callee's places with the caller's frame pointer and
budget, given the caller's correspondence before the call. -/
theorem FrameCorr.back {bud' : Budget} {st st0 : State} {hp hp0 : Heap} (fc : FrameCorr bud' places st hp)
    (caller : FrameCorr bud places st0 hp0) (limit : hp.limit = hp0.limit) (top : hp.top = hp0.top) :
    FrameCorr bud places st { hp with fsp := hp0.fsp } :=
  fc.restore (fun x mem => (caller.inside x mem).1) (fun pos => by rw [limit]; exact caller.room pos)
    (fun pos => by rw [top]; exact caller.ceiling pos) (fun pos => by rw [top]; exact caller.bounded pos)

/-- A callee with no block of its own and room no more than its caller's. -/
theorem FrameCorr.callee {st : State} {hp : Heap} (fc : FrameCorr bud places st hp) {bud' : Budget}
    (room : bud'.room ≤ bud.room) (block : bud'.block ≤ bud.block) : FrameCorr bud' places st hp := by
  have room' := fc.room
  have ceiling' := fc.ceiling
  have bounded' := fc.bounded
  refine ⟨fc.holds, fun x mem => ?_, fc.small, fc.apart, fc.packed, fun pos => ?_, fun pos => ?_,
    fun pos => bounded' (by omega)⟩
  · have inside := fc.inside x mem
    exact ⟨by omega, inside.2⟩
  · have := room' (by omega)
    omega
  · have := ceiling' (by omega)
    omega

/-- A place's words are below the top, and so below `2 ^ 62` with the heap. -/
theorem FrameCorr.covers_top {st : State} {hp : Heap}
    (fc : FrameCorr bud places st hp) {x : Addressed} (mem : x ∈ places) {a : Nat} (covers : x.Covers a) :
    hp.fsp ≤ a ∧ a < hp.top := by
  have := fc.inside x mem
  unfold Addressed.Covers at covers
  omega

end Lanius.Mini
