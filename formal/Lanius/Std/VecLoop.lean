import Lanius.Std.VecSpec
import Lanius.Semantics.TotalWhile
import Lanius.Semantics.Assignment
import Lanius.Extraction.CertificateEmitterFrame

/-! # Loops of `std::vec` on `TotalWhile`

The element-by-element loops of `std::vec`, each proved once for both
element layouts. A loop counter is the innermost local, bound by
`let index: i32 = 0;` just before the loop, so each iteration's state is the
state before that `let` with the counter rebound and a new heap. -/

namespace Lanius.Std

open Lanius Lanius.Core Lanius.Semantics Lanius.Memory

variable {P : Program} {T : Ty} {size : Nat}

/-! ## The counter -/

theorem bindLocal_cellId (S : State) (id : VarId) (v : Value) :
    (S.bindLocal id v).cellId? id = some S.nextCell := by
  simp [State.cellId?, State.bindLocal, State.bindCell]

private theorem replaceCell_append (cs ds : List Cell) (id : CellId) (w : Value) :
    replaceCell (cs ++ ds) id w = replaceCell cs id w ++ replaceCell ds id w := by
  induction cs with
  | nil => rfl
  | cons c rest ih =>
      simp only [List.cons_append, replaceCell]
      split <;> rw [ih] <;> rfl

private theorem replaceCell_absent (cs : List Cell) (id : CellId) (w : Value)
    (absent : ∀ cell ∈ cs, cell.id ≠ id) : replaceCell cs id w = cs := by
  induction cs with
  | nil => rfl
  | cons c rest ih =>
      have head : (c.id == id) = false := by simpa using absent c (by simp)
      simp only [replaceCell, head]
      rw [ih (fun cell member => absent cell (by simp [member]))]
      rfl

/-- Assigning the innermost local rebinds it. -/
theorem bindLocal_assignLocal {S : State} (formed : S.CellsWellFormed) (id : VarId) (v w : Value) :
    (S.bindLocal id v).assignLocal id w = some (S.bindLocal id w) := by
  have absent : ∀ cell ∈ S.cells, cell.id ≠ S.nextCell := fun cell member => by
    exact Nat.ne_of_lt (formed cell member)
  have entry : (S.bindLocal id v).cellEntry? S.nextCell = some { id := S.nextCell, value := some v } := by
    simp only [State.cellEntry?, State.bindLocal, State.bindCell, List.find?_append]
    rw [List.find?_eq_none.mpr (fun cell member => by simpa using absent cell member)]
    simp
  simp only [State.assignLocal, bindLocal_cellId, Option.bind_some, State.assignCell, entry,
    Option.isSome_some, if_true]
  congr 1
  simp only [State.bindLocal, State.bindCell, replaceCell_append, replaceCell_absent _ _ _ absent]
  simp [replaceCell]

open Classical in
/-- The value of an `i32` counter, as a measure. -/
noncomputable def counter (idx : VarId) (st : State) : Nat :=
  if h : ∃ k : Nat, st.local? idx = some (.signed .i32 k) then h.choose else 0

theorem counter_eq {idx : VarId} {st : State} {k : Nat} (found : st.local? idx = some (.signed .i32 k)) :
    counter idx st = k := by
  have ex : ∃ k : Nat, st.local? idx = some (.signed .i32 k) := ⟨k, found⟩
  unfold counter
  rw [dif_pos ex]
  have spec := found.symm.trans ex.choose_spec
  simp only [Option.some.injEq, Value.signed.injEq, true_and] at spec
  omega

theorem eval_i32_succ (target : P.target = Target.x86_64) {k : Nat} (small : k + 1 < 2 ^ 31) :
    evalBinaryValue P.target .add (.signed .i32 (Int.ofNat k)) (.signed .i32 1) =
      .ok (.signed .i32 (Int.ofNat (k + 1))) := by
  rw [target]
  simp only [evalBinaryValue, evalSignedBinary, beq_self_eq_true, if_true]
  rw [wrap_i32 (by simp only [Int.ofNat_eq_natCast]; omega) (by simp only [Int.ofNat_eq_natCast]; omega)]
  congr 2

/-- `index = index + 1;`, as the front end reads `index += 1;`. -/
def increment (idx : VarId) : Stmt :=
  .expression (.assign .set (.local idx) (.binary .add (.local idx) (int 1)))

theorem increment_run (target : P.target = Target.x86_64) {st after : State} {idx : VarId} {cell : CellId}
    {k : Nat} (small : k + 1 < 2 ^ 31) (cellFound : st.cellId? idx = some cell)
    (found : st.local? idx = some (.signed .i32 (Int.ofNat k)))
    (assigned : st.assignLocal idx (.signed .i32 (Int.ofNat (k + 1))) = some after) :
    RunsStmt P st (increment idx) .next after := by
  obtain ⟨threshold, sum, locals⟩ := RunsExpr.binary (program := P) (RunsExpr.local' found)
    (RunsExpr.value' (.signed .i32 1)) (by decide) (eval_i32_succ target small)
  refine RunsStmt.expression (RunsExpr.ofStable (Lanius.Extraction.CertificateEmitterFrame.StableExpr.assignSetLocal P st idx cell _ _ _ st after
    cellFound found sum rfl assigned rfl rfl) ?_)
  exact (assignLocal_preserves_frame (protectedId := idx) assigned).1

theorem increment_bound (target : P.target = Target.x86_64) {S : State} (formed : S.CellsWellFormed)
    (idx : VarId) {k : Nat} (small : k + 1 < 2 ^ 31) :
    RunsStmt P (S.bindLocal idx (.signed .i32 k)) (increment idx) .next
      (S.bindLocal idx (.signed .i32 (k + 1))) :=
  increment_run target small (bindLocal_cellId _ _ _) (local_bound formed idx _)
    (bindLocal_assignLocal formed idx _ _)

/-! ## Copy -/

/-- `while (index < value.length) { to[index] = from[index]; index += 1; }`, read as
with `value`, `from`, `to` and `index` the locals `vec`, `src`, `dst`, `idx`. -/
def copyLoop (idx vec src dst : VarId) : Stmt :=
  .whileLoop (.binary .less (.local idx) (.field (.local vec) 1))
    (.sequence (.expression (.assign .set (.index (.local dst) (.local idx)) (.index (.local src) (.local idx))))
      (increment idx))

/-- The copy loop's state after `k` iterations. -/
def CopyInv (P : Program) (T : Ty) (size : Nat) (S : State) (idx : VarId) (xs : List Value)
    (q m k : Nat) (st : State) : Prop :=
  ∃ h, st = ({ S with heap := h } : State).bindLocal idx (.signed .i32 k) ∧
    HeapRegionWrite S.heap h q (size * m) ∧
    ∀ i (inside : i < xs.length), i < k → ∀ other : State,
      ReadsWithin h other.heap (slotLo T size q m i) size →
        readRawSliceIndex P other T (viewAddr T size q m) m i = .ok xs[i]

/-- The copy loop: element `i` of the destination view reads `xs[i]` for
every `i` below `value.length`, and only the destination's storage changed. -/
theorem copy_loop_spec (target : P.target = Target.x86_64) (kind : ElemKind P T size)
    {S : State} (formed : S.CellsWellFormed) {idx vec src dst : VarId}
    (vecLocal : idx ≠ vec) (srcLocal : idx ≠ src) (dstLocal : idx ≠ dst)
    {tid : TypeId} {a c : Value} {xs : List Value}
    (vecFound : S.local? vec = some (.structure tid [a, .signed .i32 xs.length, c]))
    {p cap q m : Nat}
    (srcFound : S.local? src = some (.rawSlice T (viewAddr T size p cap) cap))
    (dstFound : S.local? dst = some (.rawSlice T (viewAddr T size q m) m))
    (srcFits : xs.length ≤ cap) (dstFits : xs.length ≤ m) (dstBound : m < 2 ^ 31)
    (reads : ∀ i (inside : i < xs.length) (other : State),
      ReadsWithin S.heap other.heap (slotLo T size p cap i) size →
        readRawSliceIndex P other T (viewAddr T size p cap) cap i = .ok xs[i])
    (buffer : 0 < m → Buffer S.heap q (size * m))
    (apart : p + size * cap ≤ q ∨ q + size * m ≤ p)
    (stores : ∀ x ∈ xs, ElemStore P T size x)
    (noViews : S.i32ArrayViews = []) (unique : HeapBlockBasesUnique S.heap) :
    ∃ h', RunsStmt P (S.bindLocal idx (.signed .i32 0)) (copyLoop idx vec src dst) .next
        (({ S with heap := h' } : State).bindLocal idx (.signed .i32 xs.length)) ∧
      HeapRegionWrite S.heap h' q (size * m) ∧
      ∀ i (inside : i < xs.length) (other : State),
        ReadsWithin h' other.heap (slotLo T size q m i) size →
          readRawSliceIndex P other T (viewAddr T size q m) m i = .ok xs[i] := by
  let st : Heap → Nat → State := fun h k => ({ S with heap := h } : State).bindLocal idx (.signed .i32 k)
  have fS : ∀ h : Heap, ({ S with heap := h } : State).CellsWellFormed := fun _ => formed
  have idxAt : ∀ h k, (st h k).local? idx = some (.signed .i32 (Int.ofNat k)) := fun h _ => local_bound (fS h) idx _
  have vecAt : ∀ h k, (st h k).local? vec = some (.structure tid [a, .signed .i32 xs.length, c]) :=
    fun h _ => local_kept (fS h) _ vecLocal vecFound
  have srcAt : ∀ h k, (st h k).local? src = some (.rawSlice T (viewAddr T size p cap) cap) :=
    fun h _ => local_kept (fS h) _ srcLocal srcFound
  have dstAt : ∀ h k, (st h k).local? dst = some (.rawSlice T (viewAddr T size q m) m) :=
    fun h _ => local_kept (fS h) _ dstLocal dstFound
  have condAt : ∀ h k, RunsExpr P (st h k) (.binary .less (.local idx) (.field (.local vec) 1))
      (.boolean (decide ((k : Int) < xs.length))) (st h k) := fun h k =>
    RunsExpr.binary (RunsExpr.local' (idxAt h k)) (RunsExpr.field' (j := 1) (RunsExpr.local' (vecAt h k)) rfl)
      (by decide) (eval_i32_lt _ _ _)
  let measure : State → Nat := fun s => xs.length - counter idx s
  let spec : CountdownWhileSpec measure P (.binary .less (.local idx) (.field (.local vec) 1))
      (.sequence (.expression (.assign .set (.index (.local dst) (.local idx)) (.index (.local src) (.local idx))))
        (increment idx)) xs.length := {
    Inv := CopyInv P T size S idx xs q m
    Done := fun completion s => completion = .next ∧ CopyInv P T size S idx xs q m xs.length s
    terminal := by
      intro s invariant
      obtain ⟨h, rfl, rest⟩ := invariant
      have run := condAt h xs.length
      rw [show decide (((xs.length : Nat) : Int) < xs.length) = false by simp] at run
      obtain ⟨threshold, stable, _⟩ := run
      exact ⟨threshold, _, stable, rfl, h, rfl, rest⟩
    step := by
      intro k s kLt invariant
      obtain ⟨h, rfl, effect, done⟩ := invariant
      have km : k < m := by omega
      have run := condAt h k
      rw [show decide ((k : Int) < xs.length) = true by simp; omega] at run
      obtain ⟨condThreshold, condStable, _⟩ := run
      -- read the source element
      have srcSlot := slot_inside (T := T) (size := size) (p := p) (show k < cap by omega)
      have srcRead : readRawSliceIndex P (st h k) T (viewAddr T size p cap) cap k = .ok xs[k] :=
        reads k kLt _ (HeapRegionWrite.readsApart effect (by omega))
      obtain ⟨readThreshold, readStable, _⟩ := RunsExpr.rawIndex (srcAt h k) (idxAt h k) srcRead
      -- store it
      have dstSlot := slot_inside (T := T) (size := size) (p := q) km
      have bufferH : Buffer h q (size * m) := (buffer (by omega)).afterWrite effect
      let base := elemBase T size q m k
      have slotEq : slotOf T size base = slotLo T size q m k := slotOf_elemBase kind.size_eight
      have readable : h.Readable (slotOf T size base) size := by
        rw [slotEq]
        have within := dstSlot
        unfold slotLo at within ⊢
        exact bufferH.2.1.subrange (start := size * slotIndex T m k) (by omega)
      have room : size ≤ base + 8 := by
        show size ≤ elemBase T size q m k + 8
        unfold elemBase
        by_cases scalar : T = i32Ty
        · rw [if_pos scalar, kind.i32_size scalar]; omega
        · rw [if_neg scalar]; have := kind.size_eight scalar; omega
      obtain ⟨h'', stored, readBack, written⟩ :=
        stores xs[k] (List.getElem_mem _) (st h k) h base room readable effect.unique
      rw [slotEq] at written
      have assign := StableExpr.assignRaw (before := st h k) (indexed := st h k) (ready := st h k)
        (heap := h'') (sourceId := dst) (dstAt h k) (StableExpr.local (idxAt h k)) km
        (elementAddress kind km) (show (st h k).i32ArrayViews = [] from noViews) readStable stored
      have bodyRun : RunsStmt P (st h k)
          (.sequence (.expression (.assign .set (.index (.local dst) (.local idx)) (.index (.local src) (.local idx))))
            (increment idx)) .next (st h'' (k + 1)) :=
        RunsStmt.sequenceNext (RunsStmt.expression (RunsExpr.ofStable assign rfl))
          (increment_bound target (fS h'') idx (by omega))
      obtain ⟨bodyThreshold, bodyStable, _⟩ := bodyRun
      refine ⟨condThreshold, bodyThreshold, _, _, condStable, bodyStable, ?_, ?_⟩
      · show xs.length - counter idx (st h'' (k + 1)) < xs.length - counter idx (st h k)
        rw [counter_eq (idxAt h'' (k + 1)), counter_eq (idxAt h k)]; omega
      · refine ⟨h'', rfl, effect.trans (written.enlarge dstSlot.1 dstSlot.2), ?_⟩
        intro i inside below other within
        by_cases same : i = k
        · subst same
          rw [readRawSliceIndex_elem other kind km]
          exact readBack other.heap (by rw [slotEq]; exact within)
        · exact done i inside (by omega) other (ReadsWithin.trans
            (HeapRegionWrite.readsApart written (slots_apart km (by omega) (fun e => same e.symm))) within) }
  obtain ⟨threshold, completion, after, run, done⟩ :=
    executeTotalWhile measure P _ _ (countdownWhileOracle measure P _ _ xs.length spec)
      (S.bindLocal idx (.signed .i32 0))
      ⟨0, Nat.zero_le _, S.heap, rfl, HeapRegionWrite.refl _ unique, fun _ _ below => absurd below (Nat.not_lt_zero _)⟩
  obtain ⟨rfl, h', rfl, effect, copied⟩ := done
  exact ⟨h', ⟨threshold, run, rfl⟩, effect, fun i inside => copied i inside inside⟩

#print axioms copy_loop_spec

end Lanius.Std
