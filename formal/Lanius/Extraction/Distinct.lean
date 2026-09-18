import Init.Data.List.Sort.Lemmas
import Lean.Elab.Tactic.Omega

namespace Lanius.Extraction.Distinct

/-- Structural fuel keeps sorting reducible in the kernel. Exhausting it
still preserves the input multiset; acceptance separately checks strict order. -/
private def mergeKeys : Nat → List Nat → List Nat → List Nat
  | 0, left, right => left ++ right
  | _ + 1, [], right => right
  | _ + 1, left, [] => left
  | fuel + 1, first :: left, second :: right =>
    if first ≤ second then first :: mergeKeys fuel left (second :: right)
    else second :: mergeKeys fuel (first :: left) right

private theorem mergeKeys_perm (fuel : Nat) (left right : List Nat) :
    (mergeKeys fuel left right).Perm (left ++ right) := by
  induction fuel generalizing left right with
  | zero => exact .refl _
  | succ fuel induction =>
    cases left with
    | nil => simp [mergeKeys]
    | cons first left =>
      cases right with
      | nil => simp [mergeKeys]
      | cons second right =>
        simp only [mergeKeys]
        split
        · exact .cons first (induction _ _)
        · exact (List.Perm.cons second (induction _ _)).trans List.perm_middle.symm

private def sortKeys : Nat → List Nat → List Nat
  | 0, values => values
  | _ + 1, [] => []
  | _ + 1, [value] => [value]
  | fuel + 1, values =>
    let half := values.length / 2
    mergeKeys values.length (sortKeys fuel (values.take half))
      (sortKeys fuel (values.drop half))

private theorem sortKeys_perm (fuel : Nat) (values : List Nat) :
    (sortKeys fuel values).Perm values := by
  induction fuel generalizing values with
  | zero => exact .refl _
  | succ fuel induction =>
    cases values with
    | nil => exact .refl _
    | cons first rest =>
      cases rest with
      | nil => exact .refl _
      | cons second rest =>
        let values := first :: second :: rest
        exact (mergeKeys_perm _ _ _).trans (by
          simpa only [List.take_append_drop] using
            (induction (values.take (values.length / 2))).append
              (induction (values.drop (values.length / 2))))

/-- Reuse the reducible key sorter to compare multisets, including repeated
keys. Fuel affects acceptance only; it cannot make unequal multisets equal. -/
def sameMultiset (left right : List Nat) : Bool :=
  sortKeys left.length left == sortKeys right.length right

theorem sameMultiset_sound {left right : List Nat}
    (accepted : sameMultiset left right = true) : left.Perm right := by
  have same := eq_of_beq accepted
  exact (sortKeys_perm left.length left).symm.trans
    ((List.Perm.of_eq same).trans (sortKeys_perm right.length right))

theorem sameMultiset_mergeSort {left right : List Nat}
    (accepted : sameMultiset left right = true) : left.mergeSort = right.mergeSort := by
  have sorted (values : List Nat) : values.mergeSort.Pairwise (· ≤ ·) := by
    have result := List.pairwise_mergeSort (le := fun a b : Nat => decide (a ≤ b))
      (by intros; simp_all; omega) (by intros; simp_all; omega) values
    simpa only [decide_eq_true_eq] using result
  exact List.Perm.eq_of_pairwise (fun _ _ _ _ => Nat.le_antisymm)
    (sorted left) (sorted right)
    ((List.mergeSort_perm left _).trans
      ((sameMultiset_sound accepted).trans (List.mergeSort_perm right _).symm))

private def increasingAfter (previous : Nat) : List Nat → Bool
  | [] => true
  | next :: rest => decide (previous < next) && increasingAfter next rest

private theorem increasingAfter_pairwise {previous : Nat} {values : List Nat}
    (accepted : increasingAfter previous values = true) :
    (previous :: values).Pairwise (· < ·) := by
  induction values generalizing previous with
  | nil => exact .cons (by simp) .nil
  | cons next rest induction =>
    simp only [increasingAfter, Bool.and_eq_true, decide_eq_true_eq] at accepted
    have following := induction accepted.2
    refine .cons ?_ following
    intro value member
    rcases List.mem_cons.mp member with rfl | later
    · exact accepted.1
    · exact Nat.lt_trans accepted.1 (List.rel_of_pairwise_cons following later)

private def increasing : List Nat → Bool
  | [] => true
  | first :: rest => increasingAfter first rest

private theorem increasing_nodup {values : List Nat}
    (accepted : increasing values = true) : values.Nodup := by
  cases values with
  | nil => exact .nil
  | cons first rest =>
    exact (increasingAfter_pairwise accepted).imp Nat.ne_of_lt

/-- Sorting small keys gives an O(n log n) positive uniqueness check.
Keys need not be injective: collisions use the ordinary complete decision
procedure, so valid values with a shared key are never rejected. -/
def nodupOn [DecidableEq α] (key : α → Nat) (values : List α) :
    Decidable values.Nodup :=
  if accepted : increasing (sortKeys values.length (values.map key)) = true then
    .isTrue (by
      have distinctKeys := (sortKeys_perm values.length (values.map key)).nodup
        (increasing_nodup accepted)
      have pairs := List.pairwise_map.mp distinctKeys
      exact pairs.imp (fun different same => different (congrArg key same)))
  else inferInstance

/-- The fast path changes computation, not the accepted proposition. -/
theorem decide_nodupOn [DecidableEq α] (key : α → Nat) (values : List α) :
    @decide values.Nodup (nodupOn key values) = decide values.Nodup := by
  exact congrArg (fun decision : Decidable values.Nodup => @decide _ decision)
    (Subsingleton.elim _ _)

end Lanius.Extraction.Distinct
