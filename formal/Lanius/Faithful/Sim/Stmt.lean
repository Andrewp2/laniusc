module

public import Lanius.Faithful.Sim.EffStep
public import Lanius.Faithful.Sim.Frame

@[expose] public section
/-! # Statements

A statement `stmtOk` accepts, that Core completes with fuel `k ≤ N`, ends as
`mstmt` with calls `pcall N` and loop fuel `N` says, in an environment that
means Core's locals (`stmt_sim`), when Core's calls with less fuel than `N`
have their pure values. So a pure function's body does (`body_sim`). -/

namespace Lanius.Faithful

open Lanius.Mini
open Lanius.Core (Value)
open Lanius.Semantics (State Completion evalExpr evalExprs execStmt restoreLocals)

/-- A Core completion and the pure ending of the same statement. -/
def DoneRel (P : Core.Program) (boxes : Boxes) (heap : Memory.Heap) (ret : SrcType) : Completion → Done → Prop
  | .next, .next => True
  | .next, .ret _ => False
  | .returned none, .ret none => True
  | .returned (some v), .ret (some p) => VRel P boxes heap ret v p
  | .returned none, .ret (some _) => False
  | .returned (some _), .ret none => False
  | .returned _, .next => False
  | .breakLoop, _ => False
  | .continueLoop, _ => False

theorem DoneRel.next_inv {P : Core.Program} {boxes : Boxes} {heap : Memory.Heap} {ret : SrcType} {c : Completion}
    (dr : DoneRel P boxes heap ret c .next) : c = .next := by
  cases c with
  | next => rfl
  | returned value => cases value <;> exact dr.elim
  | breakLoop => exact dr.elim
  | continueLoop => exact dr.elim

theorem EnvRel.heap_eq {P : Core.Program} {boxes : Boxes} {heap heap' : Memory.Heap} {tenv : TEnv} {env : Env}
    {st : State} (h : heap = heap') (r : EnvRel P boxes heap tenv env st) : EnvRel P boxes heap' tenv env st :=
  h ▸ r

/-- A Core completion and the pure ending of the same statement: the
environment it left means Core's locals, or the returned values agree. -/
def OutRel (P : Core.Program) (boxes : Boxes) (heap : Memory.Heap) (ret : SrcType) (tenv : TEnv) (st : State) :
    Completion → Out → Prop
  | .next, .next e => EnvRel P boxes heap tenv e st
  | .breakLoop, .brk e => EnvRel P boxes heap tenv e st
  | .continueLoop, .cont e => EnvRel P boxes heap tenv e st
  | .returned v, .ret p => DoneRel P boxes heap ret (.returned v) (.ret p)
  | .next, .brk _ | .next, .cont _ | .next, .ret _ => False
  | .breakLoop, .next _ | .breakLoop, .cont _ | .breakLoop, .ret _ => False
  | .continueLoop, .next _ | .continueLoop, .brk _ | .continueLoop, .ret _ => False
  | .returned _, .next _ | .returned _, .brk _ | .returned _, .cont _ => False

/-- What a completed statement kept: the invariant, a frame, the locals. -/
structure RanS (st st' : State) : Prop where
  inv : Inv st'
  frame : Frame st st'
  locals : st'.locals = st.locals

theorem RanS.refl {st : State} (inv : Inv st) : RanS st st := ⟨inv, Frame.refl st, rfl⟩

theorem RanS.trans {a b c : State} (first : RanS a b) (second : RanS b c) : RanS a c :=
  ⟨second.inv, first.frame.trans second.frame first.locals, second.locals.trans first.locals⟩

theorem Ran.toS {st st' : State} (ran : Ran st st') : RanS st st' := ⟨ran.inv, ran.step.frame, ran.locals⟩

theorem RanS.locs {st st' : State} (ran : RanS st st') (locs : Locs st) : Locs st' :=
  locs.frame ran.frame ran.locals

/-- A `let` that bound `id` in `st` and ran its body to `s`. -/
theorem RanS.unbind {st s : State} (inv : Inv st) {id : Nat} {v : Value} (ran : RanS (st.bindLocal id v) s) :
    RanS st (restoreLocals st s) :=
  ⟨ran.inv.restore st, Frame.unbind inv ran.frame, rfl⟩

theorem OutRel.next_inv {P : Core.Program} {boxes : Boxes} {heap : Memory.Heap} {ret : SrcType} {tenv : TEnv}
    {st : State} {o : Out} (r : OutRel P boxes heap ret tenv st .next o) :
    ∃ e, o = .next e ∧ EnvRel P boxes heap tenv e st := by
  cases o with
  | next e => exact ⟨e, rfl, r⟩
  | brk _ => exact r.elim
  | cont _ => exact r.elim
  | ret _ => exact r.elim

/-- A completion other than `next` passes a statement after it by. -/
theorem OutRel.then {P : Core.Program} {boxes : Boxes} {heap : Memory.Heap} {ret : SrcType} {tenv : TEnv}
    {st : State} {c : Completion} {o : Out} (r : OutRel P boxes heap ret tenv st c o) (ne : c ≠ .next)
    (k : Env → Option Out) : Out.then k o = some o := by
  cases c with
  | next => exact absurd rfl ne
  | breakLoop => cases o <;> first | rfl | exact r.elim
  | continueLoop => cases o <;> first | rfl | exact r.elim
  | returned _ => cases o <;> first | rfl | exact r.elim

/-- **After a `let`'s body**, its ending with the binding dropped means Core's. -/
theorem OutRel.pop {P : Core.Program} {boxes : Boxes} {ret : SrcType} {tenv : TEnv} {env : Env} {st s : State}
    {id : Nat} {t : SrcType} {v p : Value} {c : Completion} {o : Out}
    (inv : Inv st) (locs : Locs st) (rel0 : EnvRel P boxes st.heap tenv env st)
    (r : OutRel P boxes s.heap ret ((id, t) :: tenv) s c o)
    (ag : ∀ e, o.env? = some e → Agree [] ((id, p) :: env) e) (ran : RanS (st.bindLocal id v) s) :
    OutRel P boxes (restoreLocals st s).heap ret tenv (restoreLocals st s) c o.pop := by
  cases c with
  | next =>
    cases o with
    | next e => exact EnvRel.pop inv locs rel0 r (ag e rfl) ran.frame ran.locals
    | brk _ => exact r.elim
    | cont _ => exact r.elim
    | ret _ => exact r.elim
  | breakLoop =>
    cases o with
    | next _ => exact r.elim
    | brk e => exact EnvRel.pop inv locs rel0 r (ag e rfl) ran.frame ran.locals
    | cont _ => exact r.elim
    | ret _ => exact r.elim
  | continueLoop =>
    cases o with
    | next _ => exact r.elim
    | brk _ => exact r.elim
    | cont e => exact EnvRel.pop inv locs rel0 r (ag e rfl) ran.frame ran.locals
    | ret _ => exact r.elim
  | returned w =>
    cases o with
    | next _ => exact r.elim
    | brk _ => exact r.elim
    | cont _ => exact r.elim
    | ret q => exact r

section
variable {sp : SrcProgram} {prims : Prims} {outside : List Nat} {N : Nat}

theorem effOk {j : Nat} (lt : j < N) (calls : ∀ i < N, FuncSim sp prims outside i) : EffOk sp prims outside N j :=
  (eff_sim j (by omega) (fun i _ => calls i (by omega))).1

/-- **A loop** whose test and body end as their pure meanings say ends as `ploop` says. -/
theorem loop_sim {condC : Core.Expr} {body : SrcStmt} {test : Env → Option Bool} {ret : SrcType} {tenv : TEnv}
    (htest : ∀ {j : Nat} {env : Env} {st : State} {x : Bool} {s1 : State}, j < N →
      evalExpr j sp.toCore st condC = .done (.boolean x) s1 → Inv st →
      EnvRel sp.toCore (boxElem sp prims) st.heap tenv env st → s1.heap.nextAddress ≤ 2 ^ 64 →
      test env = some x ∧ EnvRel sp.toCore (boxElem sp prims) s1.heap tenv env s1 ∧ RanS st s1)
    (tgrows : ∀ {j : Nat} {st : State} {v : Value} {s1 : State}, evalExpr j sp.toCore st condC = .done v s1 →
      Grows st s1)
    (hbody : ∀ {j : Nat} {env : Env} {st : State} {c : Completion} {st' : State}, j < N →
      execStmt j sp.toCore st body.toCore = .done c st' → Inv st → Locs st →
      EnvRel sp.toCore (boxElem sp prims) st.heap tenv env st → st'.heap.nextAddress ≤ 2 ^ 64 →
      ∃ o, mstmt (pcall sp prims N) N env body = some o ∧
        OutRel sp.toCore (boxElem sp prims) st'.heap ret tenv st' c o ∧ RanS st st')
    (lgrows : ∀ {j : Nat} {st : State} {c : Completion} {st' : State},
      execStmt j sp.toCore st (.whileLoop condC body.toCore) = .done c st' → Grows st st') :
    ∀ (k : Nat) {env : Env} {st : State} {c : Completion} {st' : State}, k ≤ N →
      execStmt k sp.toCore st (.whileLoop condC body.toCore) = .done c st' →
      Inv st → Locs st → EnvRel sp.toCore (boxElem sp prims) st.heap tenv env st → st'.heap.nextAddress ≤ 2 ^ 64 →
      ∃ o, ploop test (fun e => mstmt (pcall sp prims N) N e body) k env = some o ∧
        OutRel sp.toCore (boxElem sp prims) st'.heap ret tenv st' c o ∧ RanS st st'
  | 0, _, _, _, _, _, run, _, _, _, _ => by simp [execStmt] at run
  | n + 1, env, st, c, st', le, run, inv, locs, rel, bound => by
    obtain ⟨j, s1, x, hj, crun, rest⟩ := while_inv run
    obtain rfl : j = n := by omega
    rcases rest with ⟨rfl, rfl, rfl⟩ | ⟨rfl, cb, s2, brun, more⟩
    · obtain ⟨ht, rel1, ran1⟩ := htest (by omega) crun inv rel bound
      exact ⟨.next env, by rw [ploop, ht]; rfl, rel1, ran1⟩
    · have g2 : Grows s2 st' := by
        rcases more with ⟨-, lrun⟩ | ⟨-, -, rfl⟩ | ⟨-, -, -, rfl⟩
        · exact lgrows lrun
        · exact Grows.refl _
        · exact Grows.refl _
      have b2 := Grows.bound (execStmt_grows brun) g2 bound
      have b1 := Grows.bound (tgrows crun) (execStmt_grows brun) b2
      obtain ⟨ht, rel1, ran1⟩ := htest (by omega) crun inv rel b1
      obtain ⟨ob, hob, orlb, ranb⟩ := hbody (by omega) brun ran1.inv (ran1.locs locs) rel1 b2
      rcases more with ⟨hcb, lrun⟩ | ⟨rfl, rfl, rfl⟩ | ⟨r, rfl, rfl, rfl⟩
      · have ran2 := ran1.trans ranb
        rcases hcb with rfl | rfl
        · obtain ⟨e, rfl, rel2⟩ := orlb.next_inv
          obtain ⟨o, ho, orl, ran⟩ := loop_sim htest tgrows hbody lgrows j (by omega) lrun ranb.inv
            (ran2.locs locs) rel2 bound
          exact ⟨o, by rw [ploop, ht]; simp only [Option.bind_some, if_true, hob]; exact ho, orl, ran2.trans ran⟩
        · cases ob with
          | next _ => exact orlb.elim
          | brk _ => exact orlb.elim
          | ret _ => exact orlb.elim
          | cont e =>
            obtain ⟨o, ho, orl, ran⟩ := loop_sim htest tgrows hbody lgrows j (by omega) lrun ranb.inv
              (ran2.locs locs) orlb bound
            exact ⟨o, by rw [ploop, ht]; simp only [Option.bind_some, if_true, hob]; exact ho, orl, ran2.trans ran⟩
      · cases ob with
        | next _ => exact orlb.elim
        | cont _ => exact orlb.elim
        | ret _ => exact orlb.elim
        | brk e =>
          exact ⟨.next e, by rw [ploop, ht]; simp only [Option.bind_some, if_true, hob], orlb, ran1.trans ranb⟩
      · cases ob with
        | next _ => exact orlb.elim
        | cont _ => exact orlb.elim
        | brk _ => exact orlb.elim
        | ret q =>
          exact ⟨.ret q, by rw [ploop, ht]; simp only [Option.bind_some, if_true, hob], orlb, ran1.trans ranb⟩

theorem stmt_sim (calls : ∀ i < N, FuncSim sp prims outside i) (ret : SrcType) (s : SrcStmt) :
    ∀ {k : Nat} {tenv : TEnv} {env : Env} {st : State} {c : Completion} {st' : State},
      k ≤ N → execStmt k sp.toCore st s.toCore = .done c st' →
      stmtOk sp outside (boxElem sp prims) ret tenv s = true →
      Inv st → Locs st → EnvRel sp.toCore (boxElem sp prims) st.heap tenv env st → st'.heap.nextAddress ≤ 2 ^ 64 →
      ∃ o, mstmt (pcall sp prims N) N env s = some o ∧
        OutRel sp.toCore (boxElem sp prims) st'.heap ret tenv st' c o ∧ RanS st st' := by
  induction s with
  | nop =>
    intro k tenv env st c st' le run ok inv locs rel bound
    obtain ⟨rfl, rfl⟩ := skip_inv run
    exact ⟨.next env, rfl, rel, .refl inv⟩
  | «let» id ty value body ih =>
    intro k tenv env st c st' le run ok inv locs rel bound
    obtain ⟨j, v, s1, s2, rfl, vrun, brun, rfl⟩ := letLocal_inv run
    have e := value.eval_state vrun
    subst s1
    simp only [stmtOk] at ok
    split at ok
    · rename_i t ht
      obtain ⟨p, hp, r⟩ := expr_sim (toCore_target sp) tenv env value vrun ht rel
      obtain ⟨o, ho, orl, ran⟩ :=
        ih (by omega) brun ok (inv.bindLocal id v) (locs.bindLocal inv id v) (rel.bind inv r) bound
      refine ⟨o.pop, by simp only [mstmt, hp, Option.bind_some, ho, Option.map_some],
        OutRel.pop inv locs rel orl (mstmt_agree _ _ body ho) ran, ran.unbind inv⟩
    · simp at ok
  | letStruct id ty fields body ih =>
    intro k tenv env st c st' le run ok inv locs rel bound
    obtain ⟨j, v, s1, s2, rfl, vrun, brun, rfl⟩ := letLocal_inv run
    simp only [stmtOk] at ok
    split at ok
    · rename_i t ht
      simp only [Option.bind_eq_some_iff] at ht
      obtain ⟨ts, hts, hs⟩ := ht
      obtain ⟨sid, rfl, hb, rfl⟩ := structTy_some hs
      simp only [SrcType.literal] at vrun
      obtain ⟨i, vs, rfl, frun, rfl⟩ := structValue_inv vrun
      have e := evalExprs_state fields frun
      subst s1
      obtain ⟨ps, hps, rs⟩ := exprs_sim (toCore_target sp) tenv env fields frun hts rel
      have r : VRel sp.toCore (boxElem sp prims) st.heap (.struct sid ts) (.structure sid vs) (.structure sid ps) :=
        .struct hb rs
      obtain ⟨o, ho, orl, ran⟩ :=
        ih (by omega) brun ok (inv.bindLocal id _) (locs.bindLocal inv id _) (rel.bind inv r) bound
      refine ⟨o.pop, by simp only [mstmt, hps, Option.bind_some, SrcType.typeId, ho, Option.map_some],
        OutRel.pop inv locs rel orl (mstmt_agree _ _ body ho) ran, ran.unbind inv⟩
    · simp at ok
  | letCall id ty callee args body ih =>
    intro k tenv env st c st' le run ok inv locs rel bound
    obtain ⟨j, v, s1, s2, rfl, vrun, brun, rfl⟩ := letLocal_inv run
    have inside : callee < sp.funcs.length := by
      simp only [stmtOk] at ok
      split at ok
      · rename_i t ht
        simp only [Option.bind_eq_some_iff] at ht
        obtain ⟨ts, hts, hc⟩ := ht
        obtain ⟨-, f', found', -, -⟩ := callTy_some hc
        exact inside_of found'
      · simp at ok
    obtain ⟨i, f, values, afterArgs, completed, cc, rfl, argsRun, found, len, bodyRun, result, rfl⟩ :=
      call_inv' inside vrun
    have e := evalExprs_state args argsRun
    subst afterArgs
    simp only [stmtOk] at ok
    split at ok
    · rename_i t ht
      simp only [Option.bind_eq_some_iff] at ht
      obtain ⟨ts, hts, hc⟩ := ht
      obtain ⟨notOut, f', found', rfl, rfl⟩ := callTy_some hc
      rw [found, Option.some.injEq] at found'
      subst found'
      obtain ⟨ps, hps, rs⟩ := exprs_sim (toCore_target sp) tenv env args argsRun hts rel
      have g2 : Grows (restoreLocals st completed) s2 :=
        (Grows.same (st := restoreLocals st completed) (st' := (restoreLocals st completed).bindLocal id v) rfl rfl).trans
          (execStmt_grows brun)
      have b1 := Grows.bound (call_grows (grows sp _) vrun) g2 bound
      obtain ⟨w, hw, rw, invc, stepc⟩ := calls i (by omega) found notOut len inv
        (show completed.heap.nextAddress ≤ 2 ^ 64 from b1) rs bodyRun result
      have inv1 : Inv (restoreLocals st completed) := invc.restore st
      have step1 : Step st (restoreLocals st completed) := stepc.restore st
      have rel1 := rel.step step1 rfl
      have locs1 : Locs (restoreLocals st completed) := locs.step step1 rfl
      obtain ⟨o, ho, orl, ran⟩ :=
        ih (by omega) brun ok (inv1.bindLocal id v) (locs1.bindLocal inv1 id v) (rel1.bind inv1 rw) bound
      refine ⟨o.pop, ?_, OutRel.pop inv1 locs1 rel1 orl (mstmt_agree _ _ body ho) ran,
        (⟨inv1, step1.frame, rfl⟩ : RanS st (restoreLocals st completed)).trans (ran.unbind inv1)⟩
      simp only [mstmt, hps, Option.bind_some, pcall_mono sp prims _ hw (by omega : i + 1 ≤ N), ho,
        Option.map_some]
    · simp at ok
  | letEnum id ty variant payload body ih =>
    intro k tenv env st c st' le run ok inv locs rel bound
    obtain ⟨j, v, s1, s2, rfl, vrun, brun, rfl⟩ := letLocal_inv run
    obtain ⟨i, vs, rfl, frun, rfl⟩ := enumValue_inv vrun
    have e := evalExprs_state payload frun
    subst s1
    simp only [stmtOk] at ok
    split at ok
    · rename_i t ht
      simp only [Option.bind_eq_some_iff] at ht
      obtain ⟨ts, hts, hs⟩ := ht
      obtain ⟨eid, variants, rfl, hk, rfl⟩ := variantTy_some hs
      obtain ⟨ps, hps, rs⟩ := exprs_sim (toCore_target sp) tenv env payload frun hts rel
      have r : VRel sp.toCore (boxElem sp prims) st.heap (.enum eid variants) (.enumeration eid variant vs)
          (.enumeration eid variant ps) := .enum hk rs
      obtain ⟨o, ho, orl, ran⟩ :=
        ih (by omega) brun ok (inv.bindLocal id _) (locs.bindLocal inv id _) (rel.bind inv r) bound
      refine ⟨o.pop, by simp only [mstmt, hps, Option.bind_some, SrcType.typeId, ho, Option.map_some],
        OutRel.pop inv locs rel orl (mstmt_agree _ _ body ho) ran, ran.unbind inv⟩
    · simp at ok
  | letMatch => intro k tenv env st c st' le run ok; simp [stmtOk] at ok
  | set id value =>
    intro k tenv env st c st' le run ok inv locs rel bound
    simp only [stmtOk, setOk] at ok
    split at ok
    · rename_i t ht
      split at ok
      · rename_i t' ht'
        rw [SrcType.same_eq ok] at ht'
        simp only [SrcStmt.toCore] at run
        obtain ⟨j, w0, rfl, arun, rfl⟩ := expression_inv run
        obtain ⟨i, cl, w, s1, rfl, hcl, vrun, -, -, hst⟩ := assignLocal_inv arun
        have e := value.eval_state vrun
        subst s1
        obtain rfl := assigned_eq (s := st.assigned cl w) inv.views hst
        obtain ⟨p, hp, r⟩ := expr_sim (toCore_target sp) tenv env value vrun ht' rel
        obtain ⟨-, q, -, hq, -⟩ := rel id t ht
        obtain ⟨e', he'⟩ := Env.set_isSome (env := env) (id := id) p (by rw [hq]; rfl)
        exact ⟨.next e', by simp only [mstmt, hp, Option.bind_some, he', Option.map_some],
          EnvRel.assign locs rel hcl ht r he', ⟨inv.assigned cl w, Frame.assigned hcl w, rfl⟩⟩
      · simp at ok
    · simp at ok
  | setField => intro k tenv env st c st' le run ok; simp [stmtOk] at ok
  | setCall => intro k tenv env st c st' le run ok; simp [stmtOk] at ok
  | «then» first second ih1 ih2 =>
    intro k tenv env st c st' le run ok inv locs rel bound
    simp only [stmtOk, Bool.and_eq_true] at ok
    simp only [SrcStmt.toCore] at run
    obtain ⟨j, s1, c1, rfl, frun, rest⟩ := sequence_inv run
    rcases rest with ⟨rfl, srun⟩ | ⟨ne, rfl, rfl⟩
    · have b1 := Grows.bound (execStmt_grows frun) (execStmt_grows srun) bound
      obtain ⟨o1, ho1, orl1, ran1⟩ := ih1 (by omega) frun ok.1 inv locs rel b1
      obtain ⟨e1, rfl, rel1⟩ := orl1.next_inv
      obtain ⟨o, ho, orl, ran2⟩ := ih2 (by omega) srun ok.2 ran1.inv (ran1.locs locs) rel1 bound
      exact ⟨o, by simp only [mstmt, ho1, Option.bind_some, Out.then, ho], orl, ran1.trans ran2⟩
    · obtain ⟨o1, ho1, orl1, ran1⟩ := ih1 (by omega) frun ok.1 inv locs rel bound
      exact ⟨o1, by simp only [mstmt, ho1, Option.bind_some, orl1.then ne], orl1, ran1⟩
  | «if» condition thenBranch elseBranch ih1 ih2 =>
    intro k tenv env st c st' le run ok inv locs rel bound
    simp only [stmtOk, Bool.and_eq_true] at ok
    obtain ⟨⟨hc, ok1⟩, ok2⟩ := ok
    have htc := isBoolTy_some hc
    simp only [SrcStmt.toCore] at run
    obtain ⟨j, s1, x, rfl, crun, brun⟩ := if_inv run
    have e := condition.eval_state crun
    subst s1
    obtain ⟨p, hp, r⟩ := expr_sim (toCore_target sp) tenv env condition crun htc rel
    rw [r.boolean] at hp
    cases x with
    | true =>
      obtain ⟨o, ho, orl, ran⟩ := ih1 (by omega) brun ok1 inv locs rel bound
      exact ⟨o, by simp only [mstmt, hp, Option.bind_some, asBool, if_true, ho], orl, ran⟩
    | false =>
      obtain ⟨o, ho, orl, ran⟩ := ih2 (by omega) brun ok2 inv locs rel bound
      exact ⟨o, by simp only [mstmt, hp, Option.bind_some, asBool, Bool.false_eq_true, if_false, ho], orl, ran⟩
  | «while» condition body ih =>
    intro k tenv env st c st' le run ok inv locs rel bound
    simp only [stmtOk, Bool.and_eq_true] at ok
    obtain ⟨hc, okb⟩ := ok
    have htc := isBoolTy_some hc
    simp only [SrcStmt.toCore] at run
    obtain ⟨o, ho, orl, ran⟩ := loop_sim (test := fun e => (pexpr e condition).bind asBool)
      (fun _ crun inv rel _ => by
        have e := condition.eval_state crun
        subst e
        obtain ⟨p, hp, r⟩ := expr_sim (toCore_target sp) tenv _ condition crun htc rel
        rw [r.boolean] at hp
        exact ⟨by simp only [hp, Option.bind_some, asBool], rel, .refl inv⟩)
      (fun crun => by
        have e := condition.eval_state crun
        subst e
        exact Grows.refl _)
      (fun _ brun inv locs rel bound => ih (by omega) brun okb inv locs rel bound)
      (fun lrun => execStmt_grows (s := .while condition body) lrun) k le run inv locs rel bound
    exact ⟨o, by simp only [mstmt]; exact ploop_mono (fun _ _ h => h) (fun _ _ h => h) le ho, orl, ran⟩
  | «return» value =>
    intro k tenv env st c st' le run ok inv locs rel bound
    simp only [SrcStmt.toCore] at run
    obtain ⟨j, v, rfl, vrun, rfl⟩ := return_inv run
    have e := value.eval_state vrun
    subst st'
    simp only [stmtOk] at ok
    split at ok
    · rename_i t ht
      obtain ⟨p, hp, r⟩ := expr_sim (toCore_target sp) tenv env value vrun ht rel
      rw [SrcType.same_eq ok] at r
      exact ⟨.ret (some p), by simp [mstmt, hp], r, .refl inv⟩
    · simp at ok
  | letAlloc => intro k tenv env st c st' le run ok; simp [stmtOk] at ok
  | letView => intro k tenv env st c st' le run ok; simp [stmtOk] at ok
  | letStr => intro k tenv env st c st' le run ok; simp [stmtOk] at ok
  | letLoad => intro k tenv env st c st' le run ok; simp [stmtOk] at ok
  | setByte => intro k tenv env st c st' le run ok; simp [stmtOk] at ok
  | free => intro k tenv env st c st' le run ok; simp [stmtOk] at ok
  | letSlice => intro k tenv env st c st' le run ok; simp [stmtOk] at ok
  | letIndex => intro k tenv env st c st' le run ok; simp [stmtOk] at ok
  | setIndex => intro k tenv env st c st' le run ok; simp [stmtOk] at ok
  | letEval id ty value body ih =>
    intro k tenv env st c st' le run ok inv locs rel bound
    obtain ⟨j, v, s1, s2, rfl, vrun, brun, rfl⟩ := letLocal_inv run
    simp only [stmtOk] at ok
    split at ok
    · rename_i t ht
      have g2 : Grows s1 s2 :=
        (Grows.same (st := s1) (st' := s1.bindLocal id v) rfl rfl).trans (execStmt_grows brun)
      have b1 := Grows.bound (effGrows vrun) g2 bound
      obtain ⟨p, hp, r, ran1⟩ := effOk (by omega) calls vrun ht inv rel b1
      have rel1 := rel.step ran1.step ran1.locals
      have locs1 := locs.step ran1.step ran1.locals
      obtain ⟨o, ho, orl, ran⟩ :=
        ih (by omega) brun ok (ran1.inv.bindLocal id v) (locs1.bindLocal ran1.inv id v) (rel1.bind ran1.inv r) bound
      refine ⟨o.pop, by simp only [mstmt, hp, Option.bind_some, ho, Option.map_some],
        OutRel.pop ran1.inv locs1 rel1 orl (mstmt_agree _ _ body ho) ran, ran1.toS.trans ?_⟩
      have u := ran.unbind ran1.inv
      exact ⟨u.inv, u.frame, by simp [restoreLocals]⟩
    · simp at ok
  | setEval id value =>
    intro k tenv env st c st' le run ok inv locs rel bound
    simp only [stmtOk, setOk] at ok
    split at ok
    · rename_i t ht
      split at ok
      · rename_i t' ht'
        rw [SrcType.same_eq ok] at ht'
        simp only [SrcStmt.toCore] at run
        obtain ⟨j, w0, rfl, arun, rfl⟩ := expression_inv run
        obtain ⟨i, cl, w, s1, rfl, hcl, vrun, -, -, hst⟩ := assignLocal_inv arun
        have b1 : s1.heap.nextAddress ≤ 2 ^ 64 := by
          rcases hst with rfl | hs
          · exact bound
          · exact (syncTo_heap hs).2 ▸ bound
        obtain ⟨p, hp, r, ran1⟩ := effOk (by omega) calls vrun ht' inv rel b1
        obtain rfl := assigned_eq (s := s1.assigned cl w) ran1.inv.views hst
        have rel1 := rel.step ran1.step ran1.locals
        have locs1 := locs.step ran1.step ran1.locals
        have hcl1 : s1.cellId? id = some cl := by rw [← hcl]; simp [State.cellId?, ran1.locals]
        obtain ⟨-, q, -, hq, -⟩ := rel id t ht
        obtain ⟨e', he'⟩ := Env.set_isSome (env := env) (id := id) p (by rw [hq]; rfl)
        exact ⟨.next e', by simp only [mstmt, hp, Option.bind_some, he', Option.map_some],
          EnvRel.assign locs1 rel1 hcl1 ht r he',
          ran1.toS.trans ⟨ran1.inv.assigned cl w, Frame.assigned hcl1 w, rfl⟩⟩
      · simp at ok
    · simp at ok
  | ifEval condition thenBranch elseBranch ih1 ih2 =>
    intro k tenv env st c st' le run ok inv locs rel bound
    simp only [stmtOk, Bool.and_eq_true] at ok
    obtain ⟨⟨hc, ok1⟩, ok2⟩ := ok
    have htc := isBoolTy_some hc
    simp only [SrcStmt.toCore] at run
    obtain ⟨j, s1, x, rfl, crun, brun⟩ := if_inv run
    cases x with
    | true =>
      simp only [if_true] at brun
      have b1 := Grows.bound (effGrows crun) (execStmt_grows brun) bound
      obtain ⟨p, hp, r, ran1⟩ := effOk (by omega) calls crun htc inv rel b1
      rw [r.boolean] at hp
      obtain ⟨o, ho, orl, ran⟩ :=
        ih1 (by omega) brun ok1 ran1.inv (locs.step ran1.step ran1.locals) (rel.step ran1.step ran1.locals) bound
      exact ⟨o, by simp only [mstmt, hp, Option.bind_some, asBool, if_true, ho], orl, ran1.toS.trans ran⟩
    | false =>
      simp only [Bool.false_eq_true, if_false] at brun
      have b1 := Grows.bound (effGrows crun) (execStmt_grows brun) bound
      obtain ⟨p, hp, r, ran1⟩ := effOk (by omega) calls crun htc inv rel b1
      rw [r.boolean] at hp
      obtain ⟨o, ho, orl, ran⟩ :=
        ih2 (by omega) brun ok2 ran1.inv (locs.step ran1.step ran1.locals) (rel.step ran1.step ran1.locals) bound
      exact ⟨o, by simp only [mstmt, hp, Option.bind_some, asBool, Bool.false_eq_true, if_false, ho], orl,
        ran1.toS.trans ran⟩
  | whileEval condition body ih =>
    intro k tenv env st c st' le run ok inv locs rel bound
    simp only [stmtOk, Bool.and_eq_true] at ok
    obtain ⟨hc, okb⟩ := ok
    have htc := isBoolTy_some hc
    simp only [SrcStmt.toCore] at run
    obtain ⟨o, ho, orl, ran⟩ := loop_sim (test := fun e => (peff (pcall sp prims N) e condition).bind asBool)
      (fun lt crun inv rel b1 => by
        obtain ⟨p, hp, r, ran1⟩ := effOk lt calls crun htc inv rel b1
        rw [r.boolean] at hp
        exact ⟨by simp only [hp, Option.bind_some, asBool], rel.step ran1.step ran1.locals, ran1.toS⟩)
      (fun crun => effGrows crun)
      (fun _ brun inv locs rel bound => ih (by omega) brun okb inv locs rel bound)
      (fun lrun => execStmt_grows (s := .whileEval condition body) lrun) k le run inv locs rel bound
    exact ⟨o, by simp only [mstmt]; exact ploop_mono (fun _ _ h => h) (fun _ _ h => h) le ho, orl, ran⟩
  | returnEval value =>
    intro k tenv env st c st' le run ok inv locs rel bound
    simp only [SrcStmt.toCore] at run
    obtain ⟨j, v, rfl, vrun, rfl⟩ := return_inv run
    simp only [stmtOk] at ok
    split at ok
    · rename_i t ht
      obtain ⟨p, hp, r, ran⟩ := effOk (by omega) calls vrun ht inv rel bound
      rw [SrcType.same_eq ok] at r
      exact ⟨.ret (some p), by simp [mstmt, hp], r, ran.toS⟩
    · simp at ok
  | discard value =>
    intro k tenv env st c st' le run ok inv locs rel bound
    simp only [stmtOk, Option.isSome_iff_exists] at ok
    obtain ⟨t, ht⟩ := ok
    simp only [SrcStmt.toCore] at run
    obtain ⟨j, v, rfl, vrun, rfl⟩ := expression_inv run
    obtain ⟨p, hp, -, ran⟩ := effOk (by omega) calls vrun ht inv rel bound
    exact ⟨.next env, by simp [mstmt, hp], rel.step ran.step ran.locals, ran.toS⟩
  | setIndexEval => intro k tenv env st c st' le run ok; simp [stmtOk] at ok
  | setFieldEval => intro k tenv env st c st' le run ok; simp [stmtOk] at ok
  | setPlace => intro k tenv env st c st' le run ok; simp [stmtOk] at ok
  | setPlaceOp => intro k tenv env st c st' le run ok; simp [stmtOk] at ok
  | «break» =>
    intro k tenv env st c st' le run ok inv locs rel bound
    simp only [SrcStmt.toCore] at run
    obtain ⟨rfl, rfl⟩ := break_inv run
    exact ⟨.brk env, rfl, rel, .refl inv⟩
  | «continue» =>
    intro k tenv env st c st' le run ok inv locs rel bound
    simp only [SrcStmt.toCore] at run
    obtain ⟨rfl, rfl⟩ := continue_inv run
    exact ⟨.cont env, rfl, rel, .refl inv⟩
  | matchArm => intro k tenv env st c st' le run ok; simp [stmtOk] at ok
  | unreachable => intro k tenv env st c st' le run ok; simp [stmtOk] at ok
  | returnUnit =>
    intro k tenv env st c st' le run ok inv locs rel bound
    simp only [SrcStmt.toCore] at run
    obtain ⟨rfl, rfl⟩ := returnUnit_inv run
    exact ⟨.ret none, rfl, trivial, .refl inv⟩
  | «assert» condition =>
    intro k tenv env st c st' le run ok inv locs rel bound
    simp only [stmtOk] at ok
    have ht := isBoolTy_some ok
    simp only [SrcStmt.toCore] at run
    obtain ⟨j, w, rfl, arun, rfl⟩ := expression_inv run
    obtain ⟨i, rfl, crun, rfl⟩ := assert_inv arun
    obtain ⟨p, hp, r, ran⟩ := effOk (by omega) calls crun ht inv rel bound
    rw [r.boolean] at hp
    exact ⟨.next env, by simp [mstmt, hp, asBool], rel.step ran.step ran.locals, ran.toS⟩

/-- A pure function's body, called on arguments meaning `ps`, gives `pcall`'s value. -/
theorem body_sim {m : Nat} (calls : ∀ i < m, FuncSim sp prims outside i) {c : Nat} {f : SrcFunc}
    {values ps : List Value} {st completed : State} {compl : Completion} {v : Value}
    (found : sp.funcs[c]? = some f) (notPrim : prims.isPrim c = false)
    (pure : PureFunc sp prims outside f = true) (inv : Inv st)
    (bound : completed.heap.nextAddress ≤ 2 ^ 64)
    (args : VRels sp.toCore (boxElem sp prims) st.heap (f.params.map SrcParam.ty) values ps)
    (run : execStmt m sp.toCore (({ st with locals := [] } : State).bindLocals (paramBindings f.params values))
      f.body.toCore = .done compl completed)
    (result : CallResult f.ret compl v) :
    ∃ w, pcall sp prims (m + 1) c ps = some w ∧ VRel sp.toCore (boxElem sp prims) completed.heap f.ret v w ∧
      Inv completed ∧ Step st completed := by
  have entryInv := Inv.bindLocals (paramBindings f.params values) inv.clear
  have rel := EnvRel.heap_eq (bindLocals_same (paramBindings f.params values) { st with locals := [] }).1.symm
    (EnvRel.entry inv args)
  obtain ⟨o, ho, orl, ran⟩ :=
    stmt_sim calls f.ret f.body (Nat.le_refl m) run (PureFunc.stmt pure) entryInv (Locs.entry inv _) rel bound
  have entryStep := (Step.clear st).trans (Step.bindLocals (paramBindings f.params values) { st with locals := [] })
  have step : Step st completed :=
    ⟨Frame.callee inv _ ran.frame, entryStep.reads.trans ran.frame.reads, entryStep.ranges.trans ran.frame.ranges⟩
  have plen : ps.length = f.params.length := by simpa using args.length.2
  have unfold : pcall sp prims (m + 1) c ps =
      (mstmt (pcall sp prims m) m (paramEnv f.params ps) f.body).bind (outValue f.ret) := by
    simp only [pcall, notPrim, Bool.false_eq_true, if_false, found, plen, if_true]
  rw [unfold, ho, Option.bind_some]
  cases compl with
  | next =>
    obtain ⟨hr, rfl⟩ := result
    rw [hr]
    obtain ⟨e, rfl, -⟩ := orl.next_inv
    exact ⟨.unit, by simp [outValue, SrcType.toCore], .scalar rfl, ran.inv, step⟩
  | returned value =>
    cases o with
    | next _ => exact orl.elim
    | brk _ => exact orl.elim
    | cont _ => exact orl.elim
    | ret dv =>
      cases value with
      | none =>
        obtain ⟨hr, rfl⟩ := result
        rw [hr]
        cases dv with
        | none => exact ⟨.unit, by simp [outValue, SrcType.toCore], .scalar rfl, ran.inv, step⟩
        | some => exact orl.elim
      | some x =>
        subst result
        cases dv with
        | none => exact orl.elim
        | some p => exact ⟨p, rfl, orl, ran.inv, step⟩
  | breakLoop => exact result.elim
  | continueLoop => exact result.elim

end

end Lanius.Faithful
