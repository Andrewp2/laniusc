import Lanius.Std.VecReserve
import Lanius.Semantics.ScalarAssignment

/-! # `try_push` and `push`

With room the item is stored at index `length` in place. Without room
`try_push` grows to `grown_capacity(v, length + 1)` through `try_reserve` and
stores into the new storage. Either way the result represents `xs ++ [x]` and
everything apart from the old storage is kept. -/

namespace Lanius.Std

open Lanius Lanius.Core Lanius.Semantics Lanius.Memory

variable {P : Program} {T : Ty} {ids : VecIds} {g : GrowIds} {size : Nat}

/-- A write inside `[p, p + n)` keeps everything apart from it. -/
theorem Kept.ofWrite {h h' : Heap} {p n lo k : Nat} (effect : HeapRegionWrite h h' lo k)
    (inside : p ≤ lo ∧ lo + k ≤ p + n) : Kept h h' p n :=
  ⟨fun _ _ _ => HeapRegionWrite.readsApart effect (by omega),
    fun _ _ _ _ buffer => buffer.afterWrite effect⟩

theorem local?_congr {s t : State} {id : VarId} (cells : s.cells = t.cells)
    (same : s.cellId? id = t.cellId? id) : s.local? id = t.local? id := by
  unfold State.local? State.cell? State.cellEntry?
  rw [same, cells]

theorem cellId_bindLocal_ne (S : State) {id other : VarId} (v : Value) (ne : other ≠ id) :
    (S.bindLocal other v).cellId? id = S.cellId? id := by
  have : (other == id) = false := by simpa using ne
  simp [State.cellId?, State.bindLocal, State.bindCell, this]

/-! ## The store -/

/-- The end of `try_push`: local 2 is a vector with room and local 1 the
item. The item goes into slot `length`, and the result represents `xs ++ [x]`. -/
theorem pushStore_spec (inst : VecInstance P T ids) (kind : ElemKind P T size) {Y : State}
    (formed : Y.CellsWellFormed) {xs : List Value} {q m : Nat} {x : Value}
    (rep : VecRep P T size ids.vec Y.heap
      (.structure ids.vec [.pointer q, .signed .i32 xs.length, .signed .i32 m]) xs)
    (room : xs.length < m)
    (l2 : Y.local? 2 = some (.structure ids.vec [.pointer q, .signed .i32 xs.length, .signed .i32 m]))
    (l1 : Y.local? 1 = some x) (store : ElemStore P T size x)
    (noViews : Y.i32ArrayViews = []) (unique : HeapBlockBasesUnique Y.heap) :
    Grow P Y (.letLocal 4 (.slice T) (.call ids.slots [.local 2])
      (.sequence (.expression (.assign .set (.index (.local 4) (.field (.local 2) 1)) (.local 1)))
        (.returnValue (some (.structValue ids.vec
          [.field (.local 2) 0, .binary .add (.field (.local 2) 1) (int 1), .field (.local 2) 2])))))
      (.returned (some (.structure ids.vec [.pointer q, .signed .i32 (xs ++ [x]).length, .signed .i32 m])))
      (fun h => VecRep P T size ids.vec h
          (.structure ids.vec [.pointer q, .signed .i32 (xs ++ [x]).length, .signed .i32 m]) (xs ++ [x]) ∧
        HeapRegionWrite Y.heap h (slotLo T size q m xs.length) size) := by
  have target := inst.target
  obtain ⟨_, _, capBound, buffer, reads⟩ := rep.fields
  let vv := Value.structure ids.vec [.pointer q, .signed .i32 xs.length, .signed .i32 m]
  obtain ⟨S', slots, frame⟩ := slots_call inst kind formed l2 capBound buffer
  have fS : S'.CellsWellFormed := frame.afterFormed
  let view := Value.rawSlice T (viewAddr T size q m) m
  let B := S'.bindLocal 4 view
  have fB : B.CellsWellFormed := fS.bindLocal _ _
  have hB : B.heap = Y.heap := frame.heap
  have src : B.local? 4 = some view := local_bound fS 4 _
  have v2 : B.local? 2 = some vv := local_kept fS _ (by decide) (frame.localFound l2)
  have xv : B.local? 1 = some x := local_kept fS _ (by decide) (frame.localFound l1)
  let lo := slotLo T size q m xs.length
  let base := elemBase T size q m xs.length
  have slotEq : slotOf T size base = lo := slotOf_elemBase kind.size_eight
  have readable : Y.heap.Readable lo size := by
    have within := slot_inside (T := T) (size := size) (p := q) room
    unfold slotLo at within
    exact (buffer (by omega)).2.1.subrange (start := size * slotIndex T m xs.length) (by omega)
  have roomBase : size ≤ base + 8 := by
    show size ≤ elemBase T size q m xs.length + 8
    unfold elemBase
    by_cases scalar : T = i32Ty
    · rw [if_pos scalar, kind.i32_size scalar]; omega
    · rw [if_neg scalar]; have := kind.size_eight scalar; omega
  obtain ⟨h', stored, readBack, effect⟩ :=
    store B B.heap base roomBase (by rw [slotEq, hB]; exact readable) (by rw [hB]; exact unique)
  rw [slotEq, hB] at effect
  have nv : B.i32ArrayViews = [] := frame.views.trans noViews
  have assign := StableExpr.assignRaw (before := B) (indexed := B) (ready := B) (heap := h')
    (sourceId := 4) (position := xs.length) src (StableExpr.field (fieldId := 1) (StableExpr.local v2) rfl)
    room (elementAddress kind room) nv (StableExpr.local xv) stored
  let C : State := { B with heap := h' }
  have c2 : C.local? 2 = some vv := v2
  have bump := RunsExpr.binary (operation := .add) (RunsExpr.field' (j := 1) (RunsExpr.local' c2) rfl)
    (RunsExpr.value' (P := P) (S := C) (.signed .i32 1)) (by decide)
    (by rw [target]; exact eval_i32_add (by omega) (by omega))
  have lenEq : ((xs ++ [x]).length : Int) = (xs.length : Int) + 1 := by simp
  rw [← lenEq] at bump
  have body : RunsStmt P B
      (.sequence (.expression (.assign .set (.index (.local 4) (.field (.local 2) 1)) (.local 1)))
        (.returnValue (some (.structValue ids.vec
          [.field (.local 2) 0, .binary .add (.field (.local 2) 1) (int 1), .field (.local 2) 2]))))
      (.returned (some (.structure ids.vec [.pointer q, .signed .i32 (xs ++ [x]).length, .signed .i32 m]))) C :=
    RunsStmt.sequenceNext (RunsStmt.expression (RunsExpr.ofStable assign rfl))
      (RunsStmt.returnValue (RunsExprs.toRun (RunsExprs.three
        (RunsExpr.field' (j := 0) (RunsExpr.local' c2) rfl) bump
        (RunsExpr.field' (j := 2) (RunsExpr.local' c2) rfl))))
  refine ⟨restoreLocals S' C, RunsStmt.letLocal slots body,
    (((Ext.ofPure frame).trans (Ext.bindLocal fS 4 view)).trans (Ext.heap fB h')).restore S', ?_, effect⟩
  refine ⟨q, m, rfl, by simp; omega, capBound, fun positive => (buffer positive).afterWrite effect, ?_⟩
  intro j jInside other within
  simp only [List.length_append, List.length_singleton] at jInside
  by_cases same : j = xs.length
  · subst same
    have last : (xs ++ [x])[xs.length]'(by simp) = x := by simp
    rw [last, readRawSliceIndex_elem other kind room]
    exact readBack other.heap (by rw [slotEq]; exact within)
  · have earlier : (xs ++ [x])[j]'(by simp; omega) = xs[j]'(by omega) := List.getElem_append_left (by omega)
    rw [earlier]
    exact reads j (by omega) other (ReadsWithin.trans
      (HeapRegionWrite.readsApart effect (slots_apart room (by omega) (fun h => same h.symm))) within)

/-! ## `try_push` -/

/-- What `try_push` leaves in the heap: the vector of the longer list,
everything apart from the old storage, and the frontier, which moves only
when the vector moved to a fresh block at the next aligned address. -/
def Pushed (P : Program) (T : Ty) (size : Nat) (vec : TypeId) (h : Heap) (p cap q m : Nat)
    (xs : List Value) (H : Heap) : Prop :=
  VecRep P T size vec H (.structure vec [.pointer q, .signed .i32 xs.length, .signed .i32 m]) xs ∧
    Kept h H p (size * cap) ∧ HeapBlocksBelowNext H ∧ HeapBlockBasesUnique H ∧ (HeapApart h → HeapApart H) ∧
    (q = p ∧ m = cap ∧ H.nextAddress = h.nextAddress ∨
      q = h.allocationAddress 8 ∧ H.nextAddress = q + size * m)

/-- The capacity `try_push` grows a full vector of capacity `cap` to. -/
def pushTarget (size cap : Nat) : Nat := grownTarget (capLimit size) cap (cap + 1)

theorem pushTarget_bounds (kind : ElemKind P T size) {cap : Nat} (fits : size * (cap + 1) ≤ 2147483647) :
    cap < pushTarget size cap ∧ size * pushTarget size cap ≤ 2147483647 := by
  have positive := kind.size_pos
  have small := kind.size_le
  have needed : cap + 1 ≤ capLimit size := (Nat.le_div_iff_mul_le positive).mpr (by rw [Nat.mul_comm]; exact fits)
  have four : 4 ≤ capLimit size := (Nat.le_div_iff_mul_le positive).mpr (by omega)
  have bounds : cap < pushTarget size cap ∧ pushTarget size cap ≤ capLimit size := by
    unfold pushTarget grownTarget
    generalize capLimit size = L at needed four
    dsimp only
    (repeat' split) <;> omega
  refine ⟨bounds.1, ?_⟩
  calc size * pushTarget size cap ≤ size * capLimit size := Nat.mul_le_mul_left _ bounds.2
    _ ≤ 2147483647 := Nat.mul_div_le 2147483647 size

/-- The arguments of `try_push`. -/
abbrev pushArgs (ids : VecIds) (p len cap : Nat) (x : Value) : List Expr :=
  [Value.structure ids.vec [.pointer p, .signed .i32 len, .signed .i32 cap], x].map Expr.value

/-- `try_push(v, x)` with room: the item goes into slot `length` in place. -/
theorem tryPush_room_spec (inst : GrowInstance P T ids g) (kind : ElemKind P T size)
    {caller : State} (formed : caller.CellsWellFormed) {xs : List Value} {p cap : Nat} {x : Value}
    (rep : VecRep P T size ids.vec caller.heap
      (.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]) xs)
    (room : xs.length < cap) (store : ElemStore P T size x)
    (below : HeapBlocksBelowNext caller.heap) (unique : HeapBlockBasesUnique caller.heap)
    (noViews : caller.i32ArrayViews = []) :
    ∃ after, RunsExpr P caller (.call g.tryPush (pushArgs ids p xs.length cap x))
      (.structure ids.vec [.pointer p, .signed .i32 (xs ++ [x]).length, .signed .i32 cap]) after ∧
      FreshCellFrame caller after ∧ after.world = caller.world ∧
      after.i32ArrayViews = caller.i32ArrayViews ∧
      Pushed P T size ids.vec caller.heap p cap p cap (xs ++ [x]) after.heap := by
  obtain ⟨_, _, capBound, _, _⟩ := rep.fields
  let vv := Value.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]
  refine Grow.call inst.tryPush rfl rfl ?_
  let E0 : State := { caller with locals := [] }
  have f0 : E0.CellsWellFormed := formed
  have f1 := f0.bindLocal 0 vv
  let E := (E0.bindLocal 0 vv).bindLocal 1 x
  change Grow P E _ _ _
  have fE : E.CellsWellFormed := f1.bindLocal _ _
  have l1 : E.local? 1 = some x := local_bound f1 1 _
  have l0 : E.local? 0 = some vv := local_kept f1 _ (by decide) (local_bound f0 0 _)
  have cond1 := RunsExpr.binary (operation := .equal) (program := P)
    (RunsExpr.field' (j := 1) (RunsExpr.local' l0) rfl) (RunsExpr.value' (.signed .i32 2147483647)) (by decide)
    (eval_i32_eq _ _ _)
  rw [show ((xs.length : Int) == 2147483647) = false by simp; omega] at cond1
  refine Grow.guardSkip cond1 (Ext.refl fE) ?_
  refine Grow.letRun (RunsExpr.local' l0) (Ext.refl fE) ?_
  let B := E.bindLocal 2 vv
  have fB : B.CellsWellFormed := fE.bindLocal _ _
  have b2 : B.local? 2 = some vv := local_bound fE 2 _
  have b1 : B.local? 1 = some x := local_kept fE _ (by decide) l1
  have cond2 := RunsExpr.binary (operation := .equal) (program := P)
    (RunsExpr.field' (j := 1) (RunsExpr.local' b2) rfl) (RunsExpr.field' (j := 2) (RunsExpr.local' b2) rfl)
    (by decide) (eval_i32_eq _ _ _)
  rw [show ((xs.length : Int) == (cap : Int)) = false by simp; omega] at cond2
  refine Grow.guardSkip cond2 (Ext.refl fB) ?_
  obtain ⟨after, run, ext, rep', effect⟩ := pushStore_spec inst.vec kind fB rep room b2 b1 store noViews unique
  refine ⟨after, run, ext, rep', Kept.ofWrite effect ?_, effect.below below, effect.unique,
    fun ap => ap.ofWrite effect, Or.inl ⟨rfl, rfl, effect.frontier⟩⟩
  have := slot_inside (T := T) (size := size) (p := p) room
  omega

/-- `try_push(v, x)` on a full vector with room in the heap for
`pushTarget size cap` elements: the vector moves to fresh storage of that
capacity and the item goes into slot `length` there. -/
theorem tryPush_grow_spec (inst : GrowInstance P T ids g) (kind : ElemKind P T size)
    {caller : State} (formed : caller.CellsWellFormed) {xs : List Value} {p : Nat} {x : Value}
    (rep : VecRep P T size ids.vec caller.heap
      (.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 xs.length]) xs)
    (fits : size * (xs.length + 1) ≤ 2147483647)
    {budget : Option Nat}
    (available : consumeBudget caller.heap.remaining (size * pushTarget size xs.length) = some budget)
    (roomHeap : caller.heap.allocationAddress 8 + size * pushTarget size xs.length < 2 ^ 64)
    (store : ElemStore P T size x) (stores : ∀ y ∈ xs, ElemStore P T size y)
    (below : HeapBlocksBelowNext caller.heap) (unique : HeapBlockBasesUnique caller.heap)
    (noViews : caller.i32ArrayViews = []) :
    ∃ after, RunsExpr P caller (.call g.tryPush (pushArgs ids p xs.length xs.length x))
      (.structure ids.vec [.pointer (caller.heap.allocationAddress 8), .signed .i32 (xs ++ [x]).length,
        .signed .i32 (pushTarget size xs.length)]) after ∧
      FreshCellFrame caller after ∧ after.world = caller.world ∧
      after.i32ArrayViews = caller.i32ArrayViews ∧
      Pushed P T size ids.vec caller.heap p xs.length (caller.heap.allocationAddress 8)
        (pushTarget size xs.length) (xs ++ [x]) after.heap := by
  have target := inst.vec.target
  obtain ⟨_, _, capBound, _, _⟩ := rep.fields
  obtain ⟨grows, mFits⟩ := pushTarget_bounds kind fits
  obtain ⟨m, hm⟩ : ∃ m, pushTarget size xs.length = m := ⟨_, rfl⟩
  rw [hm] at available roomHeap grows mFits ⊢
  let vv := Value.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 xs.length]
  refine Grow.call inst.tryPush rfl rfl ?_
  let E0 : State := { caller with locals := [] }
  have f0 : E0.CellsWellFormed := formed
  have f1 := f0.bindLocal 0 vv
  let E := (E0.bindLocal 0 vv).bindLocal 1 x
  change Grow P E _ _ _
  have fE : E.CellsWellFormed := f1.bindLocal _ _
  have l1 : E.local? 1 = some x := local_bound f1 1 _
  have l0 : E.local? 0 = some vv := local_kept f1 _ (by decide) (local_bound f0 0 _)
  have positive := kind.size_pos
  have nSmall : xs.length + 1 ≤ 2147483647 := by
    have := Nat.le_mul_of_pos_left (xs.length + 1) positive; omega
  have cond1 := RunsExpr.binary (operation := .equal) (program := P)
    (RunsExpr.field' (j := 1) (RunsExpr.local' l0) rfl) (RunsExpr.value' (.signed .i32 2147483647)) (by decide)
    (eval_i32_eq _ _ _)
  rw [show ((xs.length : Int) == 2147483647) = false by simp; omega] at cond1
  refine Grow.guardSkip cond1 (Ext.refl fE) ?_
  -- let grown = value
  let B := E.bindLocal 2 vv
  have fB : B.CellsWellFormed := fE.bindLocal _ _
  have b2 : B.local? 2 = some vv := local_bound fE 2 _
  have cB : B.cellId? 2 = some E.nextCell := bindLocal_cellId E 2 vv
  have cond2 := RunsExpr.binary (operation := .equal) (program := P)
    (RunsExpr.field' (j := 1) (RunsExpr.local' b2) rfl) (RunsExpr.field' (j := 2) (RunsExpr.local' b2) rfl)
    (by decide) (eval_i32_eq _ _ _)
  rw [show ((xs.length : Int) == (xs.length : Int)) = true by simp] at cond2
  -- let target = grown_capacity(grown, grown.length + 1)
  have needed := RunsExpr.binary (operation := .add) (RunsExpr.field' (j := 1) (RunsExpr.local' b2) rfl)
    (RunsExpr.value' (P := P) (S := B) (.signed .i32 1)) (by decide)
    (by rw [target]; exact eval_i32_add (by omega) (by omega))
  rw [show (xs.length : Int) + 1 = ((xs.length + 1 : Nat) : Int) by omega] at needed
  obtain ⟨B1, grownRun, gFrame⟩ := grown_capacity_spec inst kind fB (p := p) (len := .signed .i32 xs.length) (xs.length + 1) capBound
  rw [show grownTarget (capLimit size) xs.length (xs.length + 1) = m from hm] at grownRun
  have grownCall := callArgs (RunsExprs.two (RunsExpr.local' b2) needed) grownRun
  have fB1 := gFrame.afterFormed
  let D := B1.bindLocal 3 (.signed .i32 m)
  have fD : D.CellsWellFormed := fB1.bindLocal _ _
  have d2 : D.local? 2 = some vv := local_kept fB1 _ (by decide) (gFrame.localFound b2)
  have d3 : D.local? 3 = some (.signed .i32 m) := local_bound fB1 3 _
  have cB1 : B1.cellId? 2 = some E.nextCell := by unfold State.cellId? at cB ⊢; rw [gFrame.locals]; exact cB
  have cD : D.cellId? 2 = some E.nextCell := (cellId_bindLocal_ne B1 _ (by decide)).trans cB1
  have hD : D.heap = caller.heap := gFrame.heap
  have vD : D.i32ArrayViews = [] := gFrame.views.trans noViews
  -- grown = try_reserve(grown, target)
  obtain ⟨R, reserveRun, rCells, rWorld, rViews, grown⟩ := tryReserve_grow_spec inst kind fD
    (xs := xs) (p := p) (cap := xs.length) (min := m) (by rw [hD]; exact rep) grows mFits
    (by rw [hD]; exact available) (by rw [hD]; exact roomHeap) (by rw [hD]; exact below)
    (by rw [hD]; exact unique) vD stores
  rw [hD] at reserveRun grown
  let Q := caller.heap.allocationAddress 8
  let nv := Value.structure ids.vec [.pointer Q, .signed .i32 xs.length, .signed .i32 m]
  have right := callArgs (RunsExprs.two (RunsExpr.local' d2) (RunsExpr.local' d3)) reserveRun
  have rLocals : R.locals = D.locals := right.choose_spec.2
  obtain ⟨A, assignRun, assigned, effectA⟩ := RunsExpr.assignCellAfter (before := D) cD
    (cellEntry_of_local D 2 _ vv cD d2) right (Or.inr (rViews.trans vD))
  have cR : R.cellId? 2 = some E.nextCell := by unfold State.cellId? at cD ⊢; rw [rLocals]; exact cD
  have a2 : A.local? 2 = some nv := assignLocal_finds_assigned 2 E.nextCell nv cR assigned
  have cond3 := RunsExpr.binary (operation := .equal) (program := P)
    (RunsExpr.field' (j := 1) (RunsExpr.local' a2) rfl) (RunsExpr.field' (j := 2) (RunsExpr.local' a2) rfl)
    (by decide) (eval_i32_eq _ _ _)
  rw [show ((xs.length : Int) == (m : Int)) = false by simp; omega] at cond3
  have branch : RunsStmt P B
      (.letLocal 3 i32Ty (.call g.grownCapacity [.local 2, .binary .add (.field (.local 2) 1) (int 1)])
        (.sequence (.expression (.assign .set (.local 2) (.call g.tryReserve [.local 2, .local 3])))
          (.ifThenElse (.binary .equal (.field (.local 2) 1) (.field (.local 2) 2))
            (.returnValue (some (.local 0))) .skip)))
      .next (restoreLocals B1 A) :=
    RunsStmt.letLocal grownCall (RunsStmt.sequenceNext (RunsStmt.expression assignRun)
      (RunsStmt.ifThenElseFalse cond3 (RunsStmt.skip P A)))
  -- the frame of the caller's locals across the assignment
  have extER : Ext E R := (((Ext.bindLocal fE 2 vv).trans (Ext.ofPure gFrame)).trans (Ext.bindLocal fB1 3 _)).trans
    ⟨fD, rCells, rWorld, rViews⟩
  obtain ⟨frameA, _, _, heapA, worldA, viewsA⟩ := FreshCellFrame.assignCounter fE extER.afterFormed extER.cells
    (assignLocal_assignCell 2 E.nextCell nv cR assigned)
  have extEA : Ext E A := ⟨fE, frameA, worldA.trans extER.world, viewsA.trans extER.views⟩
  let A' := restoreLocals B1 A
  have extEA' : Ext E A' := extEA.restore B1
  have fA' : A'.CellsWellFormed := extEA'.afterFormed
  have cA : A.cellId? 2 = some E.nextCell := by unfold State.cellId? at cR ⊢; rw [effectA.locals]; exact cR
  have a'2 : A'.local? 2 = some nv := (local?_congr (s := A') (t := A) rfl ((show A'.cellId? 2 = some E.nextCell from cB1).trans
    cA.symm)).trans a2
  have a'Locals : A'.locals = (2, E.nextCell) :: E.locals := gFrame.locals
  have a'1 : A'.local? 1 = some x := local_above extEA'.cells a'Locals (by decide) l1
  have hA' : A'.heap = R.heap := heapA
  have vA' : A'.i32ArrayViews = [] := viewsA.trans (rViews.trans vD)
  obtain ⟨rep2, kept2, below2, unique2, next2, apart2⟩ := grown
  -- the store
  obtain ⟨F, tailRun, extTail, rep3, effect3⟩ := pushStore_spec inst.vec kind fA' (xs := xs) (q := Q) (m := m)
    (by rw [hA']; exact rep2) grows a'2 a'1 store vA' (by rw [hA']; exact unique2)
  rw [hA'] at effect3
  have extEF : Ext E F := extEA'.trans extTail
  refine ⟨restoreLocals E F, RunsStmt.letLocal (RunsExpr.local' l0)
    (RunsStmt.sequenceNext (RunsStmt.ifThenElseTrue cond2 branch) tailRun), extEF.restore E, ?_⟩
  have fresh : caller.heap.nextAddress ≤ slotLo T size Q m xs.length := by
    have := Heap.allocationAddress_ge caller.heap (alignment := 8) (by decide)
    unfold slotLo; dsimp only [Lanius.Address] at *; omega
  exact ⟨rep3, kept2.afterFreshWrite below fresh effect3, effect3.below below2, effect3.unique,
    fun ap => HeapApart.ofWrite effect3 (apart2 ap), Or.inr ⟨rfl, effect3.frontier.trans next2⟩⟩

/-- `try_push(v, x)` when the result has at most `capacity_limit()`
elements and, if `v` is full, the heap has room for the grown storage. -/
theorem tryPush_spec (inst : GrowInstance P T ids g) (kind : ElemKind P T size)
    {caller : State} (formed : caller.CellsWellFormed) {xs : List Value} {p cap : Nat} {x : Value}
    (rep : VecRep P T size ids.vec caller.heap
      (.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]) xs)
    (fits : size * (xs.length + 1) ≤ 2147483647)
    (growth : xs.length = cap →
      (∃ budget, consumeBudget caller.heap.remaining (size * pushTarget size cap) = some budget) ∧
        caller.heap.allocationAddress 8 + size * pushTarget size cap < 2 ^ 64)
    (store : ElemStore P T size x) (stores : ∀ y ∈ xs, ElemStore P T size y)
    (below : HeapBlocksBelowNext caller.heap) (unique : HeapBlockBasesUnique caller.heap)
    (noViews : caller.i32ArrayViews = []) :
    ∃ (after : State) (q m : Nat), RunsExpr P caller (.call g.tryPush (pushArgs ids p xs.length cap x))
      (.structure ids.vec [.pointer q, .signed .i32 (xs ++ [x]).length, .signed .i32 m]) after ∧
      FreshCellFrame caller after ∧ after.world = caller.world ∧
      after.i32ArrayViews = caller.i32ArrayViews ∧
      Pushed P T size ids.vec caller.heap p cap q m (xs ++ [x]) after.heap := by
  by_cases full : xs.length = cap
  · subst full
    obtain ⟨⟨budget, available⟩, roomHeap⟩ := growth rfl
    obtain ⟨after, run, rest⟩ := tryPush_grow_spec inst kind formed rep fits available roomHeap store stores
      below unique noViews
    exact ⟨after, _, _, run, rest⟩
  · obtain ⟨_, lenLe, _, _, _⟩ := rep.fields
    obtain ⟨after, run, rest⟩ := tryPush_room_spec inst kind formed rep (by omega) store below unique noViews
    exact ⟨after, _, _, run, rest⟩

/-! ## `push` -/

/-- `push(v, x)` under the same conditions: `try_push` succeeds, so the
length check passes and `push` returns its result. -/
theorem push_spec (inst : GrowInstance P T ids g) (kind : ElemKind P T size)
    {caller : State} (formed : caller.CellsWellFormed) {xs : List Value} {p cap : Nat} {x : Value}
    (rep : VecRep P T size ids.vec caller.heap
      (.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]) xs)
    (fits : size * (xs.length + 1) ≤ 2147483647)
    (growth : xs.length = cap →
      (∃ budget, consumeBudget caller.heap.remaining (size * pushTarget size cap) = some budget) ∧
        caller.heap.allocationAddress 8 + size * pushTarget size cap < 2 ^ 64)
    (store : ElemStore P T size x) (stores : ∀ y ∈ xs, ElemStore P T size y)
    (below : HeapBlocksBelowNext caller.heap) (unique : HeapBlockBasesUnique caller.heap)
    (noViews : caller.i32ArrayViews = []) :
    ∃ (after : State) (q m : Nat), RunsExpr P caller (.call g.push (pushArgs ids p xs.length cap x))
      (.structure ids.vec [.pointer q, .signed .i32 (xs ++ [x]).length, .signed .i32 m]) after ∧
      FreshCellFrame caller after ∧ after.world = caller.world ∧
      after.i32ArrayViews = caller.i32ArrayViews ∧
      Pushed P T size ids.vec caller.heap p cap q m (xs ++ [x]) after.heap := by
  let vv := Value.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]
  let E0 : State := { caller with locals := [] }
  have f0 : E0.CellsWellFormed := formed
  have f1 := f0.bindLocal 0 vv
  let E := (E0.bindLocal 0 vv).bindLocal 1 x
  have fE : E.CellsWellFormed := f1.bindLocal _ _
  have l1 : E.local? 1 = some x := local_bound f1 1 _
  have l0 : E.local? 0 = some vv := local_kept f1 _ (by decide) (local_bound f0 0 _)
  obtain ⟨S, q, m, run, cells, world, views, pushed⟩ := tryPush_spec inst kind fE (xs := xs) (p := p) (cap := cap)
    rep fits growth store stores below unique noViews
  let nv := Value.structure ids.vec [.pointer q, .signed .i32 (xs ++ [x]).length, .signed .i32 m]
  have call := callArgs (RunsExprs.two (RunsExpr.local' l0) (RunsExpr.local' l1)) run
  have locals : S.locals = E.locals := call.choose_spec.2
  suffices goal : ∃ after, RunsExpr P caller (.call g.push (pushArgs ids p xs.length cap x)) nv after ∧
      FreshCellFrame caller after ∧ after.world = caller.world ∧ after.i32ArrayViews = caller.i32ArrayViews ∧
      Pushed P T size ids.vec caller.heap p cap q m (xs ++ [x]) after.heap by
    obtain ⟨after, rest⟩ := goal
    exact ⟨after, q, m, rest⟩
  refine Grow.call (Q := Pushed P T size ids.vec caller.heap p cap q m (xs ++ [x])) inst.push rfl rfl ?_
  change Grow P E _ _ _
  refine Grow.letRun call ⟨fE, cells, world, views⟩ ?_
  have fS := FreshCellFrame.after_cellsWellFormed fE cells
  let B := S.bindLocal 2 nv
  have fB : B.CellsWellFormed := fS.bindLocal _ _
  have b2 : B.local? 2 = some nv := local_bound fS 2 _
  have b0 : B.local? 0 = some vv := local_kept fS _ (by decide) (cells.localFound locals 0 _ l0)
  have cond := RunsExpr.binary (operation := .equal) (program := P)
    (RunsExpr.field' (j := 1) (RunsExpr.local' b2) rfl) (RunsExpr.field' (j := 1) (RunsExpr.local' b0) rfl)
    (by decide) (eval_i32_eq _ _ _)
  rw [show (((xs ++ [x]).length : Int) == (xs.length : Int)) = false by simp; omega] at cond
  exact Grow.guardSkip cond (Ext.refl fB) ⟨B, RunsStmt.returnValue (RunsExpr.local' b2), Ext.refl fB, pushed⟩

#print axioms pushStore_spec
#print axioms tryPush_room_spec
#print axioms tryPush_grow_spec
#print axioms tryPush_spec
#print axioms push_spec

end Lanius.Std
