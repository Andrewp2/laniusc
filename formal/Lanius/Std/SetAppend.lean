import Lanius.Std.SetCount

/-! # `append_where`

`append_where(output, from, other, present)` pushes onto `output` the items
`a` of `from` with `contains(other, a) == present`, in order. The set algebra
functions reserve room for them first, so every push has room: it writes
only `output`'s storage, and `from`, `other` and the heap layout survive. -/

namespace Lanius.Std

open Lanius Lanius.Core Lanius.Semantics Lanius.Memory

variable {P : Program} {T : Ty} {ids : VecIds} {g : GrowIds} {size : Nat}

/-- The calls the set scans make. -/
structure SetIds where
  sl : FunctionId
  sc : FunctionId
  vc : FunctionId
  indexOf : FunctionId
  eq : FunctionId
  atf : FunctionId
  asl : FunctionId
  pf : FunctionId

structure SetInstance (P : Program) (T : Ty) (ids : VecIds) (sid : TypeId) (si : SetIds) : Prop where
  vec : VecInstance P T ids
  sl : P.function? si.sl = some (setForwardFn sid si.sl ids.len i32Ty)
  sc : P.function? si.sc = some (setContainsFn T sid si.sc si.vc)
  vc : P.function? si.vc = some (vecContainsFn ids T si.vc si.indexOf)
  indexOf : P.function? si.indexOf = some (indexOfFn ids T si.indexOf si.eq)
  atf : P.function? si.atf = some (atFn ids T si.atf si.asl)
  asl : P.function? si.asl = some (asSliceFn ids T si.asl si.pf)
  pf : P.function? si.pf = some (prefixFromStorageFn T si.pf ids.fromStorage)

/-- `append_where`, with locals 0 `output`, 1 `from`, 2 `other`, 3 `present`,
4 `items`, 5 `index`, 6 `item`. -/
def setAppendWhereFn (ids : VecIds) (g : GrowIds) (T : Ty) (sid : TypeId) (f : FunctionId) (si : SetIds) :
    Function where
  id := f
  parameters := [(0, vecTy ids), (1, setTy sid), (2, setTy sid), (3, boolTy)]
  returnType := vecTy ids
  body := some <|
    .letLocal 4 (vecTy ids) (.local 0)
    (.letLocal 5 i32Ty (int 0)
    (.sequence
      (.whileLoop (.binary .less (.local 5) (.call si.sl [.local 1]))
        (.letLocal 6 T (.call si.atf [.field (.local 1) 0, .local 5])
          (.sequence
            (.ifThenElse (.binary .equal (.call si.sc [.local 2, .local 6]) (.local 3))
              (.expression (.assign .set (.local 4) (.call g.tryPush [.local 4, .local 6]))) .skip)
            (increment 5))))
      (.returnValue (some (.local 4)))))

/-! ## Heap facts -/

theorem Kept.trans {a b c : Heap} {p n : Nat} (first : Kept a b p n) (second : Kept b c p n) : Kept a c p n :=
  ⟨fun lo m apart => ReadsWithin.trans (first.reads lo m apart) (second.reads lo m apart),
    fun q m positive apart buffer => second.buffers q m positive apart (first.buffers q m positive apart buffer)⟩

/-- A vector whose storage is apart from `[q, q + n)` is kept. -/
theorem VecRep.keptApart {h H : Heap} {q n : Nat} (kept : Kept h H q n) {vec : TypeId} {p cap : Nat} {len : Value}
    {xs : List Value} (rep : VecRep P T size vec h (.structure vec [.pointer p, len, .signed .i32 cap]) xs)
    (apart : p + size * cap ≤ q ∨ q + n ≤ p) (positive : 0 < size) :
    VecRep P T size vec H (.structure vec [.pointer p, len, .signed .i32 cap]) xs := by
  obtain ⟨p', cap', same, lenLe, capBound, buffer, reads⟩ := rep
  simp only [Value.structure.injEq, List.cons.injEq, Value.pointer.injEq, Value.signed.injEq, true_and,
    and_true] at same
  obtain ⟨rfl, lenEq, e⟩ := same
  have : cap = cap' := by omega
  subst this
  refine ⟨p, cap, by rw [lenEq], lenLe, capBound,
    fun pos => kept.buffers p (size * cap) (Nat.mul_pos positive pos) apart (buffer pos),
    fun i inside other within => reads i inside other (ReadsWithin.trans (kept.reads _ _ ?_) within)⟩
  have := slot_inside (T := T) (size := size) (p := p) (show i < cap by omega)
  omega

theorem filter_take_step (p : Value → Bool) (xs : List Value) {k : Nat} (kn : k < xs.length) :
    (xs.take (k + 1)).filter p = (xs.take k).filter p ++ (if p xs[k] then [xs[k]] else []) := by
  rw [List.take_add_one, List.getElem?_eq_getElem kn, List.filter_append]
  cases h : p xs[k] <;> simp [h]

theorem filter_take_le (p : Value → Bool) (xs : List Value) (k : Nat) :
    ((xs.take k).filter p).length ≤ (xs.filter p).length :=
  ((List.take_sublist k xs).filter p).length_le

/-! ## The spec -/

/-- `append_where(output, from, other, present)` when `output` (storage `q`,
capacity `m`) has room for the items, and `from`'s and `other`'s storage are
apart from `output`'s. -/
theorem setAppendWhere_spec (grow : GrowInstance P T ids g) (kind : ElemKind P T size) {sid : TypeId}
    {si : SetIds} (inst : SetInstance P T ids sid si) {f : FunctionId}
    (found : P.function? f = some (setAppendWhereFn ids g T sid f si))
    {eqv : Value → Value → Bool} {vals : List Value} (eqSpec : EqSpec P si.eq eqv vals)
    {caller : State} (formed : caller.CellsWellFormed) {acc xs ys : List Value} {q m p cap r rc : Nat}
    (repO : VecRep P T size ids.vec caller.heap
      (.structure ids.vec [.pointer q, .signed .i32 acc.length, .signed .i32 m]) acc)
    (repL : VecRep P T size ids.vec caller.heap
      (.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]) xs)
    (repR : VecRep P T size ids.vec caller.heap
      (.structure ids.vec [.pointer r, .signed .i32 ys.length, .signed .i32 rc]) ys)
    (apartL : p + size * cap ≤ q ∨ q + size * m ≤ p) (apartR : r + size * rc ≤ q ∨ q + size * m ≤ r)
    (present : Bool) (room : acc.length + (whereIn eqv ys present xs).length ≤ m)
    (subL : ∀ z ∈ xs, z ∈ vals) (subR : ∀ z ∈ ys, z ∈ vals) (stores : ∀ y ∈ xs, ElemStore P T size y)
    (below : HeapBlocksBelowNext caller.heap) (unique : HeapBlockBasesUnique caller.heap)
    (apart : HeapApart caller.heap) (noViews : caller.i32ArrayViews = []) :
    ∃ after, RunsExpr P caller (.call f
        ([Value.structure ids.vec [.pointer q, .signed .i32 acc.length, .signed .i32 m],
          .structure sid [.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]],
          .structure sid [.structure ids.vec [.pointer r, .signed .i32 ys.length, .signed .i32 rc]],
          .boolean present].map Expr.value))
      (.structure ids.vec [.pointer q, .signed .i32 (acc ++ whereIn eqv ys present xs).length, .signed .i32 m])
        after ∧
      FreshCellFrame caller after ∧ after.world = caller.world ∧ after.i32ArrayViews = caller.i32ArrayViews ∧
      VecRep P T size ids.vec after.heap
        (.structure ids.vec [.pointer q, .signed .i32 (acc ++ whereIn eqv ys present xs).length, .signed .i32 m])
        (acc ++ whereIn eqv ys present xs) ∧
      Kept caller.heap after.heap q (size * m) ∧ HeapBlocksBelowNext after.heap ∧
      HeapBlockBasesUnique after.heap ∧ HeapApart after.heap := by
  have positive : 0 < size := by cases kind <;> omega
  obtain ⟨_, lenLe, capBound, _, _⟩ := repL.fields
  let n := xs.length
  have nBound : n < 2 ^ 31 := by omega
  let pred : Value → Bool := fun a => ys.any (eqv · a) == present
  let W : Nat → List Value := fun k => (xs.take k).filter pred
  let out : Nat → Value := fun k => .structure ids.vec [.pointer q, .signed .i32 (acc ++ W k).length, .signed .i32 m]
  let vvL := Value.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]
  let vvR := Value.structure ids.vec [.pointer r, .signed .i32 ys.length, .signed .i32 rc]
  let vo := Value.structure ids.vec [.pointer q, .signed .i32 acc.length, .signed .i32 m]
  let HeapInv : Nat → Heap → Prop := fun k H => VecRep P T size ids.vec H (out k) (acc ++ W k) ∧
    Kept caller.heap H q (size * m) ∧ HeapBlocksBelowNext H ∧ HeapBlockBasesUnique H ∧ HeapApart H
  have repLAt : ∀ H : Heap, Kept caller.heap H q (size * m) → VecRep P T size ids.vec H vvL xs :=
    fun H kept => repL.keptApart kept apartL positive
  have repRAt : ∀ H : Heap, Kept caller.heap H q (size * m) → VecRep P T size ids.vec H vvR ys :=
    fun H kept => repR.keptApart kept apartR positive
  -- the entry state
  let E0 : State := { caller with locals := [] }
  have f0 : E0.CellsWellFormed := formed
  have f1 := f0.bindLocal 0 vo
  have f2 := f1.bindLocal 1 (.structure sid [vvL])
  have f3 := f2.bindLocal 2 (.structure sid [vvR])
  let E := (((E0.bindLocal 0 vo).bindLocal 1 (.structure sid [vvL])).bindLocal 2 (.structure sid [vvR])).bindLocal 3
    (.boolean present)
  have fE : E.CellsWellFormed := f3.bindLocal _ _
  have l3 : E.local? 3 = some (.boolean present) := local_bound f3 3 _
  have l2 : E.local? 2 = some (.structure sid [vvR]) := local_kept f3 _ (by decide) (local_bound f2 2 _)
  have l1 : E.local? 1 = some (.structure sid [vvL]) :=
    local_kept f3 _ (by decide) (local_kept f2 _ (by decide) (local_bound f1 1 _))
  have l0 : E.local? 0 = some vo :=
    local_kept f3 _ (by decide) (local_kept f2 _ (by decide) (local_kept f1 _ (by decide) (local_bound f0 0 _)))
  let E4 := E.bindLocal 4 vo
  have fE4 : E4.CellsWellFormed := fE.bindLocal _ _
  let E5 := E4.bindLocal 5 (.signed .i32 0)
  have fE5 : E5.CellsWellFormed := fE4.bindLocal _ _
  let Frame : State → Prop := fun s => FreshCellFrame E s ∧ s.locals = E5.locals ∧ s.world = E.world ∧
    s.i32ArrayViews = [] ∧ s.CellsWellFormed
  have frameLocals : ∀ s : State, Frame s → s.local? 1 = some (.structure sid [vvL]) ∧
      s.local? 2 = some (.structure sid [vvR]) ∧ s.local? 3 = some (.boolean present) :=
    fun s fr => ⟨local_above2 fr.1 fr.2.1 (by decide) (by decide) l1,
      local_above2 fr.1 fr.2.1 (by decide) (by decide) l2, local_above2 fr.1 fr.2.1 (by decide) (by decide) l3⟩
  have framePure : ∀ s s' : State, Frame s → PureFrame s s' → Frame s' := fun s s' fr pure =>
    ⟨fr.1.trans pure.cells, pure.locals.trans fr.2.1, pure.world.trans fr.2.2.1, pure.views.trans fr.2.2.2.1,
      pure.afterFormed⟩
  have cell4 : ∀ s : State, s.locals = E5.locals → s.cellId? 4 = some E.nextCell := fun s ls => by
    simp [State.cellId?, ls, E5, E4, State.bindLocal, State.bindCell]
  have cell5 : ∀ s : State, s.locals = E5.locals → s.cellId? 5 = some (E.nextCell + 1) := fun s ls => by
    simp [State.cellId?, ls, E5, E4, State.bindLocal, State.bindCell]
  have condAt : ∀ (s : State) (k : Nat), Frame s → Kept caller.heap s.heap q (size * m) →
      s.local? 5 = some (.signed .i32 k) → ∃ s',
      RunsExpr P s (.binary .less (.local 5) (.call si.sl [.local 1])) (.boolean (decide ((k : Int) < n))) s' ∧
        PureFrame s s' := fun s k fr kept idx => by
    obtain ⟨s', lenRun, pure⟩ := setLen_spec inst.vec inst.sl fr.2.2.2.2 (repLAt s.heap kept)
    exact ⟨s', RunsExpr.binary (RunsExpr.local' idx)
      (callArgs (RunsExprs.one (RunsExpr.local' (frameLocals s fr).1)) lenRun) (by decide) (eval_i32_lt _ _ _), pure⟩
  let body : Stmt := .letLocal 6 T (.call si.atf [.field (.local 1) 0, .local 5])
    (.sequence
      (.ifThenElse (.binary .equal (.call si.sc [.local 2, .local 6]) (.local 3))
        (.expression (.assign .set (.local 4) (.call g.tryPush [.local 4, .local 6]))) .skip)
      (increment 5))
  let measure : State → Nat := fun s => n - counter 5 s
  let oracle : TotalWhileOracle measure P (.binary .less (.local 5) (.call si.sl [.local 1])) body := {
    Inv := fun s => ∃ k : Nat, k ≤ n ∧ Frame s ∧ s.local? 5 = some (.signed .i32 k) ∧
      s.local? 4 = some (out k) ∧ HeapInv k s.heap
    Done := fun c s => Frame s ∧ c = .next ∧ s.local? 4 = some (out n) ∧ HeapInv n s.heap
    step := by
      intro s invariant
      obtain ⟨k, kle, fr, idx, items, hinv⟩ := invariant
      obtain ⟨c1, cond, pure1⟩ := condAt s k fr hinv.2.1 idx
      have fr1 := framePure s c1 fr pure1
      have idx1 := pure1.localFound idx
      have items1 := pure1.localFound items
      have h1 : c1.heap = s.heap := pure1.heap
      by_cases last : k = n
      · subst last
        rw [show decide (((xs.length : Nat) : Int) < xs.length) = false by simp] at cond
        obtain ⟨threshold, stable, _⟩ := cond
        exact Or.inl ⟨threshold, c1, stable, fr1, rfl, items1, by rw [h1]; exact hinv⟩
      have kn : k < n := by omega
      rw [show decide ((k : Int) < n) = true by simp; omega] at cond
      obtain ⟨condThreshold, condStable, _⟩ := cond
      right
      obtain ⟨c1_1, c1_2, c1_3⟩ := frameLocals c1 fr1
      obtain ⟨repK, keptK, belowK, uniqueK, apartK⟩ := hinv
      -- at(from.items, index)
      obtain ⟨a1, atRun, pa1⟩ := at_spec inst.vec kind inst.atf inst.asl inst.pf fr1.2.2.2.2
        (by rw [h1]; exact repLAt s.heap keptK) (by rw [h1]; exact apartK.disjoint uniqueK) kn
      have atCall := callArgs (RunsExprs.two (RunsExpr.field' (j := 0) (RunsExpr.local' c1_1) rfl)
        (RunsExpr.local' idx1)) atRun
      have fa1 := pa1.afterFormed
      let b := a1.bindLocal 6 xs[k]
      have fb : b.CellsWellFormed := fa1.bindLocal _ _
      have b6 : b.local? 6 = some xs[k] := local_bound fa1 6 _
      have b2 : b.local? 2 = some (.structure sid [vvR]) := local_kept fa1 _ (by decide) (pa1.localFound c1_2)
      have b3 : b.local? 3 = some (.boolean present) := local_kept fa1 _ (by decide) (pa1.localFound c1_3)
      have b4 : b.local? 4 = some (out k) := local_kept fa1 _ (by decide) (pa1.localFound items1)
      have b5 : b.local? 5 = some (.signed .i32 k) := local_kept fa1 _ (by decide) (pa1.localFound idx1)
      have hb : b.heap = s.heap := pa1.heap.trans h1
      -- contains(other, item) == present
      obtain ⟨a2, cRun, pa2⟩ := setContains_spec inst.vec kind inst.sc inst.vc inst.indexOf eqSpec fb
        (by rw [hb]; exact repRAt s.heap keptK) (subL _ (List.getElem_mem _)) subR
      have test := RunsExpr.binary (operation := .equal) (callArgs (RunsExprs.two (RunsExpr.local' b2)
        (RunsExpr.local' b6)) cRun) (RunsExpr.local' (pa2.localFound b3)) (by decide) (eval_bool_eq _ _ _)
      have fa2 := pa2.afterFormed
      have h2 : a2.heap = s.heap := pa2.heap.trans hb
      have a2_4 := pa2.localFound b4
      have a2_5 := pa2.localFound b5
      have a2_6 := pa2.localFound b6
      have frameA2 : FreshCellFrame E a2 :=
        ((fr1.1.trans pa1.cells).trans (FreshCellFrame.bindLocal a1 6 _)).trans pa2.cells
      have cellsA2 : ∀ id, id ≠ 6 → a2.cellId? id = c1.cellId? id := fun id ne => by
        have l : a2.cellId? id = b.cellId? id := by unfold State.cellId?; rw [pa2.locals]
        rw [l, cellId_bindLocal_ne a1 _ (Ne.symm ne)]
        unfold State.cellId?; rw [pa1.locals]
      have c4 : a2.cellId? 4 = some E.nextCell := (cellsA2 4 (by decide)).trans (cell4 c1 fr1.2.1)
      have c5 : a2.cellId? 5 = some (E.nextCell + 1) := (cellsA2 5 (by decide)).trans (cell5 c1 fr1.2.1)
      have va2 : a2.i32ArrayViews = [] := (pa2.views.trans pa1.views).trans fr1.2.2.2.1
      have wa2 : a2.world = E.world := (pa2.world.trans pa1.world).trans fr1.2.2.1
      -- the last part: increment, the frame of the body's final state, and the invariant
      have finish : ∀ (A : State) (k' : Nat), FreshCellFrame E A → A.locals = a2.locals →
          A.world = E.world → A.i32ArrayViews = [] → A.cellId? 4 = some E.nextCell →
          A.cellId? 5 = some (E.nextCell + 1) → A.local? 5 = some (.signed .i32 (Int.ofNat k)) →
          A.local? 4 = some (out (k + 1)) → HeapInv (k + 1) A.heap →
          ∃ A', RunsStmt P A (increment 5) .next A' ∧ measure (restoreLocals a1 A') < measure s ∧
            Frame (restoreLocals a1 A') ∧ (restoreLocals a1 A').local? 5 = some (.signed .i32 (k + 1 : Nat)) ∧
            (restoreLocals a1 A').local? 4 = some (out (k + 1)) ∧ HeapInv (k + 1) (restoreLocals a1 A').heap :=
        fun A _ frameA localsA worldA viewsA cA4 cA5 a5 a4 inv => by
          obtain ⟨A', run5, frame', locals', heap', world', views', a5', keep⟩ :=
            bump grow.vec.target fE frameA (by omega) cA5 (Nat.le_succ _) a5
          have a4' := keep 4 _ (by rw [cA4]; intro h; exact Nat.ne_of_lt (Nat.lt_succ_self _) (Option.some.inj h)) a4
          let X := restoreLocals a1 A'
          have cX : ∀ id, id ≠ 6 → X.cellId? id = A'.cellId? id := fun id ne => by
            show a1.cellId? id = A'.cellId? id
            have l' : A'.cellId? id = a2.cellId? id := by unfold State.cellId?; rw [locals', localsA]
            rw [l', cellsA2 id ne]
            unfold State.cellId?; rw [pa1.locals]
          have frameX : FreshCellFrame E X := by obtain ⟨e, c, nx, fx⟩ := frame'; exact ⟨e, c, nx, fx⟩
          have x5 : X.local? 5 = some (.signed .i32 (k + 1 : Nat)) :=
            (local?_congr (s := X) (t := A') rfl (cX 5 (by decide))).trans a5'
          refine ⟨A', run5, ?_, ⟨frameX, pa1.locals.trans fr1.2.1, world'.trans worldA, views'.trans viewsA,
              FreshCellFrame.after_cellsWellFormed fE frameX⟩, x5,
            (local?_congr (s := X) (t := A') rfl (cX 4 (by decide))).trans a4', by
              show HeapInv (k + 1) A'.heap; rw [heap']; exact inv⟩
          show n - counter 5 X < n - counter 5 s
          rw [counter_eq x5, counter_eq idx]; omega
      have step := filter_take_step pred xs kn
      cases good : pred xs[k] with
      | true =>
          have isTrue : (ys.any (eqv · xs[k]) == present) = true := good
          rw [isTrue] at test
          rw [good, if_pos rfl] at step
          have more := filter_take_le pred xs (k + 1)
          rw [step, List.length_append] at more
          have roomK : (acc ++ W k).length < m := by
            rw [List.length_append]
            have : (whereIn eqv ys present xs).length = (xs.filter pred).length := rfl
            simp only [List.length_singleton] at more
            show acc.length + ((xs.take k).filter pred).length < m
            omega
          obtain ⟨R, pushRun, cellsR, worldR, viewsR, pushed⟩ := tryPush_room_spec grow kind (caller := a2) fa2
            (by rw [h2]; exact repK) roomK (stores _ (List.getElem_mem _)) (by rw [h2]; exact belowK)
            (by rw [h2]; exact uniqueK) va2
          let nv := Value.structure ids.vec [.pointer q, .signed .i32 ((acc ++ W k) ++ [xs[k]]).length,
            .signed .i32 m]
          have right := callArgs (RunsExprs.two (RunsExpr.local' a2_4) (RunsExpr.local' a2_6)) pushRun
          have rLocals : R.locals = a2.locals := right.choose_spec.2
          obtain ⟨A, assignRun, assigned, effectA⟩ := RunsExpr.assignCellAfter (before := a2) c4
            (cellEntry_of_local a2 4 _ (out k) c4 a2_4) right (Or.inr (viewsR.trans va2))
          have cR4 : R.cellId? 4 = some E.nextCell := by unfold State.cellId? at c4 ⊢; rw [rLocals]; exact c4
          have cellA := assignLocal_assignCell 4 E.nextCell nv cR4 assigned
          have frameR : FreshCellFrame E R := frameA2.trans cellsR
          obtain ⟨frameA, localsA, heapA, worldA, viewsA⟩ := FreshCellFrame.assignFresh fE
            (FreshCellFrame.after_cellsWellFormed fE frameR) frameR (Nat.le_refl _) cellA
          have cA : ∀ id, A.cellId? id = a2.cellId? id := fun id => by
            unfold State.cellId?; rw [localsA, rLocals]
          have r5 : R.local? 5 = some (.signed .i32 k) := cellsR.localFound rLocals 5 _ a2_5
          have aA5 : A.local? 5 = some (.signed .i32 (Int.ofNat k)) :=
            assignCell_preserves_other_local_of_cellId 5 E.nextCell nv cellA r5
              (by unfold State.cellId? at c5 ⊢; rw [rLocals]; rw [c5]; intro h
                  exact Nat.ne_of_gt (Nat.lt_succ_self _) (Option.some.inj h))
          have aA4 : A.local? 4 = some nv := assignLocal_finds_assigned 4 E.nextCell nv cR4 assigned
          obtain ⟨repP, keptP, belowP, uniqueP, apartP, _⟩ := pushed
          have listEq : (acc ++ W k) ++ [xs[k]] = acc ++ W (k + 1) := by
            show (acc ++ W k) ++ [xs[k]] = acc ++ (xs.take (k + 1)).filter pred
            rw [step, List.append_assoc]
          have inv : HeapInv (k + 1) A.heap := by
            rw [heapA]
            rw [h2] at keptP apartP
            refine ⟨?_, keptK.trans keptP, belowP, uniqueP, apartP apartK⟩
            show VecRep P T size ids.vec R.heap
              (.structure ids.vec [.pointer q, .signed .i32 (acc ++ W (k + 1)).length, .signed .i32 m])
              (acc ++ W (k + 1))
            rw [← listEq]; exact repP
          have nvEq : nv = out (k + 1) := by
            show Value.structure ids.vec [.pointer q, .signed .i32 ((acc ++ W k) ++ [xs[k]]).length, .signed .i32 m] =
              .structure ids.vec [.pointer q, .signed .i32 (acc ++ W (k + 1)).length, .signed .i32 m]
            rw [listEq]
          rw [nvEq] at aA4
          obtain ⟨A', run5, less, frX, x5, x4, invX⟩ := finish A (k + 1) frameA (localsA.trans rLocals)
            (worldA.trans (worldR.trans wa2)) (viewsA.trans (viewsR.trans va2)) ((cA 4).trans c4)
            ((cA 5).trans c5) aA5 aA4 inv
          obtain ⟨bodyThreshold, bodyStable, _⟩ : RunsStmt P c1 body .next (restoreLocals a1 A') :=
            RunsStmt.letLocal atCall (RunsStmt.sequenceNext
              (RunsStmt.ifThenElseTrue test (RunsStmt.expression assignRun)) run5)
          exact ⟨condThreshold, bodyThreshold, c1, .next, restoreLocals a1 A', condStable, bodyStable,
            fun h => absurd rfl h.1, fun _ => ⟨less, k + 1, kn, frX, x5, x4, invX⟩⟩
      | false =>
          have isFalse : (ys.any (eqv · xs[k]) == present) = false := good
          rw [isFalse] at test
          rw [good] at step
          have same : W (k + 1) = W k := by
            show (xs.take (k + 1)).filter pred = (xs.take k).filter pred
            rw [step]; simp
          have outEq : out (k + 1) = out k := by
            show Value.structure ids.vec [.pointer q, .signed .i32 (acc ++ W (k + 1)).length, .signed .i32 m] =
              .structure ids.vec [.pointer q, .signed .i32 (acc ++ W k).length, .signed .i32 m]
            rw [same]
          have inv : HeapInv (k + 1) a2.heap := by
            rw [h2]
            show VecRep P T size ids.vec s.heap (out (k + 1)) (acc ++ W (k + 1)) ∧ _
            rw [outEq, same]
            exact ⟨repK, keptK, belowK, uniqueK, apartK⟩
          obtain ⟨A', run5, less, frX, x5, x4, invX⟩ := finish a2 (k + 1) frameA2 rfl wa2 va2 c4 c5 a2_5
            (by rw [outEq]; exact a2_4) inv
          obtain ⟨bodyThreshold, bodyStable, _⟩ : RunsStmt P c1 body .next (restoreLocals a1 A') :=
            RunsStmt.letLocal atCall (RunsStmt.sequenceNext
              (RunsStmt.ifThenElseFalse test (RunsStmt.skip P a2)) run5)
          exact ⟨condThreshold, bodyThreshold, c1, .next, restoreLocals a1 A', condStable, bodyStable,
            fun h => absurd rfl h.1, fun _ => ⟨less, k + 1, kn, frX, x5, x4, invX⟩⟩ }
  -- the entry of the loop
  have w0 : W 0 = [] := rfl
  have out0 : out 0 = vo := by
    show Value.structure ids.vec [.pointer q, .signed .i32 (acc ++ W 0).length, .signed .i32 m] = vo
    rw [w0, List.append_nil]
  have entryFrame : Frame E5 := ⟨(FreshCellFrame.bindLocal E 4 _).trans (FreshCellFrame.bindLocal _ 5 _),
    rfl, rfl, noViews, fE5⟩
  have e4 : E5.local? 4 = some (out 0) := by
    rw [out0]; exact local_kept fE4 _ (by decide) (local_bound fE 4 _)
  have inv0 : HeapInv 0 E5.heap := by
    show VecRep P T size ids.vec caller.heap (out 0) (acc ++ W 0) ∧ _
    rw [out0, w0, List.append_nil]
    exact ⟨repO, ⟨fun _ _ _ => fun _ _ _ _ _ read => read, fun _ _ _ _ buffer => buffer⟩, below, unique, apart⟩
  obtain ⟨threshold, completion, after, loopStable, done⟩ :=
    executeTotalWhile measure P _ _ oracle E5 ⟨0, Nat.zero_le _, entryFrame, local_bound fE4 5 _, e4, inv0⟩
  obtain ⟨frA, rfl, itemsA, invA⟩ := done
  have loopRun : RunsStmt P E5 _ .next after := ⟨threshold, loopStable, frA.2.1⟩
  have whole : W n = whereIn eqv ys present xs := by
    show (xs.take xs.length).filter pred = xs.filter pred
    rw [List.take_length]
  have outN : out n = .structure ids.vec [.pointer q, .signed .i32 (acc ++ whereIn eqv ys present xs).length,
      .signed .i32 m] := by
    show Value.structure ids.vec [.pointer q, .signed .i32 (acc ++ W n).length, .signed .i32 m] = _
    rw [whole]
  rw [outN] at itemsA
  obtain ⟨repA, keptA, belowA, uniqueA, apartA⟩ := invA
  rw [outN, whole] at repA
  have seqRun := RunsStmt.sequenceNext loopRun (RunsStmt.returnValue (RunsExpr.local' itemsA))
  have inner := RunsStmt.letLocal (type := i32Ty) (RunsExpr.value' (.signed .i32 0)) seqRun
  have outer := RunsStmt.letLocal (type := vecTy ids) (RunsExpr.local' l0) inner
  let X := restoreLocals E (restoreLocals E4 after)
  have frameX : FreshCellFrame E X := by obtain ⟨e, c, nx, fx⟩ := frA.1; exact ⟨e, c, nx, fx⟩
  obtain ⟨final, call, cellsF, worldF, viewsF, repF, keptF, belowF, uniqueF, apartF⟩ := Grow.call
    (vs := [vo, .structure sid [vvL], .structure sid [vvR], .boolean present])
    (bindings := [(0, vo), (1, .structure sid [vvL]), (2, .structure sid [vvR]), (3, .boolean present)])
    (Q := fun H => VecRep P T size ids.vec H
        (.structure ids.vec [.pointer q, .signed .i32 (acc ++ whereIn eqv ys present xs).length, .signed .i32 m])
        (acc ++ whereIn eqv ys present xs) ∧
      Kept caller.heap H q (size * m) ∧ HeapBlocksBelowNext H ∧ HeapBlockBasesUnique H ∧ HeapApart H) found rfl rfl
    ⟨X, outer, ⟨fE, frameX, frA.2.2.1, frA.2.2.2.1.trans noViews.symm⟩, repA, keptA, belowA, uniqueA, apartA⟩
  exact ⟨final, call, cellsF, worldF, viewsF, repF, keptF, belowF, uniqueF, apartF⟩

#print axioms setAppendWhere_spec

end Lanius.Std
