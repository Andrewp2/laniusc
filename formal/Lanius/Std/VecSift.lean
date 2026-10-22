import Lanius.Std.VecSwap
import Lanius.Semantics.PureProof

/-! # `sift_down`

`fn sift_down<T>(items: [T], root: i32, count: i32)` moves `items[root]`
down the max-heap in `items[0..count)`: the loop runs `SiftInv` from
`HeapSortMath` and ends at a leaf or where the larger child is not greater. -/

namespace Lanius.Std

open Lanius Lanius.Core Lanius.Semantics Lanius.Memory

variable {P : Program} {T : Ty} {size : Nat}

theorem RunsStmt.returnNone (S : State) : RunsStmt P S (.returnValue none) (.returned none) S :=
  .ofStable (show StableStmt 1 P S (.returnValue none) (.returned none) S from .ofExec rfl) rfl

/-- `v * 2 + 1` -/
def twice1 (v : VarId) : Expr := .binary .add (.binary .multiply (.local v) (int 2)) (int 1)

/-- The loop body, with `items`, `root`, `count`, `parent`, `child` and
`held` the locals 0 to 5. -/
def siftBody (T : Ty) (lt : FunctionId) : Stmt :=
  .letLocal 4 i32Ty (twice1 3)
  (.sequence
    (.ifThenElse (.binary .logicalAnd (.binary .less (.binary .add (.local 4) (int 1)) (.local 2))
        (.call lt [.index (.local 0) (.local 4), .index (.local 0) (.binary .add (.local 4) (int 1))]))
      (increment 4) .skip)
  (.sequence
    (.ifThenElse (.unary .logicalNot (.call lt [.index (.local 0) (.local 3), .index (.local 0) (.local 4)]))
      (.returnValue none) .skip)
  (.letLocal 5 T (.index (.local 0) (.local 3))
    (.sequence (.expression (.assign .set (.index (.local 0) (.local 3)) (.index (.local 0) (.local 4))))
    (.sequence (.expression (.assign .set (.index (.local 0) (.local 4)) (.local 5)))
      (.expression (.assign .set (.local 3) (.local 4))))))))

def siftDownFn (T : Ty) (f lt : FunctionId) : Function where
  id := f
  parameters := [(0, .slice T), (1, i32Ty), (2, i32Ty)]
  returnType := .unit
  body := some (.letLocal 3 i32Ty (.local 1) (.whileLoop (.binary .less (twice1 3) (.local 2)) (siftBody T lt)))

theorem twice1_run (target : P.target = Target.x86_64) {t : State} {v : VarId} {j : Nat}
    (found : t.local? v = some (.signed .i32 (j : Int))) (small : 2 * j + 2 < 2 ^ 31) :
    RunsExpr P t (twice1 v) (.signed .i32 ((2 * j + 1 : Nat) : Int)) t := by
  have m := RunsExpr.binary (operation := .multiply) (program := P) (RunsExpr.local' found)
    (RunsExpr.value' (P := P) (S := t) (.signed .i32 2)) (by decide) (by rw [target]; exact eval_i32_mul2 (by omega))
  have r := RunsExpr.binary (operation := .add) m (RunsExpr.value' (P := P) (S := t) (.signed .i32 1)) (by decide)
    (by rw [target]; exact eval_i32_add (by omega) (by omega))
  rw [show ((2 * j : Nat) : Int) + 1 = ((2 * j + 1 : Nat) : Int) by omega] at r
  exact r

theorem plus1_stable (target : P.target = Target.x86_64) {t : State} {v : VarId} {j : Nat}
    (found : t.local? v = some (.signed .i32 (j : Int))) (small : j + 1 < 2 ^ 31) :
    ∃ k, StableExpr k P t (.binary .add (.local v) (int 1)) (.signed .i32 (Int.ofNat (j + 1))) t := by
  have r := RunsExpr.binary (operation := .add) (program := P) (RunsExpr.local' found)
    (RunsExpr.value' (P := P) (S := t) (.signed .i32 1)) (by decide)
    (by rw [target]; exact eval_i32_add (by omega) (by omega))
  rw [show (j : Int) + 1 = Int.ofNat (j + 1) by simp only [Int.ofNat_eq_natCast]; omega] at r
  obtain ⟨k, stable, _⟩ := r
  exact ⟨k, stable⟩

theorem keep_below {st after : State} {c : CellId} {w : Value} (assigned : st.assignCell c w = some after)
    {id : VarId} {cid : CellId} {v : Value} (cellFound : st.cellId? id = some cid) (lt : cid < c)
    (found : st.local? id = some v) : after.local? id = some v :=
  assignCell_preserves_other_local_of_cellId id c w assigned found
    (by rw [cellFound]; exact fun e => Nat.ne_of_lt lt (Option.some.inj e))

theorem siftDown_spec (target : P.target = Target.x86_64) (kind : ElemKind P T size) {f lt : FunctionId}
    (found : P.function? f = some (siftDownFn T f lt))
    {ltv : Value → Value → Bool} {vals : List Value} (ltSpec : LtSpec P lt ltv vals)
    (order : NegTrans ltv) (asymm : Asymm ltv)
    {caller : State} (formed : caller.CellsWellFormed) {p cap root cnt : Nat} {a0 : List Value} {h0 : Heap}
    (len : a0.length ≤ cap) (cntLe : cnt ≤ a0.length) (small : 2 * cnt < 2 ^ 31)
    (inv0 : SiftInv ltv a0 root cnt root)
    (buffer : 0 < cap → Buffer h0 p (size * cap)) (effect0 : HeapRegionWrite h0 caller.heap p (size * cap))
    (arr0 : ArrayAt P T size caller.heap p cap a0) (sub : ∀ z ∈ a0, z ∈ vals)
    (stores : ∀ y ∈ a0, ElemStore P T size y) (noViews : caller.i32ArrayViews = []) :
    ∃ (after : State) (a : List Value), RunsExpr P caller (.call f
        ([.rawSlice T (viewAddr T size p cap) cap, .signed .i32 root, .signed .i32 cnt].map Expr.value)) .unit after ∧
      FreshCellFrame caller after ∧ after.world = caller.world ∧ after.i32ArrayViews = caller.i32ArrayViews ∧
      ArrayAt P T size after.heap p cap a ∧ HeapRegionWrite h0 after.heap p (size * cap) ∧
      Sifted ltv a0 a root cnt := by
  let view := Value.rawSlice T (viewAddr T size p cap) cap
  let E0 : State := { caller with locals := [] }
  have f0 : E0.CellsWellFormed := formed
  have f1 := f0.bindLocal 0 view
  have f2 := f1.bindLocal 1 (.signed .i32 root)
  let E := ((E0.bindLocal 0 view).bindLocal 1 (.signed .i32 root)).bindLocal 2 (.signed .i32 cnt)
  have fE : E.CellsWellFormed := f2.bindLocal _ _
  have e2 : E.local? 2 = some (.signed .i32 cnt) := local_bound f2 2 _
  have e1 : E.local? 1 = some (.signed .i32 root) := local_kept f2 _ (by decide) (local_bound f1 1 _)
  have e0 : E.local? 0 = some view :=
    local_kept f2 _ (by decide) (local_kept f1 _ (by decide) (local_bound f0 0 _))
  let B := E.bindLocal 3 (.signed .i32 root)
  have fB : B.CellsWellFormed := fE.bindLocal _ _
  let c3 := E.nextCell
  -- the loop frame
  let Frame : State → Prop := fun s => FreshCellFrame E s ∧ s.locals = B.locals ∧ s.world = E.world ∧
    s.i32ArrayViews = [] ∧ s.CellsWellFormed
  have frameLocals : ∀ s, Frame s → s.local? 0 = some view ∧ s.local? 2 = some (.signed .i32 cnt) :=
    fun s fr => ⟨local_above fr.1 fr.2.1 (by decide) e0, local_above fr.1 fr.2.1 (by decide) e2⟩
  have cell3 : ∀ s, Frame s → s.cellId? 3 = some c3 := fun s fr => by
    simp [State.cellId?, fr.2.1, B, State.bindLocal, State.bindCell, c3]
  have subOf : ∀ a : List Value, a.Perm a0 → ∀ z ∈ a, z ∈ vals := fun a perm z m => sub z (perm.mem_iff.mp m)
  have storesOf : ∀ a : List Value, a.Perm a0 → ∀ y ∈ a, ElemStore P T size y :=
    fun a perm y m => stores y (perm.mem_iff.mp m)
  let Inv : State → Prop := fun s => ∃ (a : List Value) (j : Nat), Frame s ∧ s.local? 3 = some (.signed .i32 (j : Int)) ∧
    ArrayAt P T size s.heap p cap a ∧ HeapRegionWrite h0 s.heap p (size * cap) ∧ a.length = a0.length ∧
    a.Perm a0 ∧ (∀ i, i < cnt → ∃ i', i' < cnt ∧ elt a i = elt a0 i') ∧ (∀ k, cnt ≤ k → elt a k = elt a0 k) ∧
    SiftInv ltv a root cnt j
  let Done : Completion → State → Prop := fun c s => (c = .next ∨ c = .returned none) ∧ Frame s ∧
    ∃ a, ArrayAt P T size s.heap p cap a ∧ HeapRegionWrite h0 s.heap p (size * cap) ∧ Sifted ltv a0 a root cnt
  let measure : State → Nat := fun s => cnt - counter 3 s
  let oracle : TotalWhileOracle measure P (.binary .less (twice1 3) (.local 2)) (siftBody T lt) := {
    Inv := Inv
    Done := Done
    step := by
      intro s invariant
      obtain ⟨a, j, fr, s3, arr, effect, alen, perm, region, untouched, sinv⟩ := invariant
      obtain ⟨s0, s2⟩ := frameLocals s fr
      have fs : s.CellsWellFormed := fr.2.2.2.2
      have jc : j < cnt := sinv.2.1
      have cond := RunsExpr.binary (operation := .less) (program := P) (twice1_run target s3 (by omega))
        (RunsExpr.local' s2) (by decide) (eval_i32_lt _ _ _)
      by_cases leaf : cnt ≤ 2 * j + 1
      · rw [show decide (((2 * j + 1 : Nat) : Int) < cnt) = false by simp; omega] at cond
        obtain ⟨threshold, stable, _⟩ := cond
        exact Or.inl ⟨threshold, s, stable, Or.inl rfl, fr, a, arr, effect, alen, perm, sift_leaf sinv leaf,
          region, untouched⟩
      rw [show decide (((2 * j + 1 : Nat) : Int) < cnt) = true by simp; omega] at cond
      obtain ⟨condThreshold, condStable, _⟩ := cond
      right
      -- let child = parent * 2 + 1
      let s4 := s.bindLocal 4 (.signed .i32 ((2 * j + 1 : Nat) : Int))
      have fs4 : s4.CellsWellFormed := fs.bindLocal _ _
      have s4_0 : s4.local? 0 = some view := local_kept fs _ (by decide) s0
      have s4_2 : s4.local? 2 = some (.signed .i32 cnt) := local_kept fs _ (by decide) s2
      have s4_3 : s4.local? 3 = some (.signed .i32 (j : Int)) := local_kept fs _ (by decide) s3
      have s4_4 : s4.local? 4 = some (.signed .i32 ((2 * j + 1 : Nat) : Int)) := local_bound fs 4 _
      have c4 : s4.cellId? 4 = some s.nextCell := bindLocal_cellId s 4 _
      have frame4 : FreshCellFrame E s4 := fr.1.trans (FreshCellFrame.bindLocal s 4 _)
      have arr4 : ArrayAt P T size s4.heap p cap a := arr
      have ja : 2 * j + 1 < a.length := by omega
      -- if (child + 1 < count && T::lt(items[child], items[child + 1])) { child += 1; }
      obtain ⟨_, _, nextLe, _⟩ := fr.1
      obtain ⟨cid0, hc0⟩ := cellId_of_local s0
      have lt0 : cid0 < s.nextCell := fs.localCellBound hc0 s0
      have lt3 : c3 < s.nextCell := fs.localCellBound (cell3 s fr) s3
      have cs4 : ∀ id, id ≠ 4 → s4.cellId? id = s.cellId? id := fun id ne => cellId_bindLocal_ne s _ (Ne.symm ne)
      have choose : ∃ (m2 : State) (c : Nat),
          RunsStmt P s4 (.ifThenElse (.binary .logicalAnd (.binary .less (.binary .add (.local 4) (int 1)) (.local 2))
            (.call lt [.index (.local 0) (.local 4), .index (.local 0) (.binary .add (.local 4) (int 1))]))
            (increment 4) .skip) .next m2 ∧
          FreshCellFrame E m2 ∧ m2.locals = s4.locals ∧ m2.heap = s.heap ∧ m2.world = s.world ∧
          m2.i32ArrayViews = s.i32ArrayViews ∧ m2.CellsWellFormed ∧
          m2.local? 0 = some view ∧ m2.local? 3 = some (.signed .i32 (j : Int)) ∧
          m2.local? 4 = some (.signed .i32 (c : Int)) ∧ MaxChild ltv a cnt j c := by
        obtain ⟨k1, plus⟩ := plus1_stable target s4_4 (by omega)
        have left := RunsExpr.binary (operation := .less) (program := P) (RunsExpr.ofStable plus rfl)
          (RunsExpr.local' s4_2) (by decide) (eval_i32_lt _ _ _)
        by_cases two : 2 * j + 2 < cnt
        · rw [show decide ((Int.ofNat (2 * j + 1 + 1)) < (cnt : Int)) = true by
            simp only [Int.ofNat_eq_natCast, decide_eq_true_eq]; omega] at left
          obtain ⟨m1, callRun, pure1⟩ := lt_call ltSpec fs4 s4_0 (StableExpr.local s4_4) plus ja (by omega) arr4
            (subOf a perm)
          obtain ⟨m1', andRun, pure1'⟩ := RunsExpr.logicalAndTruePure left ⟨m1, callRun, pure1⟩
          have fm1 : m1'.CellsWellFormed := pure1'.afterFormed
          have m1_0 := pure1'.localFound s4_0
          have m1_3 := pure1'.localFound s4_3
          have m1_4 := pure1'.localFound s4_4
          have cm : ∀ id, m1'.cellId? id = s4.cellId? id := fun id => by unfold State.cellId?; rw [pure1'.locals]
          cases less : ltv (elt a (2 * j + 1)) (elt a (2 * j + 1 + 1)) with
          | true =>
              rw [less] at andRun
              obtain ⟨m2, assigned⟩ := assignLocal_exists m1' 4 _ (.signed .i32 (Int.ofNat (2 * j + 1 + 1))) _
                ((cm 4).trans c4) m1_4
              have cellA := assignLocal_assignCell 4 _ _ ((cm 4).trans c4) assigned
              have eff := assignCell_effect cellA
              obtain ⟨frame2, _, _, _, _⟩ := FreshCellFrame.assignFresh fE fm1 (frame4.trans pure1'.cells)
                nextLe cellA
              refine ⟨m2, 2 * j + 1 + 1, RunsStmt.ifThenElseTrue andRun
                  (increment_run target (k := 2 * j + 1) (by omega) ((cm 4).trans c4) m1_4 assigned),
                frame2, eff.locals.trans pure1'.locals, eff.heap.trans pure1'.heap, eff.world.trans pure1'.world,
                eff.views.trans pure1'.views, FreshCellFrame.after_cellsWellFormed fE frame2,
                keep_below cellA ((cm 0).trans ((cs4 0 (by decide)).trans hc0)) lt0 m1_0,
                keep_below cellA ((cm 3).trans ((cs4 3 (by decide)).trans (cell3 s fr))) lt3 m1_3,
                assignLocal_finds_assigned 4 _ _ ((cm 4).trans c4) assigned, maxChild_right asymm two less⟩
          | false =>
              rw [less] at andRun
              exact ⟨m1', 2 * j + 1, RunsStmt.ifThenElseFalse andRun (RunsStmt.skip P m1'),
                frame4.trans pure1'.cells, pure1'.locals, pure1'.heap, pure1'.world, pure1'.views, fm1,
                m1_0, m1_3, m1_4, maxChild_left asymm (by omega) (fun _ => less)⟩
        · rw [show decide ((Int.ofNat (2 * j + 1 + 1)) < (cnt : Int)) = false by
            simp only [Int.ofNat_eq_natCast, decide_eq_false_iff_not]; omega] at left
          obtain ⟨m1, andRun, pure1⟩ := RunsExpr.logicalAndFalsePure (rightExpr :=
            .call lt [.index (.local 0) (.local 4), .index (.local 0) (.binary .add (.local 4) (int 1))])
            ⟨s4, left, PureFrame.refl fs4⟩
          exact ⟨m1, 2 * j + 1, RunsStmt.ifThenElseFalse andRun (RunsStmt.skip P m1),
            frame4.trans pure1.cells, pure1.locals, pure1.heap, pure1.world, pure1.views, pure1.afterFormed,
            pure1.localFound s4_0, pure1.localFound s4_3, pure1.localFound s4_4,
            maxChild_left asymm (by omega) (fun h => absurd h two)⟩
      obtain ⟨m2, c, if1, frame2, locals2, heap2, world2, views2, fm2, m2_0, m2_3, m2_4, max⟩ := choose
      have cc : c < cnt := max.2.1
      have ca : c < a.length := by omega
      have jcc : j < c := by have := max.2.2.1; have := max.1; omega
      -- if (!T::lt(items[parent], items[child])) { return; }
      have arr2 : ArrayAt P T size m2.heap p cap a := by rw [heap2]; exact arr
      obtain ⟨m3, callRun, pure3⟩ := lt_call ltSpec fm2 m2_0 (StableExpr.local m2_3) (StableExpr.local m2_4)
        (by omega) ca arr2 (subOf a perm)
      have notRun := RunsExpr.unary (operator := .logicalNot) callRun rfl
      have frame3 : FreshCellFrame E m3 := frame2.trans pure3.cells
      have heap3 : m3.heap = s.heap := pure3.heap.trans heap2
      have restoreFrame : ∀ R : State, FreshCellFrame E R → R.world = E.world → R.i32ArrayViews = [] →
          Frame (restoreLocals s R) := fun R fR wR vR => by
        have frame' : FreshCellFrame E (restoreLocals s R) := by
          obtain ⟨e, cl, nx, fx⟩ := fR; exact ⟨e, cl, nx, fx⟩
        exact ⟨frame', fr.2.1, wR, vR, FreshCellFrame.after_cellsWellFormed fE frame'⟩
      have world3 : m3.world = E.world := pure3.world.trans (world2.trans fr.2.2.1)
      have views3 : m3.i32ArrayViews = [] := pure3.views.trans (views2.trans fr.2.2.2.1)
      have fm3 : m3.CellsWellFormed := pure3.afterFormed
      have m3_0 := pure3.localFound m2_0
      have m3_3 := pure3.localFound m2_3
      have m3_4 := pure3.localFound m2_4
      have twiceRun := twice1_run (P := P) target s3 (by omega)
      cases less : ltv (elt a j) (elt a c) with
      | false =>
          rw [less] at notRun
          obtain ⟨bodyThreshold, bodyStable, _⟩ : RunsStmt P s (siftBody T lt) (.returned none) (restoreLocals s m3) :=
            RunsStmt.letLocal twiceRun (RunsStmt.sequenceNext if1
              (RunsStmt.sequenceCompleted (RunsStmt.ifThenElseTrue notRun (RunsStmt.returnNone m3))
                (by intro h; cases h) _))
          refine ⟨condThreshold, bodyThreshold, s, .returned none, restoreLocals s m3, condStable, bodyStable,
            fun _ => ⟨Or.inr rfl, restoreFrame m3 frame3 world3 views3, a, ?_, ?_,
              alen, perm, sift_stop order sinv max less, region, untouched⟩, fun h => ?_⟩
          · show ArrayAt P T size m3.heap p cap a; rw [heap3]; exact arr
          · show HeapRegionWrite h0 m3.heap p (size * cap); rw [heap3]; exact effect
          · rcases h with h | h <;> cases h
      | true =>
          rw [less] at notRun
          obtain ⟨h2, arrNew, effNew, cont⟩ := swap_run kind fm3 (items := 0) (held := 5) (ei := .local 3)
            (ej := .local 4) (i := j) (j := c) m3_0 (by decide)
            (fun t ag => ⟨1, StableExpr.local (ag 3 _ (by decide) m3_3)⟩)
            (fun t ag => ⟨1, StableExpr.local (ag 4 _ (by decide) m3_4)⟩) (by omega) ca (by omega) (by omega) buffer
            (by rw [heap3]; exact effect) (by rw [heap3]; exact arr) (storesOf a perm) views3
          let s5 : State := { m3.bindLocal 5 (elt a j) with heap := h2 }
          have s5_3 : s5.local? 3 = some (.signed .i32 (j : Int)) := local_kept fm3 _ (by decide) m3_3
          have s5_4 : s5.local? 4 = some (.signed .i32 (c : Int)) := local_kept fm3 _ (by decide) m3_4
          have m3c : m3.cellId? 3 = some c3 := by
            have l : m3.cellId? 3 = s4.cellId? 3 := by unfold State.cellId?; rw [pure3.locals, locals2]
            exact l.trans ((cs4 3 (by decide)).trans (cell3 s fr))
          have s5c : s5.cellId? 3 = some c3 := (cellId_bindLocal_ne m3 _ (by decide)).trans m3c
          obtain ⟨R, assigned⟩ := assignLocal_exists s5 3 _ (.signed .i32 (c : Int)) c3 s5c s5_3
          have swapRun := cont _ _ R (assign_run s5c s5_3 (RunsExpr.local' s5_4) rfl rfl assigned)
          obtain ⟨bodyThreshold, bodyStable, _⟩ : RunsStmt P s (siftBody T lt) .next
              (restoreLocals s (restoreLocals m3 R)) :=
            RunsStmt.letLocal twiceRun (RunsStmt.sequenceNext if1
              (RunsStmt.sequenceNext (RunsStmt.ifThenElseFalse notRun (RunsStmt.skip P m3)) swapRun))
          have cellA := assignLocal_assignCell 3 c3 _ s5c assigned
          have effR := assignCell_effect cellA
          have frame5 : FreshCellFrame E s5 := by
            obtain ⟨e, cl, nx, fx⟩ := frame3.trans (FreshCellFrame.bindLocal m3 5 (elt a j))
            exact ⟨e, cl, nx, fx⟩
          obtain ⟨frameR, _, _, _, _⟩ := FreshCellFrame.assignFresh fE
            (FreshCellFrame.after_cellsWellFormed fE frame5) frame5 (Nat.le_refl _) cellA
          have frameR' : FreshCellFrame E (restoreLocals m3 R) := by
            obtain ⟨e, cl, nx, fx⟩ := frameR; exact ⟨e, cl, nx, fx⟩
          let s' := restoreLocals s (restoreLocals m3 R)
          have s'_3 : s'.local? 3 = some (.signed .i32 (c : Int)) := by
            refine (local?_congr (s := s') (t := R) rfl ?_).trans (assignLocal_finds_assigned 3 c3 _ s5c assigned)
            show s.cellId? 3 = R.cellId? 3
            have l : R.cellId? 3 = s5.cellId? 3 := by unfold State.cellId?; rw [effR.locals]
            rw [l, s5c, cell3 s fr]
          have heapR : s'.heap = h2 := effR.heap
          have es := elt_swapAt (show j < a.length by omega) ca
          refine ⟨condThreshold, bodyThreshold, s, .next, s', condStable, bodyStable, fun h => absurd rfl h.1,
            fun _ => ⟨?_, swapAt a j c, c, restoreFrame _ frameR' (effR.world.trans world3) (effR.views.trans views3),
              s'_3, by rw [heapR]; exact arrNew, by rw [heapR]; exact effNew, by rw [length_swapAt]; exact alen,
              (swapAt_perm (by omega) ca).trans perm, fun i ic => ?_, fun k ck => ?_,
              sift_step asymm sinv max less (by omega)⟩⟩
          · show cnt - counter 3 s' < cnt - counter 3 s
            rw [counter_eq s'_3, counter_eq s3]; omega
          · rw [es]
            by_cases ic' : i = c
            · rw [if_pos ic']; exact region j jc
            · rw [if_neg ic']
              by_cases ij : i = j
              · rw [if_pos ij]; exact region c cc
              · rw [if_neg ij]; exact region i ic
          · rw [es, if_neg (by omega), if_neg (by omega)]; exact untouched k ck }
  have frame0 : Frame B := ⟨FreshCellFrame.bindLocal E 3 _, rfl, rfl, noViews, fB⟩
  obtain ⟨threshold, completion, final, loopStable, cases, frF, a, arrF, effF, sifted⟩ :=
    executeTotalWhile measure P _ _ oracle B
      ⟨a0, root, frame0, local_bound fE 3 _, arr0, effect0, rfl, List.Perm.refl _, fun i ic => ⟨i, ic, rfl⟩,
        fun k _ => rfl, inv0⟩
  have loopRun : RunsStmt P B (.whileLoop (.binary .less (twice1 3) (.local 2)) (siftBody T lt)) completion final :=
    ⟨threshold, loopStable, frF.2.1⟩
  have bodyRun := RunsStmt.letLocal (type := i32Ty) (RunsExpr.local' e1) loopRun
  have entry : FreshCellFrame caller E :=
    (show FreshCellFrame caller E0 from ⟨[], by simp [E0], Nat.le_refl _, by simp⟩).trans
      (FreshCellFrame.bindLocals E0 [(0, view), (1, .signed .i32 root), (2, .signed .i32 cnt)])
  have frameOut : FreshCellFrame caller (restoreLocals caller (restoreLocals E final)) := by
    obtain ⟨e, cl, nx, fx⟩ := entry.trans frF.1; exact ⟨e, cl, nx, fx⟩
  refine ⟨restoreLocals caller (restoreLocals E final), a, ?_, frameOut, frF.2.2.1, frF.2.2.2.1.trans noViews.symm,
    arrF, effF, sifted⟩
  rcases cases with rfl | rfl
  · exact RunsExpr.callUnit found rfl rfl (RunsExprs.values _) rfl bodyRun
  · exact RunsExpr.callUnitReturned found rfl rfl (RunsExprs.values _) rfl bodyRun

#print axioms siftDown_spec

end Lanius.Std
