import Lanius.Std.MapSpec

/-! # `std::map::try_set`

`try_set(m, key, item)` finds `key` and, when present, stores the entry
`(key, item)` through the `as_slice` view at that ordinal. The keys stay
distinct when `eqv` is transitive. -/

namespace Lanius.Std

open Lanius Lanius.Core Lanius.Semantics Lanius.Memory

variable {P : Program} {T : Ty} {ids : VecIds} {size : Nat}

/-- `try_set(value, key, item) -> bool`, with locals 3 `index`, 4 `entries`. -/
def mapTrySetFn (K V T : Ty) (mid eid : TypeId) (f fnd asl : FunctionId) : Function where
  id := f
  parameters := [(0, setTy mid), (1, K), (2, V)]
  returnType := boolTy
  body := some <| .letLocal 3 i32Ty (.call fnd [.local 0, .local 1])
    (guardReturn (.binary .less (.local 3) (int 0)) (.value (.boolean false))
    (.letLocal 4 (.slice T) (.call asl [setItems])
      (.sequence (.expression (.assign .set (.index (.local 4) (.local 3)) (.structValue eid [.local 1, .local 2])))
        (.returnValue (some (.value (.boolean true)))))))

/-- Replacing the first key `eqv`-equal to `key` by `key` keeps the keys distinct. -/
theorem Distinct.setFirst {eqv : Value → Value → Bool} {ks : List Value} (distinct : Distinct eqv ks) {i : Nat}
    (inside : i < ks.length) {key : Value} (same : eqv ks[i] key = true)
    (before : ∀ j (below : j < i), eqv (ks[j]'(by omega)) key = false)
    (trans : ∀ a b c, eqv a b = true → eqv b c = true → eqv a c = true) :
    Distinct eqv (ks.set i key) := by
  unfold Distinct at distinct ⊢
  rw [List.pairwise_iff_getElem] at distinct ⊢
  intro a b ha hb lt
  rw [List.length_set] at ha hb
  rw [List.getElem_set, List.getElem_set]
  by_cases ai : i = a
  · subst ai
    have bi : ¬ i = b := by omega
    rw [if_pos rfl, if_neg bi]
    cases e : eqv key ks[b] with
    | false => rfl
    | true =>
        have := distinct i b ha hb lt
        rw [trans _ _ _ same e] at this
        exact this
  · rw [if_neg ai]
    by_cases bi : i = b
    · subst bi
      rw [if_pos rfl]
      exact before a lt
    · rw [if_neg bi]
      exact distinct a b ha hb lt

/-- `try_set(m, key, item)` with `key` absent returns false. -/
theorem mapTrySet_absent_spec {mid eid : TypeId} {K V : Ty} {fi : MapFindIds}
    (inst : MapFindInstance P T ids mid fi) (kind : ElemKind P T size) {fnd f : FunctionId}
    (fndFound : P.function? fnd = some (mapFindFn K T mid fnd fi.asl fi.ml fi.eq))
    (found : P.function? f = some (mapTrySetFn K V T mid eid f fnd fi.asl))
    {eqv : Value → Value → Bool} {vals : List Value} (eqSpec : EqSpec P fi.eq eqv vals)
    {caller : State} (formed : caller.CellsWellFormed) {kvs : List (Value × Value)} {p cap : Nat} {key : Value}
    (rep : VecRep P T size ids.vec caller.heap
      (.structure ids.vec [.pointer p, .signed .i32 (kvs.map (entryOf eid)).length, .signed .i32 cap])
      (kvs.map (entryOf eid)))
    (keyIn : key ∈ vals) (sub : ∀ e ∈ kvs, e.1 ∈ vals) (disjoint : HeapBlocksDisjoint caller.heap)
    (missing : kvs.findIdx? (fun e => eqv e.1 key) = none) (item : Value) :
    ∃ after, RunsExpr P caller (.call f
        ([Value.structure mid [.structure ids.vec [.pointer p, .signed .i32 (kvs.map (entryOf eid)).length,
          .signed .i32 cap]], key, item].map Expr.value))
      (.boolean false) after ∧ PureFrame caller after := by
  refine PureRun.call found rfl rfl formed ?_
  obtain ⟨fE, _, l0, l1, _⟩ := map_entry3 (P := P) formed (mid := mid)
    (.structure ids.vec [.pointer p, .signed .i32 (kvs.map (entryOf eid)).length, .signed .i32 cap]) key item
  obtain ⟨S', run, frame⟩ := mapFind_spec inst kind fndFound eqSpec fE rep keyIn sub disjoint
  rw [findResult_none missing] at run
  have fS := frame.afterFormed
  refine PureRun.letRun (callArgs (RunsExprs.two (RunsExpr.local' l0) (RunsExpr.local' l1)) run) frame ?_
  have b3 := local_bound fS 3 (.signed .i32 (-1))
  exact PureRun.guardTaken (RunsExpr.binary (RunsExpr.local' b3) (RunsExpr.value' _) (by decide)
    (by rw [eval_i32_lt]; rfl)) (PureRun.ret (fS.bindLocal _ _) (RunsExpr.value' _)) nofun

/-- `try_set(m, key, item)` with `key` first matching at `i`: returns true,
writes exactly entry `i`'s slot, and the map then holds `(key, item)` at
`i`; the keys stay distinct. -/
theorem mapTrySet_found_spec {mid eid : TypeId} {K V : Ty} {fi : MapFindIds}
    (inst : MapFindInstance P T ids mid fi) (kind : ElemKind P T size) {fnd f : FunctionId}
    (fndFound : P.function? fnd = some (mapFindFn K T mid fnd fi.asl fi.ml fi.eq))
    (found : P.function? f = some (mapTrySetFn K V T mid eid f fnd fi.asl))
    {eqv : Value → Value → Bool} {vals : List Value} (eqSpec : EqSpec P fi.eq eqv vals)
    {caller : State} (formed : caller.CellsWellFormed) {kvs : List (Value × Value)} {p cap : Nat}
    {key item : Value}
    (rep : VecRep P T size ids.vec caller.heap
      (.structure ids.vec [.pointer p, .signed .i32 (kvs.map (entryOf eid)).length, .signed .i32 cap])
      (kvs.map (entryOf eid)))
    (keyIn : key ∈ vals) (sub : ∀ e ∈ kvs, e.1 ∈ vals) (disjoint : HeapBlocksDisjoint caller.heap)
    {i : Nat} (at_ : kvs.findIdx? (fun e => eqv e.1 key) = some i)
    (store : ElemStore P T size (entryOf eid (key, item)))
    (noViews : caller.i32ArrayViews = []) (unique : HeapBlockBasesUnique caller.heap) :
    ∃ after, RunsExpr P caller (.call f
        ([Value.structure mid [.structure ids.vec [.pointer p, .signed .i32 (kvs.map (entryOf eid)).length,
          .signed .i32 cap]], key, item].map Expr.value))
      (.boolean true) after ∧
      FreshCellFrame caller after ∧ after.world = caller.world ∧ after.i32ArrayViews = caller.i32ArrayViews ∧
      VecRep P T size ids.vec after.heap
        (.structure ids.vec [.pointer p, .signed .i32 (kvs.map (entryOf eid)).length, .signed .i32 cap])
        ((kvs.set i (key, item)).map (entryOf eid)) ∧
      HeapRegionWrite caller.heap after.heap (slotLo T size p cap i) size ∧
      (Distinct eqv (kvs.map Prod.fst) → (∀ a b c, eqv a b = true → eqv b c = true → eqv a c = true) →
        Distinct eqv ((kvs.set i (key, item)).map Prod.fst)) := by
  let xs := kvs.map (entryOf eid)
  let x := entryOf eid (key, item)
  let vv := Value.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]
  obtain ⟨inside, hit, earlier⟩ := List.findIdx?_eq_some_iff_getElem.mp at_
  have inside' : i < xs.length := by show i < (kvs.map (entryOf eid)).length; rw [List.length_map]; exact inside
  obtain ⟨_, lenLe, capBound, buffer, reads⟩ := rep.fields
  have hcap : i < cap := Nat.lt_of_lt_of_le inside' lenLe
  let lo := slotLo T size p cap i
  -- the keys
  have keys : Distinct eqv (kvs.map Prod.fst) → (∀ a b c, eqv a b = true → eqv b c = true → eqv a c = true) →
      Distinct eqv ((kvs.set i (key, item)).map Prod.fst) := fun distinct trans => by
    rw [List.map_set]
    refine Distinct.setFirst distinct (by rw [List.length_map]; exact inside) ?_ (fun j below => ?_) trans
    · rw [List.getElem_map]; exact hit
    · rw [List.getElem_map]
      have := earlier j below
      simpa using this
  rw [List.map_set]
  -- the entry: find, the guard, and the view
  obtain ⟨fE, _, l0, l1, l2⟩ := map_entry3 (P := P) formed (mid := mid) vv key item
  obtain ⟨S', run, frame⟩ := mapFind_spec inst kind fndFound eqSpec fE rep keyIn sub disjoint
  rw [findResult_some at_] at run
  have fS := frame.afterFormed
  have hS : S'.heap = caller.heap := frame.heap
  let B := S'.bindLocal 3 (.signed .i32 (i : Int))
  have fB : B.CellsWellFormed := fS.bindLocal _ _
  have b3 : B.local? 3 = some (.signed .i32 (i : Int)) := local_bound fS 3 _
  have b0 : B.local? 0 = some (.structure mid [vv]) := local_kept fS _ (by decide) (frame.localFound l0)
  have b1 : B.local? 1 = some key := local_kept fS _ (by decide) (frame.localFound l1)
  have b2 : B.local? 2 = some item := local_kept fS _ (by decide) (frame.localFound l2)
  have hB : B.heap = caller.heap := hS
  have cond : RunsExpr P B (.binary .less (.local 3) (int 0)) (.boolean false) B :=
    RunsExpr.binary (RunsExpr.local' b3) (RunsExpr.value' _) (by decide) (by rw [eval_i32_lt]; simp)
  obtain ⟨S2, slRun, frame2⟩ := asSlice_spec inst.vec kind inst.asl inst.pf fB (by rw [hB]; exact rep)
    (by rw [hB]; exact disjoint)
  have fS2 := frame2.afterFormed
  have h2 : S2.heap = caller.heap := frame2.heap.trans hB
  have addr : prefixAddr T size p cap xs.length = viewAddr T size p cap := if_neg (by omega)
  let C := S2.bindLocal 4 (.rawSlice T (prefixAddr T size p cap xs.length) xs.length)
  have fC : C.CellsWellFormed := fS2.bindLocal _ _
  have hC : C.heap = caller.heap := h2
  have src : C.local? 4 = some (.rawSlice T (viewAddr T size p cap) xs.length) :=
    (local_bound fS2 4 _).trans (by rw [addr])
  have c3 : C.local? 3 = some (.signed .i32 (Int.ofNat i)) := local_kept fS2 _ (by decide) (frame2.localFound b3)
  have c1 : C.local? 1 = some key := local_kept fS2 _ (by decide) (frame2.localFound b1)
  have c2 : C.local? 2 = some item := local_kept fS2 _ (by decide) (frame2.localFound b2)
  -- the store
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
    store C C.heap base room (by rw [slotEq, hC]; exact readable) (by rw [hC]; exact unique)
  rw [slotEq, hC] at effect
  have nv : C.i32ArrayViews = [] := (frame2.views.trans frame.views).trans noViews
  obtain ⟨_, rightStable, _⟩ : RunsExpr P C (.structValue eid [.local 1, .local 2]) x C :=
    RunsExpr.structValue (RunsExprs.two (RunsExpr.local' c1) (RunsExpr.local' c2))
  have assign := StableExpr.assignRaw (before := C) (indexed := C) (ready := C) (heap := h')
    (sourceId := 4) src (StableExpr.local c3) inside' (elementAddress kind hcap) nv rightStable stored
  let D : State := { C with heap := h' }
  have body : RunsStmt P C (.sequence (.expression (.assign .set (.index (.local 4) (.local 3))
      (.structValue eid [.local 1, .local 2]))) (.returnValue (some (.value (.boolean true)))))
      (.returned (some (.boolean true))) D :=
    RunsStmt.sequenceNext (RunsStmt.expression (RunsExpr.ofStable assign rfl))
      (RunsStmt.returnValue (RunsExpr.value' _))
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
        (ReadsWithin.trans (HeapRegionWrite.readsApart effect (slots_apart hcap (Nat.lt_of_lt_of_le jInside lenLe) (fun h => same h.symm)))
          within)
  obtain ⟨final, call, cellsF, worldF, viewsF, repF, writeF⟩ := Grow.call (vs := [.structure mid [vv], key, item])
    (bindings := [(0, .structure mid [vv]), (1, key), (2, item)])
    (Q := fun H => VecRep P T size ids.vec H vv (xs.set i x) ∧ HeapRegionWrite caller.heap H lo size) found rfl rfl
    (Grow.letRun (callArgs (RunsExprs.two (RunsExpr.local' l0) (RunsExpr.local' l1)) run) (Ext.ofPure frame)
      (Grow.guardSkip cond (Ext.refl fB)
        (Grow.letRun (callArgs (RunsExprs.one (RunsExpr.field' (j := 0) (RunsExpr.local' b0) rfl)) slRun)
          (Ext.ofPure frame2)
          ⟨D, body, Ext.heap fC h', rep', effect⟩)))
  exact ⟨final, call, cellsF, worldF, viewsF, repF, writeF, keys⟩

#print axioms Distinct.setFirst
#print axioms mapTrySet_absent_spec
#print axioms mapTrySet_found_spec

end Lanius.Std
