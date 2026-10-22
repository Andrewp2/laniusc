import Lanius.Std.VecEdge

/-! # The shift-up loop and `try_insert`

`while (cursor > index) { items[cursor] = items[cursor - 1]; cursor -= 1; }`
from `cursor = value.length` moves the elements from `index` on up by one;
then `items[index] = item`. A full vector first grows as in `try_push`. -/

namespace Lanius.Std

open Lanius Lanius.Core Lanius.Semantics Lanius.Memory

variable {P : Program} {T : Ty} {ids : VecIds} {g : GrowIds} {size : Nat}

/-- `index = index - 1;`, as the front end reads `index -= 1;`. -/
def decrement (idx : VarId) : Stmt :=
  .expression (.assign .set (.local idx) (.binary .subtract (.local idx) (int 1)))

theorem decrement_bound (target : P.target = Target.x86_64) {S : State} (formed : S.CellsWellFormed)
    (idx : VarId) {k : Nat} (positive : 0 < k) (small : k < 2 ^ 31) :
    RunsStmt P (S.bindLocal idx (.signed .i32 k)) (decrement idx) .next
      (S.bindLocal idx (.signed .i32 ((k - 1 : Nat) : Int))) := by
  have diff : evalBinaryValue P.target .subtract (.signed .i32 (k : Int)) (.signed .i32 1) =
      .ok (.signed .i32 ((k - 1 : Nat) : Int)) := by
    rw [target, eval_i32_sub (by omega) (by omega)]
    congr 2; omega
  obtain ⟨threshold, run, locals⟩ := RunsExpr.binary (program := P)
    (RunsExpr.local' (local_bound formed idx (.signed .i32 k))) (RunsExpr.value' (.signed .i32 1)) (by decide) diff
  have assigned := bindLocal_assignLocal formed idx (.signed .i32 k) (.signed .i32 ((k - 1 : Nat) : Int))
  refine RunsStmt.expression (RunsExpr.ofStable
    (Lanius.Extraction.CertificateEmitterFrame.StableExpr.assignSetLocal P _ idx _ _ _ _ _ _
      (bindLocal_cellId _ _ _) (local_bound formed idx _) run rfl assigned rfl rfl) ?_)
  exact (assignLocal_preserves_frame (protectedId := idx) assigned).1

/-- The shift-up loop, with `cursor`, `index` and `items` the locals `idx`,
`ix` and `items`. -/
def shiftUpLoop (idx ix items : VarId) : Stmt :=
  .whileLoop (.binary .greater (.local idx) (.local ix))
    (.sequence (.expression (.assign .set (.index (.local items) (.local idx))
        (.index (.local items) (.binary .subtract (.local idx) (int 1)))))
      (decrement idx))

/-- Which element slot `j` holds after `k` steps down from `len`. -/
def raisedFrom (len k j : Nat) : Nat := if len - k < j then j - 1 else j

def RaiseInv (P : Program) (T : Ty) (size : Nat) (S : State) (idx : VarId) (xs : List Value)
    (p cap k : Nat) (st : State) : Prop :=
  ∃ h, st = ({ S with heap := h } : State).bindLocal idx (.signed .i32 ((xs.length - k : Nat) : Int)) ∧
    HeapRegionWrite S.heap h p (size * cap) ∧
    ∀ j, j ≤ xs.length → ¬(k = 0 ∧ j = xs.length) → ∀ other : State,
      ReadsWithin h other.heap (slotLo T size p cap j) size →
        readRawSliceIndex P other T (viewAddr T size p cap) cap j = .ok (xs.getD (raisedFrom xs.length k j) .unit)

theorem shift_up_loop_spec (target : P.target = Target.x86_64) (kind : ElemKind P T size)
    {S : State} (formed : S.CellsWellFormed) {idx ix items : VarId}
    (ixLocal : idx ≠ ix) (itemsLocal : idx ≠ items) {i : Nat}
    (ixFound : S.local? ix = some (.signed .i32 i)) {xs : List Value}
    {p cap : Nat} (itemsFound : S.local? items = some (.rawSlice T (viewAddr T size p cap) cap))
    (room : xs.length < cap) (capBound : cap < 2 ^ 31) (inside : i ≤ xs.length)
    (reads : ∀ j (inside : j < xs.length) (other : State),
      ReadsWithin S.heap other.heap (slotLo T size p cap j) size →
        readRawSliceIndex P other T (viewAddr T size p cap) cap j = .ok xs[j])
    (buffer : 0 < cap → Buffer S.heap p (size * cap)) (stores : ∀ x ∈ xs, ElemStore P T size x)
    (noViews : S.i32ArrayViews = []) (unique : HeapBlockBasesUnique S.heap) :
    ∃ h', RunsStmt P (S.bindLocal idx (.signed .i32 xs.length)) (shiftUpLoop idx ix items) .next
        (({ S with heap := h' } : State).bindLocal idx (.signed .i32 i)) ∧
      HeapRegionWrite S.heap h' p (size * cap) ∧
      ∀ j, j ≤ xs.length → j ≠ i → ∀ other : State,
        ReadsWithin h' other.heap (slotLo T size p cap j) size →
          readRawSliceIndex P other T (viewAddr T size p cap) cap j =
            .ok (xs.getD (if i < j then j - 1 else j) .unit) := by
  let n := xs.length
  let st : Heap → Nat → State := fun h k => ({ S with heap := h } : State).bindLocal idx (.signed .i32 k)
  have fS : ∀ h : Heap, ({ S with heap := h } : State).CellsWellFormed := fun _ => formed
  have idxAt : ∀ h k, (st h k).local? idx = some (.signed .i32 (Int.ofNat k)) := fun h _ => local_bound (fS h) idx _
  have ixAt : ∀ h k, (st h k).local? ix = some (.signed .i32 i) := fun h _ => local_kept (fS h) _ ixLocal ixFound
  have itemsAt : ∀ h k, (st h k).local? items = some (.rawSlice T (viewAddr T size p cap) cap) :=
    fun h _ => local_kept (fS h) _ itemsLocal itemsFound
  have condAt : ∀ h k, RunsExpr P (st h k) (.binary .greater (.local idx) (.local ix))
      (.boolean (decide ((k : Int) > i))) (st h k) := fun h k =>
    RunsExpr.binary (RunsExpr.local' (idxAt h k)) (RunsExpr.local' (ixAt h k)) (by decide) (eval_i32_gt _ _ _)
  let N := xs.length - i
  let measure : State → Nat := fun s => counter idx s
  let spec : CountdownWhileSpec measure P (.binary .greater (.local idx) (.local ix))
      (.sequence (.expression (.assign .set (.index (.local items) (.local idx))
          (.index (.local items) (.binary .subtract (.local idx) (int 1)))))
        (decrement idx)) N := {
    Inv := RaiseInv P T size S idx xs p cap
    Done := fun completion s => completion = .next ∧ RaiseInv P T size S idx xs p cap N s
    terminal := by
      intro s invariant
      obtain ⟨h, rfl, rest⟩ := invariant
      have run := condAt h (xs.length - N)
      rw [show decide (((xs.length - N : Nat) : Int) > i) = false by simp; omega] at run
      obtain ⟨threshold, stable, _⟩ := run
      exact ⟨threshold, _, stable, rfl, h, rfl, rest⟩
    step := by
      intro k s kLt invariant
      obtain ⟨h, rfl, effect, done⟩ := invariant
      let cur := xs.length - k
      have curPos : 0 < cur := by omega
      have curAbove : i < cur := by omega
      have run := condAt h cur
      rw [show decide ((cur : Int) > i) = true by simp; omega] at run
      obtain ⟨condThreshold, condStable, _⟩ := run
      -- read items[cursor - 1]
      have prevValue : xs.getD (raisedFrom xs.length k (cur - 1)) .unit = xs[cur - 1]'(by omega) := by
        rw [show raisedFrom xs.length k (cur - 1) = cur - 1 by simp [raisedFrom]; omega]
        exact getD_of_lt (by omega)
      have prevRead : readRawSliceIndex P (st h cur) T (viewAddr T size p cap) cap (cur - 1) =
          .ok (xs[cur - 1]'(by omega)) := by
        rw [← prevValue]; exact done (cur - 1) (by omega) (by omega) _ (ReadsWithin.refl _ _ _)
      have prevIndex := RunsExpr.binary (operation := .subtract) (RunsExpr.local' (idxAt h cur))
        (RunsExpr.value' (P := P) (S := st h cur) (.signed .i32 1)) (by decide)
        (by rw [target]; exact eval_i32_sub (by simp only [Int.ofNat_eq_natCast]; omega) (by simp only [Int.ofNat_eq_natCast]; omega))
      rw [show Int.ofNat cur - 1 = Int.ofNat (cur - 1) by simp; omega] at prevIndex
      obtain ⟨_, prevStable, _⟩ := prevIndex
      have right := StableExpr.rawSliceIndexAt (itemsAt h cur) prevStable prevRead
      -- store it into items[cursor]
      have curCap : cur < cap := by omega
      have slot := slot_inside (T := T) (size := size) (p := p) curCap
      have bufferH : Buffer h p (size * cap) := (buffer (by omega)).afterWrite effect
      let base := elemBase T size p cap cur
      have slotEq : slotOf T size base = slotLo T size p cap cur := slotOf_elemBase kind.size_eight
      have readable : h.Readable (slotOf T size base) size := by
        rw [slotEq]
        have within := slot
        unfold slotLo at within ⊢
        exact bufferH.2.1.subrange (start := size * slotIndex T cap cur) (by omega)
      have roomBase : size ≤ base + 8 := by
        show size ≤ elemBase T size p cap cur + 8
        unfold elemBase
        by_cases scalar : T = i32Ty
        · rw [if_pos scalar, kind.i32_size scalar]; omega
        · rw [if_neg scalar]; have := kind.size_eight scalar; omega
      obtain ⟨h'', stored, readBack, written⟩ :=
        stores (xs[cur - 1]'(by omega)) (List.getElem_mem _) (st h cur) h base roomBase readable effect.unique
      rw [slotEq] at written
      have assign := StableExpr.assignRaw (before := st h cur) (indexed := st h cur) (ready := st h cur)
        (heap := h'') (sourceId := items) (itemsAt h cur) (StableExpr.local (idxAt h cur)) curCap
        (elementAddress kind curCap) (show (st h cur).i32ArrayViews = [] from noViews) right stored
      have bodyRun : RunsStmt P (st h cur)
          (.sequence (.expression (.assign .set (.index (.local items) (.local idx))
              (.index (.local items) (.binary .subtract (.local idx) (int 1)))))
            (decrement idx)) .next (st h'' (cur - 1)) :=
        RunsStmt.sequenceNext (RunsStmt.expression (RunsExpr.ofStable assign rfl))
          (decrement_bound target (fS h'') idx curPos (by omega))
      obtain ⟨bodyThreshold, bodyStable, _⟩ := bodyRun
      refine ⟨condThreshold, bodyThreshold, _, _, condStable, bodyStable, ?_, ?_⟩
      · show counter idx (st h'' (cur - 1)) < counter idx (st h cur)
        rw [counter_eq (idxAt h'' (cur - 1)), counter_eq (idxAt h cur)]; omega
      · refine ⟨h'', by rw [show xs.length - (k + 1) = cur - 1 by omega],
          effect.trans (written.enlarge slot.1 slot.2), ?_⟩
        intro j jLe notLast other within
        by_cases same : j = cur
        · subst same
          rw [readRawSliceIndex_elem other kind curCap,
            show raisedFrom xs.length (k + 1) (xs.length - k) = xs.length - k - 1 by simp [raisedFrom]; omega,
            getD_of_lt (by omega)]
          exact readBack other.heap (by rw [slotEq]; exact within)
        · rw [show raisedFrom xs.length (k + 1) j = raisedFrom xs.length k j by
            unfold raisedFrom
            by_cases h1 : xs.length - k < j
            · rw [if_pos h1, if_pos (by omega)]
            · rw [if_neg h1, if_neg (by omega)]]
          exact done j jLe (by omega) other (ReadsWithin.trans
            (HeapRegionWrite.readsApart written (slots_apart curCap (by omega) (fun e => same e.symm))) within) }
  obtain ⟨threshold, completion, after, run, done⟩ :=
    executeTotalWhile measure P _ _ (countdownWhileOracle measure P _ _ N spec)
      (S.bindLocal idx (.signed .i32 xs.length))
      ⟨0, Nat.zero_le _, S.heap, rfl, HeapRegionWrite.refl _ unique, fun j jLe notLast other within => by
        have jLt : j < xs.length := by omega
        rw [show raisedFrom xs.length 0 j = j by simp [raisedFrom]; omega, getD_of_lt jLt]
        exact reads j jLt other within⟩
  obtain ⟨rfl, h', rfl, effect, raised⟩ := done
  rw [show xs.length - N = i by omega] at run
  refine ⟨h', ⟨threshold, run, rfl⟩, effect, fun j jLe notI other within => ?_⟩
  have read := raised j jLe (by omega) other within
  rw [show raisedFrom xs.length N j = (if i < j then j - 1 else j) by
    unfold raisedFrom; rw [show xs.length - N = i by omega]] at read
  exact read

#print axioms shift_up_loop_spec

/-! ## `try_insert` -/

section templates
variable (ids : VecIds) (g : GrowIds) (T : Ty)

/-- The end of `try_insert`, with `value`, `index`, `item`, `grown`,
`target`, `items` and `cursor` the locals 0 to 6. -/
def insertTail : Stmt :=
  .letLocal 5 (.slice T) (.call ids.slots [.local 3])
  (.letLocal 6 i32Ty (.field (.local 3) 1)
  (.sequence (shiftUpLoop 6 1 5)
  (.sequence (.expression (.assign .set (.index (.local 5) (.local 1)) (.local 2)))
    (.returnValue (some (.structValue ids.vec
      [.field (.local 3) 0, .binary .add (.field (.local 3) 1) (int 1), .field (.local 3) 2]))))))

/-- `pub fn try_insert<T>(value: Vec<T>, index: i32, item: T) -> Vec<T>` -/
def tryInsertFn (f : FunctionId) : Function where
  id := f
  parameters := [(0, vecTy ids), (1, i32Ty), (2, T)]
  returnType := vecTy ids
  body := some <|
    guardReturn (.binary .logicalOr
        (.binary .logicalOr (.binary .less (.local 1) (int 0)) (.binary .greater (.local 1) (.field (.local 0) 1)))
        (.binary .equal (.field (.local 0) 1) (int 2147483647))) (.local 0)
    (.letLocal 3 (vecTy ids) (.local 0)
    (.sequence
      (.ifThenElse (.binary .equal (.field (.local 3) 1) (.field (.local 3) 2))
        (.letLocal 4 i32Ty (.call g.grownCapacity [.local 3, .binary .add (.field (.local 3) 1) (int 1)])
          (.sequence (.expression (.assign .set (.local 3) (.call g.tryReserve [.local 3, .local 4])))
            (.ifThenElse (.binary .equal (.field (.local 3) 1) (.field (.local 3) 2))
              (.returnValue (some (.local 0))) .skip)))
        .skip)
    (insertTail ids T)))

end templates

/-- The end of `try_insert`: local 3 is a vector with room, local 1 the
index and local 2 the item. -/
theorem insertTail_spec (inst : VecInstance P T ids) (kind : ElemKind P T size) {Y : State}
    (formed : Y.CellsWellFormed) {xs : List Value} {q m i : Nat} {x : Value}
    (rep : VecRep P T size ids.vec Y.heap
      (.structure ids.vec [.pointer q, .signed .i32 xs.length, .signed .i32 m]) xs)
    (room : xs.length < m) (inside : i ≤ xs.length)
    (l3 : Y.local? 3 = some (.structure ids.vec [.pointer q, .signed .i32 xs.length, .signed .i32 m]))
    (l1 : Y.local? 1 = some (.signed .i32 i)) (l2 : Y.local? 2 = some x) (store : ElemStore P T size x)
    (stores : ∀ y ∈ xs, ElemStore P T size y)
    (noViews : Y.i32ArrayViews = []) (unique : HeapBlockBasesUnique Y.heap) :
    Grow P Y (insertTail ids T)
      (.returned (some (.structure ids.vec [.pointer q, .signed .i32 (xs.insertIdx i x).length, .signed .i32 m])))
      (fun h => VecRep P T size ids.vec h
          (.structure ids.vec [.pointer q, .signed .i32 (xs.insertIdx i x).length, .signed .i32 m])
          (xs.insertIdx i x) ∧ HeapRegionWrite Y.heap h q (size * m)) := by
  have target := inst.target
  obtain ⟨_, _, capBound, buffer, reads⟩ := rep.fields
  have lenIns : (xs.insertIdx i x).length = xs.length + 1 := List.length_insertIdx_of_le_length inside x
  let vv := Value.structure ids.vec [.pointer q, .signed .i32 xs.length, .signed .i32 m]
  obtain ⟨S5, slots, frame⟩ := slots_call inst kind formed l3 capBound buffer
  have fS : S5.CellsWellFormed := frame.afterFormed
  let view := Value.rawSlice T (viewAddr T size q m) m
  let B := S5.bindLocal 5 view
  have fB : B.CellsWellFormed := fS.bindLocal _ _
  have hB : B.heap = Y.heap := frame.heap
  have b5 : B.local? 5 = some view := local_bound fS 5 _
  have b3 : B.local? 3 = some vv := local_kept fS _ (by decide) (frame.localFound l3)
  have b1 : B.local? 1 = some (.signed .i32 i) := local_kept fS _ (by decide) (frame.localFound l1)
  have b2 : B.local? 2 = some x := local_kept fS _ (by decide) (frame.localFound l2)
  obtain ⟨h1, loopRun, effect1, raised⟩ := shift_up_loop_spec target kind fB (idx := 6) (ix := 1) (items := 5)
    (by decide) (by decide) b1 b5 room capBound inside
    (fun j jInside other within => reads j jInside other (by rw [hB] at within; exact within))
    (fun positive => by rw [hB]; exact buffer positive) stores (frame.views.trans noViews)
    (by rw [hB]; exact unique)
  rw [hB] at effect1
  -- items[index] = item
  let W := ({ B with heap := h1 } : State).bindLocal 6 (.signed .i32 i)
  have fW0 : ({ B with heap := h1 } : State).CellsWellFormed := fB
  have fW : W.CellsWellFormed := fW0.bindLocal _ _
  have w5 : W.local? 5 = some view := local_kept fW0 _ (by decide) b5
  have w3 : W.local? 3 = some vv := local_kept fW0 _ (by decide) b3
  have w1 : W.local? 1 = some (.signed .i32 (Int.ofNat i)) := local_kept fW0 _ (by decide) b1
  have w2 : W.local? 2 = some x := local_kept fW0 _ (by decide) b2
  have hcap : i < m := by omega
  let base := elemBase T size q m i
  have slotEq : slotOf T size base = slotLo T size q m i := slotOf_elemBase kind.size_eight
  have slot := slot_inside (T := T) (size := size) (p := q) hcap
  have readable : h1.Readable (slotOf T size base) size := by
    rw [slotEq]
    have within := slot
    unfold slotLo at within ⊢
    exact ((buffer (by omega)).afterWrite effect1).2.1.subrange (start := size * slotIndex T m i) (by omega)
  have roomBase : size ≤ base + 8 := by
    show size ≤ elemBase T size q m i + 8
    unfold elemBase
    by_cases scalar : T = i32Ty
    · rw [if_pos scalar, kind.i32_size scalar]; omega
    · rw [if_neg scalar]; have := kind.size_eight scalar; omega
  obtain ⟨h2, stored, readBack, written⟩ := store W h1 base roomBase readable effect1.unique
  rw [slotEq] at written
  have assign := StableExpr.assignRaw (before := W) (indexed := W) (ready := W) (heap := h2) (sourceId := 5)
    w5 (StableExpr.local w1) hcap (elementAddress kind hcap) (show W.i32ArrayViews = [] from frame.views.trans noViews)
    (StableExpr.local w2) stored
  let C : State := { W with heap := h2 }
  have c3 : C.local? 3 = some vv := w3
  have bump := RunsExpr.binary (operation := .add) (RunsExpr.field' (j := 1) (RunsExpr.local' c3) rfl)
    (RunsExpr.value' (P := P) (S := C) (.signed .i32 1)) (by decide)
    (by rw [target]; exact eval_i32_add (by omega) (by omega))
  rw [show (xs.length : Int) + 1 = ((xs.insertIdx i x).length : Int) by rw [lenIns]; omega] at bump
  have ret : RunsStmt P W (.sequence (.expression (.assign .set (.index (.local 5) (.local 1)) (.local 2)))
      (.returnValue (some (.structValue ids.vec
        [.field (.local 3) 0, .binary .add (.field (.local 3) 1) (int 1), .field (.local 3) 2]))))
      (.returned (some (.structure ids.vec [.pointer q, .signed .i32 (xs.insertIdx i x).length, .signed .i32 m]))) C :=
    RunsStmt.sequenceNext (RunsStmt.expression (RunsExpr.ofStable assign rfl))
      (RunsStmt.returnValue (RunsExprs.toRun (RunsExprs.three (RunsExpr.field' (j := 0) (RunsExpr.local' c3) rfl)
        bump (RunsExpr.field' (j := 2) (RunsExpr.local' c3) rfl))))
  have inner := RunsStmt.letLocal (type := i32Ty) (RunsExpr.field' (j := 1) (RunsExpr.local' b3) rfl)
    (RunsStmt.sequenceNext loopRun ret)
  refine ⟨_, RunsStmt.letLocal slots inner,
    (((Ext.ofPure frame).trans (Ext.bindLocal fS 5 view)).trans
      ((((Ext.heap fB h1).trans (Ext.bindLocal fW0 6 _)).trans (Ext.heap fW h2)).restore B)).restore S5, ?_,
    effect1.trans (written.enlarge slot.1 slot.2)⟩
  refine ⟨q, m, rfl, by omega, capBound, fun positive => ((buffer positive).afterWrite effect1).afterWrite written, ?_⟩
  intro j jInside other within
  rw [lenIns] at jInside
  have jm : j < m := by omega
  by_cases same : j = i
  · subst same
    rw [List.getElem_insertIdx_self, readRawSliceIndex_elem other kind hcap]
    exact readBack other.heap (by rw [slotEq]; exact within)
  · have read := raised j (by omega) same other (ReadsWithin.trans
      (HeapRegionWrite.readsApart written (slots_apart hcap jm (fun e => same e.symm))) within)
    by_cases low : j < i
    · rw [List.getElem_insertIdx_of_lt low, ← getD_of_lt (by omega)]
      rw [if_neg (by omega)] at read; exact read
    · rw [List.getElem_insertIdx_of_gt (by omega), ← getD_of_lt (by omega)]
      rw [if_pos (by omega)] at read; exact read

/-- The arguments of `try_insert`. -/
abbrev insertArgs (ids : VecIds) (p len cap i : Nat) (x : Value) : List Expr :=
  [Value.structure ids.vec [.pointer p, .signed .i32 len, .signed .i32 cap], .signed .i32 i, x].map Expr.value

theorem insertGuard_run {S : State} {vec : TypeId} {ptr cap : Value} {len i : Nat}
    (l0 : S.local? 0 = some (.structure vec [ptr, .signed .i32 len, cap]))
    (l1 : S.local? 1 = some (.signed .i32 i)) (inside : i ≤ len) (small : len < 2147483647) :
    RunsExpr P S (.binary .logicalOr
        (.binary .logicalOr (.binary .less (.local 1) (int 0)) (.binary .greater (.local 1) (.field (.local 0) 1)))
        (.binary .equal (.field (.local 0) 1) (int 2147483647))) (.boolean false) S := by
  have r := RunsExpr.logicalOrBool (P := P)
    (RunsExpr.logicalOrBool (RunsExpr.binary (RunsExpr.local' l1) (RunsExpr.value' (.signed .i32 0)) (by decide)
        (eval_i32_lt _ _ _))
      (RunsExpr.binary (RunsExpr.local' l1) (RunsExpr.field' (j := 1) (RunsExpr.local' l0) rfl) (by decide)
        (eval_i32_gt _ _ _)))
    (RunsExpr.binary (RunsExpr.field' (j := 1) (RunsExpr.local' l0) rfl) (RunsExpr.value' (.signed .i32 2147483647))
      (by decide) (eval_i32_eq _ _ _))
  rw [show (decide ((i : Int) < 0) || decide ((i : Int) > len) || ((len : Int) == 2147483647)) = false by
    simp only [Bool.or_eq_false_iff, decide_eq_false_iff_not, beq_eq_false_iff_ne]; omega] at r
  exact r

/-- `try_insert(v, i, x)` with `i ≤ len(v) < capacity(v)`: shifted and
stored in place. -/
theorem tryInsert_room_spec (inst : VecInstance P T ids) (kind : ElemKind P T size)
    {f : FunctionId} (found : P.function? f = some (tryInsertFn ids g T f))
    {caller : State} (formed : caller.CellsWellFormed) {xs : List Value} {p cap : Nat}
    (rep : VecRep P T size ids.vec caller.heap
      (.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]) xs)
    (room : xs.length < cap) {i : Nat} (inside : i ≤ xs.length) {x : Value} (store : ElemStore P T size x)
    (stores : ∀ y ∈ xs, ElemStore P T size y)
    (below : HeapBlocksBelowNext caller.heap) (unique : HeapBlockBasesUnique caller.heap)
    (noViews : caller.i32ArrayViews = []) :
    ∃ after, RunsExpr P caller (.call f (insertArgs ids p xs.length cap i x))
      (.structure ids.vec [.pointer p, .signed .i32 (xs.insertIdx i x).length, .signed .i32 cap]) after ∧
      FreshCellFrame caller after ∧ after.world = caller.world ∧
      after.i32ArrayViews = caller.i32ArrayViews ∧
      Pushed P T size ids.vec caller.heap p cap p cap (xs.insertIdx i x) after.heap := by
  obtain ⟨_, _, capBound, _, _⟩ := rep.fields
  let vv := Value.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]
  refine Grow.call (vs := [vv, .signed .i32 i, x])
    (Q := Pushed P T size ids.vec caller.heap p cap p cap (xs.insertIdx i x)) found rfl rfl ?_
  let E0 : State := { caller with locals := [] }
  have f0 : E0.CellsWellFormed := formed
  have f1 := f0.bindLocal 0 vv
  have f2 := f1.bindLocal 1 (.signed .i32 i)
  let E := ((E0.bindLocal 0 vv).bindLocal 1 (.signed .i32 i)).bindLocal 2 x
  change Grow P E _ _ _
  have fE : E.CellsWellFormed := f2.bindLocal _ _
  have l2 : E.local? 2 = some x := local_bound f2 2 _
  have l1 : E.local? 1 = some (.signed .i32 i) := local_kept f2 _ (by decide) (local_bound f1 1 _)
  have l0 : E.local? 0 = some vv :=
    local_kept f2 _ (by decide) (local_kept f1 _ (by decide) (local_bound f0 0 _))
  refine Grow.guardSkip (insertGuard_run l0 l1 inside (by omega)) (Ext.refl fE) ?_
  refine Grow.letRun (RunsExpr.local' l0) (Ext.refl fE) ?_
  let B := E.bindLocal 3 vv
  have fB : B.CellsWellFormed := fE.bindLocal _ _
  have b3 : B.local? 3 = some vv := local_bound fE 3 _
  have b1 : B.local? 1 = some (.signed .i32 i) := local_kept fE _ (by decide) l1
  have b2 : B.local? 2 = some x := local_kept fE _ (by decide) l2
  have cond := RunsExpr.binary (operation := .equal) (program := P)
    (RunsExpr.field' (j := 1) (RunsExpr.local' b3) rfl) (RunsExpr.field' (j := 2) (RunsExpr.local' b3) rfl)
    (by decide) (eval_i32_eq _ _ _)
  rw [show ((xs.length : Int) == (cap : Int)) = false by simp; omega] at cond
  refine Grow.guardSkip cond (Ext.refl fB) ?_
  obtain ⟨after, run, ext, rep', effect⟩ := insertTail_spec inst kind fB rep room inside b3 b1 b2 store stores
    noViews unique
  exact ⟨after, run, ext, rep', Kept.ofWrite effect ⟨Nat.le_refl _, Nat.le_refl _⟩, effect.below below,
    effect.unique, Or.inl ⟨rfl, rfl, effect.frontier⟩⟩

/-- `try_insert(v, i, x)` on a full vector with room in the heap for
`pushTarget size len(v)` elements: grown as in `try_push`, then shifted and
stored. -/
theorem tryInsert_grow_spec (inst : GrowInstance P T ids g) (kind : ElemKind P T size)
    {f : FunctionId} (found : P.function? f = some (tryInsertFn ids g T f))
    {caller : State} (formed : caller.CellsWellFormed) {xs : List Value} {p : Nat}
    (rep : VecRep P T size ids.vec caller.heap
      (.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 xs.length]) xs)
    (fits : size * (xs.length + 1) ≤ 2147483647) {i : Nat} (inside : i ≤ xs.length)
    {budget : Option Nat}
    (available : consumeBudget caller.heap.remaining (size * pushTarget size xs.length) = some budget)
    (roomHeap : caller.heap.allocationAddress 8 + size * pushTarget size xs.length < 2 ^ 64)
    {x : Value} (store : ElemStore P T size x) (stores : ∀ y ∈ xs, ElemStore P T size y)
    (below : HeapBlocksBelowNext caller.heap) (unique : HeapBlockBasesUnique caller.heap)
    (noViews : caller.i32ArrayViews = []) :
    ∃ after, RunsExpr P caller (.call f (insertArgs ids p xs.length xs.length i x))
      (.structure ids.vec [.pointer (caller.heap.allocationAddress 8), .signed .i32 (xs.insertIdx i x).length,
        .signed .i32 (pushTarget size xs.length)]) after ∧
      FreshCellFrame caller after ∧ after.world = caller.world ∧
      after.i32ArrayViews = caller.i32ArrayViews ∧
      Pushed P T size ids.vec caller.heap p xs.length (caller.heap.allocationAddress 8)
        (pushTarget size xs.length) (xs.insertIdx i x) after.heap := by
  have target := inst.vec.target
  obtain ⟨_, _, capBound, _, _⟩ := rep.fields
  obtain ⟨grows, mFits⟩ := pushTarget_bounds kind fits
  obtain ⟨m, hm⟩ : ∃ m, pushTarget size xs.length = m := ⟨_, rfl⟩
  rw [hm] at available roomHeap grows mFits ⊢
  let vv := Value.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 xs.length]
  let Q := caller.heap.allocationAddress 8
  refine Grow.call (vs := [vv, .signed .i32 i, x])
    (Q := Pushed P T size ids.vec caller.heap p xs.length Q m (xs.insertIdx i x)) found rfl rfl ?_
  let E0 : State := { caller with locals := [] }
  have f0 : E0.CellsWellFormed := formed
  have f1 := f0.bindLocal 0 vv
  have f2 := f1.bindLocal 1 (.signed .i32 i)
  let E := ((E0.bindLocal 0 vv).bindLocal 1 (.signed .i32 i)).bindLocal 2 x
  change Grow P E _ _ _
  have fE : E.CellsWellFormed := f2.bindLocal _ _
  have l2 : E.local? 2 = some x := local_bound f2 2 _
  have l1 : E.local? 1 = some (.signed .i32 i) := local_kept f2 _ (by decide) (local_bound f1 1 _)
  have l0 : E.local? 0 = some vv :=
    local_kept f2 _ (by decide) (local_kept f1 _ (by decide) (local_bound f0 0 _))
  have positive := kind.size_pos
  have nSmall : xs.length + 1 ≤ 2147483647 := by
    have := Nat.le_mul_of_pos_left (xs.length + 1) positive; omega
  refine Grow.guardSkip (insertGuard_run l0 l1 inside (by omega)) (Ext.refl fE) ?_
  -- let grown = value
  let B := E.bindLocal 3 vv
  have fB : B.CellsWellFormed := fE.bindLocal _ _
  have b3 : B.local? 3 = some vv := local_bound fE 3 _
  have cB : B.cellId? 3 = some E.nextCell := bindLocal_cellId E 3 vv
  have cond2 := RunsExpr.binary (operation := .equal) (program := P)
    (RunsExpr.field' (j := 1) (RunsExpr.local' b3) rfl) (RunsExpr.field' (j := 2) (RunsExpr.local' b3) rfl)
    (by decide) (eval_i32_eq _ _ _)
  rw [show ((xs.length : Int) == (xs.length : Int)) = true by simp] at cond2
  -- let target = grown_capacity(grown, grown.length + 1)
  have needed := RunsExpr.binary (operation := .add) (RunsExpr.field' (j := 1) (RunsExpr.local' b3) rfl)
    (RunsExpr.value' (P := P) (S := B) (.signed .i32 1)) (by decide)
    (by rw [target]; exact eval_i32_add (by omega) (by omega))
  rw [show (xs.length : Int) + 1 = ((xs.length + 1 : Nat) : Int) by omega] at needed
  obtain ⟨B1, grownRun, gFrame⟩ := grown_capacity_spec inst kind fB (p := p) (len := .signed .i32 xs.length)
    (xs.length + 1) capBound
  rw [show grownTarget (capLimit size) xs.length (xs.length + 1) = m from hm] at grownRun
  have grownCall := callArgs (RunsExprs.two (RunsExpr.local' b3) needed) grownRun
  have fB1 := gFrame.afterFormed
  let D := B1.bindLocal 4 (.signed .i32 m)
  have fD : D.CellsWellFormed := fB1.bindLocal _ _
  have d3 : D.local? 3 = some vv := local_kept fB1 _ (by decide) (gFrame.localFound b3)
  have d4 : D.local? 4 = some (.signed .i32 m) := local_bound fB1 4 _
  have cB1 : B1.cellId? 3 = some E.nextCell := by unfold State.cellId? at cB ⊢; rw [gFrame.locals]; exact cB
  have cD : D.cellId? 3 = some E.nextCell := (cellId_bindLocal_ne B1 _ (by decide)).trans cB1
  have hD : D.heap = caller.heap := gFrame.heap
  have vD : D.i32ArrayViews = [] := gFrame.views.trans noViews
  -- grown = try_reserve(grown, target)
  obtain ⟨R, reserveRun, rCells, rWorld, rViews, grown⟩ := tryReserve_grow_spec inst kind fD
    (xs := xs) (p := p) (cap := xs.length) (min := m) (by rw [hD]; exact rep) grows mFits
    (by rw [hD]; exact available) (by rw [hD]; exact roomHeap) (by rw [hD]; exact below)
    (by rw [hD]; exact unique) vD stores
  rw [hD] at reserveRun grown
  let nv := Value.structure ids.vec [.pointer Q, .signed .i32 xs.length, .signed .i32 m]
  have right := callArgs (RunsExprs.two (RunsExpr.local' d3) (RunsExpr.local' d4)) reserveRun
  have rLocals : R.locals = D.locals := right.choose_spec.2
  obtain ⟨A, assignRun, assigned, effectA⟩ := RunsExpr.assignCellAfter (before := D) cD
    (cellEntry_of_local D 3 _ vv cD d3) right (Or.inr (rViews.trans vD))
  have cR : R.cellId? 3 = some E.nextCell := by unfold State.cellId? at cD ⊢; rw [rLocals]; exact cD
  have a3 : A.local? 3 = some nv := assignLocal_finds_assigned 3 E.nextCell nv cR assigned
  have cond3 := RunsExpr.binary (operation := .equal) (program := P)
    (RunsExpr.field' (j := 1) (RunsExpr.local' a3) rfl) (RunsExpr.field' (j := 2) (RunsExpr.local' a3) rfl)
    (by decide) (eval_i32_eq _ _ _)
  rw [show ((xs.length : Int) == (m : Int)) = false by simp; omega] at cond3
  have branch : RunsStmt P B
      (.letLocal 4 i32Ty (.call g.grownCapacity [.local 3, .binary .add (.field (.local 3) 1) (int 1)])
        (.sequence (.expression (.assign .set (.local 3) (.call g.tryReserve [.local 3, .local 4])))
          (.ifThenElse (.binary .equal (.field (.local 3) 1) (.field (.local 3) 2))
            (.returnValue (some (.local 0))) .skip)))
      .next (restoreLocals B1 A) :=
    RunsStmt.letLocal grownCall (RunsStmt.sequenceNext (RunsStmt.expression assignRun)
      (RunsStmt.ifThenElseFalse cond3 (RunsStmt.skip P A)))
  have extER : Ext E R := (((Ext.bindLocal fE 3 vv).trans (Ext.ofPure gFrame)).trans (Ext.bindLocal fB1 4 _)).trans
    ⟨fD, rCells, rWorld, rViews⟩
  obtain ⟨frameA, _, _, heapA, worldA, viewsA⟩ := FreshCellFrame.assignCounter fE extER.afterFormed extER.cells
    (assignLocal_assignCell 3 E.nextCell nv cR assigned)
  have extEA : Ext E A := ⟨fE, frameA, worldA.trans extER.world, viewsA.trans extER.views⟩
  let A' := restoreLocals B1 A
  have extEA' : Ext E A' := extEA.restore B1
  have fA' : A'.CellsWellFormed := extEA'.afterFormed
  have cA : A.cellId? 3 = some E.nextCell := by unfold State.cellId? at cR ⊢; rw [effectA.locals]; exact cR
  have a'3 : A'.local? 3 = some nv := (local?_congr (s := A') (t := A) rfl
    ((show A'.cellId? 3 = some E.nextCell from cB1).trans cA.symm)).trans a3
  have a'Locals : A'.locals = (3, E.nextCell) :: E.locals := gFrame.locals
  have a'1 : A'.local? 1 = some (.signed .i32 i) := local_above extEA'.cells a'Locals (by decide) l1
  have a'2 : A'.local? 2 = some x := local_above extEA'.cells a'Locals (by decide) l2
  have hA' : A'.heap = R.heap := heapA
  have vA' : A'.i32ArrayViews = [] := viewsA.trans (rViews.trans vD)
  obtain ⟨rep2, kept2, below2, unique2, next2⟩ := grown
  obtain ⟨F, tailRun, extTail, rep3, effect3⟩ := insertTail_spec inst.vec kind fA' (xs := xs) (q := Q) (m := m)
    (by rw [hA']; exact rep2) grows inside a'3 a'1 a'2 store stores vA' (by rw [hA']; exact unique2)
  rw [hA'] at effect3
  refine ⟨restoreLocals E F, RunsStmt.letLocal (RunsExpr.local' l0)
    (RunsStmt.sequenceNext (RunsStmt.ifThenElseTrue cond2 branch) tailRun), (extEA'.trans extTail).restore E, ?_⟩
  have fresh : caller.heap.nextAddress ≤ Q := Heap.allocationAddress_ge caller.heap (by decide)
  exact ⟨rep3, kept2.afterFreshWrite below fresh effect3, effect3.below below2, effect3.unique,
    Or.inr ⟨rfl, effect3.frontier.trans next2⟩⟩

#print axioms insertTail_spec
#print axioms tryInsert_room_spec
#print axioms tryInsert_grow_spec

end Lanius.Std
