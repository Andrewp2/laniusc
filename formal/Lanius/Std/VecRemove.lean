import Lanius.Std.VecResize

/-! # The shift-down loop and `try_remove`

`while (cursor + 1 < value.length) { items[cursor] = items[cursor + 1]; cursor += 1; }`
from `cursor = index` moves the elements after `index` down by one, so the
first `length - 1` slots hold `xs.eraseIdx index`. -/

namespace Lanius.Std

open Lanius Lanius.Core Lanius.Semantics Lanius.Memory

variable {P : Program} {T : Ty} {ids : VecIds} {size : Nat}

theorem getD_of_lt {xs : List Value} {j : Nat} (h : j < xs.length) : xs.getD j .unit = xs[j] := by
  simp [List.getD_eq_getElem?_getD, List.getElem?_eq_getElem h]

/-- The shift-down loop, with `cursor`, `value` and `items` the locals
`idx`, `vec` and `items`. -/
def shiftDownLoop (idx vec items : VarId) : Stmt :=
  .whileLoop (.binary .less (.binary .add (.local idx) (int 1)) (.field (.local vec) 1))
    (.sequence (.expression (.assign .set (.index (.local items) (.local idx))
        (.index (.local items) (.binary .add (.local idx) (int 1)))))
      (increment idx))

/-- Which element slot `j` holds after `k` steps from `i`. -/
def shiftedFrom (i k j : Nat) : Nat := if i ≤ j ∧ j < i + k then j + 1 else j

def ShiftInv (P : Program) (T : Ty) (size : Nat) (S : State) (idx : VarId) (xs : List Value)
    (p cap i k : Nat) (st : State) : Prop :=
  ∃ h, st = ({ S with heap := h } : State).bindLocal idx (.signed .i32 ((i + k : Nat) : Int)) ∧
    HeapRegionWrite S.heap h p (size * cap) ∧
    ∀ j, j < xs.length → ∀ other : State, ReadsWithin h other.heap (slotLo T size p cap j) size →
      readRawSliceIndex P other T (viewAddr T size p cap) cap j = .ok (xs.getD (shiftedFrom i k j) .unit)

theorem shift_down_loop_spec (target : P.target = Target.x86_64) (kind : ElemKind P T size)
    {S : State} (formed : S.CellsWellFormed) {idx vec items : VarId}
    (vecLocal : idx ≠ vec) (itemsLocal : idx ≠ items)
    {tid : TypeId} {a c : Value} {xs : List Value}
    (vecFound : S.local? vec = some (.structure tid [a, .signed .i32 xs.length, c]))
    {p cap : Nat} (itemsFound : S.local? items = some (.rawSlice T (viewAddr T size p cap) cap))
    (lenLe : xs.length ≤ cap) (capBound : cap < 2 ^ 31) {i : Nat} (inside : i < xs.length)
    (reads : ∀ j (inside : j < xs.length) (other : State),
      ReadsWithin S.heap other.heap (slotLo T size p cap j) size →
        readRawSliceIndex P other T (viewAddr T size p cap) cap j = .ok xs[j])
    (buffer : 0 < cap → Buffer S.heap p (size * cap)) (stores : ∀ x ∈ xs, ElemStore P T size x)
    (noViews : S.i32ArrayViews = []) (unique : HeapBlockBasesUnique S.heap) :
    ∃ h', RunsStmt P (S.bindLocal idx (.signed .i32 i)) (shiftDownLoop idx vec items) .next
        (({ S with heap := h' } : State).bindLocal idx (.signed .i32 ((xs.length - 1 : Nat) : Int))) ∧
      HeapRegionWrite S.heap h' p (size * cap) ∧
      ∀ j (inside : j < (xs.eraseIdx i).length) (other : State),
        ReadsWithin h' other.heap (slotLo T size p cap j) size →
          readRawSliceIndex P other T (viewAddr T size p cap) cap j = .ok (xs.eraseIdx i)[j] := by
  let st : Heap → Nat → State := fun h k => ({ S with heap := h } : State).bindLocal idx (.signed .i32 k)
  have fS : ∀ h : Heap, ({ S with heap := h } : State).CellsWellFormed := fun _ => formed
  have idxAt : ∀ h k, (st h k).local? idx = some (.signed .i32 (Int.ofNat k)) := fun h _ => local_bound (fS h) idx _
  have vecAt : ∀ h k, (st h k).local? vec = some (.structure tid [a, .signed .i32 xs.length, c]) :=
    fun h _ => local_kept (fS h) _ vecLocal vecFound
  have itemsAt : ∀ h k, (st h k).local? items = some (.rawSlice T (viewAddr T size p cap) cap) :=
    fun h _ => local_kept (fS h) _ itemsLocal itemsFound
  have nextAt : ∀ h k, k + 1 < 2 ^ 31 → RunsExpr P (st h k) (.binary .add (.local idx) (int 1))
      (.signed .i32 (Int.ofNat (k + 1))) (st h k) := fun h k small =>
    RunsExpr.binary (RunsExpr.local' (idxAt h k)) (RunsExpr.value' _) (by decide) (eval_i32_succ target small)
  have condAt : ∀ h k, k + 1 < 2 ^ 31 → RunsExpr P (st h k)
      (.binary .less (.binary .add (.local idx) (int 1)) (.field (.local vec) 1))
      (.boolean (decide (Int.ofNat (k + 1) < (xs.length : Int)))) (st h k) := fun h k small =>
    RunsExpr.binary (nextAt h k small) (RunsExpr.field' (j := 1) (RunsExpr.local' (vecAt h k)) rfl)
      (by decide) (eval_i32_lt _ _ _)
  let N := xs.length - 1 - i
  let measure : State → Nat := fun s => xs.length - counter idx s
  let spec : CountdownWhileSpec measure P
      (.binary .less (.binary .add (.local idx) (int 1)) (.field (.local vec) 1))
      (.sequence (.expression (.assign .set (.index (.local items) (.local idx))
          (.index (.local items) (.binary .add (.local idx) (int 1)))))
        (increment idx)) N := {
    Inv := ShiftInv P T size S idx xs p cap i
    Done := fun completion s => completion = .next ∧ ShiftInv P T size S idx xs p cap i N s
    terminal := by
      intro s invariant
      obtain ⟨h, rfl, rest⟩ := invariant
      have run := condAt h (i + N) (by omega)
      rw [show decide (Int.ofNat (i + N + 1) < (xs.length : Int)) = false by simp; omega] at run
      obtain ⟨threshold, stable, _⟩ := run
      exact ⟨threshold, _, stable, rfl, h, rfl, rest⟩
    step := by
      intro k s kLt invariant
      obtain ⟨h, rfl, effect, done⟩ := invariant
      let cur := i + k
      have curNext : cur + 1 < xs.length := by omega
      have run := condAt h cur (by omega)
      rw [show decide (Int.ofNat (cur + 1) < (xs.length : Int)) = true by simp; omega] at run
      obtain ⟨condThreshold, condStable, _⟩ := run
      -- read items[cursor + 1]
      have nextValue : xs.getD (shiftedFrom i k (cur + 1)) .unit = xs[cur + 1] := by
        rw [show shiftedFrom i k (cur + 1) = cur + 1 by simp [shiftedFrom]; omega]
        exact getD_of_lt curNext
      have nextRead : readRawSliceIndex P (st h cur) T (viewAddr T size p cap) cap (cur + 1) = .ok xs[cur + 1] := by
        rw [← nextValue]; exact done (cur + 1) curNext _ (ReadsWithin.refl _ _ _)
      obtain ⟨_, nextStable, _⟩ := nextAt h cur (by omega)
      have right := StableExpr.rawSliceIndexAt (itemsAt h cur) nextStable nextRead
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
      have room : size ≤ base + 8 := by
        show size ≤ elemBase T size p cap cur + 8
        unfold elemBase
        by_cases scalar : T = i32Ty
        · rw [if_pos scalar, kind.i32_size scalar]; omega
        · rw [if_neg scalar]; have := kind.size_eight scalar; omega
      obtain ⟨h'', stored, readBack, written⟩ :=
        stores xs[cur + 1] (List.getElem_mem _) (st h cur) h base room readable effect.unique
      rw [slotEq] at written
      have assign := StableExpr.assignRaw (before := st h cur) (indexed := st h cur) (ready := st h cur)
        (heap := h'') (sourceId := items) (itemsAt h cur) (StableExpr.local (idxAt h cur)) curCap
        (elementAddress kind curCap) (show (st h cur).i32ArrayViews = [] from noViews) right stored
      have bodyRun : RunsStmt P (st h cur)
          (.sequence (.expression (.assign .set (.index (.local items) (.local idx))
              (.index (.local items) (.binary .add (.local idx) (int 1)))))
            (increment idx)) .next (st h'' (cur + 1)) :=
        RunsStmt.sequenceNext (RunsStmt.expression (RunsExpr.ofStable assign rfl))
          (increment_bound target (fS h'') idx (by omega))
      obtain ⟨bodyThreshold, bodyStable, _⟩ := bodyRun
      refine ⟨condThreshold, bodyThreshold, _, _, condStable, bodyStable, ?_, ?_⟩
      · show xs.length - counter idx (st h'' (cur + 1)) < xs.length - counter idx (st h cur)
        rw [counter_eq (idxAt h'' (cur + 1)), counter_eq (idxAt h cur)]; omega
      · refine ⟨h'', by rw [show i + (k + 1) = cur + 1 by omega], effect.trans (written.enlarge slot.1 slot.2), ?_⟩
        intro j jInside other within
        by_cases same : j = cur
        · subst same
          rw [readRawSliceIndex_elem other kind curCap,
            show shiftedFrom i (k + 1) (i + k) = i + k + 1 by simp [shiftedFrom], getD_of_lt curNext]
          exact readBack other.heap (by rw [slotEq]; exact within)
        · rw [show shiftedFrom i (k + 1) j = shiftedFrom i k j by
            unfold shiftedFrom
            by_cases h1 : i ≤ j ∧ j < i + k
            · rw [if_pos h1, if_pos ⟨h1.1, by omega⟩]
            · rw [if_neg h1, if_neg (by omega)]]
          exact done j jInside other (ReadsWithin.trans
            (HeapRegionWrite.readsApart written (slots_apart curCap (by omega) (fun e => same e.symm))) within) }
  obtain ⟨threshold, completion, after, run, done⟩ :=
    executeTotalWhile measure P _ _ (countdownWhileOracle measure P _ _ N spec)
      (S.bindLocal idx (.signed .i32 i))
      ⟨0, Nat.zero_le _, S.heap, rfl, HeapRegionWrite.refl _ unique, fun j jInside other within => by
        rw [show shiftedFrom i 0 j = j by simp [shiftedFrom], getD_of_lt jInside]
        exact reads j jInside other within⟩
  obtain ⟨rfl, h', rfl, effect, shifted⟩ := done
  rw [show i + N = xs.length - 1 by omega] at run
  refine ⟨h', ⟨threshold, run, rfl⟩, effect, fun j jInside other within => ?_⟩
  have lenErase : (xs.eraseIdx i).length = xs.length - 1 := by simp [List.length_eraseIdx, inside]
  have jLt : j < xs.length - 1 := by omega
  rw [List.getElem_eraseIdx]
  by_cases low : j < i
  · have e : shiftedFrom i N j = j := by simp [shiftedFrom]; omega
    have read := shifted j (by omega) other within
    rw [e, getD_of_lt (by omega)] at read
    rw [dif_pos low]; exact read
  · have e : shiftedFrom i N j = j + 1 := by simp [shiftedFrom]; omega
    have read := shifted j (by omega) other within
    rw [e, getD_of_lt (by omega)] at read
    rw [dif_neg low]; exact read

#print axioms shift_down_loop_spec

/-! ## `try_remove` -/

/-- `pub fn try_remove<T>(value: Vec<T>, index: i32) -> Vec<T>` -/
def tryRemoveFn (ids : VecIds) (f : FunctionId) : Function where
  id := f
  parameters := [(0, vecTy ids), (1, i32Ty)]
  returnType := vecTy ids
  body := some <|
    guardReturn (outOfRange 1) (.local 0)
    (.letLocal 2 (.slice T) (.call ids.slots [.local 0])
    (.letLocal 3 i32Ty (.local 1)
    (.sequence (shiftDownLoop 3 0 2)
      (.returnValue (some (.structValue ids.vec
        [.field (.local 0) 0, .binary .subtract (.field (.local 0) 1) (int 1), .field (.local 0) 2]))))))

/-- `try_remove(v, i)` in range: the result represents `xs.eraseIdx i` in the
same storage, and only that storage changed. -/
theorem tryRemove_spec (inst : VecInstance P T ids) (kind : ElemKind P T size)
    {f : FunctionId} (found : P.function? f = some (tryRemoveFn (T := T) ids f))
    {caller : State} (formed : caller.CellsWellFormed) {xs : List Value} {p cap : Nat}
    (rep : VecRep P T size ids.vec caller.heap
      (.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]) xs)
    {i : Nat} (inside : i < xs.length) (stores : ∀ y ∈ xs, ElemStore P T size y)
    (noViews : caller.i32ArrayViews = []) (unique : HeapBlockBasesUnique caller.heap) :
    ∃ after, RunsExpr P caller (.call f
        ([Value.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap], .signed .i32 i].map
          Expr.value))
      (.structure ids.vec [.pointer p, .signed .i32 (xs.eraseIdx i).length, .signed .i32 cap]) after ∧
      FreshCellFrame caller after ∧ after.world = caller.world ∧
      after.i32ArrayViews = caller.i32ArrayViews ∧
      VecRep P T size ids.vec after.heap
        (.structure ids.vec [.pointer p, .signed .i32 (xs.eraseIdx i).length, .signed .i32 cap]) (xs.eraseIdx i) ∧
      HeapRegionWrite caller.heap after.heap p (size * cap) := by
  have target := inst.target
  obtain ⟨_, lenLe, capBound, buffer, reads⟩ := rep.fields
  have lenErase : (xs.eraseIdx i).length = xs.length - 1 := by simp [List.length_eraseIdx, inside]
  let vv := Value.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]
  refine Grow.call (vs := [vv, .signed .i32 i]) (Q := fun H => VecRep P T size ids.vec H
      (.structure ids.vec [.pointer p, .signed .i32 (xs.eraseIdx i).length, .signed .i32 cap]) (xs.eraseIdx i) ∧
      HeapRegionWrite caller.heap H p (size * cap)) found rfl rfl ?_
  let E0 : State := { caller with locals := [] }
  have f0 : E0.CellsWellFormed := formed
  have f1 := f0.bindLocal 0 vv
  let E := (E0.bindLocal 0 vv).bindLocal 1 (.signed .i32 i)
  change Grow P E _ _ _
  have fE : E.CellsWellFormed := f1.bindLocal _ _
  have l1 : E.local? 1 = some (.signed .i32 i) := local_bound f1 1 _
  have l0 : E.local? 0 = some vv := local_kept f1 _ (by decide) (local_bound f0 0 _)
  have cond := outOfRange_run (P := P) l0 l1
  rw [show (decide ((i : Int) < 0) || decide ((i : Int) ≥ xs.length)) = false by simp; omega] at cond
  refine Grow.guardSkip cond (Ext.refl fE) ?_
  obtain ⟨S', slots, frame⟩ := slots_call inst kind fE l0 capBound buffer
  refine Grow.letRun slots (Ext.ofPure frame) ?_
  have fS : S'.CellsWellFormed := frame.afterFormed
  let view := Value.rawSlice T (viewAddr T size p cap) cap
  let B := S'.bindLocal 2 view
  have fB : B.CellsWellFormed := fS.bindLocal _ _
  have hB : B.heap = caller.heap := frame.heap
  have b2 : B.local? 2 = some view := local_bound fS 2 _
  have b1 : B.local? 1 = some (.signed .i32 i) := local_kept fS _ (by decide) (frame.localFound l1)
  have b0 : B.local? 0 = some vv := local_kept fS _ (by decide) (frame.localFound l0)
  obtain ⟨h', loopRun, effect, shifted⟩ := shift_down_loop_spec target kind fB (idx := 3) (vec := 0) (items := 2)
    (by decide) (by decide) b0 b2 lenLe capBound inside
    (fun j jInside other within => reads j jInside other (by rw [hB] at within; exact within))
    (fun positive => by rw [hB]; exact buffer positive) stores (frame.views.trans noViews)
    (by rw [hB]; exact unique)
  rw [hB] at effect
  let W := ({ B with heap := h' } : State).bindLocal 3 (.signed .i32 ((xs.length - 1 : Nat) : Int))
  have fW0 : ({ B with heap := h' } : State).CellsWellFormed := fB
  have w0 : W.local? 0 = some vv := local_kept fW0 _ (by decide) b0
  have shorter := RunsExpr.binary (operation := .subtract) (RunsExpr.field' (j := 1) (RunsExpr.local' w0) rfl)
    (RunsExpr.value' (P := P) (S := W) (.signed .i32 1)) (by decide)
    (by rw [target]; exact eval_i32_sub (by omega) (by omega))
  rw [show (xs.length : Int) - 1 = ((xs.eraseIdx i).length : Int) by rw [lenErase]; omega] at shorter
  have ret : RunsStmt P W (.returnValue (some (.structValue ids.vec
      [.field (.local 0) 0, .binary .subtract (.field (.local 0) 1) (int 1), .field (.local 0) 2])))
      (.returned (some (.structure ids.vec [.pointer p, .signed .i32 (xs.eraseIdx i).length, .signed .i32 cap]))) W :=
    RunsStmt.returnValue (RunsExprs.toRun (RunsExprs.three (RunsExpr.field' (j := 0) (RunsExpr.local' w0) rfl)
      shorter (RunsExpr.field' (j := 2) (RunsExpr.local' w0) rfl)))
  refine ⟨restoreLocals B W, RunsStmt.letLocal (RunsExpr.local' b1) (RunsStmt.sequenceNext loopRun ret),
    ((Ext.heap fB h').trans (Ext.bindLocal fW0 3 _)).restore B, ?_, effect⟩
  exact ⟨p, cap, rfl, by omega, capBound, fun positive => (buffer positive).afterWrite effect, shifted⟩

#print axioms tryRemove_spec

end Lanius.Std
