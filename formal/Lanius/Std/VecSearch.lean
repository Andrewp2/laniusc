import Lanius.Std.VecLoop

/-! # `index_of`: a loop that returns early

`index_of` calls the element type's `Eq::eq` once per element until one is
equal, so the loop state also gains the call's fresh cells. Its invariant is
stated against the state before `let index`, with the counter's cell the
only one of the frame whose value changes. -/

namespace Lanius.Std

open Lanius Lanius.Core Lanius.Semantics Lanius.Memory

variable {P : Program} {T : Ty} {ids : VecIds} {size : Nat}

/-- `pub fn index_of<T>(value: Vec<T>, item: T) -> i32 where T: Eq<T>`:
`let items = slots(value); let index = 0; while (index < value.length)
{ if (T::eq(items[index], item)) { return index; } index += 1; } return -1;` -/
def indexOfFn (ids : VecIds) (T : Ty) (indexOf eq : FunctionId) : Function where
  id := indexOf
  parameters := [(0, vecTy ids), (1, T)]
  returnType := i32Ty
  body := some <|
    .letLocal 2 (.slice T) (.call ids.slots [.local 0])
    (.letLocal 3 i32Ty (int 0)
    (.sequence
      (.whileLoop (.binary .less (.local 3) (.field (.local 0) 1))
        (.sequence
          (.ifThenElse (.call eq [.index (.local 2) (.local 3), .local 1]) (.returnValue (some (.local 3))) .skip)
          (increment 3)))
      (.returnValue (some (.unary .negate (int 1))))))

/-! ## Frames with one rebound counter -/

private theorem replaceCell_append' (cs ds : List Cell) (id : CellId) (w : Value) :
    replaceCell (cs ++ ds) id w = replaceCell cs id w ++ replaceCell ds id w := by
  induction cs with
  | nil => rfl
  | cons c rest ih =>
      simp only [List.cons_append, replaceCell]
      split <;> rw [ih] <;> rfl

private theorem replaceCell_absent' (cs : List Cell) (id : CellId) (w : Value)
    (absent : ∀ cell ∈ cs, cell.id ≠ id) : replaceCell cs id w = cs := by
  induction cs with
  | nil => rfl
  | cons c rest ih =>
      have head : (c.id == id) = false := by simpa using absent c (by simp)
      simp only [replaceCell, head]
      rw [ih (fun cell member => absent cell (by simp [member]))]
      rfl

theorem replaceCell_ids (cs : List Cell) (id : CellId) (w : Value) :
    (replaceCell cs id w).map Cell.id = cs.map Cell.id := by
  induction cs with
  | nil => rfl
  | cons c rest ih =>
      simp only [replaceCell]
      split <;> simp [ih]

theorem mem_replaceCell {cs : List Cell} {id : CellId} {w : Value} {cell : Cell}
    (member : cell ∈ replaceCell cs id w) : ∃ old ∈ cs, old.id = cell.id := by
  have mapped : cell.id ∈ (replaceCell cs id w).map Cell.id := List.mem_map_of_mem member
  rw [replaceCell_ids] at mapped
  exact List.mem_map.mp mapped

/-- Assigning the counter, whose cell is `base.nextCell`, keeps the frame. -/
theorem FreshCellFrame.assignCounter {base s s' : State} (formedBase : base.CellsWellFormed)
    (formed : s.CellsWellFormed) (frame : FreshCellFrame base s) {w : Value}
    (assigned : s.assignCell base.nextCell w = some s') :
    FreshCellFrame base s' ∧ s'.CellsWellFormed ∧ s'.locals = s.locals ∧ s'.heap = s.heap ∧
      s'.world = s.world ∧ s'.i32ArrayViews = s.i32ArrayViews := by
  rw [assignCell_state assigned]
  obtain ⟨extra, cells, frontier, fresh⟩ := frame
  have absent : ∀ cell ∈ base.cells, cell.id ≠ base.nextCell := fun cell member =>
    Nat.ne_of_lt (formedBase cell member)
  refine ⟨⟨replaceCell extra base.nextCell w, ?_, frontier, ?_⟩, ?_, rfl, rfl, rfl, rfl⟩
  · show replaceCell s.cells base.nextCell w = _
    rw [cells, replaceCell_append', replaceCell_absent' _ _ _ absent]
  · intro cell member
    obtain ⟨old, oldMember, same⟩ := mem_replaceCell member
    rw [← same]; exact fresh old oldMember
  · intro cell member
    obtain ⟨old, oldMember, same⟩ := mem_replaceCell member
    show cell.id < s.nextCell
    rw [← same]; exact formed old oldMember

/-- A local of the base frame other than the counter keeps its value. -/
theorem local_above {base s : State} (frame : FreshCellFrame base s) {idx id : VarId} {c : CellId}
    (locals : s.locals = (idx, c) :: base.locals) (different : id ≠ idx) {v : Value}
    (found : base.local? id = some v) : s.local? id = some v := by
  have ne : (idx == id) = false := by simpa using Ne.symm different
  have cellIds : s.cellId? id = base.cellId? id := by
    simp only [State.cellId?, locals, List.find?_cons, ne]
  unfold State.local? at found ⊢
  rw [cellIds]
  cases h : base.cellId? id with
  | none => simp [h] at found
  | some cell =>
      simp only [h, Option.bind_some] at found ⊢
      unfold State.cell? at found ⊢
      cases e : base.cellEntry? cell with
      | none => simp [e] at found
      | some entry => rw [frame.cellEntryFound e]; simpa [e] using found

/-- `let x: i32 = v; body` where the body's frame is stated against the
state before the `let`. -/
theorem PureRun.letValue {S : State} {id : VarId} {ty : Ty} {v : Value} {body : Stmt} {k : Completion}
    (formed : S.CellsWellFormed)
    (tail : ∃ after, RunsStmt P (S.bindLocal id v) body k after ∧ FreshCellFrame S after ∧
      after.heap = S.heap ∧ after.world = S.world ∧ after.i32ArrayViews = S.i32ArrayViews) :
    PureRun P S (.letLocal id ty (.value v) body) k := by
  obtain ⟨after, run, cells, heap, world, views⟩ := tail
  exact ⟨restoreLocals S after, RunsStmt.letLocal (RunsExpr.value' v) run,
    ⟨formed, cells.restoreLocals, rfl, heap, world, views⟩⟩

/-! ## The spec -/

/-- `index_of(v, item)`: the index of the first element `eq` to `item`, or
-1, given `eq`'s contract on the elements. -/
theorem index_of_spec (inst : VecInstance P T ids) (kind : ElemKind P T size) {indexOf eq : FunctionId}
    (found : P.function? indexOf = some (indexOfFn ids T indexOf eq))
    {eqv : Value → Value → Bool} {item : Value} {xs : List Value}
    (eqSpec : ∀ S : State, S.CellsWellFormed → ∀ a ∈ xs, ∃ after,
      RunsExpr P S (.call eq ([a, item].map Expr.value)) (.boolean (eqv a item)) after ∧ PureFrame S after)
    {caller : State} (formed : caller.CellsWellFormed) {v : Value}
    (rep : VecRep P T size ids.vec caller.heap v xs) :
    ∃ after, RunsExpr P caller (.call indexOf ([v, item].map Expr.value))
      (.signed .i32 (((xs.findIdx? (eqv · item)).map Int.ofNat).getD (-1))) after ∧
      PureFrame caller after := by
  obtain ⟨p, cap, rfl, lenLe, capBound, buffer, reads⟩ := rep
  let vv := Value.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]
  refine PureRun.call found rfl rfl formed ?_
  let E0 : State := { caller with locals := [] }
  have f0 : E0.CellsWellFormed := formed
  have f1 := f0.bindLocal 0 vv
  let E := (E0.bindLocal 0 vv).bindLocal 1 item
  change PureRun P E _ _
  have fE : E.CellsWellFormed := f1.bindLocal _ _
  have l1 : E.local? 1 = some item := local_bound f1 1 _
  have l0 : E.local? 0 = some vv := local_kept f1 _ (by decide) (local_bound f0 0 _)
  obtain ⟨S', slots, frame⟩ := slots_call inst kind fE l0 capBound buffer
  refine PureRun.letRun slots frame ?_
  have fS : S'.CellsWellFormed := frame.afterFormed
  let view := Value.rawSlice T (viewAddr T size p cap) cap
  let B := S'.bindLocal 2 view
  have fB : B.CellsWellFormed := fS.bindLocal _ _
  have b2 : B.local? 2 = some view := local_bound fS 2 _
  have b1 : B.local? 1 = some item := local_kept fS _ (by decide) (frame.localFound l1)
  have b0 : B.local? 0 = some vv := local_kept fS _ (by decide) (frame.localFound l0)
  have hB : B.heap = caller.heap := frame.heap
  refine PureRun.letValue fB ?_
  -- the loop
  let n := xs.length
  let Frame : State → Prop := fun s => FreshCellFrame B s ∧
    s.locals = (B.bindLocal 3 (.signed .i32 0)).locals ∧ s.heap = B.heap ∧ s.world = B.world ∧
    s.i32ArrayViews = B.i32ArrayViews ∧ s.CellsWellFormed
  let Before : Nat → Prop := fun k => ∀ i (inside : i < n), i < k → eqv xs[i] item = false
  have frameLocals : ∀ s, Frame s → s.local? 0 = some vv ∧ s.local? 1 = some item ∧ s.local? 2 = some view :=
    fun s fr => ⟨local_above fr.1 fr.2.1 (by decide) b0, local_above fr.1 fr.2.1 (by decide) b1,
      local_above fr.1 fr.2.1 (by decide) b2⟩
  have framePure : ∀ s s', Frame s → PureFrame s s' → Frame s' := fun s s' fr pure =>
    ⟨fr.1.trans pure.cells, pure.locals.trans fr.2.1, pure.heap.trans fr.2.2.1, pure.world.trans fr.2.2.2.1,
      pure.views.trans fr.2.2.2.2.1, pure.afterFormed⟩
  have cellAt : ∀ s, Frame s → s.cellId? 3 = some B.nextCell := fun s fr => by
    simp [State.cellId?, fr.2.1, State.bindLocal, State.bindCell]
  have condAt : ∀ s (k : Nat), Frame s → s.local? 3 = some (.signed .i32 k) →
      RunsExpr P s (.binary .less (.local 3) (.field (.local 0) 1)) (.boolean (decide ((k : Int) < n))) s :=
    fun s k fr idx => RunsExpr.binary (RunsExpr.local' idx)
      (RunsExpr.field' (j := 1) (RunsExpr.local' (frameLocals s fr).1) rfl) (by decide) (eval_i32_lt _ _ _)
  let measure : State → Nat := fun s => n - counter 3 s
  let oracle : TotalWhileOracle measure P (.binary .less (.local 3) (.field (.local 0) 1))
      (.sequence
        (.ifThenElse (.call eq [.index (.local 2) (.local 3), .local 1]) (.returnValue (some (.local 3))) .skip)
        (increment 3)) := {
    Inv := fun s => ∃ k, k ≤ n ∧ Frame s ∧ s.local? 3 = some (.signed .i32 k) ∧ Before k
    Done := fun c s => Frame s ∧ ((c = .next ∧ Before n) ∨
      (∃ k, ∃ inside : k < n, c = .returned (some (.signed .i32 k)) ∧ eqv xs[k] item = true ∧ Before k))
    step := by
      intro s invariant
      obtain ⟨k, kle, fr, idx, before⟩ := invariant
      have cond := condAt s k fr idx
      by_cases last : k = n
      · subst last
        rw [show decide (((xs.length : Nat) : Int) < xs.length) = false by simp] at cond
        obtain ⟨threshold, stable, _⟩ := cond
        exact Or.inl ⟨threshold, s, stable, fr, Or.inl ⟨rfl, before⟩⟩
      · have kn : k < n := by omega
        rw [show decide ((k : Int) < n) = true by simp; omega] at cond
        obtain ⟨condThreshold, condStable, _⟩ := cond
        obtain ⟨s0, s1, s2⟩ := frameLocals s fr
        have readOk : readRawSliceIndex P s T (viewAddr T size p cap) cap k = .ok xs[k] :=
          reads k kn s (by rw [fr.2.2.1, hB]; exact ReadsWithin.refl _ _ _)
        obtain ⟨a1, callRun, pure1⟩ := eqSpec s fr.2.2.2.2.2 xs[k] (List.getElem_mem _)
        have test := callArgs (RunsExprs.two (RunsExpr.rawIndex s2 idx readOk) (RunsExpr.local' s1)) callRun
        have fr1 := framePure s a1 fr pure1
        have idx1 := pure1.localFound idx
        right
        cases equal : eqv xs[k] item with
        | true =>
            rw [equal] at test
            obtain ⟨bodyThreshold, bodyStable, _⟩ : RunsStmt P s _ (.returned (some (.signed .i32 k))) a1 :=
              RunsStmt.sequenceCompleted (RunsStmt.ifThenElseTrue test
                (RunsStmt.returnValue (RunsExpr.local' idx1))) (by intro h; cases h) (increment 3)
            refine ⟨condThreshold, bodyThreshold, s, _, a1, condStable, bodyStable,
              fun _ => ⟨fr1, Or.inr ⟨k, kn, rfl, equal, before⟩⟩, fun h => ?_⟩
            rcases h with h | h <;> cases h
        | false =>
            rw [equal] at test
            have cell1 := cellAt a1 fr1
            obtain ⟨a2, assigned⟩ := assignLocal_exists a1 3 _ (.signed .i32 (Int.ofNat (k + 1))) _ cell1 idx1
            obtain ⟨bodyThreshold, bodyStable, _⟩ : RunsStmt P s _ .next a2 :=
              RunsStmt.sequenceNext (RunsStmt.ifThenElseFalse test (RunsStmt.skip P a1))
                (increment_run inst.target (by omega) cell1 idx1 assigned)
            obtain ⟨cells2, formed2, locals2, heap2, world2, views2⟩ :=
              FreshCellFrame.assignCounter fB fr1.2.2.2.2.2 fr1.1 (assignLocal_assignCell 3 _ _ cell1 assigned)
            have fr2 : Frame a2 := ⟨cells2, locals2.trans fr1.2.1, heap2.trans fr1.2.2.1,
              world2.trans fr1.2.2.2.1, views2.trans fr1.2.2.2.2.1, formed2⟩
            have idx2 := assignLocal_finds_assigned 3 _ _ cell1 assigned
            refine ⟨condThreshold, bodyThreshold, s, .next, a2, condStable, bodyStable,
              fun h => absurd rfl h.1, fun _ => ⟨?_, k + 1, kn, fr2, idx2, ?_⟩⟩
            · show n - counter 3 a2 < n - counter 3 s
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
  · have missing : xs.findIdx? (eqv · item) = none := by
      rw [List.findIdx?_eq_none_iff]
      intro x member
      obtain ⟨i, inside, rfl⟩ := List.getElem_of_mem member
      exact absent i inside inside
    rw [missing]
    have negOne : evalUnaryValue P.target .negate (.signed .i32 1) = .ok (.signed .i32 (-1)) := by
      rw [inst.target]; rfl
    exact RunsStmt.sequenceNext loopRun (RunsStmt.returnValue (RunsExpr.unary (RunsExpr.value' _) negOne))
  · have first : xs.findIdx? (eqv · item) = some k := by
      rw [List.findIdx?_eq_some_iff_getElem]
      exact ⟨kn, equal, fun j below => by rw [before j (by omega) below]; decide⟩
    rw [first]
    exact RunsStmt.sequenceCompleted loopRun (by intro h; cases h) _

#print axioms index_of_spec

end Lanius.Std
