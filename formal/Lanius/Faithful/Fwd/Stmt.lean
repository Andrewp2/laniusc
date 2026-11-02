import Lanius.Faithful.Fwd.Eff

/-! # Forward: statements complete in Core

A statement `stmtOk` accepts, with a cost-semantics ending `(d, h)`,
completes in Core from some fuel on with the ending `d` means, when the heap
has `h` bytes left below `2 ^ 64` and Core completes the calls of the cost
semantics (`FuncLive`): `stmt_live`. The heap grows by at most `h`. -/

namespace Lanius.Faithful

open Lanius.Mini
open Lanius.Core (Value)
open Lanius.Semantics (State Completion evalExpr evalExprs execStmt restoreLocals)

section
variable {sp : SrcProgram} {prims : Prims} {outside : List Nat} {cost : Nat → Nat} {N : Nat}

/-- The bound of a part of a budget. -/
private theorem part {a b : Nat} (le : a ≤ b) (budget : b ≤ 2 ^ 64) : a ≤ 2 ^ 64 := Nat.le_trans le budget

/-! ## Relations of completed pure runs -/

theorem expr_rel {tenv : TEnv} {env : Env} {st : State} {e : SrcExpr} {t : SrcType} {p v : Value} {st' : State}
    (ht : exprTy (boxElem sp prims) tenv e = some t) (rel : EnvRel sp.toCore (boxElem sp prims) st.heap tenv env st)
    (hp : pexpr env e = some p) (run : Ev (fun k => evalExpr k sp.toCore st e.toCore) v st') :
    VRel sp.toCore (boxElem sp prims) st.heap t v p := by
  obtain ⟨k, hk⟩ := run.at
  obtain ⟨p', hp', r⟩ := expr_sim (toCore_target sp) tenv env e hk ht rel
  rw [hp, Option.some.injEq] at hp'
  subst hp'
  exact r

theorem exprs_rel {tenv : TEnv} {env : Env} {st : State} {es : List SrcExpr} {ts : List SrcType} {ps vs : List Value}
    {st' : State} (ht : exprTys (boxElem sp prims) tenv es = some ts)
    (rel : EnvRel sp.toCore (boxElem sp prims) st.heap tenv env st) (hp : pexprs env es = some ps)
    (run : Ev (fun k => evalExprs k sp.toCore st (es.map SrcExpr.toCore)) vs st') :
    VRels sp.toCore (boxElem sp prims) st.heap ts vs ps := by
  obtain ⟨k, hk⟩ := run.at
  obtain ⟨ps', hp', r⟩ := exprs_sim (toCore_target sp) tenv env es hk ht rel
  rw [hp, Option.some.injEq] at hp'
  subst hp'
  exact r

/-- A `let`'s body's ending, its binding dropped. -/
theorem qpop_some {o : Option (Out × Nat)} {b : Out} {h : Nat} (e : qpop o = some (b, h)) :
    ∃ ob, o = some (ob, h) ∧ b = ob.pop := by
  cases o with
  | none => simp [qpop] at e
  | some p =>
    obtain ⟨ob, h'⟩ := p
    simp only [qpop, Option.map_some, Option.some.injEq, Prod.mk.injEq] at e
    obtain ⟨rfl, rfl⟩ := e
    exact ⟨ob, rfl, rfl⟩

theorem OutRel.of_next {P : Core.Program} {boxes : Boxes} {heap : Memory.Heap} {ret : SrcType} {tenv : TEnv}
    {st : State} {c : Completion} {e : Env} (r : OutRel P boxes heap ret tenv st c (.next e)) :
    c = .next ∧ EnvRel P boxes heap tenv e st := by
  cases c with
  | next => exact ⟨rfl, r⟩
  | breakLoop => exact False.elim r
  | continueLoop => exact False.elim r
  | returned _ => exact False.elim r

theorem OutRel.ne_next {P : Core.Program} {boxes : Boxes} {heap : Memory.Heap} {ret : SrcType} {tenv : TEnv}
    {st : State} {c : Completion} {o : Out} (r : OutRel P boxes heap ret tenv st c o) (hno : ∀ e, o ≠ .next e) :
    c ≠ .next := by
  rintro rfl
  cases o with
  | next e => exact hno e rfl
  | brk _ => exact False.elim r
  | cont _ => exact False.elim r
  | ret _ => exact False.elim r

/-- **Core's `id = e` completes** once `e` does, for a bound `id` whose cell
outlives `e`, with views gone. -/
theorem setLocal_fwd {P : Core.Program} {st s1 : State} {id : Nat} {e : Core.Expr} {v0 w : Value}
    (hv : st.local? id = some v0) (sub : Ev (fun k => evalExpr k P st e) w s1) (views : s1.i32ArrayViews = [])
    (keep : ∀ c, st.cellId? id = some c → (s1.cellEntry? c).isSome) :
    ∃ c, st.cellId? id = some c ∧
      Ev (fun k => evalExpr k P st (.assign .set (.local id) e)) .unit (s1.assigned c w) := by
  cases hc : st.cellId? id with
  | none => simp [State.local?, hc] at hv
  | some c =>
    cases he : st.cellEntry? c with
    | none => simp [State.local?, State.cell?, hc, he] at hv
    | some entry =>
      have hs := keep c hc
      obtain ⟨K, hK⟩ := sub
      refine ⟨c, rfl, K + 2, fun k hk => ?_⟩
      obtain ⟨j, rfl⟩ : ∃ j, k = j + 1 := ⟨k - 1, by omega⟩
      simp only [evalExpr]
      obtain ⟨i, rfl⟩ : ∃ i, j = i + 1 := ⟨j - 1, by omega⟩
      simp only [Semantics.evalPlace, hc, he, hK (i + 1) (by omega), Semantics.evalAssignValue,
        Semantics.assignOpBinary?, Semantics.writeResolvedPlaceNative, Semantics.writeResolvedPlace,
        Semantics.State.assignCell]
      rw [if_pos hs]
      simp only
      by_cases hw : ({ root := c, projections := [], value := entry.value } : Semantics.ResolvedPlace).viewFreeRootWrite w = true
      · rw [if_pos hw]
      · rw [if_neg hw]
        simp [Semantics.syncI32ViewsToHeap, Semantics.syncI32ViewsToHeapFrom, views]

variable (calls : ∀ m, FuncSim sp prims outside m)
include calls

/-- A completed body of a callee the cost semantics gives `w`: Core's value means `w`. -/
theorem call_rel {c : Nat} {f : SrcFunc} {values ps : List Value} {st completed : State} {compl : Completion}
    {v w : Value} {h : Nat} (found : sp.funcs[c]? = some f) (notOut : outside.contains c = false)
    (len : values.length = f.params.length) (inv : Inv st)
    (args : VRels sp.toCore (boxElem sp prims) st.heap (f.params.map SrcParam.ty) values ps)
    (hq : qcall sp prims cost N c ps = some (w, h))
    (run : Ev (fun k => execStmt k sp.toCore (({ st with locals := [] } : State).bindLocals
      (paramBindings f.params values)) f.body.toCore) compl completed)
    (result : CallResult f.ret compl v) (bound : completed.heap.nextAddress ≤ 2 ^ 64) :
    VRel sp.toCore (boxElem sp prims) completed.heap f.ret v w ∧ Inv completed ∧ Step st completed := by
  obtain ⟨k, hk⟩ := run.at
  obtain ⟨w', hw', r, invc, step⟩ := calls k found notOut len inv bound args hk result
  have hp : pcall sp prims N c ps = some w := by rw [pcall_eq_qcall sp prims cost, hq]; rfl
  have e1 := pcall_mono sp prims (k + 1) hw' (Nat.le_max_right N (k + 1))
  rw [pcall_mono sp prims N hp (Nat.le_max_left N (k + 1)), Option.some.injEq] at e1
  subst e1
  exact ⟨r, invc, step⟩

theorem stmt_rel {ret : SrcType} {tenv : TEnv} {env : Env} {st : State} {s : SrcStmt} {o : Out} {c : Completion}
    {st' : State} (ok : stmtOk sp outside (boxElem sp prims) ret tenv s = true) (inv : Inv st) (locs : Locs st)
    (rel : EnvRel sp.toCore (boxElem sp prims) st.heap tenv env st) (hp : mstmt (pcall sp prims N) N env s = some o)
    (run : Ev (fun k => execStmt k sp.toCore st s.toCore) c st') (bound : st'.heap.nextAddress ≤ 2 ^ 64) :
    OutRel sp.toCore (boxElem sp prims) st'.heap ret tenv st' c o ∧ RanS st st' := by
  obtain ⟨k, hk⟩ := run.at
  obtain ⟨o', ho', orl, ran⟩ :=
    stmt_sim (N := max N k) (fun i _ => calls i) ret s (Nat.le_max_right N k) hk ok inv locs rel bound
  rw [mstmt_mono (callsLe (Nat.le_max_left N k)) (Nat.le_max_left N k) s hp, Option.some.injEq] at ho'
  subst ho'
  exact ⟨orl, ran⟩

/-! ## Statements -/

/-- **A statement with a cost-semantics ending completes in Core.** -/
theorem stmt_live (live : FuncLive sp prims outside cost N) (ret : SrcType) (s : SrcStmt) :
    ∀ {tenv : TEnv} {env : Env} {st : State} {d : Out} {h : Nat},
      stmtOk sp outside (boxElem sp prims) ret tenv s = true → Inv st → Locs st →
      EnvRel sp.toCore (boxElem sp prims) st.heap tenv env st →
      qstmt (qcall sp prims cost N) N env s = some (d, h) → st.heap.nextAddress + h ≤ 2 ^ 64 →
      st.heap.remaining = none →
      ∃ c st', Ev (fun k => execStmt k sp.toCore st s.toCore) c st' ∧
        OutRel sp.toCore (boxElem sp prims) st'.heap ret tenv st' c d ∧ RanS st st' ∧
        st'.heap.nextAddress ≤ st.heap.nextAddress + h ∧ st'.heap.remaining = none := by
  induction s with
  | nop =>
    intro tenv env st d h ok inv locs rel hq budget fr
    have hq' := hq
    simp only [qstmt, Option.some.injEq, Prod.mk.injEq] at hq'
    obtain ⟨rfl, rfl⟩ := hq'
    have ev : Ev (fun k => execStmt k sp.toCore st SrcStmt.nop.toCore) .next st := by
      simpa only [SrcStmt.toCore] using skip_fwd
    have g : st.heap.nextAddress ≤ st.heap.nextAddress + 0 := by aomega
    obtain ⟨dr, ran⟩ := stmt_rel calls ok inv locs rel (mstmt_of hq) ev (part g budget)
    exact ⟨_, _, ev, dr, ran, g, fr⟩
  | «let» id ty value body ih =>
    intro tenv env st d h ok inv locs rel hq budget fr
    have ok' := ok
    simp only [stmtOk] at ok'
    split at ok'
    · rename_i t ht
      have hq' := hq
      simp only [qstmt, Option.bind_eq_some_iff] at hq'
      obtain ⟨pv, hpv, hb⟩ := hq'
      obtain ⟨ob, hob, rfl⟩ := qpop_some hb
      obtain ⟨v, evv⟩ := expr_live (toCore_target sp) tenv env value ht rel hpv
      have r := expr_rel ht rel hpv evv
      obtain ⟨c, s2, evb, -, -, g, fg⟩ := ih ok' (inv.bindLocal id v) (locs.bindLocal inv id v) (rel.bind inv r) hob
        budget fr
      have ev : Ev (fun k => execStmt k sp.toCore st (SrcStmt.let id ty value body).toCore) c
          (restoreLocals st s2) := by
        simpa only [SrcStmt.toCore] using letLocal_fwd (ty := ty.toCore) evv evb
      obtain ⟨dr, ran⟩ := stmt_rel calls ok inv locs rel (mstmt_of hq) ev (part g budget)
      exact ⟨_, _, ev, dr, ran, g, fg⟩
    · simp at ok'
  | letStruct id ty fields body ih =>
    intro tenv env st d h ok inv locs rel hq budget fr
    have ok' := ok
    simp only [stmtOk] at ok'
    split at ok'
    · rename_i t ht
      simp only [Option.bind_eq_some_iff] at ht
      obtain ⟨ts, hts, hs⟩ := ht
      obtain ⟨sid, rfl, hbx, rfl⟩ := structTy_some hs
      have hq' := hq
      simp only [qstmt, Option.bind_eq_some_iff] at hq'
      obtain ⟨ps, hps, hb⟩ := hq'
      obtain ⟨ob, hob, rfl⟩ := qpop_some hb
      obtain ⟨vs, evs⟩ := exprs_live (toCore_target sp) tenv env fields hts rel hps
      have r : VRel sp.toCore (boxElem sp prims) st.heap (.struct sid ts) (.structure sid vs) (.structure sid ps) :=
        .struct hbx (exprs_rel hts rel hps evs)
      obtain ⟨c, s2, evb, -, -, g, fg⟩ := ih ok' (inv.bindLocal id _) (locs.bindLocal inv id _) (rel.bind inv r) hob
        budget fr
      have ev : Ev (fun k => execStmt k sp.toCore st (SrcStmt.letStruct id (.struct sid ts) fields body).toCore) c
          (restoreLocals st s2) := by
        simpa only [SrcStmt.toCore, SrcType.literal] using
          letLocal_fwd (ty := (SrcType.struct sid ts).toCore) (struct_fwd (id := sid) evs) evb
      obtain ⟨dr, ran⟩ := stmt_rel calls ok inv locs rel (mstmt_of hq) ev (part g budget)
      exact ⟨_, _, ev, dr, ran, g, fg⟩
    · simp at ok'
  | letCall id ty callee args body ih =>
    intro tenv env st d h ok inv locs rel hq budget fr
    have ok' := ok
    simp only [stmtOk] at ok'
    split at ok'
    · rename_i t ht
      simp only [Option.bind_eq_some_iff] at ht
      obtain ⟨ts, hts, hct⟩ := ht
      obtain ⟨notOut, f, found, rfl, rfl⟩ := callTy_some hct
      have hq' := hq
      simp only [qstmt] at hq'
      obtain ⟨w, h1, h2, hc, hb, rfl⟩ := qthen_some hq'
      obtain ⟨ob, hob, rfl⟩ := qpop_some hb
      simp only [Option.bind_eq_some_iff] at hc
      obtain ⟨ps, hps, hc⟩ := hc
      obtain ⟨vs, evs⟩ := exprs_live (toCore_target sp) tenv env args hts rel hps
      have rs := exprs_rel hts rel hps evs
      have len : vs.length = f.params.length := by simpa using rs.length.1
      obtain ⟨compl, completed, v, evb, result, g1, f1⟩ := live found notOut len inv rs hc (part (by aomega) budget) fr
      have evc := call_fwd evs found len evb result
      obtain ⟨rw, invc, stepc⟩ := call_rel calls found notOut len inv rs hc evb result (part (by aomega) budget)
      have inv1 : Inv (restoreLocals st completed) := invc.restore st
      have rel1 := rel.step (stepc.restore st) rfl
      have locs1 : Locs (restoreLocals st completed) := locs.step (stepc.restore st) rfl
      obtain ⟨c, s2, evb2, -, -, g2, f2⟩ := ih ok' (inv1.bindLocal id v) (locs1.bindLocal inv1 id v) (rel1.bind inv1 rw) hob
        (part (show completed.heap.nextAddress + h2 ≤ st.heap.nextAddress + (h1 + h2) by aomega) budget) f1
      have ev : Ev (fun k => execStmt k sp.toCore st (SrcStmt.letCall id ty callee args body).toCore) c
          (restoreLocals (restoreLocals st completed) s2) := by
        simpa only [SrcStmt.toCore] using letLocal_fwd (ty := ty.toCore) evc evb2
      have g : (restoreLocals (restoreLocals st completed) s2).heap.nextAddress ≤
          st.heap.nextAddress + (h1 + h2) := by
        show s2.heap.nextAddress ≤ _
        have g2' : s2.heap.nextAddress ≤ completed.heap.nextAddress + h2 := g2
        aomega
      obtain ⟨dr, ran⟩ := stmt_rel calls ok inv locs rel (mstmt_of hq) ev (part g budget)
      exact ⟨_, _, ev, dr, ran, g, f2⟩
    · simp at ok'
  | letEnum id ty variant payload body ih =>
    intro tenv env st d h ok inv locs rel hq budget fr
    have ok' := ok
    simp only [stmtOk] at ok'
    split at ok'
    · rename_i t ht
      simp only [Option.bind_eq_some_iff] at ht
      obtain ⟨ts, hts, hs⟩ := ht
      obtain ⟨eid, variants, rfl, hk, rfl⟩ := variantTy_some hs
      have hq' := hq
      simp only [qstmt, Option.bind_eq_some_iff] at hq'
      obtain ⟨ps, hps, hb⟩ := hq'
      obtain ⟨ob, hob, rfl⟩ := qpop_some hb
      obtain ⟨vs, evs⟩ := exprs_live (toCore_target sp) tenv env payload hts rel hps
      have r : VRel sp.toCore (boxElem sp prims) st.heap (.enum eid variants) (.enumeration eid variant vs)
          (.enumeration eid variant ps) := .enum hk (exprs_rel hts rel hps evs)
      simp only [SrcType.typeId] at hb
      obtain ⟨c, s2, evb, -, -, g, fg⟩ := ih ok' (inv.bindLocal id _) (locs.bindLocal inv id _) (rel.bind inv r) hob
        budget fr
      have ev : Ev (fun k => execStmt k sp.toCore st
          (SrcStmt.letEnum id (.enum eid variants) variant payload body).toCore) c (restoreLocals st s2) := by
        simpa only [SrcStmt.toCore, SrcType.typeId] using
          letLocal_fwd (ty := (SrcType.enum eid variants).toCore) (enum_fwd (id := eid) (variant := variant) evs) evb
      obtain ⟨dr, ran⟩ := stmt_rel calls ok inv locs rel (mstmt_of hq) ev (part g budget)
      exact ⟨_, _, ev, dr, ran, g, fg⟩
    · simp at ok'
  | letMatch => intro tenv env st d h ok; simp [stmtOk] at ok
  | set id value =>
    intro tenv env st d h ok inv locs rel hq budget fr
    have ok' := ok
    simp only [stmtOk, setOk] at ok'
    split at ok'
    · rename_i t ht
      split at ok'
      · rename_i t' ht'
        rw [SrcType.same_eq ok'] at ht'
        have hq' := hq
        simp only [qstmt] at hq'
        obtain ⟨hm, rfl⟩ := qfree_some hq'
        simp only [Option.bind_eq_some_iff] at hm
        obtain ⟨pv, hpv, -⟩ := hm
        obtain ⟨v, evv⟩ := expr_live (toCore_target sp) tenv env value ht' rel hpv
        obtain ⟨v0, -, hv0, -, -⟩ := rel id t ht
        obtain ⟨c, -, eva⟩ := setLocal_fwd hv0 evv inv.views fun c hc => locs.alloc id c hc
        have ev : Ev (fun k => execStmt k sp.toCore st (SrcStmt.set id value).toCore) .next (st.assigned c v) := by
          simpa only [SrcStmt.toCore] using expression_fwd eva
        have g : (st.assigned c v).heap.nextAddress ≤ st.heap.nextAddress + 0 := by
          show st.heap.nextAddress ≤ _
          aomega
        obtain ⟨dr, ran⟩ := stmt_rel calls ok inv locs rel (mstmt_of hq) ev (part g budget)
        exact ⟨_, _, ev, dr, ran, g, fr⟩
      · simp at ok'
    · simp at ok'
  | setField => intro tenv env st d h ok; simp [stmtOk] at ok
  | setCall => intro tenv env st d h ok; simp [stmtOk] at ok
  | «then» first second ih1 ih2 =>
    intro tenv env st d h ok inv locs rel hq budget fr
    have ok' := ok
    simp only [stmtOk, Bool.and_eq_true] at ok'
    have hq' := hq
    simp only [qstmt] at hq'
    obtain ⟨d1, h1, h2, hq1, hrest, rfl⟩ := qthen_some hq'
    obtain ⟨c1, s1, ev1, dr1, ran1, g1, f1⟩ := ih1 ok'.1 inv locs rel hq1 (part (by aomega) budget) fr
    have stop : (∀ e, d1 ≠ .next e) → d = d1 ∧ h2 = 0 → ∃ c st', Ev (fun k => execStmt k sp.toCore st
        (SrcStmt.then first second).toCore) c st' ∧
        OutRel sp.toCore (boxElem sp prims) st'.heap ret tenv st' c d ∧ RanS st st' ∧
        st'.heap.nextAddress ≤ st.heap.nextAddress + (h1 + h2) ∧ st'.heap.remaining = none := by
      rintro hno ⟨rfl, rfl⟩
      have ev : Ev (fun k => execStmt k sp.toCore st (SrcStmt.then first second).toCore) c1 s1 := by
        simpa only [SrcStmt.toCore] using sequence_stop_fwd (b := second.toCore) (dr1.ne_next hno) ev1
      have g : s1.heap.nextAddress ≤ st.heap.nextAddress + (h1 + 0) := by aomega
      obtain ⟨dr, ran⟩ := stmt_rel calls ok inv locs rel (mstmt_of hq) ev (part g budget)
      exact ⟨_, _, ev, dr, ran, g, f1⟩
    cases d1 with
    | next e1 =>
      obtain ⟨rfl, rel1⟩ := dr1.of_next
      simp only [Out.qthen] at hrest
      obtain ⟨c, s2, ev2, -, -, g2, f2⟩ := ih2 ok'.2 ran1.inv (ran1.locs locs) rel1 hrest
        (part (by aomega) budget) f1
      have ev : Ev (fun k => execStmt k sp.toCore st (SrcStmt.then first second).toCore) c s2 := by
        simpa only [SrcStmt.toCore] using sequence_next_fwd ev1 ev2
      have g : s2.heap.nextAddress ≤ st.heap.nextAddress + (h1 + h2) := by aomega
      obtain ⟨dr, ran⟩ := stmt_rel calls ok inv locs rel (mstmt_of hq) ev (part g budget)
      exact ⟨_, _, ev, dr, ran, g, f2⟩
    | brk e1 =>
      simp only [Out.qthen, Option.some.injEq, Prod.mk.injEq] at hrest
      exact stop (fun _ h => by cases h) ⟨hrest.1.symm, hrest.2.symm⟩
    | cont e1 =>
      simp only [Out.qthen, Option.some.injEq, Prod.mk.injEq] at hrest
      exact stop (fun _ h => by cases h) ⟨hrest.1.symm, hrest.2.symm⟩
    | ret value =>
      simp only [Out.qthen, Option.some.injEq, Prod.mk.injEq] at hrest
      exact stop (fun _ h => by cases h) ⟨hrest.1.symm, hrest.2.symm⟩
  | «if» condition thenBranch elseBranch ih1 ih2 =>
    intro tenv env st d h ok inv locs rel hq budget fr
    have ok' := ok
    simp only [stmtOk, Bool.and_eq_true] at ok'
    obtain ⟨⟨hc, ok1⟩, ok2⟩ := ok'
    have htc := isBoolTy_some hc
    have hq' := hq
    simp only [qstmt, Option.bind_eq_some_iff] at hq'
    obtain ⟨b, ⟨cv, hcv, hb⟩, hbr⟩ := hq'
    obtain ⟨v, evc⟩ := expr_live (toCore_target sp) tenv env condition htc rel hcv
    obtain ⟨rfl, b', rfl⟩ : cv = v ∧ ∃ b', v = .boolean b' := (expr_rel htc rel hcv evc).scalar_ty rfl
    simp only [asBool, Option.some.injEq] at hb
    subst hb
    cases b' with
    | true =>
      simp only [if_true] at hbr
      obtain ⟨c, s2, ev2, -, -, g, fg⟩ := ih1 ok1 inv locs rel hbr budget fr
      have ev : Ev (fun k => execStmt k sp.toCore st (SrcStmt.if condition thenBranch elseBranch).toCore) c s2 := by
        simp only [SrcStmt.toCore]
        exact if_fwd evc (by simpa using ev2)
      obtain ⟨dr, ran⟩ := stmt_rel calls ok inv locs rel (mstmt_of hq) ev (part g budget)
      exact ⟨_, _, ev, dr, ran, g, fg⟩
    | false =>
      simp only [Bool.false_eq_true, if_false] at hbr
      obtain ⟨c, s2, ev2, -, -, g, fg⟩ := ih2 ok2 inv locs rel hbr budget fr
      have ev : Ev (fun k => execStmt k sp.toCore st (SrcStmt.if condition thenBranch elseBranch).toCore) c s2 := by
        simp only [SrcStmt.toCore]
        exact if_fwd evc (by simpa using ev2)
      obtain ⟨dr, ran⟩ := stmt_rel calls ok inv locs rel (mstmt_of hq) ev (part g budget)
      exact ⟨_, _, ev, dr, ran, g, fg⟩
  | «while» => intro tenv env st d h ok; simp [stmtOk] at ok
  | «return» value =>
    intro tenv env st d h ok inv locs rel hq budget fr
    have ok' := ok
    simp only [stmtOk] at ok'
    split at ok'
    · rename_i t ht
      have hq' := hq
      simp only [qstmt] at hq'
      obtain ⟨hm, rfl⟩ := qfree_some hq'
      simp only [Option.map_eq_some_iff] at hm
      obtain ⟨pv, hpv, rfl⟩ := hm
      obtain ⟨v, evv⟩ := expr_live (toCore_target sp) tenv env value ht rel hpv
      have ev : Ev (fun k => execStmt k sp.toCore st (SrcStmt.return value).toCore) (.returned (some v)) st := by
        simpa only [SrcStmt.toCore] using return_fwd evv
      have g : st.heap.nextAddress ≤ st.heap.nextAddress + 0 := by aomega
      obtain ⟨dr, ran⟩ := stmt_rel calls ok inv locs rel (mstmt_of hq) ev (part g budget)
      exact ⟨_, _, ev, dr, ran, g, fr⟩
    · simp at ok'
  | letAlloc => intro tenv env st d h ok; simp [stmtOk] at ok
  | letLoad => intro tenv env st d h ok; simp [stmtOk] at ok
  | setByte => intro tenv env st d h ok; simp [stmtOk] at ok
  | free => intro tenv env st d h ok; simp [stmtOk] at ok
  | letSlice => intro tenv env st d h ok; simp [stmtOk] at ok
  | letIndex => intro tenv env st d h ok; simp [stmtOk] at ok
  | setIndex => intro tenv env st d h ok; simp [stmtOk] at ok
  | letEval id ty value body ih =>
    intro tenv env st d h ok inv locs rel hq budget fr
    have ok' := ok
    simp only [stmtOk] at ok'
    split at ok'
    · rename_i t ht
      have hq' := hq
      simp only [qstmt] at hq'
      obtain ⟨pv, h1, h2, hpv, hb, rfl⟩ := qthen_some hq'
      obtain ⟨ob, hob, rfl⟩ := qpop_some hb
      obtain ⟨v, s1, ev1, r, ran1, g1, f1⟩ := eff_live calls live value ht inv rel hpv (part (by aomega) budget) fr
      have rel1 := rel.step ran1.step ran1.locals
      have locs1 := locs.step ran1.step ran1.locals
      obtain ⟨c, s2, evb, -, -, g2, f2⟩ := ih ok' (ran1.inv.bindLocal id v) (locs1.bindLocal ran1.inv id v)
        (rel1.bind ran1.inv r) hob
        (part (show s1.heap.nextAddress + h2 ≤ st.heap.nextAddress + (h1 + h2) by aomega) budget) f1
      have ev : Ev (fun k => execStmt k sp.toCore st (SrcStmt.letEval id ty value body).toCore) c
          (restoreLocals s1 s2) := by
        simpa only [SrcStmt.toCore] using letLocal_fwd (ty := ty.toCore) ev1 evb
      have g : (restoreLocals s1 s2).heap.nextAddress ≤ st.heap.nextAddress + (h1 + h2) := by
        show s2.heap.nextAddress ≤ _
        have g2' : s2.heap.nextAddress ≤ s1.heap.nextAddress + h2 := g2
        aomega
      obtain ⟨dr, ran⟩ := stmt_rel calls ok inv locs rel (mstmt_of hq) ev (part g budget)
      exact ⟨_, _, ev, dr, ran, g, f2⟩
    · simp at ok'
  | setEval id value =>
    intro tenv env st d h ok inv locs rel hq budget fr
    have ok' := ok
    simp only [stmtOk, setOk] at ok'
    split at ok'
    · rename_i t ht
      split at ok'
      · rename_i t' ht'
        rw [SrcType.same_eq ok'] at ht'
        have hq' := hq
        simp only [qstmt] at hq'
        obtain ⟨pv, h1, h2, hpv, hm, rfl⟩ := qthen_some hq'
        obtain ⟨-, rfl⟩ := qfree_some hm
        obtain ⟨v, s1, ev1, -, ran1, g1, f1⟩ := eff_live calls live value ht' inv rel hpv (part (by aomega) budget) fr
        obtain ⟨v0, -, hv0, -, -⟩ := rel id t ht
        obtain ⟨c, -, eva⟩ := setLocal_fwd hv0 ev1 ran1.inv.views fun c hc => ran1.step.frame.isSome (locs.alloc id c hc)
        have ev : Ev (fun k => execStmt k sp.toCore st (SrcStmt.setEval id value).toCore) .next (s1.assigned c v) := by
          simpa only [SrcStmt.toCore] using expression_fwd eva
        have g : (s1.assigned c v).heap.nextAddress ≤ st.heap.nextAddress + (h1 + 0) := by
          show s1.heap.nextAddress ≤ _
          aomega
        obtain ⟨dr, ran⟩ := stmt_rel calls ok inv locs rel (mstmt_of hq) ev (part g budget)
        exact ⟨_, _, ev, dr, ran, g, f1⟩
      · simp at ok'
    · simp at ok'
  | ifEval condition thenBranch elseBranch ih1 ih2 =>
    intro tenv env st d h ok inv locs rel hq budget fr
    have ok' := ok
    simp only [stmtOk, Bool.and_eq_true] at ok'
    obtain ⟨⟨hc, ok1⟩, ok2⟩ := ok'
    have htc := isBoolTy_some hc
    have hq' := hq
    simp only [qstmt] at hq'
    obtain ⟨cv, h1, h2, hcv, hbr, rfl⟩ := qthen_some hq'
    obtain ⟨v, s1, ev1, r, ran1, g1, f1⟩ := eff_live calls live condition htc inv rel hcv (part (by aomega) budget) fr
    obtain ⟨rfl, b, rfl⟩ : cv = v ∧ ∃ b, v = .boolean b := r.scalar_ty rfl
    simp only [asBool, Option.bind_some] at hbr
    cases b with
    | true =>
      simp only [if_true] at hbr
      obtain ⟨c, s2, ev2, -, -, g2, f2⟩ := ih1 ok1 ran1.inv (locs.step ran1.step ran1.locals)
        (rel.step ran1.step ran1.locals) hbr
        (part (by aomega) budget) f1
      have ev : Ev (fun k => execStmt k sp.toCore st (SrcStmt.ifEval condition thenBranch elseBranch).toCore) c s2 := by
        simp only [SrcStmt.toCore]
        exact if_fwd ev1 (by simpa using ev2)
      have g : s2.heap.nextAddress ≤ st.heap.nextAddress + (h1 + h2) := by aomega
      obtain ⟨dr, ran⟩ := stmt_rel calls ok inv locs rel (mstmt_of hq) ev (part g budget)
      exact ⟨_, _, ev, dr, ran, g, f2⟩
    | false =>
      simp only [Bool.false_eq_true, if_false] at hbr
      obtain ⟨c, s2, ev2, -, -, g2, f2⟩ := ih2 ok2 ran1.inv (locs.step ran1.step ran1.locals)
        (rel.step ran1.step ran1.locals) hbr
        (part (by aomega) budget) f1
      have ev : Ev (fun k => execStmt k sp.toCore st (SrcStmt.ifEval condition thenBranch elseBranch).toCore) c s2 := by
        simp only [SrcStmt.toCore]
        exact if_fwd ev1 (by simpa using ev2)
      have g : s2.heap.nextAddress ≤ st.heap.nextAddress + (h1 + h2) := by aomega
      obtain ⟨dr, ran⟩ := stmt_rel calls ok inv locs rel (mstmt_of hq) ev (part g budget)
      exact ⟨_, _, ev, dr, ran, g, f2⟩
  | whileEval => intro tenv env st d h ok; simp [stmtOk] at ok
  | returnEval value =>
    intro tenv env st d h ok inv locs rel hq budget fr
    have ok' := ok
    simp only [stmtOk] at ok'
    split at ok'
    · rename_i t ht
      have hq' := hq
      simp only [qstmt] at hq'
      obtain ⟨pv, h1, h2, hpv, last, rfl⟩ := qthen_some hq'
      simp only [Option.some.injEq, Prod.mk.injEq] at last
      obtain ⟨rfl, rfl⟩ := last
      obtain ⟨v, s1, ev1, -, -, g1, f1⟩ := eff_live calls live value ht inv rel hpv (part (by aomega) budget) fr
      have ev : Ev (fun k => execStmt k sp.toCore st (SrcStmt.returnEval value).toCore) (.returned (some v)) s1 := by
        simpa only [SrcStmt.toCore] using return_fwd ev1
      have g : s1.heap.nextAddress ≤ st.heap.nextAddress + (h1 + 0) := by aomega
      obtain ⟨dr, ran⟩ := stmt_rel calls ok inv locs rel (mstmt_of hq) ev (part g budget)
      exact ⟨_, _, ev, dr, ran, g, f1⟩
    · simp at ok'
  | discard value =>
    intro tenv env st d h ok inv locs rel hq budget fr
    have ok' := ok
    simp only [stmtOk, Option.isSome_iff_exists] at ok'
    obtain ⟨t, ht⟩ := ok'
    have hq' := hq
    simp only [qstmt] at hq'
    obtain ⟨pv, h1, h2, hpv, last, rfl⟩ := qthen_some hq'
    simp only [Option.some.injEq, Prod.mk.injEq] at last
    obtain ⟨rfl, rfl⟩ := last
    obtain ⟨v, s1, ev1, -, -, g1, f1⟩ := eff_live calls live value ht inv rel hpv (part (by aomega) budget) fr
    have ev : Ev (fun k => execStmt k sp.toCore st (SrcStmt.discard value).toCore) .next s1 := by
      simpa only [SrcStmt.toCore] using expression_fwd ev1
    have g : s1.heap.nextAddress ≤ st.heap.nextAddress + (h1 + 0) := by aomega
    obtain ⟨dr, ran⟩ := stmt_rel calls ok inv locs rel (mstmt_of hq) ev (part g budget)
    exact ⟨_, _, ev, dr, ran, g, f1⟩
  | setIndexEval => intro tenv env st d h ok; simp [stmtOk] at ok
  | setFieldEval => intro tenv env st d h ok; simp [stmtOk] at ok
  | «break» => intro tenv env st d h ok; simp [stmtOk] at ok
  | «continue» => intro tenv env st d h ok; simp [stmtOk] at ok
  | matchArm => intro tenv env st d h ok; simp [stmtOk] at ok
  | unreachable => intro tenv env st d h ok; simp [stmtOk] at ok
  | returnUnit =>
    intro tenv env st d h ok inv locs rel hq budget fr
    have hq' := hq
    simp only [qstmt, Option.some.injEq, Prod.mk.injEq] at hq'
    obtain ⟨rfl, rfl⟩ := hq'
    have ev : Ev (fun k => execStmt k sp.toCore st SrcStmt.returnUnit.toCore) (.returned none) st := by
      simpa only [SrcStmt.toCore] using returnUnit_fwd
    have g : st.heap.nextAddress ≤ st.heap.nextAddress + 0 := by aomega
    obtain ⟨dr, ran⟩ := stmt_rel calls ok inv locs rel (mstmt_of hq) ev (part g budget)
    exact ⟨_, _, ev, dr, ran, g, fr⟩
  | «assert» condition =>
    intro tenv env st d h ok inv locs rel hq budget fr
    have ok' := ok
    simp only [stmtOk] at ok'
    have htc := isBoolTy_some ok'
    have hq' := hq
    simp only [qstmt] at hq'
    obtain ⟨cv, h1, h2, hcv, hbr, rfl⟩ := qthen_some hq'
    obtain ⟨v, s1, ev1, r, -, g1, f1⟩ := eff_live calls live condition htc inv rel hcv (part (by aomega) budget) fr
    obtain ⟨rfl, b, rfl⟩ : cv = v ∧ ∃ b, v = .boolean b := r.scalar_ty rfl
    cases b with
    | false => simp [asBool] at hbr
    | true =>
      simp only [asBool, Option.bind_some, if_true, Option.some.injEq, Prod.mk.injEq] at hbr
      obtain ⟨rfl, rfl⟩ := hbr
      have ev : Ev (fun k => execStmt k sp.toCore st (SrcStmt.assert condition).toCore) .next s1 := by
        simpa only [SrcStmt.toCore] using expression_fwd (assert_fwd ev1)
      have g : s1.heap.nextAddress ≤ st.heap.nextAddress + (h1 + 0) := by aomega
      obtain ⟨dr, ran⟩ := stmt_rel calls ok inv locs rel (mstmt_of hq) ev (part g budget)
      exact ⟨_, _, ev, dr, ran, g, f1⟩

end

end Lanius.Faithful
