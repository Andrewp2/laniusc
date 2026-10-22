import Lanius.Std.VecClone

/-! # The fill loop

`while (index < new_len) { items[index] = fill; index += 1; }` from a start
index: slots `[start, new_len)` read `fill` afterwards and the slots below
`start` are untouched. -/

namespace Lanius.Std

open Lanius Lanius.Core Lanius.Semantics Lanius.Memory

variable {P : Program} {T : Ty} {size : Nat}

/-- `while (index < len) { items[index] = fill; index += 1; }` with the
locals `idx`, `len`, `dst` and `fill`. -/
def fillLoop (idx len dst fill : VarId) : Stmt :=
  .whileLoop (.binary .less (.local idx) (.local len))
    (.sequence (.expression (.assign .set (.index (.local dst) (.local idx)) (.local fill))) (increment idx))

/-- The fill loop's state after `k` iterations from `start`. -/
def FillInv (P : Program) (T : Ty) (size : Nat) (S : State) (idx : VarId) (x : Value)
    (q m start k : Nat) (st : State) : Prop :=
  ∃ h, st = ({ S with heap := h } : State).bindLocal idx (.signed .i32 ((start + k : Nat) : Int)) ∧
    HeapRegionWrite S.heap h q (size * m) ∧
    (∀ i, start ≤ i → i < start + k → ∀ other : State,
      ReadsWithin h other.heap (slotLo T size q m i) size →
        readRawSliceIndex P other T (viewAddr T size q m) m i = .ok x) ∧
    ∀ i, i < start → ReadsWithin S.heap h (slotLo T size q m i) size

theorem fill_loop_spec (target : P.target = Target.x86_64) (kind : ElemKind P T size)
    {S : State} (formed : S.CellsWellFormed) {idx len dst fill : VarId}
    (lenLocal : idx ≠ len) (dstLocal : idx ≠ dst) (fillLocal : idx ≠ fill)
    {N start q m : Nat} {x : Value}
    (lenFound : S.local? len = some (.signed .i32 N))
    (dstFound : S.local? dst = some (.rawSlice T (viewAddr T size q m) m))
    (fillFound : S.local? fill = some x)
    (startLe : start ≤ N) (fits : N ≤ m) (dstBound : m < 2 ^ 31)
    (buffer : 0 < m → Buffer S.heap q (size * m)) (store : ElemStore P T size x)
    (noViews : S.i32ArrayViews = []) (unique : HeapBlockBasesUnique S.heap) :
    ∃ h', RunsStmt P (S.bindLocal idx (.signed .i32 start)) (fillLoop idx len dst fill) .next
        (({ S with heap := h' } : State).bindLocal idx (.signed .i32 N)) ∧
      HeapRegionWrite S.heap h' q (size * m) ∧
      (∀ i, start ≤ i → i < N → ∀ other : State,
        ReadsWithin h' other.heap (slotLo T size q m i) size →
          readRawSliceIndex P other T (viewAddr T size q m) m i = .ok x) ∧
      ∀ i, i < start → ReadsWithin S.heap h' (slotLo T size q m i) size := by
  let st : Heap → Nat → State := fun h k => ({ S with heap := h } : State).bindLocal idx (.signed .i32 k)
  have fS : ∀ h : Heap, ({ S with heap := h } : State).CellsWellFormed := fun _ => formed
  have idxAt : ∀ h k, (st h k).local? idx = some (.signed .i32 (Int.ofNat k)) := fun h _ => local_bound (fS h) idx _
  have lenAt : ∀ h k, (st h k).local? len = some (.signed .i32 N) := fun h _ => local_kept (fS h) _ lenLocal lenFound
  have dstAt : ∀ h k, (st h k).local? dst = some (.rawSlice T (viewAddr T size q m) m) :=
    fun h _ => local_kept (fS h) _ dstLocal dstFound
  have fillAt : ∀ h k, (st h k).local? fill = some x := fun h _ => local_kept (fS h) _ fillLocal fillFound
  have condAt : ∀ h k, RunsExpr P (st h k) (.binary .less (.local idx) (.local len))
      (.boolean (decide ((k : Int) < N))) (st h k) := fun h k =>
    RunsExpr.binary (RunsExpr.local' (idxAt h k)) (RunsExpr.local' (lenAt h k)) (by decide) (eval_i32_lt _ _ _)
  let measure : State → Nat := fun s => N - counter idx s
  let spec : CountdownWhileSpec measure P (.binary .less (.local idx) (.local len))
      (.sequence (.expression (.assign .set (.index (.local dst) (.local idx)) (.local fill))) (increment idx))
      (N - start) := {
    Inv := FillInv P T size S idx x q m start
    Done := fun completion s => completion = .next ∧ FillInv P T size S idx x q m start (N - start) s
    terminal := by
      intro s invariant
      obtain ⟨h, rfl, rest⟩ := invariant
      have run := condAt h (start + (N - start))
      rw [show decide (((start + (N - start) : Nat) : Int) < N) = false by simp; omega] at run
      obtain ⟨threshold, stable, _⟩ := run
      exact ⟨threshold, _, stable, rfl, h, rfl, rest⟩
    step := by
      intro k s kLt invariant
      obtain ⟨h, rfl, effect, done, untouched⟩ := invariant
      have km : start + k < m := by omega
      have run := condAt h (start + k)
      rw [show decide (((start + k : Nat) : Int) < N) = true by simp; omega] at run
      obtain ⟨condThreshold, condStable, _⟩ := run
      have dstSlot := slot_inside (T := T) (size := size) (p := q) km
      have bufferH : Buffer h q (size * m) := (buffer (by omega)).afterWrite effect
      let base := elemBase T size q m (start + k)
      have slotEq : slotOf T size base = slotLo T size q m (start + k) := slotOf_elemBase kind.size_eight
      have readable : h.Readable (slotOf T size base) size := by
        rw [slotEq]
        have within := dstSlot
        unfold slotLo at within ⊢
        exact bufferH.2.1.subrange (start := size * slotIndex T m (start + k)) (by omega)
      have room : size ≤ base + 8 := by
        show size ≤ elemBase T size q m (start + k) + 8
        unfold elemBase
        by_cases scalar : T = i32Ty
        · rw [if_pos scalar, kind.i32_size scalar]; omega
        · rw [if_neg scalar]; have := kind.size_eight scalar; omega
      obtain ⟨h'', stored, readBack, written⟩ := store (st h (start + k)) h base room readable effect.unique
      rw [slotEq] at written
      have assign := StableExpr.assignRaw (before := st h (start + k)) (indexed := st h (start + k))
        (ready := st h (start + k)) (heap := h'') (sourceId := dst) (dstAt h (start + k))
        (StableExpr.local (idxAt h (start + k))) km (elementAddress kind km)
        (show (st h (start + k)).i32ArrayViews = [] from noViews) (StableExpr.local (fillAt h (start + k))) stored
      have bodyRun : RunsStmt P (st h (start + k))
          (.sequence (.expression (.assign .set (.index (.local dst) (.local idx)) (.local fill))) (increment idx))
          .next (st h'' (start + k + 1)) :=
        RunsStmt.sequenceNext (RunsStmt.expression (RunsExpr.ofStable assign rfl))
          (increment_bound target (fS h'') idx (by omega))
      obtain ⟨bodyThreshold, bodyStable, _⟩ := bodyRun
      refine ⟨condThreshold, bodyThreshold, _, _, condStable, bodyStable, ?_, ?_⟩
      · show N - counter idx (st h'' (start + k + 1)) < N - counter idx (st h (start + k))
        rw [counter_eq (idxAt h'' (start + k + 1)), counter_eq (idxAt h (start + k))]; omega
      · refine ⟨h'', by rw [Nat.add_assoc], effect.trans (written.enlarge dstSlot.1 dstSlot.2), ?_, ?_⟩
        · intro i lower upper other within
          by_cases same : i = start + k
          · subst same
            rw [readRawSliceIndex_elem other kind km]
            exact readBack other.heap (by rw [slotEq]; exact within)
          · exact done i lower (by omega) other (ReadsWithin.trans
              (HeapRegionWrite.readsApart written (slots_apart km (by omega) (fun e => same e.symm))) within)
        · intro i below
          exact ReadsWithin.trans (untouched i below)
            (HeapRegionWrite.readsApart written (slots_apart km (by omega) (by omega))) }
  obtain ⟨threshold, completion, after, run, done⟩ :=
    executeTotalWhile measure P _ _ (countdownWhileOracle measure P _ _ (N - start) spec)
      (S.bindLocal idx (.signed .i32 start))
      ⟨0, Nat.zero_le _, S.heap, rfl, HeapRegionWrite.refl _ unique, fun _ _ _ => by omega,
        fun i _ => ReadsWithin.refl _ _ _⟩
  obtain ⟨rfl, h', rfl, effect, filled, untouched⟩ := done
  rw [show start + (N - start) = N by omega] at run filled
  exact ⟨h', ⟨threshold, run, rfl⟩, effect, filled, untouched⟩

#print axioms fill_loop_spec

end Lanius.Std
