import Lanius.Std.VecView

/-! # Specs of the loop-free `std::vec` functions

Total-correctness contracts in the `RunsExpr` style, proved once for every
`VecInstance` and both element layouts (`ElemKind`). Each says the call
returns, gives its value in terms of the list the vector represents
(`VecRep`), and frames the state: `PureFrame` (heap, world and views as they
were, only fresh cells added) for all but `try_set`, which changes exactly
one element's slot (`HeapRegionWrite`). Ownership: none of these grows, so
the argument's `VecRep` still holds afterwards (`try_set` keeps it for the
other elements; the old value is the new one). -/

namespace Lanius.Std

open Lanius Lanius.Core Lanius.Semantics Lanius.Memory

variable {P : Program} {T : Ty} {ids : VecIds} {size : Nat}

/-- `slots(v)` is the view of the whole storage. -/
theorem slots_spec (inst : VecInstance P T ids) (kind : ElemKind P T size)
    {caller : State} (formed : caller.CellsWellFormed) {p cap : Nat} {len : Value}
    (capBound : cap < 2 ^ 31) (buffer : 0 < cap → Buffer caller.heap p (size * cap)) :
    ∃ after, RunsExpr P caller
      (.call ids.slots ([Value.structure ids.vec [.pointer p, len, .signed .i32 cap]].map Expr.value))
      (.rawSlice T (viewAddr T size p cap) cap) after ∧ PureFrame caller after := by
  refine PureRun.call inst.slots rfl rfl formed ?_
  let E0 : State := { caller with locals := [] }
  have f0 : E0.CellsWellFormed := formed
  let E := E0.bindLocal 0 (.structure ids.vec [.pointer p, len, .signed .i32 cap])
  change PureRun P E _ _
  have fE : E.CellsWellFormed := f0.bindLocal _ _
  have l0 := local_bound f0 0 (.structure ids.vec [.pointer p, len, .signed .i32 cap])
  have args : RunsExprs P E [.field (.local 0) 0, .field (.local 0) 2] [.pointer p, .signed .i32 cap] E :=
    RunsExprs.two (RunsExpr.field' (RunsExpr.local' l0) rfl) (RunsExpr.field' (RunsExpr.local' l0) rfl)
  obtain ⟨after, run, frame⟩ := fromStorage_spec inst kind fE capBound buffer
  exact ⟨after, RunsStmt.returnValue (callArgs args run), frame⟩

/-- The pure call of `slots` from inside a body. -/
theorem slots_call (inst : VecInstance P T ids) (kind : ElemKind P T size)
    {S : State} (formed : S.CellsWellFormed) {xs : List Value} {p cap : Nat} {id : VarId}
    (found : S.local? id = some (.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]))
    (capBound : cap < 2 ^ 31) (buffer : 0 < cap → Buffer S.heap p (size * cap)) :
    ∃ after, RunsExpr P S (.call ids.slots [.local id]) (.rawSlice T (viewAddr T size p cap) cap) after ∧
      PureFrame S after := by
  obtain ⟨after, run, frame⟩ := slots_spec inst kind formed capBound buffer
  exact ⟨after, callArgs (RunsExprs.one (RunsExpr.local' found)) run, frame⟩

/-! ## Accessors -/

theorem new_spec (inst : VecInstance P T ids) {caller : State} (formed : caller.CellsWellFormed) :
    ∃ after v, RunsExpr P caller (.call ids.new (([] : List Value).map Expr.value)) v after ∧
      PureFrame caller after ∧ ∀ h, VecRep P T size ids.vec h v [] := by
  obtain ⟨after, run, frame⟩ : ∃ after, RunsExpr P caller (.call ids.new (([] : List Value).map Expr.value))
      (.structure ids.vec [.pointer 0, .signed .i32 0, .signed .i32 0]) after ∧ PureFrame caller after := by
    refine PureRun.call inst.new rfl rfl formed ?_
    let E : State := { caller with locals := [] }
    have f0 : E.CellsWellFormed := formed
    change PureRun P E _ _
    refine PureRun.letPure f0 (RunsExpr.value' (.pointer 0)) ?_
    have l0 := local_bound f0 0 (.pointer 0)
    exact PureRun.ret (f0.bindLocal _ _) (RunsExprs.toRun (RunsExprs.three (RunsExpr.local' l0)
      (RunsExpr.value' _) (RunsExpr.value' _)))
  refine ⟨after, _, run, frame, fun h => ⟨0, 0, rfl, Nat.le_refl _, by decide, nofun, nofun⟩⟩

theorem len_spec (inst : VecInstance P T ids) {caller : State} (formed : caller.CellsWellFormed)
    {v : Value} {xs : List Value} (rep : VecRep P T size ids.vec caller.heap v xs) :
    ∃ after, RunsExpr P caller (.call ids.len ([v].map Expr.value)) (.signed .i32 xs.length) after ∧
      PureFrame caller after := by
  obtain ⟨p, cap, rfl, _⟩ := rep
  refine PureRun.call inst.len rfl rfl formed ?_
  let E0 : State := { caller with locals := [] }
  have f0 : E0.CellsWellFormed := formed
  change PureRun P (E0.bindLocal 0 _) _ _
  exact PureRun.ret (f0.bindLocal _ _) (RunsExpr.field' (RunsExpr.local' (local_bound f0 0 _)) rfl)

theorem capacity_spec (inst : VecInstance P T ids) {caller : State} (formed : caller.CellsWellFormed)
    {v : Value} {xs : List Value} (rep : VecRep P T size ids.vec caller.heap v xs) :
    ∃ (after : State) (cap : Nat), RunsExpr P caller (.call ids.capacity ([v].map Expr.value)) (.signed .i32 cap) after ∧
      PureFrame caller after ∧ xs.length ≤ cap := by
  obtain ⟨p, cap, rfl, lenLe, _⟩ := rep
  obtain ⟨after, run, frame⟩ : ∃ after, RunsExpr P caller (.call ids.capacity ([Value.structure ids.vec
      [.pointer p, .signed .i32 xs.length, .signed .i32 cap]].map Expr.value)) (.signed .i32 cap) after ∧
      PureFrame caller after := by
    refine PureRun.call inst.capacity rfl rfl formed ?_
    let E0 : State := { caller with locals := [] }
    have f0 : E0.CellsWellFormed := formed
    change PureRun P (E0.bindLocal 0 _) _ _
    exact PureRun.ret (f0.bindLocal _ _) (RunsExpr.field' (RunsExpr.local' (local_bound f0 0 _)) rfl)
  exact ⟨after, cap, run, frame, lenLe⟩

theorem isEmpty_spec (inst : VecInstance P T ids) {caller : State} (formed : caller.CellsWellFormed)
    {v : Value} {xs : List Value} (rep : VecRep P T size ids.vec caller.heap v xs) :
    ∃ after, RunsExpr P caller (.call ids.isEmpty ([v].map Expr.value)) (.boolean xs.isEmpty) after ∧
      PureFrame caller after := by
  obtain ⟨p, cap, rfl, _⟩ := rep
  have empty : ((xs.length : Int) == 0) = xs.isEmpty := by cases xs <;> simp <;> omega
  refine PureRun.call inst.isEmpty rfl rfl formed ?_
  let E0 : State := { caller with locals := [] }
  have f0 : E0.CellsWellFormed := formed
  change PureRun P (E0.bindLocal 0 _) _ _
  rw [← empty]
  exact PureRun.ret (f0.bindLocal _ _) (RunsExpr.binary
    (RunsExpr.field' (RunsExpr.local' (local_bound f0 0 _)) rfl) (RunsExpr.value' _) (by decide)
    (eval_i32_eq _ _ _))

/-- `index < 0 || index >= value.length` in a body whose local 0 is the
vector and `id` the index. -/
theorem outOfRange_run {S : State} {id : VarId} {vec : TypeId} {ptr cap : Value} {len index : Int}
    (vector : S.local? 0 = some (.structure vec [ptr, .signed .i32 len, cap]))
    (indexFound : S.local? id = some (.signed .i32 index)) :
    RunsExpr P S (outOfRange id) (.boolean (decide (index < 0) || decide (index ≥ len))) S :=
  RunsExpr.logicalOrBool
    (RunsExpr.binary (RunsExpr.local' indexFound) (RunsExpr.value' _) (by decide) (eval_i32_lt _ _ _))
    (RunsExpr.binary (RunsExpr.local' indexFound) (RunsExpr.field' (RunsExpr.local' vector) rfl) (by decide)
      (eval_i32_ge _ _ _))

/-! ## Element reads -/

/-- `get_or(v, index, fallback)`: element `index` of the list, or `fallback`
when `index` is out of range. -/
theorem getOr_spec (inst : VecInstance P T ids) (kind : ElemKind P T size) {caller : State}
    (formed : caller.CellsWellFormed) {v : Value} {xs : List Value}
    (rep : VecRep P T size ids.vec caller.heap v xs) (index : Int) (fallback : Value) :
    ∃ after, RunsExpr P caller (.call ids.getOr ([v, .signed .i32 index, fallback].map Expr.value))
      (if 0 ≤ index then (xs[index.toNat]?).getD fallback else fallback) after ∧ PureFrame caller after := by
  obtain ⟨p, cap, rfl, lenLe, capBound, buffer, reads⟩ := rep
  refine PureRun.call inst.getOr rfl rfl formed ?_
  let E0 : State := { caller with locals := [] }
  have f0 : E0.CellsWellFormed := formed
  let vv := Value.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]
  have f1 := f0.bindLocal 0 vv
  have f2 := f1.bindLocal 1 (.signed .i32 index)
  let E := ((E0.bindLocal 0 vv).bindLocal 1 (.signed .i32 index)).bindLocal 2 fallback
  change PureRun P E _ _
  have fE : E.CellsWellFormed := f2.bindLocal _ _
  have l2 : E.local? 2 = some fallback := local_bound f2 2 _
  have l1 : E.local? 1 = some (.signed .i32 index) := local_kept f2 _ (by decide) (local_bound f1 1 _)
  have l0 : E.local? 0 = some vv :=
    local_kept f2 _ (by decide) (local_kept f1 _ (by decide) (local_bound f0 0 _))
  have cond := outOfRange_run (P := P) l0 l1
  by_cases inRange : 0 ≤ index ∧ index < xs.length
  · obtain ⟨i, rfl⟩ := Int.eq_ofNat_of_zero_le inRange.1
    have hi : i < xs.length := by omega
    rw [if_pos inRange.1, Int.toNat_natCast, List.getElem?_eq_getElem hi, Option.getD_some]
    have isFalse : (decide ((i : Int) < 0) || decide ((i : Int) ≥ xs.length)) = false := by
      simp; omega
    rw [isFalse] at cond
    refine PureRun.guardSkip cond ?_
    obtain ⟨S', slots, frame⟩ := slots_call inst kind fE l0 capBound buffer
    refine PureRun.letRun slots frame ?_
    have fS : S'.CellsWellFormed := frame.afterFormed
    have heap : (S'.bindLocal 3 (.rawSlice T (viewAddr T size p cap) cap)).heap = caller.heap := frame.heap
    exact PureRun.ret (fS.bindLocal _ _) (RunsExpr.rawIndex (local_bound fS 3 _)
      (local_kept fS _ (by decide) (frame.localFound l1))
      (reads i hi _ (by rw [heap]; exact ReadsWithin.refl _ _ _)))
  · have isTrue : (decide (index < 0) || decide (index ≥ xs.length)) = true := by
      simp; omega
    rw [isTrue] at cond
    have result : (if 0 ≤ index then (xs[index.toNat]?).getD fallback else fallback) = fallback := by
      split
      · rw [List.getElem?_eq_none (by omega)]; rfl
      · rfl
    rw [result]
    exact PureRun.guardTaken cond (PureRun.ret fE (RunsExpr.local' l2)) nofun

/-- `core::option::Option<T>` of a Lean option: `Some` is variant 0. -/
def optionValue (option : TypeId) : Option Value → Value
  | some x => .enumeration option 0 [x]
  | none => .enumeration option 1 []

/-- `get(v, index)`: `Some` of element `index`, or `None` out of range. -/
theorem get_spec (inst : VecInstance P T ids) (kind : ElemKind P T size) {caller : State}
    (formed : caller.CellsWellFormed) {v : Value} {xs : List Value}
    (rep : VecRep P T size ids.vec caller.heap v xs) (index : Int) :
    ∃ after, RunsExpr P caller (.call ids.get ([v, .signed .i32 index].map Expr.value))
      (optionValue ids.option (if 0 ≤ index then xs[index.toNat]? else none)) after ∧
      PureFrame caller after := by
  obtain ⟨p, cap, rfl, lenLe, capBound, buffer, reads⟩ := rep
  refine PureRun.call inst.get rfl rfl formed ?_
  let E0 : State := { caller with locals := [] }
  have f0 : E0.CellsWellFormed := formed
  let vv := Value.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]
  have f1 := f0.bindLocal 0 vv
  let E := (E0.bindLocal 0 vv).bindLocal 1 (.signed .i32 index)
  change PureRun P E _ _
  have fE : E.CellsWellFormed := f1.bindLocal _ _
  have l1 : E.local? 1 = some (.signed .i32 index) := local_bound f1 1 _
  have l0 : E.local? 0 = some vv := local_kept f1 _ (by decide) (local_bound f0 0 _)
  have cond := outOfRange_run (P := P) l0 l1
  by_cases inRange : 0 ≤ index ∧ index < xs.length
  · obtain ⟨i, rfl⟩ := Int.eq_ofNat_of_zero_le inRange.1
    have hi : i < xs.length := by omega
    rw [if_pos inRange.1, Int.toNat_natCast, List.getElem?_eq_getElem hi]
    have isFalse : (decide ((i : Int) < 0) || decide ((i : Int) ≥ xs.length)) = false := by
      simp; omega
    rw [isFalse] at cond
    refine PureRun.guardSkip cond ?_
    obtain ⟨S', slots, frame⟩ := slots_call inst kind fE l0 capBound buffer
    refine PureRun.letRun slots frame ?_
    have fS : S'.CellsWellFormed := frame.afterFormed
    have heap : (S'.bindLocal 2 (.rawSlice T (viewAddr T size p cap) cap)).heap = caller.heap := frame.heap
    exact PureRun.ret (fS.bindLocal _ _) (RunsExprs.toEnum (RunsExprs.one (RunsExpr.rawIndex
      (local_bound fS 2 _) (local_kept fS _ (by decide) (frame.localFound l1))
      (reads i hi _ (by rw [heap]; exact ReadsWithin.refl _ _ _)))))
  · have isTrue : (decide (index < 0) || decide (index ≥ xs.length)) = true := by
      simp; omega
    rw [isTrue] at cond
    have result : (if 0 ≤ index then xs[index.toNat]? else none) = none := by
      split
      · rw [List.getElem?_eq_none (by omega)]
      · rfl
    rw [result]
    exact PureRun.guardTaken cond (PureRun.ret fE (RunsExprs.toEnum RunsExprs.nil)) nofun

/-! ## The one store -/

theorem ElemKind.i32_size (kind : ElemKind P T size) (scalar : T = i32Ty) : size = 4 := by
  cases kind with
  | i32 => rfl
  | «structure» => cases scalar
  | enumeration => cases scalar

/-- `try_set(v, index, x)` in range: the call returns `v` itself, changes
exactly the bytes of element `index`'s slot, and `v` then represents the list
with that element replaced. The other elements read as before because their
slots are apart from the written one. -/
theorem trySet_spec (inst : VecInstance P T ids) (kind : ElemKind P T size) {caller : State}
    (formed : caller.CellsWellFormed) {v : Value} {xs : List Value}
    (rep : VecRep P T size ids.vec caller.heap v xs) {i : Nat} (inside : i < xs.length)
    {x : Value} (store : ElemStore P T size x)
    (noViews : caller.i32ArrayViews = []) (unique : HeapBlockBasesUnique caller.heap) :
    ∃ after, RunsExpr P caller (.call ids.trySet ([v, .signed .i32 i, x].map Expr.value)) v after ∧
      FreshCellFrame caller after ∧ after.world = caller.world ∧
      after.i32ArrayViews = caller.i32ArrayViews ∧
      VecRep P T size ids.vec after.heap v (xs.set i x) ∧
      ∃ p cap : Nat, v = .structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap] ∧
        HeapRegionWrite caller.heap after.heap (slotLo T size p cap i) size := by
  obtain ⟨p, cap, rfl, lenLe, capBound, buffer, reads⟩ := rep
  let vv := Value.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]
  have hcap : i < cap := by omega
  let lo := slotLo T size p cap i
  let E0 : State := { caller with locals := [] }
  have f0 : E0.CellsWellFormed := formed
  have f1 := f0.bindLocal 0 vv
  have f2 := f1.bindLocal 1 (.signed .i32 i)
  let E := ((E0.bindLocal 0 vv).bindLocal 1 (.signed .i32 i)).bindLocal 2 x
  have fE : E.CellsWellFormed := f2.bindLocal _ _
  have l2 : E.local? 2 = some x := local_bound f2 2 _
  have l1 : E.local? 1 = some (.signed .i32 i) := local_kept f2 _ (by decide) (local_bound f1 1 _)
  have l0 : E.local? 0 = some vv :=
    local_kept f2 _ (by decide) (local_kept f1 _ (by decide) (local_bound f0 0 _))
  have cond := outOfRange_run (P := P) l0 l1
  have isFalse : (decide ((i : Int) < 0) || decide ((i : Int) ≥ xs.length)) = false := by simp; omega
  rw [isFalse] at cond
  obtain ⟨S', slots, frame⟩ := slots_call inst kind fE l0 capBound buffer
  have fS : S'.CellsWellFormed := frame.afterFormed
  let view := Value.rawSlice T (viewAddr T size p cap) cap
  let B := S'.bindLocal 3 view
  have hB : B.heap = caller.heap := frame.heap
  have src : B.local? 3 = some view := local_bound fS 3 _
  have idx : B.local? 1 = some (.signed .i32 (Int.ofNat i)) :=
    local_kept fS _ (by decide) (frame.localFound l1)
  have xv : B.local? 2 = some x := local_kept fS _ (by decide) (frame.localFound l2)
  have v0 : B.local? 0 = some vv := local_kept fS _ (by decide) (frame.localFound l0)
  let base := elemBase T size p cap i
  have slotEq : slotOf T size base = lo := slotOf_elemBase kind.size_eight
  have readable : caller.heap.Readable lo size := by
    have within := slot_inside (T := T) (size := size) (p := p) hcap
    unfold slotLo at within
    exact (buffer (by omega)).2.1.subrange (start := size * slotIndex T cap i) (by omega)
  have room : size ≤ base + 8 := by
    show size ≤ elemBase T size p cap i + 8
    unfold elemBase
    by_cases scalar : T = i32Ty
    · rw [if_pos scalar, kind.i32_size scalar]; omega
    · rw [if_neg scalar]; have := kind.size_eight scalar; omega
  obtain ⟨h', stored, readBack, effect⟩ :=
    store B B.heap base room (by rw [slotEq, hB]; exact readable) (by rw [hB]; exact unique)
  rw [slotEq, hB] at effect
  have nv : B.i32ArrayViews = [] := frame.views.trans noViews
  have assign := StableExpr.assignRaw (before := B) (indexed := B) (ready := B) (heap := h')
    (sourceId := 3) src (StableExpr.local idx) hcap (elementAddress kind hcap) nv (StableExpr.local xv) stored
  let C : State := { B with heap := h' }
  have body : RunsStmt P B (.sequence (.expression (.assign .set (.index (.local 3) (.local 1)) (.local 2)))
      (.returnValue (some (.local 0)))) (.returned (some vv)) C :=
    RunsStmt.sequenceNext (RunsStmt.expression (RunsExpr.ofStable assign rfl))
      (RunsStmt.returnValue (RunsExpr.local' (show C.local? 0 = some vv from v0)))
  have cellsBC : FreshCellFrame B C := ⟨[], by simp [C], Nat.le_refl _, by simp⟩
  have cells : FreshCellFrame E (restoreLocals S' C) := by
    obtain ⟨extra, c, n, fresh⟩ := (frame.cells.trans (FreshCellFrame.bindLocal S' 3 view)).trans cellsBC
    exact ⟨extra, c, n, fresh⟩
  have run : RunsStmt P E (guardReturn (outOfRange 1) (.local 0)
      (.letLocal 3 (.slice T) (.call ids.slots [.local 0])
        (.sequence (.expression (.assign .set (.index (.local 3) (.local 1)) (.local 2)))
          (.returnValue (some (.local 0)))))) (.returned (some vv)) (restoreLocals S' C) :=
    RunsStmt.sequenceNext (RunsStmt.ifThenElseFalse cond (RunsStmt.skip P E)) (RunsStmt.letLocal slots body)
  have rep' : VecRep P T size ids.vec h' vv (xs.set i x) := by
    refine ⟨p, cap, by rw [List.length_set], by rw [List.length_set]; exact lenLe, capBound,
      fun positive => (buffer positive).afterWrite effect, ?_⟩
    intro j jInside other within
    rw [List.length_set] at jInside
    by_cases same : j = i
    · subst same
      rw [List.getElem_set_self, readRawSliceIndex_elem other kind hcap]
      exact readBack other.heap (by rw [slotEq]; exact within)
    · rw [List.getElem_set_ne (fun h => same h.symm)]
      exact reads j jInside other
        (ReadsWithin.trans (HeapRegionWrite.readsApart effect (slots_apart hcap (by omega) (fun h => same h.symm))) within)
  obtain ⟨after, call, cellsAfter, world, views, effect', rep''⟩ := RunsExpr.callStores
    (post := fun heap world views => world = caller.world ∧ views = caller.i32ArrayViews ∧
      HeapRegionWrite caller.heap heap lo size ∧ VecRep P T size ids.vec heap vv (xs.set i x))
    (caller := caller) (values := [vv, .signed .i32 i, x]) (value := vv)
    inst.trySet rfl rfl ⟨restoreLocals S' C, run, cells, frame.world, frame.views, effect, rep'⟩
  exact ⟨after, call, cellsAfter, world, views, rep'', p, cap, rfl, effect'⟩

/-- `try_set` out of range returns `v` and changes nothing. -/
theorem trySet_skip_spec (inst : VecInstance P T ids) {caller : State}
    (formed : caller.CellsWellFormed) {v : Value} {xs : List Value}
    (rep : VecRep P T size ids.vec caller.heap v xs) {index : Int}
    (outside : ¬(0 ≤ index ∧ index < xs.length)) (x : Value) :
    ∃ after, RunsExpr P caller (.call ids.trySet ([v, .signed .i32 index, x].map Expr.value)) v after ∧
      PureFrame caller after := by
  obtain ⟨p, cap, rfl, _⟩ := rep
  let vv := Value.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]
  refine PureRun.call inst.trySet rfl rfl formed ?_
  let E0 : State := { caller with locals := [] }
  have f0 : E0.CellsWellFormed := formed
  have f1 := f0.bindLocal 0 vv
  have f2 := f1.bindLocal 1 (.signed .i32 index)
  let E := ((E0.bindLocal 0 vv).bindLocal 1 (.signed .i32 index)).bindLocal 2 x
  change PureRun P E _ _
  have fE : E.CellsWellFormed := f2.bindLocal _ _
  have l1 : E.local? 1 = some (.signed .i32 index) := local_kept f2 _ (by decide) (local_bound f1 1 _)
  have l0 : E.local? 0 = some vv :=
    local_kept f2 _ (by decide) (local_kept f1 _ (by decide) (local_bound f0 0 _))
  have cond := outOfRange_run (P := P) l0 l1
  have isTrue : (decide (index < 0) || decide (index ≥ xs.length)) = true := by simp; omega
  rw [isTrue] at cond
  exact PureRun.guardTaken cond (PureRun.ret fE (RunsExpr.local' l0)) nofun

/-! ## Shrinking without freeing -/

theorem tryPop_spec (inst : VecInstance P T ids) {caller : State} (formed : caller.CellsWellFormed)
    {v : Value} {xs : List Value} (rep : VecRep P T size ids.vec caller.heap v xs) :
    ∃ after v', RunsExpr P caller (.call ids.tryPop ([v].map Expr.value)) v' after ∧
      PureFrame caller after ∧ VecRep P T size ids.vec caller.heap v' xs.dropLast := by
  obtain ⟨p, cap, rfl, lenLe, capBound, buffer, reads⟩ := rep
  let vv := Value.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]
  by_cases empty : xs = []
  · subst empty
    obtain ⟨after, run, frame⟩ : ∃ after, RunsExpr P caller (.call ids.tryPop ([vv].map Expr.value)) vv after ∧
        PureFrame caller after := by
      refine PureRun.call inst.tryPop rfl rfl formed ?_
      let E0 : State := { caller with locals := [] }
      have f0 : E0.CellsWellFormed := formed
      change PureRun P (E0.bindLocal 0 vv) _ _
      have l0 := local_bound f0 0 vv
      refine PureRun.guardTaken (RunsExpr.binary (RunsExpr.field' (RunsExpr.local' l0) rfl)
        (RunsExpr.value' _) (by decide) (eval_i32_eq _ _ _)) (PureRun.ret (f0.bindLocal _ _)
        (RunsExpr.local' l0)) nofun
    exact ⟨after, vv, run, frame, p, cap, rfl, lenLe, capBound, buffer, fun i inside => absurd inside (by simp)⟩
  · have positive : 0 < xs.length := List.length_pos_iff.mpr empty
    let popped := Value.structure ids.vec [.pointer p, .signed .i32 xs.dropLast.length, .signed .i32 cap]
    obtain ⟨after, run, frame⟩ : ∃ after, RunsExpr P caller (.call ids.tryPop ([vv].map Expr.value)) popped after ∧
        PureFrame caller after := by
      refine PureRun.call inst.tryPop rfl rfl formed ?_
      let E0 : State := { caller with locals := [] }
      have f0 : E0.CellsWellFormed := formed
      change PureRun P (E0.bindLocal 0 vv) _ _
      have l0 := local_bound f0 0 vv
      have isFalse : ((xs.length : Int) == 0) = false := by simp; omega
      refine PureRun.guardSkip (by
        have := RunsExpr.binary (program := P) (RunsExpr.field' (j := 1) (RunsExpr.local' l0) rfl)
          (RunsExpr.value' (.signed .i32 0)) (by decide) (eval_i32_eq _ _ _)
        rwa [isFalse] at this) ?_
      have dropped : ((xs.dropLast.length : Nat) : Int) = (xs.length : Int) - 1 := by
        rw [List.length_dropLast]; omega
      have sub : evalBinaryValue P.target .subtract (.signed .i32 (xs.length : Int)) (.signed .i32 1) =
          .ok (.signed .i32 ((xs.length : Int) - 1)) := by
        rw [inst.target]; exact eval_i32_sub (by omega) (by omega)
      have decrement := RunsExpr.binary (RunsExpr.field' (j := 1) (RunsExpr.local' l0) rfl) (RunsExpr.value' _)
        (by decide) sub
      rw [← dropped] at decrement
      exact PureRun.ret (f0.bindLocal _ _) (RunsExprs.toRun (RunsExprs.three
        (RunsExpr.field' (RunsExpr.local' l0) rfl) decrement
        (RunsExpr.field' (RunsExpr.local' l0) rfl)))
    refine ⟨after, popped, run, frame, p, cap, rfl, by simp; omega, capBound, buffer, ?_⟩
    intro i inside other within
    rw [List.getElem_dropLast]
    exact reads i (by simp at inside; omega) other within

theorem truncate_spec (inst : VecInstance P T ids) {caller : State} (formed : caller.CellsWellFormed)
    {v : Value} {xs : List Value} (rep : VecRep P T size ids.vec caller.heap v xs) (length : Int) :
    ∃ after v', RunsExpr P caller (.call ids.truncate ([v, .signed .i32 length].map Expr.value)) v' after ∧
      PureFrame caller after ∧
      VecRep P T size ids.vec caller.heap v' (if 0 ≤ length then xs.take length.toNat else xs) := by
  obtain ⟨p, cap, rfl, lenLe, capBound, buffer, reads⟩ := rep
  let vv := Value.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]
  by_cases shorter : 0 ≤ length ∧ length < xs.length
  · obtain ⟨n, rfl⟩ := Int.eq_ofNat_of_zero_le shorter.1
    have hn : n < xs.length := by omega
    rw [if_pos shorter.1, Int.toNat_natCast]
    let cut := Value.structure ids.vec [.pointer p, .signed .i32 (xs.take n).length, .signed .i32 cap]
    obtain ⟨after, run, frame⟩ : ∃ after, RunsExpr P caller
        (.call ids.truncate ([vv, .signed .i32 n].map Expr.value)) cut after ∧ PureFrame caller after := by
      refine PureRun.call inst.truncate rfl rfl formed ?_
      let E0 : State := { caller with locals := [] }
      have f0 : E0.CellsWellFormed := formed
      have f1 := f0.bindLocal 0 vv
      change PureRun P ((E0.bindLocal 0 vv).bindLocal 1 _) _ _
      have l1 := local_bound f1 1 (.signed .i32 n)
      have l0 := local_kept f1 (new := 1) (.signed .i32 n) (by decide) (local_bound f0 0 vv)
      have cond := outOfRange_run (P := P) l0 l1
      have isFalse : (decide ((n : Int) < 0) || decide ((n : Int) ≥ xs.length)) = false := by simp; omega
      rw [isFalse] at cond
      refine PureRun.guardSkip cond ?_
      have taken : ((xs.take n).length : Int) = n := by rw [List.length_take]; omega
      exact PureRun.ret (f1.bindLocal _ _) (RunsExprs.toRun (RunsExprs.three
        (RunsExpr.field' (RunsExpr.local' l0) rfl) (by rw [taken]; exact RunsExpr.local' l1)
        (RunsExpr.field' (RunsExpr.local' l0) rfl)))
    refine ⟨after, cut, run, frame, p, cap, rfl, by simp; omega, capBound, buffer, ?_⟩
    intro i inside other within
    rw [List.getElem_take]
    exact reads i (by simp at inside; omega) other within
  · have same : (if 0 ≤ length then xs.take length.toNat else xs) = xs := by
      split
      · exact List.take_of_length_le (by omega)
      · rfl
    rw [same]
    obtain ⟨after, run, frame⟩ : ∃ after, RunsExpr P caller
        (.call ids.truncate ([vv, .signed .i32 length].map Expr.value)) vv after ∧ PureFrame caller after := by
      refine PureRun.call inst.truncate rfl rfl formed ?_
      let E0 : State := { caller with locals := [] }
      have f0 : E0.CellsWellFormed := formed
      have f1 := f0.bindLocal 0 vv
      change PureRun P ((E0.bindLocal 0 vv).bindLocal 1 _) _ _
      have l1 := local_bound f1 1 (.signed .i32 length)
      have l0 := local_kept f1 (new := 1) (.signed .i32 length) (by decide) (local_bound f0 0 vv)
      have cond := outOfRange_run (P := P) l0 l1
      have isTrue : (decide (length < 0) || decide (length ≥ xs.length)) = true := by simp; omega
      rw [isTrue] at cond
      exact PureRun.guardTaken cond (PureRun.ret (f1.bindLocal _ _) (RunsExpr.local' l0)) nofun
    exact ⟨after, vv, run, frame, p, cap, rfl, lenLe, capBound, buffer, reads⟩

theorem clear_spec (inst : VecInstance P T ids) {caller : State} (formed : caller.CellsWellFormed)
    {v : Value} {xs : List Value} (rep : VecRep P T size ids.vec caller.heap v xs) :
    ∃ after v', RunsExpr P caller (.call ids.clear ([v].map Expr.value)) v' after ∧
      PureFrame caller after ∧ VecRep P T size ids.vec caller.heap v' [] := by
  obtain ⟨p, cap, rfl, lenLe, capBound, buffer, reads⟩ := rep
  let vv := Value.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]
  let cleared := Value.structure ids.vec [.pointer p, .signed .i32 0, .signed .i32 cap]
  obtain ⟨after, run, frame⟩ : ∃ after, RunsExpr P caller (.call ids.clear ([vv].map Expr.value)) cleared after ∧
      PureFrame caller after := by
    refine PureRun.call inst.clear rfl rfl formed ?_
    let E0 : State := { caller with locals := [] }
    have f0 : E0.CellsWellFormed := formed
    change PureRun P (E0.bindLocal 0 vv) _ _
    have l0 := local_bound f0 0 vv
    exact PureRun.ret (f0.bindLocal _ _) (RunsExprs.toRun (RunsExprs.three
      (RunsExpr.field' (RunsExpr.local' l0) rfl) (RunsExpr.value' _) (RunsExpr.field' (RunsExpr.local' l0) rfl)))
  exact ⟨after, cleared, run, frame, p, cap, rfl, Nat.zero_le _, capBound, buffer, fun i inside => absurd inside (by simp)⟩

#print axioms slots_spec
#print axioms new_spec
#print axioms len_spec
#print axioms capacity_spec
#print axioms isEmpty_spec
#print axioms clear_spec
#print axioms getOr_spec
#print axioms get_spec
#print axioms trySet_spec
#print axioms trySet_skip_spec
#print axioms truncate_spec
#print axioms tryPop_spec

end Lanius.Std
