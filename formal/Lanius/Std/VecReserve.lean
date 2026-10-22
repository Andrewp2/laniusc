import Lanius.Std.VecGrow

/-! # `try_reserve`

Runs that may write the heap (`Grow`): the caller sees fresh cells only and
the same world and views (`Ext`), and a property of the final heap. Then
`try_reserve` when it grows: it allocates the new storage, copies the
elements, frees the old storage and returns the new vector. -/

namespace Lanius.Std

open Lanius Lanius.Core Lanius.Semantics Lanius.Memory

variable {P : Program} {T : Ty} {ids : VecIds} {g : GrowIds} {size : Nat}

/-! ## Runs that may write the heap -/

/-- What a caller sees of a run that may write the heap. -/
structure Ext (S T : State) : Prop where
  formed : S.CellsWellFormed
  cells : FreshCellFrame S T
  world : T.world = S.world
  views : T.i32ArrayViews = S.i32ArrayViews

theorem Ext.refl {S : State} (formed : S.CellsWellFormed) : Ext S S :=
  ⟨formed, ⟨[], by simp, Nat.le_refl _, by simp⟩, rfl, rfl⟩

theorem Ext.trans {S M T : State} (a : Ext S M) (b : Ext M T) : Ext S T :=
  ⟨a.formed, a.cells.trans b.cells, b.world.trans a.world, b.views.trans a.views⟩

theorem Ext.afterFormed {S T : State} (e : Ext S T) : T.CellsWellFormed :=
  FreshCellFrame.after_cellsWellFormed e.formed e.cells

theorem Ext.ofPure {S T : State} (f : PureFrame S T) : Ext S T := ⟨f.beforeFormed, f.cells, f.world, f.views⟩

theorem Ext.bindLocal {S : State} (formed : S.CellsWellFormed) (id : VarId) (v : Value) :
    Ext S (S.bindLocal id v) := ⟨formed, FreshCellFrame.bindLocal S id v, rfl, rfl⟩

theorem Ext.restore {S T : State} (e : Ext S T) (x : State) : Ext S (restoreLocals x T) :=
  ⟨e.formed, by obtain ⟨a, b, c, d⟩ := e.cells; exact ⟨a, b, c, d⟩, e.world, e.views⟩

theorem Ext.heap {S : State} (formed : S.CellsWellFormed) (h : Heap) : Ext S { S with heap := h } :=
  ⟨formed, ⟨[], by simp, Nat.le_refl _, by simp⟩, rfl, rfl⟩

/-- A run of `s` from `S` completing with `k`, seen through `Ext`, whose
final heap has `Q`. -/
def Grow (P : Program) (S : State) (s : Stmt) (k : Completion) (Q : Heap → Prop) : Prop :=
  ∃ after, RunsStmt P S s k after ∧ Ext S after ∧ Q after.heap

theorem Grow.guardSkip {S S' : State} {c : Expr} {t rest : Stmt} {k : Completion} {Q : Heap → Prop}
    (cond : RunsExpr P S c (.boolean false) S') (ext : Ext S S') (tail : Grow P S' rest k Q) :
    Grow P S (.sequence (.ifThenElse c t .skip) rest) k Q := by
  obtain ⟨after, run, e, q⟩ := tail
  exact ⟨after, RunsStmt.sequenceNext (RunsStmt.ifThenElseFalse cond (RunsStmt.skip P S')) run, ext.trans e, q⟩

theorem Grow.letRun {S S' : State} {id : VarId} {ty : Ty} {e : Expr} {v : Value} {body : Stmt}
    {k : Completion} {Q : Heap → Prop}
    (init : RunsExpr P S e v S') (ext : Ext S S') (tail : Grow P (S'.bindLocal id v) body k Q) :
    Grow P S (.letLocal id ty e body) k Q := by
  obtain ⟨after, run, e', q⟩ := tail
  exact ⟨restoreLocals S' after, RunsStmt.letLocal init run,
    ((ext.trans (Ext.bindLocal ext.afterFormed id v)).trans e').restore S', q⟩

theorem bindLocals_world (S : State) (bs : List (VarId × Value)) : (S.bindLocals bs).world = S.world := by
  induction bs generalizing S with
  | nil => rfl
  | cons b rest ih => exact ih _

theorem bindLocals_views (S : State) (bs : List (VarId × Value)) :
    (S.bindLocals bs).i32ArrayViews = S.i32ArrayViews := by
  induction bs generalizing S with
  | nil => rfl
  | cons b rest ih => exact ih _

/-- A call whose body is a `Grow` run. -/
theorem Grow.call {caller : State} {f : FunctionId} {fn : Function} {body : Stmt} {vs : List Value}
    {bindings : List (VarId × Value)} {v : Value} {Q : Heap → Prop}
    (found : P.function? f = some fn) (bodyFound : fn.body = some body)
    (parameters : bindParameters fn.parameters vs = some bindings)
    (run : Grow P (({ caller with locals := [] } : State).bindLocals bindings) body (.returned (some v)) Q) :
    ∃ after, RunsExpr P caller (.call f (vs.map Expr.value)) v after ∧ FreshCellFrame caller after ∧
      after.world = caller.world ∧ after.i32ArrayViews = caller.i32ArrayViews ∧ Q after.heap := by
  obtain ⟨completed, r, e, q⟩ := run
  obtain ⟨after, call, cells, w, vw, qq⟩ := RunsExpr.callStores
    (fun heap world views => world = caller.world ∧ views = caller.i32ArrayViews ∧ Q heap)
    found bodyFound parameters ⟨completed, r, e.cells,
      e.world.trans (bindLocals_world _ _), e.views.trans (bindLocals_views _ _), q⟩
  exact ⟨after, call, cells, w, vw, qq⟩

/-- `dealloc(p, n, a);` with value arguments and no registered views. -/
theorem RunsExpr.dealloc' {S : State} {pE sE aE : Expr} {p n a : Nat} {h' : Heap}
    (args : RunsExprs P S [pE, sE, aE] [.pointer p, .unsigned .usize n, .unsigned .usize a] S)
    (noViews : S.i32ArrayViews = []) (freed : S.heap.deallocate p n a = .ok h') :
    RunsExpr P S (.dealloc pE sE aE) .unit { S with heap := h' } := by
  obtain ⟨t, run, _⟩ := args
  refine ⟨t + 1, fun fuel enough => ?_, rfl⟩
  rw [show fuel = (fuel - 1).succ by omega, evalExpr.eq_def]
  simp only [run (fuel - 1) (by omega)]
  simp [syncI32ViewsToHeap, noViews, syncI32ViewsToHeapFrom, freed]

/-! ## `try_reserve` -/

/-- What growing leaves in the heap: the new vector, everything apart from
the old storage, and the frontier. -/
def Grown (P : Program) (T : Ty) (size : Nat) (vec : TypeId) (h : Heap) (p n q m : Nat)
    (xs : List Value) (H : Heap) : Prop :=
  VecRep P T size vec H (.structure vec [.pointer q, .signed .i32 xs.length, .signed .i32 m]) xs ∧
    Kept h H p n ∧ HeapBlocksBelowNext H ∧ HeapBlockBasesUnique H ∧ H.nextAddress = q + size * m ∧
    (HeapApart h → HeapApart H)

theorem VecRep.fields {vec : TypeId} {h : Heap} {p cap : Nat} {len : Value} {xs : List Value}
    (rep : VecRep P T size vec h (.structure vec [.pointer p, len, .signed .i32 cap]) xs) :
    len = .signed .i32 xs.length ∧ xs.length ≤ cap ∧ cap < 2 ^ 31 ∧ (0 < cap → Buffer h p (size * cap)) ∧
      ∀ i (inside : i < xs.length) (other : State), ReadsWithin h other.heap (slotLo T size p cap i) size →
        readRawSliceIndex P other T (viewAddr T size p cap) cap i = .ok xs[i] := by
  obtain ⟨p', cap', same, lenLe, capBound, buffer, reads⟩ := rep
  simp only [Value.structure.injEq, List.cons.injEq, Value.pointer.injEq, Value.signed.injEq, true_and,
    and_true] at same
  obtain ⟨rfl, rfl, e⟩ := same
  have : cap = cap' := by omega
  subst this
  exact ⟨rfl, lenLe, capBound, buffer, reads⟩

/-- `try_reserve(v, min)` with `capacity(v) < min ≤ capacity_limit()` and
room for `min` elements: the vector moves to fresh storage at the next
aligned address, the old storage is freed, and nothing else changes. -/
theorem tryReserve_grow_spec (inst : GrowInstance P T ids g) (kind : ElemKind P T size)
    {caller : State} (formed : caller.CellsWellFormed) {xs : List Value} {p cap min : Nat}
    (rep : VecRep P T size ids.vec caller.heap
      (.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]) xs)
    (grows : cap < min) (fits : size * min ≤ 2147483647)
    {budget : Option Nat} (available : consumeBudget caller.heap.remaining (size * min) = some budget)
    (room : caller.heap.allocationAddress 8 + size * min < 2 ^ 64)
    (below : HeapBlocksBelowNext caller.heap) (unique : HeapBlockBasesUnique caller.heap)
    (noViews : caller.i32ArrayViews = []) (stores : ∀ x ∈ xs, ElemStore P T size x) :
    ∃ after, RunsExpr P caller (.call g.tryReserve
        ([Value.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap], .signed .i32 min].map
          Expr.value))
      (.structure ids.vec [.pointer (caller.heap.allocationAddress 8), .signed .i32 xs.length, .signed .i32 min])
      after ∧ FreshCellFrame caller after ∧ after.world = caller.world ∧
      after.i32ArrayViews = caller.i32ArrayViews ∧
      Grown P T size ids.vec caller.heap p (size * cap) (caller.heap.allocationAddress 8) min xs after.heap := by
  have target := inst.vec.target
  obtain ⟨_, lenLe, capBound, buffer, reads⟩ := rep.fields
  have positive := kind.size_pos
  have sizeBound := kind.size_le
  have minLimit : min ≤ capLimit size := (Nat.le_div_iff_mul_le positive).mpr (by rw [Nat.mul_comm]; exact fits)
  have minBound : min < 2 ^ 31 := by
    have : capLimit size ≤ 2147483647 := Nat.div_le_self _ _
    omega
  have bytesPos : 0 < size * min := Nat.mul_pos positive (by omega)
  let q := caller.heap.allocationAddress 8
  have qPos : 0 < q := Heap.allocationAddress_pos _ (by decide)
  have fresh : caller.heap.nextAddress ≤ q := Heap.allocationAddress_ge _ (by decide)
  let H1 := caller.heap.allocatedBytes (size * min) 8 budget
  have bufQ : Buffer H1 q (size * min) := alloc_buffer below bytesPos room
  have oldBelow : 0 < cap → p + size * cap ≤ q := fun pos => by
    have := ((buffer pos).2.1).belowNext (Nat.mul_pos positive pos) below
    dsimp only [Lanius.Address] at *; omega
  refine Grow.call inst.tryReserve rfl rfl ?_
  let vv := Value.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]
  let E0 : State := { caller with locals := [] }
  have f0 : E0.CellsWellFormed := formed
  have f1 := f0.bindLocal 0 vv
  let E := (E0.bindLocal 0 vv).bindLocal 1 (.signed .i32 min)
  change Grow P E _ _ _
  have fE : E.CellsWellFormed := f1.bindLocal _ _
  have l1 : E.local? 1 = some (.signed .i32 min) := local_bound f1 1 _
  have l0 : E.local? 0 = some vv := local_kept f1 _ (by decide) (local_bound f0 0 _)
  -- minimum_capacity <= value.reserved
  have cond1 := RunsExpr.binary (operation := .lessEqual) (program := P) (RunsExpr.local' l1)
    (RunsExpr.field' (j := 2) (RunsExpr.local' l0) rfl) (by decide) (eval_i32_le _ _ _)
  rw [show decide ((min : Int) ≤ cap) = false by simp; omega] at cond1
  refine Grow.guardSkip cond1 (Ext.refl fE) ?_
  -- minimum_capacity > capacity_limit()
  obtain ⟨E1, limitRun, fr1⟩ := capacity_limit_spec inst kind fE
  have cond2 := RunsExpr.binary (operation := .greater) (RunsExpr.local' l1)
    (show RunsExpr P E (.call g.capacityLimit []) _ E1 from limitRun) (by decide) (eval_i32_gt _ _ _)
  rw [show decide ((min : Int) > (capLimit size : Nat)) = false by simp; omega] at cond2
  refine Grow.guardSkip cond2 (Ext.ofPure fr1) ?_
  -- let size = size_of()
  obtain ⟨E2, sizeRun, fr2⟩ := size_of_spec target kind inst.sizeOf fr1.afterFormed
  refine Grow.letRun (show RunsExpr P E1 (.call g.sizeOf []) _ E2 from sizeRun) (Ext.ofPure fr2) ?_
  have fE2 := fr2.afterFormed
  let B2 := E2.bindLocal 2 (.unsigned .usize size)
  have fB2 : B2.CellsWellFormed := fE2.bindLocal _ _
  have b2_2 : B2.local? 2 = some (.unsigned .usize size) := local_bound fE2 2 _
  have b2_1 : B2.local? 1 = some (.signed .i32 min) :=
    local_kept fE2 _ (by decide) (fr2.localFound (fr1.localFound l1))
  have b2_0 : B2.local? 0 = some vv := local_kept fE2 _ (by decide) (fr2.localFound (fr1.localFound l0))
  have hB2 : B2.heap = caller.heap := fr2.heap.trans fr1.heap
  have vB2 : B2.i32ArrayViews = [] := (fr2.views.trans fr1.views).trans noViews
  have cond3 := RunsExpr.binary (operation := .equal) (program := P) (RunsExpr.local' b2_2)
    (RunsExpr.value' (.unsigned .usize 0)) (by decide) (eval_usize_eq _ _ _)
  rw [show (size == 0) = false by simp; omega] at cond3
  refine Grow.guardSkip cond3 (Ext.refl fB2) ?_
  -- let next = alloc(size * minimum_capacity, 8)
  have bytesRun : RunsExpr P B2 (.binary .multiply (.local 2) (.cast (.unsigned .usize) (.local 1)))
      (.unsigned .usize (size * min)) B2 :=
    RunsExpr.binary (RunsExpr.local' b2_2) (RunsExpr.cast' (RunsExpr.local' b2_1)
      (by rw [target]; exact cast_usize_of_i32 (by omega))) (by decide)
      (by rw [target]; exact eval_usize_mul (by omega))
  have allocRun := RunsExpr.allocAt (P := P) bytesRun (RunsExpr.value' (.unsigned .usize 8))
    (show consumeBudget B2.heap.remaining (size * min) = some budget by rw [hB2]; exact available)
  rw [hB2] at allocRun
  let A3 : State := { B2 with heap := H1 }
  refine Grow.letRun allocRun (Ext.heap fB2 H1) ?_
  have fA3 : A3.CellsWellFormed := fB2
  let B3 := A3.bindLocal 3 (.pointer q)
  have fB3 : B3.CellsWellFormed := fA3.bindLocal _ _
  have b3_3 : B3.local? 3 = some (.pointer q) := local_bound fA3 3 _
  have b3_2 : B3.local? 2 = some (.unsigned .usize size) := local_kept fA3 _ (by decide) b2_2
  have b3_1 : B3.local? 1 = some (.signed .i32 min) := local_kept fA3 _ (by decide) b2_1
  have b3_0 : B3.local? 0 = some vv := local_kept fA3 _ (by decide) b2_0
  have cond4 := RunsExpr.binary (operation := .equal) (program := P) (RunsExpr.local' b3_3)
    (RunsExpr.value' (.pointer 0)) (by decide) (eval_ptr_eq _ _ _)
  rw [show (q == 0) = false by simpa using Nat.ne_of_gt qPos] at cond4
  refine Grow.guardSkip cond4 (Ext.refl fB3) ?_
  -- the copy, then the return
  have cond5 := RunsExpr.binary (operation := .greater) (program := P)
    (RunsExpr.field' (j := 2) (RunsExpr.local' b3_0) rfl) (RunsExpr.value' (.signed .i32 0)) (by decide)
    (eval_i32_gt _ _ _)
  have finish : ∀ X : State, RunsStmt P B3 (.ifThenElse (.binary .greater (.field (.local 0) 2) (int 0))
        (.letLocal 4 (.slice T) (.call ids.fromStorage [.field (.local 0) 0, .field (.local 0) 2])
        (.letLocal 5 (.slice T) (.call ids.fromStorage [.local 3, .local 1])
        (.letLocal 6 i32Ty (int 0)
        (.sequence (copyLoop 6 0 4 5)
          (.expression (.dealloc (.field (.local 0) 0)
            (.binary .multiply (.local 2) (.cast (.unsigned .usize) (.field (.local 0) 2))) (usize 8)))))))
        .skip) .next X → Ext B3 X →
      Grown P T size ids.vec caller.heap p (size * cap) q min xs X.heap →
      Grow P B3 (.sequence (.ifThenElse (.binary .greater (.field (.local 0) 2) (int 0))
        (.letLocal 4 (.slice T) (.call ids.fromStorage [.field (.local 0) 0, .field (.local 0) 2])
        (.letLocal 5 (.slice T) (.call ids.fromStorage [.local 3, .local 1])
        (.letLocal 6 i32Ty (int 0)
        (.sequence (copyLoop 6 0 4 5)
          (.expression (.dealloc (.field (.local 0) 0)
            (.binary .multiply (.local 2) (.cast (.unsigned .usize) (.field (.local 0) 2))) (usize 8)))))))
        .skip)
        (.returnValue (some (.structValue ids.vec [.local 3, .field (.local 0) 1, .local 1]))))
        (.returned (some (.structure ids.vec [.pointer q, .signed .i32 xs.length, .signed .i32 min])))
        (Grown P T size ids.vec caller.heap p (size * cap) q min xs) := by
    intro X run ext grown
    have locals : X.locals = B3.locals := run.choose_spec.2
    have x3 := ext.cells.localFound locals 3 _ b3_3
    have x1 := ext.cells.localFound locals 1 _ b3_1
    have x0 := ext.cells.localFound locals 0 _ b3_0
    exact ⟨X, RunsStmt.sequenceNext run (RunsStmt.returnValue (RunsExprs.toRun (RunsExprs.three
      (RunsExpr.local' x3) (RunsExpr.field' (j := 1) (RunsExpr.local' x0) rfl) (RunsExpr.local' x1)))),
      ext, grown⟩
  by_cases empty : cap = 0
  · subst empty
    have nil : xs = [] := List.eq_nil_of_length_eq_zero (by omega)
    rw [show decide ((0 : Nat) > (0 : Int)) = false by decide] at cond5
    refine finish B3 (RunsStmt.ifThenElseFalse cond5 (RunsStmt.skip P B3)) (Ext.refl fB3) ?_
    refine ⟨⟨q, min, rfl, by omega, minBound, fun _ => bufQ, fun i inside => by subst nil; simp at inside⟩,
      Kept.afterAlloc _ _ _ _ _ _, Heap.allocatedBytes_below below (by decide),
      Heap.allocatedBytes_unique below unique (by decide), ?_, fun ap => ap.afterAlloc below _ _ _ (by decide)⟩
    show q + max (size * min) 1 = q + size * min
    rw [Nat.max_eq_left bytesPos]
  · have capPos : 0 < cap := Nat.pos_of_ne_zero empty
    rw [show decide ((cap : Int) > 0) = true by simp; omega] at cond5
    have apart := oldBelow capPos
    -- let from = typed_slice_from_storage(value.storage, value.reserved)
    obtain ⟨F4, fromRun, fr4⟩ := fromStorage_spec inst.vec kind fB3 capBound
      (fun _ => (buffer capPos).afterAlloc)
    have fromCall := callArgs (RunsExprs.two (RunsExpr.field' (j := 0) (RunsExpr.local' b3_0) rfl)
      (RunsExpr.field' (j := 2) (RunsExpr.local' b3_0) rfl)) fromRun
    have fF4 := fr4.afterFormed
    let B4 := F4.bindLocal 4 (.rawSlice T (viewAddr T size p cap) cap)
    have fB4 : B4.CellsWellFormed := fF4.bindLocal _ _
    have hB4 : B4.heap = H1 := fr4.heap
    -- let to = typed_slice_from_storage(next, minimum_capacity)
    obtain ⟨F5, toRun, fr5⟩ := fromStorage_spec inst.vec kind fB4 minBound
      (fun _ => by rw [hB4]; exact bufQ)
    have toCall := callArgs (RunsExprs.two (RunsExpr.local' (local_kept fF4 _ (by decide) (fr4.localFound b3_3)))
      (RunsExpr.local' (local_kept fF4 _ (by decide) (fr4.localFound b3_1)))) toRun
    have fF5 := fr5.afterFormed
    let B5 := F5.bindLocal 5 (.rawSlice T (viewAddr T size q min) min)
    have fB5 : B5.CellsWellFormed := fF5.bindLocal _ _
    have hB5 : B5.heap = H1 := fr5.heap.trans hB4
    have keep5 : ∀ (id : VarId) (v : Value), id ≠ 4 → id ≠ 5 → B3.local? id = some v → B5.local? id = some v :=
      fun id v n4 n5 found => local_kept fF5 _ (Ne.symm n5)
        (fr5.localFound (local_kept fF4 _ (Ne.symm n4) (fr4.localFound found)))
    have b5_0 := keep5 0 vv (by decide) (by decide) b3_0
    have b5_2 := keep5 2 _ (by decide) (by decide) b3_2
    have b5_4 : B5.local? 4 = some (.rawSlice T (viewAddr T size p cap) cap) :=
      local_kept fF5 _ (by decide) (fr5.localFound (local_bound fF4 4 _))
    have b5_5 : B5.local? 5 = some (.rawSlice T (viewAddr T size q min) min) := local_bound fF5 5 _
    have vB5 : B5.i32ArrayViews = [] := (fr5.views.trans fr4.views).trans vB2
    -- the copy loop
    obtain ⟨h2, loopRun, effect, copied⟩ := copy_loop_spec target kind fB5 (idx := 6) (vec := 0) (src := 4)
      (dst := 5) (by decide) (by decide) (by decide) b5_0 b5_4 b5_5 lenLe (by omega) minBound
      (fun i inside other within => reads i inside other (ReadsWithin.trans
        (by rw [hB5]; exact ReadsWithin.afterAlloc _ _ _ _ _ _) within))
      (fun _ => by rw [hB5]; exact bufQ) (Or.inl apart) stores vB5
      (by rw [hB5]; exact Heap.allocatedBytes_unique below unique (by decide))
    rw [hB5] at effect
    -- dealloc(value.storage, size * value.reserved, 8)
    have bufP2 : Buffer h2 p (size * cap) := ((buffer capPos).afterAlloc).afterWrite effect
    obtain ⟨h3, freedRun, freed⟩ := dealloc_buffer bufP2 effect.unique
    let W : State := { B5 with heap := h2 }
    have fW : W.CellsWellFormed := fB5
    let C6 := W.bindLocal 6 (.signed .i32 xs.length)
    have c6_0 : C6.local? 0 = some vv := local_kept fW _ (by decide) b5_0
    have c6_2 : C6.local? 2 = some (.unsigned .usize size) := local_kept fW _ (by decide) b5_2
    have deallocRun := RunsExpr.dealloc' (P := P) (S := C6) (RunsExprs.three
      (RunsExpr.field' (j := 0) (RunsExpr.local' c6_0) rfl)
      (RunsExpr.binary (operation := .multiply) (RunsExpr.local' c6_2) (RunsExpr.cast' (RunsExpr.field' (j := 2) (RunsExpr.local' c6_0) rfl)
        (by rw [target]; exact cast_usize_of_i32 (by omega))) (by decide)
        (by rw [target]; exact eval_usize_mul (a := size) (b := cap) (by
          have := Nat.mul_le_mul_left size (Nat.le_of_lt grows); omega)))
      (RunsExpr.value' (.unsigned .usize 8))) vB5 freedRun
    have inner : RunsStmt P B5 (.letLocal 6 i32Ty (int 0) (.sequence (copyLoop 6 0 4 5)
          (.expression (.dealloc (.field (.local 0) 0)
            (.binary .multiply (.local 2) (.cast (.unsigned .usize) (.field (.local 0) 2))) (usize 8)))))
        .next (restoreLocals B5 { C6 with heap := h3 }) :=
      RunsStmt.letLocal (RunsExpr.value' _) (RunsStmt.sequenceNext loopRun (RunsStmt.expression deallocRun))
    have extInner : Ext B5 (restoreLocals B5 { C6 with heap := h3 }) :=
      (((Ext.heap fB5 h2).trans (Ext.bindLocal fW 6 _)).trans (Ext.heap (fW.bindLocal _ _) h3)).restore B5
    have mid := RunsStmt.letLocal (type := .slice T) toCall inner
    have outer := RunsStmt.letLocal (type := .slice T) fromCall mid
    refine finish _ (RunsStmt.ifThenElseTrue cond5 outer)
      ((((Ext.ofPure fr4).trans (Ext.bindLocal fF4 4 _)).trans
        ((((Ext.ofPure fr5).trans (Ext.bindLocal fF5 5 _)).trans extInner).restore F5)).restore F4) ?_
    show Grown P T size ids.vec caller.heap p (size * cap) q min xs h3
    refine ⟨⟨q, min, rfl, by omega, minBound, fun _ => freed.buffer bytesPos (Or.inr apart) (bufQ.afterWrite effect),
      fun i inside other within => copied i inside other (ReadsWithin.trans (freed.reads (Or.inr ?_)) within)⟩,
      ((Kept.afterAlloc caller.heap p (size * cap) (size * min) 8 budget).afterFreshWrite below fresh effect).afterFree
        freed,
      freed.below (effect.below (Heap.allocatedBytes_below below (by decide))), freed.unique effect.unique, ?_,
      fun ap => freed.apart (HeapApart.ofWrite effect (ap.afterAlloc below _ _ _ (by decide)))⟩
    · have := slot_inside (T := T) (size := size) (p := q) (show i < min by omega); omega
    · rw [freed.next, effect.frontier]
      show q + max (size * min) 1 = q + size * min
      rw [Nat.max_eq_left bytesPos]

#print axioms tryReserve_grow_spec

end Lanius.Std
