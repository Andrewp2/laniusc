import Lanius.Mini.Progress
import Lanius.Mini.TypeSound
import Lanius.Mini.UndefTraps

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
    simp only [place, Semantics.evalExpr_of_le h (by intro h; cases h) (Nat.le_succ j)], rfl⟩) none

/-- Core's `id.index = e` on a struct local of the scope completes once `e` does. -/
theorem field_assign_progress {P : Core.Program} {scope frame st env} (corr : Corr scope frame st env)
    {id : Nat} {b : Binding} (found : lookup scope id = some b) {sid : Nat} {vs : List Value}
    (entry : st.cellEntry? (frame b.slot) = some ⟨frame b.slot, some (.structure sid vs)⟩)
    {index : Nat} {old : Value} (got : vs[index]? = some old) (views : st.i32ArrayViews = [])
    {e : Core.Expr} {k : Nat} {rv : Value} (valueRun : evalExpr k P st e = .done rv st) :
    ∃ k' st3, evalExpr k' P st (.assign .set (.field (.local id) index) e) = .done .unit st3 ∧
      st3.heap = st.heap := by
  have place : Semantics.evalPlace (k + 2) P st .address (.field (.local id) index) =
      .done { root := frame b.slot, projections := [.field index], value := some old } st := by
    simp [Semantics.evalPlace, corr.cellId, found, entry, got]
  have valueRun' := Semantics.evalExpr_of_le valueRun (by intro h; cases h) (Nat.le_add_right k 2)
  have synced := sync_ok
    (st := { st with cells := Semantics.replaceCell st.cells (frame b.slot) (.structure sid (Semantics.setValue vs index rv)) })
    views
  refine ⟨k + 3, { st with cells := Semantics.replaceCell st.cells (frame b.slot) (.structure sid (Semantics.setValue vs index rv)) },
    ?_, rfl⟩
  rw [evalExpr.eq_def]
  simp only [place, valueRun', Semantics.evalAssignValue, Semantics.assignOpBinary?,
    Semantics.writeResolvedPlaceNative, Semantics.writeResolvedPlace, entry,
    Semantics.replaceProjectedValue, got, assignCell_some entry, synced, ite_self]

end Assignments

/-! ## Matches -/

section Matches

/-- The arm Core picks either stops at its guard or has a value. -/
theorem lowerArms_progress {P : Core.Program} {mp : Program} {hp : Heap} (target : P.target = .x86_64)
    {scope frame st env} (corr : Corr scope frame st env) (fresh : st.Fresh)
    {slot dst eid : Nat} {ty : SrcType} {n : Nat} :
    ∀ (arms : List SrcArm) {variants : List (List SrcType)} {k kv : Nat} {stmt : Stmt}
      {fs : List SrcType} {vs : List Value},
      lowerArms scope slot dst ty k variants arms = some stmt → arms.length = variants.length →
      (∀ fs ∈ variants, ∀ b ∈ scope, b.slot < slot + 1 ∨ slot + 1 + sizes fs ≤ b.slot) →
      k ≤ kv → variants[kv - k]? = some fs → kv < 2 ^ 64 →
      env slot = BitVec.ofNat 64 kv → FieldsHold fs vs env (slot + 1) →
      (∃ d, Stops mp d env hp stmt n) ∨
        ∃ fuel v st', Semantics.evalMatchArms (fuel + 1) P st (.enumeration eid kv vs) (coreArms eid k arms) =
          .done v st' := by
  intro arms
  induction arms with
  | nil =>
    intro variants k kv stmt fs vs ok
    simp [lowerArms] at ok
  | cons arm rest ih =>
    intro variants k kv stmt fs vs ok len clear le found bound tag payload
    cases variants with
    | nil => simp [lowerArms] at ok
    | cons types more =>
      simp only [lowerArms, lowerArm] at ok
      split at ok
      · simp at ok
      rename_i xs valueOk
      by_cases hk : k = kv
      · subst hk
        simp only [Nat.sub_self, List.getElem?_cons_zero, Option.some.injEq] at found
        subst found
        by_cases g : (armGuard (armScope arm.binders types (slot + 1) scope) arm.value).eval env = 0
        · refine .inl ⟨0, ?_⟩
          split at ok
          · simp only [Option.some.injEq] at ok
            subst ok
            exact Stops.check fun h => absurd g h
          · split at ok
            · simp at ok
            · simp only [Option.some.injEq] at ok
              subst ok
              exact .ifTrue (by simp [Expr.eval, Word.holds, CmpOp.holdsU, tag]) (Stops.check fun h => absurd g h)
        · simp only [lowerArmValue] at valueOk
          split at valueOk
          · simp at valueOk
          rename_i s' scopeOk
          obtain ⟨frame', corr', -, -, blen⟩ := armScope_corr arm.binders scopeOk payload
            (clear _ (List.mem_cons_self ..)) corr fresh
          rw [scopeOk] at g
          obtain ⟨j, w, armRun⟩ := lowerValue_progress corr' target valueOk g
          refine .inr ⟨j, w, Semantics.restoreLocals st (st.bindLocals (arm.binders.zip vs)), ?_⟩
          simp only [coreArms, Semantics.evalMatchArms, Semantics.matchPattern, beq_self_eq_true, Bool.and_self,
            ↓reduceIte, matchBinds _ _ blen, armRun, Semantics.restoreOutcomeLocals]
      · have hne : (k == kv) = false := by simpa using hk
        have found' : more[kv - (k + 1)]? = some fs := by
          rw [show kv - k = kv - (k + 1) + 1 by omega] at found
          simpa using found
        split at ok
        · have := (List.getElem?_eq_some_iff.mp found').1
          simp only [List.length_cons, List.length_nil] at len
          omega
        · split at ok
          · simp at ok
          rename_i o othersOk
          simp only [Option.some.injEq] at ok
          subst ok
          have differ : BitVec.ofNat 64 kv ≠ BitVec.ofNat 64 k := ofNat_ne bound (by omega) (Ne.symm hk)
          rcases ih othersOk (by simpa using len) (fun fs mem => clear fs (List.mem_cons_of_mem _ mem)) (by omega)
            found' bound tag payload with ⟨d, stops⟩ | ⟨j, w, st', armsRun⟩
          · exact .inl ⟨d, .ifFalse (by simp [Expr.eval, Word.holds, CmpOp.holdsU, tag, differ]) stops⟩
          · refine .inr ⟨j + 1, w, st', ?_⟩
            simp only [coreArms, Semantics.evalMatchArms, Semantics.matchPattern, beq_self_eq_true, Bool.true_and,
              hne, Bool.false_eq_true, ↓reduceIte] at armsRun ⊢
            exact armsRun

end Matches

/-! ## Raw memory -/

section RawMemory

theorem loadByte_undefined {h : Memory.Heap} {p o : Nat} {r : Lanius.Trap} (bad : h.loadByte p o = .error r) :
    undefinedTrap r = true := by
  simp only [Memory.Heap.loadByte] at bad
  split at bad
  · split at bad
    · simp only [Except.error.injEq] at bad; subst bad; rfl
    · split at bad <;> (simp only [Except.error.injEq] at bad; subst bad; rfl)
    · simp only [Except.error.injEq] at bad; subst bad; rfl
  · split at bad
    · simp only [Except.error.injEq] at bad; subst bad; rfl
    · simp at bad

theorem storeByte_undefined {h : Memory.Heap} {p o : Nat} {v : UInt8} {r : Lanius.Trap}
    (bad : h.storeByte p o v = .error r) : undefinedTrap r = true := by
  simp only [Memory.Heap.storeByte] at bad
  split at bad
  · split at bad
    · simp only [Except.error.injEq] at bad; subst bad; rfl
    · split at bad <;> (simp only [Except.error.injEq] at bad; subst bad; rfl)
    · simp only [Except.error.injEq] at bad; subst bad; rfl
  · simp at bad

theorem deallocate_undefined {h : Memory.Heap} {p s a : Nat} {r : Lanius.Trap}
    (bad : h.deallocate p s a = .error r) : undefinedTrap r = true := by
  simp only [Memory.Heap.deallocate] at bad
  split at bad
  · simp at bad
  split at bad
  · simp only [Except.error.injEq] at bad; subst bad; rfl
  split at bad
  · simp only [Except.error.injEq] at bad; subst bad; rfl
  split at bad
  · simp only [Except.error.injEq] at bad; subst bad; rfl
  split at bad
  · simp only [Except.error.injEq] at bad; subst bad; rfl
  · simp at bad

/-- Expressions that each complete without changing the state complete together. -/
theorem exprs_cons_done {P : Core.Program} {st : State} {e : Core.Expr} {es : List Core.Expr} {f1 f2 : Nat}
    {v : Value} {vs : List Value} (head : evalExpr f1 P st e = .done v st)
    (rest : Semantics.evalExprs f2 P st es = .done vs st) :
    Semantics.evalExprs (max f1 f2 + 1) P st (e :: es) = .done (v :: vs) st := by
  have head' := Semantics.evalExpr_of_le head (by intro h; cases h) (Nat.le_max_left f1 f2)
  have rest' := (rest ▸ Semantics.evalExprs_refines (program := P) (state := st) (expressions := es)
    (Nat.le_max_right f1 f2)).completed (by intro h; cases h)
  simp only [Semantics.evalExprs, head', rest']

theorem exprs_nil_done {P : Core.Program} {st : State} : Semantics.evalExprs 1 P st [] = .done [] st := by
  simp only [Semantics.evalExprs]

theorem checkRange_undefined {h : Memory.Heap} {p size a : Nat} {r : Lanius.Trap}
    (bad : h.checkRange p size a = .error r) : undefinedTrap r = true := by
  simp only [Memory.Heap.checkRange] at bad
  split at bad
  · simp only [Except.error.injEq] at bad; subst bad; rfl
  split at bad
  · simp only [Except.error.injEq] at bad; subst bad; rfl
  split at bad
  · simp only [Except.error.injEq] at bad; subst bad; rfl
  · simp at bad

/-- Core's raw slice constructors complete or trap undefined. -/
theorem mapRawI32Slice_cases {st : State} {a : Nat} {n : Int} {out : Semantics.Outcome Value}
    (run : Semantics.mapRawI32Slice st a n = out) :
    (∃ v st1, out = .done v st1) ∨ ∃ r, out = .trapped r st ∧ undefinedTrap r = true := by
  unfold Semantics.mapRawI32Slice at run
  split at run
  · exact .inr ⟨_, run.symm, rfl⟩
  split at run
  · exact .inl ⟨_, _, run.symm⟩
  dsimp only at run
  split at run
  · rename_i reason bad
    exact .inr ⟨_, run.symm, checkRange_undefined bad⟩
  · exact .inl ⟨_, _, run.symm⟩

theorem mapRawNominalSlice_cases {P : Core.Program} {st : State} {element : Core.Ty} {a : Nat} {n : Int}
    {out : Semantics.Outcome Value} (run : Semantics.mapRawNominalSlice P st element a n = out) :
    (∃ v st1, out = .done v st1) ∨ ∃ r, out = .trapped r st ∧ undefinedTrap r = true := by
  unfold Semantics.mapRawNominalSlice at run
  repeat' (first | split at run | (dsimp only at run; split at run))
  all_goals first
    | exact .inl ⟨_, _, run.symm⟩
    | exact .inr ⟨_, run.symm, rfl⟩
    | (rename_i bad; exact .inr ⟨_, run.symm, checkRange_undefined bad⟩)

/-- Core's `slice_from_raw_parts` of evaluated operands completes or traps undefined. -/
theorem sliceFrom_cases {P : Core.Program} {k : Nat} {st : State} {element : SrcType}
    (kind : element = .i32 ∨ (∃ sid fields, element = .struct sid fields) ∨
      ∃ eid variants, element = .enum eid variants) {p l : Core.Expr} {a : Nat} {n : Int}
    (pRun : evalExpr k P st p = .done (.pointer a) st) (lRun : evalExpr k P st l = .done (.signed .i32 n) st) :
    (∃ v st1, evalExpr (k + 1) P st (element.sliceFrom p l) = .done v st1) ∨
      ∃ r, evalExpr (k + 1) P st (element.sliceFrom p l) = .trapped r st ∧ undefinedTrap r = true := by
  rcases kind with rfl | ⟨sid, fields, rfl⟩ | ⟨eid, variants, rfl⟩
  · simp only [SrcType.sliceFrom, evalExpr, pRun, lRun]
    exact mapRawI32Slice_cases rfl
  · simp only [SrcType.sliceFrom, evalExpr, pRun, lRun]
    exact mapRawNominalSlice_cases rfl
  · simp only [SrcType.sliceFrom, evalExpr, pRun, lRun]
    exact mapRawNominalSlice_cases rfl

end RawMemory

/-! ## Indexing -/

section Indexing

theorem rawSliceElementAddress_undef (P : Core.Program) (element : Core.Ty) (a i : Nat) :
    UndefErr (Semantics.rawSliceElementAddress? P element a i) := by
  have nofind : True := trivial
  simp only [Semantics.rawSliceElementAddress?]
  repeat' undef_step

theorem readRawSliceIndex_undef {P : Core.Program} {st : State} {element : Core.Ty} {a len pos : Nat}
    (lt : pos < len) : UndefErr (Semantics.readRawSliceIndex P st element a len pos) := by
  simp only [Semantics.readRawSliceIndex, if_neg (Nat.not_le.mpr lt)]
  exact UndefErr.bind (rawSliceElementAddress_undef P element a pos) fun _ => readNativeValue_undef _ _ _ _ _

/-- Core's read of `slice[idx]` from a raw slice local, the index in bounds:
the element, or an undefined trap. -/
theorem index_outcome {P : Core.Program} {k : Nat} {st : State} {slice : Nat} {idx : Core.Expr}
    {element : Core.Ty} {address length : Nat} {iv : Value} {pos : Nat}
    (base : evalExpr (k + 1) P st (.local slice) = .done (.rawSlice element address length) st)
    (idxRun : evalExpr (k + 1) P st idx = .done iv st) (posOk : Semantics.integerIndex iv = .ok pos)
    (lt : pos < length) :
    (∃ v, evalExpr (k + 2) P st (.index (.local slice) idx) = .done v st ∧
      Semantics.readRawSliceIndex P st element address length pos = .ok v) ∨
    ∃ r, evalExpr (k + 2) P st (.index (.local slice) idx) = .trapped r st ∧ undefinedTrap r = true := by
  have eq : evalExpr (k + 2) P st (.index (.local slice) idx) =
      match Semantics.readRawSliceIndex P st element address length pos with
      | .ok value => .done value st
      | .error reason => .trapped reason st := by
    rw [evalExpr.eq_def]
    simp only [base, idxRun, posOk]
    cases Semantics.readRawSliceIndex P st element address length pos <;> rfl
  rw [eq]
  cases read : Semantics.readRawSliceIndex P st element address length pos with
  | ok v => exact .inl ⟨v, rfl, rfl⟩
  | error r => exact .inr ⟨r, rfl, readRawSliceIndex_undef lt r read⟩

/-- A guard-checked index is below the slice's length. -/
theorem indexGuard_ne {scope : List Binding} {slice : Nat} {b : Binding} (found : lookup scope slice = some b)
    {index : SrcExpr} {x : Expr} (ok : lowerIndex scope index = some x) {env : Env}
    (g : (indexGuard scope slice index).eval env ≠ 0) : (x.eval env).toNat < (env (b.slot + 1)).toNat := by
  simp only [indexGuard, found, ok, boundsGuard, Expr.eval, Word.holds, CmpOp.holdsU, BitVec.ult] at g
  by_cases h : (x.eval env).toNat < (env (b.slot + 1)).toNat
  · exact h
  · simp [h] at g

/-- An `i32` or `usize` index below `2 ^ 31` is the position it holds. -/
theorem index_ok {t : Typed} {iv : Value} {x : BitVec 64}
    (kind : (t.ty.isI32 || t.ty.isUint .usize) = true) (holds : t.ty.Holds iv x) (small : x.toNat < 2 ^ 31) :
    Semantics.integerIndex iv = .ok x.toNat := by
  cases hty : t.ty with
  | i32 =>
    rw [hty] at holds
    obtain ⟨rfl, bits⟩ := holds
    have hx : x.toNat = (low x).toNat :=
      calc x.toNat = (widen (low x)).toNat := by rw [← bits]
        _ = (low x).toNat := by
          show (BitVec.setWidth 64 (low x)).toNat = (low x).toNat
          rw [BitVec.toNat_setWidth]
          exact Nat.mod_eq_of_lt (Nat.lt_trans (low x).isLt (by decide))
    rw [BitVec.toInt_eq_toNat_cond, if_pos (by omega)]
    simp only [Semantics.integerIndex]
    rw [if_neg (by omega), Int.toNat_natCast]
    exact congrArg _ hx.symm
  | uint k =>
    rw [hty] at kind holds
    simp only [SrcType.isI32, SrcType.isUint, Bool.false_or, decide_eq_true_eq] at kind
    cases UintTy.eq_of_code kind
    obtain ⟨rfl, -⟩ := holds
    simp only [Semantics.integerIndex]
  | bool | struct | enum | ptr | slice | unit | isize | char | float | sint => rw [hty] at kind; simp [SrcType.isI32, SrcType.isUint] at kind

/-- Statements one after another, then `body`. -/
def chain : List Stmt → Stmt → Stmt
  | [], body => body
  | p :: ps, body => .seq p (chain ps body)

theorem chain_append : ∀ (ps qs : List Stmt) (body : Stmt), chain ps (chain qs body) = chain (ps ++ qs) body
  | [], _, _ => rfl
  | p :: ps, qs, body => by simp only [chain, List.cons_append, chain_append ps qs body]

/-- A chain that runs to its end stops when what follows does. -/
theorem Stops.chain {prog : Program} {d : Nat} :
    ∀ (ps : List Stmt) {env env' : Env} {hp hp' : Heap} {body : Stmt} {n : Nat},
      Exec prog d env hp (Lanius.Mini.chain ps .skip) (.normal env' hp') → Stops prog d env' hp' body n →
      Stops prog d env hp (Lanius.Mini.chain ps body) n
  | [], _, _, _, _, _, _, exec, stops => by
    cases exec
    exact stops
  | p :: ps, _, _, _, _, _, _, exec, stops => by
    cases exec with
    | seq first rest => exact .seqSecond first (Stops.chain ps rest stops)

mutual
theorem loadType_chain : ∀ (t : SrcType) (target : Nat) (base : Expr) (offset : Nat),
    ∃ ps, ∀ body, loadType t target base offset body = chain ps body
  | .i32, _, _, _ => ⟨[_], fun _ => rfl⟩
  | .bool, _, _, _ => ⟨[_], fun _ => rfl⟩
  | .uint _, _, _, _ => ⟨[_], fun _ => rfl⟩
  | .ptr, _, _, _ => ⟨[_], fun _ => rfl⟩
  | .isize, _, _, _ => ⟨[_], fun _ => rfl⟩
  | .char, _, _, _ => ⟨[_], fun _ => rfl⟩
  | .float _, _, _, _ => ⟨[_], fun _ => rfl⟩
  | .sint _, _, _, _ => ⟨[_], fun _ => rfl⟩
  | .slice _, _, _, _ => ⟨[_], fun _ => rfl⟩
  | .unit, _, _, _ => ⟨[_], fun _ => rfl⟩
  | .enum _ _, _, _, _ => ⟨[_, _], fun _ => rfl⟩
  | .struct _ fields, target, base, offset => by
    obtain ⟨ps, eq⟩ := loadTypes_chain fields target base offset
    exact ⟨ps, fun body => by simp only [loadType]; exact eq body⟩

theorem loadTypes_chain : ∀ (fs : List SrcType) (target : Nat) (base : Expr) (offset : Nat),
    ∃ ps, ∀ body, loadTypes fs target base offset body = chain ps body
  | [], _, _, _ => ⟨[], fun _ => rfl⟩
  | f :: rest, target, base, offset => by
    obtain ⟨ps, eq⟩ := loadType_chain f target base offset
    obtain ⟨qs, eq'⟩ := loadTypes_chain rest (target + f.size) base (offset + 8 * f.size)
    exact ⟨ps ++ qs, fun body => by simp only [loadTypes]; rw [eq', eq, chain_append]⟩
end

/-- Core's `slice[idx] = e` on a raw slice local, the index in bounds and no
array views: it completes keeping the heap's cursor, or traps undefined. -/
theorem setIndex_outcome {P : Core.Program} {k : Nat} {st : State} {slice : Nat} {idx e : Core.Expr}
    {element : Core.Ty} {address length root : Nat} {iv right : Value} {pos : Nat}
    (views : st.i32ArrayViews = [])
    (base : Semantics.evalPlace (k + 1) P st .read (.local slice) =
      .done { root, projections := [], value := some (.rawSlice element address length) } st)
    (idxRun : evalExpr (k + 1) P st idx = .done iv st) (posOk : Semantics.integerIndex iv = .ok pos)
    (lt : pos < length) (eRun : evalExpr (k + 2) P st e = .done right st) :
    (∃ st', evalExpr (k + 3) P st (.assign .set (.index (.local slice) idx) e) = .done .unit st' ∧
      st'.heap.nextAddress = st.heap.nextAddress) ∨
    ∃ r, evalExpr (k + 3) P st (.assign .set (.index (.local slice) idx) e) = .trapped r st ∧
      undefinedTrap r = true := by
  generalize hout : evalExpr (k + 3) P st (.assign .set (.index (.local slice) idx) e) = out
  rw [evalExpr] at hout
  rw [Semantics.evalPlace] at hout
  rw [base] at hout
  simp only [idxRun, posOk, lt, if_true, decide_true] at hout
  cases located : Semantics.rawSliceElementAddress? P element address pos with
  | error r =>
    simp only [located] at hout
    exact .inr ⟨r, hout.symm, rawSliceElementAddress_undef P element address pos r located⟩
  | ok at_ =>
    simp only [located, eRun, Semantics.evalAssignValue, Semantics.assignOpBinary?,
      Semantics.writeResolvedPlaceNative] at hout
    cases stored : Semantics.writeNativeValue NativeLayout.maxDepth P st st.heap element at_ right with
    | error r =>
      simp only [stored, bind, Except.bind] at hout
      exact .inr ⟨r, hout.symm, writeNativeValue_undef _ _ _ _ _ _ _ views r stored⟩
    | ok heap =>
      simp only [stored, bind, Except.bind, pure, Except.pure, Semantics.syncI32ViewsFromHeap, views,
        Semantics.syncI32ViewsFromHeapFrom, ite_self] at hout
      exact .inl ⟨_, hout.symm, writeNativeValue_next _ stored⟩

end Indexing

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


theorem stops_setField {id index : Nat} {value : SrcExpr} : SrcStops sp mp n (.setField id index value) := by
  intro hp ret scope next stmt frame base st env ok corr fr fresh le hc within fails
  simp only [SrcStmt.lower] at ok
  replace ok := guarded_some ok
  obtain ⟨stmt, ok, rfl⟩ := ok
  simp only [lowerSetField] at ok
  split at ok
  · simp at ok
  rename_i b found
  simp only [lowerSetFieldOf] at ok
  split at ok
  · simp at ok
  · simp at ok
  · simp at ok
  case h_5 => simp at ok
  case h_6 => simp at ok
  case h_7 => simp at ok
  case h_8 => simp at ok
  case h_9 => simp at ok
  case h_10 => simp at ok
  case h_11 => simp at ok
  case h_12 => simp at ok
  rename_i sid types hty
  simp only [lowerSetFieldAt] at ok
  split at ok
  · simp at ok
  rename_i f fieldFound
  split at ok
  case isFalse => simp at ok
  rename_i scalar
  simp only [lowerSetValue] at ok
  split at ok
  · simp at ok
  rename_i x valueOk
  have bmem := (lookup_mem found).1
  obtain ⟨v0, entry, holds0⟩ := corr.values b bmem
  rw [hty] at holds0
  cases holds0 with
  | @struct _ _ vs _ _ fieldsHold =>
  obtain ⟨old, got, _⟩ := fieldsHold.get fieldFound
  refine Stops.checked fun g => ?_
  obtain ⟨k, w, valueRun⟩ := lowerAs_progress corr (SrcProgram.target_toCore sp) valueOk g
  obtain ⟨k', st3, run, heap⟩ := field_assign_progress corr found entry got fresh.2 valueRun
  simp only [SrcStmt.toCore] at fails
  exact (fails.not_done (k := k' + 1) (c := .next) (st' := st3) (by simp only [execStmt, run])
    (by rw [heap]; exact within)).elim


theorem stops_letStruct {id : Nat} {ty : SrcType} {fields : List SrcExpr} {body : SrcStmt}
    (ih : SrcStops sp mp n body) : SrcStops sp mp n (.letStruct id ty fields body) := by
  intro hp ret scope next stmt frame base st env ok corr fr fresh le hc within fails
  simp only [SrcStmt.lower] at ok
  replace ok := guarded_some ok
  obtain ⟨stmt, ok, rfl⟩ := ok
  simp only [lowerLet] at ok
  split at ok
  · simp at ok
  rename_i xs literalOk
  split at ok
  · simp at ok
  rename_i bstmt bodyOk
  simp only [Option.some.injEq] at ok
  subst ok
  cases ty with
  | i32 => simp [lowerLiteral] at literalOk
  | bool => simp [lowerLiteral] at literalOk
  | uint => simp [lowerLiteral] at literalOk
  | enum => simp [lowerLiteral] at literalOk
  | slice => simp [lowerLiteral] at literalOk
  | unit => simp [lowerLiteral] at literalOk
  | isize => simp [lowerLiteral] at literalOk
  | char => simp [lowerLiteral] at literalOk
  | float => simp [lowerLiteral] at literalOk
  | sint => simp [lowerLiteral] at literalOk
  | ptr => simp [lowerLiteral] at literalOk
  | struct sid types =>
    simp only [lowerLiteral, lowerStructFields] at literalOk
    split at literalOk
    · simp at literalOk
    rename_i nonempty
    refine Stops.checked fun g => ?_
    obtain ⟨k, vs, fieldsRun⟩ := lowerArgs_progress corr (SrcProgram.target_toCore sp) literalOk g
    obtain ⟨-, fieldsHold, len, shapes⟩ := lowerArgs_sound corr (SrcProgram.target_toCore sp) literalOk fieldsRun
    have valueRun : evalExpr (k + 1) sp.toCore st (.structValue sid (fields.map SrcExpr.toCore)) =
        .done (.structure sid vs) st := by
      simp only [evalExpr, fieldsRun]
    have flat : FlatValue (.struct sid types) (.structure sid vs) env xs :=
      ⟨by simp [SrcType.size, len], .struct fieldsHold⟩
    have insens : Insens xs next := Insens.below fun x mem => by
      obtain ⟨ys, shape, inYs⟩ := shapes x mem
      exact shape.below fr.slots x inYs
    simp only [SrcStmt.toCore, SrcType.typeId] at fails
    obtain ⟨d, stops⟩ := let_stops ih bodyOk corr fr fresh le (by simp only [SrcType.size]; omega)
      (fr.agree fun j below => setFrom_outside xs next env j (.inl below)) (flat.store insens) hc within
      (fails.letBody valueRun)
    exact ⟨d, Stops.assignFrom xs next stops⟩

theorem stops_letEnum {id : Nat} {ty : SrcType} {variant : Nat} {payload : List SrcExpr} {body : SrcStmt}
    (ih : SrcStops sp mp n body) : SrcStops sp mp n (.letEnum id ty variant payload body) := by
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
  cases ty with
  | i32 => simp [lowerEnumValue] at valueOk
  | bool => simp [lowerEnumValue] at valueOk
  | uint => simp [lowerEnumValue] at valueOk
  | struct => simp [lowerEnumValue] at valueOk
  | ptr => simp [lowerEnumValue] at valueOk
  | slice => simp [lowerEnumValue] at valueOk
  | unit => simp [lowerEnumValue] at valueOk
  | isize => simp [lowerEnumValue] at valueOk
  | char => simp [lowerEnumValue] at valueOk
  | float => simp [lowerEnumValue] at valueOk
  | sint => simp [lowerEnumValue] at valueOk
  | enum eid variants =>
    simp only [lowerEnumValue, lowerTagged] at valueOk
    split at valueOk
    case isFalse => simp at valueOk
    simp only [lowerVariant] at valueOk
    split at valueOk
    · simp at valueOk
    rename_i fs found
    simp only [lowerTag] at valueOk
    split at valueOk
    · simp at valueOk
    rename_i fxs fieldsOk
    simp only [Option.some.injEq] at valueOk
    subst valueOk
    refine Stops.checked fun g => ?_
    obtain ⟨k, vs, fieldsRun⟩ := lowerArgs_progress corr (SrcProgram.target_toCore sp) fieldsOk g
    obtain ⟨-, fieldsHold, len, shapes⟩ := lowerArgs_sound corr (SrcProgram.target_toCore sp) fieldsOk fieldsRun
    have valueRun : evalExpr (k + 1) sp.toCore st (.enumValue eid variant (payload.map SrcExpr.toCore)) =
        .done (.enumeration eid variant vs) st := by
      simp only [evalExpr, fieldsRun]
    have insens : Insens (.lit (BitVec.ofNat 64 variant) :: fxs) next := Insens.below fun x mem => by
      simp only [List.mem_cons] at mem
      rcases mem with rfl | mem
      · trivial
      · obtain ⟨ys, shape, inYs⟩ := shapes x mem
        exact shape.below fr.slots x inYs
    have holds : (SrcType.enum eid variants).HoldsAt (.enumeration eid variant vs)
        (env.setFrom next (.lit (BitVec.ofNat 64 variant) :: fxs)) next := by
      refine .enum found ?_ (fieldsHold.congr fun i below => ?_)
      · simpa [Expr.eval] using setFrom_value _ next env insens 0 _ rfl
      · have : i < fxs.length := by rw [len]; exact below
        obtain ⟨x, xFound⟩ : ∃ x, fxs[i]? = some x := ⟨fxs[i], by simp [this]⟩
        rw [show next + 1 + i = next + (i + 1) by omega,
          setFrom_value _ next env insens (i + 1) x (by simpa using xFound), Nat.zero_add,
          entry_evalAll env fxs i x xFound]
    simp only [SrcStmt.toCore, SrcType.typeId] at fails
    obtain ⟨d, stops⟩ := let_stops ih bodyOk corr fr fresh le (by simp only [SrcType.size]; omega)
      (fr.agree fun j below => setFrom_outside _ next env j (.inl below)) holds hc within (fails.letBody valueRun)
    exact ⟨d, Stops.assignFrom _ next stops⟩


theorem stops_letMatch {id : Nat} {ty : SrcType} {scrutinee enumId : Nat} {arms : List SrcArm} {body : SrcStmt}
    (ih : SrcStops sp mp n body) : SrcStops sp mp n (.letMatch id ty scrutinee enumId arms body) := by
  intro hp ret scope next stmt frame base st env ok corr fr fresh le hc within fails
  simp only [SrcStmt.lower, lowerThen] at ok
  split at ok
  · simp at ok
  rename_i mstmt matchOk
  split at ok
  · simp at ok
  rename_i bstmt bodyOk
  simp only [Option.some.injEq] at ok
  subst ok
  simp only [lowerMatch] at matchOk
  split at matchOk
  · simp at matchOk
  rename_i b found
  simp only [lowerMatchOn] at matchOk
  split at matchOk
  · simp at matchOk
  · simp at matchOk
  · simp at matchOk
  · simp at matchOk
  case h_6 => simp at matchOk
  case h_7 => simp at matchOk
  case h_8 => simp at matchOk
  case h_9 => simp at matchOk
  case h_10 => simp at matchOk
  case h_11 => simp at matchOk
  case h_12 => simp at matchOk
  rename_i eid variants hty
  simp only [lowerMatchArms] at matchOk
  split at matchOk
  case isFalse => simp at matchOk
  rename_i cond
  simp only [Bool.and_eq_true, decide_eq_true_eq] at cond
  obtain ⟨⟨⟨rfl, sized⟩, len⟩, few⟩ := cond
  have bmem := (lookup_mem found).1
  have room : ∀ fs ∈ variants, b.slot + 1 + sizes fs ≤ next := by
    intro fs mem
    have bound := sizes_le_maxSize_of_mem mem
    have := fr.slots b bmem
    rw [hty] at this
    simp only [SrcType.size] at this
    omega
  have clear : ∀ fs ∈ variants, ∀ b' ∈ scope, b'.slot < b.slot + 1 ∨ b.slot + 1 + sizes fs ≤ b'.slot := by
    intro fs mem b' mem'
    have bound := sizes_le_maxSize_of_mem mem
    by_cases same : b' = b
    · subst same
      omega
    · rcases fr.apart b' mem' b bmem same with h | h
      · have := fr.sized b' mem'
        omega
      · rw [hty] at h
        simp only [SrcType.size] at h
        omega
  obtain ⟨w, localRun0, holdsW⟩ := corr.local found 0 sp.toCore
  rw [hty] at holdsW
  cases holdsW with
  | @enum _ _ kv fs vs _ _ fsFound tag payload =>
  have kvLt : kv < variants.length := (List.getElem?_eq_some_iff.mp fsFound).1
  have kvBound : kv < 2 ^ 64 := Nat.lt_trans kvLt (by omega)
  rcases lowerArms_progress (mp := mp) (hp := hp) (n := n) (eid := eid) (SrcProgram.target_toCore sp) corr fresh arms
      matchOk len clear (Nat.zero_le _) (by simpa using fsFound) kvBound tag payload with
    ⟨d, stops⟩ | ⟨f, v, st1, armsRun⟩
  · exact ⟨d, .seqFirst stops⟩
  · obtain ⟨w', localRun, -⟩ := corr.local found f sp.toCore
    have same : w' = .enumeration eid kv vs := by
      have := Semantics.evalExpr_of_le localRun0 (by intro h; cases h) (Nat.le_add_left 1 f)
      rw [localRun] at this
      simp only [Semantics.Outcome.done.injEq] at this
      exact this.1
    subst same
    have matchRun : evalExpr (f + 2) sp.toCore st (.matchValue (.local scrutinee) (coreArms eid 0 arms)) =
        .done v st1 := by
      have lr := localRun
      simp only [evalExpr] at lr ⊢
      simp only [lr]
      exact armsRun
    obtain ⟨fresh1, keeps1, locals1, xs, flat, insens, mexec⟩ :=
      lowerArms_sound (mp := mp) (hp := hp) (SrcProgram.target_toCore sp) corr fresh fr.slots arms matchOk len
        clear room (Nat.zero_le _) (by simpa using fsFound) kvBound tag payload armsRun
    have corr1 := corr.keeps fresh keeps1 locals1
    have heap1 := (matchArms_same arms eid 0 armsRun).1
    have hc1 : HeapCorr st1.heap hp := by rw [heap1]; exact hc
    simp only [SrcStmt.toCore] at fails
    obtain ⟨d, stops⟩ := let_stops ih bodyOk corr1 fr fresh1 (Nat.le_trans le keeps1.next) sized
      (env' := env.setFrom next xs) (fr.agree fun j below => setFrom_outside xs next env j (.inl below))
      (flat.store insens) hc1 (by rw [heap1]; exact within) (fails.letBody matchRun)
    exact ⟨_, Stops.after (mexec 0) stops⟩


theorem stops_letAlloc {id shift : Nat} {size : SrcExpr} {body : SrcStmt} (ih : SrcStops sp mp n body) :
    SrcStops sp mp n (.letAlloc id size shift body) := by
  intro hp ret scope next stmt frame base st env ok corr fr fresh le hc within fails
  simp only [SrcStmt.lower] at ok
  replace ok := guarded_some ok
  obtain ⟨stmt, ok, rfl⟩ := ok
  simp only [lowerAlloc] at ok
  split at ok
  case isFalse => simp at ok
  split at ok
  · simp at ok
  rename_i x sizeOk
  split at ok
  · simp at ok
  rename_i bstmt bodyOk
  simp only [Option.some.injEq] at ok
  subst ok
  refine Stops.checked fun g => ?_
  obtain ⟨k, w, sizeRun⟩ := lowerAs_progress corr (SrcProgram.target_toCore sp) sizeOk g
  obtain ⟨-, holdsN, -⟩ := lowerAs_sound corr (SrcProgram.target_toCore sp) sizeOk sizeRun
  simp only [UintTy.toCore] at holdsN
  subst holdsN
  simp only [SrcStmt.toCore] at fails
  cases alloc : st.heap.allocate (x.eval env).toNat (2 ^ shift) with
  | exhausted heap' => exact (hc.allocated _ _ alloc).elim
  | trapped r heap' => exact (hc.untrapped _ _ alloc).elim
  | allocated p heap' =>
    obtain ⟨rfl, grown, hc'⟩ := hc.allocate alloc
    have valueRun : evalExpr (k + 2) sp.toCore st
        (.alloc size.toCore (.value (.unsigned .usize (2 ^ shift)))) =
          .done (.pointer (alignUp hp.cursor shift)) { st with heap := heap' } := by
      have alignRun : evalExpr (k + 1) sp.toCore st (.value (.unsigned .usize (2 ^ shift))) =
          .done (.unsigned .usize (2 ^ shift)) st := by simp only [evalExpr]
      rw [evalExpr.eq_def]
      simp only [value_after sizeRun (Nat.le_succ k), alignRun, alloc]
    by_cases fits : heap'.nextAddress ≤ hp.limit
    · have room : alignUp hp.cursor shift + ((atLeastOne x).eval env).toNat ≤ hp.limit := by
        rw [atLeastOne_eval]; rw [grown] at fits; exact fits
      have small := hc.small
      obtain ⟨d, stops⟩ := let_stops ih (ty := .ptr) (st := { st with heap := heap' })
        (v := .pointer (alignUp hp.cursor shift))
        (env' := env.set next (BitVec.ofNat 64 (alignUp hp.cursor shift)))
        (hp := { hp with cursor := alignUp hp.cursor shift + max (x.eval env).toNat 1 }) bodyOk
        (corr.cells_congr rfl fun _ _ => rfl) fr fresh le Nat.one_pos
        (fr.agree fun j below => by simp only [Env.set]; rw [if_neg (by omega)])
        (.ptr (by
          simp only [SrcType.Holds, Env.set, if_pos, Value.pointer.injEq, BitVec.toNat_ofNat]
          exact (Nat.mod_eq_of_lt (by omega)).symm))
        hc' fits (fails.letBody valueRun)
      have step := Exec.alloc (prog := mp) (depth := 0) (env := env) (target := next) room
      rw [atLeastOne_eval] at step
      exact ⟨_, Stops.after step stops⟩
    · refine ⟨0, .seqFirst (.alloc (by rw [hc.cursor]; exact within) ?_)⟩
      rw [atLeastOne_eval]
      rw [grown] at fits
      exact Nat.lt_of_not_le fits


theorem stops_letLoad {id : Nat} {pointer offset : SrcExpr} {body : SrcStmt} (ih : SrcStops sp mp n body) :
    SrcStops sp mp n (.letLoad id pointer offset body) := by
  intro hp ret scope next stmt frame base st env ok corr fr fresh le hc within fails
  simp only [SrcStmt.lower] at ok
  replace ok := guarded_some ok
  obtain ⟨stmt, ok, rfl⟩ := ok
  cases pOk : lowerAs scope pointer .ptr with
  | none => simp [pOk, lowerAddress, lowerLoad] at ok
  | some xp =>
  cases oOk : lowerAs scope offset (.uint .usize) with
  | none => simp [pOk, oOk, lowerAddress, lowerLoad] at ok
  | some xo =>
  cases bodyOk : body.lower (sigs sp.funcs) sp.decls ret (⟨id, next, .uint .uint8⟩ :: scope) (next + 1) with
  | none => simp [pOk, oOk, bodyOk, lowerAddress, lowerLoad] at ok
  | some bstmt =>
  simp only [pOk, oOk, bodyOk, lowerAddress, lowerLoad, Option.some.injEq] at ok
  subst ok
  refine Stops.checked fun g => ?_
  obtain ⟨gp, go⟩ := guardAnd_ne g
  obtain ⟨fp, pv, pRun⟩ := lowerAs_progress corr (SrcProgram.target_toCore sp) pOk gp
  obtain ⟨fo, ov, oRun⟩ := lowerAs_progress corr (SrcProgram.target_toCore sp) oOk go
  obtain ⟨-, hpv⟩ := lowerAs_sound corr (SrcProgram.target_toCore sp) pOk pRun
  obtain ⟨-, hov, -⟩ := lowerAs_sound corr (SrcProgram.target_toCore sp) oOk oRun
  simp only [SrcType.Holds] at hpv
  simp only [UintTy.toCore] at hov
  subst hpv hov
  have argsRun := exprs_cons_done pRun (exprs_cons_done oRun exprs_nil_done)
  simp only [SrcStmt.toCore] at fails
  cases loaded : st.heap.loadByte (xp.eval env).toNat (xo.eval env).toNat with
  | error r =>
    have := fails (max fp (max fo 1 + 1) + 1 + 2)
    simp only [execStmt] at this
    rw [evalExpr.eq_def] at this
    simp only [argsRun, sync_ok fresh.2, loaded, Failing] at this
    exact (trap_within this (loadByte_undefined loaded) within).elim
  | ok b =>
    have valueRun : evalExpr (max fp (max fo 1 + 1) + 1 + 1) sp.toCore st (.loadByte pointer.toCore offset.toCore) =
        .done (.unsigned .u8 b.toNat) st := by
      rw [evalExpr.eq_def]
      simp only [argsRun, sync_ok fresh.2, loaded]
    obtain ⟨byte, inside⟩ := hc.load loaded
    have tail := within
    have small := hc.small
    obtain ⟨-, -, -, address⟩ := address_sound (rest := []) (SrcProgram.target_toCore sp) corr pOk oOk argsRun
      (by addr_omega)
    have room : ((Expr.binary Word.u64 BinOp.add xp xo).eval env).toNat < hp.limit := by
      rw [address]; addr_omega
    obtain ⟨d, stops⟩ := let_stops ih (ty := .uint .uint8) (v := .unsigned .u8 b.toNat)
        (env' := env.set next (BitVec.ofNat 64 (hp.bytes
          ((Expr.binary Word.u64 BinOp.add xp xo).eval env).toNat).toNat))
        bodyOk corr fr fresh le Nat.one_pos
        (fr.agree fun j below => by simp only [Env.set]; rw [if_neg (by omega)])
        (.uint (by
          simp only [SrcType.Holds, Env.set, if_pos, address, byte, BitVec.toNat_ofNat, UintTy.toCore,
            UintTy.width]
          have := b.toNat_lt
          exact ⟨by rw [Nat.mod_eq_of_lt (by omega)], by rw [Nat.mod_eq_of_lt (by omega)]; exact this⟩))
        hc within (fails.letBody valueRun)
    exact ⟨_, Stops.after (.loadByte (depth := 0) room) stops⟩

theorem stops_setByte {pointer offset value : SrcExpr} : SrcStops sp mp n (.setByte pointer offset value) := by
  intro hp ret scope next stmt frame base st env ok corr fr fresh le hc within fails
  simp only [SrcStmt.lower] at ok
  replace ok := guarded_some ok
  obtain ⟨stmt, ok, rfl⟩ := ok
  cases pOk : lowerAs scope pointer .ptr with
  | none => simp [pOk, lowerAddress, lowerStore] at ok
  | some xp =>
  cases oOk : lowerAs scope offset (.uint .usize) with
  | none => simp [pOk, oOk, lowerAddress, lowerStore] at ok
  | some xo =>
  cases vOk : lowerAs scope value (.uint .uint8) with
  | none => simp [pOk, oOk, vOk, lowerAddress, lowerStore] at ok
  | some xv =>
  refine Stops.checked fun g => ?_
  obtain ⟨gp, g'⟩ := guardAnd_ne g
  obtain ⟨go, gv⟩ := guardAnd_ne g'
  obtain ⟨fp, pv, pRun⟩ := lowerAs_progress corr (SrcProgram.target_toCore sp) pOk gp
  obtain ⟨fo, ov, oRun⟩ := lowerAs_progress corr (SrcProgram.target_toCore sp) oOk go
  obtain ⟨fv, bv, vRun⟩ := lowerAs_progress corr (SrcProgram.target_toCore sp) vOk gv
  obtain ⟨-, hpv⟩ := lowerAs_sound corr (SrcProgram.target_toCore sp) pOk pRun
  obtain ⟨-, hov, -⟩ := lowerAs_sound corr (SrcProgram.target_toCore sp) oOk oRun
  obtain ⟨-, hbv, -⟩ := lowerAs_sound corr (SrcProgram.target_toCore sp) vOk vRun
  simp only [SrcType.Holds] at hpv
  simp only [UintTy.toCore] at hov hbv
  subst hpv hov hbv
  have argsRun := exprs_cons_done pRun (exprs_cons_done oRun (exprs_cons_done vRun exprs_nil_done))
  simp only [SrcStmt.toCore] at fails
  have := fails (max fp (max fo (max fv 1 + 1) + 1) + 1 + 2)
  simp only [execStmt] at this
  rw [evalExpr.eq_def] at this
  simp only [argsRun, sync_ok fresh.2] at this
  cases stored : st.heap.storeByte (xp.eval env).toNat (xo.eval env).toNat (UInt8.ofNat (xv.eval env).toNat) with
  | error r =>
    simp only [stored, Failing] at this
    exact (trap_within this (storeByte_undefined stored) within).elim
  | ok heap' =>
    simp only [stored, syncFrom_ok (st := { st with heap := heap' }) fresh.2, Failing] at this
    rw [storeByte_next stored] at this
    exact absurd within (Nat.not_le.mpr this)

theorem stops_free {pointer size : SrcExpr} {shift : Nat} : SrcStops sp mp n (.free pointer size shift) := by
  intro hp ret scope next stmt frame base st env ok corr fr fresh le hc within fails
  simp only [SrcStmt.lower] at ok
  replace ok := guarded_some ok
  obtain ⟨stmt, ok, rfl⟩ := ok
  simp only [lowerFree] at ok
  split at ok
  case isFalse => simp at ok
  split at ok
  · simp at ok
  rename_i xp pOk
  split at ok
  · simp at ok
  rename_i xs sOk
  refine Stops.checked fun g => ?_
  obtain ⟨gp, gs⟩ := guardAnd_ne g
  obtain ⟨fp, pv, pRun⟩ := lowerAs_progress corr (SrcProgram.target_toCore sp) pOk gp
  obtain ⟨fs, sv, sRun⟩ := lowerAs_progress corr (SrcProgram.target_toCore sp) sOk gs
  obtain ⟨-, hpv⟩ := lowerAs_sound corr (SrcProgram.target_toCore sp) pOk pRun
  obtain ⟨-, hsv, -⟩ := lowerAs_sound corr (SrcProgram.target_toCore sp) sOk sRun
  simp only [SrcType.Holds] at hpv
  simp only [UintTy.toCore] at hsv
  subst hpv hsv
  have aRun : evalExpr 1 sp.toCore st (.value (.unsigned .usize (2 ^ shift))) = .done (.unsigned .usize (2 ^ shift)) st := by
    simp only [evalExpr]
  have argsRun := exprs_cons_done pRun (exprs_cons_done sRun (exprs_cons_done aRun exprs_nil_done))
  simp only [SrcStmt.toCore] at fails
  have := fails (max fp (max fs (max 1 1 + 1) + 1) + 1 + 2)
  simp only [execStmt] at this
  rw [evalExpr.eq_def] at this
  simp only [argsRun, sync_ok fresh.2] at this
  cases freed : st.heap.deallocate (xp.eval env).toNat (xs.eval env).toNat (2 ^ shift) with
  | error r =>
    simp only [freed, Failing] at this
    exact (trap_within this (deallocate_undefined freed) within).elim
  | ok heap' =>
    simp only [freed, Failing] at this
    rw [deallocate_next freed] at this
    exact absurd within (Nat.not_le.mpr this)


theorem stops_letSlice {id : Nat} {element : SrcType} {pointer length : SrcExpr} {body : SrcStmt}
    (ih : SrcStops sp mp n body) : SrcStops sp mp n (.letSlice id element pointer length body) := by
  intro hp ret scope next stmt frame base st env ok corr fr fresh le hc within fails
  simp only [SrcStmt.lower] at ok
  replace ok := guarded_some ok
  obtain ⟨stmt, ok, rfl⟩ := ok
  simp only [lowerLet] at ok
  split at ok
  · simp at ok
  rename_i xs sliceOk
  split at ok
  · simp at ok
  rename_i bstmt bodyOk
  simp only [Option.some.injEq] at ok
  subst ok
  simp only [lowerSlice] at sliceOk
  split at sliceOk
  case isFalse => simp at sliceOk
  rename_i cond
  have kind := slice_kind (by simp only [Bool.and_eq_true] at cond; exact cond.1)
  cases pOk : lowerAs scope pointer .ptr with
  | none => simp [pOk] at sliceOk
  | some xp =>
  cases lOk : lowerAs scope length .i32 with
  | none => simp [pOk, lOk] at sliceOk
  | some xl =>
  simp only [pOk, lOk, Option.some.injEq] at sliceOk
  subst sliceOk
  refine Stops.checked fun g => ?_
  obtain ⟨gp, gl⟩ := guardAnd_ne g
  obtain ⟨fp, pv, pRun⟩ := lowerAs_progress corr (SrcProgram.target_toCore sp) pOk gp
  obtain ⟨fl, lv, lRun⟩ := lowerAs_progress corr (SrcProgram.target_toCore sp) lOk gl
  obtain ⟨-, holdsP⟩ := lowerAs_sound corr (SrcProgram.target_toCore sp) pOk pRun
  obtain ⟨-, holdsL⟩ := lowerAs_sound corr (SrcProgram.target_toCore sp) lOk lRun
  simp only [SrcType.Holds] at holdsP
  obtain ⟨hn, bitsL⟩ := holdsL
  subst holdsP hn
  have pRun' := value_after pRun (Nat.le_max_left fp fl)
  have lRun' := value_after lRun (Nat.le_max_right fp fl)
  simp only [SrcStmt.toCore] at fails
  rcases sliceFrom_cases kind pRun' lRun' with ⟨v, st1, valueRun⟩ | ⟨r, trapRun, undefined⟩
  · obtain ⟨a, afterPointer, n, afterLength, len, heap, pointerRun, lengthRun, rfl, rfl, hcOf, lenEq, nonneg⟩ :=
      sliceFrom_inv kind valueRun
    rw [pRun'] at pointerRun
    simp only [Semantics.Outcome.done.injEq, Value.pointer.injEq] at pointerRun
    obtain ⟨rfl, rfl⟩ := pointerRun
    rw [lRun'] at lengthRun
    simp only [Semantics.Outcome.done.injEq, Value.signed.injEq, true_and] at lengthRun
    obtain ⟨rfl, rfl⟩ := lengthRun
    have sized : (0 : Nat) < (SrcType.slice element).size := by simp [SrcType.size]
    have insens : Insens [xp, xl] next := Insens.below fun x mem => by
      simp only [List.mem_cons, List.not_mem_nil, or_false] at mem
      rcases mem with rfl | rfl
      · obtain ⟨t, lowered, -, rfl⟩ := lowerAs_some pOk
        exact (ValueShape.single lowered rfl).below fr.slots _ List.mem_cons_self
      · obtain ⟨t, lowered, -, rfl⟩ := lowerAs_some lOk
        exact (ValueShape.single lowered rfl).below fr.slots _ List.mem_cons_self
    obtain ⟨d, stops⟩ := let_stops ih (ty := .slice element)
        (st := { st with heap }) (v := .rawSlice element.toCore (xp.eval env).toNat len)
        (env' := env.setFrom next [xp, xl]) (hp := hp) (by simpa [SrcType.size] using bodyOk)
        (corr.cells_congr rfl fun _ _ => rfl) fr fresh le sized
        (fr.agree fun j below => setFrom_outside [xp, xl] next env j (.inl below))
        (by
          have first : (xp.eval env).toNat = (env.setFrom next [xp, xl] next).toNat := by
            have here := setFrom_value _ next env insens 0 xp rfl
            simp only [Nat.add_zero] at here
            rw [here]
          have second : env.setFrom next [xp, xl] (next + 1) = xl.eval env := by
            simpa using setFrom_value _ next env insens 1 xl rfl
          rw [first]
          refine .slice ?_ ?_
          · have bits : (xl.eval env).toNat = (low (xl.eval env)).toNat := by
              conv => lhs; rw [bitsL]
              exact widen_toNat _
            rw [second, lenEq, bits, ← toNat_of_toInt _ nonneg, Int.toNat_natCast]
          · have := BitVec.toInt_lt (x := low (xl.eval env))
            omega)
        (hcOf hp hc) (show heap.nextAddress ≤ hp.limit by rw [← (hcOf hp hc).cursor, hc.cursor]; exact within)
        (fails.letBody valueRun)
    exact ⟨d, Stops.assignFrom [xp, xl] next stops⟩
  · have := fails (max fp fl + 1 + 1)
    simp only [execStmt, trapRun, Failing] at this
    exact (trap_within this undefined within).elim


theorem stops_letIndex_i32 {id : Nat} {ty : SrcType} {slice : Nat} {index : SrcExpr} {body : SrcStmt}
    (ih : SrcStops sp mp n body) {hp : Heap} {ret : SrcType} {scope : List Binding} {next : Nat} {stmt : Stmt}
    {frame : Nat → Nat} {base : Nat} {st : State} {env : Env}
    (ok : lowerLoadWord next (lowerElement (lookup scope slice) ty (lowerIndex scope index))
      (body.lower (sigs sp.funcs) sp.decls ret (⟨id, next, ty⟩ :: scope) (next + ty.size)) = some stmt)
    (corr : Corr scope frame st env) (fr : Layout scope frame base next) (fresh : st.Fresh)
    (le : base ≤ st.nextCell) (hc : HeapCorr st.heap hp) (within : st.heap.nextAddress ≤ hp.limit)
    (fails : Fails sp hp.limit st (SrcStmt.letIndex id ty slice index body).toCore) :
    ∃ d, Stops mp d env hp (checkThen next (guardAnd (index.guard scope) (indexGuard scope slice index)) stmt) n := by
  simp only [lowerLoadWord] at ok
  split at ok
  · simp at ok
  rename_i a addressOk
  split at ok
  · simp at ok
  rename_i bstmt bodyOk
  simp only [Option.some.injEq] at ok
  subst ok
  simp only [lowerElement] at addressOk
  split at addressOk
  · simp at addressOk
  rename_i b found
  split at addressOk
  case isFalse => simp at addressOk
  rename_i same
  have bty := SrcType.same_eq same
  simp only [elementAddress, bty, elementOf] at addressOk
  split at addressOk
  · simp at addressOk
  rename_i i indexOk
  split at addressOk
  case isFalse => simp at addressOk
  rename_i isI32
  cases ty <;> simp [SrcType.isI32] at isI32
  simp only [Option.some.injEq] at addressOk
  subst addressOk
  simp only [lowerIndex] at indexOk
  split at indexOk
  · simp at indexOk
  rename_i t indexLowered
  simp only [indexOf] at indexOk
  split at indexOk
  case isFalse => simp at indexOk
  rename_i kind
  simp only [Option.some.injEq] at indexOk
  subst indexOk
  refine Stops.checked fun g => ?_
  obtain ⟨gi, gb⟩ := guardAnd_ne g
  obtain ⟨w0, localRun0, holdsW⟩ := corr.local found 0 sp.toCore
  rw [bty] at holdsW
  cases holdsW with
  | @slice _ len _ _ lenSlot lenSmall =>
  obtain ⟨fi, iv, indexRun⟩ := index.progress corr (SrcProgram.target_toCore sp) indexLowered gi
  obtain ⟨-, holdsI⟩ := index.lower_sound corr (SrcProgram.target_toCore sp) indexLowered indexRun
  have inBounds := indexGuard_ne found (x := t.expr) (by simp [lowerIndex, indexLowered, indexOf, kind]) gb
  rw [lenSlot] at inBounds
  have posOk := index_ok kind holdsI (by omega)
  obtain ⟨w', localRun, -⟩ := corr.local found fi sp.toCore
  have same' := value_after localRun0 (Nat.le_add_left 1 fi)
  rw [localRun] at same'
  simp only [Semantics.Outcome.done.injEq] at same'
  obtain ⟨rfl, -⟩ := same'
  have indexRun' := value_after indexRun (Nat.le_succ fi)
  simp only [SrcStmt.toCore] at fails
  rcases index_outcome localRun indexRun' posOk inBounds with ⟨v, valueRun, read⟩ | ⟨r, trapRun, undefined⟩
  · have posEq : (t.expr.eval env).toNat = (t.expr.eval env).toNat := rfl
    simp only [Semantics.readRawSliceIndex] at read
    split at read
    · simp at read
    simp only [Semantics.rawSliceElementAddress?, SrcType.toCore] at read
    obtain ⟨elt, eltOk, read⟩ := except_bind_ok read
    simp only [pure, Except.pure, Except.ok.injEq] at eltOk
    subst eltOk
    simp only [NativeLayout.maxDepth, Semantics.readNativeValue] at read
    obtain ⟨bits, loaded, wrapped⟩ := except_bind_ok read
    simp only [pure, Except.pure, Except.ok.injEq] at wrapped
    subst wrapped
    obtain ⟨rfl, inside⟩ := hc.loadNatLE loaded
    have inside := inside (by decide)
    have tail := within
    have small := hc.small
    have address : ((Expr.binary Word.u64 BinOp.add (Expr.var b.slot)
        (Expr.binary Word.u64 BinOp.mul t.expr (Expr.lit 4))).eval env).toNat =
        (env b.slot).toNat + (t.expr.eval env).toNat * 4 := by
      have four : (4 : BitVec 64).toNat = 4 := rfl
      simp only [Expr.eval, Word.apply, BinOp.apply, BitVec.toNat_add, BitVec.toNat_mul, four]
      rw [Nat.mod_eq_of_lt (a := (t.expr.eval env).toNat * 4) (by addr_omega), Nat.mod_eq_of_lt (by addr_omega)]
    have room : ((Expr.binary Word.u64 BinOp.add (Expr.var b.slot)
        (Expr.binary Word.u64 BinOp.mul t.expr (Expr.lit 4))).eval env).toNat + MemWidth.m32.bytes ≤
        hp.limit := by
      rw [address]; simp only [MemWidth.bytes]; addr_omega
    have lt32 := hp.readLE_lt ((env b.slot).toNat + (t.expr.eval env).toNat * 4) 4
    obtain ⟨d, stops⟩ := let_stops ih (ty := .i32)
        (env' := env.set next (BitVec.ofNat 64 (hp.readLE ((Expr.binary Word.u64 BinOp.add
          (Expr.var b.slot) (Expr.binary Word.u64 BinOp.mul t.expr (Expr.lit 4))).eval env).toNat
          MemWidth.m32.bytes)))
        (hp := hp) (by simpa [SrcType.size] using bodyOk) corr fr fresh le (by simp [SrcType.size])
        (fr.agree fun j below => by simp only [Env.set]; rw [if_neg (by omega)])
        (.i32 (by
          simp only [Env.set, if_pos, address, MemWidth.bytes]
          exact i32_load_holds (by simpa using lt32)))
        hc within (fails.letBody valueRun)
    exact ⟨_, Stops.after (.loadWord (depth := 0) room) stops⟩
  · have := fails (fi + 2 + 1)
    simp only [execStmt, trapRun, Failing] at this
    exact (trap_within this undefined within).elim

theorem stops_letIndex_word {id : Nat} {ty : SrcType} {slice : Nat} {index : SrcExpr} {body : SrcStmt}
    (ih : SrcStops sp mp n body) {hp : Heap} {ret : SrcType} {scope : List Binding} {next : Nat} {stmt : Stmt}
    {frame : Nat → Nat} {base : Nat} {st : State} {env : Env}
    (ok : lowerLoadType sp.decls next (lookup scope slice) ty (lowerIndex scope index)
      (body.lower (sigs sp.funcs) sp.decls ret (⟨id, next, ty⟩ :: scope) (next + ty.size)) = some stmt)
    (corr : Corr scope frame st env) (fr : Layout scope frame base next) (fresh : st.Fresh)
    (le : base ≤ st.nextCell) (hc : HeapCorr st.heap hp) (within : st.heap.nextAddress ≤ hp.limit)
    (fails : Fails sp hp.limit st (SrcStmt.letIndex id ty slice index body).toCore) :
    ∃ d, Stops mp d env hp (checkThen next (guardAnd (index.guard scope) (indexGuard scope slice index)) stmt) n := by
  unfold lowerLoadType at ok
  split at ok
  · simp at ok
  rename_i b found
  split at ok
  · simp at ok
  rename_i i indexOk
  split at ok
  · simp at ok
  rename_i bstmt bodyOk
  split at ok
  case isFalse => simp at ok
  rename_i cond
  simp only [Bool.and_eq_true] at cond
  obtain ⟨hel, same⟩ := cond
  simp only [Option.some.injEq] at ok
  subst ok
  have bty := SrcType.same_eq same
  have tpos := wordElement_size hel
  have indexOk' := indexOk
  simp only [lowerIndex] at indexOk
  split at indexOk
  · simp at indexOk
  rename_i t indexLowered
  simp only [indexOf] at indexOk
  split at indexOk
  case isFalse => simp at indexOk
  rename_i kind
  simp only [Option.some.injEq] at indexOk
  subst indexOk
  refine Stops.checked fun g => ?_
  obtain ⟨gi, gb⟩ := guardAnd_ne g
  obtain ⟨w0, localRun0, holdsW⟩ := corr.local found 0 sp.toCore
  rw [bty] at holdsW
  cases holdsW with
  | @slice _ len _ _ lenSlot lenSmall =>
  obtain ⟨fi, iv, indexRun⟩ := index.progress corr (SrcProgram.target_toCore sp) indexLowered gi
  obtain ⟨-, holdsI⟩ := index.lower_sound corr (SrcProgram.target_toCore sp) indexLowered indexRun
  have inBounds := indexGuard_ne found indexOk' gb
  rw [lenSlot] at inBounds
  have posOk := index_ok kind holdsI (by omega)
  obtain ⟨w', localRun, -⟩ := corr.local found fi sp.toCore
  have same' := value_after localRun0 (Nat.le_add_left 1 fi)
  rw [localRun] at same'
  simp only [Semantics.Outcome.done.injEq] at same'
  obtain ⟨rfl, -⟩ := same'
  have indexRun' := value_after indexRun (Nat.le_succ fi)
  simp only [SrcStmt.toCore] at fails
  rcases index_outcome localRun indexRun' posOk inBounds with ⟨v, valueRun, read⟩ | ⟨r, trapRun, undefined⟩
  · have bslot : b.slot < next := by
      have := fr.slots b (lookup_mem found).1
      rw [bty] at this
      simp only [SrcType.size] at this
      omega
    have below : (elementBase b.slot ty.size t.expr).Below next :=
      ⟨bslot, SrcExpr.lower_below fr.slots index indexLowered, trivial⟩
    obtain ⟨env2, agree, holds, load⟩ := loadElement_sound (mp := mp) hc within hel rfl below read
    obtain ⟨d, stops⟩ := let_stops ih (ty := ty) (env' := env2) (hp := hp) bodyOk corr fr fresh le tpos
      (fr.agree fun j lt => agree j (.inl lt)) holds hc within (fails.letBody valueRun)
    obtain ⟨ps, eq⟩ := loadType_chain ty next (elementBase b.slot ty.size t.expr) 0
    have pre := load (d := d) (rest := .skip) .skip
    rw [eq] at pre ⊢
    exact ⟨d, Stops.chain ps pre stops⟩
  · have := fails (fi + 2 + 1)
    simp only [execStmt, trapRun, Failing] at this
    exact (trap_within this undefined within).elim

theorem stops_letIndex {id : Nat} {ty : SrcType} {slice : Nat} {index : SrcExpr} {body : SrcStmt}
    (ih : SrcStops sp mp n body) : SrcStops sp mp n (.letIndex id ty slice index body) := by
  intro hp ret scope next stmt frame base st env ok corr fr fresh le hc within fails
  simp only [SrcStmt.lower] at ok
  replace ok := guarded_some ok
  obtain ⟨stmt, ok, rfl⟩ := ok
  simp only [lowerLetIndex] at ok
  split at ok
  · exact stops_letIndex_i32 ih ok corr fr fresh le hc within fails
  · exact stops_letIndex_word ih ok corr fr fresh le hc within fails


/-- A failing `slice[index] = value` whose operands are checked is impossible. -/
theorem setIndex_fails {scope : List Binding} {frame : Nat → Nat} {st : State} {env : Env} {hp : Heap}
    (corr : Corr scope frame st env) (fresh : st.Fresh) (within : st.heap.nextAddress ≤ hp.limit)
    {slice : Nat} {b : Binding} (found : lookup scope slice = some b) {element : SrcType}
    (bty : b.ty = .slice element) {index value : SrcExpr} {x : Expr} (indexOk : lowerIndex scope index = some x)
    (gi : (index.guard scope).eval env ≠ 0) (gb : (indexGuard scope slice index).eval env ≠ 0)
    (vRun : ∃ f v, evalExpr f sp.toCore st value.toCore = .done v st)
    (fails : Fails sp hp.limit st (SrcStmt.setIndex slice index value).toCore) : False := by
  have indexOk' := indexOk
  simp only [lowerIndex] at indexOk
  split at indexOk
  · simp at indexOk
  rename_i t indexLowered
  simp only [indexOf] at indexOk
  split at indexOk
  case isFalse => simp at indexOk
  rename_i kind
  simp only [Option.some.injEq] at indexOk
  subst indexOk
  obtain ⟨fv, rv, valueRun⟩ := vRun
  obtain ⟨fi, iv, indexRun⟩ := index.progress corr (SrcProgram.target_toCore sp) indexLowered gi
  obtain ⟨-, holdsI⟩ := index.lower_sound corr (SrcProgram.target_toCore sp) indexLowered indexRun
  obtain ⟨w, place, holdsW⟩ := corr.readPlace found (max fi fv) sp.toCore
  rw [bty] at holdsW
  cases holdsW with
  | @slice _ len _ _ lenSlot lenSmall =>
  have inBounds := indexGuard_ne found indexOk' gb
  rw [lenSlot] at inBounds
  have posOk := index_ok kind holdsI (by omega)
  have indexRun' := value_after indexRun (show fi ≤ max fi fv + 1 by omega)
  have valueRun' := value_after valueRun (show fv ≤ max fi fv + 2 by omega)
  simp only [SrcStmt.toCore] at fails
  rcases setIndex_outcome fresh.2 place indexRun' posOk inBounds valueRun' with ⟨st', run, keeps⟩ | ⟨r, run, undefined⟩
  · exact fails.not_done (k := max fi fv + 3 + 1) (c := .next) (st' := st') (by simp only [execStmt, run])
      (by rw [keeps]; exact within)
  · have := fails (max fi fv + 3 + 1)
    simp only [execStmt, run, Failing] at this
    exact (trap_within this undefined within).elim

theorem stops_setIndex {slice : Nat} {index value : SrcExpr} : SrcStops sp mp n (.setIndex slice index value) := by
  intro hp ret scope next stmt frame base st env ok corr fr fresh le hc within fails
  simp only [SrcStmt.lower] at ok
  replace ok := guarded_some ok
  obtain ⟨stmt, ok, rfl⟩ := ok
  simp only [lowerSetIndex] at ok
  split at ok
  · simp at ok
  rename_i b found
  simp only [lowerSetIndexOf] at ok
  split at ok
  · simp at ok
  rename_i element hElt
  have bty : b.ty = .slice element := by
    cases hty : b.ty <;> simp [elementOf, hty] at hElt
    rw [hElt]
  refine Stops.checked fun g => ?_
  obtain ⟨g1, gv⟩ := guardAnd_ne g
  obtain ⟨gi, gb⟩ := guardAnd_ne g1
  exfalso
  simp only [storeAny] at ok
  split at ok
  · split at ok
    · simp at ok
    rename_i a addrOk
    split at ok
    · simp at ok
    rename_i xv vOk
    simp only [elementAddress, bty, elementOf] at addrOk
    split at addrOk
    · simp at addrOk
    rename_i i indexOk
    exact setIndex_fails corr fresh within found bty indexOk gi gb
      (lowerAs_progress corr (SrcProgram.target_toCore sp) vOk gv) fails
  · split at ok
    · unfold storeWordElement at ok
      split at ok
      · simp at ok
      rename_i i indexOk
      split at ok
      · simp at ok
      rename_i vs vOk
      exact setIndex_fails corr fresh within found bty indexOk gi gb
        (lowerValue_progress corr (SrcProgram.target_toCore sp) vOk gv) fails
    · simp at ok

end Statements

end Lanius.Mini
