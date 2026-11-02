module

public import Lanius.Semantics

@[expose] public section

/-! Core's `i32` array views (`i32_array_data_ptr`, SEMANTIC_DECISIONS
"Addressed locals" point 5, stage a). A view is a borrowed heap block that
Core keeps equal to an array cell: after a write to the cell it stores the
cell's encoding into the block (`syncI32ViewsToHeap`), after a raw store or
a host call it reads the block back into the cell (`syncI32ViewsFromHeap`).
`ViewsHold` says every view's block already holds its cell, so both syncs
are the identity. -/

namespace Lanius.Mini.Views

open Lanius Lanius.Core Lanius.Memory
open Lanius.Semantics (State Cell I32ArrayView)


/-! ## Bytes -/

theorem setByte_self : ∀ (bs : List UInt8) (i : Nat) (lt : i < bs.length), Memory.setByte bs i bs[i] = bs
  | [], _, lt => by simp at lt
  | _ :: _, 0, _ => rfl
  | b :: rest, i + 1, lt => by
    simp only [Memory.setByte, List.getElem_cons_succ]
    rw [setByte_self rest i (by simpa using lt)]

/-- Replacing a block by itself, when it is the only block at its base. -/
theorem replaceBlock_self : ∀ (blocks : List Block) (b : Block),
    (∀ c ∈ blocks, c.base = b.base → c = b) → Memory.replaceBlock blocks b = blocks
  | [], _, _ => rfl
  | c :: rest, b, only => by
    simp only [Memory.replaceBlock]
    rw [replaceBlock_self rest b fun d mem => only d (List.mem_cons_of_mem _ mem)]
    by_cases same : c.base = b.base
    · simp [only c (List.mem_cons_self ..) same]
    · simp [same]

/-- A live, borrowed block of the heap, apart from every other block (each
block takes at least one address, as the bump allocator gives it). -/
structure Owns (heap : Heap) (b : Block) : Prop where
  mem : b ∈ heap.blocks
  sized : b.bytes.length = b.size
  live : b.live = true
  borrowed : b.owned = false
  alone : ∀ c ∈ heap.blocks, c ≠ b → c.base + max c.size 1 ≤ b.base ∨ b.base + max b.size 1 ≤ c.base

/-- A block that ends below the next address. -/
def Before (heap : Heap) (b : Block) : Prop := b.base + max b.size 1 ≤ heap.nextAddress

theorem find?_unique {α : Type} {p : α → Bool} : ∀ {l : List α} {a : α}, a ∈ l → p a = true →
    (∀ c ∈ l, p c = true → c = a) → l.find? p = some a
  | [], _, mem, _, _ => by simp at mem
  | c :: rest, a, mem, pa, only => by
    by_cases pc : p c = true
    · rw [List.find?_cons_of_pos pc, only c (List.mem_cons_self ..) pc]
    · rw [List.find?_cons_of_neg pc]
      rcases List.mem_cons.mp mem with rfl | mem
      · exact absurd pa pc
      · exact find?_unique mem pa fun d dm => only d (List.mem_cons_of_mem _ dm)

/-- The only block at its base. -/
theorem Owns.only {heap : Heap} {b : Block} (owns : Owns heap b) : ∀ c ∈ heap.blocks, c.base = b.base → c = b := by
  intro c mem same
  by_cases eq : c = b
  · exact eq
  · have := Nat.le_max_right c.size 1
    have := Nat.le_max_right b.size 1
    have al := owns.alone c mem eq
    simp only [Lanius.Address] at *
    rcases al with h | h <;> omega

/-- The block holds each address of its own. -/
theorem Owns.holds {heap : Heap} {b : Block} (owns : Owns heap b) :
    ∀ i < b.size, heap.containingBlock? (b.base + i) = some b := by
  intro i lt
  refine find?_unique owns.mem (by simp [owns.live, lt]) fun c mem pc => ?_
  by_cases eq : c = b
  · exact eq
  · simp only [Bool.and_eq_true, decide_eq_true_eq] at pc
    have := Nat.le_max_left c.size 1
    have := Nat.le_max_left b.size 1
    have al := owns.alone c mem eq
    simp only [Lanius.Address] at *
    rcases al with h | h <;> omega

theorem storeByte_self {heap : Heap} {b : Block} (owns : Owns heap b) {i : Nat} (lt : i < b.size) :
    heap.storeByte b.base i (b.bytes[i]'(owns.sized ▸ lt)) = .ok heap := by
  simp only [Heap.storeByte, owns.holds i lt, Nat.add_sub_cancel_left]
  rw [setByte_self b.bytes i (owns.sized ▸ lt)]
  have : ({ b with bytes := b.bytes } : Block) = b := rfl
  rw [this, replaceBlock_self heap.blocks b owns.only]

theorem storeBytesFrom_self {heap : Heap} {b : Block} (owns : Owns heap b) :
    ∀ (k : Nat), k ≤ b.size → storeBytesFrom heap b.base k (b.bytes.drop k) = .ok heap := by
  intro k le
  induction h : b.size - k generalizing k with
  | zero =>
    have : b.bytes.drop k = [] := by simp [List.drop_eq_nil_iff, owns.sized]; omega
    rw [this]; rfl
  | succ n ih =>
    have lt : k < b.size := by omega
    have lt' : k < b.bytes.length := owns.sized ▸ lt
    rw [List.drop_eq_getElem_cons lt']
    simp only [storeBytesFrom, storeByte_self owns lt]
    exact ih (k + 1) (by omega) (by omega)

/-- Storing a block's own bytes at its base leaves the heap as it was. -/
theorem storeBytes_self {heap : Heap} {b : Block} (owns : Owns heap b) :
    heap.storeBytes b.base b.bytes = .ok heap := by
  have := storeBytesFrom_self owns 0 (Nat.zero_le _)
  simpa [Heap.storeBytes] using this

theorem loadByte_self {heap : Heap} {b : Block} (owns : Owns heap b) {i : Nat} (lt : i < b.size) :
    heap.loadByte b.base i = .ok (b.bytes[i]'(owns.sized ▸ lt)) := by
  simp only [Heap.loadByte, owns.holds i lt, Nat.add_sub_cancel_left]
  rw [List.getElem?_eq_getElem (owns.sized ▸ lt)]

theorem loadBytesFrom_self {heap : Heap} {b : Block} (owns : Owns heap b) :
    ∀ (k : Nat), k ≤ b.size → loadBytesFrom heap b.base k (b.size - k) = .ok (b.bytes.drop k) := by
  intro k le
  induction h : b.size - k generalizing k with
  | zero =>
    have : b.bytes.drop k = [] := by simp [List.drop_eq_nil_iff, owns.sized]; omega
    rw [this]; rfl
  | succ n ih =>
    have lt : k < b.size := by omega
    have lt' : k < b.bytes.length := owns.sized ▸ lt
    rw [List.drop_eq_getElem_cons lt']
    simp only [loadBytesFrom, loadByte_self owns lt]
    rw [ih (k + 1) (by omega) (by omega)]

/-- A block's bytes, loaded from its base. -/
theorem loadBytes_self {heap : Heap} {b : Block} (owns : Owns heap b) :
    heap.loadBytes b.base b.size = .ok b.bytes := by
  have := loadBytesFrom_self owns 0 (Nat.zero_le _)
  simpa [Heap.loadBytes] using this

/-! ## The `i32` codec -/

/-- An `i32` value in range, as Core's arithmetic leaves one. -/
def IsI32 (v : Value) : Prop := ∃ x : Int, v = .signed .i32 x ∧ -2 ^ 31 ≤ x ∧ x < 2 ^ 31

theorem i32Bytes_length (x : Int) : (Semantics.i32Bytes x).length = 4 := by
  simp [Semantics.i32Bytes]

theorem encodeI32Array_length : ∀ {vs : List Value} {bytes : List UInt8},
    Semantics.encodeI32Array vs = .ok bytes → bytes.length = 4 * vs.length
  | [], bytes, ok => by simp [Semantics.encodeI32Array] at ok; subst ok; rfl
  | .signed .i32 x :: rest, bytes, ok => by
    simp only [Semantics.encodeI32Array] at ok
    split at ok
    · rename_i tail run
      simp only [Except.ok.injEq] at ok
      subst ok
      simp [i32Bytes_length, encodeI32Array_length run]; omega
    · simp at ok
  | .unit :: _, _, ok | .boolean _ :: _, _, ok | .signed .i8 _ :: _, _, ok | .signed .i16 _ :: _, _, ok
  | .signed .i64 _ :: _, _, ok | .signed .isize _ :: _, _, ok | .unsigned _ _ :: _, _, ok
  | .f32Bits _ :: _, _, ok | .f64Bits _ :: _, _, ok | .character _ :: _, _, ok | .string _ :: _, _, ok
  | .pointer _ :: _, _, ok | .array _ :: _, _, ok | .slice .. :: _, _, ok | .rawSlice .. :: _, _, ok
  | .structure .. :: _, _, ok | .enumeration .. :: _, _, ok | .reference .. :: _, _, ok => by
    simp [Semantics.encodeI32Array] at ok

theorem decodeI32_i32Bytes {x : Int} (lo : -2 ^ 31 ≤ x) (hi : x < 2 ^ 31) (rest : List UInt8) :
    Semantics.decodeI32 (Semantics.i32Bytes x ++ rest) = x := by
  have key : ∀ m : Nat, (UInt8.ofNat m).toNat = m % 256 := fun m => by simp
  simp only [Semantics.i32Bytes, List.range, List.range.loop, List.map_cons, List.map_nil,
    List.cons_append, List.nil_append, Semantics.decodeI32, key, Nat.reduceMul, Nat.reducePow, Nat.pow_zero,
    Nat.div_one, Int.ofNat_eq_natCast]
  have hn' : (((x % 2 ^ 32).toNat : Nat) : Int) = x % 2 ^ 32 :=
    Int.toNat_of_nonneg (Int.emod_nonneg _ (by decide))
  generalize (x % 2 ^ 32).toNat = n at hn' ⊢
  split <;> omega

theorem decode_encode : ∀ {vs : List Value} {bytes : List UInt8}, (∀ v ∈ vs, IsI32 v) →
    Semantics.encodeI32Array vs = .ok bytes → Semantics.decodeI32Array vs.length bytes = .ok vs
  | [], bytes, _, ok => by
    simp [Semantics.encodeI32Array] at ok; subst ok; rfl
  | v :: rest, bytes, i32s, ok => by
    obtain ⟨x, rfl, lo, hi⟩ := i32s v (List.mem_cons_self ..)
    simp only [Semantics.encodeI32Array] at ok
    split at ok
    · rename_i tail run
      simp only [Except.ok.injEq] at ok
      subst ok
      have len := encodeI32Array_length run
      have inner := decode_encode (fun w mem => i32s w (List.mem_cons_of_mem _ mem)) run
      simp only [List.length_cons, Semantics.decodeI32Array, List.length_append, i32Bytes_length]
      rw [if_neg (by omega)]
      have drop : (Semantics.i32Bytes x ++ tail).drop 4 = tail := by
        rw [List.drop_append_of_le_length (by simp [i32Bytes_length])]; simp [i32Bytes_length]
      have take : (Semantics.i32Bytes x ++ tail).take 4 = Semantics.i32Bytes x ++ [] := by
        rw [List.take_append_of_le_length (by simp [i32Bytes_length]), List.append_nil]
        exact List.take_of_length_le (by simp [i32Bytes_length])
      rw [drop, inner, take, decodeI32_i32Bytes lo hi]
    · simp at ok

/-! ## Views that hold their cells -/

/-- View `v` holds: its root cell is the array `vs` of in-range `i32`s
(every cell with that id), and its block `b`, at the view's address and the
only block there, holds their encoding. -/
structure ViewHolds (cellList : List Cell) (heap : Heap) (v : I32ArrayView) (vs : List Value) (b : Block) :
    Prop where
  proj : v.projections = []
  cells : ∀ c ∈ cellList, c.id = v.root → c.value = some (.array vs)
  present : ∃ c ∈ cellList, c.id = v.root
  length : vs.length = v.length
  i32s : ∀ x ∈ vs, IsI32 x
  base : b.base = v.address
  owns : Owns heap b
  before : Before heap b
  bytes : Semantics.encodeI32Array vs = .ok b.bytes

/-- Every view of `st` holds its cell. -/
def ViewsHold (st : State) : Prop :=
  (∀ v ∈ st.i32ArrayViews, ∃ vs b, ViewHolds st.cells st.heap v vs b) ∧
    st.i32ArrayViews.Pairwise fun v w => v.root ≠ w.root

theorem ViewsHold.nil {st : State} (views : st.i32ArrayViews = []) : ViewsHold st := by
  exact ⟨fun v mem => by simp [views] at mem, by simp [views]⟩

theorem ViewHolds.cellEntry {st : State} {v : I32ArrayView} {vs : List Value} {b : Block}
    (h : ViewHolds st.cells st.heap v vs b) : st.cellEntry? v.root = some ⟨v.root, some (.array vs)⟩ := by
  obtain ⟨c, mem, id⟩ := h.present
  cases found : st.cellEntry? v.root with
  | none =>
    simp only [State.cellEntry?, List.find?_eq_none] at found
    exact absurd (by simpa using id) (found c mem)
  | some d =>
    have did : d.id = v.root := by simpa [State.cellEntry?] using List.find?_some found
    have dmem : d ∈ st.cells := List.mem_of_find?_eq_some found
    have := h.cells d dmem did
    cases d; simp_all

theorem ViewHolds.read {st : State} {v : I32ArrayView} {vs : List Value} {b : Block}
    (h : ViewHolds st.cells st.heap v vs b) : Semantics.readCellProjection st v.root v.projections = .ok (.array vs) := by
  simp [Semantics.readCellProjection, h.cellEntry, h.proj, Semantics.projectedValue]

theorem ViewHolds.size {st : State} {v : I32ArrayView} {vs : List Value} {b : Block}
    (h : ViewHolds st.cells st.heap v vs b) : b.size = v.length * 4 := by
  rw [← h.owns.sized, encodeI32Array_length h.bytes, h.length]; omega

theorem syncToFrom_ok {st : State} (hold : ViewsHold st) :
    ∀ (views : List I32ArrayView), (∀ v ∈ views, v ∈ st.i32ArrayViews) →
      Semantics.syncI32ViewsToHeapFrom views st = .ok st
  | [], _ => rfl
  | v :: rest, sub => by
    obtain ⟨vs, b, h⟩ := hold.1 v (sub v (List.mem_cons_self ..))
    simp only [Semantics.syncI32ViewsToHeapFrom, h.read, h.length, bne_self_eq_false, Bool.false_eq_true,
      ite_false, h.bytes, ← h.base, storeBytes_self h.owns]
    exact syncToFrom_ok hold rest fun w mem => sub w (List.mem_cons_of_mem _ mem)

/-- Under `ViewsHold`, Core's sync of the views to the heap changes nothing. -/
theorem syncTo_ok {st : State} (hold : ViewsHold st) : Semantics.syncI32ViewsToHeap st = .ok st :=
  syncToFrom_ok hold _ fun _ mem => mem

theorem replaceCell_self : ∀ (cells : List Cell) (id : Nat) (value : Value),
    (∀ c ∈ cells, c.id = id → c.value = some value) → Semantics.replaceCell cells id value = cells
  | [], _, _, _ => rfl
  | c :: rest, id, value, all => by
    simp only [Semantics.replaceCell]
    rw [replaceCell_self rest id value fun d mem => all d (List.mem_cons_of_mem _ mem)]
    by_cases same : c.id = id
    · have := all c (List.mem_cons_self ..) same
      cases c; simp_all
    · simp [same]

theorem ViewHolds.write {st : State} {v : I32ArrayView} {vs : List Value} {b : Block}
    (h : ViewHolds st.cells st.heap v vs b) :
    Semantics.writeResolvedPlace st { root := v.root, projections := v.projections, value := none }
      (.array vs) = .ok st := by
  simp only [Semantics.writeResolvedPlace, h.proj, Semantics.State.assignCell, h.cellEntry, Option.isSome_some,
    ite_true, replaceCell_self st.cells v.root (.array vs) h.cells]

theorem syncFromFrom_ok {st : State} (hold : ViewsHold st) :
    ∀ (views : List I32ArrayView), (∀ v ∈ views, v ∈ st.i32ArrayViews) →
      Semantics.syncI32ViewsFromHeapFrom views st = .ok st
  | [], _ => rfl
  | v :: rest, sub => by
    obtain ⟨vs, b, h⟩ := hold.1 v (sub v (List.mem_cons_self ..))
    have load : st.heap.loadBytes v.address (v.length * 4) = .ok b.bytes := by
      rw [← h.base, ← h.size]; exact loadBytes_self h.owns
    have decode : Semantics.decodeI32Array v.length b.bytes = .ok vs := by
      rw [← h.length]; exact decode_encode h.i32s h.bytes
    simp only [Semantics.syncI32ViewsFromHeapFrom, load, decode]
    rw [show ({ root := v.root, projections := v.projections, value := none } : Semantics.ResolvedPlace) =
      { root := v.root, projections := v.projections, value := none } from rfl] at *
    simp only [h.write]
    exact syncFromFrom_ok hold rest fun w mem => sub w (List.mem_cons_of_mem _ mem)

/-- Under `ViewsHold`, Core's sync of the heap back to the views changes nothing. -/
theorem syncFrom_ok {st : State} (hold : ViewsHold st) : Semantics.syncI32ViewsFromHeap st = .ok st :=
  syncFromFrom_ok hold _ fun _ mem => mem

/-! ## What keeps the views holding -/

/-- The views and their cells are as in `st`, and each view's block still
owns its bytes in the new heap: the views hold. -/
theorem ViewsHold.frame {st st' : State} (hold : ViewsHold st) (views : st'.i32ArrayViews = st.i32ArrayViews)
    (cells : ∀ v ∈ st.i32ArrayViews, ∀ c ∈ st'.cells, c.id = v.root → c ∈ st.cells)
    (present : ∀ v ∈ st.i32ArrayViews, ∀ c ∈ st.cells, c.id = v.root → c ∈ st'.cells)
    (owns : ∀ v ∈ st.i32ArrayViews, ∀ b, Owns st.heap b → Before st.heap b → b.base = v.address →
      Owns st'.heap b ∧ Before st'.heap b) :
    ViewsHold st' := by
  refine ⟨fun v mem => ?_, by rw [views]; exact hold.2⟩
  rw [views] at mem
  obtain ⟨vs, b, h⟩ := hold.1 v mem
  obtain ⟨c, cmem, cid⟩ := h.present
  obtain ⟨o, bf⟩ := owns v mem b h.owns h.before h.base
  exact ⟨vs, b, h.proj, fun d dmem did => h.cells d (cells v mem d dmem did) did,
    ⟨c, present v mem c cmem cid, cid⟩, h.length, h.i32s, h.base, o, bf, h.bytes⟩

/-- A new cell, numbered past every cell, leaves the views holding. -/
theorem ViewsHold.bindCell {st : State} (hold : ViewsHold st) (below : ∀ c ∈ st.cells, c.id < st.nextCell)
    (id : Nat) (value : Option Value) : ViewsHold (st.bindCell id value) := by
  refine hold.frame rfl ?_ (fun _ _ c mem _ => by simp [State.bindCell, mem]) fun _ _ _ owns before _ => ⟨owns, before⟩
  intro v mem c cmem cid
  simp only [State.bindCell, List.mem_append, List.mem_singleton] at cmem
  rcases cmem with old | rfl
  · exact old
  · obtain ⟨vs, b, h⟩ := hold.1 v mem
    obtain ⟨d, dmem, did⟩ := h.present
    have := below d dmem
    simp only [Lanius.CellId] at *
    omega

theorem ViewsHold.bindLocals : ∀ (bs : List (Nat × Value)) {st : State}, ViewsHold st →
    (∀ c ∈ st.cells, c.id < st.nextCell) → ViewsHold (st.bindLocals bs) ∧
      ∀ c ∈ (st.bindLocals bs).cells, c.id < (st.bindLocals bs).nextCell
  | [], _, hold, below => ⟨hold, below⟩
  | b :: bs, st, hold, below => by
    have below' : ∀ c ∈ (st.bindLocal b.1 b.2).cells, c.id < (st.bindLocal b.1 b.2).nextCell := by
      intro c mem
      simp only [State.bindLocal, State.bindCell, List.mem_append, List.mem_singleton] at mem ⊢
      rcases mem with old | rfl
      · have := below c old; simp only [Lanius.CellId] at *; omega
      · simp
    exact ViewsHold.bindLocals bs (hold.bindCell below b.1 (some b.2)) below'

theorem replaceCell_map : ∀ (cells : List Cell) (c : Nat) (v : Value),
    Semantics.replaceCell cells c v = cells.map fun cell => if cell.id == c then { cell with value := some v } else cell
  | [], _, _ => rfl
  | cell :: rest, c, v => by
    simp only [Semantics.replaceCell, List.map_cons]
    split <;> simp_all [replaceCell_map rest c v]

/-- Replacing a cell that no view roots at leaves the views holding. -/
theorem ViewsHold.replace {st : State} (hold : ViewsHold st) {c : Nat} {value : Value}
    (apart : ∀ v ∈ st.i32ArrayViews, v.root ≠ c) :
    ViewsHold { st with cells := Semantics.replaceCell st.cells c value } := by
  refine hold.frame rfl ?_ ?_ fun _ _ _ owns before _ => ⟨owns, before⟩
  · intro v mem d dmem did
    simp only [replaceCell_map, List.mem_map] at dmem
    obtain ⟨e, emem, rfl⟩ := dmem
    have ne := apart v mem
    by_cases same : e.id = c
    · simp only [same, beq_self_eq_true, ite_true] at did
      exact absurd (by simp only [Lanius.CellId] at *; omega) ne
    · simpa [same] using emem
  · intro v mem d dmem did
    simp only [replaceCell_map, List.mem_map]
    refine ⟨d, dmem, ?_⟩
    have ne := apart v mem
    have : d.id ≠ c := fun h => ne (did ▸ h)
    simp [this]

/-- A write of a cell that no view roots at leaves the views holding. -/
theorem ViewsHold.assignCell {st st' : State} (hold : ViewsHold st) {c : Nat} {value : Value}
    (ok : st.assignCell c value = some st') (apart : ∀ v ∈ st.i32ArrayViews, v.root ≠ c) : ViewsHold st' := by
  simp only [State.assignCell] at ok
  split at ok
  · simp only [Option.some.injEq] at ok
    subst ok
    exact hold.replace apart
  · simp at ok

/-- Every view roots at a cell below the next one. -/
theorem ViewsHold.root_lt {st : State} (hold : ViewsHold st) (below : ∀ c ∈ st.cells, c.id < st.nextCell) :
    ∀ v ∈ st.i32ArrayViews, v.root < st.nextCell := by
  intro v mem
  obtain ⟨vs, b, h⟩ := hold.1 v mem
  obtain ⟨c, cmem, cid⟩ := h.present
  rw [← cid]; exact below c cmem


theorem find?_append_some {α : Type} {p : α → Bool} {l : List α} {a : α} (found : l.find? p = some a)
    (more : List α) : (l ++ more).find? p = some a := by
  rw [List.find?_append, found]; rfl

theorem le_alignUp (x : Nat) {alignment : Nat} (pos : 0 < alignment) : x ≤ alignUp x alignment := by
  unfold alignUp
  have hq : x + alignment - 1 < alignment * ((x + alignment - 1) / alignment + 1) :=
    Nat.lt_mul_div_succ _ pos
  have e1 : alignment * ((x + alignment - 1) / alignment + 1) =
      (x + alignment - 1) / alignment * alignment + alignment := by
    rw [Nat.mul_add, Nat.mul_one, Nat.mul_comm]
  rw [e1] at hq
  generalize (x + alignment - 1) / alignment * alignment = m at hq ⊢
  omega

/-- A block appended at or above the next address keeps a block that ends
below it. -/
theorem Owns.push {heap : Heap} {b : Block} (owns : Owns heap b) (before : Before heap b) (c : Block)
    (above : heap.nextAddress ≤ c.base) (blocks : List Block) (eq : blocks = heap.blocks ++ [c]) (next : Nat)
    (le : heap.nextAddress ≤ next) (remaining : Option Nat) :
    Owns { heap with blocks, nextAddress := next, remaining } b ∧
      Before { heap with blocks, nextAddress := next, remaining } b := by
  subst eq
  unfold Before at before ⊢
  refine ⟨⟨by simp [owns.mem], owns.sized, owns.live, owns.borrowed, fun d mem ne => ?_⟩, Nat.le_trans before le⟩
  simp only [List.mem_append, List.mem_singleton] at mem
  rcases mem with old | rfl
  · exact owns.alone d old ne
  · exact .inr (Nat.le_trans before above)

theorem alignUp_above (heap : Heap) {alignment : Nat} (nz : alignment ≠ 0) :
    heap.nextAddress ≤ alignUp (max heap.nextAddress 1) alignment :=
  Nat.le_trans (Nat.le_max_left _ _) (le_alignUp _ (Nat.pos_of_ne_zero nz))

theorem validAlignment_ne {alignment : Nat} (valid : ¬(!validAlignment alignment) = true) : alignment ≠ 0 := by
  intro zero; simp [zero, validAlignment] at valid

/-- An allocation keeps a block that ends below the next address. -/
theorem Owns.allocate {heap heap' : Heap} {b : Block} (owns : Owns heap b) (before : Before heap b)
    {size alignment : Nat} {p : Nat} (ok : heap.allocate size alignment = .allocated p heap') :
    Owns heap' b ∧ Before heap' b := by
  simp only [Heap.allocate] at ok
  split at ok
  · simp at ok
  · rename_i valid
    have nz := validAlignment_ne valid
    split at ok
    · simp at ok
    · simp only [AllocationResult.allocated.injEq] at ok
      obtain ⟨rfl, rfl⟩ := ok
      have up := alignUp_above heap nz
      exact owns.push before _ up _ rfl _ (Nat.le_trans up (Nat.le_add_right _ _)) _

/-- A borrowed view's mapping keeps a block that ends below the next address. -/
theorem Owns.mapBorrowed {heap heap' : Heap} {b : Block} (owns : Owns heap b) (before : Before heap b)
    {bytes : List UInt8} {alignment : Nat} {p : Nat} (ok : heap.mapBorrowed bytes alignment = .allocated p heap') :
    Owns heap' b ∧ Before heap' b := by
  simp only [Heap.mapBorrowed] at ok
  split at ok
  · simp at ok
  · rename_i valid
    have nz := validAlignment_ne valid
    simp only [AllocationResult.allocated.injEq] at ok
    obtain ⟨rfl, rfl⟩ := ok
    have up := alignUp_above heap nz
    exact owns.push before _ up _ rfl _ (Nat.le_trans up (Nat.le_add_right _ _)) _

theorem replaceBlock_map : ∀ (blocks : List Block) (r : Block),
    replaceBlock blocks r = blocks.map fun x => if x.base == r.base then r else x
  | [], _ => rfl
  | x :: rest, r => by simp only [replaceBlock, List.map_cons, replaceBlock_map rest r]

/-- Replacing the blocks at another block's base by one with that block's
range keeps an owned block apart from it. -/
theorem Owns.replace {heap : Heap} {b : Block} (owns : Owns heap b) {c : Block} (cmem : c ∈ heap.blocks)
    (ne : c.base ≠ b.base) (r : Block) (base : r.base = c.base) (size : r.size = c.size) {heap' : Heap}
    (blocks : heap'.blocks = replaceBlock heap.blocks r) : Owns heap' b := by
  have cb : c ≠ b := fun h => ne (by rw [h])
  refine ⟨?_, owns.sized, owns.live, owns.borrowed, fun d dmem dne => ?_⟩
  · rw [blocks]
    simp only [replaceBlock_map, List.mem_map]
    exact ⟨b, owns.mem, by simp [base, Ne.symm ne]⟩
  · rw [blocks] at dmem
    simp only [replaceBlock_map, List.mem_map] at dmem
    obtain ⟨d0, d0mem, rfl⟩ := dmem
    by_cases same : d0.base = r.base
    · simp only [same, beq_self_eq_true, ite_true] at dne ⊢
      rw [base, size]; exact owns.alone c cmem cb
    · have : (d0.base == r.base) = false := by simp [same]
      simp only [this] at dne ⊢
      exact owns.alone d0 d0mem dne

/-- A deallocation keeps a borrowed block. -/
theorem Owns.deallocate {heap heap' : Heap} {b : Block} (owns : Owns heap b) {p s a : Nat}
    (ok : heap.deallocate p s a = .ok heap') : Owns heap' b ∧ heap'.nextAddress = heap.nextAddress := by
  simp only [Heap.deallocate] at ok
  split at ok
  · simp only [Except.ok.injEq] at ok; subst ok; exact ⟨owns, rfl⟩
  split at ok
  · simp at ok
  rename_i c found
  split at ok
  · simp at ok
  split at ok
  · simp at ok
  rename_i owned
  split at ok
  · simp at ok
  simp only [Except.ok.injEq] at ok
  subst ok
  have cmem : c ∈ heap.blocks := List.mem_of_find?_eq_some found
  have ne : c.base ≠ b.base := by
    intro same
    have := owns.only c cmem same
    subst this
    simp [owns.borrowed] at owned
  exact ⟨owns.replace cmem ne { c with live := false } rfl rfl rfl, rfl⟩

theorem setByte_len : ∀ (bs : List UInt8) (i : Nat) (v : UInt8), (Memory.setByte bs i v).length = bs.length
  | [], _, _ => rfl
  | _ :: _, 0, _ => rfl
  | _ :: rest, i + 1, v => by simp [Memory.setByte, setByte_len rest i v]

/-- A byte store keeps a block with the same range owned (its bytes may
change). -/
theorem Owns.storeByte {heap heap' : Heap} {b : Block} (owns : Owns heap b) {p o : Nat} {x : UInt8}
    (ok : heap.storeByte p o x = .ok heap') :
    ∃ b', Owns heap' b' ∧ b'.base = b.base ∧ b'.size = b.size ∧ heap'.nextAddress = heap.nextAddress := by
  simp only [Heap.storeByte] at ok
  split at ok
  · split at ok <;> (try split at ok) <;> simp at ok
  rename_i c found
  simp only [Except.ok.injEq] at ok
  subst ok
  have cmem : c ∈ heap.blocks := List.mem_of_find?_eq_some found
  by_cases same : c.base = b.base
  · have := owns.only c cmem same
    subst this
    refine ⟨{ c with bytes := Memory.setByte c.bytes (p + o - c.base) x }, ⟨?_, ?_, owns.live, owns.borrowed, ?_⟩,
      rfl, rfl, rfl⟩
    · simp only [replaceBlock_map, List.mem_map]
      exact ⟨c, cmem, by simp⟩
    · simp only [setByte_len, owns.sized]
    · intro d dmem dne
      simp only [replaceBlock_map, List.mem_map] at dmem
      obtain ⟨d0, d0mem, rfl⟩ := dmem
      by_cases eq : d0.base = c.base
      · simp [eq] at dne
      · have : (d0.base == c.base) = false := by simp [eq]
        simp only [this] at dne ⊢
        exact owns.alone d0 d0mem fun h => eq (by rw [h])
  · exact ⟨b, owns.replace cmem same { c with bytes := Memory.setByte c.bytes (p + o - c.base) x } rfl rfl rfl,
      rfl, rfl, rfl⟩

/-- Byte stores keep a block with the same range owned. -/
theorem Owns.storeBytesFrom : ∀ (bytes : List UInt8) {heap heap' : Heap} {b : Block} {p o : Nat},
    Owns heap b → storeBytesFrom heap p o bytes = .ok heap' →
      ∃ b', Owns heap' b' ∧ b'.base = b.base ∧ b'.size = b.size ∧ heap'.nextAddress = heap.nextAddress
  | [], heap, heap', b, p, o, owns, ok => by
    simp only [Memory.storeBytesFrom, Except.ok.injEq] at ok
    subst ok; exact ⟨b, owns, rfl, rfl, rfl⟩
  | x :: rest, heap, heap', b, p, o, owns, ok => by
    simp only [Memory.storeBytesFrom] at ok
    split at ok
    · simp at ok
    rename_i mid stored
    obtain ⟨b1, owns1, base1, size1, next1⟩ := owns.storeByte stored
    obtain ⟨b2, owns2, base2, size2, next2⟩ := Owns.storeBytesFrom rest owns1 ok
    exact ⟨b2, owns2, base2.trans base1, size2.trans size1, next2.trans next1⟩

theorem Owns.storeBytes {heap heap' : Heap} {b : Block} (owns : Owns heap b) {p : Nat} {bytes : List UInt8}
    (ok : heap.storeBytes p bytes = .ok heap') :
    ∃ b', Owns heap' b' ∧ b'.base = b.base ∧ b'.size = b.size ∧ heap'.nextAddress = heap.nextAddress :=
  Owns.storeBytesFrom bytes owns ok

/-! ## Reading the views back from the heap -/

theorem decodeI32_range (bs : List UInt8) :
    -2 ^ 31 ≤ Semantics.decodeI32 bs ∧ Semantics.decodeI32 bs < 2 ^ 31 := by
  match bs with
  | b0 :: b1 :: b2 :: b3 :: _ =>
    have := b0.toNat_lt; have := b1.toNat_lt; have := b2.toNat_lt; have := b3.toNat_lt
    simp only [Semantics.decodeI32]
    split <;> simp only [Int.ofNat_eq_natCast] <;> omega
  | [] | [_] | [_, _] | [_, _, _] => simp [Semantics.decodeI32]

theorem i32Bytes_decode (b0 b1 b2 b3 : UInt8) :
    Semantics.i32Bytes (Semantics.decodeI32 [b0, b1, b2, b3]) = [b0, b1, b2, b3] := by
  have h0 := b0.toNat_lt; have h1 := b1.toNat_lt; have h2 := b2.toNat_lt; have h3 := b3.toNat_lt
  have key : Semantics.decodeI32 [b0, b1, b2, b3] % 2 ^ 32 =
      ((b0.toNat + b1.toNat * 2 ^ 8 + b2.toNat * 2 ^ 16 + b3.toNat * 2 ^ 24 : Nat) : Int) := by
    simp only [Semantics.decodeI32]
    split <;> simp only [Int.ofNat_eq_natCast] <;> omega
  have byte : ∀ m : Nat, (UInt8.ofNat m).toNat = m % 256 := fun m => by simp
  simp only [Semantics.i32Bytes, key, Int.toNat_natCast, List.range, List.range.loop, List.map_cons, List.map_nil]
  refine List.cons_eq_cons.mpr ⟨?_, List.cons_eq_cons.mpr ⟨?_, List.cons_eq_cons.mpr ⟨?_,
    List.cons_eq_cons.mpr ⟨?_, rfl⟩⟩⟩⟩ <;> apply UInt8.toNat_inj.mp <;>
    simp only [byte, Nat.reduceMul, Nat.reducePow, Nat.pow_zero, Nat.div_one] <;> omega

/-- What Core's decoder of `n` `i32`s gives: `n` in-range values whose
encoding is the bytes. -/
theorem decode_spec : ∀ (n : Nat) {bytes : List UInt8} {vs : List Value},
    Semantics.decodeI32Array n bytes = .ok vs →
      vs.length = n ∧ (∀ x ∈ vs, IsI32 x) ∧ Semantics.encodeI32Array vs = .ok bytes
  | 0, bytes, vs, ok => by
    simp only [Semantics.decodeI32Array] at ok
    split at ok
    · rename_i empty
      simp only [Except.ok.injEq] at ok
      subst ok
      simp only [List.isEmpty_iff] at empty
      subst empty
      exact ⟨rfl, by simp, rfl⟩
    · simp at ok
  | n + 1, bytes, vs, ok => by
    simp only [Semantics.decodeI32Array] at ok
    split at ok
    · simp at ok
    rename_i long
    split at ok
    · rename_i rest decoded
      simp only [Except.ok.injEq] at ok
      subst ok
      obtain ⟨len, i32s, enc⟩ := decode_spec n decoded
      refine ⟨by simp [len], ?_, ?_⟩
      · intro x mem
        rcases List.mem_cons.mp mem with rfl | mem
        · exact ⟨_, rfl, decodeI32_range _⟩
        · exact i32s x mem
      · simp only [Semantics.encodeI32Array, enc]
        match bytes, long with
        | b0 :: b1 :: b2 :: b3 :: tail, _ =>
          simp only [List.take, List.drop, i32Bytes_decode, List.cons_append, List.nil_append]
        | [], h | [_], h | [_, _], h | [_, _, _], h => simp at h
    · simp at ok

/-- A view whose root cell is present and whose block is owned, with room for
its elements: what Core's sync from the heap needs. -/
structure ViewLive (cellList : List Cell) (heap : Heap) (v : I32ArrayView) : Prop where
  proj : v.projections = []
  present : ∃ c ∈ cellList, c.id = v.root
  block : ∃ b, Owns heap b ∧ Before heap b ∧ b.base = v.address ∧ b.size = v.length * 4

theorem ViewHolds.live {cellList : List Cell} {heap : Heap} {v : I32ArrayView} {vs : List Value} {b : Block}
    (h : ViewHolds cellList heap v vs b) : ViewLive cellList heap v := by
  refine ⟨h.proj, h.present, b, h.owns, h.before, h.base, ?_⟩
  rw [← h.owns.sized, encodeI32Array_length h.bytes, h.length]; omega

theorem replaceCell_ids {cells : List Cell} {target : Nat} {value : Value} :
    ∀ c ∈ cells, ∃ d ∈ Semantics.replaceCell cells target value, d.id = c.id := by
  intro c mem
  simp only [replaceCell_map, List.mem_map]
  refine ⟨_, ⟨c, mem, rfl⟩, ?_⟩
  split <;> rfl

theorem replaceCell_find_other : ∀ (cells : List Cell) {target c : Nat} {value : Value}, target ≠ c →
    (Semantics.replaceCell cells target value).find? (fun cell => cell.id == c) =
      cells.find? (fun cell => cell.id == c)
  | [], _, _, _, _ => rfl
  | cell :: rest, target, c, value, ne => by
    simp only [Semantics.replaceCell]
    by_cases same : cell.id = target
    · have hc : (cell.id == c) = false := by simp only [beq_eq_false_iff_ne]; intro h; exact ne (same ▸ h)
      have hc' : ({ cell with value := some value } : Cell).id = cell.id := rfl
      simp only [same, beq_self_eq_true, ite_true, List.find?_cons]
      simp only [same] at hc
      simp only [hc, replaceCell_find_other rest ne]
    · have : (cell.id == target) = false := by simp [same]
      simp only [this, Bool.false_eq_true, ite_false, List.find?_cons, replaceCell_find_other rest ne]

theorem cellEntry_replace_other (st : State) {target c : Nat} {value : Value} (ne : target ≠ c) :
    ({ st with cells := Semantics.replaceCell st.cells target value } : State).cellEntry? c = st.cellEntry? c :=
  replaceCell_find_other st.cells ne

theorem syncFromFrom_holds : ∀ (l : List I32ArrayView) {st st' : State},
    (∀ v ∈ l, ViewLive st.cells st.heap v) → l.Pairwise (fun v w => v.root ≠ w.root) →
    Semantics.syncI32ViewsFromHeapFrom l st = .ok st' →
      st'.heap = st.heap ∧ st'.i32ArrayViews = st.i32ArrayViews ∧
      (∀ v ∈ l, ∃ vs b, ViewHolds st'.cells st'.heap v vs b) ∧
      (∀ c ∈ st'.cells, (∀ v ∈ l, c.id ≠ v.root) → c ∈ st.cells) ∧
      (∀ c ∈ st.cells, ∃ d ∈ st'.cells, d.id = c.id) ∧
      (∀ c, (∀ v ∈ l, v.root ≠ c) → st'.cellEntry? c = st.cellEntry? c)
  | [], st, st', _, _, ok => by
    simp only [Semantics.syncI32ViewsFromHeapFrom, Except.ok.injEq] at ok
    subst ok
    exact ⟨rfl, rfl, by simp, fun c mem _ => mem, fun c mem => ⟨c, mem, rfl⟩, fun _ _ => rfl⟩
  | v :: rest, st, st', live, apart, ok => by
    obtain ⟨proj, ⟨c0, c0mem, c0id⟩, b, owns, before, base, size⟩ := live v (List.mem_cons_self ..)
    have load : st.heap.loadBytes v.address (v.length * 4) = .ok b.bytes := by
      rw [← base, ← size]; exact loadBytes_self owns
    simp only [Semantics.syncI32ViewsFromHeapFrom, load] at ok
    split at ok
    · simp at ok
    rename_i vs decoded
    obtain ⟨len, i32s, enc⟩ := decode_spec v.length decoded
    have entry : (st.cellEntry? v.root).isSome = true := by
      cases found : st.cellEntry? v.root with
      | some _ => rfl
      | none =>
        simp only [State.cellEntry?, List.find?_eq_none] at found
        exact absurd (by simpa using c0id) (found c0 c0mem)
    simp only [Semantics.writeResolvedPlace, proj, State.assignCell, entry, ite_true] at ok
    obtain ⟨heapEq, viewsEq, holds, from_, ids, others⟩ := syncFromFrom_holds rest (st := { st with
      cells := Semantics.replaceCell st.cells v.root (.array vs) })
      (fun w wmem => by
        obtain ⟨wproj, ⟨d, dmem, did⟩, wblock⟩ := live w (List.mem_cons_of_mem _ wmem)
        obtain ⟨d', d'mem, d'id⟩ := replaceCell_ids (target := v.root) (value := .array vs) d dmem
        exact ⟨wproj, ⟨d', d'mem, d'id.trans did⟩, wblock⟩)
      (List.pairwise_cons.mp apart).2 ok
    have vrest := (List.pairwise_cons.mp apart).1
    refine ⟨heapEq, viewsEq, fun w wmem => ?_, fun c cmem notRoot => ?_, fun c cmem => ?_, fun c notRoot => ?_⟩
    rotate_left 3
    · rw [others c fun u umem => notRoot u (List.mem_cons_of_mem _ umem)]
      exact cellEntry_replace_other st (notRoot v (List.mem_cons_self ..))
    · rcases List.mem_cons.mp wmem with rfl | wmem
      · refine ⟨vs, b, proj, fun c cmem cid => ?_, ?_, len, i32s, base, by rw [heapEq]; exact owns,
          by rw [heapEq]; exact before, enc⟩
        · have inner := from_ c cmem fun u umem => by rw [cid]; exact vrest u umem
          simp only [replaceCell_map, List.mem_map] at inner
          obtain ⟨e, -, rfl⟩ := inner
          have eid : e.id = w.root := by
            by_cases same : e.id = w.root
            · exact same
            · exfalso; simp [same] at cid
          simp [eid]
        · obtain ⟨d, dmem, did⟩ := replaceCell_ids (target := w.root) (value := .array vs) c0 c0mem
          obtain ⟨e, emem, eid⟩ := ids d dmem
          exact ⟨e, emem, eid.trans (did.trans c0id)⟩
      · exact holds w wmem
    · have inner := from_ c cmem fun u umem => notRoot u (List.mem_cons_of_mem _ umem)
      simp only [replaceCell_map, List.mem_map] at inner
      obtain ⟨e, emem, rfl⟩ := inner
      have ne : e.id ≠ v.root := by
        intro same
        apply notRoot v (List.mem_cons_self ..)
        simp [same]
      simpa [ne] using emem
    · obtain ⟨d, dmem, did⟩ := replaceCell_ids (target := v.root) (value := .array vs) c cmem
      obtain ⟨e, emem, eid⟩ := ids d dmem
      exact ⟨e, emem, eid.trans did⟩

/-- Core's sync from the heap, from live views, leaves them holding. -/
theorem syncFrom_holds {st st' : State} (live : ∀ v ∈ st.i32ArrayViews, ViewLive st.cells st.heap v)
    (apart : st.i32ArrayViews.Pairwise fun v w => v.root ≠ w.root)
    (ok : Semantics.syncI32ViewsFromHeap st = .ok st') : ViewsHold st' ∧ st'.heap = st.heap ∧
      st'.i32ArrayViews = st.i32ArrayViews ∧ (∀ c ∈ st'.cells, (∀ v ∈ st.i32ArrayViews, c.id ≠ v.root) → c ∈ st.cells) ∧
      (∀ c ∈ st.cells, ∃ d ∈ st'.cells, d.id = c.id) ∧
      (∀ c, (∀ v ∈ st.i32ArrayViews, v.root ≠ c) → st'.cellEntry? c = st.cellEntry? c) := by
  obtain ⟨heapEq, viewsEq, holds, from_, ids, others⟩ := syncFromFrom_holds _ live apart ok
  exact ⟨⟨fun v mem => holds v (viewsEq ▸ mem), by rw [viewsEq]; exact apart⟩, heapEq, viewsEq, from_, ids, others⟩

/-! ## Heap changes -/

theorem ViewsHold.live {st : State} (hold : ViewsHold st) : ∀ v ∈ st.i32ArrayViews, ViewLive st.cells st.heap v :=
  fun v mem => let ⟨_, _, h⟩ := hold.1 v mem; h.live

/-- The cells and views as they were, and each owned block that ended below
the next address still does: the views hold. -/
theorem ViewsHold.heapOf {st st' : State} (hold : ViewsHold st) (cells : st'.cells = st.cells)
    (views : st'.i32ArrayViews = st.i32ArrayViews)
    (keep : ∀ b, Owns st.heap b → Before st.heap b → Owns st'.heap b ∧ Before st'.heap b) : ViewsHold st' :=
  hold.frame views (fun _ _ c mem _ => cells ▸ mem) (fun _ _ c mem _ => cells ▸ mem) fun _ _ b o bf _ => keep b o bf

/-- A heap change that keeps each owned block's range owned, below the next
address (its bytes may change). -/
def Stores (heap heap' : Heap) : Prop :=
  ∀ b, Owns heap b → Before heap b → ∃ b', Owns heap' b' ∧ Before heap' b' ∧ b'.base = b.base ∧ b'.size = b.size

theorem Stores.refl (heap : Heap) : Stores heap heap := fun b o bf => ⟨b, o, bf, rfl, rfl⟩

theorem Stores.trans {a b c : Heap} (first : Stores a b) (second : Stores b c) : Stores a c := fun x o bf =>
  let ⟨y, oy, by_, ey, sy⟩ := first x o bf
  let ⟨z, oz, bz, ez, sz⟩ := second y oy by_
  ⟨z, oz, bz, ez.trans ey, sz.trans sy⟩

theorem Stores.storeBytes {heap heap' : Heap} {p : Nat} {bytes : List UInt8}
    (ok : heap.storeBytes p bytes = .ok heap') : Stores heap heap' := fun b o bf => by
  obtain ⟨b', o', base, size, next⟩ := o.storeBytes ok
  refine ⟨b', o', ?_, base, size⟩
  unfold Before at bf ⊢
  rw [base, size, next]; exact bf

theorem Stores.storeByte {heap heap' : Heap} {p off : Nat} {x : UInt8}
    (ok : heap.storeByte p off x = .ok heap') : Stores heap heap' := fun b o bf => by
  obtain ⟨b', o', base, size, next⟩ := o.storeByte ok
  refine ⟨b', o', ?_, base, size⟩
  unfold Before at bf ⊢
  rw [base, size, next]; exact bf

theorem writeResolved_frame {st st' : State} {r : Semantics.ResolvedPlace} {v : Value}
    (ok : Semantics.writeResolvedPlace st r v = .ok st') :
    st'.heap = st.heap ∧ st'.i32ArrayViews = st.i32ArrayViews ∧ st'.locals = st.locals ∧
      st'.nextCell = st.nextCell ∧ st'.world = st.world := by
  unfold Semantics.writeResolvedPlace at ok
  split at ok
  · split at ok
    · simp only [Except.ok.injEq] at ok
      subst ok
      rename_i assigned h
      simp only [State.assignCell] at h
      split at h
      · simp only [Option.some.injEq] at h; subst h; exact ⟨rfl, rfl, rfl, rfl, rfl⟩
      · simp at h
    · simp at ok
  · split at ok
    · simp at ok
    · simp at ok
    · split at ok
      · simp at ok
      · split at ok
        · simp only [Except.ok.injEq] at ok
          subst ok
          rename_i assigned h
          simp only [State.assignCell] at h
          split at h
          · simp only [Option.some.injEq] at h; subst h; exact ⟨rfl, rfl, rfl, rfl, rfl⟩
          · simp at h
        · simp at ok

theorem syncFromFrom_frame : ∀ (l : List I32ArrayView) {st st' : State},
    Semantics.syncI32ViewsFromHeapFrom l st = .ok st' →
      st'.locals = st.locals ∧ st'.nextCell = st.nextCell ∧ st'.world = st.world
  | [], st, st', ok => by
    simp only [Semantics.syncI32ViewsFromHeapFrom, Except.ok.injEq] at ok
    subst ok; exact ⟨rfl, rfl, rfl⟩
  | v :: rest, st, st', ok => by
    simp only [Semantics.syncI32ViewsFromHeapFrom] at ok
    split at ok
    · simp at ok
    · split at ok
      · simp at ok
      · split at ok
        · simp at ok
        · rename_i next written
          obtain ⟨l1, n1, w1⟩ := syncFromFrom_frame rest ok
          obtain ⟨-, -, l2, n2, w2⟩ := writeResolved_frame written
          exact ⟨l1.trans l2, n1.trans n2, w1.trans w2⟩

/-- After heap stores, Core's sync from the heap leaves the views holding,
and the cells no view roots at as they were. -/
theorem ViewsHold.afterStores {st s st' : State} (hold : ViewsHold st) (stores : Stores st.heap s.heap)
    (cells : s.cells = st.cells) (views : s.i32ArrayViews = st.i32ArrayViews)
    (ok : Semantics.syncI32ViewsFromHeap s = .ok st') :
    ViewsHold st' ∧ st'.heap = s.heap ∧ st'.i32ArrayViews = st.i32ArrayViews ∧
      (∀ c, (∀ v ∈ st.i32ArrayViews, v.root ≠ c) → st'.cellEntry? c = s.cellEntry? c) ∧
      st'.nextCell = s.nextCell ∧ st'.locals = s.locals ∧ st'.world = s.world ∧
      ((∀ c ∈ s.cells, c.id < s.nextCell) → ∀ c ∈ st'.cells, c.id < st'.nextCell) := by
  have live : ∀ v ∈ s.i32ArrayViews, ViewLive s.cells s.heap v := by
    intro v mem
    rw [views] at mem
    obtain ⟨proj, present, b, o, bf, base, size⟩ := hold.live v mem
    obtain ⟨b', o', bf', base', size'⟩ := stores b o bf
    exact ⟨proj, cells ▸ present, b', o', bf', base'.trans base, size'.trans size⟩
  obtain ⟨hold', heapEq, viewsEq, from_, -, others⟩ := syncFrom_holds live (by rw [views]; exact hold.2) ok
  obtain ⟨locals, next, world⟩ := syncFromFrom_frame _ ok
  refine ⟨hold', heapEq, viewsEq.trans views, fun c away => others c (views ▸ away), next, locals, world,
    fun below c mem => ?_⟩
  rw [next]
  rcases Classical.em (∃ v ∈ s.i32ArrayViews, c.id = v.root) with ⟨v, vmem, eq⟩ | none
  · obtain ⟨d, dmem, did⟩ := (live v vmem).present
    rw [eq, ← did]; exact below d dmem
  · exact below c (from_ c mem fun v vm h => none ⟨v, vm, h⟩)

theorem decode_ok : ∀ (n : Nat) (bytes : List UInt8), bytes.length = n * 4 →
    ∃ vs, Semantics.decodeI32Array n bytes = .ok vs
  | 0, bytes, len => by
    have : bytes = [] := List.eq_nil_of_length_eq_zero (by simpa using len)
    subst this
    exact ⟨[], rfl⟩
  | n + 1, bytes, len => by
    obtain ⟨rest, ok⟩ := decode_ok n (bytes.drop 4) (by rw [List.length_drop, len, Nat.succ_mul]; omega)
    refine ⟨.signed .i32 (Semantics.decodeI32 (bytes.take 4)) :: rest, ?_⟩
    simp only [Semantics.decodeI32Array]
    rw [if_neg (by rw [len, Nat.succ_mul]; omega), ok]

theorem syncFromFrom_exists : ∀ (l : List I32ArrayView) (st : State),
    (∀ v ∈ l, ViewLive st.cells st.heap v) → ∃ st', Semantics.syncI32ViewsFromHeapFrom l st = .ok st'
  | [], st, _ => ⟨st, rfl⟩
  | v :: rest, st, live => by
    obtain ⟨proj, ⟨c0, c0mem, c0id⟩, b, owns, before, base, size⟩ := live v (List.mem_cons_self ..)
    have load : st.heap.loadBytes v.address (v.length * 4) = .ok b.bytes := by
      rw [← base, ← size]; exact loadBytes_self owns
    obtain ⟨vs, decoded⟩ := decode_ok v.length b.bytes (by rw [owns.sized, size])
    have entry : (st.cellEntry? v.root).isSome = true := by
      cases found : st.cellEntry? v.root with
      | some _ => rfl
      | none =>
        simp only [State.cellEntry?, List.find?_eq_none] at found
        exact absurd (by simpa using c0id) (found c0 c0mem)
    simp only [Semantics.syncI32ViewsFromHeapFrom, load, decoded]
    simp only [Semantics.writeResolvedPlace, proj, State.assignCell, entry, ite_true]
    exact syncFromFrom_exists rest _ fun w wmem => by
      obtain ⟨wproj, ⟨d, dmem, did⟩, wblock⟩ := live w (List.mem_cons_of_mem _ wmem)
      obtain ⟨d', d'mem, d'id⟩ := replaceCell_ids (target := v.root) (value := .array vs) d dmem
      exact ⟨wproj, ⟨d', d'mem, d'id.trans did⟩, wblock⟩

/-- After heap stores, Core's sync from the heap succeeds. -/
theorem ViewsHold.syncAfter {st s : State} (hold : ViewsHold st) (stores : Stores st.heap s.heap)
    (cells : s.cells = st.cells) (views : s.i32ArrayViews = st.i32ArrayViews) :
    ∃ st', Semantics.syncI32ViewsFromHeap s = .ok st' :=
  syncFromFrom_exists _ s fun v mem => by
    rw [views] at mem
    obtain ⟨proj, present, b, o, bf, base, size⟩ := hold.live v mem
    obtain ⟨b', o', bf', base', size'⟩ := stores b o bf
    exact ⟨proj, cells ▸ present, b', o', bf', base'.trans base, size'.trans size⟩

theorem ViewsHold.allocate {st : State} (hold : ViewsHold st) {size alignment p : Nat} {heap' : Heap}
    (ok : st.heap.allocate size alignment = .allocated p heap') : ViewsHold { st with heap := heap' } :=
  hold.heapOf rfl rfl fun _ o bf => o.allocate bf ok

theorem ViewsHold.deallocate {st : State} (hold : ViewsHold st) {p size alignment : Nat} {heap' : Heap}
    (ok : st.heap.deallocate p size alignment = .ok heap') : ViewsHold { st with heap := heap' } :=
  hold.heapOf rfl rfl fun _ o bf => by
    obtain ⟨o', next⟩ := o.deallocate ok
    refine ⟨o', ?_⟩
    unfold Before at bf ⊢
    show _ ≤ heap'.nextAddress
    rw [next]; exact bf

end Lanius.Mini.Views


