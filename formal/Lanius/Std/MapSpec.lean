import Lanius.Std.MapFind

/-! # `std::map`: lookups, insertion and removal

Built on `find` (`MapFind`). A map of key-value pairs `kvs` is the vector
`kvs.map (entryOf eid)` wrapped in `.structure mid [_]`; its invariant is
`Distinct eqv (kvs.map Prod.fst)`, which `try_insert` and `try_remove`
preserve. -/

namespace Lanius.Std

open Lanius Lanius.Core Lanius.Semantics Lanius.Memory

variable {P : Program} {T : Ty} {ids : VecIds} {g : GrowIds} {size : Nat}

/-! ## Templates -/

section templates
variable (K V T : Ty) (mid eid : TypeId) (f : FunctionId)

/-- `try_insert(value, key, item)`, with local 3 `entry`. -/
def mapTryInsertFn (g : GrowIds) (fnd : FunctionId) : Function where
  id := f
  parameters := [(0, setTy mid), (1, K), (2, V)]
  returnType := setTy mid
  body := some <| guardReturn (.binary .greaterEqual (.call fnd [.local 0, .local 1]) (int 0)) (.local 0)
    (.letLocal 3 T (.structValue eid [.local 1, .local 2])
      (.returnValue (some (.structValue mid [.call g.tryPush [setItems, .local 3]]))))

/-- `try_remove(value, key)`, with local 2 `index`. -/
def mapTryRemoveFn (fnd vr : FunctionId) : Function where
  id := f
  parameters := [(0, setTy mid), (1, K)]
  returnType := setTy mid
  body := some <| .letLocal 2 i32Ty (.call fnd [.local 0, .local 1])
    (guardReturn (.binary .less (.local 2) (int 0)) (.local 0)
      (.returnValue (some (.structValue mid [.call vr [setItems, .local 2]]))))

end templates

/-! ## List facts -/

theorem findResult_nonneg (eqv : Value → Value → Bool) (key : Value) (kvs : List (Value × Value)) :
    decide (findResult eqv key kvs ≥ 0) = kvs.any (fun e => eqv e.1 key) := by
  unfold findResult
  rw [← List.findIdx?_isSome]
  cases kvs.findIdx? (fun e => eqv e.1 key) with
  | none => decide
  | some i => simp

theorem findResult_none {eqv : Value → Value → Bool} {key : Value} {kvs : List (Value × Value)}
    (missing : kvs.findIdx? (fun e => eqv e.1 key) = none) : findResult eqv key kvs = -1 := by
  unfold findResult; rw [missing]; rfl

theorem findResult_some {eqv : Value → Value → Bool} {key : Value} {kvs : List (Value × Value)} {i : Nat}
    (at_ : kvs.findIdx? (fun e => eqv e.1 key) = some i) : findResult eqv key kvs = i := by
  unfold findResult; rw [at_]; rfl

theorem entry_getElem (eid : TypeId) {kvs : List (Value × Value)} {k : Nat}
    (inside : k < (kvs.map (entryOf eid)).length) :
    (kvs.map (entryOf eid))[k] = .structure eid [(kvs[k]'(by simpa using inside)).1, (kvs[k]'(by simpa using inside)).2] := by
  rw [List.getElem_map]; rfl

theorem map_eraseIdx' {α β : Type} (f : α → β) : ∀ (l : List α) (i : Nat), (l.eraseIdx i).map f = (l.map f).eraseIdx i
  | [], _ => rfl
  | _ :: _, 0 => rfl
  | a :: l, i + 1 => by
      show f a :: (l.eraseIdx i).map f = f a :: (l.map f).eraseIdx i
      rw [map_eraseIdx' f l i]

/-- The entry state of a three-parameter map function. -/
theorem map_entry3 {caller : State} (formed : caller.CellsWellFormed) {mid : TypeId} (v x y : Value) :
    let E := ((({ caller with locals := [] } : State).bindLocal 0 (.structure mid [v])).bindLocal 1 x).bindLocal 2 y
    E.CellsWellFormed ∧ RunsExpr P E setItems v E ∧ E.local? 0 = some (.structure mid [v]) ∧
      E.local? 1 = some x ∧ E.local? 2 = some y := by
  intro E
  have f0 : ({ caller with locals := [] } : State).CellsWellFormed := formed
  have f1 := f0.bindLocal 0 (.structure mid [v])
  have f2 := f1.bindLocal 1 x
  have l0 : E.local? 0 = some (.structure mid [v]) :=
    local_kept f2 _ (by decide) (local_kept f1 _ (by decide) (local_bound f0 0 _))
  exact ⟨f2.bindLocal _ _, RunsExpr.field' (j := 0) (RunsExpr.local' l0) rfl, l0,
    local_kept f2 _ (by decide) (local_bound f1 1 _), local_bound f2 2 _⟩

/-! ## `contains_key` -/

theorem mapContainsKey_spec {mid eid : TypeId} {K : Ty} {fi : MapFindIds} (inst : MapFindInstance P T ids mid fi)
    (kind : ElemKind P T size) {fnd f : FunctionId}
    (fndFound : P.function? fnd = some (mapFindFn K T mid fnd fi.asl fi.ml fi.eq))
    (found : P.function? f = some (mapContainsKeyFn K mid f fnd))
    {eqv : Value → Value → Bool} {vals : List Value} (eqSpec : EqSpec P fi.eq eqv vals)
    {caller : State} (formed : caller.CellsWellFormed) {kvs : List (Value × Value)} {p cap : Nat} {key : Value}
    (rep : VecRep P T size ids.vec caller.heap
      (.structure ids.vec [.pointer p, .signed .i32 (kvs.map (entryOf eid)).length, .signed .i32 cap])
      (kvs.map (entryOf eid)))
    (keyIn : key ∈ vals) (sub : ∀ e ∈ kvs, e.1 ∈ vals) (disjoint : HeapBlocksDisjoint caller.heap) :
    ∃ after, RunsExpr P caller (.call f
        ([Value.structure mid [.structure ids.vec [.pointer p, .signed .i32 (kvs.map (entryOf eid)).length,
          .signed .i32 cap]], key].map Expr.value))
      (.boolean (kvs.any (fun e => eqv e.1 key))) after ∧ PureFrame caller after := by
  refine PureRun.call found rfl rfl formed ?_
  obtain ⟨fE, _, l0, l1⟩ := set_entry2 (P := P) formed (sid := mid)
    (.structure ids.vec [.pointer p, .signed .i32 (kvs.map (entryOf eid)).length, .signed .i32 cap]) key
  obtain ⟨S', run, frame⟩ := mapFind_spec inst kind fndFound eqSpec fE rep keyIn sub disjoint
  obtain ⟨after, cmp, frame'⟩ := RunsExpr.binaryPure (operation := .greaterEqual)
    ⟨S', callArgs (RunsExprs.two (RunsExpr.local' l0) (RunsExpr.local' l1)) run, frame⟩
    (fun m fm => ⟨m, RunsExpr.value' (.signed .i32 0), PureFrame.refl fm.afterFormed⟩) (by decide)
    (eval_i32_ge _ _ _)
  rw [findResult_nonneg] at cmp
  exact ⟨after, RunsStmt.returnValue cmp, frame'⟩

/-! ## `get_or` -/

theorem mapGetOr_spec {mid eid : TypeId} {K V : Ty} {fi : MapFindIds} (inst : MapFindInstance P T ids mid fi)
    (kind : ElemKind P T size) {fnd f : FunctionId}
    (fndFound : P.function? fnd = some (mapFindFn K T mid fnd fi.asl fi.ml fi.eq))
    (found : P.function? f = some (mapGetOrFn K T mid f V fnd fi.asl))
    {eqv : Value → Value → Bool} {vals : List Value} (eqSpec : EqSpec P fi.eq eqv vals)
    {caller : State} (formed : caller.CellsWellFormed) {kvs : List (Value × Value)} {p cap : Nat} {key : Value}
    (rep : VecRep P T size ids.vec caller.heap
      (.structure ids.vec [.pointer p, .signed .i32 (kvs.map (entryOf eid)).length, .signed .i32 cap])
      (kvs.map (entryOf eid)))
    (keyIn : key ∈ vals) (sub : ∀ e ∈ kvs, e.1 ∈ vals) (disjoint : HeapBlocksDisjoint caller.heap)
    (fallback : Value) :
    ∃ after, RunsExpr P caller (.call f
        ([Value.structure mid [.structure ids.vec [.pointer p, .signed .i32 (kvs.map (entryOf eid)).length,
          .signed .i32 cap]], key, fallback].map Expr.value))
      (((kvs.find? (fun e => eqv e.1 key)).map Prod.snd).getD fallback) after ∧ PureFrame caller after := by
  let vv := Value.structure ids.vec [.pointer p, .signed .i32 (kvs.map (entryOf eid)).length, .signed .i32 cap]
  refine PureRun.call found rfl rfl formed ?_
  obtain ⟨fE, _, l0, l1, l2⟩ := map_entry3 (P := P) formed (mid := mid) vv key fallback
  obtain ⟨S', run, frame⟩ := mapFind_spec inst kind fndFound eqSpec fE rep keyIn sub disjoint
  have fS := frame.afterFormed
  have hS : S'.heap = caller.heap := frame.heap
  have args := callArgs (RunsExprs.two (RunsExpr.local' l0) (RunsExpr.local' l1)) run
  rw [List.find?_eq_bind_findIdx?_getElem?]
  cases at_ : kvs.findIdx? (fun e => eqv e.1 key) with
  | none =>
      rw [findResult_none at_] at args
      refine PureRun.letRun args frame ?_
      have b3 := local_bound fS 3 (.signed .i32 (-1))
      have b2 := local_kept fS (.signed .i32 (-1)) (show (3 : VarId) ≠ 2 by decide) (frame.localFound l2)
      exact PureRun.guardTaken (RunsExpr.binary (RunsExpr.local' b3) (RunsExpr.value' _) (by decide)
        (by rw [eval_i32_lt]; rfl)) (PureRun.ret (fS.bindLocal _ _) (RunsExpr.local' b2)) nofun
  | some i =>
      have inside : i < kvs.length := (List.findIdx?_eq_some_iff_findIdx_eq.mp at_).1
      have inside' : i < (kvs.map (entryOf eid)).length := by rw [List.length_map]; exact inside
      rw [findResult_some at_] at args
      show PureRun P _ _ (.returned (some (((kvs[i]?).map Prod.snd).getD fallback)))
      rw [List.getElem?_eq_getElem inside]
      refine PureRun.letRun args frame ?_
      let B := S'.bindLocal 3 (.signed .i32 (i : Int))
      have fB : B.CellsWellFormed := fS.bindLocal _ _
      have b3 : B.local? 3 = some (.signed .i32 (i : Int)) := local_bound fS 3 _
      have b0 : B.local? 0 = some (.structure mid [vv]) := local_kept fS _ (by decide) (frame.localFound l0)
      have hB : B.heap = caller.heap := hS
      refine PureRun.guardSkip (RunsExpr.binary (RunsExpr.local' b3) (RunsExpr.value' _) (by decide)
        (by rw [eval_i32_lt]; simp)) ?_
      obtain ⟨S2, slRun, frame2⟩ := asSlice_spec inst.vec kind inst.asl inst.pf fB (by rw [hB]; exact rep)
        (by rw [hB]; exact disjoint)
      refine PureRun.letRun (callArgs (RunsExprs.one (RunsExpr.field' (j := 0) (RunsExpr.local' b0) rfl)) slRun)
        frame2 ?_
      have fS2 := frame2.afterFormed
      let view := Value.rawSlice T (prefixAddr T size p cap (kvs.map (entryOf eid)).length)
        (kvs.map (entryOf eid)).length
      let C := S2.bindLocal 4 view
      have fC : C.CellsWellFormed := fS2.bindLocal _ _
      have c4 : C.local? 4 = some view := local_bound fS2 4 _
      have c3 : C.local? 3 = some (.signed .i32 (i : Int)) := local_kept fS2 _ (by decide) (frame2.localFound b3)
      have read := entry_read rep inside' C (frame2.heap.trans hB)
      rw [entry_getElem eid inside'] at read
      have entryRun := RunsExpr.rawIndex c4 c3 read
      refine PureRun.letPure fC entryRun ?_
      exact PureRun.ret (fC.bindLocal _ _) (RunsExpr.field' (j := 1) (RunsExpr.local' (local_bound fC 5 _)) rfl)

/-! ## `key_at_or` and `value_at_or` -/

theorem mapAtOr_spec {mid eid : TypeId} {R : Ty} {fi : MapFindIds} (inst : MapFindInstance P T ids mid fi)
    (kind : ElemKind P T size) {f : FunctionId} {field : Nat} {sel : Value × Value → Value}
    (pick : ∀ kv : Value × Value, [kv.1, kv.2][field]? = some (sel kv))
    (found : P.function? f = some (mapAtOrFn T mid f R field fi.ml fi.asl))
    {caller : State} (formed : caller.CellsWellFormed) {kvs : List (Value × Value)} {p cap : Nat}
    (rep : VecRep P T size ids.vec caller.heap
      (.structure ids.vec [.pointer p, .signed .i32 (kvs.map (entryOf eid)).length, .signed .i32 cap])
      (kvs.map (entryOf eid)))
    (disjoint : HeapBlocksDisjoint caller.heap) (ordinal : Int) (fallback : Value) :
    ∃ after, RunsExpr P caller (.call f
        ([Value.structure mid [.structure ids.vec [.pointer p, .signed .i32 (kvs.map (entryOf eid)).length,
          .signed .i32 cap]], .signed .i32 ordinal, fallback].map Expr.value))
      (if 0 ≤ ordinal then ((kvs[ordinal.toNat]?).map sel).getD fallback else fallback) after ∧
      PureFrame caller after := by
  let vv := Value.structure ids.vec [.pointer p, .signed .i32 (kvs.map (entryOf eid)).length, .signed .i32 cap]
  refine PureRun.call found rfl rfl formed ?_
  obtain ⟨fE, items, l0, l1, l2⟩ := map_entry3 (P := P) formed (mid := mid) vv (.signed .i32 ordinal) fallback
  have lenEq : (kvs.map (entryOf eid)).length = kvs.length := List.length_map _
  by_cases neg : ordinal < 0
  · rw [if_neg (by omega)]
    obtain ⟨_, cond, cf⟩ := RunsExpr.logicalOrTruePure (rightExpr := .binary .greaterEqual (.local 1)
        (.call fi.ml [.local 0]))
      ⟨_, RunsExpr.binary (operation := .less) (RunsExpr.local' l1) (RunsExpr.value' (.signed .i32 0)) (by decide)
        (by rw [eval_i32_lt]; simp [neg]), PureFrame.refl fE⟩
    exact PureRun.guardTakenAfter cond cf (PureRun.ret cf.afterFormed (RunsExpr.local' (cf.localFound l2))) nofun
  obtain ⟨n, rfl⟩ := Int.eq_ofNat_of_zero_le (Int.not_lt.mp neg)
  rw [if_pos (Int.natCast_nonneg n), Int.toNat_natCast]
  have left : RunsExpr P _ (.binary .less (.local 1) (int 0)) (.boolean false) _ :=
    RunsExpr.binary (operation := .less) (RunsExpr.local' l1) (RunsExpr.value' (.signed .i32 0)) (by decide)
      (by rw [eval_i32_lt]; simp)
  obtain ⟨S', lenRun, frame⟩ := setLen_spec inst.vec inst.ml fE rep
  have right := RunsExpr.binary (operation := .greaterEqual) (RunsExpr.local' l1)
    (callArgs (RunsExprs.one (RunsExpr.local' l0)) lenRun) (by decide) (eval_i32_ge _ _ _)
  by_cases big : kvs.length ≤ n
  · rw [List.getElem?_eq_none big]
    rw [show decide ((n : Int) ≥ ((kvs.map (entryOf eid)).length : Int)) = true by simp; omega] at right
    obtain ⟨_, cond, cf⟩ := RunsExpr.logicalOrFalsePure left ⟨S', right, frame⟩
    exact PureRun.guardTakenAfter cond cf (PureRun.ret cf.afterFormed (RunsExpr.local' (cf.localFound l2))) nofun
  · have inside : n < kvs.length := by omega
    have inside' : n < (kvs.map (entryOf eid)).length := by omega
    rw [show decide ((n : Int) ≥ ((kvs.map (entryOf eid)).length : Int)) = false by simp; omega] at right
    obtain ⟨S1, cond, cf⟩ := RunsExpr.logicalOrFalsePure left ⟨S', right, frame⟩
    rw [List.getElem?_eq_getElem inside]
    refine PureRun.guardSkipAfter cond cf ?_
    have fS1 := cf.afterFormed
    have h1 : S1.heap = caller.heap := cf.heap
    obtain ⟨S2, slRun, frame2⟩ := asSlice_spec inst.vec kind inst.asl inst.pf fS1 (by rw [h1]; exact rep)
      (by rw [h1]; exact disjoint)
    refine PureRun.letRun (callArgs (RunsExprs.one (RunsExpr.field' (j := 0) (RunsExpr.local' (cf.localFound l0))
      rfl)) slRun) frame2 ?_
    have fS2 := frame2.afterFormed
    let view := Value.rawSlice T (prefixAddr T size p cap (kvs.map (entryOf eid)).length)
      (kvs.map (entryOf eid)).length
    let C := S2.bindLocal 3 view
    have fC : C.CellsWellFormed := fS2.bindLocal _ _
    have c3 : C.local? 3 = some view := local_bound fS2 3 _
    have c1 : C.local? 1 = some (.signed .i32 (n : Int)) :=
      local_kept fS2 _ (by decide) (frame2.localFound (cf.localFound l1))
    have read := entry_read rep inside' C (frame2.heap.trans h1)
    rw [entry_getElem eid inside'] at read
    refine PureRun.letPure fC (RunsExpr.rawIndex c3 c1 read) ?_
    exact PureRun.ret (fC.bindLocal _ _)
      (RunsExpr.field' (j := field) (RunsExpr.local' (local_bound fC 4 _)) (pick kvs[n]))

/-! ## `try_insert` -/

/-- `try_insert(m, key, item)` with `key` already present returns `m`. -/
theorem mapTryInsert_present_spec {mid eid : TypeId} {K V : Ty} {fi : MapFindIds}
    (inst : MapFindInstance P T ids mid fi) (kind : ElemKind P T size) {fnd f : FunctionId}
    (fndFound : P.function? fnd = some (mapFindFn K T mid fnd fi.asl fi.ml fi.eq))
    (found : P.function? f = some (mapTryInsertFn K V T mid eid f g fnd))
    {eqv : Value → Value → Bool} {vals : List Value} (eqSpec : EqSpec P fi.eq eqv vals)
    {caller : State} (formed : caller.CellsWellFormed) {kvs : List (Value × Value)} {p cap : Nat} {key : Value}
    (rep : VecRep P T size ids.vec caller.heap
      (.structure ids.vec [.pointer p, .signed .i32 (kvs.map (entryOf eid)).length, .signed .i32 cap])
      (kvs.map (entryOf eid)))
    (keyIn : key ∈ vals) (sub : ∀ e ∈ kvs, e.1 ∈ vals) (disjoint : HeapBlocksDisjoint caller.heap)
    (present : kvs.any (fun e => eqv e.1 key) = true) (item : Value) :
    ∃ after, RunsExpr P caller (.call f
        ([Value.structure mid [.structure ids.vec [.pointer p, .signed .i32 (kvs.map (entryOf eid)).length,
          .signed .i32 cap]], key, item].map Expr.value))
      (.structure mid [.structure ids.vec [.pointer p, .signed .i32 (kvs.map (entryOf eid)).length,
          .signed .i32 cap]]) after ∧ PureFrame caller after := by
  refine PureRun.call found rfl rfl formed ?_
  obtain ⟨fE, _, l0, l1, _⟩ := map_entry3 (P := P) formed (mid := mid)
    (.structure ids.vec [.pointer p, .signed .i32 (kvs.map (entryOf eid)).length, .signed .i32 cap]) key item
  obtain ⟨S', run, frame⟩ := mapFind_spec inst kind fndFound eqSpec fE rep keyIn sub disjoint
  obtain ⟨S1, cmp, cf⟩ := RunsExpr.binaryPure (operation := .greaterEqual)
    ⟨S', callArgs (RunsExprs.two (RunsExpr.local' l0) (RunsExpr.local' l1)) run, frame⟩
    (fun m fm => ⟨m, RunsExpr.value' (.signed .i32 0), PureFrame.refl fm.afterFormed⟩) (by decide)
    (eval_i32_ge _ _ _)
  rw [findResult_nonneg, present] at cmp
  exact PureRun.guardTakenAfter cmp cf (PureRun.ret cf.afterFormed (RunsExpr.local' (cf.localFound l0))) nofun

/-- `try_insert(m, key, item)` with `key` absent: `try_push` of the entry;
the keys stay distinct. -/
theorem mapTryInsert_absent_spec {mid eid : TypeId} {K V : Ty} {fi : MapFindIds}
    (inst : MapFindInstance P T ids mid fi) (grow : GrowInstance P T ids g) (kind : ElemKind P T size)
    {fnd f : FunctionId}
    (fndFound : P.function? fnd = some (mapFindFn K T mid fnd fi.asl fi.ml fi.eq))
    (found : P.function? f = some (mapTryInsertFn K V T mid eid f g fnd))
    {eqv : Value → Value → Bool} {vals : List Value} (eqSpec : EqSpec P fi.eq eqv vals)
    {caller : State} (formed : caller.CellsWellFormed) {kvs : List (Value × Value)} {p cap : Nat}
    {key item : Value}
    (rep : VecRep P T size ids.vec caller.heap
      (.structure ids.vec [.pointer p, .signed .i32 (kvs.map (entryOf eid)).length, .signed .i32 cap])
      (kvs.map (entryOf eid)))
    (keyIn : key ∈ vals) (sub : ∀ e ∈ kvs, e.1 ∈ vals) (disjoint : HeapBlocksDisjoint caller.heap)
    (absent : kvs.any (fun e => eqv e.1 key) = false) (distinct : Distinct eqv (kvs.map Prod.fst))
    (fits : size * ((kvs.map (entryOf eid)).length + 1) ≤ 2147483647)
    (growth : (kvs.map (entryOf eid)).length = cap →
      (∃ budget, consumeBudget caller.heap.remaining (size * pushTarget size cap) = some budget) ∧
        caller.heap.allocationAddress 8 + size * pushTarget size cap < 2 ^ 64)
    (store : ElemStore P T size (entryOf eid (key, item)))
    (stores : ∀ y ∈ kvs.map (entryOf eid), ElemStore P T size y)
    (below : HeapBlocksBelowNext caller.heap) (unique : HeapBlockBasesUnique caller.heap)
    (noViews : caller.i32ArrayViews = []) :
    ∃ (after : State) (q m : Nat), RunsExpr P caller (.call f
        ([Value.structure mid [.structure ids.vec [.pointer p, .signed .i32 (kvs.map (entryOf eid)).length,
          .signed .i32 cap]], key, item].map Expr.value))
      (.structure mid [.structure ids.vec [.pointer q, .signed .i32 ((kvs ++ [(key, item)]).map (entryOf eid)).length,
        .signed .i32 m]]) after ∧
      FreshCellFrame caller after ∧ after.world = caller.world ∧
      after.i32ArrayViews = caller.i32ArrayViews ∧
      Pushed P T size ids.vec caller.heap p cap q m ((kvs ++ [(key, item)]).map (entryOf eid)) after.heap ∧
      Distinct eqv ((kvs ++ [(key, item)]).map Prod.fst) := by
  let xs := kvs.map (entryOf eid)
  let vv := Value.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]
  have appended : (kvs ++ [(key, item)]).map (entryOf eid) = xs ++ [entryOf eid (key, item)] := List.map_append
  rw [appended, List.map_append]
  obtain ⟨fE, _, l0, l1, l2⟩ := map_entry3 (P := P) formed (mid := mid) vv key item
  obtain ⟨S', run, frame⟩ := mapFind_spec inst kind fndFound eqSpec fE rep keyIn sub disjoint
  obtain ⟨S1, cmp, cf⟩ := RunsExpr.binaryPure (operation := .greaterEqual)
    ⟨S', callArgs (RunsExprs.two (RunsExpr.local' l0) (RunsExpr.local' l1)) run, frame⟩
    (fun m fm => ⟨m, RunsExpr.value' (.signed .i32 0), PureFrame.refl fm.afterFormed⟩) (by decide)
    (eval_i32_ge _ _ _)
  rw [findResult_nonneg, absent] at cmp
  have fS := cf.afterFormed
  have hS : S1.heap = caller.heap := cf.heap
  have entryRun : RunsExpr P S1 (.structValue eid [.local 1, .local 2]) (entryOf eid (key, item)) S1 :=
    RunsExpr.structValue (RunsExprs.two (RunsExpr.local' (cf.localFound l1)) (RunsExpr.local' (cf.localFound l2)))
  let B := S1.bindLocal 3 (entryOf eid (key, item))
  have fB : B.CellsWellFormed := fS.bindLocal _ _
  have hB : B.heap = caller.heap := hS
  have b0 : B.local? 0 = some (.structure mid [vv]) := local_kept fS _ (by decide) (cf.localFound l0)
  have b3 : B.local? 3 = some (entryOf eid (key, item)) := local_bound fS 3 _
  have items' : RunsExpr P B setItems vv B := RunsExpr.field' (j := 0) (RunsExpr.local' b0) rfl
  obtain ⟨after, q, m, pushRun, cells, world, views, pushed⟩ := tryPush_spec grow kind (caller := B) fB
    (by rw [hB]; exact rep) fits (by rw [hB]; exact growth) store stores (by rw [hB]; exact below)
    (by rw [hB]; exact unique) ((cf.views.trans rfl).trans noViews)
  rw [hB] at pushed
  obtain ⟨final, call, cellsF, worldF, viewsF, pushedF⟩ := Grow.call (vs := [.structure mid [vv], key, item])
    (bindings := [(0, .structure mid [vv]), (1, key), (2, item)])
    (Q := fun H => Pushed P T size ids.vec caller.heap p cap q m (xs ++ [entryOf eid (key, item)]) H) found rfl rfl
    (Grow.guardSkip cmp (Ext.ofPure cf)
      (Grow.letRun entryRun (Ext.refl fS)
        (Grow.retWrap fB (RunsExprs.two items' (RunsExpr.local' b3))
          ⟨after, pushRun, cells, world, views, pushed⟩)))
  refine ⟨final, q, m, call, cellsF, worldF, viewsF, pushedF, distinct.append_absent ?_⟩
  rw [List.any_map]; exact absent

/-! ## `try_remove` -/

/-- `try_remove(m, key)` with `key` absent returns `m`. -/
theorem mapTryRemove_absent_spec {mid eid : TypeId} {K : Ty} {fi : MapFindIds}
    (inst : MapFindInstance P T ids mid fi) (kind : ElemKind P T size) {fnd vr f : FunctionId}
    (fndFound : P.function? fnd = some (mapFindFn K T mid fnd fi.asl fi.ml fi.eq))
    (found : P.function? f = some (mapTryRemoveFn K mid f fnd vr))
    {eqv : Value → Value → Bool} {vals : List Value} (eqSpec : EqSpec P fi.eq eqv vals)
    {caller : State} (formed : caller.CellsWellFormed) {kvs : List (Value × Value)} {p cap : Nat} {key : Value}
    (rep : VecRep P T size ids.vec caller.heap
      (.structure ids.vec [.pointer p, .signed .i32 (kvs.map (entryOf eid)).length, .signed .i32 cap])
      (kvs.map (entryOf eid)))
    (keyIn : key ∈ vals) (sub : ∀ e ∈ kvs, e.1 ∈ vals) (disjoint : HeapBlocksDisjoint caller.heap)
    (missing : kvs.findIdx? (fun e => eqv e.1 key) = none) :
    ∃ after, RunsExpr P caller (.call f
        ([Value.structure mid [.structure ids.vec [.pointer p, .signed .i32 (kvs.map (entryOf eid)).length,
          .signed .i32 cap]], key].map Expr.value))
      (.structure mid [.structure ids.vec [.pointer p, .signed .i32 (kvs.map (entryOf eid)).length,
          .signed .i32 cap]]) after ∧ PureFrame caller after := by
  refine PureRun.call found rfl rfl formed ?_
  obtain ⟨fE, _, l0, l1⟩ := set_entry2 (P := P) formed (sid := mid)
    (.structure ids.vec [.pointer p, .signed .i32 (kvs.map (entryOf eid)).length, .signed .i32 cap]) key
  obtain ⟨S', run, frame⟩ := mapFind_spec inst kind fndFound eqSpec fE rep keyIn sub disjoint
  rw [findResult_none missing] at run
  have fS := frame.afterFormed
  refine PureRun.letRun (callArgs (RunsExprs.two (RunsExpr.local' l0) (RunsExpr.local' l1)) run) frame ?_
  have b2 := local_bound fS 2 (.signed .i32 (-1))
  have b0 := local_kept fS (.signed .i32 (-1)) (show (2 : VarId) ≠ 0 by decide) (frame.localFound l0)
  exact PureRun.guardTaken (RunsExpr.binary (RunsExpr.local' b2) (RunsExpr.value' _) (by decide)
    (by rw [eval_i32_lt]; rfl)) (PureRun.ret (fS.bindLocal _ _) (RunsExpr.local' b0)) nofun

/-- `try_remove(m, key)` with `key` first matching at `i`: the entry at `i`
is removed; the keys stay distinct. -/
theorem mapTryRemove_found_spec {mid eid : TypeId} {K : Ty} {fi : MapFindIds}
    (inst : MapFindInstance P T ids mid fi) (kind : ElemKind P T size) {fnd vr f : FunctionId}
    (fndFound : P.function? fnd = some (mapFindFn K T mid fnd fi.asl fi.ml fi.eq))
    (found : P.function? f = some (mapTryRemoveFn K mid f fnd vr))
    (vrFound : P.function? vr = some (tryRemoveFn (T := T) ids vr))
    {eqv : Value → Value → Bool} {vals : List Value} (eqSpec : EqSpec P fi.eq eqv vals)
    {caller : State} (formed : caller.CellsWellFormed) {kvs : List (Value × Value)} {p cap : Nat} {key : Value}
    (rep : VecRep P T size ids.vec caller.heap
      (.structure ids.vec [.pointer p, .signed .i32 (kvs.map (entryOf eid)).length, .signed .i32 cap])
      (kvs.map (entryOf eid)))
    (keyIn : key ∈ vals) (sub : ∀ e ∈ kvs, e.1 ∈ vals) (disjoint : HeapBlocksDisjoint caller.heap)
    {i : Nat} (at_ : kvs.findIdx? (fun e => eqv e.1 key) = some i) (distinct : Distinct eqv (kvs.map Prod.fst))
    (stores : ∀ y ∈ kvs.map (entryOf eid), ElemStore P T size y)
    (noViews : caller.i32ArrayViews = []) (unique : HeapBlockBasesUnique caller.heap) :
    ∃ after, RunsExpr P caller (.call f
        ([Value.structure mid [.structure ids.vec [.pointer p, .signed .i32 (kvs.map (entryOf eid)).length,
          .signed .i32 cap]], key].map Expr.value))
      (.structure mid [.structure ids.vec [.pointer p, .signed .i32 ((kvs.eraseIdx i).map (entryOf eid)).length,
        .signed .i32 cap]]) after ∧
      FreshCellFrame caller after ∧ after.world = caller.world ∧ after.i32ArrayViews = caller.i32ArrayViews ∧
      VecRep P T size ids.vec after.heap
        (.structure ids.vec [.pointer p, .signed .i32 ((kvs.eraseIdx i).map (entryOf eid)).length, .signed .i32 cap])
        ((kvs.eraseIdx i).map (entryOf eid)) ∧
      HeapRegionWrite caller.heap after.heap p (size * cap) ∧ Distinct eqv ((kvs.eraseIdx i).map Prod.fst) := by
  let xs := kvs.map (entryOf eid)
  let vv := Value.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]
  have inside : i < kvs.length := (List.findIdx?_eq_some_iff_findIdx_eq.mp at_).1
  have inside' : i < xs.length := by show i < (kvs.map (entryOf eid)).length; rw [List.length_map]; exact inside
  rw [map_eraseIdx']
  obtain ⟨fE, _, l0, l1⟩ := set_entry2 (P := P) formed (sid := mid) vv key
  obtain ⟨S', run, frame⟩ := mapFind_spec inst kind fndFound eqSpec fE rep keyIn sub disjoint
  rw [findResult_some at_] at run
  have fS := frame.afterFormed
  have hS : S'.heap = caller.heap := frame.heap
  let B := S'.bindLocal 2 (.signed .i32 (i : Int))
  have fB : B.CellsWellFormed := fS.bindLocal _ _
  have b2 : B.local? 2 = some (.signed .i32 (i : Int)) := local_bound fS 2 _
  have b0 : B.local? 0 = some (.structure mid [vv]) := local_kept fS _ (by decide) (frame.localFound l0)
  have cond : RunsExpr P B (.binary .less (.local 2) (int 0)) (.boolean false) B :=
    RunsExpr.binary (RunsExpr.local' b2) (RunsExpr.value' _) (by decide) (by rw [eval_i32_lt]; simp)
  obtain ⟨after, rmRun, cells, world, views, rep', write⟩ := tryRemove_spec inst.vec kind vrFound (caller := B) fB
    (by rw [show B.heap = caller.heap from hS]; exact rep) inside' stores (frame.views.trans noViews)
    (by rw [show B.heap = caller.heap from hS]; exact unique)
  rw [show B.heap = caller.heap from hS] at write
  obtain ⟨final, call, cellsF, worldF, viewsF, repF, writeF⟩ := Grow.call (vs := [.structure mid [vv], key])
    (bindings := [(0, .structure mid [vv]), (1, key)])
    (Q := fun H => VecRep P T size ids.vec H
        (.structure ids.vec [.pointer p, .signed .i32 (xs.eraseIdx i).length, .signed .i32 cap]) (xs.eraseIdx i) ∧
      HeapRegionWrite caller.heap H p (size * cap)) found rfl rfl
    (Grow.letRun (callArgs (RunsExprs.two (RunsExpr.local' l0) (RunsExpr.local' l1)) run) (Ext.ofPure frame)
      (Grow.guardSkip cond (Ext.refl fB)
        (Grow.retWrap fB (RunsExprs.two (RunsExpr.field' (j := 0) (RunsExpr.local' b0) rfl) (RunsExpr.local' b2))
          ⟨after, rmRun, cells, world, views, rep', write⟩)))
  exact ⟨final, call, cellsF, worldF, viewsF, repF, writeF,
    distinct.sublist ((List.eraseIdx_sublist kvs i).map _)⟩

#print axioms findResult_nonneg
#print axioms mapContainsKey_spec
#print axioms mapGetOr_spec
#print axioms mapAtOr_spec
#print axioms mapTryInsert_present_spec
#print axioms mapTryInsert_absent_spec
#print axioms mapTryRemove_absent_spec
#print axioms mapTryRemove_found_spec

end Lanius.Std
