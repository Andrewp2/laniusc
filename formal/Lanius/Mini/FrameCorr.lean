import Lanius.Mini.Source

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

/-- A place a reference names, held in frame memory: Core's cell `cell` at
the projection path `projections` holds a value of `ty`, whose slots are the
words from `address`. -/
structure Addressed where
  cell : Nat
  projections : List ValueProjection
  ty : SrcType
  address : Nat

/-- The bytes a place's words take. -/
def Addressed.Covers (x : Addressed) (a : Nat) : Prop := x.address ≤ a ∧ a < x.address + 8 * x.ty.size

/-- Core's value at the place is represented by its words. -/
def Addressed.Holds (st : State) (hp : Heap) (x : Addressed) : Prop :=
  ∃ v, Semantics.readCellProjection st x.cell x.projections = .ok v ∧ x.ty.HoldsAt v (hp.words x.address) 0

/-- The addressed places of the activations: each one's value is represented
by its words, which lie between the frame pointer and the heap's top. -/
structure FrameCorr (places : List Addressed) (st : State) (hp : Heap) : Prop where
  holds : ∀ x ∈ places, x.Holds st hp
  inside : ∀ x ∈ places, hp.fsp ≤ x.address ∧ x.address + 8 * x.ty.size ≤ hp.top

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
  · obtain ⟨v, read, holds⟩ := fc.holds x mem
    refine ⟨v, ?_, holds.words_congr fun a lo hi => bytes x mem a ⟨lo, hi⟩⟩
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

end Lanius.Mini
