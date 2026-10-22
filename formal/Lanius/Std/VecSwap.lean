import Lanius.Std.HeapSortMath

/-! # Swaps and comparisons through a slice

`let held = items[i]; items[i] = items[j]; items[j] = held; rest` and the
call `T::lt(items[x], items[y])`, for an array `a` held in the slots of a
buffer. -/

namespace Lanius.Std

open Lanius Lanius.Core Lanius.Semantics Lanius.Memory

variable {P : Program} {T : Ty} {size : Nat}

/-- The slots of `[p, p + size * cap)` hold `a`. -/
def ArrayAt (P : Program) (T : Ty) (size : Nat) (h : Heap) (p cap : Nat) (a : List Value) : Prop :=
  ∀ j, j < a.length → ∀ other : State, ReadsWithin h other.heap (slotLo T size p cap j) size →
    readRawSliceIndex P other T (viewAddr T size p cap) cap j = .ok (elt a j)

theorem elt_mem {a : List Value} {i : Nat} (inside : i < a.length) : elt a i ∈ a := by
  unfold elt; rw [getD_of_lt inside]; exact List.getElem_mem _

theorem RunsExpr.callUnitReturned {caller completed : State} {f : FunctionId} {fn : Function} {body : Stmt}
    {arguments : List Expr} {values : List Value} {afterArguments : State} {bindings : List (VarId × Value)}
    (found : P.function? f = some fn) (bodyFound : fn.body = some body) (returnsUnit : fn.returnType = .unit)
    (argumentsRun : RunsExprs P caller arguments values afterArguments)
    (parameters : bindParameters fn.parameters values = some bindings)
    (bodyRun : RunsStmt P (({ afterArguments with locals := [] }).bindLocals bindings) body (.returned none)
      completed) :
    RunsExpr P caller (.call f arguments) .unit (restoreLocals caller completed) := by
  obtain ⟨argumentsFuel, argumentsRun, locals⟩ := argumentsRun
  obtain ⟨bodyFuel, bodyRun, _⟩ := bodyRun
  refine ⟨max argumentsFuel bodyFuel + 1, ?_, rfl⟩
  intro fuel enough
  rw [show fuel = (fuel - 1).succ by omega, evalExpr.eq_def]
  simp only [argumentsRun (fuel - 1) (by omega), found, bodyFound, parameters,
    bodyRun (fuel - 1) (by omega), returnsUnit, ↓reduceIte, restoreLocals, locals]

/-- The slot of element `j` is readable and room for a store. -/
theorem slot_ready (kind : ElemKind P T size) {h0 h : Heap} {p cap j : Nat} (jc : j < cap)
    (buffer : 0 < cap → Buffer h0 p (size * cap)) (effect : HeapRegionWrite h0 h p (size * cap)) :
    h.Readable (slotOf T size (elemBase T size p cap j)) size ∧ size ≤ elemBase T size p cap j + 8 := by
  refine ⟨?_, ?_⟩
  · rw [slotOf_elemBase kind.size_eight]
    have within := slot_inside (T := T) (size := size) (p := p) jc
    unfold slotLo at within ⊢
    exact ((buffer (by omega)).afterWrite effect).2.1.subrange (start := size * slotIndex T cap j) (by omega)
  · unfold elemBase
    by_cases scalar : T = i32Ty
    · rw [if_pos scalar, kind.i32_size scalar]; omega
    · rw [if_neg scalar]; have := kind.size_eight scalar; omega

/-- A local agreement: `t` has every local of `s` except `held`. -/
def Agrees (s t : State) (held : VarId) : Prop := ∀ id v, id ≠ held → s.local? id = some v → t.local? id = some v

theorem swap_run (kind : ElemKind P T size) {s : State} (formed : s.CellsWellFormed) {items held : VarId}
    {ei ej : Expr} {i j p cap : Nat} {a : List Value} {h0 : Heap}
    (itemsFound : s.local? items = some (.rawSlice T (viewAddr T size p cap) cap)) (heldNe : items ≠ held)
    (ri : ∀ t : State, Agrees s t held → ∃ k, StableExpr k P t ei (.signed .i32 (Int.ofNat i)) t)
    (rj : ∀ t : State, Agrees s t held → ∃ k, StableExpr k P t ej (.signed .i32 (Int.ofNat j)) t)
    (hi : i < a.length) (hj : j < a.length) (ne : i ≠ j) (len : a.length ≤ cap)
    (buffer : 0 < cap → Buffer h0 p (size * cap)) (effect : HeapRegionWrite h0 s.heap p (size * cap))
    (arr : ArrayAt P T size s.heap p cap a) (stores : ∀ y ∈ a, ElemStore P T size y)
    (noViews : s.i32ArrayViews = []) :
    ∃ h2, ArrayAt P T size h2 p cap (swapAt a i j) ∧ HeapRegionWrite h0 h2 p (size * cap) ∧
      ∀ rest k R, RunsStmt P ({ s.bindLocal held (elt a i) with heap := h2 }) rest k R →
        RunsStmt P s (.letLocal held T (.index (.local items) ei)
          (.sequence (.expression (.assign .set (.index (.local items) ei) (.index (.local items) ej)))
          (.sequence (.expression (.assign .set (.index (.local items) ej) (.local held))) rest)))
          k (restoreLocals s R) := by
  have ic : i < cap := by omega
  have jc : j < cap := by omega
  have readI := arr i hi s (ReadsWithin.refl _ _ _)
  obtain ⟨ki, si⟩ := ri s (fun _ _ _ f => f)
  have heldRun : RunsExpr P s (.index (.local items) ei) (elt a i) s :=
    RunsExpr.ofStable (StableExpr.rawSliceIndexAt itemsFound si readI) rfl
  let s1 := s.bindLocal held (elt a i)
  have agree1 : ∀ hh : Heap, Agrees s ({ s1 with heap := hh } : State) held :=
    fun _ id v ne f => local_kept formed _ (Ne.symm ne) f
  have s1_items : ∀ hh : Heap, ({ s1 with heap := hh } : State).local? items = some (.rawSlice T (viewAddr T size p cap) cap) :=
    fun hh => agree1 hh items _ heldNe itemsFound
  have s1_held : ∀ hh : Heap, ({ s1 with heap := hh } : State).local? held = some (elt a i) :=
    fun _ => local_bound formed held _
  -- items[i] = items[j]
  have readJ := arr j hj ({ s1 with heap := s.heap } : State) (ReadsWithin.refl _ _ _)
  obtain ⟨kj1, sj1⟩ := rj _ (agree1 s.heap)
  obtain ⟨ki1, si1⟩ := ri _ (agree1 s.heap)
  have slotEq : ∀ m, slotOf T size (elemBase T size p cap m) = slotLo T size p cap m :=
    fun m => slotOf_elemBase kind.size_eight
  obtain ⟨readyI, roomI⟩ := slot_ready kind ic buffer effect
  obtain ⟨h1, stored1, readBack1, written1⟩ := stores (elt a j) (elt_mem hj) ({ s1 with heap := s.heap } : State)
    s.heap (elemBase T size p cap i) roomI readyI effect.unique
  rw [slotEq] at written1
  have assign1 := StableExpr.assignRaw (before := { s1 with heap := s.heap }) (indexed := { s1 with heap := s.heap })
    (ready := { s1 with heap := s.heap }) (heap := h1) (sourceId := items) (s1_items s.heap) si1 ic
    (elementAddress kind ic) noViews (StableExpr.rawSliceIndexAt (s1_items s.heap) sj1 readJ) stored1
  have effect1 : HeapRegionWrite h0 h1 p (size * cap) := by
    have sl := slot_inside (T := T) (size := size) (p := p) ic
    exact effect.trans (written1.enlarge sl.1 sl.2)
  -- items[j] = held
  obtain ⟨kj2, sj2⟩ := rj _ (agree1 h1)
  obtain ⟨readyJ, roomJ⟩ := slot_ready kind jc buffer effect1
  obtain ⟨h2, stored2, readBack2, written2⟩ := stores (elt a i) (elt_mem hi) ({ s1 with heap := h1 } : State)
    h1 (elemBase T size p cap j) roomJ readyJ effect1.unique
  rw [slotEq] at written2
  have assign2 := StableExpr.assignRaw (before := { s1 with heap := h1 }) (indexed := { s1 with heap := h1 })
    (ready := { s1 with heap := h1 }) (heap := h2) (sourceId := items) (s1_items h1) sj2 jc
    (elementAddress kind jc) noViews (StableExpr.local (s1_held h1)) stored2
  have effect2 : HeapRegionWrite h0 h2 p (size * cap) := by
    have sl := slot_inside (T := T) (size := size) (p := p) jc
    exact effect1.trans (written2.enlarge sl.1 sl.2)
  refine ⟨h2, fun m mlen other within => ?_, effect2, fun rest k R restRun => ?_⟩
  · rw [length_swapAt] at mlen
    have mc : m < cap := by omega
    rw [elt_swapAt hi hj]
    by_cases mj : m = j
    · rw [if_pos mj, mj, readRawSliceIndex_elem other kind jc]
      rw [mj] at within
      exact readBack2 other.heap (by rw [slotEq]; exact within)
    · rw [if_neg mj]
      by_cases mi : m = i
      · rw [if_pos mi, mi, readRawSliceIndex_elem other kind ic]
        rw [mi] at within
        exact readBack1 other.heap (by
          rw [slotEq]
          exact ReadsWithin.trans (HeapRegionWrite.readsApart written2 (slots_apart jc ic (Ne.symm ne))) within)
      · rw [if_neg mi]
        exact arr m mlen other (ReadsWithin.trans
          (HeapRegionWrite.readsApart written1 (slots_apart ic mc (fun e => mi e.symm)))
          (ReadsWithin.trans (HeapRegionWrite.readsApart written2 (slots_apart jc mc (fun e => mj e.symm))) within))
  · exact RunsStmt.letLocal heldRun (RunsStmt.sequenceNext (RunsStmt.expression (RunsExpr.ofStable assign1 rfl))
      (RunsStmt.sequenceNext (RunsStmt.expression (RunsExpr.ofStable assign2 rfl)) restRun))

/-- `T::lt(items[x], items[y])` for pure index expressions. -/
theorem lt_call {lt : FunctionId} {ltv : Value → Value → Bool} {vals : List Value} (ltSpec : LtSpec P lt ltv vals)
    {t : State} (formed : t.CellsWellFormed) {items : VarId} {ex ey : Expr} {x y p cap kx ky : Nat}
    {a : List Value} (itemsFound : t.local? items = some (.rawSlice T (viewAddr T size p cap) cap))
    (sx : StableExpr kx P t ex (.signed .i32 (Int.ofNat x)) t) (sy : StableExpr ky P t ey (.signed .i32 (Int.ofNat y)) t)
    (hx : x < a.length) (hy : y < a.length) (arr : ArrayAt P T size t.heap p cap a) (sub : ∀ z ∈ a, z ∈ vals) :
    ∃ t', RunsExpr P t (.call lt [.index (.local items) ex, .index (.local items) ey])
      (.boolean (ltv (elt a x) (elt a y))) t' ∧ PureFrame t t' := by
  obtain ⟨t', call, pure⟩ := ltSpec t formed (elt a x) (sub _ (elt_mem hx)) (elt a y) (sub _ (elt_mem hy))
  refine ⟨t', callArgs (RunsExprs.two
    (RunsExpr.ofStable (StableExpr.rawSliceIndexAt itemsFound sx (arr x hx t (ReadsWithin.refl _ _ _))) rfl)
    (RunsExpr.ofStable (StableExpr.rawSliceIndexAt itemsFound sy (arr y hy t (ReadsWithin.refl _ _ _))) rfl)) call, pure⟩

#print axioms swap_run
#print axioms lt_call

end Lanius.Std
