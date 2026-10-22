import Lanius.Std.SetAppend

/-! # `try_intersection` and `try_difference`

Both count the items of `left` that are (`try_intersection`) or are not
(`try_difference`) in `right`, reserve exactly that many slots and append
those items, so they share one template, `setKeepWhereFn present`. When the
heap has room, the result is a fresh set of those items in `left`'s order,
whose storage is new (above the caller's frontier), and everything the
caller could read survives. -/

namespace Lanius.Std

open Lanius Lanius.Core Lanius.Semantics Lanius.Memory

variable {P : Program} {T : Ty} {ids : VecIds} {g : GrowIds} {mo : MoreIds} {size : Nat}

/-- `count_where(left, right, present)`, `reserved_for`, the capacity check
and `append_where(output, left, right, present)`; locals 0 `left`, 1
`right`, 2 `count`, 3 `output`. -/
def setKeepWhereFn (ids : VecIds) (sid : TypeId) (f cw rf aw sn : FunctionId) (present : Bool) : Function where
  id := f
  parameters := [(0, setTy sid), (1, setTy sid)]
  returnType := setTy sid
  body := some <|
    .letLocal 2 i32Ty (.call cw [.local 0, .local 1, .value (.boolean present)])
    (.letLocal 3 (vecTy ids) (.call rf [.local 2])
    (.sequence
      (.ifThenElse (.binary .less (.call ids.capacity [.local 3]) (.local 2)) (.returnValue (some (.call sn []))) .skip)
      (.returnValue (some (.structValue sid [.call aw [.local 3, .local 0, .local 1, .value (.boolean present)]])))))

theorem capacity_exact (inst : VecInstance P T ids) {caller : State} (formed : caller.CellsWellFormed)
    (p : Nat) (len : Value) (cap : Nat) :
    ∃ after, RunsExpr P caller (.call ids.capacity
        ([Value.structure ids.vec [.pointer p, len, .signed .i32 cap]].map Expr.value)) (.signed .i32 cap) after ∧
      PureFrame caller after := by
  refine PureRun.call inst.capacity rfl rfl formed ?_
  let E0 : State := { caller with locals := [] }
  have f0 : E0.CellsWellFormed := formed
  change PureRun P (E0.bindLocal 0 _) _ _
  exact PureRun.ret (f0.bindLocal _ _) (RunsExpr.field' (RunsExpr.local' (local_bound f0 0 _)) rfl)

theorem Kept.same (h : Heap) (p n : Nat) : Kept h h p n :=
  ⟨fun _ _ _ => fun _ _ _ _ _ read => read, fun _ _ _ _ buffer => buffer⟩

theorem Kept.ofNone {h H : Heap} (kept : Kept h H 0 0) (q n : Nat) : Kept h H q n :=
  ⟨fun lo m _ => kept.reads lo m (Or.inr (Nat.zero_le _)),
    fun r m pos _ buffer => kept.buffers r m pos (Or.inr (Nat.zero_le _)) buffer⟩

theorem VecRep.emptyAt (P : Program) (T : Ty) (size : Nat) (vec : TypeId) (h : Heap) :
    VecRep P T size vec h (.structure vec [.pointer 0, .signed .i32 ([] : List Value).length, .signed .i32 0]) [] :=
  ⟨0, 0, rfl, Nat.le_refl _, by decide, fun pos => absurd pos (Nat.lt_irrefl 0),
    fun _ inside => absurd inside (Nat.not_lt_zero _)⟩

/-- What a set algebra result leaves: the vector of `zs` at fresh storage
`q` of capacity `m`, and the caller's heap apart from it. -/
def AlgebraOut (P : Program) (T : Ty) (size : Nat) (vec : TypeId) (h : Heap) (q m : Nat) (zs : List Value)
    (H : Heap) : Prop :=
  VecRep P T size vec H (.structure vec [.pointer q, .signed .i32 zs.length, .signed .i32 m]) zs ∧
    Kept h H q (size * m) ∧ HeapBlocksBelowNext H ∧ HeapBlockBasesUnique H ∧ HeapApart H

/-- `try_intersection(left, right)` (`present = true`) and
`try_difference(left, right)` (`present = false`) when the heap has room
for the kept items. -/
theorem setKeepWhere_spec (more : MoreInstance P T ids g mo) (kind : ElemKind P T size) {sid : TypeId}
    {si : SetIds} (inst : SetInstance P T ids sid si) {f cw rf aw sn : FunctionId} {present : Bool}
    (found : P.function? f = some (setKeepWhereFn ids sid f cw rf aw sn present))
    (cwFound : P.function? cw = some (setCountWhereFn sid cw si.sl si.sc si.atf))
    (rfFound : P.function? rf = some (setReservedForFn ids mo rf))
    (awFound : P.function? aw = some (setAppendWhereFn ids g T sid aw si))
    {eqv : Value → Value → Bool} {vals : List Value} (eqSpec : EqSpec P si.eq eqv vals)
    {caller : State} (formed : caller.CellsWellFormed) {xs ys : List Value} {p cap r rc : Nat}
    (repL : VecRep P T size ids.vec caller.heap
      (.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]) xs)
    (repR : VecRep P T size ids.vec caller.heap
      (.structure ids.vec [.pointer r, .signed .i32 ys.length, .signed .i32 rc]) ys)
    (subL : ∀ z ∈ xs, z ∈ vals) (subR : ∀ z ∈ ys, z ∈ vals) (stores : ∀ y ∈ xs, ElemStore P T size y)
    (alloc : 0 < (whereIn eqv ys present xs).length →
      size * (whereIn eqv ys present xs).length ≤ 2147483647 ∧
      (∃ budget : Option Nat,
        consumeBudget caller.heap.remaining (size * (whereIn eqv ys present xs).length) = some budget) ∧
      caller.heap.allocationAddress 8 + size * (whereIn eqv ys present xs).length < 2 ^ 64)
    (below : HeapBlocksBelowNext caller.heap) (unique : HeapBlockBasesUnique caller.heap)
    (apart : HeapApart caller.heap) (noViews : caller.i32ArrayViews = []) :
    ∃ (after : State) (q m : Nat), RunsExpr P caller (.call f
        ([Value.structure sid [.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]],
          .structure sid [.structure ids.vec [.pointer r, .signed .i32 ys.length, .signed .i32 rc]]].map Expr.value))
      (.structure sid [.structure ids.vec
        [.pointer q, .signed .i32 (whereIn eqv ys present xs).length, .signed .i32 m]]) after ∧
      FreshCellFrame caller after ∧ after.world = caller.world ∧ after.i32ArrayViews = caller.i32ArrayViews ∧
      (0 < m → caller.heap.nextAddress ≤ q) ∧
      AlgebraOut P T size ids.vec caller.heap q m (whereIn eqv ys present xs) after.heap := by
  have positive : 0 < size := kind.size_pos
  obtain ⟨_, _, _, bufL, _⟩ := repL.fields
  obtain ⟨_, _, _, bufR, _⟩ := repR.fields
  let W := whereIn eqv ys present xs
  let n := W.length
  let vvL := Value.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]
  let vvR := Value.structure ids.vec [.pointer r, .signed .i32 ys.length, .signed .i32 rc]
  let E0 : State := { caller with locals := [] }
  have f0 : E0.CellsWellFormed := formed
  have f1 := f0.bindLocal 0 (.structure sid [vvL])
  let E := (E0.bindLocal 0 (.structure sid [vvL])).bindLocal 1 (.structure sid [vvR])
  have fE : E.CellsWellFormed := f1.bindLocal _ _
  have l1 : E.local? 1 = some (.structure sid [vvR]) := local_bound f1 1 _
  have l0 : E.local? 0 = some (.structure sid [vvL]) := local_kept f1 _ (by decide) (local_bound f0 0 _)
  -- count_where(left, right, present)
  obtain ⟨c1, countRun, pc1⟩ := setCountWhere_spec inst.vec kind cwFound inst.sl inst.sc inst.vc inst.indexOf
    inst.atf inst.asl inst.pf eqSpec fE (caller := E) repL repR subL subR (apart.disjoint unique) present
  have countCall := callArgs (RunsExprs.three (RunsExpr.local' l0) (RunsExpr.local' l1) (RunsExpr.value' _))
    countRun
  have fc1 := pc1.afterFormed
  let S2 := c1.bindLocal 2 (.signed .i32 n)
  have fS2 : S2.CellsWellFormed := fc1.bindLocal _ _
  have s2 : S2.local? 2 = some (.signed .i32 n) := local_bound fc1 2 _
  have s1 : S2.local? 1 = some (.structure sid [vvR]) := local_kept fc1 _ (by decide) (pc1.localFound l1)
  have s0 : S2.local? 0 = some (.structure sid [vvL]) := local_kept fc1 _ (by decide) (pc1.localFound l0)
  have hS2 : S2.heap = caller.heap := pc1.heap
  have vS2 : S2.i32ArrayViews = [] := pc1.views.trans noViews
  -- the rest, from the run of reserved_for(count)
  have tail : ∀ (S3 : State) (q m : Nat),
      RunsExpr P S2 (.call rf [.local 2]) (.structure ids.vec [.pointer q, .signed .i32 0, .signed .i32 m]) S3 →
      Ext S2 S3 → S3.i32ArrayViews = [] → n ≤ m →
      VecRep P T size ids.vec S3.heap
        (.structure ids.vec [.pointer q, .signed .i32 ([] : List Value).length, .signed .i32 m]) [] →
      VecRep P T size ids.vec S3.heap vvL xs → VecRep P T size ids.vec S3.heap vvR ys →
      (0 < cap → (p + size * cap ≤ q ∨ q + size * m ≤ p)) →
      (0 < rc → (r + size * rc ≤ q ∨ q + size * m ≤ r)) →
      HeapBlocksBelowNext S3.heap → HeapBlockBasesUnique S3.heap → HeapApart S3.heap →
      Kept caller.heap S3.heap q (size * m) →
      Grow P S2 (.letLocal 3 (vecTy ids) (.call rf [.local 2])
        (.sequence
          (.ifThenElse (.binary .less (.call ids.capacity [.local 3]) (.local 2)) (.returnValue (some (.call sn []))) .skip)
          (.returnValue (some (.structValue sid [.call aw [.local 3, .local 0, .local 1, .value (.boolean present)]])))))
        (.returned (some (.structure sid [.structure ids.vec [.pointer q, .signed .i32 n, .signed .i32 m]])))
        (AlgebraOut P T size ids.vec caller.heap q m W) := by
    intro S3 q m rfRun ext3 views3 nm repO repL3 repR3 apL apR below3 unique3 apart3 kept3
    have loc3 : S3.locals = S2.locals := rfRun.choose_spec.2
    have f3 := ext3.afterFormed
    let outv := Value.structure ids.vec [.pointer q, .signed .i32 0, .signed .i32 m]
    let S4 := S3.bindLocal 3 outv
    have fS4 : S4.CellsWellFormed := f3.bindLocal _ _
    have m3 : S4.local? 3 = some outv := local_bound f3 3 _
    have m2 : S4.local? 2 = some (.signed .i32 n) := local_kept f3 _ (by decide) (ext3.cells.localFound loc3 2 _ s2)
    have m1 : S4.local? 1 = some (.structure sid [vvR]) :=
      local_kept f3 _ (by decide) (ext3.cells.localFound loc3 1 _ s1)
    have m0 : S4.local? 0 = some (.structure sid [vvL]) :=
      local_kept f3 _ (by decide) (ext3.cells.localFound loc3 0 _ s0)
    obtain ⟨c5, capRun, pc5⟩ := capacity_exact inst.vec fS4 q (.signed .i32 0) m
    have cond := RunsExpr.binary (operation := .less) (callArgs (RunsExprs.one (RunsExpr.local' m3)) capRun)
      (RunsExpr.local' (pc5.localFound m2)) (by decide) (eval_i32_lt _ _ _)
    rw [show decide ((m : Int) < (n : Int)) = false by simp; omega] at cond
    have hc5 : c5.heap = S3.heap := pc5.heap
    have fc5 := pc5.afterFormed
    obtain ⟨A, appendRun, cellsA, worldA, viewsA, repA, keptA, belowA, uniqueA, apartA⟩ :=
      setAppendWhere_spec more.grow kind inst awFound eqSpec fc5 (acc := [])
        (by rw [hc5]; exact repO) (by rw [hc5]; exact repL3) (by rw [hc5]; exact repR3) apL apR present
        (by show 0 + n ≤ m; omega) subL subR stores (by rw [hc5]; exact below3) (by rw [hc5]; exact unique3)
        (by rw [hc5]; exact apart3) (pc5.views.trans views3)
    rw [hc5] at keptA
    refine Grow.letRun rfRun ext3 (Grow.guardSkip cond (Ext.ofPure pc5)
      (Grow.retWrap fc5 (RunsExprs.cons (RunsExpr.local' (pc5.localFound m3))
        (RunsExprs.three (RunsExpr.local' (pc5.localFound m0)) (RunsExpr.local' (pc5.localFound m1))
          (RunsExpr.value' _))) ⟨A, appendRun, cellsA, worldA, viewsA, repA, kept3.trans keptA, belowA, uniqueA,
            apartA⟩))
  have whole : ∀ (S3 : State) (q m : Nat) (body : Grow P S2 _ _ (AlgebraOut P T size ids.vec caller.heap q m W)),
      (0 < m → caller.heap.nextAddress ≤ q) →
      ∃ (after : State) (q m : Nat), RunsExpr P caller (.call f
          ([Value.structure sid [vvL], .structure sid [vvR]].map Expr.value))
        (.structure sid [.structure ids.vec [.pointer q, .signed .i32 n, .signed .i32 m]]) after ∧
        FreshCellFrame caller after ∧ after.world = caller.world ∧ after.i32ArrayViews = caller.i32ArrayViews ∧
        (0 < m → caller.heap.nextAddress ≤ q) ∧ AlgebraOut P T size ids.vec caller.heap q m W after.heap :=
    fun _ q m body newer => by
      obtain ⟨after, call, cells, world, views, out⟩ := Grow.call
        (vs := [.structure sid [vvL], .structure sid [vvR]])
        (bindings := [(0, .structure sid [vvL]), (1, .structure sid [vvR])])
        (Q := AlgebraOut P T size ids.vec caller.heap q m W) found rfl rfl
        (Grow.letRun countCall (Ext.ofPure pc1) body)
      exact ⟨after, q, m, call, cells, world, views, newer, out⟩
  by_cases zero : n = 0
  · obtain ⟨S3, run, pure3⟩ := setReservedFor_empty_spec more rfFound fS2 (n := (n : Int)) (by omega)
    have h3 : S3.heap = caller.heap := pure3.heap.trans hS2
    have k3 : Kept caller.heap S3.heap 0 (size * 0) := by rw [h3]; exact Kept.same _ _ _
    exact whole S3 0 0 (tail S3 0 0 (callArgs (RunsExprs.one (RunsExpr.local' s2)) run) (Ext.ofPure pure3)
      (pure3.views.trans vS2) (by omega) (VecRep.emptyAt P T size ids.vec _) (by rw [h3]; exact repL)
      (by rw [h3]; exact repR) (fun _ => Or.inr (by omega)) (fun _ => Or.inr (by omega)) (by rw [h3]; exact below)
      (by rw [h3]; exact unique) (by rw [h3]; exact apart) k3) (fun none => absurd none (Nat.lt_irrefl 0))
  · have npos : 0 < n := Nat.pos_of_ne_zero zero
    obtain ⟨fits, ⟨budget, available⟩, room⟩ := alloc npos
    let q := caller.heap.allocationAddress 8
    have fresh : caller.heap.nextAddress ≤ q := Heap.allocationAddress_ge _ (by decide)
    obtain ⟨S3, run, cells3, world3, views3, grown⟩ := setReservedFor_spec more kind rfFound fS2 npos fits
      (by rw [hS2]; exact available) (by rw [hS2]; exact room) (by rw [hS2]; exact below)
      (by rw [hS2]; exact unique) vS2
    rw [hS2] at run grown
    obtain ⟨rep1, kept1, below1, unique1, _, apart1⟩ := grown
    have oldL : 0 < cap → p + size * cap ≤ q := fun pos => by
      have := ((bufL pos).2.1).belowNext (Nat.mul_pos positive pos) below
      dsimp only [Lanius.Address] at *; omega
    have oldR : 0 < rc → r + size * rc ≤ q := fun pos => by
      have := ((bufR pos).2.1).belowNext (Nat.mul_pos positive pos) below
      dsimp only [Lanius.Address] at *; omega
    exact whole S3 q n (tail S3 q n (callArgs (RunsExprs.one (RunsExpr.local' s2)) run)
      ⟨fS2, cells3, world3, views3⟩ (views3.trans vS2) (Nat.le_refl _) rep1
      (repL.keptApart kept1 (fun _ => Or.inr (Nat.zero_le _)) positive)
      (repR.keptApart kept1 (fun _ => Or.inr (Nat.zero_le _)) positive)
      (fun pos => Or.inl (oldL pos)) (fun pos => Or.inl (oldR pos)) below1 unique1 (apart1 apart)
      (kept1.ofNone q (size * n))) (fun _ => fresh)

#print axioms setKeepWhere_spec

end Lanius.Std
