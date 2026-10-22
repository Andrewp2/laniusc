import Lanius.Std.VecMore

/-! # `try_clone`

A nonempty vector clones into fresh storage of capacity `len`, through
`try_with_capacity` and the copy loop. Everything the heap held before is
kept: the source still represents its list. -/

namespace Lanius.Std

open Lanius Lanius.Core Lanius.Semantics Lanius.Memory

variable {P : Program} {T : Ty} {ids : VecIds} {g : GrowIds} {mo : MoreIds} {size : Nat}

/-- Everything apart from the empty range `[0, 0)`, that is everything, is
kept. -/
theorem Kept.everything {h H : Heap} (kept : Kept h H 0 0) (positive : 0 < size) {v : Value}
    {xs : List Value} {vec : TypeId} (rep : VecRep P T size vec h v xs) : VecRep P T size vec H v xs := by
  obtain ⟨p, cap, same, lenLe, capBound, buffer, reads⟩ := rep
  exact ⟨p, cap, same, lenLe, capBound,
    fun pos => kept.buffers p (size * cap) (Nat.mul_pos positive pos) (Or.inr (Nat.zero_le _)) (buffer pos),
    fun i inside other within =>
      reads i inside other (ReadsWithin.trans (kept.reads _ _ (Or.inr (Nat.zero_le _))) within)⟩

/-- `try_clone(v)` of a nonempty vector with room in the heap for `len(v)`
elements: a vector of the same list in fresh storage of capacity `len(v)`.
Only fresh storage is written, so everything else, the source included,
is kept. -/
theorem tryClone_spec (inst : MoreInstance P T ids g mo) (kind : ElemKind P T size)
    {caller : State} (formed : caller.CellsWellFormed) {xs : List Value} {p cap : Nat}
    (rep : VecRep P T size ids.vec caller.heap
      (.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]) xs)
    (nonempty : 0 < xs.length) (fits : size * xs.length ≤ 2147483647)
    {budget : Option Nat} (available : consumeBudget caller.heap.remaining (size * xs.length) = some budget)
    (room : caller.heap.allocationAddress 8 + size * xs.length < 2 ^ 64)
    (below : HeapBlocksBelowNext caller.heap) (unique : HeapBlockBasesUnique caller.heap)
    (noViews : caller.i32ArrayViews = []) (stores : ∀ x ∈ xs, ElemStore P T size x) :
    ∃ after, RunsExpr P caller (.call mo.tryClone
        ([Value.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]].map Expr.value))
      (.structure ids.vec [.pointer (caller.heap.allocationAddress 8), .signed .i32 xs.length,
        .signed .i32 xs.length]) after ∧
      FreshCellFrame caller after ∧ after.world = caller.world ∧
      after.i32ArrayViews = caller.i32ArrayViews ∧
      Grown P T size ids.vec caller.heap 0 0 (caller.heap.allocationAddress 8) xs.length xs after.heap := by
  have target := inst.grow.vec.target
  obtain ⟨_, lenLe, capBound, buffer, reads⟩ := rep.fields
  let n := xs.length
  have positive := kind.size_pos
  have nBound : xs.length < 2 ^ 31 := by
    have := Nat.le_mul_of_pos_left xs.length positive; omega
  let Q := caller.heap.allocationAddress 8
  have fresh : caller.heap.nextAddress ≤ Q := Heap.allocationAddress_ge _ (by decide)
  have capPos : 0 < cap := by omega
  have oldBelow : p + size * cap ≤ Q := by
    have := ((buffer capPos).2.1).belowNext (Nat.mul_pos positive capPos) below
    dsimp only [Lanius.Address] at *; omega
  let vv := Value.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]
  refine Grow.call (vs := [vv]) (Q := Grown P T size ids.vec caller.heap 0 0 Q xs.length xs)
    inst.tryClone rfl rfl ?_
  let E0 : State := { caller with locals := [] }
  have f0 : E0.CellsWellFormed := formed
  let E := E0.bindLocal 0 vv
  change Grow P E _ _ _
  have fE : E.CellsWellFormed := f0.bindLocal _ _
  have l0 : E.local? 0 = some vv := local_bound f0 0 _
  have hE : E.heap = caller.heap := rfl
  -- let copy = try_with_capacity(value.length)
  obtain ⟨R, wcRun, cells, world, views, grown⟩ := tryWithCapacity_spec inst kind fE nonempty fits
    (by rw [hE]; exact available) (by rw [hE]; exact room) (by rw [hE]; exact below) (by rw [hE]; exact unique)
    noViews
  rw [hE] at wcRun grown
  have wcCall := callArgs (RunsExprs.one (RunsExpr.field' (j := 1) (RunsExpr.local' l0) rfl)) wcRun
  have locals : R.locals = E.locals := wcCall.choose_spec.2
  refine Grow.letRun wcCall ⟨fE, cells, world, views⟩ ?_
  have fR := FreshCellFrame.after_cellsWellFormed fE cells
  obtain ⟨rep2, kept2, below2, unique2, next2, apart2⟩ := grown
  obtain ⟨_, _, _, buffer2, _⟩ := rep2.fields
  let copy := Value.structure ids.vec [.pointer Q, .signed .i32 0, .signed .i32 n]
  let B1 := R.bindLocal 1 copy
  have fB1 : B1.CellsWellFormed := fR.bindLocal _ _
  have b1 : B1.local? 1 = some copy := local_bound fR 1 _
  have b0 : B1.local? 0 = some vv := local_kept fR _ (by decide) (cells.localFound locals 0 _ l0)
  have hB1 : B1.heap = R.heap := rfl
  have vB1 : B1.i32ArrayViews = [] := views.trans noViews
  have cond := RunsExpr.binary (operation := .less) (program := P)
    (RunsExpr.field' (j := 2) (RunsExpr.local' b1) rfl) (RunsExpr.field' (j := 1) (RunsExpr.local' b0) rfl)
    (by decide) (eval_i32_lt _ _ _)
  rw [show decide ((n : Int) < (xs.length : Int)) = false by simp [n]] at cond
  refine Grow.guardSkip cond (Ext.refl fB1) ?_
  -- let from = slots(value)
  have bufP : 0 < cap → Buffer B1.heap p (size * cap) := fun pos =>
    kept2.buffers p (size * cap) (Nat.mul_pos positive pos) (Or.inr (Nat.zero_le _)) (buffer pos)
  obtain ⟨S3, fromRun, fr3⟩ := slots_call inst.grow.vec kind fB1 b0 capBound bufP
  refine Grow.letRun fromRun (Ext.ofPure fr3) ?_
  have fS3 := fr3.afterFormed
  let B3 := S3.bindLocal 3 (.rawSlice T (viewAddr T size p cap) cap)
  have fB3 : B3.CellsWellFormed := fS3.bindLocal _ _
  have hB3 : B3.heap = R.heap := fr3.heap
  have b3_1 : B3.local? 1 = some copy := local_kept fS3 _ (by decide) (fr3.localFound b1)
  -- let to = slots(copy)
  obtain ⟨S4, toRun, fr4⟩ := slots_call (xs := []) inst.grow.vec kind fB3 b3_1 nBound
    (fun pos => by rw [hB3]; exact buffer2 pos)
  refine Grow.letRun toRun (Ext.ofPure fr4) ?_
  have fS4 := fr4.afterFormed
  let B4 := S4.bindLocal 4 (.rawSlice T (viewAddr T size Q n) n)
  have fB4 : B4.CellsWellFormed := fS4.bindLocal _ _
  have hB4 : B4.heap = R.heap := fr4.heap.trans hB3
  have keep4 : ∀ (id : VarId) (v : Value), id ≠ 3 → id ≠ 4 → B1.local? id = some v → B4.local? id = some v :=
    fun id v n3 n4 found => local_kept fS4 _ (Ne.symm n4)
      (fr4.localFound (local_kept fS3 _ (Ne.symm n3) (fr3.localFound found)))
  have b4_0 := keep4 0 vv (by decide) (by decide) b0
  have b4_1 := keep4 1 copy (by decide) (by decide) b1
  have b4_3 : B4.local? 3 = some (.rawSlice T (viewAddr T size p cap) cap) :=
    local_kept fS4 _ (by decide) (fr4.localFound (local_bound fS3 3 _))
  have b4_4 : B4.local? 4 = some (.rawSlice T (viewAddr T size Q n) n) := local_bound fS4 4 _
  have vB4 : B4.i32ArrayViews = [] := (fr4.views.trans fr3.views).trans vB1
  -- the copy loop
  obtain ⟨h2, loopRun, effect, copied⟩ := copy_loop_spec target kind fB4 (idx := 5) (vec := 0) (src := 3)
    (dst := 4) (by decide) (by decide) (by decide) b4_0 b4_3 b4_4 lenLe (Nat.le_refl _) nBound
    (fun i inside other within => reads i inside other (ReadsWithin.trans
      (by rw [hB4]; exact kept2.reads _ _ (Or.inr (Nat.zero_le _))) within))
    (fun pos => by rw [hB4]; exact buffer2 pos) (Or.inl oldBelow) stores vB4 (by rw [hB4]; exact unique2)
  rw [hB4] at effect
  let W := ({ B4 with heap := h2 } : State).bindLocal 5 (.signed .i32 xs.length)
  have fW0 : ({ B4 with heap := h2 } : State).CellsWellFormed := fB4
  have w0 : W.local? 0 = some vv := local_kept fW0 _ (by decide) b4_0
  have w1 : W.local? 1 = some copy := local_kept fW0 _ (by decide) b4_1
  have ret : RunsStmt P W (.returnValue (some (.structValue ids.vec
      [.field (.local 1) 0, .field (.local 0) 1, .field (.local 1) 2])))
      (.returned (some (.structure ids.vec [.pointer Q, .signed .i32 xs.length, .signed .i32 n]))) W :=
    RunsStmt.returnValue (RunsExprs.toRun (RunsExprs.three (RunsExpr.field' (j := 0) (RunsExpr.local' w1) rfl)
      (RunsExpr.field' (j := 1) (RunsExpr.local' w0) rfl) (RunsExpr.field' (j := 2) (RunsExpr.local' w1) rfl)))
  refine ⟨restoreLocals B4 W, RunsStmt.letLocal (RunsExpr.value' _) (RunsStmt.sequenceNext loopRun ret),
    ((Ext.heap fB4 h2).trans (Ext.bindLocal fW0 5 _)).restore B4, ?_⟩
  have bytesPos : 0 < size * n := Nat.mul_pos positive nonempty
  show Grown P T size ids.vec caller.heap 0 0 Q xs.length xs h2
  refine ⟨⟨Q, n, rfl, Nat.le_refl _, nBound, fun _ => (buffer2 (by omega)).afterWrite effect, copied⟩,
    kept2.afterFreshWrite below fresh effect, effect.below below2, effect.unique, effect.frontier.trans next2,
    fun ap => HeapApart.ofWrite effect (apart2 ap)⟩

#print axioms tryClone_spec

end Lanius.Std
