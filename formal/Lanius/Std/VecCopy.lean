import Lanius.Std.VecReverse

/-! # The copy loop of `try_extend_from_slice`

`while (index < count) { to[grown.length + index] = items[index]; index += 1; }`
copies `count` elements of a source slice to the slots from `grown.length`
on. The source is described by where each element is read from (`lo j`),
and it must lie apart from the destination storage. -/

namespace Lanius.Std

open Lanius Lanius.Core Lanius.Semantics Lanius.Memory

variable {P : Program} {T : Ty} {size : Nat}

/-- The copy loop with the locals `idx`, `cnt`, `dst`, `src` and `vec`. -/
def extendLoop (idx cnt dst src vec : VarId) : Stmt :=
  .whileLoop (.binary .less (.local idx) (.local cnt))
    (.sequence (.expression (.assign .set (.index (.local dst) (.binary .add (.field (.local vec) 1) (.local idx)))
      (.index (.local src) (.local idx)))) (increment idx))

/-- A slice value whose element `j` is `ys[j]`, read from `[lo j, lo j + size)`
in `h`. -/
def SliceRep (P : Program) (T : Ty) (size : Nat) (h : Heap) (address length : Nat) (lo : Nat → Nat)
    (ys : List Value) : Prop :=
  ∀ j (inside : j < ys.length) (other : State), ReadsWithin h other.heap (lo j) size →
    readRawSliceIndex P other T address length j = .ok ys[j]

/-- The copy loop's state after `k` iterations. -/
def ExtendInv (P : Program) (T : Ty) (size : Nat) (S : State) (idx : VarId) (ys : List Value)
    (q m L : Nat) (k : Nat) (st : State) : Prop :=
  ∃ h, st = ({ S with heap := h } : State).bindLocal idx (.signed .i32 (k : Int)) ∧
    HeapRegionWrite S.heap h q (size * m) ∧
    (∀ j, j < k → ∀ other : State, ReadsWithin h other.heap (slotLo T size q m (L + j)) size →
        readRawSliceIndex P other T (viewAddr T size q m) m (L + j) = .ok (ys.getD j .unit)) ∧
    ∀ i, i < L → ReadsWithin S.heap h (slotLo T size q m i) size

theorem extend_loop_spec (target : P.target = Target.x86_64) (kind : ElemKind P T size)
    {S : State} (formed : S.CellsWellFormed) {idx cnt dst src vec : VarId}
    (cntLocal : idx ≠ cnt) (dstLocal : idx ≠ dst) (srcLocal : idx ≠ src) (vecLocal : idx ≠ vec)
    {q m L : Nat} {ys : List Value} {vid : TypeId} {ptr capv : Value} {sA sL : Nat} {lo : Nat → Nat}
    (cntFound : S.local? cnt = some (.signed .i32 ys.length))
    (dstFound : S.local? dst = some (.rawSlice T (viewAddr T size q m) m))
    (vecFound : S.local? vec = some (.structure vid [ptr, .signed .i32 L, capv]))
    (srcFound : S.local? src = some (.rawSlice T sA sL))
    (fits : L + ys.length ≤ m) (dstBound : m < 2 ^ 31)
    (buffer : 0 < m → Buffer S.heap q (size * m))
    (source : SliceRep P T size S.heap sA sL lo ys)
    (apart : ∀ j, j < ys.length → lo j + size ≤ q ∨ q + size * m ≤ lo j)
    (stores : ∀ y ∈ ys, ElemStore P T size y)
    (noViews : S.i32ArrayViews = []) (unique : HeapBlockBasesUnique S.heap) :
    ∃ h', RunsStmt P (S.bindLocal idx (.signed .i32 0)) (extendLoop idx cnt dst src vec) .next
        (({ S with heap := h' } : State).bindLocal idx (.signed .i32 ys.length)) ∧
      HeapRegionWrite S.heap h' q (size * m) ∧
      (∀ j, j < ys.length → ∀ other : State, ReadsWithin h' other.heap (slotLo T size q m (L + j)) size →
        readRawSliceIndex P other T (viewAddr T size q m) m (L + j) = .ok (ys.getD j .unit)) ∧
      ∀ i, i < L → ReadsWithin S.heap h' (slotLo T size q m i) size := by
  obtain ⟨N, hN⟩ : ∃ N, ys.length = N := ⟨_, rfl⟩
  rw [hN] at cntFound fits ⊢
  let st : Heap → Nat → State := fun h k => ({ S with heap := h } : State).bindLocal idx (.signed .i32 k)
  have fS : ∀ h : Heap, ({ S with heap := h } : State).CellsWellFormed := fun _ => formed
  have idxAt : ∀ h k, (st h k).local? idx = some (.signed .i32 (Int.ofNat k)) := fun h _ => local_bound (fS h) idx _
  have cntAt : ∀ h k, (st h k).local? cnt = some (.signed .i32 N) := fun h _ => local_kept (fS h) _ cntLocal cntFound
  have dstAt : ∀ h k, (st h k).local? dst = some (.rawSlice T (viewAddr T size q m) m) :=
    fun h _ => local_kept (fS h) _ dstLocal dstFound
  have srcAt : ∀ h k, (st h k).local? src = some (.rawSlice T sA sL) := fun h _ => local_kept (fS h) _ srcLocal srcFound
  have vecAt : ∀ h k, (st h k).local? vec = some (.structure vid [ptr, .signed .i32 L, capv]) :=
    fun h _ => local_kept (fS h) _ vecLocal vecFound
  have condAt : ∀ h k, RunsExpr P (st h k) (.binary .less (.local idx) (.local cnt))
      (.boolean (decide ((k : Int) < N))) (st h k) := fun h k =>
    RunsExpr.binary (RunsExpr.local' (idxAt h k)) (RunsExpr.local' (cntAt h k)) (by decide) (eval_i32_lt _ _ _)
  let measure : State → Nat := fun s => N - counter idx s
  let spec : CountdownWhileSpec measure P (.binary .less (.local idx) (.local cnt))
      (.sequence (.expression (.assign .set (.index (.local dst) (.binary .add (.field (.local vec) 1) (.local idx)))
        (.index (.local src) (.local idx)))) (increment idx)) N := {
    Inv := ExtendInv P T size S idx ys q m L
    Done := fun completion s => completion = .next ∧ ExtendInv P T size S idx ys q m L N s
    terminal := by
      intro s invariant
      obtain ⟨h, rfl, rest⟩ := invariant
      have run := condAt h N
      rw [show decide ((N : Int) < N) = false by simp] at run
      obtain ⟨threshold, stable, _⟩ := run
      exact ⟨threshold, _, stable, rfl, h, rfl, rest⟩
    step := by
      intro k s kLt invariant
      obtain ⟨h, rfl, effect, done, untouched⟩ := invariant
      have km : L + k < m := by omega
      have run := condAt h k
      rw [show decide ((k : Int) < N) = true by simp; omega] at run
      obtain ⟨condThreshold, condStable, _⟩ := run
      -- the index grown.length + index
      have indexRun := RunsExpr.binary (operation := .add) (program := P)
        (RunsExpr.field' (j := 1) (RunsExpr.local' (vecAt h k)) rfl) (RunsExpr.local' (idxAt h k)) (by decide)
        (by rw [target]; exact eval_i32_add (by simp only [Int.ofNat_eq_natCast]; omega) (by simp only [Int.ofNat_eq_natCast]; omega))
      rw [show (L : Int) + Int.ofNat k = Int.ofNat (L + k) by simp only [Int.ofNat_eq_natCast]; omega] at indexRun
      obtain ⟨_, indexStable, _⟩ := indexRun
      -- the source element items[index]
      have kys : k < ys.length := by omega
      have srcRead : readRawSliceIndex P (st h k) T sA sL k = .ok (ys[k]'kys) :=
        source k kys (st h k) (HeapRegionWrite.readsApart effect (apart k kys))
      have right := StableExpr.rawSliceIndex (srcAt h k) (idxAt h k) srcRead
      -- the store
      have dstSlot := slot_inside (T := T) (size := size) (p := q) km
      have bufferH : Buffer h q (size * m) := (buffer (by omega)).afterWrite effect
      let base := elemBase T size q m (L + k)
      have slotEq : slotOf T size base = slotLo T size q m (L + k) := slotOf_elemBase kind.size_eight
      have readable : h.Readable (slotOf T size base) size := by
        rw [slotEq]
        have within := dstSlot
        unfold slotLo at within ⊢
        exact bufferH.2.1.subrange (start := size * slotIndex T m (L + k)) (by omega)
      have room : size ≤ base + 8 := by
        show size ≤ elemBase T size q m (L + k) + 8
        unfold elemBase
        by_cases scalar : T = i32Ty
        · rw [if_pos scalar, kind.i32_size scalar]; omega
        · rw [if_neg scalar]; have := kind.size_eight scalar; omega
      obtain ⟨h'', stored, readBack, written⟩ :=
        stores (ys[k]'kys) (List.getElem_mem _) (st h k) h base room readable effect.unique
      rw [slotEq] at written
      have assign := StableExpr.assignRaw (before := st h k) (indexed := st h k)
        (ready := st h k) (heap := h'') (sourceId := dst) (dstAt h k) indexStable km (elementAddress kind km)
        (show (st h k).i32ArrayViews = [] from noViews) right stored
      have bodyRun : RunsStmt P (st h k)
          (.sequence (.expression (.assign .set (.index (.local dst) (.binary .add (.field (.local vec) 1) (.local idx)))
            (.index (.local src) (.local idx)))) (increment idx))
          .next (st h'' (k + 1)) :=
        RunsStmt.sequenceNext (RunsStmt.expression (RunsExpr.ofStable assign rfl))
          (increment_bound target (fS h'') idx (by omega))
      obtain ⟨bodyThreshold, bodyStable, _⟩ := bodyRun
      refine ⟨condThreshold, bodyThreshold, _, _, condStable, bodyStable, ?_, ?_⟩
      · show N - counter idx (st h'' (k + 1)) < N - counter idx (st h k)
        rw [counter_eq (idxAt h'' (k + 1)), counter_eq (idxAt h k)]; omega
      · refine ⟨h'', rfl, effect.trans (written.enlarge dstSlot.1 dstSlot.2), ?_, ?_⟩
        · intro j below other within
          by_cases same : j = k
          · rw [same, readRawSliceIndex_elem other kind km, getD_of_lt kys]
            rw [same] at within
            exact readBack other.heap (by rw [slotEq]; exact within)
          · exact done j (by omega) other (ReadsWithin.trans
              (HeapRegionWrite.readsApart written (slots_apart km (by omega) (by omega))) within)
        · intro i below
          exact ReadsWithin.trans (untouched i below)
            (HeapRegionWrite.readsApart written (slots_apart km (by omega) (by omega))) }
  obtain ⟨threshold, completion, after, run, done⟩ :=
    executeTotalWhile measure P _ _ (countdownWhileOracle measure P _ _ N spec)
      (S.bindLocal idx (.signed .i32 0))
      ⟨0, Nat.zero_le _, S.heap, rfl, HeapRegionWrite.refl _ unique, fun _ _ _ => by omega,
        fun i _ => ReadsWithin.refl _ _ _⟩
  obtain ⟨rfl, h', rfl, effect, copied, untouched⟩ := done
  exact ⟨h', ⟨threshold, run, rfl⟩, effect, copied, untouched⟩

#print axioms extend_loop_spec

end Lanius.Std
