import Lanius.Std.VecPrefix

/-! # `is_subset` and `is_disjoint`

Both walk `left` with `at` and ask `contains(right, item)`, returning `false`
at the first item whose answer is not the wanted one (`true` for
`is_subset`, `false` for `is_disjoint`). -/

namespace Lanius.Std

open Lanius Lanius.Core Lanius.Semantics Lanius.Memory

variable {P : Program} {T : Ty} {ids : VecIds} {size : Nat}

/-- The early-return test: `!contains(...)` for `is_subset`, `contains(...)`
for `is_disjoint`. -/
def scanTest : Bool → Expr → Expr
  | true, e => .unary .logicalNot e
  | false, e => e

/-- `let index = 0; while (index < len(left)) { if (test) { return false; }
index += 1; } return true;` with `left`, `right`, `index` the locals 0 to 2. -/
def setScanFn (sid : TypeId) (f sl sc atf : FunctionId) (want : Bool) : Function where
  id := f
  parameters := [(0, setTy sid), (1, setTy sid)]
  returnType := boolTy
  body := some <|
    .letLocal 2 i32Ty (int 0)
    (.sequence
      (.whileLoop (.binary .less (.local 2) (.call sl [.local 0]))
        (.sequence
          (.ifThenElse (scanTest want (.call sc [.local 1, .call atf [setItems, .local 2]]))
            (.returnValue (some (.value (.boolean false)))) .skip)
          (increment 2)))
      (.returnValue (some (.value (.boolean true)))))

/-- `pub fn is_subset<T>(left: Set<T>, right: Set<T>) -> bool` -/
abbrev setIsSubsetFn (sid : TypeId) (f sl sc atf : FunctionId) : Function := setScanFn sid f sl sc atf true

/-- `pub fn is_disjoint<T>(left: Set<T>, right: Set<T>) -> bool` -/
abbrev setIsDisjointFn (sid : TypeId) (f sl sc atf : FunctionId) : Function := setScanFn sid f sl sc atf false

theorem scanTest_run {s s' : State} {e : Expr} {c : Bool} (want : Bool) (run : RunsExpr P s e (.boolean c) s') :
    RunsExpr P s (scanTest want e) (.boolean (!(c == want))) s' := by
  cases want with
  | false =>
      have same : (!(c == false)) = c := by cases c <;> rfl
      rw [same]; exact run
  | true =>
      have flip : (!(c == true)) = !c := by cases c <;> rfl
      rw [flip]; exact RunsExpr.unary (operator := .logicalNot) run rfl

/-- `is_subset` (`want = true`) and `is_disjoint` (`want = false`): every
item of `left` has `contains(right, item) = want`. -/
theorem setScan_spec (inst : VecInstance P T ids) (kind : ElemKind P T size) {sid : TypeId}
    {f sl sc vc indexOf eq atf asl pf : FunctionId} (want : Bool)
    (found : P.function? f = some (setScanFn sid f sl sc atf want))
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
    (subL : ∀ z ∈ xs, z ∈ vals) (subR : ∀ z ∈ ys, z ∈ vals) (disjoint : HeapBlocksDisjoint caller.heap) :
    ∃ after, RunsExpr P caller (.call f
        ([Value.structure sid [.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]],
          .structure sid [w]].map Expr.value))
      (.boolean (xs.all (fun a => ys.any (eqv · a) == want))) after ∧ PureFrame caller after := by
  obtain ⟨_, lenLe, capBound, _, _⟩ := repL.fields
  refine PureRun.call found rfl rfl formed ?_
  let vv := Value.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]
  let E0 : State := { caller with locals := [] }
  have f0 : E0.CellsWellFormed := formed
  have f1 := f0.bindLocal 0 (.structure sid [vv])
  let E := (E0.bindLocal 0 (.structure sid [vv])).bindLocal 1 (.structure sid [w])
  change PureRun P E (.letLocal 2 i32Ty (.value (.signed .i32 0)) _) _
  have fE : E.CellsWellFormed := f1.bindLocal _ _
  have l1 : E.local? 1 = some (.structure sid [w]) := local_bound f1 1 _
  have l0 : E.local? 0 = some (.structure sid [vv]) := local_kept f1 _ (by decide) (local_bound f0 0 _)
  refine PureRun.letValue fE ?_
  let n := xs.length
  let Frame : State → Prop := fun s => FreshCellFrame E s ∧
    s.locals = (E.bindLocal 2 (.signed .i32 0)).locals ∧ s.heap = E.heap ∧ s.world = E.world ∧
    s.i32ArrayViews = E.i32ArrayViews ∧ s.CellsWellFormed
  let Good : Nat → Prop := fun i => ∀ inside : i < n, (ys.any (eqv · xs[i]) == want) = true
  have frameLocals : ∀ s, Frame s → s.local? 0 = some (.structure sid [vv]) ∧ s.local? 1 = some (.structure sid [w]) :=
    fun s fr => ⟨local_above fr.1 fr.2.1 (by decide) l0, local_above fr.1 fr.2.1 (by decide) l1⟩
  have framePure : ∀ s s', Frame s → PureFrame s s' → Frame s' := fun s s' fr pure =>
    ⟨fr.1.trans pure.cells, pure.locals.trans fr.2.1, pure.heap.trans fr.2.2.1, pure.world.trans fr.2.2.2.1,
      pure.views.trans fr.2.2.2.2.1, pure.afterFormed⟩
  have cellAt : ∀ s, Frame s → s.cellId? 2 = some E.nextCell := fun s fr => by
    simp [State.cellId?, fr.2.1, State.bindLocal, State.bindCell]
  have condAt : ∀ s (k : Nat), Frame s → s.local? 2 = some (.signed .i32 k) → ∃ s',
      RunsExpr P s (.binary .less (.local 2) (.call sl [.local 0])) (.boolean (decide ((k : Int) < n))) s' ∧
        PureFrame s s' := fun s k fr idx => by
    obtain ⟨s', lenRun, pure⟩ := setLen_spec inst slFound fr.2.2.2.2.2 (by rw [fr.2.2.1]; exact repL)
    exact ⟨s', RunsExpr.binary (RunsExpr.local' idx)
      (callArgs (RunsExprs.one (RunsExpr.local' (frameLocals s fr).1)) lenRun) (by decide) (eval_i32_lt _ _ _), pure⟩
  let measure : State → Nat := fun s => n - counter 2 s
  let oracle : TotalWhileOracle measure P (.binary .less (.local 2) (.call sl [.local 0]))
      (.sequence
        (.ifThenElse (scanTest want (.call sc [.local 1, .call atf [setItems, .local 2]]))
          (.returnValue (some (.value (.boolean false)))) .skip)
        (increment 2)) := {
    Inv := fun s => ∃ k, k ≤ n ∧ Frame s ∧ s.local? 2 = some (.signed .i32 k) ∧ ∀ i, i < k → Good i
    Done := fun c s => Frame s ∧ ((c = .next ∧ ∀ i, i < n → Good i) ∨
      (∃ k, ∃ inside : k < n, c = .returned (some (.boolean false)) ∧ (ys.any (eqv · xs[k]) == want) = false))
    step := by
      intro s invariant
      obtain ⟨k, kle, fr, idx, before⟩ := invariant
      obtain ⟨c1, cond, pure1⟩ := condAt s k fr idx
      have fr1 := framePure s c1 fr pure1
      have idx1 := pure1.localFound idx
      by_cases last : k = n
      · subst last
        rw [show decide (((xs.length : Nat) : Int) < xs.length) = false by simp] at cond
        obtain ⟨threshold, stable, _⟩ := cond
        exact Or.inl ⟨threshold, c1, stable, fr1, Or.inl ⟨rfl, before⟩⟩
      have kn : k < n := by omega
      rw [show decide ((k : Int) < n) = true by simp; omega] at cond
      obtain ⟨condThreshold, condStable, _⟩ := cond
      right
      obtain ⟨c1_0, c1_1⟩ := frameLocals c1 fr1
      -- at(left.items, index)
      obtain ⟨a1, atRun, pa1⟩ := at_spec inst kind atFound aslFound pfFound fr1.2.2.2.2.2
        (by rw [fr1.2.2.1]; exact repL) (by rw [fr1.2.2.1]; exact disjoint) kn
      have atCall := callArgs (RunsExprs.two (RunsExpr.field' (j := 0) (RunsExpr.local' c1_0) rfl)
        (RunsExpr.local' idx1)) atRun
      have fa1 := framePure c1 a1 fr1 pa1
      -- contains(right, item)
      obtain ⟨a2, cRun, pa2⟩ := setContains_spec inst kind scFound vcFound indexFound eqSpec fa1.2.2.2.2.2
        (by rw [fa1.2.2.1]; exact repR) (subL _ (List.getElem_mem _)) subR
      have fa2 := framePure a1 a2 fa1 pa2
      have test := scanTest_run want (RunsExpr.callArguments
        (RunsExprs.cons (RunsExpr.local' c1_1) (RunsExprs.cons atCall RunsExprs.nil)) cRun)
      have idx2 := pa2.localFound (pa1.localFound idx1)
      cases good : (ys.any (eqv · xs[k]) == want) with
      | false =>
          rw [good] at test
          obtain ⟨bodyThreshold, bodyStable, _⟩ : RunsStmt P c1 _ (.returned (some (.boolean false))) a2 :=
            RunsStmt.sequenceCompleted (RunsStmt.ifThenElseTrue test
              (RunsStmt.returnValue (RunsExpr.value' (.boolean false)))) (by intro h; cases h) (increment 2)
          refine ⟨condThreshold, bodyThreshold, c1, _, a2, condStable, bodyStable,
            fun _ => ⟨fa2, Or.inr ⟨k, kn, rfl, good⟩⟩, fun h => ?_⟩
          rcases h with h | h <;> cases h
      | true =>
          rw [good] at test
          have cell2 := cellAt a2 fa2
          obtain ⟨a3, assigned⟩ := assignLocal_exists a2 2 _ (.signed .i32 (Int.ofNat (k + 1))) _ cell2 idx2
          obtain ⟨bodyThreshold, bodyStable, _⟩ : RunsStmt P c1 _ .next a3 :=
            RunsStmt.sequenceNext (RunsStmt.ifThenElseFalse test (RunsStmt.skip P a2))
              (increment_run inst.target (by omega) cell2 idx2 assigned)
          obtain ⟨cells3, formed3, locals3, heap3, world3, views3⟩ :=
            FreshCellFrame.assignCounter fE fa2.2.2.2.2.2 fa2.1 (assignLocal_assignCell 2 _ _ cell2 assigned)
          have fr3 : Frame a3 := ⟨cells3, locals3.trans fa2.2.1, heap3.trans fa2.2.2.1,
            world3.trans fa2.2.2.2.1, views3.trans fa2.2.2.2.2.1, formed3⟩
          have idx3 := assignLocal_finds_assigned 2 _ _ cell2 assigned
          refine ⟨condThreshold, bodyThreshold, c1, .next, a3, condStable, bodyStable,
            fun h => absurd rfl h.1, fun _ => ⟨?_, k + 1, kn, fr3, idx3, ?_⟩⟩
          · show n - counter 2 a3 < n - counter 2 s
            rw [counter_eq idx3, counter_eq idx]; omega
          · intro i below
            by_cases same : i = k
            · subst same; exact fun _ => good
            · exact before i (by omega) }
  have entryFrame : Frame (E.bindLocal 2 (.signed .i32 0)) :=
    ⟨FreshCellFrame.bindLocal E 2 _, rfl, rfl, rfl, rfl, fE.bindLocal _ _⟩
  obtain ⟨threshold, completion, after, loopStable, done⟩ :=
    executeTotalWhile measure P _ _ oracle (E.bindLocal 2 (.signed .i32 0))
      ⟨0, Nat.zero_le _, entryFrame, local_bound fE 2 _, fun _ below => absurd below (Nat.not_lt_zero _)⟩
  obtain ⟨frA, result⟩ := done
  have loopRun : RunsStmt P (E.bindLocal 2 (.signed .i32 0)) _ completion after := ⟨threshold, loopStable, frA.2.1⟩
  refine ⟨after, ?_, frA.1, frA.2.2.1, frA.2.2.2.1, frA.2.2.2.2.1⟩
  rcases result with ⟨rfl, all⟩ | ⟨k, kn, rfl, bad⟩
  · have holds : xs.all (fun a => ys.any (eqv · a) == want) = true := by
      refine List.all_eq_true.mpr fun a member => ?_
      obtain ⟨i, inside, rfl⟩ := List.getElem_of_mem member
      exact all i inside inside
    rw [holds]
    exact RunsStmt.sequenceNext loopRun (RunsStmt.returnValue (RunsExpr.value' _))
  · have fails : xs.all (fun a => ys.any (eqv · a) == want) = false := by
      cases h : xs.all (fun a => ys.any (eqv · a) == want) with
      | false => rfl
      | true =>
          have := List.all_eq_true.mp h xs[k] (List.getElem_mem _)
          rw [bad] at this; exact absurd this Bool.false_ne_true
    rw [fails]
    exact RunsStmt.sequenceCompleted loopRun (by intro h; cases h) _

#print axioms setScan_spec

end Lanius.Std
