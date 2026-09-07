import Lanius.Core.Relocation

namespace Lanius.Core.Relocation

/-- Move a module's original type-ID interval `[0, width)` to
`[base, base + width)` while remaining a permutation of all type IDs.
Unlike a plain offset, this also has an inverse for unrelated caller values. -/
def rotateTypes (base width id : Nat) : Nat :=
  if id < base + width then (id + base) % (base + width) else id

theorem rotateTypes_module (base width id : Nat) (inside : id < width) :
    rotateTypes base width id = base + id := by
  have before : id < base + width := by omega
  have shifted : id + base < base + width := by omega
  simp only [rotateTypes, if_pos before, Nat.mod_eq_of_lt shifted]
  omega

theorem rotateTypes_inverse (base width id : Nat) :
    rotateTypes width base (rotateTypes base width id) = id := by
  by_cases inside : id < base + width
  · have positive : 0 < base + width := by omega
    have shifted : (id + base) % (base + width) < width + base := by
      simpa [Nat.add_comm] using Nat.mod_lt (id + base) positive
    simp only [rotateTypes, inside, if_true, shifted]
    rw [show width + base = base + width by omega]
    rw [Nat.mod_add_mod]
    have regroup : id + base + width = id + (base + width) := by omega
    rw [regroup, Nat.add_mod_right, Nat.mod_eq_of_lt inside]
  · have outside : ¬ id < width + base := by omega
    simp [rotateTypes, inside, outside]

theorem rotateTypes_injective (base width : Nat) : Function.Injective (rotateTypes base width) :=
  (show Function.LeftInverse (rotateTypes width base) (rotateTypes base width) from
    rotateTypes_inverse base width).injective

/-- Finite permutations also support merged modules whose destination type
intervals are interleaved with unrelated declarations. -/
def swapTypes (first second id : Nat) : Nat :=
  if id = first then second else if id = second then first else id

theorem swapTypes_inverse (first second id : Nat) :
    swapTypes first second (swapTypes first second id) = id := by
  by_cases firstEqual : id = first
  · subst id
    by_cases same : first = second <;> simp [swapTypes, same]
  · by_cases secondEqual : id = second
    · subst id
      simp [swapTypes, firstEqual]
    · simp [swapTypes, firstEqual, secondEqual]

def permuteTypes : List (Nat × Nat) → Nat → Nat
  | [], id => id
  | (first, second) :: rest, id => permuteTypes rest (swapTypes first second id)

theorem permuteTypes_append (first second : List (Nat × Nat)) (id : Nat) :
    permuteTypes (first ++ second) id = permuteTypes second (permuteTypes first id) := by
  induction first generalizing id with
  | nil => rfl
  | cons pair rest induction =>
      obtain ⟨a, b⟩ := pair
      simp only [List.cons_append, permuteTypes, induction]

theorem permuteTypes_inverse (swaps : List (Nat × Nat)) (id : Nat) :
    permuteTypes swaps.reverse (permuteTypes swaps id) = id := by
  induction swaps generalizing id with
  | nil => rfl
  | cons pair rest induction =>
      obtain ⟨a, b⟩ := pair
      simp only [List.reverse_cons, permuteTypes_append, permuteTypes,
        induction, swapTypes_inverse]

theorem permuteTypes_injective (swaps : List (Nat × Nat)) : Function.Injective (permuteTypes swaps) :=
  (show Function.LeftInverse (permuteTypes swaps.reverse) (permuteTypes swaps) from
    permuteTypes_inverse swaps).injective

end Lanius.Core.Relocation
