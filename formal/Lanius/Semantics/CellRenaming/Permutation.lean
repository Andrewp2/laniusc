import Lanius.Basic

namespace Lanius.Semantics.CellRenaming

/-- Rename existing cells only. Every identity at or above the allocation
boundary stays fixed, including all cells allocated later. -/
structure Permutation (boundary : Nat) where
  forward : CellId → CellId
  backward : CellId → CellId
  leftInverse : ∀ cell, backward (forward cell) = cell
  rightInverse : ∀ cell, forward (backward cell) = cell
  fresh : ∀ cell, boundary ≤ cell → forward cell = cell

theorem Permutation.injective (rename : Permutation boundary) : Function.Injective rename.forward := by
  intro left right same
  have recovered := congrArg rename.backward same
  simpa only [rename.leftInverse] using recovered

theorem Permutation.below (rename : Permutation boundary) (old : cell < boundary) :
    rename.forward cell < boundary := by
  by_cases inside : rename.forward cell < boundary
  · exact inside
  · have fixed := rename.fresh (rename.forward cell) (Nat.le_of_not_gt inside)
    have same := rename.injective fixed
    exact (inside (same.symm ▸ old)).elim

theorem Permutation.backward_fresh (rename : Permutation boundary) (fresh : boundary ≤ cell) :
    rename.backward cell = cell := by
  calc
    rename.backward cell = rename.backward (rename.forward cell) :=
      congrArg rename.backward (rename.fresh cell fresh).symm
    _ = cell := rename.leftInverse cell

def Permutation.inverse (rename : Permutation boundary) : Permutation boundary where
  forward := rename.backward
  backward := rename.forward
  leftInverse := rename.rightInverse
  rightInverse := rename.leftInverse
  fresh := fun _ fresh => rename.backward_fresh fresh

def Permutation.then (first second : Permutation boundary) : Permutation boundary where
  forward := fun cell => second.forward (first.forward cell)
  backward := fun cell => first.backward (second.backward cell)
  leftInverse := by intro cell; simp only [second.leftInverse, first.leftInverse]
  rightInverse := by intro cell; simp only [first.rightInverse, second.rightInverse]
  fresh := by intro cell fresh; rw [first.fresh cell fresh, second.fresh cell fresh]

private def exchange (left right cell : CellId) : CellId :=
  if cell = left then right else if cell = right then left else cell

private theorem exchange_twice (left right cell : CellId) :
    exchange left right (exchange left right cell) = cell := by
  by_cases atLeft : cell = left
  · subst cell; by_cases same : left = right <;> simp [exchange, same]
  · by_cases atRight : cell = right
    · subst cell; simp [exchange, atLeft]
    · simp [exchange, atLeft, atRight]

def Permutation.swap (left right : CellId) (leftBelow : left < boundary)
    (rightBelow : right < boundary) : Permutation boundary where
  forward := exchange left right
  backward := exchange left right
  leftInverse := exchange_twice left right
  rightInverse := exchange_twice left right
  fresh := by
    intro cell fresh
    simp [exchange, Nat.ne_of_gt (Nat.lt_of_lt_of_le leftBelow fresh),
      Nat.ne_of_gt (Nat.lt_of_lt_of_le rightBelow fresh)]

@[simp] theorem Permutation.swap_left (leftBelow : left < boundary) (rightBelow : right < boundary) :
    (Permutation.swap left right leftBelow rightBelow).forward left = right := by
  simp [Permutation.swap, exchange]

@[simp] theorem Permutation.swap_right (leftBelow : left < boundary) (rightBelow : right < boundary) :
    (Permutation.swap left right leftBelow rightBelow).forward right = left := by
  by_cases same : left = right <;> simp [Permutation.swap, exchange, same]

theorem Permutation.swap_other (leftBelow : left < boundary) (rightBelow : right < boundary)
    (notLeft : cell ≠ left) (notRight : cell ≠ right) :
    (Permutation.swap left right leftBelow rightBelow).forward cell = cell := by
  simp [Permutation.swap, exchange, notLeft, notRight]

/-- Place two distinct model buffers at two distinct caller addresses. The
second exchange accounts for any overlap caused by the first exchange. -/
def Permutation.placePair (left right targetLeft targetRight : CellId)
    (leftBelow : left < boundary) (rightBelow : right < boundary)
    (targetLeftBelow : targetLeft < boundary) (targetRightBelow : targetRight < boundary) :
    Permutation boundary :=
  let first := Permutation.swap left targetLeft leftBelow targetLeftBelow
  first.then (Permutation.swap (first.forward right) targetRight
    (first.below rightBelow) targetRightBelow)

theorem Permutation.placePair_left
    (leftBelow : left < boundary) (rightBelow : right < boundary)
    (targetLeftBelow : targetLeft < boundary) (targetRightBelow : targetRight < boundary)
    (distinct : left ≠ right) (targetsDistinct : targetLeft ≠ targetRight) :
    (Permutation.placePair left right targetLeft targetRight leftBelow rightBelow
      targetLeftBelow targetRightBelow).forward left = targetLeft := by
  let first := Permutation.swap left targetLeft leftBelow targetLeftBelow
  have placed : first.forward left = targetLeft := Permutation.swap_left leftBelow targetLeftBelow
  have different : targetLeft ≠ first.forward right := by
    intro same
    exact distinct (first.injective (placed.trans same))
  change (Permutation.swap (first.forward right) targetRight
    (first.below rightBelow) targetRightBelow).forward (first.forward left) = targetLeft
  rw [placed]
  exact Permutation.swap_other _ _ different targetsDistinct

theorem Permutation.placePair_right
    (leftBelow : left < boundary) (rightBelow : right < boundary)
    (targetLeftBelow : targetLeft < boundary) (targetRightBelow : targetRight < boundary) :
    (Permutation.placePair left right targetLeft targetRight leftBelow rightBelow
      targetLeftBelow targetRightBelow).forward right = targetRight := by
  exact Permutation.swap_left
    ((Permutation.swap left targetLeft leftBelow targetLeftBelow).below rightBelow) targetRightBelow

end Lanius.Semantics.CellRenaming
