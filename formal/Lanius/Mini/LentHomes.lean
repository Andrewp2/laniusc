module

public import Lanius.Mini.Borrowed
public import Lanius.Mini.Homes
import all Lanius.Mini.Compiler.P.SrcType_same
import all Lanius.Mini.Compiler.P.SrcType_size
import all Lanius.Mini.Compiler.P.fieldOffset
import all Lanius.Mini.Compiler.P.norm
import all Lanius.Mini.Compiler.P.wrap
import all Lanius.Mini.Compiler.P.BinOp_size
import all Lanius.Mini.Compiler.P.Lists_concat
import all Lanius.Mini.Compiler.P.Lists_cons
import all Lanius.Mini.Compiler.P.Lists_empty
import all Lanius.Mini.Compiler.P.Lists_get
import all Lanius.Mini.Compiler.P.Lists_getOr
import all Lanius.Mini.Compiler.P.Lists_length
import all Lanius.Mini.Compiler.P.Lists_single
import all Lanius.Mini.Compiler.P.MemWidth_bytes
import all Lanius.Mini.Compiler.P.MemWidth_prefix
import all Lanius.Mini.Compiler.P.MemWidth_rex
import all Lanius.Mini.Compiler.P.Word_prefix

@[expose] public section

/-! # The simulation's frame memory: homes, each one lent (F5 stage 2, S6a-1)

SEMANTIC_DECISIONS "S6's steps". The simulation keeps its addressed places
as `Homes` (`Homes.lean`), the memory model of references, together with the
side fact `Lent`: until S6b gives borrowed locals homes, every place is a
caller's packed `i32` or `u8` array lent to a callee as a slice
(`Addressed.Packed`), in a block above the activation's own block. A place
takes its native words (`Addressed.Within`), which for a packed array are at
most its slots.

`LentHomes` has the interface `FrameCorr` had (`FrameCorr.lean`), with the
same names: the field-like facts (`holds`, `inside`, `small`, `apart`,
`packed`, ...), and the lemmas that keep it over a change of the heap, of
Core's cells or of the frame pointer. `FrameCorr` itself stays, unused by
the simulation, since open statements name it (`FrameCorrHomes`).
-/

namespace Lanius.Mini

open Lanius.Core (Value)
open Lanius.Semantics (State)

variable {bud : Budget} {sx : Statics} {places : List Addressed}

/-! ## Packed places -/

/-- A packed array takes no more words than slots. -/
theorem Addressed.Packed.words_le {x : Addressed} (packed : x.Packed) : x.ty.words ≤ x.ty.size := by
  obtain ⟨-, -, element, n, ty, el⟩ := packed
  rcases el with rfl | rfl
  · rw [Addressed.words_i32 ty, Addressed.size_i32 ty]; omega
  · rw [Addressed.words_u8 ty, Addressed.size_u8 ty]; omega

/-- A packed array's home view is its slice-layout view. -/
theorem Addressed.Packed.homeView {x : Addressed} (packed : x.Packed) (hp : Heap) :
    x.ty.homeView x.address hp = x.view hp := by
  funext s
  obtain ⟨sl, -, element, n, ty, el⟩ := packed
  simp only [SrcType.homeView, Addressed.view, Addressed.slotBytes, sl, if_true]
  rcases el with rfl | rfl <;> rw [ty] <;>
    simp [SrcType.slotAt, SrcType.accessKind, Access.narrow, Access.bytes, MemWidth.bytes]

theorem Addressed.Packed.homeOk {x : Addressed} (packed : x.Packed) : x.ty.homeOk = true := by
  obtain ⟨-, -, element, n, ty, el⟩ := packed
  rw [ty]
  rcases el with rfl | rfl <;> simp [SrcType.homeOk]

/-- Each slot of a packed place lies in its words. -/
theorem Addressed.Packed.slotBytes_within {x : Addressed} (packed : x.Packed) {s : Nat} (lt : s < x.ty.size) :
    x.address ≤ (x.slotBytes s).1 ∧ (x.slotBytes s).1 + (x.slotBytes s).2 ≤ x.address + 8 * x.ty.words := by
  obtain ⟨sl, -, element, n, ty, el⟩ := packed
  rcases el with rfl | rfl
  · have := Addressed.words_i32 ty
    have := Addressed.size_i32 ty
    have bytes : x.slotBytes s = (x.address + 4 * s, 4) := by simp [Addressed.slotBytes, sl, ty]
    rw [bytes]
    omega
  · have := Addressed.words_u8 ty
    have := Addressed.size_u8 ty
    have bytes : x.slotBytes s = (x.address + s, 1) := by simp [Addressed.slotBytes, sl, ty]
    rw [bytes]
    omega

/-- A packed place's slots agree in two heaps whose bytes agree on its words. -/
theorem Addressed.Packed.view_congr {x : Addressed} (packed : x.Packed) {hp hp' : Heap}
    (same : ∀ a, x.Within a → hp'.bytes a = hp.bytes a) :
    ∀ i < x.ty.size, x.view hp' (0 + i) = x.view hp (0 + i) := by
  intro i lt
  have inside := packed.slotBytes_within lt
  simp only [Addressed.view, Nat.zero_add]
  rw [Heap.readLE_congr (fun a lo hi => same a ⟨by omega, by omega⟩)]

/-- A packed place's words are among its slots' bytes. -/
theorem Addressed.Packed.within_covers {x : Addressed} (packed : x.Packed) {a : Nat} (within : x.Within a) :
    x.Covers a := by
  have := packed.words_le
  unfold Addressed.Within at within
  unfold Addressed.Covers
  omega

/-! ## Indices -/

/-- Two different indices name different members of a list whose members
are pairwise related. -/
theorem indexed_of_pairwise {R S : Addressed → Addressed → Prop} {l : List Addressed} (h : l.Pairwise R)
    (both : ∀ x y, R x y → S x y ∧ S y x) :
    ∀ (i j : Nat) (x y : Addressed), l[i]? = some x → l[j]? = some y → i ≠ j → S x y := by
  intro i j x y hx hy ne
  obtain ⟨hi, rfl⟩ := List.getElem?_eq_some_iff.mp hx
  obtain ⟨hj, rfl⟩ := List.getElem?_eq_some_iff.mp hy
  rcases Nat.lt_or_gt_of_ne ne with lt | lt
  · exact (both _ _ (List.pairwise_iff_getElem.mp h i j hi hj lt)).1
  · exact (both _ _ (List.pairwise_iff_getElem.mp h j i hj hi lt)).2

/-- Indexed facts about two lists and across them give the facts about
their concatenation. -/
theorem indexed_append {S : Addressed → Addressed → Prop} {l₁ l₂ : List Addressed}
    (one : ∀ (i j : Nat) (x y : Addressed), l₁[i]? = some x → l₁[j]? = some y → i ≠ j → S x y)
    (two : ∀ (i j : Nat) (x y : Addressed), l₂[i]? = some x → l₂[j]? = some y → i ≠ j → S x y)
    (cross : ∀ x ∈ l₁, ∀ y ∈ l₂, S x y ∧ S y x) :
    ∀ (i j : Nat) (x y : Addressed), (l₁ ++ l₂)[i]? = some x → (l₁ ++ l₂)[j]? = some y → i ≠ j → S x y := by
  intro i j x y hx hy ne
  rcases Nat.lt_or_ge i l₁.length with hi | hi <;> rcases Nat.lt_or_ge j l₁.length with hj | hj
  · rw [List.getElem?_append_left hi] at hx
    rw [List.getElem?_append_left hj] at hy
    exact one i j x y hx hy ne
  · rw [List.getElem?_append_left hi] at hx
    rw [List.getElem?_append_right hj] at hy
    exact (cross x (List.mem_of_getElem? hx) y (List.mem_of_getElem? hy)).1
  · rw [List.getElem?_append_right hi] at hx
    rw [List.getElem?_append_left hj] at hy
    exact (cross y (List.mem_of_getElem? hy) x (List.mem_of_getElem? hx)).2
  · rw [List.getElem?_append_right hi] at hx
    rw [List.getElem?_append_right hj] at hy
    exact two _ _ x y hx hy (by omega)

/-- Indexed facts about a concatenation hold for its second part. -/
theorem indexed_right {S : Addressed → Addressed → Prop} {l₁ l₂ : List Addressed}
    (h : ∀ (i j : Nat) (x y : Addressed), (l₁ ++ l₂)[i]? = some x → (l₁ ++ l₂)[j]? = some y → i ≠ j → S x y) :
    ∀ (i j : Nat) (x y : Addressed), l₂[i]? = some x → l₂[j]? = some y → i ≠ j → S x y := by
  intro i j x y hx hy ne
  refine h (l₁.length + i) (l₁.length + j) x y ?_ ?_ (by omega)
  · rw [List.getElem?_append_right (by omega)]; simpa using hx
  · rw [List.getElem?_append_right (by omega)]; simpa using hy

/-! ## Lent homes -/

/-- The side fact of stage 2 until S6b: every place is a caller's packed
array lent as a slice, above the activation's block. -/
structure Lent (bud : Budget) (places : List Addressed) (hp : Heap) : Prop where
  packed : ∀ x ∈ places, x.Packed
  above : ∀ x ∈ places, hp.fsp + bud.block ≤ x.address

/-- The activations' places: homes (`Homes`), each one lent (`Lent`). -/
structure LentHomes (sx : Statics) (bud : Budget) (places : List Addressed) (st : State) (hp : Heap) : Prop where
  homes : Homes sx bud places st hp
  lent : Lent bud places hp

/-- `LentHomes` from `FrameCorr`'s facts, the bounds by words and `apart`
by indices. -/
theorem LentHomes.ofParts {st : State} {hp : Heap}
    (holds : ∀ x ∈ places, x.Holds sx places st hp)
    (packed : ∀ x ∈ places, x.Packed)
    (inside : ∀ x ∈ places,
      hp.fsp + bud.block ≤ x.address ∧ hp.limit ≤ x.address ∧ x.address + 8 * x.ty.words ≤ hp.top)
    (small : ∀ x ∈ places, x.address + 8 * x.ty.words < 2 ^ 62)
    (apart : ∀ (i j : Nat) (x y : Addressed), places[i]? = some x → places[j]? = some y → i ≠ j →
      x.cell ≠ y.cell ∧ (x.address + 8 * x.ty.words ≤ y.address ∨ y.address + 8 * y.ty.words ≤ x.address))
    (unviewed : ∀ v ∈ st.i32ArrayViews, ∀ x ∈ places, v.root ≠ x.cell)
    (room : 0 < bud.room + bud.block → hp.limit + bud.room ≤ hp.fsp)
    (ceiling : 0 < bud.room + bud.block → hp.fsp + bud.block ≤ hp.top)
    (bounded : 0 < bud.room + bud.block → hp.top < 2 ^ 62)
    (statics : hp.StaticsAt sx) :
    LentHomes sx bud places st hp where
  homes :=
    { holds := fun i x hx => by
        have mem : x ∈ places := List.mem_of_getElem? hx
        obtain ⟨v, read, h⟩ := holds x mem
        rw [(packed x mem).2.1] at read
        refine ⟨v, read, ?_⟩
        rw [(packed x mem).homeView]
        exact (packed x mem).holdsAt h
      roots := fun x mem => (packed x mem).2.1
      sliced := fun x mem => (packed x mem).1
      layout := fun x mem => (packed x mem).homeOk
      inside := fun x mem => by
        have := inside x mem
        exact ⟨by omega, this.2.1, this.2.2⟩
      small := small
      apart := apart
      unviewed := unviewed
      room := room
      ceiling := ceiling
      bounded := bounded
      statics := statics }
  lent := ⟨packed, fun x mem => (inside x mem).1⟩

section
variable {st : State} {hp : Heap} (fc : LentHomes sx bud places st hp)
include fc

theorem LentHomes.packed : ∀ x ∈ places, x.Packed := fc.lent.packed

/-- Core's value at each place is represented by its slots. -/
theorem LentHomes.holds : ∀ x ∈ places, x.Holds sx places st hp := by
  intro x mem
  obtain ⟨i, hi⟩ := List.mem_iff_getElem?.mp mem
  obtain ⟨v, read, h⟩ := fc.homes.holds i x hi
  have packed := fc.packed x mem
  refine ⟨v, by rw [packed.2.1]; exact read, ?_⟩
  rw [← packed.homeView]
  exact packed.holdsAt h

theorem LentHomes.inside : ∀ x ∈ places,
    hp.fsp + bud.block ≤ x.address ∧ hp.limit ≤ x.address ∧ x.address + 8 * x.ty.words ≤ hp.top :=
  fun x mem => ⟨fc.lent.above x mem, (fc.homes.inside x mem).2⟩

theorem LentHomes.small : ∀ x ∈ places, x.address + 8 * x.ty.words < 2 ^ 62 := fc.homes.small

/-- Two different places name different cells and have words apart. -/
theorem LentHomes.apart : ∀ x ∈ places, ∀ y ∈ places, x ≠ y →
    x.cell ≠ y.cell ∧ (x.address + 8 * x.ty.words ≤ y.address ∨ y.address + 8 * y.ty.words ≤ x.address) := by
  intro x xm y ym ne
  obtain ⟨i, hi⟩ := List.mem_iff_getElem?.mp xm
  obtain ⟨j, hj⟩ := List.mem_iff_getElem?.mp ym
  exact fc.homes.apart i j x y hi hj fun same => ne (by rw [same] at hi; rw [hi] at hj; cases hj; rfl)

theorem LentHomes.unviewed : ∀ v ∈ st.i32ArrayViews, ∀ x ∈ places, v.root ≠ x.cell := fc.homes.unviewed

theorem LentHomes.room : 0 < bud.room + bud.block → hp.limit + bud.room ≤ hp.fsp := fc.homes.room

theorem LentHomes.ceiling : 0 < bud.room + bud.block → hp.fsp + bud.block ≤ hp.top := fc.homes.ceiling

theorem LentHomes.bounded : 0 < bud.room + bud.block → hp.top < 2 ^ 62 := fc.homes.bounded

theorem LentHomes.statics : hp.StaticsAt sx := fc.homes.statics

end

theorem LentHomes.nil (st : State) {hp : Heap} (room : 0 < bud.room + bud.block → hp.limit + bud.room ≤ hp.fsp)
    (ceiling : 0 < bud.room + bud.block → hp.fsp + bud.block ≤ hp.top)
    (bounded : 0 < bud.room + bud.block → hp.top < 2 ^ 62) (statics : hp.StaticsAt sx) :
    LentHomes sx bud [] st hp :=
  LentHomes.ofParts (fun _ mem => by simp at mem) (fun _ mem => by simp at mem) (fun _ mem => by simp at mem)
    (fun _ mem => by simp at mem) (fun _ _ _ _ hx => by simp at hx) (fun _ _ _ mem => by simp at mem) room ceiling
    bounded statics

/-- No places, and `need` bytes of frame memory room when `need` is positive:
where a program's run starts. -/
theorem LentHomes.start (st : State) {hp : Heap} {need : Nat}
    (frameRoom : 0 < need → hp.limit + need ≤ hp.fsp ∧ hp.fsp ≤ hp.top ∧ hp.top < 2 ^ 62)
    (statics : hp.StaticsAt sx) :
    LentHomes sx ⟨need, 0⟩ [] st hp :=
  LentHomes.nil st (fun pos => (frameRoom (by simpa using pos)).1)
    (fun pos => by simpa using (frameRoom (by simpa using pos)).2.1)
    (fun pos => (frameRoom (by simpa using pos)).2.2) statics

/-- No places, and no frame memory needed. -/
theorem LentHomes.empty (st : State) (hp : Heap) (statics : hp.StaticsAt sx) : LentHomes sx ⟨0, 0⟩ [] st hp :=
  LentHomes.nil st (fun pos => absurd pos (by decide)) (fun pos => absurd pos (by decide))
    (fun pos => absurd pos (by decide)) statics

/-- Changes to bytes no place takes, to the cursor or the trace, and to Core
cells no place names keep the correspondence. -/
theorem LentHomes.congrViews {st st' : State} {hp hp' : Heap}
    (fc : LentHomes sx bud places st hp)
    (cells : ∀ x ∈ places, st'.cellEntry? x.cell = st.cellEntry? x.cell)
    (bytes : ∀ x ∈ places, ∀ a, x.Within a → hp'.bytes a = hp.bytes a)
    (fsp : hp'.fsp = hp.fsp) (limit : hp'.limit = hp.limit) (top : hp'.top = hp.top)
    (unviewed : ∀ v ∈ st'.i32ArrayViews, ∀ x ∈ places, v.root ≠ x.cell)
    (statics : hp'.staticBase = hp.staticBase ∧ hp'.statics = hp.statics := by exact ⟨rfl, rfl⟩) :
    LentHomes sx bud places st' hp' := by
  refine LentHomes.ofParts (fun x mem => ?_) fc.packed (fun x mem => ?_) fc.small fc.homes.apart unviewed
    (by rw [fsp, limit]; exact fc.room) (by rw [fsp, top]; exact fc.ceiling) (by rw [top]; exact fc.bounded)
    (fc.statics.congr statics.1 statics.2 top)
  · obtain ⟨v, read, holds⟩ := fc.holds x mem
    refine ⟨v, ?_, holds.congr ((fc.packed x mem).view_congr (bytes x mem))⟩
    simp only [Semantics.readCellProjection, cells x mem] at read ⊢
    exact read
  · have := fc.inside x mem
    exact ⟨fsp ▸ this.1, limit ▸ this.2.1, top ▸ this.2.2⟩

/-- As `congrViews`, with the views as they were. -/
theorem LentHomes.congr {st st' : State} {hp hp' : Heap}
    (fc : LentHomes sx bud places st hp)
    (cells : ∀ x ∈ places, st'.cellEntry? x.cell = st.cellEntry? x.cell)
    (bytes : ∀ x ∈ places, ∀ a, x.Within a → hp'.bytes a = hp.bytes a)
    (fsp : hp'.fsp = hp.fsp) (limit : hp'.limit = hp.limit) (top : hp'.top = hp.top)
    (views : st'.i32ArrayViews = st.i32ArrayViews := by rfl)
    (statics : hp'.staticBase = hp.staticBase ∧ hp'.statics = hp.statics := by exact ⟨rfl, rfl⟩) :
    LentHomes sx bud places st' hp' :=
  fc.congrViews cells bytes fsp limit top (by rw [views]; exact fc.unviewed) statics

/-- A heap that differs only below the limit, with the same limit, top and
frame pointer, and Core cells no place names, keep the correspondence: the
bump heap is not frame memory. -/
theorem LentHomes.low {st st' : State} {hp hp' : Heap} (fc : LentHomes sx bud places st hp)
    (cells : ∀ x ∈ places, st'.cellEntry? x.cell = st.cellEntry? x.cell)
    (bytes : ∀ a, hp.limit ≤ a → hp'.bytes a = hp.bytes a)
    (fsp : hp'.fsp = hp.fsp) (limit : hp'.limit = hp.limit) (top : hp'.top = hp.top)
    (views : st'.i32ArrayViews = st.i32ArrayViews := by rfl)
    (statics : hp'.staticBase = hp.staticBase ∧ hp'.statics = hp.statics := by exact ⟨rfl, rfl⟩) :
    LentHomes sx bud places st' hp' :=
  fc.congr cells (fun x mem a within => bytes a (by
      have := fc.inside x mem; unfold Addressed.Within at within; omega))
    fsp limit top views statics

/-- A store below the frame pointer misses every place. -/
theorem LentHomes.writeLE_below {st : State} {hp : Heap}
    (fc : LentHomes sx bud places st hp) {address value count : Nat} (below : address + count ≤ hp.fsp) :
    LentHomes sx bud places st (hp.writeLE address value count) :=
  fc.congr (fun _ _ => rfl)
    (fun x mem a within => Heap.writeLE_bytes_outside _ _ _ _ _ (.inr (by
      have := fc.inside x mem; unfold Addressed.Within at within; omega)))
    (Heap.writeLE_top _ _ _ _).2 (Heap.writeLE_limit _ _ _ _).1 (Heap.writeLE_top _ _ _ _).1 rfl
    (Heap.writeLE_statics _ _ _ _)

/-- A store below the limit, into the bump heap, misses every place. -/
theorem LentHomes.writeLE_low {st : State} {hp : Heap}
    (fc : LentHomes sx bud places st hp) {address value count : Nat} (below : address + count ≤ hp.limit) :
    LentHomes sx bud places st (hp.writeLE address value count) :=
  fc.congr (fun _ _ => rfl)
    (fun x mem a within => Heap.writeLE_bytes_outside _ _ _ _ _ (.inr (by
      have := fc.inside x mem; unfold Addressed.Within at within; omega)))
    (Heap.writeLE_top _ _ _ _).2 (Heap.writeLE_limit _ _ _ _).1 (Heap.writeLE_top _ _ _ _).1 rfl
    (Heap.writeLE_statics _ _ _ _)

/-- A byte store below the limit misses every place. -/
theorem LentHomes.write_low {st : State} {hp : Heap}
    (fc : LentHomes sx bud places st hp) {address : Nat} {byte : UInt8} (below : address < hp.limit) :
    LentHomes sx bud places st (hp.write address byte) :=
  fc.congr (fun _ _ => rfl)
    (fun x mem a within => by
      have := fc.inside x mem; unfold Addressed.Within at within
      rw [Heap.write_bytes, if_neg (by omega)])
    rfl rfl rfl

/-- The places hold over a change below the limit. -/
theorem LentHomes.lowOnly {st : State} {hp hp' : Heap} (fc : LentHomes sx bud places st hp) (low : hp.LowOnly hp') :
    LentHomes sx bud places st hp' :=
  fc.low (fun _ _ => rfl) low.bytes low.fsp low.limit low.top rfl ⟨low.staticBase, low.statics⟩

/-- Core's heap is not frame memory. -/
theorem LentHomes.withHeap {st : State} {hp : Heap} (fc : LentHomes sx bud places st hp) (heap : Memory.Heap) :
    LentHomes sx bud places { st with heap } hp :=
  fc.congr (fun _ _ => rfl) (fun _ _ _ _ => rfl) rfl rfl rfl

/-- `frame` lowers the frame pointer and keeps every place: the bytes come
out of the room, and the new block is at most what was handed out over the
old one. -/
theorem LentHomes.frame {st : State} {hp : Heap}
    (fc : LentHomes sx bud places st hp) {bud' : Budget} (bytes : Nat) (room : bytes + bud'.room ≤ bud.room)
    (block : bud'.block ≤ bytes + bud.block) :
    LentHomes sx bud' places st { hp with fsp := hp.fsp - bytes } := by
  have room' := fc.room
  have ceiling' := fc.ceiling
  have bounded' := fc.bounded
  refine LentHomes.ofParts (fun x mem => ?_) fc.packed (fun x mem => ?_) fc.small fc.homes.apart fc.unviewed
    (fun pos => ?_) (fun pos => ?_) (fun pos => bounded' (by omega)) (fc.statics.congr rfl rfl rfl)
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
theorem LentHomes.restore {bud' : Budget} {st : State} {hp : Heap}
    (fc : LentHomes sx bud' places st hp) {fsp : Nat} (above : ∀ x ∈ places, fsp + bud.block ≤ x.address)
    (room : 0 < bud.room + bud.block → hp.limit + bud.room ≤ fsp)
    (ceiling : 0 < bud.room + bud.block → fsp + bud.block ≤ hp.top)
    (bounded : 0 < bud.room + bud.block → hp.top < 2 ^ 62) :
    LentHomes sx bud places st { hp with fsp := fsp } :=
  LentHomes.ofParts
    (fun x mem => by
      obtain ⟨v, read, holds⟩ := fc.holds x mem
      exact ⟨v, read, holds.congr (Addressed.view_congr fun _ _ => rfl)⟩)
    fc.packed (fun x mem => ⟨above x mem, (fc.inside x mem).2⟩) fc.small fc.homes.apart fc.unviewed room ceiling
    bounded (fc.statics.congr rfl rfl rfl)

/-- After a call: the callee's places with the caller's frame pointer and
budget, given the caller's correspondence before the call. -/
theorem LentHomes.back {bud' : Budget} {st st0 : State} {hp hp0 : Heap} (fc : LentHomes sx bud' places st hp)
    (caller : LentHomes sx bud places st0 hp0) (limit : hp.limit = hp0.limit) (top : hp.top = hp0.top) :
    LentHomes sx bud places st { hp with fsp := hp0.fsp } :=
  fc.restore (fun x mem => (caller.inside x mem).1) (fun pos => by rw [limit]; exact caller.room pos)
    (fun pos => by rw [top]; exact caller.ceiling pos) (fun pos => by rw [top]; exact caller.bounded pos)

/-- A callee with no block of its own and room no more than its caller's. -/
theorem LentHomes.callee {st : State} {hp : Heap} (fc : LentHomes sx bud places st hp) {bud' : Budget}
    (room : bud'.room ≤ bud.room) (block : bud'.block ≤ bud.block) : LentHomes sx bud' places st hp := by
  have room' := fc.room
  have ceiling' := fc.ceiling
  have bounded' := fc.bounded
  refine LentHomes.ofParts fc.holds fc.packed (fun x mem => ?_) fc.small fc.homes.apart fc.unviewed
    (fun pos => ?_) (fun pos => ?_) (fun pos => bounded' (by omega)) fc.statics
  · have inside := fc.inside x mem
    exact ⟨by omega, inside.2⟩
  · have := room' (by omega)
    omega
  · have := ceiling' (by omega)
    omega

/-- A place's words are below the top, and so below `2 ^ 62` with the heap. -/
theorem LentHomes.covers_top {st : State} {hp : Heap}
    (fc : LentHomes sx bud places st hp) {x : Addressed} (mem : x ∈ places) {a : Nat} (within : x.Within a) :
    hp.fsp ≤ a ∧ a < hp.top := by
  have := fc.inside x mem
  unfold Addressed.Within at within
  omega

/-- The correspondence for a callee's places holds for its caller's, the
ones after the arrays the callee was lent. -/
theorem LentHomes.drop {own : List Addressed} {st : State} {hp : Heap} (fc : LentHomes sx bud (own ++ places) st hp) :
    LentHomes sx bud places st hp := by
  have sub : ∀ x ∈ places, x ∈ own ++ places := fun x mem => List.mem_append_right _ mem
  refine LentHomes.ofParts (fun x mem => ?_) (fun x mem => fc.packed x (sub x mem))
    (fun x mem => fc.inside x (sub x mem)) (fun x mem => fc.small x (sub x mem)) (indexed_right fc.homes.apart)
    (fun v vmem x mem => fc.unviewed v vmem x (sub x mem)) fc.room fc.ceiling fc.bounded fc.statics
  obtain ⟨v, read, h⟩ := fc.holds x (sub x mem)
  exact ⟨v, read, (fc.packed x (sub x mem)).holdsAt h⟩

/-! ## A sliced place's array -/

/-- A sliced array place: Core's array in its cell, as long as its type
says, and its elements in the place's slots. -/
theorem LentHomes.array {st : State} {hp : Heap} (fc : LentHomes sx bud places st hp) {x : Addressed}
    (mem : x ∈ places) (root : x.projections = []) {element : SrcType} {n : Nat} (ty : x.ty = .array element n) :
    ∃ vs, Semantics.readCellProjection st x.cell [] = .ok (.array vs) ∧ vs.length = n ∧
      FieldsHold sx places (List.replicate n element) vs (x.view hp) 0 := by
  obtain ⟨v, read, holds⟩ := fc.holds x mem
  rw [root] at read
  rw [ty] at holds
  cases holds with
  | array elems => exact ⟨_, read, by simpa using elems.length, elems⟩

/-- Element `pos` of a borrowed slice, as Core reads it, is in the place's
slots of that element. -/
theorem LentHomes.borrowed_get {st : State} {hp : Heap} (fc : LentHomes sx bud places st hp) {x : Addressed}
    (mem : x ∈ places) (root : x.projections = []) {element : SrcType} {n : Nat} (ty : x.ty = .array element n)
    {elems : List Value} (values : Semantics.sliceValues st x.cell [] 0 n = .ok elems) {pos : Nat} {v : Value}
    (found : elems[pos]? = some v) : pos < n ∧ element.HoldsAt sx places v (x.view hp) (pos * element.size) := by
  obtain ⟨vs, read, len, elemsHold⟩ := fc.array mem root ty
  rw [← len, sliceValues_whole read] at values
  simp only [Except.ok.injEq] at values
  subst values
  refine ⟨?_, by simpa using fieldsHold_replicate_get elemsHold found⟩
  rw [← len]
  exact (List.getElem?_eq_some_iff.mp found).1

/-- A borrowed slice's reads never fail: every index below its length has
an element. -/
theorem LentHomes.borrowed_values {st : State} {hp : Heap} (fc : LentHomes sx bud places st hp) {x : Addressed}
    (mem : x ∈ places) (root : x.projections = []) {element : SrcType} {n : Nat} (ty : x.ty = .array element n) :
    ∃ vs, Semantics.sliceValues st x.cell [] 0 n = .ok vs ∧ vs.length = n := by
  obtain ⟨vs, read, len, -⟩ := fc.array mem root ty
  exact ⟨vs, by rw [← len]; exact sliceValues_whole read, len⟩

/-- The block of a sliced place: from its address, its words, below the top
and `2 ^ 62`. -/
theorem LentHomes.block {st : State} {hp : Heap} (fc : LentHomes sx bud places st hp) {x : Addressed}
    (mem : x ∈ places) : hp.limit ≤ x.address ∧ x.address + 8 * x.ty.words ≤ hp.top ∧
      x.address + 8 * x.ty.words < 2 ^ 62 :=
  ⟨(fc.inside x mem).2.1, (fc.inside x mem).2.2, fc.small x mem⟩

/-- A store into element `pos` of a sliced array place: Core's cell holds the
array with that element replaced, and the mini heap changed only in the
place's words, the element's slots holding the new value and the others
unchanged. The correspondence still holds. -/
theorem LentHomes.borrowed_set {st st' : State} {hp hp' : Heap} (fc : LentHomes sx bud places st hp) {x : Addressed}
    (mem : x ∈ places) (root : x.projections = []) {element : SrcType} {n : Nat} (ty : x.ty = .array element n)
    {vs : List Value} (read : Semantics.readCellProjection st x.cell [] = .ok (.array vs)) {pos : Nat} (lt : pos < n)
    {v : Value} (readNew : Semantics.readCellProjection st' x.cell [] = .ok (.array (Semantics.setValue vs pos v)))
    (others : ∀ y ∈ places, y.cell ≠ x.cell → st'.cellEntry? y.cell = st.cellEntry? y.cell)
    (held : element.HoldsAt sx places v (x.view hp') (pos * element.size))
    (away : ∀ s, s < pos * element.size ∨ pos * element.size + element.size ≤ s → x.view hp' s = x.view hp s)
    (bytes : ∀ a, ¬ x.Within a → hp'.bytes a = hp.bytes a)
    (fsp : hp'.fsp = hp.fsp) (limit : hp'.limit = hp.limit) (top : hp'.top = hp.top)
    (views : st'.i32ArrayViews = st.i32ArrayViews := by rfl)
    (statics : hp'.staticBase = hp.staticBase ∧ hp'.statics = hp.statics := by
      first | exact ⟨rfl, rfl⟩ | exact Heap.writeLE_statics _ _ _ _) :
    LentHomes sx bud places st' hp' := by
  refine LentHomes.ofParts (fun y ymem => ?_) fc.packed (fun y ymem => ?_) fc.small fc.homes.apart
    (by rw [views]; exact fc.unviewed) (by rw [fsp, limit]; exact fc.room)
    (by rw [fsp, top]; exact fc.ceiling) (by rw [top]; exact fc.bounded) (fc.statics.congr statics.1 statics.2 top)
  · by_cases same : y = x
    · subst same
      obtain ⟨vs', read', -, elems⟩ := fc.array mem root ty
      rw [read] at read'
      simp only [Except.ok.injEq, Value.array.injEq] at read'
      subst read'
      refine ⟨_, by rw [root]; exact readNew, ?_⟩
      rw [ty]
      exact .array (fieldsHold_replicate_set elems lt (by simpa using held) (by simpa using away))
    · obtain ⟨cellNe, apart⟩ := fc.apart y ymem x mem same
      obtain ⟨w, readY, holdsY⟩ := fc.holds y ymem
      refine ⟨w, ?_, holdsY.congr ((fc.packed y ymem).view_congr fun a within => bytes a ?_)⟩
      · simp only [Semantics.readCellProjection, others y ymem cellNe] at readY ⊢
        exact readY
      · intro withinX
        unfold Addressed.Within at within withinX
        omega
  · have := fc.inside y ymem
    exact ⟨fsp ▸ this.1, limit ▸ this.2.1, top ▸ this.2.2⟩

end Lanius.Mini
