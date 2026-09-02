import Lean

namespace Lanius.Data

/-! A neutral, cache-friendly finite sequence representation.

The list returned by `flatten` is the semantic model.  Cached sizes and heights
are untrusted data: clients may use them only together with `WellFormed` (or by
checking `wellFormed`).  Range operations descend through the tree once instead
of restarting a root lookup for every element.
-/

inductive SeqTree (α : Type u) where
  | leaf (values : List α)
  | branch (cachedSize cachedHeight : Nat) (left right : SeqTree α)
deriving Repr, Lean.ToExpr

instance : Inhabited (SeqTree α) := ⟨.leaf []⟩

namespace SeqTree

def size : SeqTree α → Nat
  | .leaf values => values.length
  | .branch cachedSize _ _ _ => cachedSize

def height : SeqTree α → Nat
  | .leaf _ => 1
  | .branch _ cachedHeight _ _ => cachedHeight

def flatten : SeqTree α → List α
  | .leaf values => values
  | .branch _ _ left right => left.flatten ++ right.flatten

/-- The representation relation exposed to clients. -/
def Represents (tree : SeqTree α) (values : List α) : Prop :=
  tree.flatten = values

/-- Structural invariants needed for logarithmic lookup and bounded leaf work.
Branches cache their total size and height, have nonempty children, and differ
in height by at most one. -/
def WellFormed (leafCapacity : Nat) : SeqTree α → Prop
  | .leaf values => values.length ≤ leafCapacity
  | .branch cachedSize cachedHeight left right =>
      cachedSize = left.size + right.size ∧
      cachedHeight = Nat.max left.height right.height + 1 ∧
      left.WellFormed leafCapacity ∧ right.WellFormed leafCapacity ∧
      0 < left.size ∧ 0 < right.size ∧
      left.height ≤ right.height + 1 ∧ right.height ≤ left.height + 1

def wellFormed (leafCapacity : Nat) : SeqTree α → Bool
  | .leaf values => decide (values.length ≤ leafCapacity)
  | .branch cachedSize cachedHeight left right =>
      cachedSize == left.size + right.size &&
      cachedHeight == Nat.max left.height right.height + 1 &&
      left.wellFormed leafCapacity && right.wellFormed leafCapacity &&
      decide (0 < left.size) && decide (0 < right.size) &&
      decide (left.height ≤ right.height + 1) &&
      decide (right.height ≤ left.height + 1)

theorem wellFormed_sound {tree : SeqTree α} {leafCapacity : Nat}
    (accepted : tree.wellFormed leafCapacity = true) :
    tree.WellFormed leafCapacity := by
  induction tree with
  | leaf values =>
      simpa [wellFormed, WellFormed] using of_decide_eq_true accepted
  | branch cachedSize cachedHeight left right leftIH rightIH =>
      simp only [wellFormed, Bool.and_eq_true] at accepted
      rcases accepted with
        ⟨⟨⟨⟨⟨⟨⟨sizeOk, heightOk⟩, leftOk⟩, rightOk⟩,
          leftNonempty⟩, rightNonempty⟩, leftBalanced⟩, rightBalanced⟩
      exact ⟨eq_of_beq sizeOk, eq_of_beq heightOk, leftIH leftOk,
        rightIH rightOk, of_decide_eq_true leftNonempty,
        of_decide_eq_true rightNonempty, of_decide_eq_true leftBalanced,
        of_decide_eq_true rightBalanced⟩

theorem size_eq_length (tree : SeqTree α) {leafCapacity : Nat}
    (wellFormed : tree.WellFormed leafCapacity) :
    tree.size = tree.flatten.length := by
  induction tree with
  | leaf values => rfl
  | branch cachedSize cachedHeight left right leftIH rightIH =>
      rcases wellFormed with
        ⟨sizeOk, _, leftOk, rightOk, _, _, _, _⟩
      change cachedSize = (left.flatten ++ right.flatten).length
      rw [sizeOk, leftIH leftOk, rightIH rightOk]
      simp

def lookup : SeqTree α → Nat → Option α
  | .leaf values, index => values[index]?
  | .branch _ _ left right, index =>
      if index < left.size then left.lookup index
      else right.lookup (index - left.size)

theorem lookup_eq_flatten (tree : SeqTree α) {leafCapacity : Nat}
    (wellFormed : tree.WellFormed leafCapacity) (index : Nat) :
    tree.lookup index = tree.flatten[index]? := by
  induction tree generalizing index with
  | leaf values => rfl
  | branch cachedSize cachedHeight left right leftIH rightIH =>
      rcases wellFormed with
        ⟨_, _, leftOk, rightOk, _, _, _, _⟩
      unfold lookup flatten
      rw [left.size_eq_length leftOk]
      by_cases inLeft : index < left.flatten.length
      · rw [if_pos inLeft, leftIH leftOk]
        exact (List.getElem?_append_left inLeft).symm
      · rw [if_neg inLeft, rightIH rightOk]
        exact (List.getElem?_append_right (by omega)).symm

/-- Structurally extracts a range.  At a branch it visits only the selected
suffix of the left child and selected prefix of the right child. -/
def rangeToList : SeqTree α → Nat → Nat → List α
  | _, _, 0 => []
  | .leaf values, start, count => (values.drop start).take count
  | .branch _ _ left right, start, count + 1 =>
      if start < left.size then
        left.rangeToList start (count + 1) ++
          right.rangeToList 0 (count + 1 - (left.size - start))
      else
        right.rangeToList (start - left.size) (count + 1)

private theorem dropTakeAppend (left right : List α) (start count : Nat) :
    ((left ++ right).drop start).take count =
      if start < left.length then
        (left.drop start).take count ++
          right.take (count - (left.length - start))
      else
        (right.drop (start - left.length)).take count := by
  rw [List.drop_append, List.take_append]
  by_cases inLeft : start < left.length
  · simp only [inLeft, if_pos]
    have startSub : start - left.length = 0 := by omega
    have remaining : (left.drop start).length = left.length - start :=
      List.length_drop
    rw [startSub, List.drop_zero, remaining]
  · simp only [inLeft]
    have dropped : left.drop start = [] := by
      apply List.eq_nil_of_length_eq_zero
      simp [List.length_drop]
      omega
    rw [dropped]
    simp

theorem rangeToList_eq_flatten (tree : SeqTree α) {leafCapacity : Nat}
    (wellFormed : tree.WellFormed leafCapacity) (start count : Nat) :
    tree.rangeToList start count = (tree.flatten.drop start).take count := by
  induction tree generalizing start count with
  | leaf values => cases count <;> rfl
  | branch cachedSize cachedHeight left right leftIH rightIH =>
      rcases wellFormed with
        ⟨_, _, leftOk, rightOk, _, _, _, _⟩
      cases count with
      | zero => rfl
      | succ count =>
      unfold rangeToList flatten
      rw [dropTakeAppend]
      rw [left.size_eq_length leftOk]
      by_cases inLeft : start < left.flatten.length
      · simp only [inLeft, if_pos]
        rw [leftIH leftOk, rightIH rightOk]
        simp
      · simp only [inLeft]
        exact rightIH rightOk _ _

/-- A fold over a structural range. -/
def foldRange (tree : SeqTree α) (start count : Nat)
    (initial : β) (step : β → α → β) : β :=
  (tree.rangeToList start count).foldl step initial

theorem foldRange_eq_flatten (tree : SeqTree α) {leafCapacity : Nat}
    (wellFormed : tree.WellFormed leafCapacity) (start count : Nat)
    (initial : β) (step : β → α → β) :
    tree.foldRange start count initial step =
      ((tree.flatten.drop start).take count).foldl step initial := by
  simp [foldRange, rangeToList_eq_flatten tree wellFormed]

/-- Consume as much of `expected` as `available` can match.  A mismatch returns
`none`; a successful comparison returns the unconsumed suffix of `expected`.
This lets adjacent tree leaves share one comparison state without constructing
an intermediate source slice. -/
def consumeAvailable [BEq α] : List α → List α → Option (List α)
  | _, [] => some []
  | [], expected => some expected
  | value :: values, wanted :: expected =>
      if value == wanted then consumeAvailable values expected else none

theorem consumeAvailable_append [BEq α] (left right expected : List α) :
    consumeAvailable (left ++ right) expected =
      match consumeAvailable left expected with
      | none => none
      | some remaining => consumeAvailable right remaining := by
  induction left generalizing expected with
  | nil => cases expected <;> rfl
  | cons value values inductionHypothesis =>
      cases expected with
      | nil => simp [consumeAvailable]
      | cons wanted expected =>
          simp only [List.cons_append, consumeAvailable]
          split
          · exact inductionHypothesis expected
          · rfl

theorem consumeAvailable_nil_sound [BEq α] [LawfulBEq α]
    {available expected : List α}
    (accepted : consumeAvailable available expected = some []) :
    available.take expected.length = expected := by
  induction available generalizing expected with
  | nil =>
      cases expected with
      | nil => rfl
      | cons wanted expected => simp [consumeAvailable] at accepted
  | cons value available inductionHypothesis =>
      cases expected with
      | nil => rfl
      | cons wanted expected =>
          simp only [consumeAvailable] at accepted
          by_cases equal : value == wanted
          · simp only [equal, ↓reduceIte] at accepted
            have valueEqual : value = wanted := eq_of_beq equal
            subst wanted
            simpa using inductionHypothesis accepted
          · simp [equal] at accepted

theorem consumeAvailable_nil_complete [BEq α] [LawfulBEq α]
    {available expected : List α}
    (equal : available.take expected.length = expected) :
    consumeAvailable available expected = some [] := by
  induction available generalizing expected with
  | nil =>
      cases expected <;> simp_all [consumeAvailable]
  | cons value available inductionHypothesis =>
      cases expected with
      | nil => rfl
      | cons wanted expected =>
          simp only [List.length_cons, List.take_succ_cons,
            List.cons.injEq] at equal
          rcases equal with ⟨valueEqual, suffixEqual⟩
          subst wanted
          simp [consumeAvailable, inductionHypothesis suffixEqual]

/-- Compare a range without constructing the selected source list.  The walk
descends once to `start`, carries the unmatched suffix across adjacent leaves,
and stops as soon as all expected values have been consumed. -/
def consumeRange [BEq α] : SeqTree α → Nat → List α → Option (List α)
  | _, _, [] => some []
  | .leaf values, start, expected =>
      consumeAvailable (values.drop start) expected
  | .branch _ _ left right, start, expected =>
      if start < left.size then
        match left.consumeRange start expected with
        | none => none
        | some remaining => right.consumeRange 0 remaining
      else
        right.consumeRange (start - left.size) expected

theorem consumeRange_eq_flatten [BEq α] (tree : SeqTree α)
    {leafCapacity : Nat} (wellFormed : tree.WellFormed leafCapacity)
    (start : Nat) (expected : List α) :
    tree.consumeRange start expected =
      consumeAvailable (tree.flatten.drop start) expected := by
  induction tree generalizing start expected with
  | leaf values =>
      cases expected <;> simp [consumeRange, consumeAvailable, flatten]
  | branch cachedSize cachedHeight left right leftIH rightIH =>
      rcases wellFormed with
        ⟨_, _, leftOk, rightOk, _, _, _, _⟩
      cases expected with
      | nil => simp [consumeRange, consumeAvailable]
      | cons wanted expected =>
          unfold consumeRange flatten
          rw [List.drop_append]
          rw [left.size_eq_length leftOk]
          by_cases inLeft : start < left.flatten.length
          · simp only [inLeft, ↓reduceIte]
            have startSub : start - left.flatten.length = 0 := by omega
            rw [startSub, List.drop_zero, consumeAvailable_append]
            rw [leftIH leftOk]
            split
            · rfl
            · rename_i remaining found
              simpa using rightIH rightOk 0 remaining
          · simp only [inLeft, ↓reduceIte]
            have dropped : left.flatten.drop start = [] := by
              apply List.eq_nil_of_length_eq_zero
              simp [List.length_drop]
              omega
            rw [dropped, List.nil_append]
            exact rightIH rightOk _ _

def rangeEq [BEq α] (tree : SeqTree α) (start : Nat)
    (expected : List α) : Bool :=
  tree.consumeRange start expected == some []

theorem rangeEq_sound [BEq α] [LawfulBEq α]
    {tree : SeqTree α} {leafCapacity start : Nat} {expected : List α}
    (wellFormed : tree.WellFormed leafCapacity)
    (accepted : tree.rangeEq start expected = true) :
    (tree.flatten.drop start).take expected.length = expected := by
  have consumed : tree.consumeRange start expected = some [] :=
    eq_of_beq accepted
  rw [tree.consumeRange_eq_flatten wellFormed] at consumed
  exact consumeAvailable_nil_sound consumed

theorem rangeEq_complete [BEq α] [LawfulBEq α]
    {tree : SeqTree α} {leafCapacity start : Nat} {expected : List α}
    (wellFormed : tree.WellFormed leafCapacity)
    (equal : (tree.flatten.drop start).take expected.length = expected) :
    tree.rangeEq start expected = true := by
  unfold rangeEq
  rw [tree.consumeRange_eq_flatten wellFormed]
  exact beq_iff_eq.mpr (consumeAvailable_nil_complete equal)

theorem rangeEq_iff [BEq α] [LawfulBEq α]
    {tree : SeqTree α} {leafCapacity start : Nat} {expected : List α}
    (wellFormed : tree.WellFormed leafCapacity) :
    tree.rangeEq start expected = true ↔
      (tree.flatten.drop start).take expected.length = expected :=
  ⟨rangeEq_sound wellFormed, rangeEq_complete wellFormed⟩

end SeqTree

end Lanius.Data
