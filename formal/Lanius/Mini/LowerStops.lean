import Lanius.Mini.Progress
import Lanius.Mini.TypeSound

/-! Core to mini for runs that do not complete: a lowered statement whose
Core run fails (`Fails`: it runs out of every fuel, stops at a trap that is
not undefined, or completes past the heap's limit) is `Stops` for every
number of ticks. By induction on the ticks and then on the statement: a
sub-run that completes within the limit is the forward simulation's
(`stmt_sound`), and the rest of the run fails from where it ends; a sub-run
that does not complete fails itself. A loop's next iteration and a callee's
body are the previous tick count. A check whose guard fails stops at its
`1 / 0` whatever Core does; one that passes makes its pure expressions
evaluate (`SrcExpr.progress`), so a statement with no loop, call or
allocation completes and cannot fail. -/

namespace Lanius.Mini

open Lanius.Core (Value)
open Lanius.Semantics (State Cell Completion evalExpr evalExprs execStmt restoreLocals)

/-- A lowered statement whose Core run fails stops within `n` ticks. -/
def SrcStops (sp : SrcProgram) (mp : Program) (n : Nat) (s : SrcStmt) : Prop :=
  ∀ {hp : Heap} {ret : SrcType} {scope : List Binding} {next : Nat} {stmt : Stmt}
    {frame : Nat → Nat} {base : Nat} {st : State} {env : Env},
    s.lower (sigs sp.funcs) sp.decls ret scope next = some stmt →
    Corr scope frame st env → Layout scope frame base next → st.Fresh → base ≤ st.nextCell →
    HeapCorr st.heap hp → st.heap.nextAddress ≤ hp.limit →
    Fails sp hp.limit st s.toCore → ∃ d, Stops mp d env hp stmt n

abbrev StmtStops (sp : SrcProgram) (mp : Program) (n : Nat) : Prop := ∀ s, SrcStops sp mp n s

/-- A lowered effectful expression whose Core evaluation fails stops within
`n` ticks. -/
def EvalStops (sp : SrcProgram) (mp : Program) (n : Nat) : Prop :=
  ∀ {hp : Heap} {e : SrcEff} {scope : List Binding} {slot : Nat} {ev : Evaluated}
    {frame : Nat → Nat} {base : Nat} {st : State} {env : Env},
    e.eval (sigs sp.funcs) sp.decls scope slot = some ev →
    Corr scope frame st env → Layout scope frame base slot → st.Fresh →
    HeapCorr st.heap hp → st.heap.nextAddress ≤ hp.limit →
    EFails sp hp.limit st e.toCore → ∃ d, Stops mp d env hp ev.stmt n

/-! ## Mini helpers -/

theorem Stops.checkThen_inv {prog : Program} {d : Nat} {env : Env} {hp : Heap} {s : Stmt} {n slot : Nat}
    {g : Expr} (pass : g.eval env ≠ 0) (stops : Stops prog d env hp (checkThen slot g s) n) :
    Stops prog d env hp s n := by
  unfold checkThen at stops
  split at stops
  · exact stops
  · cases stops with
    | zero => exact .zero
    | ifTrue _ inner => exact inner
    | ifFalse zero _ => exact absurd zero pass

/-- A check, with the depth the passing case needs. -/
theorem Stops.checked {prog : Program} {env : Env} {hp : Heap} {s : Stmt} {n slot : Nat} {g : Expr}
    (pass : g.eval env ≠ 0 → ∃ d, Stops prog d env hp s n) : ∃ d, Stops prog d env hp (checkThen slot g s) n := by
  by_cases zero : g.eval env = 0
  · exact ⟨0, Stops.check fun h => absurd zero h⟩
  · obtain ⟨d, stops⟩ := pass zero
    exact ⟨d, Stops.check fun _ => stops⟩

/-- A statement, then a check that fails. -/
theorem Stops.thenCheck {prog : Program} {d : Nat} {env env' : Env} {hp hp' : Heap} {s : Stmt} {n slot : Nat}
    {g : Expr} (exec : Exec prog d env hp s (.normal env' hp')) (zero : g.eval env' = 0) :
    Stops prog d env hp (Lanius.Mini.thenCheck slot g s) n := by
  unfold Lanius.Mini.thenCheck
  split
  · rename_i one
    rw [isOne_eval one] at zero
    exact absurd zero (by decide)
  · exact .seqSecond exec (.ifFalse zero .trap)

theorem Stops.thenCheck_first {prog : Program} {d : Nat} {env : Env} {hp : Heap} {s : Stmt} {n slot : Nat}
    {g : Expr} (stops : Stops prog d env hp s n) : Stops prog d env hp (Lanius.Mini.thenCheck slot g s) n := by
  unfold Lanius.Mini.thenCheck
  split
  · exact stops
  · exact .seqFirst stops

/-! ## Bodies that return -/

section Returns

variable {P : Core.Program}

/-- A run that completes does not fall through. -/
abbrev NoNext (P : Core.Program) (s : Core.Stmt) : Prop :=
  ∀ {fuel : Nat} {st : State} {c : Completion} {st' : State}, execStmt fuel P st s = .done c st' → c ≠ .next

theorem NoNext.letLocal {id : Nat} {ty : Core.Ty} {init : Core.Expr} {body : Core.Stmt} (ih : NoNext P body) :
    NoNext P (.letLocal id ty init body) := by
  intro fuel st c st' run
  cases fuel with
  | zero => simp [execStmt] at run
  | succ fuel =>
    simp only [execStmt] at run
    split at run
    · rename_i v st1 _
      cases hb : execStmt fuel P (st1.bindLocal id v) body <;>
        simp [hb, Semantics.restoreOutcomeLocals] at run
      obtain ⟨rfl, -⟩ := run
      exact ih hb
    all_goals simp at run

theorem NoNext.sequence {a b : Core.Stmt} (h : NoNext P a ∨ NoNext P b) : NoNext P (.sequence a b) := by
  intro fuel st c st' run
  cases fuel with
  | zero => simp [execStmt] at run
  | succ fuel =>
    simp only [execStmt] at run
    split at run
    · rename_i st1 firstRun
      rcases h with ha | hb
      · exact absurd rfl (ha firstRun)
      · exact hb run
    · rename_i completion st1 notNext firstRun
      simp only [Semantics.Outcome.done.injEq] at run
      obtain ⟨rfl, -⟩ := run
      exact notNext
    all_goals simp at run

theorem NoNext.ite {cond : Core.Expr} {a b : Core.Stmt} (ha : NoNext P a) (hb : NoNext P b) :
    NoNext P (.ifThenElse cond a b) := by
  intro fuel st c st' run
  cases fuel with
  | zero => simp [execStmt] at run
  | succ fuel =>
    simp only [execStmt] at run
    split at run
    · exact ha run
    · exact hb run
    all_goals simp at run

theorem NoNext.returnValue {value : Option Core.Expr} : NoNext P (.returnValue value) := by
  intro fuel st c st' run
  cases fuel with
  | zero => simp [execStmt] at run
  | succ fuel =>
    cases value with
    | none =>
      simp only [execStmt, Semantics.Outcome.done.injEq] at run
      obtain ⟨rfl, -⟩ := run
      simp
    | some e =>
      simp only [execStmt] at run
      split at run
      · simp only [Semantics.Outcome.done.injEq] at run
        obtain ⟨rfl, -⟩ := run
        simp
      all_goals simp at run

/-- A body the front pass checked to return on every path never falls
through. -/
theorem returns_noNext : ∀ (s : SrcStmt), s.returns = true → NoNext P s.toCore
  | .nop, h => by simp [SrcStmt.returns] at h
  | .let _ _ _ body, h => NoNext.letLocal (returns_noNext body h)
  | .letStruct _ _ _ body, h => NoNext.letLocal (returns_noNext body h)
  | .letCall _ _ _ _ body, h => NoNext.letLocal (returns_noNext body h)
  | .letEnum _ _ _ _ body, h => NoNext.letLocal (returns_noNext body h)
  | .letMatch _ _ _ _ _ body, h => NoNext.letLocal (returns_noNext body h)
  | .set _ _, h => by simp [SrcStmt.returns] at h
  | .setField _ _ _, h => by simp [SrcStmt.returns] at h
  | .setCall _ _ _, h => by simp [SrcStmt.returns] at h
  | .then first second, h => by
    simp only [SrcStmt.returns, Bool.or_eq_true] at h
    exact NoNext.sequence (h.imp (returns_noNext first) (returns_noNext second))
  | .if _ thenBranch elseBranch, h => by
    simp only [SrcStmt.returns, Bool.and_eq_true] at h
    exact NoNext.ite (returns_noNext thenBranch h.1) (returns_noNext elseBranch h.2)
  | .while _ _, h => by simp [SrcStmt.returns] at h
  | .return _, _ => NoNext.returnValue
  | .letAlloc _ _ _ body, h => NoNext.letLocal (returns_noNext body h)
  | .letLoad _ _ _ body, h => NoNext.letLocal (returns_noNext body h)
  | .setByte _ _ _, h => by simp [SrcStmt.returns] at h
  | .free _ _ _, h => by simp [SrcStmt.returns] at h
  | .letSlice _ _ _ _ body, h => NoNext.letLocal (returns_noNext body h)
  | .letIndex _ _ _ _ body, h => NoNext.letLocal (returns_noNext body h)
  | .setIndex _ _ _, h => by simp [SrcStmt.returns] at h
  | .letEval _ _ _ body, h => NoNext.letLocal (returns_noNext body h)
  | .setEval _ _, h => by simp [SrcStmt.returns] at h
  | .ifEval _ thenBranch elseBranch, h => by
    simp only [SrcStmt.returns, Bool.and_eq_true] at h
    exact NoNext.ite (returns_noNext thenBranch h.1) (returns_noNext elseBranch h.2)
  | .whileEval _ _, h => by simp [SrcStmt.returns] at h
  | .returnEval _, _ => NoNext.returnValue
  | .discard _, h => by simp [SrcStmt.returns] at h
  | .setIndexEval _ _ _, h => by simp [SrcStmt.returns] at h
  | .setFieldEval _ _ _, h => by simp [SrcStmt.returns] at h
  | .returnUnit, _ => NoNext.returnValue
  | .assert _, h => by simp [SrcStmt.returns] at h

end Returns

/-! ## Calls -/

section Calls

variable {sp : SrcProgram} {mp : Program} {n : Nat}

/-- The state a callee's body starts from. -/
abbrev calleeState (f : SrcFunc) (values : List Value) (afterArgs : State) : State :=
  ({ afterArgs with locals := [] } : State).bindLocals (paramBindings f.params values)

/-- The body of a call that fails, once its arguments are evaluated, fails,
unless it completes within the limit in a way the call cannot complete. -/
theorem EFails.callBody {L : Nat} {st : State} {callee : Nat} {args : List Core.Expr}
    (fails : EFails sp L st (.call callee args)) {k : Nat} {values : List Value} {afterArgs : State}
    (argsRun : evalExprs k sp.toCore st args = .done values afterArgs) {f : SrcFunc}
    (found : sp.funcs[callee]? = some f) (len : values.length = f.params.length)
    (shapes : ∀ {j : Nat} {c : Completion} {completed : State},
      execStmt j sp.toCore (calleeState f values afterArgs) f.body.toCore = .done c completed →
      completed.heap.nextAddress ≤ L →
      (c = .next ∧ f.ret = .unit) ∨ (∃ v, c = .returned (some v)) ∨ (c = .returned none ∧ f.ret = .unit)) :
    Fails sp L (calleeState f values afterArgs) f.body.toCore := by
  intro j
  have call := fails (max k j + 1)
  have argsRun' := values_after argsRun (Nat.le_max_left k j)
  simp only [evalExpr, argsRun', SrcProgram.function?_toCore, found, Option.map_some, SrcFunc.toCore,
    bindParameters_eq _ _ len] at call
  cases hb : execStmt j sp.toCore (calleeState f values afterArgs) f.body.toCore with
  | done c completed =>
    show L < completed.heap.nextAddress
    refine Nat.lt_of_not_le fun within => ?_
    have hb' := done_after hb (Nat.le_max_right k j)
    rcases shapes hb within with ⟨rfl, unit⟩ | ⟨v, rfl⟩ | ⟨rfl, unit⟩
    · simp only [calleeState] at hb'
      simp only [hb', unit, SrcType.toCore, if_true, Failing, restoreLocals] at call
      omega
    · simp only [calleeState] at hb'
      simp only [hb', Failing, restoreLocals] at call
      omega
    · simp only [calleeState] at hb'
      simp only [hb', unit, SrcType.toCore, if_true, Failing, restoreLocals] at call
      omega
  | trapped reason s =>
    have hb' := Semantics.execStmt_of_le hb (by intro h; cases h) (Nat.le_max_right k j)
    simp only [calleeState] at hb'
    simp only [hb', Failing] at call
    exact call
  | exited => trivial
  | outOfFuel => trivial

/-- A callee's frame: its parameters in correspondence with the mini entry. -/
theorem callee_frame (lowered : lowerFuncs (sigs sp.funcs) sp.decls sp.funcs = some mp.funcs) {callee : Nat}
    {f : SrcFunc} (found : sp.funcs[callee]? = some f) {st : State} (fresh : st.Fresh) {values : List Value}
    {bits : List (BitVec 64)} (holds : FieldsHold (paramTypes f.params) values (Func.entry bits) 0) :
    ∃ g b frame, mp.funcs[callee]? = some g ∧ g.params = paramsSize f.params ∧
      f.body.lower (sigs sp.funcs) sp.decls f.ret (paramScope f.params 0 []) (paramsSize f.params) = some b ∧
      unitTail f.ret (some b) = some g.body ∧
      Corr (paramScope f.params 0 []) frame (calleeState f values st) (Func.entry bits) ∧
      Layout (paramScope f.params 0 []) frame st.nextCell (paramsSize f.params) ∧
      (calleeState f values st).Fresh ∧ Keeps st.nextCell ({ st with locals := [] } : State) (calleeState f values st) := by
  obtain ⟨g, gFound, gOk⟩ := lowerFuncs_get lowered found
  obtain ⟨gParams, _, valid, b, bodyOk, tail⟩ := lowerFunc_some gOk
  obtain ⟨frame, corr, fr, fresh0, keeps0⟩ := entry_corr (Func.entry bits) st.nextCell f.params
    (k := 0) (scope := []) (frame := fun _ => 0) (st := { st with locals := [] }) holds valid
    (Nat.le_refl _) fresh ⟨rfl, fun _ mem => by simp at mem⟩
    ⟨fun _ mem => by simp at mem, fun _ mem => by simp at mem, fun _ mem => by simp at mem,
      fun _ mem => by simp at mem, fun _ mem => by simp at mem⟩
  rw [Nat.zero_add] at fr
  exact ⟨g, b, frame, gFound, gParams, bodyOk, tail, corr, fr, fresh0, keeps0⟩

/-- How a callee's body that completes within the limit completes. -/
theorem body_shapes (lowered : lowerFuncs (sigs sp.funcs) sp.decls sp.funcs = some mp.funcs)
    (returns : funcsReturn sp.funcs = true) {callee : Nat} {f : SrcFunc} (found : sp.funcs[callee]? = some f)
    {hp : Heap} {st : State} (fresh : st.Fresh) (hc : HeapCorr st.heap hp) {values : List Value}
    {bits : List (BitVec 64)} (holds : FieldsHold (paramTypes f.params) values (Func.entry bits) 0)
    {j : Nat} {c : Completion} {completed : State}
    (run : execStmt j sp.toCore (calleeState f values st) f.body.toCore = .done c completed)
    (bound : completed.heap.nextAddress ≤ hp.limit) :
    (c = .next ∧ f.ret = .unit) ∨ (∃ v, c = .returned (some v)) ∨ (c = .returned none ∧ f.ret = .unit) := by
  obtain ⟨g, b, frame, -, -, bodyOk, -, corr, fr, fresh0, keeps0⟩ := callee_frame lowered found fresh holds
  have hc0 : HeapCorr (calleeState f values st).heap hp := by
    rw [(bindLocals_same _ _).1]
    exact hc
  obtain ⟨-, -, _, _, _, matched⟩ := stmt_sound lowered j (hp := hp) bodyOk corr fr fresh0 keeps0.next hc0 run bound
  cases matched with
  | next =>
    refine .inl ⟨rfl, ?_⟩
    have each := TypeSound.funcsReturn_each returns f (List.mem_of_getElem? found)
    by_cases unit : f.ret = .unit
    · exact unit
    · have nonUnit : f.ret.isUnit = false := by
        cases h : f.ret <;> simp_all [SrcType.isUnit]
      rw [nonUnit, Bool.false_or] at each
      exact absurd rfl (returns_noNext f.body each run)
  | @returned v _ _ holdsRet _ _ =>
    cases v with
    | some w => exact .inr (.inl ⟨w, rfl⟩)
    | none => exact .inr (.inr ⟨rfl, holdsRet⟩)

/-- The callee of a call that fails stops, one tick fewer. -/
theorem callee_stops (lowered : lowerFuncs (sigs sp.funcs) sp.decls sp.funcs = some mp.funcs)
    (returns : funcsReturn sp.funcs = true) (prev : StmtStops sp mp n)
    {callee : Nat} {args : List Core.Expr} {st afterArgs : State} {k : Nat} {values : List Value}
    (argsRun : evalExprs k sp.toCore st args = .done values afterArgs) {f : SrcFunc}
    (found : sp.funcs[callee]? = some f) {hp : Heap} (fresh : afterArgs.Fresh) (hc : HeapCorr afterArgs.heap hp)
    (within : afterArgs.heap.nextAddress ≤ hp.limit) {bits : List (BitVec 64)}
    (holds : FieldsHold (paramTypes f.params) values (Func.entry bits) 0) (bitsLen : bits.length = paramsSize f.params)
    (fails : EFails sp hp.limit st (.call callee args)) :
    ∃ d g, mp.funcs[callee]? = some g ∧ bits.length = g.params ∧ Stops mp d (Func.entry bits) hp g.body n := by
  obtain ⟨g, b, frame, gFound, gParams, bodyOk, tail, corr, fr, fresh0, keeps0⟩ :=
    callee_frame lowered found fresh holds
  have hc0 : HeapCorr (calleeState f values afterArgs).heap hp := by
    rw [(bindLocals_same _ _).1]
    exact hc
  have len : values.length = f.params.length := by rw [holds.length, paramTypes_length]
  have bodyFails := fails.callBody argsRun found len fun run bound =>
    body_shapes lowered returns found fresh hc holds run bound
  have within0 : (calleeState f values afterArgs).heap.nextAddress ≤ hp.limit := by
    rw [(bindLocals_same _ _).1]
    exact within
  obtain ⟨d, stops⟩ := prev f.body bodyOk corr fr fresh0 keeps0.next hc0 within0 bodyFails
  refine ⟨d, g, gFound, by rw [gParams, bitsLen], ?_⟩
  simp only [unitTail] at tail
  split at tail
  · simp only [Option.some.injEq] at tail
    rw [← tail]
    exact .seqFirst stops
  · simp only [Option.some.injEq] at tail
    rw [← tail]
    exact stops

/-- A call whose arguments are lowered: it stops, or completes within the limit. -/
theorem lowerCall_found {callee : Nat} {scope : List Binding} {args : List SrcExpr} {ty : SrcType}
    {es : List Expr} (ok : lowerCall (sigs sp.funcs) scope callee args ty = some es) :
    ∃ f, sp.funcs[callee]? = some f ∧ lowerArgs scope args (paramTypes f.params) = some es := by
  simp only [lowerCall, sigs_get] at ok
  cases found : sp.funcs[callee]? with
  | none => simp [found] at ok
  | some f =>
    simp only [found, Option.map_some, lowerCallSig] at ok
    split at ok
    · exact ⟨f, rfl, ok⟩
    · simp at ok

/-- A call that fails and whose guard holds stops, one tick more than its callee. -/
theorem call_stops (lowered : lowerFuncs (sigs sp.funcs) sp.decls sp.funcs = some mp.funcs)
    (returns : funcsReturn sp.funcs = true) (prev : StmtStops sp mp n) {scope frame st env}
    (corr : Corr scope frame st env) (fresh : st.Fresh) {hp : Heap} (hc : HeapCorr st.heap hp)
    (within : st.heap.nextAddress ≤ hp.limit) {callee : Nat} {args : List SrcExpr} {ty : SrcType}
    {es : List Expr} (ok : lowerCall (sigs sp.funcs) scope callee args ty = some es)
    (g : (guardAll scope args).eval env ≠ 0)
    (fails : EFails sp hp.limit st (.call callee (args.map SrcExpr.toCore))) (target count : Nat) :
    ∃ d, Stops mp d env hp (.call target count callee es) (n + 1) := by
  obtain ⟨f, found, argsOk⟩ := lowerCall_found ok
  obtain ⟨k, vs, argsRun⟩ := lowerArgs_progress corr (SrcProgram.target_toCore sp) argsOk g
  obtain ⟨-, holds, esLen, -⟩ := lowerArgs_sound corr (SrcProgram.target_toCore sp) argsOk argsRun
  obtain ⟨d, func, gFound, arity, stops⟩ := callee_stops lowered returns prev argsRun found fresh hc within holds
    (by rw [evalAll_length, esLen, paramsSize_eq]) fails
  exact ⟨d + 1, .call gFound (by rw [← arity, evalAll_length]) (Nat.lt_succ_self d) stops⟩

end Calls

/-! ## Assignments -/

section Assignments

variable {sp : SrcProgram} {L : Nat}

/-- Core's `id = e` on a local of the scope completes once `e` does. -/
theorem assign_local_progress {P : Core.Program} {scope frame st env} (corr : Corr scope frame st env)
    {id : Nat} {b : Binding} (found : lookup scope id = some b) {e : Core.Expr} {k : Nat} {rv : Value}
    {st2 : State} (valueRun : evalExpr k P st e = .done rv st2) (views : st2.i32ArrayViews = [])
    (present : (st2.cellEntry? (frame b.slot)).isSome) :
    ∃ k' st3, evalExpr k' P st (.assign .set (.local id) e) = .done .unit st3 ∧ st3.heap = st2.heap := by
  obtain ⟨v0, entry, _⟩ := corr.values b (lookup_mem found).1
  have place : Semantics.evalPlace (k + 1) P st .address (.local id) =
      .done { root := frame b.slot, projections := [], value := some v0 } st := by
    simp [Semantics.evalPlace, corr.cellId, found, entry]
  have valueRun' := Semantics.evalExpr_of_le valueRun (by intro h; cases h) (Nat.le_succ k)
  obtain ⟨e2, entry2⟩ := Option.isSome_iff_exists.mp present
  have synced := sync_ok (st := { st2 with cells := Semantics.replaceCell st2.cells (frame b.slot) rv }) views
  refine ⟨k + 2, { st2 with cells := Semantics.replaceCell st2.cells (frame b.slot) rv }, ?_, rfl⟩
  rw [evalExpr.eq_def]
  simp only [place, valueRun', Semantics.evalAssignValue, Semantics.assignOpBinary?,
    Semantics.writeResolvedPlaceNative, Semantics.writeResolvedPlace, assignCell_some entry2, synced, ite_self]

/-- A failing `id = e` whose `e` completes within the limit is impossible. -/
theorem Fails.assign_done {scope frame st env} (corr : Corr scope frame st env) {id : Nat} {b : Binding}
    (found : lookup scope id = some b) {e : Core.Expr}
    (fails : Fails sp L st (.expression (.assign .set (.local id) e))) {k : Nat} {rv : Value} {st2 : State}
    (valueRun : evalExpr k sp.toCore st e = .done rv st2) (views : st2.i32ArrayViews = [])
    (present : (st2.cellEntry? (frame b.slot)).isSome) (within : st2.heap.nextAddress ≤ L) : False := by
  obtain ⟨k', st3, run, heap⟩ := assign_local_progress corr found valueRun views present
  exact fails.not_done (k := k' + 1) (c := .next) (st' := st3) (by simp only [execStmt, run]) (by rw [heap]; exact within)

/-- The value of a failing `id = e` that never completes fails. -/
theorem EFails.assignValue {scope frame st env} (corr : Corr scope frame st env) {id : Nat} {b : Binding}
    (found : lookup scope id = some b) {e : Core.Expr} (fails : EFails sp L st (.assign .set (.local id) e))
    (none : ¬Completes L fun k => evalExpr k sp.toCore st e) : EFails sp L st e :=
  failing_of_not_completes fails (fun j reason s h => ⟨j + 2, s, by
    obtain ⟨v0, entry, _⟩ := corr.values b (lookup_mem found).1
    have place : Semantics.evalPlace (j + 1) sp.toCore st .address (.local id) =
        .done { root := frame b.slot, projections := [], value := some v0 } st := by
      simp [Semantics.evalPlace, corr.cellId, found, entry]
    rw [evalExpr.eq_def]
    simp only [place, Semantics.evalExpr_of_le h (by intro h; cases h) (Nat.le_succ j)]⟩) none

end Assignments

section Statements

variable {sp : SrcProgram} {mp : Program} {n : Nat}

/-- The body of a `let`, from the state after its initializer. -/
theorem let_stops {body : SrcStmt} (ih : SrcStops sp mp n body) {ret : SrcType} {scope : List Binding}
    {next : Nat} {bstmt : Stmt} {id : Nat} {ty : SrcType} {hp : Heap}
    (bodyOk : body.lower (sigs sp.funcs) sp.decls ret (⟨id, next, ty⟩ :: scope) (next + ty.size) = some bstmt)
    {frame base st env} (corr : Corr scope frame st env) (fr : Layout scope frame base next)
    (fresh : st.Fresh) (le : base ≤ st.nextCell) (sized : 0 < ty.size) {v : Value} {env' : Env}
    (agree : ScopeAgree scope env env') (holds : ty.HoldsAt v env' next)
    (hc : HeapCorr st.heap hp) (within : st.heap.nextAddress ≤ hp.limit)
    (fails : Fails sp hp.limit (st.bindLocal id v) body.toCore) :
    ∃ d, Stops mp d env' hp bstmt n :=
  ih (hp := hp) bodyOk (corr.push fr fresh agree holds) (fr.push (corr.below fresh) le id sized)
    (bindLocal_fresh fresh id v) (Nat.le_trans le (Nat.le_succ _)) hc within fails

theorem stops_nop : SrcStops sp mp n .nop := by
  intro hp ret scope next stmt frame base st env ok corr fr fresh le hc within fails
  have := fails 1
  simp only [SrcStmt.toCore, execStmt, Failing] at this
  exact absurd within (Nat.not_le.mpr this)

theorem stops_then (lowered : lowerFuncs (sigs sp.funcs) sp.decls sp.funcs = some mp.funcs)
    {first second : SrcStmt} (ih1 : SrcStops sp mp n first) (ih2 : SrcStops sp mp n second) :
    SrcStops sp mp n (.then first second) := by
  intro hp ret scope next stmt frame base st env ok corr fr fresh le hc within fails
  simp only [SrcStmt.lower, lowerThen] at ok
  split at ok
  · simp at ok
  rename_i a firstOk
  split at ok
  · simp at ok
  rename_i b secondOk
  simp only [Option.some.injEq] at ok
  subst ok
  simp only [SrcStmt.toCore] at fails
  by_cases done : Completes hp.limit fun k => execStmt k sp.toCore st first.toCore
  · obtain ⟨k, c, st1, run1, bound1⟩ := done
    obtain ⟨fresh1, keeps1, d1, out1, exec1, matched1⟩ :=
      stmt_sound lowered k firstOk corr fr fresh le hc run1 bound1
    cases matched1 with
    | next corr1 hc1 =>
      have limit := exec1.limit_normal
      obtain ⟨d2, stops2⟩ := ih2 secondOk corr1 fr fresh1 (Nat.le_trans le keeps1.next) hc1
        (by rw [limit]; exact bound1) (by rw [limit]; exact fails.seqSecond run1)
      exact ⟨_, Stops.after exec1 stops2⟩
    | returned =>
      have := fails (k + 1)
      simp only [execStmt, run1] at this
      exact absurd bound1 (Nat.not_le.mpr this)
  · obtain ⟨d, stops⟩ := ih1 firstOk corr fr fresh le hc within (fails.seqFirst done)
    exact ⟨d, .seqFirst stops⟩

theorem stops_if (lowered : lowerFuncs (sigs sp.funcs) sp.decls sp.funcs = some mp.funcs)
    {condition : SrcExpr} {thenBranch elseBranch : SrcStmt} (ih1 : SrcStops sp mp n thenBranch)
    (ih2 : SrcStops sp mp n elseBranch) : SrcStops sp mp n (.if condition thenBranch elseBranch) := by
  intro hp ret scope next stmt frame base st env ok corr fr fresh le hc within fails
  simp only [SrcStmt.lower] at ok
  replace ok := guarded_some ok
  obtain ⟨stmt, ok, rfl⟩ := ok
  simp only [lowerIf] at ok
  split at ok
  · simp at ok
  rename_i x condOk
  split at ok
  · simp at ok
  rename_i ts thenOk
  split at ok
  · simp at ok
  rename_i es elseOk
  simp only [Option.some.injEq] at ok
  subst ok
  refine Stops.checked fun g => ?_
  obtain ⟨k, w, condRun⟩ := lowerAs_progress corr (SrcProgram.target_toCore sp) condOk g
  obtain ⟨-, y, rfl, bits⟩ := lowerAs_sound corr (SrcProgram.target_toCore sp) condOk condRun
  simp only [SrcStmt.toCore] at fails
  have branch := fails.ifBranch condRun
  cases y with
  | true =>
    obtain ⟨d, stops⟩ := ih1 thenOk corr fr fresh le hc within branch
    exact ⟨d, .ifTrue (by rw [bits]; decide) stops⟩
  | false =>
    obtain ⟨d, stops⟩ := ih2 elseOk corr fr fresh le hc within branch
    exact ⟨d, .ifFalse (by rw [bits]; decide) stops⟩

theorem stops_while (lowered : lowerFuncs (sigs sp.funcs) sp.decls sp.funcs = some mp.funcs)
    {condition : SrcExpr} {body : SrcStmt} (prev : StmtStops sp mp n) (ih : SrcStops sp mp (n + 1) body) :
    SrcStops sp mp (n + 1) (.while condition body) := by
  intro hp ret scope next stmt frame base st env ok corr fr fresh le hc within fails
  have whileOk := ok
  simp only [SrcStmt.lower] at ok
  replace ok := guarded_some ok
  obtain ⟨stmt, ok, rfl⟩ := ok
  simp only [lowerWhile] at ok
  split at ok
  · simp at ok
  rename_i x condOk
  split at ok
  · simp at ok
  rename_i bstmt bodyOk
  simp only [Option.some.injEq] at ok
  subst ok
  refine Stops.checked fun g => ?_
  obtain ⟨k, w, condRun⟩ := lowerAs_progress corr (SrcProgram.target_toCore sp) condOk g
  obtain ⟨-, y, rfl, bits⟩ := lowerAs_sound corr (SrcProgram.target_toCore sp) condOk condRun
  simp only [SrcStmt.toCore] at fails
  cases y with
  | false =>
    have := fails (k + 1)
    simp only [execStmt, condRun] at this
    exact absurd within (Nat.not_le.mpr this)
  | true =>
    have condTrue : x.eval env ≠ 0 := by rw [bits]; decide
    by_cases done : Completes hp.limit fun j => execStmt j sp.toCore st body.toCore
    · obtain ⟨k', c, st1, run1, bound1⟩ := done
      obtain ⟨fresh1, keeps1, d1, out1, exec1, matched1⟩ :=
        stmt_sound lowered k' bodyOk corr fr fresh le hc run1 bound1
      cases matched1 with
      | @next env1 hp1 corr1 hc1 =>
        have limit := exec1.limit_normal
        by_cases pass : (condition.guard scope).eval env1 = 0
        · exact ⟨d1, .loopBody condTrue (Stops.thenCheck exec1 pass)⟩
        · obtain ⟨d2, stops2⟩ := prev (.while condition body) whileOk corr1 fr fresh1
            (Nat.le_trans le keeps1.next) hc1 (by rw [limit]; exact bound1)
            (by rw [limit]; exact fails.whileNext condRun run1)
          exact ⟨max d1 d2, .loopNext condTrue ((exec1.thenCheck pass).mono (Nat.le_max_left _ _))
            ((stops2.checkThen_inv pass).deeper (Nat.le_max_right _ _))⟩
      | returned =>
        have := fails (max k k' + 1)
        simp only [execStmt, value_after condRun (Nat.le_max_left k k'),
          done_after run1 (Nat.le_max_right k k')] at this
        exact absurd bound1 (Nat.not_le.mpr this)
    · obtain ⟨d, stops⟩ := ih bodyOk corr fr fresh le hc within (fails.whileBody condRun done)
      exact ⟨d, .loopBody condTrue stops.thenCheck_first⟩

theorem stops_let {id : Nat} {ty : SrcType} {value : SrcExpr} {body : SrcStmt} (ih : SrcStops sp mp n body) :
    SrcStops sp mp n (.let id ty value body) := by
  intro hp ret scope next stmt frame base st env ok corr fr fresh le hc within fails
  simp only [SrcStmt.lower] at ok
  replace ok := guarded_some ok
  obtain ⟨stmt, ok, rfl⟩ := ok
  simp only [lowerLet] at ok
  split at ok
  · simp at ok
  rename_i xs valueOk
  split at ok
  · simp at ok
  rename_i bstmt bodyOk
  simp only [Option.some.injEq] at ok
  subst ok
  refine Stops.checked fun g => ?_
  obtain ⟨k, v, valueRun⟩ := lowerValue_progress corr (SrcProgram.target_toCore sp) valueOk g
  obtain ⟨-, flat, shape⟩ := lowerValue_sound corr (SrcProgram.target_toCore sp) valueOk valueRun
  simp only [SrcStmt.toCore] at fails
  obtain ⟨d, stops⟩ := let_stops ih bodyOk corr fr fresh le (by rw [← flat.length]; exact shape.sized fr)
    (fr.agree fun j below => setFrom_outside xs next env j (.inl below))
    (flat.store (shape.insens_next fr)) hc within (fails.letBody valueRun)
  exact ⟨d, Stops.assignFrom xs next stops⟩

theorem stops_return {value : SrcExpr} : SrcStops sp mp n (.return value) := by
  intro hp ret scope next stmt frame base st env ok corr fr fresh le hc within fails
  simp only [SrcStmt.lower] at ok
  replace ok := guarded_some ok
  obtain ⟨stmt, ok, rfl⟩ := ok
  simp only [lowerReturn] at ok
  split at ok
  · simp at ok
  rename_i xs valueOk
  refine Stops.checked fun g => ?_
  obtain ⟨k, v, valueRun⟩ := lowerValue_progress corr (SrcProgram.target_toCore sp) valueOk g
  have := fails (k + 1)
  simp only [SrcStmt.toCore, execStmt, valueRun, Failing] at this
  exact absurd within (Nat.not_le.mpr this)

theorem stops_letCall (lowered : lowerFuncs (sigs sp.funcs) sp.decls sp.funcs = some mp.funcs)
    (returns : funcsReturn sp.funcs = true) (prev : StmtStops sp mp n) {id : Nat} {ty : SrcType}
    {callee : Nat} {args : List SrcExpr} {body : SrcStmt} (ih : SrcStops sp mp (n + 1) body) :
    SrcStops sp mp (n + 1) (.letCall id ty callee args body) := by
  intro hp ret scope next stmt frame base st env ok corr fr fresh le hc within fails
  simp only [SrcStmt.lower] at ok
  replace ok := guarded_some ok
  obtain ⟨stmt, ok, rfl⟩ := ok
  simp only [lowerLetCall] at ok
  split at ok
  · simp at ok
  rename_i es argsOk
  split at ok
  · simp at ok
  rename_i bstmt bodyOk
  simp only [Option.some.injEq] at ok
  subst ok
  refine Stops.checked fun g => ?_
  simp only [SrcStmt.toCore] at fails
  by_cases done : Completes hp.limit fun k => evalExpr k sp.toCore st (.call callee (args.map SrcExpr.toCore))
  · obtain ⟨k, v, st1, run1, bound1⟩ := done
    cases k with
    | zero => simp [evalExpr] at run1
    | succ k =>
      obtain ⟨fresh1, keeps1, locals1, sized, d1, rs, hp1, holds, len, hc1, callExec⟩ :=
        call_sound lowered (stmt_sound lowered k) corr fresh hc argsOk run1 bound1
      have corr1 := corr.keeps fresh keeps1 locals1
      have limit := (callExec next).limit_normal
      obtain ⟨d2, stops⟩ := let_stops ih bodyOk corr1 fr fresh1 (Nat.le_trans le keeps1.next) sized
        (env' := env.setMany next rs) (fr.agree fun j below => by rw [setMany_eq, if_neg (by omega)])
        (setMany_holds holds len env next) hc1 (by rw [limit]; exact bound1) (by rw [limit]; exact fails.letBody run1)
      exact ⟨_, Stops.after (callExec next) stops⟩
  · obtain ⟨d, stops⟩ := call_stops lowered returns prev corr fresh hc within argsOk g (fails.letInit done) next ty.size
    exact ⟨d, .seqFirst stops⟩


theorem stops_set {id : Nat} {value : SrcExpr} : SrcStops sp mp n (.set id value) := by
  intro hp ret scope next stmt frame base st env ok corr fr fresh le hc within fails
  simp only [SrcStmt.lower] at ok
  replace ok := guarded_some ok
  obtain ⟨stmt, ok, rfl⟩ := ok
  simp only [lowerSet] at ok
  split at ok
  · simp at ok
  rename_i b found
  simp only [lowerSetValues] at ok
  split at ok
  · simp at ok
  rename_i xs valueOk
  refine Stops.checked fun g => ?_
  obtain ⟨k, v, valueRun⟩ := lowerValue_progress corr (SrcProgram.target_toCore sp) valueOk g
  obtain ⟨v0, entry, _⟩ := corr.values b (lookup_mem found).1
  simp only [SrcStmt.toCore] at fails
  exact (fails.assign_done corr found valueRun fresh.2 (by rw [entry]; rfl) within).elim

theorem stops_setCall (lowered : lowerFuncs (sigs sp.funcs) sp.decls sp.funcs = some mp.funcs)
    (returns : funcsReturn sp.funcs = true) (prev : StmtStops sp mp n) {id callee : Nat}
    {args : List SrcExpr} : SrcStops sp mp (n + 1) (.setCall id callee args) := by
  intro hp ret scope next stmt frame base st env ok corr fr fresh le hc within fails
  simp only [SrcStmt.lower] at ok
  replace ok := guarded_some ok
  obtain ⟨stmt, ok, rfl⟩ := ok
  simp only [lowerSetCall] at ok
  split at ok
  · simp at ok
  rename_i b found
  simp only [lowerSetCallArgs] at ok
  split at ok
  · simp at ok
  rename_i es argsOk
  simp only [Option.some.injEq] at ok
  subst ok
  refine Stops.checked fun g => ?_
  simp only [SrcStmt.toCore] at fails
  have efails := fails.expression
  by_cases done : Completes hp.limit fun k => evalExpr k sp.toCore st (.call callee (args.map SrcExpr.toCore))
  · obtain ⟨k, v, st1, run1, bound1⟩ := done
    cases k with
    | zero => simp [evalExpr] at run1
    | succ k =>
      obtain ⟨fresh1, keeps1, locals1, -, -, -, -, -, -, -, -⟩ :=
        call_sound lowered (stmt_sound lowered k) corr fresh hc argsOk run1 bound1
      have corr1 := corr.keeps fresh keeps1 locals1
      obtain ⟨v1, entry1, _⟩ := corr1.values b (lookup_mem found).1
      exact (fails.assign_done corr found run1 fresh1.2 (by rw [entry1]; rfl) bound1).elim
  · exact call_stops lowered returns prev corr fresh hc within argsOk g (efails.assignValue corr found done) b.slot b.ty.size

end Statements

end Lanius.Mini
