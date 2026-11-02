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

/-- A block that holds the address `base + i` for each `i` below its size,
and is the only one at its base. -/
structure Owns (heap : Heap) (b : Block) : Prop where
  mem : b ∈ heap.blocks
  sized : b.bytes.length = b.size
  holds : ∀ i < b.size, heap.containingBlock? (b.base + i) = some b
  only : ∀ c ∈ heap.blocks, c.base = b.base → c = b

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
structure ViewHolds (st : State) (v : I32ArrayView) (vs : List Value) (b : Block) : Prop where
  proj : v.projections = []
  cells : ∀ c ∈ st.cells, c.id = v.root → c.value = some (.array vs)
  present : ∃ c ∈ st.cells, c.id = v.root
  length : vs.length = v.length
  i32s : ∀ x ∈ vs, IsI32 x
  base : b.base = v.address
  owns : Owns st.heap b
  bytes : Semantics.encodeI32Array vs = .ok b.bytes

/-- Every view of `st` holds its cell. -/
def ViewsHold (st : State) : Prop := ∀ v ∈ st.i32ArrayViews, ∃ vs b, ViewHolds st v vs b

theorem ViewsHold.nil {st : State} (views : st.i32ArrayViews = []) : ViewsHold st := by
  intro v mem; simp [views] at mem

theorem ViewHolds.cellEntry {st : State} {v : I32ArrayView} {vs : List Value} {b : Block}
    (h : ViewHolds st v vs b) : st.cellEntry? v.root = some ⟨v.root, some (.array vs)⟩ := by
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
    (h : ViewHolds st v vs b) : Semantics.readCellProjection st v.root v.projections = .ok (.array vs) := by
  simp [Semantics.readCellProjection, h.cellEntry, h.proj, Semantics.projectedValue]

theorem ViewHolds.size {st : State} {v : I32ArrayView} {vs : List Value} {b : Block}
    (h : ViewHolds st v vs b) : b.size = v.length * 4 := by
  rw [← h.owns.sized, encodeI32Array_length h.bytes, h.length]; omega

theorem syncToFrom_ok {st : State} (hold : ViewsHold st) :
    ∀ (views : List I32ArrayView), (∀ v ∈ views, v ∈ st.i32ArrayViews) →
      Semantics.syncI32ViewsToHeapFrom views st = .ok st
  | [], _ => rfl
  | v :: rest, sub => by
    obtain ⟨vs, b, h⟩ := hold v (sub v (List.mem_cons_self ..))
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
    (h : ViewHolds st v vs b) :
    Semantics.writeResolvedPlace st { root := v.root, projections := v.projections, value := none }
      (.array vs) = .ok st := by
  simp only [Semantics.writeResolvedPlace, h.proj, Semantics.State.assignCell, h.cellEntry, Option.isSome_some,
    ite_true, replaceCell_self st.cells v.root (.array vs) h.cells]

theorem syncFromFrom_ok {st : State} (hold : ViewsHold st) :
    ∀ (views : List I32ArrayView), (∀ v ∈ views, v ∈ st.i32ArrayViews) →
      Semantics.syncI32ViewsFromHeapFrom views st = .ok st
  | [], _ => rfl
  | v :: rest, sub => by
    obtain ⟨vs, b, h⟩ := hold v (sub v (List.mem_cons_self ..))
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
    (owns : ∀ v ∈ st.i32ArrayViews, ∀ b, Owns st.heap b → b.base = v.address → Owns st'.heap b) :
    ViewsHold st' := by
  intro v mem
  rw [views] at mem
  obtain ⟨vs, b, h⟩ := hold v mem
  obtain ⟨c, cmem, cid⟩ := h.present
  exact ⟨vs, b, h.proj, fun d dmem did => h.cells d (cells v mem d dmem did) did,
    ⟨c, present v mem c cmem cid, cid⟩, h.length, h.i32s, h.base, owns v mem b h.owns h.base, h.bytes⟩

/-- A new cell, numbered past every cell, leaves the views holding. -/
theorem ViewsHold.bindCell {st : State} (hold : ViewsHold st) (below : ∀ c ∈ st.cells, c.id < st.nextCell)
    (id : Nat) (value : Option Value) : ViewsHold (st.bindCell id value) := by
  refine hold.frame rfl ?_ (fun _ _ c mem _ => by simp [State.bindCell, mem]) fun _ _ _ owns _ => owns
  intro v mem c cmem cid
  simp only [State.bindCell, List.mem_append, List.mem_singleton] at cmem
  rcases cmem with old | rfl
  · exact old
  · obtain ⟨vs, b, h⟩ := hold v mem
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

/-- A write of a cell that no view roots at leaves the views holding. -/
theorem ViewsHold.assignCell {st st' : State} (hold : ViewsHold st) {c : Nat} {value : Value}
    (ok : st.assignCell c value = some st') (apart : ∀ v ∈ st.i32ArrayViews, v.root ≠ c) : ViewsHold st' := by
  simp only [State.assignCell] at ok
  split at ok
  · simp only [Option.some.injEq] at ok
    subst ok
    refine hold.frame rfl ?_ ?_ fun _ _ _ owns _ => owns
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
  · simp at ok

/-- A block that ends below the next address. -/
def Before (heap : Heap) (b : Block) : Prop := b.base + max b.size 1 ≤ heap.nextAddress

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

/-- An allocation keeps a block that ends below the next address. -/
theorem Owns.allocate {heap heap' : Heap} {b : Block} (owns : Owns heap b) (before : Before heap b)
    {size alignment : Nat} {p : Nat} (ok : heap.allocate size alignment = .allocated p heap') :
    Owns heap' b ∧ Before heap' b := by
  simp only [Heap.allocate] at ok
  split at ok
  · simp at ok
  · rename_i valid
    have nz : alignment ≠ 0 := by
      intro zero; simp [zero, validAlignment] at valid
    split at ok
    · simp at ok
    · simp only [AllocationResult.allocated.injEq] at ok
      obtain ⟨rfl, rfl⟩ := ok
      have up : heap.nextAddress ≤ alignUp (max heap.nextAddress 1) alignment := by
        have := Nat.le_max_left heap.nextAddress 1
        have : max heap.nextAddress 1 ≤ alignUp (max heap.nextAddress 1) alignment :=
          le_alignUp _ (Nat.pos_of_ne_zero nz)
        exact Nat.le_trans (Nat.le_max_left _ _) this
      unfold Before at before
      refine ⟨⟨by simp [owns.mem], owns.sized, fun i lt => ?_, fun c mem same => ?_⟩, ?_⟩
      · simp only [Heap.containingBlock?]
        exact find?_append_some (owns.holds i lt) _
      · simp only [List.mem_append, List.mem_singleton] at mem
        rcases mem with old | rfl
        · exact owns.only c old same
        · simp only at same
          have := Nat.le_max_right b.size 1
          simp only [Lanius.Address] at *
          omega
      · exact Nat.le_trans before (Nat.le_trans up (Nat.le_add_right _ _))

end Lanius.Mini.Views
