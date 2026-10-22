import Lanius.Std.VecBound

/-! # Searching a sorted vector

`lower_bound`, `upper_bound` and `binary_search` against `T::lt`, given as a
Boolean function `ltv` with a contract for calls on the elements and the
needle. A vector is sorted when no element is less than an earlier one;
the searches also need `ltv` negatively transitive (`a < c` implies
`a < b` or `b < c`), which every strict weak order is. -/

namespace Lanius.Std

open Lanius Lanius.Core Lanius.Semantics Lanius.Memory

variable {P : Program} {T : Ty} {ids : VecIds} {size : Nat}

/-! ## Order facts -/

/-- No element is less than an earlier one. -/
def Sorted (ltv : Value → Value → Bool) (xs : List Value) : Prop :=
  xs.Pairwise (fun a b => ltv b a = false)

/-- `a < c` implies `a < b` or `b < c`. -/
def NegTrans (ltv : Value → Value → Bool) : Prop :=
  ∀ a b c, ltv a c = true → ltv a b = true ∨ ltv b c = true

/-- `T::lt`'s contract on the values `vals`. -/
def LtSpec (P : Program) (lt : FunctionId) (ltv : Value → Value → Bool) (vals : List Value) : Prop :=
  ∀ S : State, S.CellsWellFormed → ∀ a ∈ vals, ∀ b ∈ vals, ∃ after,
    RunsExpr P S (.call lt ([a, b].map Expr.value)) (.boolean (ltv a b)) after ∧ PureFrame S after

/-- The number of elements less than `needle`, in a sorted list. -/
def lowerBoundOf (ltv : Value → Value → Bool) (needle : Value) (xs : List Value) : Nat :=
  (xs.takeWhile (fun x => ltv x needle)).length

/-- The number of elements not greater than `needle`, in a sorted list. -/
def upperBoundOf (ltv : Value → Value → Bool) (needle : Value) (xs : List Value) : Nat :=
  (xs.takeWhile (fun x => !ltv needle x)).length

theorem takeWhile_length_eq {p : Value → Bool} :
    ∀ (xs : List Value) (r : Nat), r ≤ xs.length →
      (∀ i (h : i < xs.length), i < r → p xs[i] = true) →
      (∀ i (h : i < xs.length), r ≤ i → p xs[i] = false) → (xs.takeWhile p).length = r
  | [], r, le, _, _ => by simp at le ⊢; omega
  | x :: rest, 0, _, _, after => by
      have h : p x = false := after 0 (by simp) (Nat.le_refl _)
      rw [List.takeWhile_cons_of_neg (by simp [h])]; rfl
  | x :: rest, k + 1, le, before, after => by
      have h : p x = true := before 0 (by simp) (by omega)
      rw [List.takeWhile_cons_of_pos (by simp [h]), List.length_cons]
      congr 1
      refine takeWhile_length_eq rest k (by simp at le; omega) (fun i h lt => ?_) (fun i h ge => ?_)
      · exact before (i + 1) (by simp; omega) (by omega)
      · exact after (i + 1) (by simp; omega) (by omega)

theorem Sorted.at {ltv : Value → Value → Bool} {xs : List Value} (sorted : Sorted ltv xs) {i j : Nat}
    (hi : i < xs.length) (hj : j < xs.length) (lt : i < j) : ltv xs[j] xs[i] = false :=
  List.pairwise_iff_getElem.mp sorted i j hi hj lt

/-! ## The template -/

/-- `T::lt(items[middle], needle)`, or with `swap` `T::lt(needle, items[middle])`. -/
def cmpExpr (lt : FunctionId) : Bool → Expr
  | false => .call lt [.index (.local 2) (.local 5), .local 1]
  | true => .call lt [.local 1, .index (.local 2) (.local 5)]

/-- `lower_bound` (`swap = false`) and `upper_bound` (`swap = true`), with
`value`, `needle`, `items`, `low`, `high` and `middle` the locals 0 to 5. -/
def boundFn (ids : VecIds) (T : Ty) (f lt : FunctionId) (swap : Bool) : Function where
  id := f
  parameters := [(0, vecTy ids), (1, T)]
  returnType := i32Ty
  body := some <|
    .letLocal 2 (.slice T) (.call ids.slots [.local 0])
    (.letLocal 3 i32Ty (int 0)
    (.letLocal 4 i32Ty (.field (.local 0) 1)
    (.sequence (searchLoop (cmpExpr lt swap) swap) (.returnValue (some (.local 3))))))

/-- Whether the answer lies right of index `i`. -/
def rightOf (ltv : Value → Value → Bool) (needle : Value) (xs : List Value) : Bool → Nat → Bool
  | false, i => ltv (xs.getD i .unit) needle
  | true, i => !ltv needle (xs.getD i .unit)

theorem rightOf_part {ltv : Value → Value → Bool} {needle : Value} {xs : List Value}
    (sorted : Sorted ltv xs) (order : NegTrans ltv) (swap : Bool) :
    ∀ i j, i ≤ j → j < xs.length → rightOf ltv needle xs swap j = true → rightOf ltv needle xs swap i = true := by
  intro i j le hj yes
  by_cases same : i = j
  · rw [same]; exact yes
  have below := sorted.at (by omega) hj (by omega : i < j)
  cases swap with
  | false =>
      simp only [rightOf, getD_of_lt hj, getD_of_lt (show i < xs.length by omega)] at yes ⊢
      rcases order _ _ _ yes with h | h
      · rw [below] at h; cases h
      · exact h
  | true =>
      simp only [rightOf, getD_of_lt hj, getD_of_lt (show i < xs.length by omega), Bool.not_eq_eq_eq_not, Bool.not_true] at yes ⊢
      cases h : ltv needle xs[i] with
      | false => rfl
      | true =>
          rcases order _ xs[j] _ h with h' | h'
          · rw [yes] at h'; cases h'
          · rw [below] at h'; cases h'

/-! ## `lower_bound` and `upper_bound` -/

theorem bound_spec (inst : VecInstance P T ids) (kind : ElemKind P T size) {f lt : FunctionId} (swap : Bool)
    (found : P.function? f = some (boundFn ids T f lt swap))
    {ltv : Value → Value → Bool} {needle : Value} {xs : List Value}
    (ltSpec : LtSpec P lt ltv (needle :: xs)) (sorted : Sorted ltv xs) (order : NegTrans ltv)
    {caller : State} (formed : caller.CellsWellFormed) {v : Value}
    (rep : VecRep P T size ids.vec caller.heap v xs) :
    ∃ (after : State) (r : Nat), RunsExpr P caller (.call f ([v, needle].map Expr.value)) (.signed .i32 r) after ∧
      PureFrame caller after ∧ r ≤ xs.length ∧
      (∀ i, i < r → rightOf ltv needle xs swap i = true) ∧
      (∀ i, r ≤ i → i < xs.length → rightOf ltv needle xs swap i = false) := by
  have target := inst.target
  obtain ⟨p, cap, rfl, lenLe, capBound, buffer, reads⟩ := rep
  let vv := Value.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]
  let E0 : State := { caller with locals := [] }
  have f0 : E0.CellsWellFormed := formed
  have f1 := f0.bindLocal 0 vv
  let E := (E0.bindLocal 0 vv).bindLocal 1 needle
  have fE : E.CellsWellFormed := f1.bindLocal _ _
  have l1 : E.local? 1 = some needle := local_bound f1 1 _
  have l0 : E.local? 0 = some vv := local_kept f1 _ (by decide) (local_bound f0 0 _)
  obtain ⟨S', slots, frame⟩ := slots_call inst kind fE l0 capBound buffer
  have fS : S'.CellsWellFormed := frame.afterFormed
  let view := Value.rawSlice T (viewAddr T size p cap) cap
  let B := S'.bindLocal 2 view
  have fB : B.CellsWellFormed := fS.bindLocal _ _
  have b2 : B.local? 2 = some view := local_bound fS 2 _
  have b1 : B.local? 1 = some needle := local_kept fS _ (by decide) (frame.localFound l1)
  have b0 : B.local? 0 = some vv := local_kept fS _ (by decide) (frame.localFound l0)
  have hB : B.heap = caller.heap := frame.heap
  -- the loop
  have cmpSpec : ∀ (s : State) (mid : Nat), mid < xs.length → s.CellsWellFormed → FreshCellFrame B s →
      s.heap = B.heap → s.i32ArrayViews = B.i32ArrayViews → s.local? 5 = some (.signed .i32 mid) →
      (∀ id v, id ≠ 3 → id ≠ 4 → id ≠ 5 → B.local? id = some v → s.local? id = some v) →
      ∃ after, RunsExpr P s (cmpExpr lt swap) (.boolean (rightOf ltv needle xs swap mid != swap)) after ∧
        PureFrame s after := by
    intro s mid hmid fs _ heap _ s5 old
    have s1 := old 1 _ (by decide) (by decide) (by decide) b1
    have s2 := old 2 _ (by decide) (by decide) (by decide) b2
    have readOk : readRawSliceIndex P s T (viewAddr T size p cap) cap mid = .ok xs[mid] :=
      reads mid hmid s (by rw [heap, hB]; exact ReadsWithin.refl _ _ _)
    have item := RunsExpr.rawIndex s2 s5 readOk
    cases swap with
    | false =>
        obtain ⟨after, call, pure⟩ := ltSpec s fs xs[mid] (by simp) needle (by simp)
        refine ⟨after, ?_, pure⟩
        rw [show (rightOf ltv needle xs false mid != false) = ltv xs[mid] needle by
          simp only [rightOf, Bool.bne_false, getD_of_lt hmid]]
        exact callArgs (RunsExprs.two item (RunsExpr.local' s1)) call
    | true =>
        obtain ⟨after, call, pure⟩ := ltSpec s fs needle (by simp) xs[mid] (by simp)
        refine ⟨after, ?_, pure⟩
        rw [show (rightOf ltv needle xs true mid != true) = ltv needle xs[mid] by
          simp only [rightOf, Bool.bne_true, Bool.not_not, getD_of_lt hmid]]
        exact callArgs (RunsExprs.two (RunsExpr.local' s1) item) call
  obtain ⟨after, r, loopRun, cells, heap, world, views, a3, le, below, above⟩ :=
    search_loop_spec target fB (by omega) (rightOf ltv needle xs swap) (rightOf_part sorted order swap) swap
      (cmpExpr lt swap) cmpSpec
  suffices whole : ∃ after', RunsExpr P caller (.call f ([vv, needle].map Expr.value)) (.signed .i32 r) after' ∧
      PureFrame caller after' by
    obtain ⟨after', run', frame'⟩ := whole
    exact ⟨after', r, run', frame', le, below, above⟩
  refine PureRun.call found rfl rfl formed ?_
  change PureRun P E _ _
  refine PureRun.letRun slots frame ?_
  refine PureRun.letValue fB ?_
  let B3 := B.bindLocal 3 (.signed .i32 0)
  have fB3 : B3.CellsWellFormed := fB.bindLocal _ _
  have b3_0 : B3.local? 0 = some vv := local_kept fB _ (by decide) b0
  have ret : RunsStmt P after (.returnValue (some (.local 3))) (.returned (some (.signed .i32 r))) after :=
    RunsStmt.returnValue (RunsExpr.local' a3)
  refine ⟨_, RunsStmt.letLocal (RunsExpr.field' (j := 1) (RunsExpr.local' b3_0) rfl)
    (RunsStmt.sequenceNext loopRun ret), ?_, heap, world, views⟩
  obtain ⟨e, c, nx, fr⟩ := cells
  exact ⟨e, c, nx, fr⟩

def lowerBoundFn (ids : VecIds) (T : Ty) (f lt : FunctionId) : Function := boundFn ids T f lt false
def upperBoundFn (ids : VecIds) (T : Ty) (f lt : FunctionId) : Function := boundFn ids T f lt true

/-- `lower_bound(v, needle)` on a sorted vector: the number of elements less
than `needle`. -/
theorem lowerBound_spec (inst : VecInstance P T ids) (kind : ElemKind P T size) {f lt : FunctionId}
    (found : P.function? f = some (lowerBoundFn ids T f lt))
    {ltv : Value → Value → Bool} {needle : Value} {xs : List Value}
    (ltSpec : LtSpec P lt ltv (needle :: xs)) (sorted : Sorted ltv xs) (order : NegTrans ltv)
    {caller : State} (formed : caller.CellsWellFormed) {v : Value}
    (rep : VecRep P T size ids.vec caller.heap v xs) :
    ∃ after, RunsExpr P caller (.call f ([v, needle].map Expr.value))
      (.signed .i32 (lowerBoundOf ltv needle xs)) after ∧ PureFrame caller after := by
  obtain ⟨after, r, run, frame, le, below, above⟩ :=
    bound_spec inst kind false found ltSpec sorted order formed rep
  have eq : lowerBoundOf ltv needle xs = r := takeWhile_length_eq xs r le
    (fun i h lt => by have := below i lt; simp only [rightOf, getD_of_lt h] at this; exact this)
    (fun i h ge => by have := above i ge h; simp only [rightOf, getD_of_lt h] at this; exact this)
  rw [eq]; exact ⟨after, run, frame⟩

/-- `upper_bound(v, needle)` on a sorted vector: the number of elements not
greater than `needle`. -/
theorem upperBound_spec (inst : VecInstance P T ids) (kind : ElemKind P T size) {f lt : FunctionId}
    (found : P.function? f = some (upperBoundFn ids T f lt))
    {ltv : Value → Value → Bool} {needle : Value} {xs : List Value}
    (ltSpec : LtSpec P lt ltv (needle :: xs)) (sorted : Sorted ltv xs) (order : NegTrans ltv)
    {caller : State} (formed : caller.CellsWellFormed) {v : Value}
    (rep : VecRep P T size ids.vec caller.heap v xs) :
    ∃ after, RunsExpr P caller (.call f ([v, needle].map Expr.value))
      (.signed .i32 (upperBoundOf ltv needle xs)) after ∧ PureFrame caller after := by
  obtain ⟨after, r, run, frame, le, below, above⟩ :=
    bound_spec inst kind true found ltSpec sorted order formed rep
  have eq : upperBoundOf ltv needle xs = r := takeWhile_length_eq xs r le
    (fun i h lt => by have := below i lt; simp only [rightOf, getD_of_lt h] at this; exact this)
    (fun i h ge => by have := above i ge h; simp only [rightOf, getD_of_lt h] at this; exact this)
  rw [eq]; exact ⟨after, run, frame⟩

#print axioms bound_spec
#print axioms lowerBound_spec
#print axioms upperBound_spec

end Lanius.Std
