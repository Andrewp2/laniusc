import Lanius.Std.VecSorted

/-! # `binary_search` and `is_sorted` -/

namespace Lanius.Std

open Lanius Lanius.Core Lanius.Semantics Lanius.Memory

variable {P : Program} {T : Ty} {ids : VecIds} {size : Nat}

theorem PureRun.guardTakenAfter {S S' : State} {c : Expr} {t rest : Stmt} {k : Completion}
    (cond : RunsExpr P S c (.boolean true) S') (cf : PureFrame S S') (branch : PureRun P S' t k)
    (notNext : k ≠ .next) : PureRun P S (.sequence (.ifThenElse c t .skip) rest) k := by
  obtain ⟨after, run, frame⟩ := branch
  exact ⟨after, RunsStmt.sequenceCompleted (RunsStmt.ifThenElseTrue cond run) notNext rest, cf.trans frame⟩

theorem PureRun.guardSkipAfter {S S' : State} {c : Expr} {t rest : Stmt} {k : Completion}
    (cond : RunsExpr P S c (.boolean false) S') (cf : PureFrame S S') (tail : PureRun P S' rest k) :
    PureRun P S (.sequence (.ifThenElse c t .skip) rest) k := by
  obtain ⟨after, run, frame⟩ := tail
  exact ⟨after, RunsStmt.sequenceNext (RunsStmt.ifThenElseFalse cond (RunsStmt.skip P S')) run, cf.trans frame⟩

theorem lowerBoundOf_le (ltv : Value → Value → Bool) (needle : Value) (xs : List Value) :
    lowerBoundOf ltv needle xs ≤ xs.length := (List.takeWhile_sublist _).length_le

/-! ## `binary_search` -/

/-- `pub fn binary_search<T>(value: Vec<T>, needle: T) -> i32`, with `value`,
`needle`, `index` and `items` the locals 0 to 3. -/
def binarySearchFn (ids : VecIds) (T : Ty) (f lb lt : FunctionId) : Function where
  id := f
  parameters := [(0, vecTy ids), (1, T)]
  returnType := i32Ty
  body := some <|
    .letLocal 2 i32Ty (.call lb [.local 0, .local 1])
    (guardReturn (.binary .equal (.local 2) (.field (.local 0) 1)) (.unary .negate (int 1))
    (.letLocal 3 (.slice T) (.call ids.slots [.local 0])
    (guardReturn (.call lt [.local 1, .index (.local 3) (.local 2)]) (.unary .negate (int 1))
    (.returnValue (some (.local 2))))))

/-- The first index holding an element equivalent to `needle`, or -1. -/
def binarySearchOf (ltv : Value → Value → Bool) (needle : Value) (xs : List Value) : Int :=
  match xs[lowerBoundOf ltv needle xs]? with
  | none => -1
  | some y => if ltv needle y then -1 else (lowerBoundOf ltv needle xs : Int)

theorem binarySearch_spec (inst : VecInstance P T ids) (kind : ElemKind P T size) {f lb lt : FunctionId}
    (found : P.function? f = some (binarySearchFn ids T f lb lt))
    (lbFound : P.function? lb = some (lowerBoundFn ids T lb lt))
    {ltv : Value → Value → Bool} {needle : Value} {xs : List Value}
    (ltSpec : LtSpec P lt ltv (needle :: xs)) (sorted : Sorted ltv xs) (order : NegTrans ltv)
    {caller : State} (formed : caller.CellsWellFormed) {v : Value}
    (rep : VecRep P T size ids.vec caller.heap v xs) :
    ∃ after, RunsExpr P caller (.call f ([v, needle].map Expr.value))
      (.signed .i32 (binarySearchOf ltv needle xs)) after ∧ PureFrame caller after := by
  have target := inst.target
  have rep' := rep
  obtain ⟨p, cap, rfl, lenLe, capBound, buffer, reads⟩ := rep
  let vv := Value.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]
  refine PureRun.call found rfl rfl formed ?_
  let E0 : State := { caller with locals := [] }
  have f0 : E0.CellsWellFormed := formed
  have f1 := f0.bindLocal 0 vv
  let E := (E0.bindLocal 0 vv).bindLocal 1 needle
  change PureRun P E _ _
  have fE : E.CellsWellFormed := f1.bindLocal _ _
  have l1 : E.local? 1 = some needle := local_bound f1 1 _
  have l0 : E.local? 0 = some vv := local_kept f1 _ (by decide) (local_bound f0 0 _)
  obtain ⟨A, lbRun, lbFrame⟩ := lowerBound_spec inst kind lbFound ltSpec sorted order fE rep'
  refine PureRun.letRun (callArgs (RunsExprs.two (RunsExpr.local' l0) (RunsExpr.local' l1)) lbRun) lbFrame ?_
  obtain ⟨r, hr⟩ : ∃ r, lowerBoundOf ltv needle xs = r := ⟨_, rfl⟩
  have rle : r ≤ xs.length := hr ▸ lowerBoundOf_le ltv needle xs
  rw [hr]
  unfold binarySearchOf
  rw [hr]
  have fA : A.CellsWellFormed := lbFrame.afterFormed
  let A2 := A.bindLocal 2 (.signed .i32 r)
  have fA2 : A2.CellsWellFormed := fA.bindLocal _ _
  have a2_2 : A2.local? 2 = some (.signed .i32 r) := local_bound fA 2 _
  have a2_1 : A2.local? 1 = some needle := local_kept fA _ (by decide) (lbFrame.localFound l1)
  have a2_0 : A2.local? 0 = some vv := local_kept fA _ (by decide) (lbFrame.localFound l0)
  have hA2 : A2.heap = caller.heap := lbFrame.heap
  have negOne : evalUnaryValue P.target .negate (.signed .i32 1) = .ok (.signed .i32 (-1)) := by
    rw [target]; rfl
  have cond := RunsExpr.binary (operation := .equal) (program := P) (RunsExpr.local' a2_2)
    (RunsExpr.field' (j := 1) (RunsExpr.local' a2_0) rfl) (by decide) (eval_i32_eq _ _ _)
  by_cases last : r = xs.length
  · rw [show ((r : Int) == (xs.length : Int)) = true by simp [last]] at cond
    rw [show xs[r]? = none from List.getElem?_eq_none (by omega)]
    exact PureRun.guardTaken cond (PureRun.ret fA2 (RunsExpr.unary (RunsExpr.value' _) negOne)) (by intro h; cases h)
  · have rn : r < xs.length := by omega
    rw [show ((r : Int) == (xs.length : Int)) = false by simp; omega] at cond
    refine PureRun.guardSkip cond ?_
    rw [List.getElem?_eq_getElem rn]
    dsimp only
    obtain ⟨S3, slots, frame⟩ := slots_call inst kind fA2 a2_0 capBound (fun pos => by rw [hA2]; exact buffer pos)
    refine PureRun.letRun slots frame ?_
    have fS3 : S3.CellsWellFormed := frame.afterFormed
    let view := Value.rawSlice T (viewAddr T size p cap) cap
    let A3 := S3.bindLocal 3 view
    have fA3 : A3.CellsWellFormed := fS3.bindLocal _ _
    have a3_3 : A3.local? 3 = some view := local_bound fS3 3 _
    have a3_2 : A3.local? 2 = some (.signed .i32 r) := local_kept fS3 _ (by decide) (frame.localFound a2_2)
    have a3_1 : A3.local? 1 = some needle := local_kept fS3 _ (by decide) (frame.localFound a2_1)
    have readOk : readRawSliceIndex P A3 T (viewAddr T size p cap) cap r = .ok xs[r] :=
      reads r rn A3 (by rw [show A3.heap = caller.heap from frame.heap.trans hA2]; exact ReadsWithin.refl _ _ _)
    obtain ⟨A4, call, pure⟩ := ltSpec A3 fA3 needle (by simp) xs[r] (by simp)
    have test := callArgs (RunsExprs.two (RunsExpr.local' a3_1) (RunsExpr.rawIndex a3_3 a3_2 readOk)) call
    have fA4 : A4.CellsWellFormed := pure.afterFormed
    cases greater : ltv needle xs[r] with
    | true =>
        rw [greater] at test
        exact PureRun.guardTakenAfter test pure (PureRun.ret fA4 (RunsExpr.unary (RunsExpr.value' _) negOne))
          (by intro h; cases h)
    | false =>
        rw [greater] at test
        exact PureRun.guardSkipAfter test pure (PureRun.ret fA4 (RunsExpr.local' (pure.localFound a3_2)))

/-! ## `is_sorted` -/

/-- `pub fn is_sorted<T>(value: Vec<T>) -> bool`, with `value`, `items` and
`index` the locals 0 to 2. -/
def isSortedFn (ids : VecIds) (T : Ty) (f lt : FunctionId) : Function where
  id := f
  parameters := [(0, vecTy ids)]
  returnType := boolTy
  body := some <|
    .letLocal 1 (.slice T) (.call ids.slots [.local 0])
    (.letLocal 2 i32Ty (int 1)
    (.sequence
      (.whileLoop (.binary .less (.local 2) (.field (.local 0) 1))
        (.sequence
          (.ifThenElse (.call lt [.index (.local 1) (.local 2), .index (.local 1) (.binary .subtract (.local 2) (int 1))])
            (.returnValue (some (.value (.boolean false)))) .skip)
          (increment 2)))
      (.returnValue (some (.value (.boolean true))))))

theorem sorted_of_adjacent {ltv : Value → Value → Bool} {xs : List Value} (order : NegTrans ltv)
    (adjacent : ∀ i (h : i + 1 < xs.length), ltv xs[i + 1] xs[i] = false) : Sorted ltv xs := by
  refine List.pairwise_iff_getElem.mpr fun i j hi hj hij => ?_
  show ltv xs[j] xs[i] = false
  have key : ∀ d j (hj : j < xs.length), j = i + 1 + d → ltv xs[j] xs[i] = false := by
    intro d
    induction d with
    | zero => intro j hj e; subst e; exact adjacent i hj
    | succ d ih =>
        intro j hj e
        obtain ⟨j', rfl⟩ : ∃ j', j = j' + 1 := ⟨j - 1, by omega⟩
        have prev := ih j' (by omega) (by omega)
        have step := adjacent j' hj
        cases h : ltv xs[j' + 1] xs[i] with
        | false => rfl
        | true =>
            rcases order _ xs[j'] _ h with h' | h'
            · rw [step] at h'; cases h'
            · rw [prev] at h'; cases h'
  exact key (j - i - 1) j hj (by omega)

theorem isSorted_spec (inst : VecInstance P T ids) (kind : ElemKind P T size) {f lt : FunctionId}
    (found : P.function? f = some (isSortedFn ids T f lt))
    {ltv : Value → Value → Bool} {xs : List Value} (ltSpec : LtSpec P lt ltv xs) (order : NegTrans ltv)
    {caller : State} (formed : caller.CellsWellFormed) {v : Value}
    (rep : VecRep P T size ids.vec caller.heap v xs) :
    ∃ (after : State) (b : Bool), RunsExpr P caller (.call f ([v].map Expr.value)) (.boolean b) after ∧
      PureFrame caller after ∧ (b = true ↔ Sorted ltv xs) := by
  have target := inst.target
  obtain ⟨p, cap, rfl, lenLe, capBound, buffer, reads⟩ := rep
  let vv := Value.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]
  let E0 : State := { caller with locals := [] }
  have f0 : E0.CellsWellFormed := formed
  let E := E0.bindLocal 0 vv
  have fE : E.CellsWellFormed := f0.bindLocal _ _
  have l0 : E.local? 0 = some vv := local_bound f0 0 _
  obtain ⟨S', slots, frame⟩ := slots_call inst kind fE l0 capBound buffer
  have fS : S'.CellsWellFormed := frame.afterFormed
  let view := Value.rawSlice T (viewAddr T size p cap) cap
  let B := S'.bindLocal 1 view
  have fB : B.CellsWellFormed := fS.bindLocal _ _
  have b1 : B.local? 1 = some view := local_bound fS 1 _
  have b0 : B.local? 0 = some vv := local_kept fS _ (by decide) (frame.localFound l0)
  have hB : B.heap = caller.heap := frame.heap
  -- the loop
  let n := xs.length
  let Frame : State → Prop := fun s => FreshCellFrame B s ∧
    s.locals = (B.bindLocal 2 (.signed .i32 1)).locals ∧ s.heap = B.heap ∧ s.world = B.world ∧
    s.i32ArrayViews = B.i32ArrayViews ∧ s.CellsWellFormed
  let Before : Nat → Prop := fun k => ∀ i (h : i + 1 < n), i + 1 < k → ltv xs[i + 1] xs[i] = false
  have frameLocals : ∀ s, Frame s → s.local? 0 = some vv ∧ s.local? 1 = some view :=
    fun s fr => ⟨local_above fr.1 fr.2.1 (by decide) b0, local_above fr.1 fr.2.1 (by decide) b1⟩
  have framePure : ∀ s s', Frame s → PureFrame s s' → Frame s' := fun s s' fr pure =>
    ⟨fr.1.trans pure.cells, pure.locals.trans fr.2.1, pure.heap.trans fr.2.2.1, pure.world.trans fr.2.2.2.1,
      pure.views.trans fr.2.2.2.2.1, pure.afterFormed⟩
  have cellAt : ∀ s, Frame s → s.cellId? 2 = some B.nextCell := fun s fr => by
    simp [State.cellId?, fr.2.1, State.bindLocal, State.bindCell]
  have condAt : ∀ s (k : Nat), Frame s → s.local? 2 = some (.signed .i32 k) →
      RunsExpr P s (.binary .less (.local 2) (.field (.local 0) 1)) (.boolean (decide ((k : Int) < n))) s :=
    fun s k fr idx => RunsExpr.binary (RunsExpr.local' idx)
      (RunsExpr.field' (j := 1) (RunsExpr.local' (frameLocals s fr).1) rfl) (by decide) (eval_i32_lt _ _ _)
  let measure : State → Nat := fun s => n - counter 2 s
  let body : Stmt := .sequence
    (.ifThenElse (.call lt [.index (.local 1) (.local 2), .index (.local 1) (.binary .subtract (.local 2) (int 1))])
      (.returnValue (some (.value (.boolean false)))) .skip)
    (increment 2)
  let oracle : TotalWhileOracle measure P (.binary .less (.local 2) (.field (.local 0) 1)) body := {
    Inv := fun s => ∃ k, 1 ≤ k ∧ (k ≤ n ∨ k = 1) ∧ Frame s ∧ s.local? 2 = some (.signed .i32 k) ∧ Before k
    Done := fun c s => Frame s ∧ ((c = .next ∧ Before n) ∨
      (c = .returned (some (.boolean false)) ∧ ∃ i, ∃ h : i + 1 < n, ltv xs[i + 1] xs[i] = true))
    step := by
      intro s invariant
      obtain ⟨k, one, kle, fr, idx, before⟩ := invariant
      have cond := condAt s k fr idx
      by_cases more : k < n
      · rw [show decide ((k : Int) < n) = true by simp; omega] at cond
        obtain ⟨condThreshold, condStable, _⟩ := cond
        obtain ⟨s0, s1⟩ := frameLocals s fr
        have readK : readRawSliceIndex P s T (viewAddr T size p cap) cap k = .ok xs[k] :=
          reads k more s (by rw [fr.2.2.1, hB]; exact ReadsWithin.refl _ _ _)
        have readPrev : readRawSliceIndex P s T (viewAddr T size p cap) cap (k - 1) = .ok (xs[k - 1]'(by omega)) :=
          reads (k - 1) (by omega) s (by rw [fr.2.2.1, hB]; exact ReadsWithin.refl _ _ _)
        have prevIndex := RunsExpr.binary (operation := .subtract) (RunsExpr.local' idx)
          (RunsExpr.value' (P := P) (S := s) (.signed .i32 1)) (by decide)
          (by rw [target]; exact eval_i32_sub (by omega) (by omega))
        rw [show (k : Int) - 1 = Int.ofNat (k - 1) by simp only [Int.ofNat_eq_natCast]; omega] at prevIndex
        obtain ⟨_, prevStable, _⟩ := prevIndex
        have right : RunsExpr P s (.index (.local 1) (.binary .subtract (.local 2) (int 1))) (xs[k - 1]'(by omega)) s :=
          RunsExpr.ofStable (StableExpr.rawSliceIndexAt s1 prevStable readPrev) rfl
        obtain ⟨a1, callRun, pure1⟩ := ltSpec s fr.2.2.2.2.2 xs[k] (List.getElem_mem _) (xs[k - 1]'(by omega))
          (List.getElem_mem _)
        have test := callArgs (RunsExprs.two (RunsExpr.rawIndex s1 idx readK) right) callRun
        have fr1 := framePure s a1 fr pure1
        have idx1 := pure1.localFound idx
        have kEq : k - 1 + 1 = k := by omega
        right
        cases bad : ltv xs[k] (xs[k - 1]'(by omega)) with
        | true =>
            rw [bad] at test
            obtain ⟨bodyThreshold, bodyStable, _⟩ : RunsStmt P s body (.returned (some (.boolean false))) a1 :=
              RunsStmt.sequenceCompleted (RunsStmt.ifThenElseTrue test
                (RunsStmt.returnValue (RunsExpr.value' (P := P) (S := a1) (.boolean false)))) (by intro h; cases h)
                (increment 2)
            refine ⟨condThreshold, bodyThreshold, s, _, a1, condStable, bodyStable,
              fun _ => ⟨fr1, Or.inr ⟨rfl, k - 1, by omega, ?_⟩⟩, fun h => ?_⟩
            · have e : xs[k - 1 + 1]'(by omega) = xs[k] := by simp only [kEq]
              rw [e]; exact bad
            · rcases h with h | h <;> cases h
        | false =>
            rw [bad] at test
            have cell1 := cellAt a1 fr1
            obtain ⟨a2, assigned⟩ := assignLocal_exists a1 2 _ (.signed .i32 (Int.ofNat (k + 1))) _ cell1 idx1
            obtain ⟨bodyThreshold, bodyStable, _⟩ : RunsStmt P s body .next a2 :=
              RunsStmt.sequenceNext (RunsStmt.ifThenElseFalse test (RunsStmt.skip P a1))
                (increment_run target (by omega) cell1 idx1 assigned)
            obtain ⟨cells2, formed2, locals2, heap2, world2, views2⟩ :=
              FreshCellFrame.assignCounter fB fr1.2.2.2.2.2 fr1.1 (assignLocal_assignCell 2 _ _ cell1 assigned)
            have fr2 : Frame a2 := ⟨cells2, locals2.trans fr1.2.1, heap2.trans fr1.2.2.1,
              world2.trans fr1.2.2.2.1, views2.trans fr1.2.2.2.2.1, formed2⟩
            have idx2 := assignLocal_finds_assigned 2 _ _ cell1 assigned
            refine ⟨condThreshold, bodyThreshold, s, .next, a2, condStable, bodyStable,
              fun h => absurd rfl h.1, fun _ => ⟨?_, k + 1, by omega, Or.inl (by omega), fr2, idx2, ?_⟩⟩
            · show n - counter 2 a2 < n - counter 2 s
              rw [counter_eq idx2, counter_eq idx]; omega
            · intro i h below
              by_cases same : i + 1 = k
              · have e1 : xs[i + 1] = xs[k] := by simp only [same]
                have e2 : xs[i]'(by omega) = xs[k - 1]'(by omega) := by simp only [show i = k - 1 by omega]
                rw [e1, e2]; exact bad
              · exact before i h (by omega)
      · rw [show decide ((k : Int) < n) = false by simp; omega] at cond
        obtain ⟨threshold, stable, _⟩ := cond
        exact Or.inl ⟨threshold, s, stable, fr, Or.inl ⟨rfl, fun i h _ => before i h (by omega)⟩⟩ }
  have entryFrame : Frame (B.bindLocal 2 (.signed .i32 1)) :=
    ⟨FreshCellFrame.bindLocal B 2 _, rfl, rfl, rfl, rfl, fB.bindLocal _ _⟩
  obtain ⟨threshold, completion, after, loopStable, done⟩ :=
    executeTotalWhile measure P _ _ oracle (B.bindLocal 2 (.signed .i32 1))
      ⟨1, Nat.le_refl _, Or.inr rfl, entryFrame, local_bound fB 2 _, fun i _ below => by omega⟩
  obtain ⟨frA, result⟩ := done
  have loopRun : RunsStmt P (B.bindLocal 2 (.signed .i32 1)) _ completion after := ⟨threshold, loopStable, frA.2.1⟩
  have pureAfter : FreshCellFrame B after ∧ after.heap = B.heap ∧ after.world = B.world ∧
      after.i32ArrayViews = B.i32ArrayViews := ⟨frA.1, frA.2.2.1, frA.2.2.2.1, frA.2.2.2.2.1⟩
  rcases result with ⟨rfl, all⟩ | ⟨rfl, i, h, bad⟩
  · suffices whole : ∃ after', RunsExpr P caller (.call f ([vv].map Expr.value)) (.boolean true) after' ∧
        PureFrame caller after' by
      obtain ⟨after', run', frame'⟩ := whole
      exact ⟨after', true, run', frame', fun _ => sorted_of_adjacent order fun i h => all i h (by omega), fun _ => rfl⟩
    refine PureRun.call found rfl rfl formed ?_
    change PureRun P E _ _
    refine PureRun.letRun slots frame ?_
    refine PureRun.letValue fB ⟨_, RunsStmt.sequenceNext loopRun
      (RunsStmt.returnValue (RunsExpr.value' (P := P) (S := after) (.boolean true))), pureAfter⟩
  · suffices whole : ∃ after', RunsExpr P caller (.call f ([vv].map Expr.value)) (.boolean false) after' ∧
        PureFrame caller after' by
      obtain ⟨after', run', frame'⟩ := whole
      refine ⟨after', false, run', frame', Iff.intro (fun e => Bool.noConfusion e) (fun sorted => ?_)⟩
      rw [sorted.at (by omega) h (Nat.lt_succ_self i)] at bad; cases bad
    refine PureRun.call found rfl rfl formed ?_
    change PureRun P E _ _
    refine PureRun.letRun slots frame ?_
    exact PureRun.letValue fB ⟨_, RunsStmt.sequenceCompleted loopRun (by intro h; cases h) _, pureAfter⟩

#print axioms binarySearch_spec
#print axioms isSorted_spec

end Lanius.Std
