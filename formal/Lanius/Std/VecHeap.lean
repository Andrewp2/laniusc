import Lanius.Std.VecAlloc

/-! # The heap across growth

`try_reserve` allocates a fresh block, copies into it and frees the old
storage. `Kept h h' p n` says what survives from `h` to `h'` for everything
apart from the old storage `[p, p + n)`: every successful read and every
buffer. -/

namespace Lanius.Std

open Lanius Lanius.Core Lanius.Semantics Lanius.Memory

/-- Blocks ordered by base do not overlap (the verified compiler's
`HeapCorr.apart`). With unique bases it gives `HeapBlocksDisjoint`, which
`as_slice` and `at` need. -/
def HeapApart (h : Heap) : Prop :=
  ∀ b ∈ h.blocks, ∀ b' ∈ h.blocks, b.base < b'.base → b.base + b.size ≤ b'.base

theorem HeapApart.disjoint {h : Heap} (apart : HeapApart h) (unique : HeapBlockBasesUnique h) :
    HeapBlocksDisjoint h := by
  intro l lm r rm ne
  unfold BlockIntervalsDisjoint
  rcases Nat.lt_trichotomy l.base r.base with lt | eq | gt
  · exact Or.inl (apart l lm r rm lt)
  · exact absurd (unique l lm r rm eq) ne
  · exact Or.inr (apart r rm l lm gt)

/-- Every block of `h'` has the interval of a block of `h`. -/
theorem HeapApart.ofTwins {h h' : Heap} (apart : HeapApart h)
    (twins : ∀ b ∈ h'.blocks, ∃ c ∈ h.blocks, c.base = b.base ∧ c.size = b.size) : HeapApart h' := by
  intro b bm b' bm' lt
  obtain ⟨c, cm, cb, cs⟩ := twins b bm
  obtain ⟨c', cm', cb', _⟩ := twins b' bm'
  have := apart c cm c' cm' (by rw [cb, cb']; exact lt)
  rw [cb, cs, cb'] at this
  exact this

theorem HeapApart.ofWrite {h h' : Heap} {lo n : Nat} (effect : HeapRegionWrite h h' lo n) (apart : HeapApart h) :
    HeapApart h' := by
  refine apart.ofTwins fun b member => ?_
  have masked : { b with bytes := [] } ∈ h'.blocks.map (fun item => { item with bytes := [] }) :=
    List.mem_map.mpr ⟨b, member, rfl⟩
  rw [effect.layout] at masked
  obtain ⟨old, oldMember, same⟩ := List.mem_map.mp masked
  have eb := congrArg (fun x : Block => x.base) same
  have es := congrArg (fun x : Block => x.size) same
  exact ⟨old, oldMember, eb, es⟩

theorem HeapApart.afterAlloc {h : Heap} (apart : HeapApart h) (below : HeapBlocksBelowNext h) (size a : Nat)
    (budget : Option Nat) (positive : 0 < a) : HeapApart (h.allocatedBytes size a budget) := by
  have ge := Heap.allocationAddress_ge h positive
  intro b bm b' bm' lt
  simp only [Heap.allocatedBytes, List.mem_append, List.mem_singleton] at bm bm'
  rcases bm with bm | rfl <;> rcases bm' with bm' | rfl
  · exact apart b bm b' bm' lt
  · have hb := below b bm
    show b.base + b.size ≤ h.allocationAddress a
    have hs : b.size ≤ max b.size 1 := Nat.le_max_left _ _
    dsimp only [Lanius.Address] at *
    omega
  · have hb := below b' bm'
    have hs : 1 ≤ max b'.size 1 := Nat.le_max_right _ _
    have hbase : (h.allocationBlock size a).base = h.allocationAddress a := rfl
    rw [hbase] at lt
    dsimp only [Lanius.Address] at *
    omega
  · exact absurd lt (Nat.lt_irrefl _)

/-- Reads and buffers apart from `[p, p + n)` survive from `h` to `h'`. -/
structure Kept (h h' : Heap) (p n : Nat) : Prop where
  reads : ∀ lo m, (lo + m ≤ p ∨ p + n ≤ lo) → ReadsWithin h h' lo m
  buffers : ∀ q m, 0 < m → (q + m ≤ p ∨ p + n ≤ q) → Buffer h q m → Buffer h' q m

theorem Kept.afterAlloc (h : Heap) (p n size a : Nat) (budget : Option Nat) :
    Kept h (h.allocatedBytes size a budget) p n :=
  ⟨fun lo m _ => ReadsWithin.afterAlloc h size a budget lo m, fun _ _ _ _ buffer => buffer.afterAlloc⟩

theorem loadBytes_zero (h : Heap) (pointer : Nat) : h.loadBytes pointer 0 = .ok [] := rfl

/-- A successful read lies below the allocation frontier. -/
theorem loadBytes_below {h : Heap} (below : HeapBlocksBelowNext h) {pointer count : Nat}
    {bytes : List UInt8} (loaded : h.loadBytes pointer count = .ok bytes) (positive : 0 < count) :
    pointer + count ≤ h.nextAddress :=
  (Heap.Readable.of_loadBytes loaded).belowNext positive below

/-- Writing into storage at or above `h`'s frontier keeps `Kept h`. -/
theorem Kept.afterFreshWrite {h h1 h2 : Heap} {p n q k : Nat} (below : HeapBlocksBelowNext h)
    (fresh : h.nextAddress ≤ q) (kept : Kept h h1 p n) (write : HeapRegionWrite h1 h2 q k) :
    Kept h h2 p n := by
  refine ⟨fun lo m apart pointer count bytes lower upper loaded => ?_,
    fun q' m positive apart buffer => (kept.buffers q' m positive apart buffer).afterWrite write⟩
  have first := kept.reads lo m apart pointer count bytes lower upper loaded
  cases count with
  | zero => cases (show bytes = [] by simpa [loadBytes_zero] using loaded.symm); exact loadBytes_zero _ _
  | succ c =>
      have := loadBytes_below below loaded (Nat.succ_pos c)
      exact write.loadBytes first (Or.inl (by dsimp only [Lanius.Address] at *; omega))

/-! ## `dealloc` -/

theorem replaceBlock_eq_map (l : List Block) (r : Block) :
    replaceBlock l r = l.map (fun blk => if blk.base == r.base then r else blk) := by
  induction l with
  | nil => rfl
  | cons x rest ih => simp only [replaceBlock, List.map_cons, ih]

theorem find?_map_same {l : List Block} {f : Block → Block} {pred : Block → Bool}
    (same : ∀ x ∈ l, pred (f x) = pred x) (fixed : ∀ x ∈ l, pred x = true → f x = x) :
    (l.map f).find? pred = l.find? pred := by
  induction l with
  | nil => rfl
  | cons x rest ih =>
      simp only [List.map_cons, List.find?_cons]
      rw [same x (by simp)]
      have rest' := ih (fun y m => same y (by simp [m])) (fun y m => fixed y (by simp [m]))
      cases hx : pred x with
      | false => exact rest'
      | true => rw [fixed x (by simp) hx]

/-- What freeing the storage `[p, p + n)` of a buffer keeps. -/
structure Freed (h h' : Heap) (p n : Nat) : Prop where
  containing : ∀ a, (a < p ∨ p + n ≤ a) → h'.containingBlock? a = h.containingBlock? a
  next : h'.nextAddress = h.nextAddress
  below : HeapBlocksBelowNext h → HeapBlocksBelowNext h'
  unique : HeapBlockBasesUnique h → HeapBlockBasesUnique h'
  apart : HeapApart h → HeapApart h'

theorem Freed.refl (h : Heap) (p n : Nat) : Freed h h p n :=
  ⟨fun _ _ => rfl, rfl, id, id, id⟩

/-- `dealloc(p, n, 8)` of a buffer succeeds. -/
theorem dealloc_buffer {h : Heap} {p n : Nat} (buffer : Buffer h p n) (unique : HeapBlockBasesUnique h) :
    ∃ h', h.deallocate p n 8 = .ok h' ∧ Freed h h' p n := by
  by_cases zero : p = null
  · refine ⟨h, ?_, Freed.refl h p n⟩
    simp [Heap.deallocate, zero]
  obtain ⟨found, _, _, _⟩ := buffer
  cases hb : h.containingBlock? p with
  | none => simp [hb] at found
  | some b =>
    simp only [hb, Option.map_some, Option.some.injEq, Block.shape] at found
    have base : b.base = p := congrArg Block.base found
    have bsize : b.size = n := congrArg Block.size found
    have balign : b.alignment = 8 := congrArg Block.alignment found
    have blive : b.live = true := congrArg Block.live found
    have bowned : b.owned = true := congrArg Block.owned found
    have member : b ∈ h.blocks := List.mem_of_find?_eq_some hb
    have only : ∀ x ∈ h.blocks, x.base = p → x = b := fun x m same =>
      unique x m b member (same.trans base.symm)
    cases hx : h.blocks.find? (fun blk => blk.base == p) with
    | none =>
        have := List.find?_eq_none.mp hx b member
        simp [base] at this
    | some x =>
      have xm := List.mem_of_find?_eq_some hx
      have xb : x = b := only x xm (by simpa using List.find?_some hx)
      subst xb
      let r : Block := { x with live := false }
      refine ⟨{ h with blocks := replaceBlock h.blocks r, remaining := refundBudget h.remaining x.size },
        ?_, ?_⟩
      · simp [Heap.deallocate, Heap.block?, zero, hx, blive, bowned, bsize, balign, r]
      · have f_base : ∀ blk : Block, (if blk.base == r.base then r else blk).base = blk.base := by
          intro blk; split
          · rename_i e; simpa [r] using (beq_iff_eq.mp e).symm
          · rfl
        have f_size : ∀ blk ∈ h.blocks, (if blk.base == r.base then r else blk).size = blk.size := by
          intro blk m; split
          · rename_i e; rw [only blk m (by simpa [r, base] using beq_iff_eq.mp e)]
          · rfl
        refine ⟨fun a outside => ?_, rfl, fun below blk m => ?_, fun _ => ?_, fun apart => ?_⟩
        · simp only [Heap.containingBlock?, replaceBlock_eq_map]
          apply find?_map_same
          · intro y m
            split
            · rename_i e
              have yb := only y m (by simpa [r, base] using beq_iff_eq.mp e)
              subst yb
              simp [r]
              dsimp only [Lanius.Address] at *
              omega
            · rfl
          · intro y m _
            split
            · rename_i e
              have yb := only y m (by simpa [r, base] using beq_iff_eq.mp e)
              subst yb
              simp_all
              dsimp only [Lanius.Address] at *
              omega
            · rfl
        · simp only [replaceBlock_eq_map, List.mem_map] at m
          obtain ⟨old, om, rfl⟩ := m
          rw [f_base, f_size old om]
          exact below old om
        · intro left lm right rm same
          simp only [replaceBlock_eq_map, List.mem_map] at lm rm
          obtain ⟨l0, l0m, rfl⟩ := lm
          obtain ⟨r0, r0m, rfl⟩ := rm
          rw [f_base, f_base] at same
          rw [unique l0 l0m r0 r0m same]
        · refine apart.ofTwins fun b m => ?_
          simp only [replaceBlock_eq_map, List.mem_map] at m
          obtain ⟨old, om, rfl⟩ := m
          exact ⟨old, om, (f_base old).symm, (f_size old om).symm⟩

theorem Freed.reads {h h' : Heap} {p n : Nat} (freed : Freed h h' p n) {lo m : Nat}
    (apart : lo + m ≤ p ∨ p + n ≤ lo) : ReadsWithin h h' lo m := by
  intro pointer count bytes lower upper loaded
  apply Heap.loadBytes_congr loaded
  intro index inside
  have length := (loadBytesFrom_spec loaded).1
  have read := Heap.loadBytes_get loaded (List.getElem?_eq_getElem (by omega : index < bytes.length))
  rw [read]
  obtain ⟨block, contains, byte⟩ := Heap.loadByte_ok_iff.mp read
  exact Heap.loadByte_ok_iff.mpr ⟨block, by rw [freed.containing _ (by omega)]; exact contains, byte⟩

theorem Freed.buffer {h h' : Heap} {p n q m : Nat} (freed : Freed h h' p n) (positive : 0 < m)
    (apart : q + m ≤ p ∨ p + n ≤ q) (buffer : Buffer h q m) : Buffer h' q m := by
  obtain ⟨found, readable, aligned, bound⟩ := buffer
  refine ⟨by rw [freed.containing q (by omega)]; exact found, fun i inside => ?_, aligned, bound⟩
  obtain ⟨byte, read⟩ := readable i inside
  obtain ⟨block, contains, value⟩ := Heap.loadByte_ok_iff.mp read
  exact ⟨byte, Heap.loadByte_ok_iff.mpr ⟨block, by rw [freed.containing _ (by omega)]; exact contains, value⟩⟩

theorem Kept.afterFree {h h1 h2 : Heap} {p n : Nat} (kept : Kept h h1 p n) (freed : Freed h1 h2 p n) :
    Kept h h2 p n :=
  ⟨fun lo m apart => ReadsWithin.trans (kept.reads lo m apart) (freed.reads apart),
    fun q m positive apart buffer => freed.buffer positive apart (kept.buffers q m positive apart buffer)⟩

#print axioms dealloc_buffer

end Lanius.Std
