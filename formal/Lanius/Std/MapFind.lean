import Lanius.Std.SetScan

/-! # `std::map`: lookups

`struct Map<K, V> { entries: Vec<Entry<K, V>> }` is `.structure mid [v]`
with `v` a vector of entries `.structure eid [key, value]` (element type
`T = .structure eid`). A map represents a list of key-value pairs `kvs`
whose keys are `Distinct`. `find` walks the entries through `as_slice` and
calls `K::eq` on each key; the lookups are built on it. The loop-free
functions `new`, `len`, `capacity`, `is_empty`, `try_reserve`, `clear`,
`try_shrink_to_fit`, `try_clone` and `destroy` have the same Core bodies as
the set ones (`setNewFn`, `setForwardFn`, `setRewrapFn`, ... at the map's
struct id), so their specs are those of `SetSpec`. -/

namespace Lanius.Std

open Lanius Lanius.Core Lanius.Semantics Lanius.Memory

variable {P : Program} {T : Ty} {ids : VecIds} {size : Nat}

def entryOf (eid : TypeId) (kv : Value × Value) : Value := .structure eid [kv.1, kv.2]

/-- What `find` returns: the ordinal of the first key equal to `key`, or -1. -/
def findResult (eqv : Value → Value → Bool) (key : Value) (kvs : List (Value × Value)) : Int :=
  ((kvs.findIdx? (fun e => eqv e.1 key)).map Int.ofNat).getD (-1)

/-! ## Templates -/

section templates
variable (K T : Ty) (mid eid : TypeId) (f : FunctionId)

/-- `fn find<K, V>(value: Map<K, V>, key: K) -> i32`, with locals 0 `value`,
1 `key`, 2 `entries`, 3 `index`, 4 `entry`. -/
def mapFindFn (asl ml eq : FunctionId) : Function where
  id := f
  parameters := [(0, setTy mid), (1, K)]
  returnType := i32Ty
  body := some <|
    .letLocal 2 (.slice T) (.call asl [setItems])
    (.letLocal 3 i32Ty (int 0)
    (.sequence
      (.whileLoop (.binary .less (.local 3) (.call ml [.local 0]))
        (.letLocal 4 T (.index (.local 2) (.local 3))
          (.sequence (.ifThenElse (.call eq [.field (.local 4) 0, .local 1]) (.returnValue (some (.local 3))) .skip)
            (increment 3))))
      (.returnValue (some (.unary .negate (int 1))))))

def mapContainsKeyFn (fnd : FunctionId) : Function where
  id := f
  parameters := [(0, setTy mid), (1, K)]
  returnType := boolTy
  body := some (.returnValue (some (.binary .greaterEqual (.call fnd [.local 0, .local 1]) (int 0))))

/-- `get_or(value, key, fallback)`, with locals 3 `index`, 4 `entries`, 5 `entry`. -/
def mapGetOrFn (V : Ty) (fnd asl : FunctionId) : Function where
  id := f
  parameters := [(0, setTy mid), (1, K), (2, V)]
  returnType := V
  body := some <|
    .letLocal 3 i32Ty (.call fnd [.local 0, .local 1])
    (guardReturn (.binary .less (.local 3) (int 0)) (.local 2)
    (.letLocal 4 (.slice T) (.call asl [setItems])
    (.letLocal 5 T (.index (.local 4) (.local 3))
      (.returnValue (some (.field (.local 5) 1))))))

/-- `key_at_or` (`field = 0`) and `value_at_or` (`field = 1`), with locals
3 `entries`, 4 `entry`. -/
def mapAtOrFn (R : Ty) (field : Nat) (ml asl : FunctionId) : Function where
  id := f
  parameters := [(0, setTy mid), (1, i32Ty), (2, R)]
  returnType := R
  body := some <|
    guardReturn (.binary .logicalOr (.binary .less (.local 1) (int 0))
        (.binary .greaterEqual (.local 1) (.call ml [.local 0]))) (.local 2)
    (.letLocal 3 (.slice T) (.call asl [setItems])
    (.letLocal 4 T (.index (.local 3) (.local 1))
      (.returnValue (some (.field (.local 4) field)))))

end templates

/-! ## `find` -/

/-- The calls `find` makes, at element type `T`. -/
structure MapFindIds where
  asl : FunctionId
  pf : FunctionId
  ml : FunctionId
  eq : FunctionId

structure MapFindInstance (P : Program) (T : Ty) (ids : VecIds) (mid : TypeId) (fi : MapFindIds) : Prop where
  vec : VecInstance P T ids
  asl : P.function? fi.asl = some (asSliceFn ids T fi.asl fi.pf)
  pf : P.function? fi.pf = some (prefixFromStorageFn T fi.pf ids.fromStorage)
  ml : P.function? fi.ml = some (setForwardFn mid fi.ml ids.len i32Ty)

/-- Reading entry `k` through the `as_slice` view. -/
theorem entry_read {P : Program} {T : Ty} {size : Nat} {vec : TypeId} {h : Heap} {p cap : Nat}
    {xs : List Value} (rep : VecRep P T size vec h (.structure vec [.pointer p, .signed .i32 xs.length,
      .signed .i32 cap]) xs) {k : Nat} (inside : k < xs.length) (s : State) (heap : s.heap = h) :
    readRawSliceIndex P s T (prefixAddr T size p cap xs.length) xs.length k = .ok xs[k] := by
  obtain ⟨_, lenLe, _, _, reads⟩ := rep.fields
  have addr : prefixAddr T size p cap xs.length = viewAddr T size p cap := if_neg (by omega)
  rw [addr, readRawSliceIndex_shorter inside lenLe]
  exact reads k inside s (by rw [heap]; exact ReadsWithin.refl _ _ _)

theorem mapFind_spec {mid eid : TypeId} {K : Ty} {fi : MapFindIds} (inst : MapFindInstance P T ids mid fi)
    (kind : ElemKind P T size) {f : FunctionId} (found : P.function? f = some (mapFindFn K T mid f fi.asl fi.ml fi.eq))
    {eqv : Value → Value → Bool} {vals : List Value} (eqSpec : EqSpec P fi.eq eqv vals)
    {caller : State} (formed : caller.CellsWellFormed) {kvs : List (Value × Value)} {p cap : Nat} {key : Value}
    (rep : VecRep P T size ids.vec caller.heap
      (.structure ids.vec [.pointer p, .signed .i32 (kvs.map (entryOf eid)).length, .signed .i32 cap])
      (kvs.map (entryOf eid)))
    (keyIn : key ∈ vals) (sub : ∀ e ∈ kvs, e.1 ∈ vals) (disjoint : HeapBlocksDisjoint caller.heap) :
    ∃ after, RunsExpr P caller (.call f
        ([Value.structure mid [.structure ids.vec [.pointer p, .signed .i32 (kvs.map (entryOf eid)).length,
          .signed .i32 cap]], key].map Expr.value))
      (.signed .i32 (findResult eqv key kvs)) after ∧ PureFrame caller after := by
  let xs := kvs.map (entryOf eid)
  obtain ⟨_, lenLe, capBound, _, _⟩ := rep.fields
  refine PureRun.call found rfl rfl formed ?_
  let vv := Value.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]
  let E0 : State := { caller with locals := [] }
  have f0 : E0.CellsWellFormed := formed
  have f1 := f0.bindLocal 0 (.structure mid [vv])
  let E := (E0.bindLocal 0 (.structure mid [vv])).bindLocal 1 key
  change PureRun P E _ _
  have fE : E.CellsWellFormed := f1.bindLocal _ _
  have l1 : E.local? 1 = some key := local_bound f1 1 _
  have l0 : E.local? 0 = some (.structure mid [vv]) := local_kept f1 _ (by decide) (local_bound f0 0 _)
  obtain ⟨S', slRun, frame⟩ := asSlice_spec inst.vec kind inst.asl inst.pf fE rep disjoint
  refine PureRun.letRun (callArgs (RunsExprs.one (RunsExpr.field' (j := 0) (RunsExpr.local' l0) rfl)) slRun)
    frame ?_
  have fS : S'.CellsWellFormed := frame.afterFormed
  let view := Value.rawSlice T (prefixAddr T size p cap xs.length) xs.length
  let B := S'.bindLocal 2 view
  have fB : B.CellsWellFormed := fS.bindLocal _ _
  have b2 : B.local? 2 = some view := local_bound fS 2 _
  have b1 : B.local? 1 = some key := local_kept fS _ (by decide) (frame.localFound l1)
  have b0 : B.local? 0 = some (.structure mid [vv]) := local_kept fS _ (by decide) (frame.localFound l0)
  have hB : B.heap = caller.heap := frame.heap
  change PureRun P B (.letLocal 3 i32Ty (.value (.signed .i32 0)) _) _
  refine PureRun.letValue fB ?_
  let n := xs.length
  let Frame : State → Prop := fun s => FreshCellFrame B s ∧
    s.locals = (B.bindLocal 3 (.signed .i32 0)).locals ∧ s.heap = B.heap ∧ s.world = B.world ∧
    s.i32ArrayViews = B.i32ArrayViews ∧ s.CellsWellFormed
  let Before : Nat → Prop := fun k => ∀ i (inside : i < kvs.length), i < k → eqv kvs[i].1 key = false
  have frameLocals : ∀ s, Frame s → s.local? 0 = some (.structure mid [vv]) ∧ s.local? 1 = some key ∧
      s.local? 2 = some view :=
    fun s fr => ⟨local_above fr.1 fr.2.1 (by decide) b0, local_above fr.1 fr.2.1 (by decide) b1,
      local_above fr.1 fr.2.1 (by decide) b2⟩
  have framePure : ∀ s s', Frame s → PureFrame s s' → Frame s' := fun s s' fr pure =>
    ⟨fr.1.trans pure.cells, pure.locals.trans fr.2.1, pure.heap.trans fr.2.2.1, pure.world.trans fr.2.2.2.1,
      pure.views.trans fr.2.2.2.2.1, pure.afterFormed⟩
  have cellAt : ∀ s, Frame s → s.cellId? 3 = some B.nextCell := fun s fr => by
    simp [State.cellId?, fr.2.1, State.bindLocal, State.bindCell]
  have condAt : ∀ s (k : Nat), Frame s → s.local? 3 = some (.signed .i32 k) → ∃ s',
      RunsExpr P s (.binary .less (.local 3) (.call fi.ml [.local 0])) (.boolean (decide ((k : Int) < n))) s' ∧
        PureFrame s s' := fun s k fr idx => by
    obtain ⟨s', lenRun, pure⟩ := setLen_spec inst.vec inst.ml fr.2.2.2.2.2
      (by rw [fr.2.2.1, hB]; exact rep)
    exact ⟨s', RunsExpr.binary (RunsExpr.local' idx)
      (callArgs (RunsExprs.one (RunsExpr.local' (frameLocals s fr).1)) lenRun) (by decide) (eval_i32_lt _ _ _), pure⟩
  have lenEq : n = kvs.length := List.length_map _
  have nBound : kvs.length < 2 ^ 31 := by
    have l : (kvs.map (entryOf eid)).length = kvs.length := List.length_map _
    rw [l] at lenLe; omega
  let body : Stmt := .letLocal 4 T (.index (.local 2) (.local 3))
    (.sequence (.ifThenElse (.call fi.eq [.field (.local 4) 0, .local 1]) (.returnValue (some (.local 3))) .skip)
      (increment 3))
  let measure : State → Nat := fun s => n - counter 3 s
  let oracle : TotalWhileOracle measure P (.binary .less (.local 3) (.call fi.ml [.local 0])) body := {
    Inv := fun s => ∃ k, k ≤ n ∧ Frame s ∧ s.local? 3 = some (.signed .i32 k) ∧ Before k
    Done := fun c s => Frame s ∧ ((c = .next ∧ Before n) ∨
      (∃ k, ∃ inside : k < kvs.length, c = .returned (some (.signed .i32 k)) ∧ eqv kvs[k].1 key = true ∧ Before k))
    step := by
      intro s invariant
      obtain ⟨k, kle, fr, idx, before⟩ := invariant
      obtain ⟨c1, cond, pure1⟩ := condAt s k fr idx
      have fr1 := framePure s c1 fr pure1
      have idx1 := pure1.localFound idx
      by_cases last : k = n
      · subst last
        rw [show decide (((xs.length : Nat) : Int) < xs.length) = false by simp] at cond
        obtain ⟨threshold, stable, _⟩ := cond
        exact Or.inl ⟨threshold, c1, stable, fr1, Or.inl ⟨rfl, before⟩⟩
      have kn : k < n := by omega
      have kk : k < kvs.length := by omega
      rw [show decide ((k : Int) < n) = true by simp; omega] at cond
      obtain ⟨condThreshold, condStable, _⟩ := cond
      right
      obtain ⟨_, c1_1, c1_2⟩ := frameLocals c1 fr1
      have fc1 := fr1.2.2.2.2.2
      -- let entry = entries[index]
      have read := entry_read rep kn c1 (fr1.2.2.1.trans hB)
      have entryEq : xs[k] = .structure eid [kvs[k].1, kvs[k].2] := by
        show (kvs.map (entryOf eid))[k] = _
        rw [List.getElem_map]; rfl
      rw [entryEq] at read
      have entryRun := RunsExpr.rawIndex c1_2 idx1 read
      let b := c1.bindLocal 4 (.structure eid [kvs[k].1, kvs[k].2])
      have fb : b.CellsWellFormed := fc1.bindLocal _ _
      have b4 : b.local? 4 = some (.structure eid [kvs[k].1, kvs[k].2]) := local_bound fc1 4 _
      have b1' : b.local? 1 = some key := local_kept fc1 _ (by decide) c1_1
      have b3 : b.local? 3 = some (.signed .i32 k) := local_kept fc1 _ (by decide) idx1
      obtain ⟨a1, eqRun, pa1⟩ := eqSpec b fb kvs[k].1 (sub _ (List.getElem_mem _)) key keyIn
      have test := callArgs (RunsExprs.two (RunsExpr.field' (j := 0) (RunsExpr.local' b4) rfl)
        (RunsExpr.local' b1')) eqRun
      have frameB : FreshCellFrame B b := fr1.1.trans (FreshCellFrame.bindLocal c1 4 _)
      have frameA1 : FreshCellFrame B a1 := frameB.trans pa1.cells
      have restoreFrame : ∀ R : State, FreshCellFrame B R → R.heap = B.heap → R.world = B.world →
          R.i32ArrayViews = B.i32ArrayViews → Frame (restoreLocals c1 R) := fun R fR hR wR vR => by
        have frame' : FreshCellFrame B (restoreLocals c1 R) := by
          obtain ⟨e, cl, nx, fx⟩ := fR; exact ⟨e, cl, nx, fx⟩
        exact ⟨frame', fr1.2.1, hR, wR, vR, FreshCellFrame.after_cellsWellFormed fB frame'⟩
      have hA1 : a1.heap = B.heap := pa1.heap.trans fr1.2.2.1
      have wA1 : a1.world = B.world := pa1.world.trans fr1.2.2.2.1
      have vA1 : a1.i32ArrayViews = B.i32ArrayViews := pa1.views.trans fr1.2.2.2.2.1
      have a1_3 := pa1.localFound b3
      cases equal : eqv kvs[k].1 key with
      | true =>
          rw [equal] at test
          obtain ⟨bodyThreshold, bodyStable, _⟩ : RunsStmt P c1 body (.returned (some (.signed .i32 k)))
              (restoreLocals c1 a1) :=
            RunsStmt.letLocal entryRun (RunsStmt.sequenceCompleted (RunsStmt.ifThenElseTrue test
              (RunsStmt.returnValue (RunsExpr.local' a1_3))) (by intro h; cases h) (increment 3))
          refine ⟨condThreshold, bodyThreshold, c1, _, restoreLocals c1 a1, condStable, bodyStable,
            fun _ => ⟨restoreFrame a1 frameA1 hA1 wA1 vA1, Or.inr ⟨k, kk, rfl, equal, before⟩⟩, fun h => ?_⟩
          rcases h with h | h <;> cases h
      | false =>
          rw [equal] at test
          have cell1 : a1.cellId? 3 = some B.nextCell := by
            have l : a1.cellId? 3 = b.cellId? 3 := by unfold State.cellId?; rw [pa1.locals]
            rw [l, cellId_bindLocal_ne c1 _ (by decide)]; exact cellAt c1 fr1
          obtain ⟨a2, assigned⟩ := assignLocal_exists a1 3 _ (.signed .i32 (Int.ofNat (k + 1))) _ cell1 a1_3
          have cellA := assignLocal_assignCell 3 _ _ cell1 assigned
          obtain ⟨cells2, _, locals2, heap2, world2, views2⟩ :=
            FreshCellFrame.assignCounter fB pa1.afterFormed frameA1 cellA
          obtain ⟨bodyThreshold, bodyStable, _⟩ : RunsStmt P c1 body .next (restoreLocals c1 a2) :=
            RunsStmt.letLocal entryRun (RunsStmt.sequenceNext (RunsStmt.ifThenElseFalse test (RunsStmt.skip P a1))
              (increment_run inst.vec.target (by omega : k + 1 < 2 ^ 31) cell1 a1_3 assigned))
          have idx2 : (restoreLocals c1 a2).local? 3 = some (.signed .i32 (Int.ofNat (k + 1))) := by
            refine (local?_congr (s := restoreLocals c1 a2) (t := a2) rfl ?_).trans
              (assignLocal_finds_assigned 3 _ _ cell1 assigned)
            show c1.cellId? 3 = a2.cellId? 3
            have l : a2.cellId? 3 = a1.cellId? 3 := by unfold State.cellId?; rw [locals2]
            rw [l, cell1]; exact cellAt c1 fr1
          refine ⟨condThreshold, bodyThreshold, c1, .next, restoreLocals c1 a2, condStable, bodyStable,
            fun h => absurd rfl h.1, fun _ => ⟨?_, k + 1, kn, restoreFrame a2 cells2 (heap2.trans hA1)
              (world2.trans wA1) (views2.trans vA1), idx2, ?_⟩⟩
          · show n - counter 3 (restoreLocals c1 a2) < n - counter 3 s
            rw [counter_eq idx2, counter_eq idx]; omega
          · intro i inside below
            by_cases same : i = k
            · subst same; exact equal
            · exact before i inside (by omega) }
  have entryFrame : Frame (B.bindLocal 3 (.signed .i32 0)) :=
    ⟨FreshCellFrame.bindLocal B 3 _, rfl, rfl, rfl, rfl, fB.bindLocal _ _⟩
  obtain ⟨threshold, completion, after, loopStable, done⟩ :=
    executeTotalWhile measure P _ _ oracle (B.bindLocal 3 (.signed .i32 0))
      ⟨0, Nat.zero_le _, entryFrame, local_bound fB 3 _, fun _ _ below => absurd below (Nat.not_lt_zero _)⟩
  obtain ⟨frA, result⟩ := done
  have loopRun : RunsStmt P (B.bindLocal 3 (.signed .i32 0)) _ completion after := ⟨threshold, loopStable, frA.2.1⟩
  refine ⟨after, ?_, frA.1, frA.2.2.1, frA.2.2.2.1, frA.2.2.2.2.1⟩
  rcases result with ⟨rfl, absent⟩ | ⟨k, kn, rfl, equal, before⟩
  · have missing : kvs.findIdx? (fun e => eqv e.1 key) = none := by
      rw [List.findIdx?_eq_none_iff]
      intro x member
      obtain ⟨i, inside, rfl⟩ := List.getElem_of_mem member
      exact absent i inside (by omega)
    have negOne : evalUnaryValue P.target .negate (.signed .i32 1) = .ok (.signed .i32 (-1)) := by
      rw [inst.vec.target]; rfl
    show RunsStmt P _ _ (.returned (some (.signed .i32 (((kvs.findIdx? (fun e => eqv e.1 key)).map Int.ofNat).getD (-1)))))
      after
    rw [missing]
    exact RunsStmt.sequenceNext loopRun (RunsStmt.returnValue (RunsExpr.unary (RunsExpr.value' _) negOne))
  · have first : kvs.findIdx? (fun e => eqv e.1 key) = some k := by
      rw [List.findIdx?_eq_some_iff_getElem]
      exact ⟨kn, equal, fun j below => by rw [before j (by omega) below]; decide⟩
    show RunsStmt P _ _ (.returned (some (.signed .i32 (((kvs.findIdx? (fun e => eqv e.1 key)).map Int.ofNat).getD (-1)))))
      after
    rw [first]
    exact RunsStmt.sequenceCompleted loopRun (by intro h; cases h) _

#print axioms mapFind_spec

end Lanius.Std
