import Lanius.Memory.Borrow

namespace Lanius.Memory

/-- Printer effects are exact byte writes, fresh borrowed string storage, or
    their composition. This permits no deallocation or arbitrary heap change. -/
inductive OutputEffect : Heap → Heap → Nat → List UInt8 → Prop where
  | write (written : BytesWrite before after address bytes) : OutputEffect before after address bytes
  | borrow (storage : List UInt8) (bounded : HeapBlocksBelowNext before)
      (written : BytesWrite (before.borrowedI32 storage) after address bytes) :
      OutputEffect before after address bytes
  | append (first : OutputEffect before middle address front)
      (second : OutputEffect middle after (address + front.length) suffix) :
      OutputEffect before after address (front ++ suffix)

variable {before middle after heap : Heap} {front suffix bytes : List UInt8}

private def outputByte (address : Nat) (bytes : List UInt8) (query : Nat) (old : UInt8) : UInt8 :=
  if address ≤ query then bytes[query - address]?.getD old else old

private theorem outputByte_append : outputByte address (front ++ suffix) query old =
    outputByte (address + front.length) suffix query (outputByte address front query old) := by
  unfold outputByte
  by_cases start : address ≤ query
  · rw [if_pos start]
    by_cases inside : query - address < front.length
    · have notNext : ¬ address + front.length ≤ query := by omega
      simp only [start, notNext, ↓reduceIte, List.getElem?_append_left inside]
    · have next : address + front.length ≤ query := by omega
      simp only [start, next, ↓reduceIte, List.getElem?_append_right (by omega : front.length ≤ query - address),
        List.getElem?_eq_none (by omega : front.length ≤ query - address), Option.getD_none, Nat.sub_add_eq]
  · have notNext : ¬ address + front.length ≤ query := by omega
    simp only [start, notNext, ↓reduceIte]

private theorem BytesWrite.oldRead (written : BytesWrite before after address bytes)
    (read : before.loadByte pointer offset = .ok old) :
    after.loadByte pointer offset = .ok (outputByte address bytes (pointer + offset) old) := by
  rw [written.reads]
  unfold outputByte
  split
  · cases bytes[pointer + offset - address]? <;> simp_all
  · exact read

/-- All previously readable locations remain readable. Inside the output
    segment they contain its exact bytes; elsewhere they retain their value. -/
theorem OutputEffect.oldRead (effect : OutputEffect before after address bytes)
    (read : before.loadByte pointer offset = .ok old) :
    after.loadByte pointer offset = .ok (outputByte address bytes (pointer + offset) old) := by
  induction effect generalizing old with
  | write written => exact written.oldRead read
  | borrow storage below written => exact written.oldRead (Heap.borrowedI32_oldRead read)
  | append first second left right => simpa only [outputByte_append] using right (left read)

theorem OutputEffect.readable (effect : OutputEffect before after address bytes)
    (readable : before.Readable pointer count) : after.Readable pointer count := by
  intro index inside
  obtain ⟨old, read⟩ := readable index inside
  exact ⟨_, effect.oldRead read⟩

theorem OutputEffect.loadBytes (effect : OutputEffect before after address bytes)
    (readable : before.Readable address bytes.length) : after.loadBytes address bytes.length = .ok bytes := by
  apply loadBytesFrom_of_reads
  intro index byte found
  obtain ⟨old, read⟩ := readable index (List.getElem?_eq_some_iff.mp found).1
  simpa only [Nat.zero_add, outputByte, Nat.le_add_right, ↓reduceIte, Nat.add_sub_cancel_left,
    found, Option.getD_some] using effect.oldRead read

theorem OutputEffect.outside (effect : OutputEffect before after address bytes)
    (read : before.loadByte pointer offset = .ok old)
    (separate : pointer + offset < address ∨ address + bytes.length ≤ pointer + offset) :
    after.loadByte pointer offset = .ok old := by
  have result := effect.oldRead read
  rcases separate with left | right
  · simpa only [outputByte, if_neg (by omega : ¬ address ≤ pointer + offset)] using result
  · have past : bytes.length ≤ pointer + offset - address := by omega
    simp only [outputByte, List.getElem?_eq_none past, Option.getD_none, ite_self] at result
    exact result

theorem OutputEffect.unique (effect : OutputEffect before after address bytes) : HeapBlockBasesUnique after := by
  induction effect with
  | write written | borrow _ _ written => exact written.unique
  | append _ _ _ right => exact right

theorem Heap.borrowedI32_below (below : HeapBlocksBelowNext heap) : HeapBlocksBelowNext (heap.borrowedI32 bytes) := by
  intro block member
  rcases List.mem_append.mp member with old | fresh
  · exact Nat.le_trans (below block old) (Nat.le_trans heap.borrowedAddress_ge (Nat.le_add_right _ _))
  · simp only [List.mem_singleton] at fresh
    subst block
    exact Nat.le_refl _

theorem OutputEffect.belowNext (effect : OutputEffect before after address bytes)
    (below : HeapBlocksBelowNext before) : HeapBlocksBelowNext after := by
  induction effect with
  | write written => exact written.below below
  | borrow _ initial written => exact written.below (Heap.borrowedI32_below initial)
  | append _ _ left right => exact right (left below)

theorem OutputEffect.budget (effect : OutputEffect before after address bytes) : after.remaining = before.remaining := by
  induction effect with
  | write written | borrow _ _ written => exact written.budget
  | append _ _ left right => exact right.trans left

end Lanius.Memory
