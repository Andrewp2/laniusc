import Lanius.Faithful.Sim.EffStep

/-! # Statements

A statement `stmtOk` accepts, that Core completes with fuel `k ≤ N`, ends as
`pstmt` with calls `pcall N` says (`stmt_sim`), when Core's calls with less
fuel than `N` have their pure values. So a pure function's body does
(`body_sim`). -/

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

section
variable {sp : SrcProgram} {prims : Prims} {outside : List Nat} {N : Nat}

theorem effOk {j : Nat} (lt : j < N) (calls : ∀ i < N, FuncSim sp prims outside i) : EffOk sp prims outside N j :=
  (eff_sim j (by omega) (fun i _ => calls i (by omega))).1

theorem stmt_sim (calls : ∀ i < N, FuncSim sp prims outside i) (ret : SrcType) (s : SrcStmt) :
    ∀ {k : Nat} {tenv : TEnv} {env : Env} {st : State} {c : Completion} {st' : State},
      k ≤ N → execStmt k sp.toCore st s.toCore = .done c st' →
      stmtOk sp outside (boxElem sp prims) ret tenv s = true →
      Inv st → EnvRel sp.toCore (boxElem sp prims) st.heap tenv env st → st'.heap.nextAddress ≤ 2 ^ 64 →
      ∃ d, pstmt (pcall sp prims N) env s = some d ∧ DoneRel sp.toCore (boxElem sp prims) st'.heap ret c d ∧
        Ran st st' := by
  induction s with
  | nop =>
    intro k tenv env st c st' le run ok inv rel bound
    obtain ⟨rfl, rfl⟩ := skip_inv run
    exact ⟨.next, rfl, trivial, .refl inv⟩
  | «let» id ty value body ih =>
    intro k tenv env st c st' le run ok inv rel bound
    obtain ⟨j, v, s1, s2, rfl, vrun, brun, rfl⟩ := letLocal_inv run
    have e := value.eval_state vrun
    subst s1
    simp only [stmtOk] at ok
    split at ok
    · rename_i t ht
      obtain ⟨p, hp, r⟩ := expr_sim (toCore_target sp) tenv env value vrun ht rel
      obtain ⟨d, hd, dr, ran⟩ := ih (by omega) brun ok (inv.bindLocal id v) (rel.bind inv r) bound
      refine ⟨d, by simp only [pstmt, hp, Option.bind_some, hd], dr,
        ⟨ran.inv.restore st, ((Step.bindLocal st id v).trans ran.step).restore st, rfl⟩⟩
    · simp at ok
  | letStruct id ty fields body ih =>
    intro k tenv env st c st' le run ok inv rel bound
    obtain ⟨j, v, s1, s2, rfl, vrun, brun, rfl⟩ := letLocal_inv run
    obtain ⟨i, vs, rfl, frun, rfl⟩ := structValue_inv vrun
    have e := evalExprs_state fields frun
    subst s1
    simp only [stmtOk] at ok
    split at ok
    · rename_i t ht
      simp only [Option.bind_eq_some_iff] at ht
      obtain ⟨ts, hts, hs⟩ := ht
      obtain ⟨sid, rfl, hb, rfl⟩ := structTy_some hs
      obtain ⟨ps, hps, rs⟩ := exprs_sim (toCore_target sp) tenv env fields frun hts rel
      have r : VRel sp.toCore (boxElem sp prims) st.heap (.struct sid ts) (.structure sid vs) (.structure sid ps) :=
        .struct hb rs
      obtain ⟨d, hd, dr, ran⟩ := ih (by omega) brun ok (inv.bindLocal id _) (rel.bind inv r) bound
      refine ⟨d, by simp only [pstmt, hps, Option.bind_some, SrcType.typeId, hd], dr,
        ⟨ran.inv.restore st, ((Step.bindLocal st id _).trans ran.step).restore st, rfl⟩⟩
    · simp at ok
  | letCall id ty callee args body ih =>
    intro k tenv env st c st' le run ok inv rel bound
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
      have b1 := Grows.bound (call_grows (grows sp _) vrun) g2 inv.views bound
      obtain ⟨w, hw, rw, invc, stepc⟩ := calls i (by omega) found notOut len inv
        (show completed.heap.nextAddress ≤ 2 ^ 64 from b1) rs bodyRun result
      have inv1 : Inv (restoreLocals st completed) := invc.restore st
      have rel1 := rel.step (stepc.restore st) rfl
      obtain ⟨d, hd, dr, ran⟩ := ih (by omega) brun ok (inv1.bindLocal id v) (rel1.bind inv1 rw) bound
      refine ⟨d, ?_, dr, ⟨ran.inv.restore _, ((stepc.restore st).trans
        ((Step.bindLocal _ id v).trans ran.step)).restore _, rfl⟩⟩
      simp only [pstmt, hps, Option.bind_some, pcall_mono sp prims _ hw (by omega : i + 1 ≤ N), hd]
    · simp at ok
  | letEnum id ty variant payload body ih =>
    intro k tenv env st c st' le run ok inv rel bound
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
      obtain ⟨d, hd, dr, ran⟩ := ih (by omega) brun ok (inv.bindLocal id _) (rel.bind inv r) bound
      refine ⟨d, by simp only [pstmt, hps, Option.bind_some, SrcType.typeId, hd], dr,
        ⟨ran.inv.restore st, ((Step.bindLocal st id _).trans ran.step).restore st, rfl⟩⟩
    · simp at ok
  | letMatch => intro k tenv env st c st' le run ok; simp [stmtOk] at ok
  | set => intro k tenv env st c st' le run ok; simp [stmtOk] at ok
  | setField => intro k tenv env st c st' le run ok; simp [stmtOk] at ok
  | setCall => intro k tenv env st c st' le run ok; simp [stmtOk] at ok
  | «then» first second ih1 ih2 =>
    intro k tenv env st c st' le run ok inv rel bound
    simp only [stmtOk, Bool.and_eq_true] at ok
    simp only [SrcStmt.toCore] at run
    obtain ⟨j, s1, c1, rfl, frun, rest⟩ := sequence_inv run
    rcases rest with ⟨rfl, srun⟩ | ⟨ne, rfl, rfl⟩
    · have b1 := Grows.bound (execStmt_grows frun) (execStmt_grows srun) inv.views bound
      obtain ⟨d1, hd1, dr1, ran1⟩ := ih1 (by omega) frun ok.1 inv rel b1
      cases d1 with
      | ret _ => exact dr1.elim
      | next =>
        obtain ⟨d, hd, dr, ran2⟩ := ih2 (by omega) srun ok.2 ran1.inv (rel.step ran1.step ran1.locals) bound
        exact ⟨d, by simp only [pstmt, hd1, Option.bind_some, Done.then, hd], dr, ran1.trans ran2⟩
    · obtain ⟨d1, hd1, dr1, ran1⟩ := ih1 (by omega) frun ok.1 inv rel bound
      cases d1 with
      | next => exact absurd dr1.next_inv ne
      | ret value => exact ⟨.ret value, by simp only [pstmt, hd1, Option.bind_some, Done.then], dr1, ran1⟩
  | «if» condition thenBranch elseBranch ih1 ih2 =>
    intro k tenv env st c st' le run ok inv rel bound
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
      obtain ⟨d, hd, dr, ran⟩ := ih1 (by omega) brun ok1 inv rel bound
      exact ⟨d, by simp only [pstmt, hp, Option.bind_some, asBool, if_true, hd], dr, ran⟩
    | false =>
      obtain ⟨d, hd, dr, ran⟩ := ih2 (by omega) brun ok2 inv rel bound
      exact ⟨d, by simp only [pstmt, hp, Option.bind_some, asBool, Bool.false_eq_true, if_false, hd], dr, ran⟩
  | «while» => intro k tenv env st c st' le run ok; simp [stmtOk] at ok
  | «return» value =>
    intro k tenv env st c st' le run ok inv rel bound
    simp only [SrcStmt.toCore] at run
    obtain ⟨j, v, rfl, vrun, rfl⟩ := return_inv run
    have e := value.eval_state vrun
    subst st'
    simp only [stmtOk] at ok
    split at ok
    · rename_i t ht
      obtain ⟨p, hp, r⟩ := expr_sim (toCore_target sp) tenv env value vrun ht rel
      rw [SrcType.same_eq ok] at r
      exact ⟨.ret (some p), by simp [pstmt, hp], r, .refl inv⟩
    · simp at ok
  | letAlloc => intro k tenv env st c st' le run ok; simp [stmtOk] at ok
  | letLoad => intro k tenv env st c st' le run ok; simp [stmtOk] at ok
  | setByte => intro k tenv env st c st' le run ok; simp [stmtOk] at ok
  | free => intro k tenv env st c st' le run ok; simp [stmtOk] at ok
  | letSlice => intro k tenv env st c st' le run ok; simp [stmtOk] at ok
  | letIndex => intro k tenv env st c st' le run ok; simp [stmtOk] at ok
  | setIndex => intro k tenv env st c st' le run ok; simp [stmtOk] at ok
  | letEval id ty value body ih =>
    intro k tenv env st c st' le run ok inv rel bound
    obtain ⟨j, v, s1, s2, rfl, vrun, brun, rfl⟩ := letLocal_inv run
    simp only [stmtOk] at ok
    split at ok
    · rename_i t ht
      have g2 : Grows s1 s2 :=
        (Grows.same (st := s1) (st' := s1.bindLocal id v) rfl rfl).trans (execStmt_grows brun)
      have b1 := Grows.bound (effGrows vrun) g2 inv.views bound
      obtain ⟨p, hp, r, ran1⟩ := effOk (by omega) calls vrun ht inv rel b1
      have rel1 := rel.step ran1.step ran1.locals
      obtain ⟨d, hd, dr, ran⟩ := ih (by omega) brun ok (ran1.inv.bindLocal id v) (rel1.bind ran1.inv r) bound
      refine ⟨d, by simp only [pstmt, hp, Option.bind_some, hd], dr,
        ⟨ran.inv.restore s1, (ran1.step.trans ((Step.bindLocal s1 id v).trans ran.step)).restore s1,
          ran1.locals⟩⟩
    · simp at ok
  | setEval => intro k tenv env st c st' le run ok; simp [stmtOk] at ok
  | ifEval condition thenBranch elseBranch ih1 ih2 =>
    intro k tenv env st c st' le run ok inv rel bound
    simp only [stmtOk, Bool.and_eq_true] at ok
    obtain ⟨⟨hc, ok1⟩, ok2⟩ := ok
    have htc := isBoolTy_some hc
    simp only [SrcStmt.toCore] at run
    obtain ⟨j, s1, x, rfl, crun, brun⟩ := if_inv run
    cases x with
    | true =>
      simp only [if_true] at brun
      have b1 := Grows.bound (effGrows crun) (execStmt_grows brun) inv.views bound
      obtain ⟨p, hp, r, ran1⟩ := effOk (by omega) calls crun htc inv rel b1
      rw [r.boolean] at hp
      obtain ⟨d, hd, dr, ran⟩ := ih1 (by omega) brun ok1 ran1.inv (rel.step ran1.step ran1.locals) bound
      exact ⟨d, by simp only [pstmt, hp, Option.bind_some, asBool, if_true, hd], dr, ran1.trans ran⟩
    | false =>
      simp only [Bool.false_eq_true, if_false] at brun
      have b1 := Grows.bound (effGrows crun) (execStmt_grows brun) inv.views bound
      obtain ⟨p, hp, r, ran1⟩ := effOk (by omega) calls crun htc inv rel b1
      rw [r.boolean] at hp
      obtain ⟨d, hd, dr, ran⟩ := ih2 (by omega) brun ok2 ran1.inv (rel.step ran1.step ran1.locals) bound
      exact ⟨d, by simp only [pstmt, hp, Option.bind_some, asBool, Bool.false_eq_true, if_false, hd], dr,
        ran1.trans ran⟩
  | whileEval => intro k tenv env st c st' le run ok; simp [stmtOk] at ok
  | returnEval value =>
    intro k tenv env st c st' le run ok inv rel bound
    simp only [SrcStmt.toCore] at run
    obtain ⟨j, v, rfl, vrun, rfl⟩ := return_inv run
    simp only [stmtOk] at ok
    split at ok
    · rename_i t ht
      obtain ⟨p, hp, r, ran⟩ := effOk (by omega) calls vrun ht inv rel bound
      rw [SrcType.same_eq ok] at r
      exact ⟨.ret (some p), by simp [pstmt, hp], r, ran⟩
    · simp at ok
  | discard value =>
    intro k tenv env st c st' le run ok inv rel bound
    simp only [stmtOk, Option.isSome_iff_exists] at ok
    obtain ⟨t, ht⟩ := ok
    simp only [SrcStmt.toCore] at run
    obtain ⟨j, v, rfl, vrun, rfl⟩ := expression_inv run
    obtain ⟨p, hp, -, ran⟩ := effOk (by omega) calls vrun ht inv rel bound
    exact ⟨.next, by simp [pstmt, hp], trivial, ran⟩
  | setIndexEval => intro k tenv env st c st' le run ok; simp [stmtOk] at ok
  | setFieldEval => intro k tenv env st c st' le run ok; simp [stmtOk] at ok
  | «break» => intro k tenv env st c st' le run ok; simp [stmtOk] at ok
  | «continue» => intro k tenv env st c st' le run ok; simp [stmtOk] at ok
  | matchArm => intro k tenv env st c st' le run ok; simp [stmtOk] at ok
  | returnUnit =>
    intro k tenv env st c st' le run ok inv rel bound
    simp only [SrcStmt.toCore] at run
    obtain ⟨rfl, rfl⟩ := returnUnit_inv run
    exact ⟨.ret none, rfl, trivial, .refl inv⟩
  | «assert» condition =>
    intro k tenv env st c st' le run ok inv rel bound
    simp only [stmtOk] at ok
    have ht := isBoolTy_some ok
    simp only [SrcStmt.toCore] at run
    obtain ⟨j, w, rfl, arun, rfl⟩ := expression_inv run
    obtain ⟨i, rfl, crun, rfl⟩ := assert_inv arun
    obtain ⟨p, hp, r, ran⟩ := effOk (by omega) calls crun ht inv rel bound
    rw [r.boolean] at hp
    exact ⟨.next, by simp [pstmt, hp, asBool], trivial, ran⟩

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
  obtain ⟨d, hd, dr, ran⟩ := stmt_sim calls f.ret f.body (Nat.le_refl m) run pure entryInv rel bound
  have step : Step st completed := ((Step.clear st).trans (Step.bindLocals _ _)).trans ran.step
  have plen : ps.length = f.params.length := by simpa using args.length.2
  have unfold : pcall sp prims (m + 1) c ps = (pstmt (pcall sp prims m) (paramEnv f.params ps) f.body).bind
      (doneValue f.ret) := by
    simp only [pcall, notPrim, Bool.false_eq_true, if_false, found, plen, if_true]
  rw [unfold, hd, Option.bind_some]
  cases compl with
  | next =>
    obtain ⟨hr, rfl⟩ := result
    rw [hr]
    cases d with
    | next => exact ⟨.unit, by simp [doneValue, SrcType.toCore], .scalar rfl, ran.inv, step⟩
    | ret => exact dr.elim
  | returned value =>
    cases value with
    | none =>
      obtain ⟨hr, rfl⟩ := result
      rw [hr]
      cases d with
      | next => exact dr.elim
      | ret dv =>
        cases dv with
        | none => exact ⟨.unit, by simp [doneValue, SrcType.toCore], .scalar rfl, ran.inv, step⟩
        | some => exact dr.elim
    | some x =>
      subst result
      cases d with
      | next => exact dr.elim
      | ret dv =>
        cases dv with
        | none => exact dr.elim
        | some p => exact ⟨p, rfl, dr, ran.inv, step⟩
  | breakLoop => exact result.elim
  | continueLoop => exact result.elim

end

end Lanius.Faithful
