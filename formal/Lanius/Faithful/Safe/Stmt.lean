import Lanius.Faithful.Sim.Stmt
import Lanius.Faithful.Safe.Eff

/-! # Statements do not trap undefined

A statement `stmtOk` accepts, that Core runs with fuel `k ≤ N` until it traps
within the heap bound, traps defined (`stmt_safe`), when Core's runs of
callees' bodies with less fuel than `N` do. So a pure function's body does
(`body_safe`). -/

namespace Lanius.Faithful

open Lanius.Mini
open Lanius.Core (Value)
open Lanius.Semantics (State Completion evalExpr evalExprs execStmt restoreLocals)

section
variable {sp : SrcProgram} {prims : Prims} {outside : List Nat} {N : Nat}

theorem stmt_safe (calls : ∀ m, FuncSim sp prims outside m) (funcs : ∀ i < N, FuncSafe sp prims outside i)
    (ret : SrcType) (s : SrcStmt) :
    ∀ {k : Nat} {tenv : TEnv} {env : Env} {st : State} {r : Lanius.Trap} {st' : State},
      k ≤ N → execStmt k sp.toCore st s.toCore = .trapped r st' →
      stmtOk sp outside (boxElem sp prims) ret tenv s = true →
      Inv st → EnvRel sp.toCore (boxElem sp prims) st.heap tenv env st → st'.heap.nextAddress ≤ 2 ^ 64 →
      undefinedTrap r = false := by
  have effS : ∀ {j}, j < N → EffSafe sp prims outside j := fun {j} lt =>
    (eff_safe calls j (fun i lt' => funcs i (by omega))).1
  have effD : ∀ {j}, EffOk sp prims outside j j := fun {j} =>
    (eff_sim j (Nat.le_refl j) (fun i _ => calls i)).1
  have stmtD := stmt_sim (N := N) (fun i _ => calls i)
  have target := toCore_target sp
  induction s with
  | nop =>
    intro k tenv env st r st' le run ok inv rel bound
    exact (skip_trap run).elim
  | «let» id ty value body ih =>
    intro k tenv env st r st' le run ok inv rel bound
    simp only [stmtOk] at ok
    split at ok
    · rename_i t ht
      obtain ⟨j, rfl, vrun | ⟨v, s1, s2, vrun, brun, rfl⟩⟩ := letLocal_trap_inv run
      · exact (expr_safe target tenv env value vrun ht rel).2
      · have e := value.eval_state vrun
        subst s1
        obtain ⟨p, -, r⟩ := expr_sim target tenv env value vrun ht rel
        exact ih (by omega) brun ok (inv.bindLocal id v) (rel.bind inv r) bound
    · simp at ok
  | letStruct id ty fields body ih =>
    intro k tenv env st r st' le run ok inv rel bound
    simp only [stmtOk] at ok
    split at ok
    · rename_i t ht
      simp only [Option.bind_eq_some_iff] at ht
      obtain ⟨ts, hts, hs⟩ := ht
      obtain ⟨sid, rfl, hb, rfl⟩ := structTy_some hs
      obtain ⟨j, rfl, vrun | ⟨v, s1, s2, vrun, brun, rfl⟩⟩ := letLocal_trap_inv run
      · obtain ⟨i, -, frun⟩ := structValue_trap_inv vrun
        exact (exprs_safe target tenv env fields frun hts rel).2
      · obtain ⟨i, vs, rfl, frun, rfl⟩ := structValue_inv vrun
        have e := evalExprs_state fields frun
        subst s1
        obtain ⟨ps, -, rs⟩ := exprs_sim target tenv env fields frun hts rel
        have r : VRel sp.toCore (boxElem sp prims) st.heap (.struct sid ts) (.structure sid vs) (.structure sid ps) :=
          .struct hb rs
        exact ih (by omega) brun ok (inv.bindLocal id _) (rel.bind inv r) bound
    · simp at ok
  | letCall id ty callee args body ih =>
    intro k tenv env st r st' le run ok inv rel bound
    simp only [stmtOk] at ok
    split at ok
    · rename_i t ht
      simp only [Option.bind_eq_some_iff] at ht
      obtain ⟨ts, hts, hc⟩ := ht
      obtain ⟨notOut, f, found, rfl, rfl⟩ := callTy_some hc
      obtain ⟨j, rfl, vrun | ⟨v, s1, s2, vrun, brun, rfl⟩⟩ := letLocal_trap_inv run
      · obtain ⟨i, rfl, h⟩ := call_trap_inv vrun
        rcases h with argsRun | ⟨values, afterArgs, argsRun, h⟩
        · exact (exprs_safe target tenv env args argsRun hts rel).2
        have e := evalExprs_state args argsRun
        subst afterArgs
        obtain ⟨ps, -, rs⟩ := exprs_sim target tenv env args argsRun hts rel
        cases h with
        | inl h => exact absurd rs.length_params (h.2 f found)
        | inr h =>
          obtain ⟨f', completed, found', len, rfl, body⟩ := h
          rw [found, Option.some.injEq] at found'
          subst found'
          exact call_body_safe (completed := completed) (funcs i (by omega)) notOut found len inv bound rs body
      · obtain ⟨i, f', values, afterArgs, completed, cc, rfl, argsRun, found', len, bodyRun, result, rfl⟩ :=
          call_inv' vrun
        have e := evalExprs_state args argsRun
        subst afterArgs
        rw [found, Option.some.injEq] at found'
        subst found'
        obtain ⟨ps, -, rs⟩ := exprs_sim target tenv env args argsRun hts rel
        have g2 : Grows (restoreLocals st completed) s2 :=
          (Grows.same (st := restoreLocals st completed) (st' := (restoreLocals st completed).bindLocal id v) rfl rfl).trans
            (execStmt_trap_grows brun)
        have b1 := Grows.bound (call_grows (grows sp _) vrun) g2 inv.views bound
        obtain ⟨w, -, rw, invc, stepc⟩ := calls i found notOut len inv
          (show completed.heap.nextAddress ≤ 2 ^ 64 from b1) rs bodyRun result
        have inv1 : Inv (restoreLocals st completed) := invc.restore st
        have rel1 := rel.step (stepc.restore st) rfl
        exact ih (by omega) brun ok (inv1.bindLocal id v) (rel1.bind inv1 rw) bound
    · simp at ok
  | letEnum id ty variant payload body ih =>
    intro k tenv env st r st' le run ok inv rel bound
    simp only [stmtOk] at ok
    split at ok
    · rename_i t ht
      simp only [Option.bind_eq_some_iff] at ht
      obtain ⟨ts, hts, hs⟩ := ht
      obtain ⟨eid, variants, rfl, hk, rfl⟩ := variantTy_some hs
      obtain ⟨j, rfl, vrun | ⟨v, s1, s2, vrun, brun, rfl⟩⟩ := letLocal_trap_inv run
      · obtain ⟨i, -, frun⟩ := enumValue_trap_inv vrun
        exact (exprs_safe target tenv env payload frun hts rel).2
      · obtain ⟨i, vs, rfl, frun, rfl⟩ := enumValue_inv vrun
        have e := evalExprs_state payload frun
        subst s1
        obtain ⟨ps, -, rs⟩ := exprs_sim target tenv env payload frun hts rel
        have r : VRel sp.toCore (boxElem sp prims) st.heap (.enum eid variants) (.enumeration eid variant vs)
            (.enumeration eid variant ps) := .enum hk rs
        exact ih (by omega) brun ok (inv.bindLocal id _) (rel.bind inv r) bound
    · simp at ok
  | letMatch => intro k tenv env st r st' le run ok; simp [stmtOk] at ok
  | set => intro k tenv env st r st' le run ok; simp [stmtOk] at ok
  | setField => intro k tenv env st r st' le run ok; simp [stmtOk] at ok
  | setCall => intro k tenv env st r st' le run ok; simp [stmtOk] at ok
  | «then» first second ih1 ih2 =>
    intro k tenv env st r st' le run ok inv rel bound
    simp only [stmtOk, Bool.and_eq_true] at ok
    simp only [SrcStmt.toCore] at run
    obtain ⟨j, rfl, frun | ⟨s1, frun, srun⟩⟩ := sequence_trap_inv run
    · exact ih1 (by omega) frun ok.1 inv rel bound
    · have b1 := Grows.bound (execStmt_grows frun) (execStmt_trap_grows srun) inv.views bound
      obtain ⟨d1, -, -, ran1⟩ := stmtD ret first (by omega) frun ok.1 inv rel b1
      exact ih2 (by omega) srun ok.2 ran1.inv (rel.step ran1.step ran1.locals) bound
  | «if» condition thenBranch elseBranch ih1 ih2 =>
    intro k tenv env st r st' le run ok inv rel bound
    simp only [stmtOk, Bool.and_eq_true] at ok
    obtain ⟨⟨hc, ok1⟩, ok2⟩ := ok
    have htc := isBoolTy_some hc
    simp only [SrcStmt.toCore] at run
    obtain ⟨j, rfl, crun | ⟨v, crun, notBool, -⟩ | ⟨x, s1, crun, brun⟩⟩ := if_trap_inv run
    · exact (expr_safe target tenv env condition crun htc rel).2
    · have e := condition.eval_state crun
      subst e
      obtain ⟨p, -, r⟩ := expr_sim target tenv env condition crun htc rel
      obtain ⟨b, rfl⟩ := r.bool_inv
      exact (notBool b rfl).elim
    · have e := condition.eval_state crun
      subst s1
      cases x
      · exact ih2 (by omega) brun ok2 inv rel bound
      · exact ih1 (by omega) brun ok1 inv rel bound
  | «while» => intro k tenv env st r st' le run ok; simp [stmtOk] at ok
  | «return» value =>
    intro k tenv env st r st' le run ok inv rel bound
    simp only [SrcStmt.toCore] at run
    obtain ⟨j, -, vrun⟩ := return_trap_inv run
    simp only [stmtOk] at ok
    split at ok
    · rename_i t ht
      exact (expr_safe target tenv env value vrun ht rel).2
    · simp at ok
  | letAlloc => intro k tenv env st r st' le run ok; simp [stmtOk] at ok
  | letLoad => intro k tenv env st r st' le run ok; simp [stmtOk] at ok
  | setByte => intro k tenv env st r st' le run ok; simp [stmtOk] at ok
  | free => intro k tenv env st r st' le run ok; simp [stmtOk] at ok
  | letSlice => intro k tenv env st r st' le run ok; simp [stmtOk] at ok
  | letIndex => intro k tenv env st r st' le run ok; simp [stmtOk] at ok
  | setIndex => intro k tenv env st r st' le run ok; simp [stmtOk] at ok
  | letEval id ty value body ih =>
    intro k tenv env st r st' le run ok inv rel bound
    simp only [stmtOk] at ok
    split at ok
    · rename_i t ht
      obtain ⟨j, rfl, vrun | ⟨v, s1, s2, vrun, brun, rfl⟩⟩ := letLocal_trap_inv run
      · exact effS (by omega) vrun ht inv rel bound
      · have g2 : Grows s1 s2 :=
          (Grows.same (st := s1) (st' := s1.bindLocal id v) rfl rfl).trans (execStmt_trap_grows brun)
        have b1 := Grows.bound (effGrows vrun) g2 inv.views bound
        obtain ⟨p, -, r, ran1⟩ := effD vrun ht inv rel b1
        have rel1 := rel.step ran1.step ran1.locals
        exact ih (by omega) brun ok (ran1.inv.bindLocal id v) (rel1.bind ran1.inv r) bound
    · simp at ok
  | setEval => intro k tenv env st r st' le run ok; simp [stmtOk] at ok
  | ifEval condition thenBranch elseBranch ih1 ih2 =>
    intro k tenv env st r st' le run ok inv rel bound
    simp only [stmtOk, Bool.and_eq_true] at ok
    obtain ⟨⟨hc, ok1⟩, ok2⟩ := ok
    have htc := isBoolTy_some hc
    simp only [SrcStmt.toCore] at run
    obtain ⟨j, rfl, crun | ⟨v, crun, notBool, -⟩ | ⟨x, s1, crun, brun⟩⟩ := if_trap_inv run
    · exact effS (by omega) crun htc inv rel bound
    · obtain ⟨p, -, r, -⟩ := effD crun htc inv rel bound
      obtain ⟨b, rfl⟩ := r.bool_inv
      exact (notBool b rfl).elim
    · cases x with
      | true =>
        simp only [if_true] at brun
        have b1 := Grows.bound (effGrows crun) (execStmt_trap_grows brun) inv.views bound
        obtain ⟨p, -, r, ran1⟩ := effD crun htc inv rel b1
        exact ih1 (by omega) brun ok1 ran1.inv (rel.step ran1.step ran1.locals) bound
      | false =>
        simp only [Bool.false_eq_true, if_false] at brun
        have b1 := Grows.bound (effGrows crun) (execStmt_trap_grows brun) inv.views bound
        obtain ⟨p, -, r, ran1⟩ := effD crun htc inv rel b1
        exact ih2 (by omega) brun ok2 ran1.inv (rel.step ran1.step ran1.locals) bound
  | whileEval => intro k tenv env st r st' le run ok; simp [stmtOk] at ok
  | returnEval value =>
    intro k tenv env st r st' le run ok inv rel bound
    simp only [SrcStmt.toCore] at run
    obtain ⟨j, rfl, vrun⟩ := return_trap_inv run
    simp only [stmtOk] at ok
    split at ok
    · rename_i t ht
      exact effS (by omega) vrun ht inv rel bound
    · simp at ok
  | discard value =>
    intro k tenv env st r st' le run ok inv rel bound
    simp only [stmtOk, Option.isSome_iff_exists] at ok
    obtain ⟨t, ht⟩ := ok
    simp only [SrcStmt.toCore] at run
    obtain ⟨j, rfl, vrun⟩ := expression_trap_inv run
    exact effS (by omega) vrun ht inv rel bound
  | setIndexEval => intro k tenv env st r st' le run ok; simp [stmtOk] at ok
  | setFieldEval => intro k tenv env st r st' le run ok; simp [stmtOk] at ok
  | «break» => intro k tenv env st r st' le run ok; simp [stmtOk] at ok
  | «continue» => intro k tenv env st r st' le run ok; simp [stmtOk] at ok
  | returnUnit =>
    intro k tenv env st r st' le run ok inv rel bound
    simp only [SrcStmt.toCore] at run
    exact (returnUnit_trap run).elim
  | «assert» condition =>
    intro k tenv env st r st' le run ok inv rel bound
    simp only [stmtOk] at ok
    have ht := isBoolTy_some ok
    simp only [SrcStmt.toCore] at run
    obtain ⟨j, rfl, arun⟩ := expression_trap_inv run
    obtain ⟨i, rfl, crun | ⟨v, crun, ⟨-, rfl⟩ | ⟨notBool, -⟩⟩⟩ := assert_trap_inv arun
    · exact effS (by omega) crun ht inv rel bound
    · rfl
    · obtain ⟨p, -, r, -⟩ := effD crun ht inv rel bound
      obtain ⟨b, rfl⟩ := r.bool_inv
      exact (notBool b rfl).elim

/-- A pure function's body, called on arguments meaning `ps`, that traps
within the heap bound, traps defined. -/
theorem body_safe {m : Nat} (calls : ∀ i, FuncSim sp prims outside i) (funcs : ∀ i < m, FuncSafe sp prims outside i)
    {f : SrcFunc} {values ps : List Value} {st completed : State} {r : Lanius.Trap}
    (pure : PureFunc sp prims outside f = true) (inv : Inv st)
    (bound : completed.heap.nextAddress ≤ 2 ^ 64)
    (args : VRels sp.toCore (boxElem sp prims) st.heap (f.params.map SrcParam.ty) values ps)
    (run : execStmt m sp.toCore (({ st with locals := [] } : State).bindLocals (paramBindings f.params values))
      f.body.toCore = .trapped r completed) :
    undefinedTrap r = false := by
  have entryInv := Inv.bindLocals (paramBindings f.params values) inv.clear
  have rel := EnvRel.heap_eq (bindLocals_same (paramBindings f.params values) { st with locals := [] }).1.symm
    (EnvRel.entry inv args)
  exact stmt_safe calls funcs f.ret f.body (Nat.le_refl m) run pure entryInv rel bound

end

end Lanius.Faithful
