import Lanius.Std.SetScan

/-! # `count_where` and `reserved_for`

The private helpers of the set algebra functions. `count_where(from, other,
present)` counts the items `a` of `from` with `contains(other, a) == present`;
`reserved_for(count)` forwards to `try_with_capacity`. -/

namespace Lanius.Std

open Lanius Lanius.Core Lanius.Semantics Lanius.Memory

variable {P : Program} {T : Ty} {ids : VecIds} {g : GrowIds} {mo : MoreIds} {size : Nat}

/-- The items of `xs` whose membership in `ys` is `present`. -/
def whereIn (eqv : Value → Value → Bool) (ys : List Value) (present : Bool) (xs : List Value) : List Value :=
  xs.filter (fun a => ys.any (eqv · a) == present)

/-- `count_where`, with locals 0 `from`, 1 `other`, 2 `present`, 3 `count`, 4 `index`. -/
def setCountWhereFn (sid : TypeId) (f sl sc atf : FunctionId) : Function where
  id := f
  parameters := [(0, setTy sid), (1, setTy sid), (2, boolTy)]
  returnType := i32Ty
  body := some <|
    .letLocal 3 i32Ty (int 0)
    (.letLocal 4 i32Ty (int 0)
    (.sequence
      (.whileLoop (.binary .less (.local 4) (.call sl [.local 0]))
        (.sequence
          (.ifThenElse (.binary .equal (.call sc [.local 1, .call atf [setItems, .local 4]]) (.local 2))
            (increment 3) .skip)
          (increment 4)))
      (.returnValue (some (.local 3)))))

/-- `fn reserved_for<T>(count: i32) -> Vec<T> { return std::vec::try_with_capacity(count); }` -/
def setReservedForFn (ids : VecIds) (mo : MoreIds) (f : FunctionId) : Function where
  id := f
  parameters := [(0, i32Ty)]
  returnType := vecTy ids
  body := some (.returnValue (some (.call mo.tryWithCapacity [.local 0])))

theorem eval_bool_eq (t : Target) (a b : Bool) :
    evalBinaryValue t .equal (.boolean a) (.boolean b) = .ok (.boolean (a == b)) := by
  cases a <;> cases b <;> simp [evalBinaryValue, scalarEqual]

theorem filter_take_succ (p : Value → Bool) (xs : List Value) {k : Nat} (kn : k < xs.length) :
    ((xs.take (k + 1)).filter p).length = ((xs.take k).filter p).length + (if p xs[k] then 1 else 0) := by
  rw [List.take_succ, List.getElem?_eq_getElem kn, List.filter_append, List.length_append]
  cases h : p xs[k] <;> simp [h]

/-- `x += 1` on a counter cell created after `E`. -/
theorem bump (target : P.target = Target.x86_64) {E a : State} (fE : E.CellsWellFormed)
    (frame : FreshCellFrame E a) {id : VarId} {c : CellId} {k : Nat} (small : k + 1 < 2 ^ 31)
    (cell : a.cellId? id = some c) (fresh : E.nextCell ≤ c) (found : a.local? id = some (.signed .i32 (Int.ofNat k))) :
    ∃ a', RunsStmt P a (increment id) .next a' ∧ FreshCellFrame E a' ∧ a'.locals = a.locals ∧ a'.heap = a.heap ∧
      a'.world = a.world ∧ a'.i32ArrayViews = a.i32ArrayViews ∧
      a'.local? id = some (.signed .i32 (Int.ofNat (k + 1))) ∧
      ∀ id' v, a.cellId? id' ≠ some c → a.local? id' = some v → a'.local? id' = some v := by
  obtain ⟨a', assigned⟩ := assignLocal_exists a id _ (.signed .i32 (Int.ofNat (k + 1))) c cell found
  have cellA := assignLocal_assignCell id c _ cell assigned
  obtain ⟨frame', locals, heap, world, views⟩ :=
    FreshCellFrame.assignFresh fE (FreshCellFrame.after_cellsWellFormed fE frame) frame fresh cellA
  exact ⟨a', increment_run target small cell found assigned, frame', locals, heap, world, views,
    assignLocal_finds_assigned id c _ cell assigned,
    fun id' v ne lf => assignCell_preserves_other_local_of_cellId id' c _ cellA lf ne⟩

theorem setCountWhere_spec (inst : VecInstance P T ids) (kind : ElemKind P T size) {sid : TypeId}
    {f sl sc vc indexOf eq atf asl pf : FunctionId}
    (found : P.function? f = some (setCountWhereFn sid f sl sc atf))
    (slFound : P.function? sl = some (setForwardFn sid sl ids.len i32Ty))
    (scFound : P.function? sc = some (setContainsFn T sid sc vc))
    (vcFound : P.function? vc = some (vecContainsFn ids T vc indexOf))
    (indexFound : P.function? indexOf = some (indexOfFn ids T indexOf eq))
    (atFound : P.function? atf = some (atFn ids T atf asl))
    (aslFound : P.function? asl = some (asSliceFn ids T asl pf))
    (pfFound : P.function? pf = some (prefixFromStorageFn T pf ids.fromStorage))
    {eqv : Value → Value → Bool} {vals : List Value} (eqSpec : EqSpec P eq eqv vals)
    {caller : State} (formed : caller.CellsWellFormed) {xs ys : List Value} {p cap : Nat} {w : Value}
    (repL : VecRep P T size ids.vec caller.heap
      (.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]) xs)
    (repR : VecRep P T size ids.vec caller.heap w ys)
    (subL : ∀ z ∈ xs, z ∈ vals) (subR : ∀ z ∈ ys, z ∈ vals) (disjoint : HeapBlocksDisjoint caller.heap)
    (present : Bool) :
    ∃ after, RunsExpr P caller (.call f
        ([Value.structure sid [.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]],
          .structure sid [w], .boolean present].map Expr.value))
      (.signed .i32 (whereIn eqv ys present xs).length) after ∧ PureFrame caller after := by
  obtain ⟨_, lenLe, capBound, _, _⟩ := repL.fields
  refine PureRun.call found rfl rfl formed ?_
  let vv := Value.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]
  let E0 : State := { caller with locals := [] }
  have f0 : E0.CellsWellFormed := formed
  have f1 := f0.bindLocal 0 (.structure sid [vv])
  have f2 := f1.bindLocal 1 (.structure sid [w])
  let E := ((E0.bindLocal 0 (.structure sid [vv])).bindLocal 1 (.structure sid [w])).bindLocal 2 (.boolean present)
  change PureRun P E (.letLocal 3 i32Ty (.value (.signed .i32 0)) (.letLocal 4 i32Ty (.value (.signed .i32 0)) _)) _
  have fE : E.CellsWellFormed := f2.bindLocal _ _
  have l2 : E.local? 2 = some (.boolean present) := local_bound f2 2 _
  have l1 : E.local? 1 = some (.structure sid [w]) := local_kept f2 _ (by decide) (local_bound f1 1 _)
  have l0 : E.local? 0 = some (.structure sid [vv]) :=
    local_kept f2 _ (by decide) (local_kept f1 _ (by decide) (local_bound f0 0 _))
  refine PureRun.letValue fE ?_
  have fE3 : (E.bindLocal 3 (.signed .i32 0)).CellsWellFormed := fE.bindLocal _ _
  let E4 := (E.bindLocal 3 (.signed .i32 0)).bindLocal 4 (.signed .i32 0)
  let n := xs.length
  have nBound : n < 2 ^ 31 := by omega
  let pred : Value → Bool := fun a => ys.any (eqv · a) == present
  let Frame : State → Prop := fun s => FreshCellFrame E s ∧ s.locals = E4.locals ∧ s.heap = E.heap ∧
    s.world = E.world ∧ s.i32ArrayViews = E.i32ArrayViews ∧ s.CellsWellFormed
  have frameLocals : ∀ s, Frame s → s.local? 0 = some (.structure sid [vv]) ∧ s.local? 1 = some (.structure sid [w]) ∧
      s.local? 2 = some (.boolean present) :=
    fun s fr => ⟨local_above2 fr.1 fr.2.1 (by decide) (by decide) l0, local_above2 fr.1 fr.2.1 (by decide) (by decide) l1,
      local_above2 fr.1 fr.2.1 (by decide) (by decide) l2⟩
  have framePure : ∀ s s', Frame s → PureFrame s s' → Frame s' := fun s s' fr pure =>
    ⟨fr.1.trans pure.cells, pure.locals.trans fr.2.1, pure.heap.trans fr.2.2.1, pure.world.trans fr.2.2.2.1,
      pure.views.trans fr.2.2.2.2.1, pure.afterFormed⟩
  have cell3 : ∀ s, Frame s → s.cellId? 3 = some E.nextCell := fun s fr => by
    simp [State.cellId?, fr.2.1, E4, State.bindLocal, State.bindCell]
  have cell4 : ∀ s, Frame s → s.cellId? 4 = some (E.nextCell + 1) := fun s fr => by
    simp [State.cellId?, fr.2.1, E4, State.bindLocal, State.bindCell]
  -- after a bump, the frame and the cells of the other locals stay
  have bumped : ∀ s s', Frame s → FreshCellFrame E s' → s'.locals = s.locals → s'.heap = s.heap →
      s'.world = s.world → s'.i32ArrayViews = s.i32ArrayViews → Frame s' := fun s s' fr cells locals heap world views =>
    ⟨cells, locals.trans fr.2.1, heap.trans fr.2.2.1, world.trans fr.2.2.2.1, views.trans fr.2.2.2.2.1,
      FreshCellFrame.after_cellsWellFormed fE cells⟩
  have condAt : ∀ s (k : Nat), Frame s → s.local? 4 = some (.signed .i32 k) → ∃ s',
      RunsExpr P s (.binary .less (.local 4) (.call sl [.local 0])) (.boolean (decide ((k : Int) < n))) s' ∧
        PureFrame s s' := fun s k fr idx => by
    obtain ⟨s', lenRun, pure⟩ := setLen_spec inst slFound fr.2.2.2.2.2 (by rw [fr.2.2.1]; exact repL)
    exact ⟨s', RunsExpr.binary (RunsExpr.local' idx)
      (callArgs (RunsExprs.one (RunsExpr.local' (frameLocals s fr).1)) lenRun) (by decide) (eval_i32_lt _ _ _), pure⟩
  let body : Stmt := .sequence
    (.ifThenElse (.binary .equal (.call sc [.local 1, .call atf [setItems, .local 4]]) (.local 2)) (increment 3) .skip)
    (increment 4)
  let measure : State → Nat := fun s => n - counter 4 s
  let oracle : TotalWhileOracle measure P (.binary .less (.local 4) (.call sl [.local 0])) body := {
    Inv := fun s => ∃ k : Nat, k ≤ n ∧ Frame s ∧ s.local? 4 = some (.signed .i32 k) ∧
      s.local? 3 = some (.signed .i32 ((xs.take k).filter pred).length)
    Done := fun c s => Frame s ∧ c = .next ∧ s.local? 3 = some (.signed .i32 (xs.filter pred).length)
    step := by
      intro s invariant
      obtain ⟨k, kle, fr, idx, cnt⟩ := invariant
      obtain ⟨c1, cond, pure1⟩ := condAt s k fr idx
      have fr1 := framePure s c1 fr pure1
      have idx1 := pure1.localFound idx
      by_cases last : k = n
      · subst last
        rw [show decide (((xs.length : Nat) : Int) < xs.length) = false by simp] at cond
        obtain ⟨threshold, stable, _⟩ := cond
        refine Or.inl ⟨threshold, c1, stable, fr1, rfl, ?_⟩
        have whole : xs.take xs.length = xs := List.take_length
        rw [← whole]; exact pure1.localFound cnt
      have kn : k < n := by omega
      rw [show decide ((k : Int) < n) = true by simp; omega] at cond
      obtain ⟨condThreshold, condStable, _⟩ := cond
      right
      obtain ⟨c1_0, c1_1, c1_2⟩ := frameLocals c1 fr1
      -- at(from.items, index)
      obtain ⟨a1, atRun, pa1⟩ := at_spec inst kind atFound aslFound pfFound fr1.2.2.2.2.2
        (by rw [fr1.2.2.1]; exact repL) (by rw [fr1.2.2.1]; exact disjoint) kn
      have atCall := callArgs (RunsExprs.two (RunsExpr.field' (j := 0) (RunsExpr.local' c1_0) rfl)
        (RunsExpr.local' idx1)) atRun
      have fa1 := framePure c1 a1 fr1 pa1
      -- contains(other, item) == present
      obtain ⟨a2, cRun, pa2⟩ := setContains_spec inst kind scFound vcFound indexFound eqSpec fa1.2.2.2.2.2
        (by rw [fa1.2.2.1]; exact repR) (subL _ (List.getElem_mem _)) subR
      have fa2 := framePure a1 a2 fa1 pa2
      have test := RunsExpr.binary (operation := .equal) (RunsExpr.callArguments
        (RunsExprs.cons (RunsExpr.local' c1_1) (RunsExprs.cons atCall RunsExprs.nil)) cRun)
        (RunsExpr.local' (frameLocals a2 fa2).2.2) (by decide) (eval_bool_eq _ _ _)
      have idx2 := pa2.localFound (pa1.localFound idx1)
      have cnt2 := pa2.localFound (pa1.localFound (pure1.localFound cnt))
      let c := ((xs.take k).filter pred).length
      have cBound : c ≤ k := by
        have : ((xs.take k).filter pred).length ≤ (xs.take k).length := List.Sublist.length_le List.filter_sublist
        rw [List.length_take] at this; omega
      have step := filter_take_succ pred xs kn
      have advance : ∀ a3 : State, Frame a3 → a3.local? 4 = some (.signed .i32 (Int.ofNat k)) →
          a3.local? 3 = some (.signed .i32 ((xs.take (k + 1)).filter pred).length) →
          ∃ a4, RunsStmt P a3 (increment 4) .next a4 ∧ measure a4 < measure s ∧ (∃ k' : Nat, k' ≤ n ∧ Frame a4 ∧
            a4.local? 4 = some (.signed .i32 k') ∧ a4.local? 3 = some (.signed .i32 ((xs.take k').filter pred).length)) :=
        fun a3 fr3 idx3 cnt3 => by
          obtain ⟨a4, run4, cells4, locals4, heap4, world4, views4, idx4, keep4⟩ :=
            bump inst.target fE fr3.1 (by omega) (cell4 a3 fr3) (Nat.le_succ _) idx3
          have fr4 := bumped a3 a4 fr3 cells4 locals4 heap4 world4 views4
          refine ⟨a4, run4, ?_, k + 1, kn, fr4, idx4, keep4 3 _ ?_ cnt3⟩
          · show n - counter 4 a4 < n - counter 4 s
            rw [counter_eq idx4, counter_eq idx]; omega
          · rw [cell3 a3 fr3]; intro h; exact Nat.ne_of_lt (Nat.lt_succ_self _) (Option.some.inj h)
      cases good : pred xs[k] with
      | true =>
          have isTrue : (ys.any (eqv · xs[k]) == present) = true := good
          rw [isTrue] at test
          obtain ⟨a3, run3, cells3, locals3, heap3, world3, views3, cnt3, keep3⟩ :=
            bump inst.target fE fa2.1 (by omega) (cell3 a2 fa2) (Nat.le_refl _) cnt2
          have fr3 := bumped a2 a3 fa2 cells3 locals3 heap3 world3 views3
          have idx3 := keep3 4 _ (by rw [cell4 a2 fa2]; intro h; exact Nat.ne_of_gt (Nat.lt_succ_self _) (Option.some.inj h)) idx2
          rw [good] at step
          obtain ⟨a4, run4, less, inv4⟩ := advance a3 fr3 idx3 (by rw [step]; exact cnt3)
          obtain ⟨bodyThreshold, bodyStable, _⟩ : RunsStmt P c1 body .next a4 :=
            RunsStmt.sequenceNext (RunsStmt.ifThenElseTrue test run3) run4
          exact ⟨condThreshold, bodyThreshold, c1, .next, a4, condStable, bodyStable,
            fun h => absurd rfl h.1, fun _ => ⟨less, inv4⟩⟩
      | false =>
          have isFalse : (ys.any (eqv · xs[k]) == present) = false := good
          rw [isFalse] at test
          rw [good] at step
          obtain ⟨a4, run4, less, inv4⟩ := advance a2 fa2 idx2 (by rw [step]; exact cnt2)
          obtain ⟨bodyThreshold, bodyStable, _⟩ : RunsStmt P c1 body .next a4 :=
            RunsStmt.sequenceNext (RunsStmt.ifThenElseFalse test (RunsStmt.skip P a2)) run4
          exact ⟨condThreshold, bodyThreshold, c1, .next, a4, condStable, bodyStable,
            fun h => absurd rfl h.1, fun _ => ⟨less, inv4⟩⟩ }
  have fE4 : E4.CellsWellFormed := fE3.bindLocal _ _
  have entryFrame : Frame E4 := ⟨(FreshCellFrame.bindLocal E 3 _).trans (FreshCellFrame.bindLocal _ 4 _),
    rfl, rfl, rfl, rfl, fE4⟩
  have e3 : E4.local? 3 = some (.signed .i32 0) := local_kept fE3 _ (by decide) (local_bound fE 3 _)
  obtain ⟨threshold, completion, after, loopStable, done⟩ :=
    executeTotalWhile measure P _ _ oracle E4 ⟨0, Nat.zero_le _, entryFrame, local_bound fE3 4 _, e3⟩
  obtain ⟨frA, rfl, cntA⟩ := done
  have loopRun : RunsStmt P E4 _ .next after := ⟨threshold, loopStable, frA.2.1⟩
  have seqRun := RunsStmt.sequenceNext loopRun (RunsStmt.returnValue (RunsExpr.local' cntA))
  refine ⟨restoreLocals (E.bindLocal 3 (.signed .i32 0)) after,
    RunsStmt.letLocal (RunsExpr.value' _) seqRun, ?_, frA.2.2.1, frA.2.2.2.1, frA.2.2.2.2.1⟩
  obtain ⟨e, c, nx, fr⟩ := frA.1
  exact ⟨e, c, nx, fr⟩

/-- `reserved_for(n)` with `n > 0` and the allocation succeeding. -/
theorem setReservedFor_spec (inst : MoreInstance P T ids g mo) (kind : ElemKind P T size) {f : FunctionId}
    (found : P.function? f = some (setReservedForFn ids mo f)) {caller : State} (formed : caller.CellsWellFormed)
    {n : Nat} (positive : 0 < n) (fits : size * n ≤ 2147483647)
    {budget : Option Nat} (available : consumeBudget caller.heap.remaining (size * n) = some budget)
    (room : caller.heap.allocationAddress 8 + size * n < 2 ^ 64)
    (below : HeapBlocksBelowNext caller.heap) (unique : HeapBlockBasesUnique caller.heap)
    (noViews : caller.i32ArrayViews = []) :
    ∃ after, RunsExpr P caller (.call f ([Value.signed .i32 n].map Expr.value))
      (.structure ids.vec [.pointer (caller.heap.allocationAddress 8), .signed .i32 0, .signed .i32 n])
      after ∧ FreshCellFrame caller after ∧ after.world = caller.world ∧
      after.i32ArrayViews = caller.i32ArrayViews ∧
      Grown P T size ids.vec caller.heap 0 0 (caller.heap.allocationAddress 8) n [] after.heap := by
  let E := ({ caller with locals := [] } : State).bindLocal 0 (.signed .i32 n)
  have f0 : ({ caller with locals := [] } : State).CellsWellFormed := formed
  have fE : E.CellsWellFormed := f0.bindLocal _ _
  have l0 : E.local? 0 = some (.signed .i32 n) := local_bound f0 0 _
  obtain ⟨after, run, cells, world, views, grown⟩ :=
    tryWithCapacity_spec inst kind (caller := E) fE positive fits available room below unique noViews
  exact Grow.call (vs := [.signed .i32 n]) (bindings := [(0, .signed .i32 n)])
    (Q := fun H => Grown P T size ids.vec caller.heap 0 0 (caller.heap.allocationAddress 8) n [] H) found rfl rfl
    ⟨after, RunsStmt.returnValue (callArgs (RunsExprs.one (RunsExpr.local' l0)) run), ⟨fE, cells, world, views⟩,
      grown⟩

/-- `reserved_for(n)` with `n ≤ 0` returns the empty vector. -/
theorem setReservedFor_empty_spec (inst : MoreInstance P T ids g mo) {f : FunctionId}
    (found : P.function? f = some (setReservedForFn ids mo f)) {caller : State} (formed : caller.CellsWellFormed)
    {n : Int} (nonpositive : n ≤ 0) :
    ∃ after, RunsExpr P caller (.call f ([Value.signed .i32 n].map Expr.value))
      (.structure ids.vec [.pointer 0, .signed .i32 0, .signed .i32 0]) after ∧ PureFrame caller after := by
  refine PureRun.call found rfl rfl formed ?_
  have f0 : ({ caller with locals := [] } : State).CellsWellFormed := formed
  have fE := f0.bindLocal 0 (.signed .i32 n)
  exact PureRun.retCall (RunsExprs.one (RunsExpr.local' (local_bound f0 0 _)))
    (tryWithCapacity_empty_spec inst fE nonpositive)

#print axioms setCountWhere_spec
#print axioms setReservedFor_spec
#print axioms setReservedFor_empty_spec

end Lanius.Std
