import Lanius.Faithful.Sim.Inv

/-! # What a Core run that trapped did

One lemma per Core construct the pure subset, the prims and the driver use:
a run that trapped ran its parts, in order, until one trapped, or ran them to
completion and then trapped itself. -/

namespace Lanius.Faithful

open Lanius.Mini
open Lanius.Core (Value)
open Lanius.Semantics (State Completion evalExpr evalExprs evalMatchArms execStmt restoreLocals
  restoreOutcomeLocals)

section
variable {P : Core.Program} {k : Nat} {st st' : State} {r : Lanius.Trap}

/-! ## Expressions -/

theorem value_trap {x : Value} (h : evalExpr k P st (.value x) = .trapped r st') : False := by
  cases k <;> simp [evalExpr] at h

theorem local_trap {id : Nat} {x : Value} (known : st.local? id = some x)
    (h : evalExpr k P st (.local id) = .trapped r st') : False := by
  cases k with
  | zero => simp [evalExpr] at h
  | succ j =>
    simp only [State.local?] at known
    simp only [evalExpr] at h
    split at h
    · rename_i none; simp [none] at known
    · rename_i cell found
      rw [found, Option.bind_some] at known
      simp only [State.cell?] at known
      split at h
      · rename_i none; simp [none] at known
      · rename_i entry; simp [entry] at known
      · simp at h

theorem unary_trap_inv {op : Core.UnaryOp} {e : Core.Expr} (h : evalExpr k P st (.unary op e) = .trapped r st') :
    ∃ j, k = j + 1 ∧ (evalExpr j P st e = .trapped r st' ∨
      ∃ w, evalExpr j P st e = .done w st' ∧ Semantics.evalUnaryValue P.target op w = .error r) := by
  cases k with
  | zero => simp [evalExpr] at h
  | succ j =>
    simp only [evalExpr] at h
    split at h
    · rename_i w next run
      split at h
      · simp at h
      · rename_i reason bad
        simp only [Semantics.Outcome.trapped.injEq] at h
        obtain ⟨rfl, rfl⟩ := h
        exact ⟨j, rfl, .inr ⟨w, run, bad⟩⟩
    · rename_i reason next run
      simp only [Semantics.Outcome.trapped.injEq] at h
      obtain ⟨rfl, rfl⟩ := h
      exact ⟨j, rfl, .inl run⟩
    all_goals simp at h

theorem cast_trap_inv {ty : Core.ScalarTy} {e : Core.Expr} (h : evalExpr k P st (.cast ty e) = .trapped r st') :
    ∃ j, k = j + 1 ∧ (evalExpr j P st e = .trapped r st' ∨
      ∃ w, evalExpr j P st e = .done w st' ∧ Semantics.evalScalarCast P.target ty w = .error r) := by
  cases k with
  | zero => simp [evalExpr] at h
  | succ j =>
    simp only [evalExpr] at h
    split at h
    · rename_i w next run
      split at h
      · simp at h
      · rename_i reason bad
        simp only [Semantics.Outcome.trapped.injEq] at h
        obtain ⟨rfl, rfl⟩ := h
        exact ⟨j, rfl, .inr ⟨w, run, bad⟩⟩
    · rename_i reason next run
      simp only [Semantics.Outcome.trapped.injEq] at h
      obtain ⟨rfl, rfl⟩ := h
      exact ⟨j, rfl, .inl run⟩
    all_goals simp at h

/-- A binary operator other than `&&` and `||`: a side trapped, or the operator did. -/
theorem binary_trap_inv {op : Core.BinaryOp} {a b : Core.Expr}
    (notAnd : op ≠ .logicalAnd) (notOr : op ≠ .logicalOr) (h : evalExpr k P st (.binary op a b) = .trapped r st') :
    ∃ j, k = j + 1 ∧ (evalExpr j P st a = .trapped r st' ∨
      ∃ l s1, evalExpr j P st a = .done l s1 ∧ (evalExpr j P s1 b = .trapped r st' ∨
        ∃ rv, evalExpr j P s1 b = .done rv st' ∧ Semantics.evalBinaryValue P.target op l rv = .error r)) := by
  cases k with
  | zero => simp [evalExpr] at h
  | succ j =>
    cases op
    all_goals first
      | exact absurd rfl notAnd
      | exact absurd rfl notOr
      | skip
    all_goals
      simp only [evalExpr] at h
      split at h
      · rename_i l s1 runL
        split at h
        · rename_i rv s2 runR
          split at h
          · simp at h
          · rename_i reason bad
            simp only [Semantics.Outcome.trapped.injEq] at h
            obtain ⟨rfl, rfl⟩ := h
            exact ⟨j, rfl, .inr ⟨l, s1, runL, .inr ⟨rv, runR, bad⟩⟩⟩
        · rename_i reason s2 runR
          simp only [Semantics.Outcome.trapped.injEq] at h
          obtain ⟨rfl, rfl⟩ := h
          exact ⟨j, rfl, .inr ⟨l, s1, runL, .inl runR⟩⟩
        all_goals simp at h
      · rename_i reason s1 runL
        simp only [Semantics.Outcome.trapped.injEq] at h
        obtain ⟨rfl, rfl⟩ := h
        exact ⟨j, rfl, .inl runL⟩
      all_goals simp at h

theorem logicalAnd_trap_inv {a b : Core.Expr} (h : evalExpr k P st (.binary .logicalAnd a b) = .trapped r st') :
    ∃ j, k = j + 1 ∧ (evalExpr j P st a = .trapped r st' ∨
      (∃ l, evalExpr j P st a = .done l st' ∧ (∀ x, l ≠ .boolean x) ∧ r = .typeMismatch) ∨
      ∃ s1, evalExpr j P st a = .done (.boolean true) s1 ∧ evalExpr j P s1 b = .trapped r st') := by
  cases k with
  | zero => simp [evalExpr] at h
  | succ j =>
    simp only [evalExpr] at h
    split at h
    · simp at h
    · rename_i s1 run
      exact ⟨j, rfl, .inr (.inr ⟨s1, run, h⟩)⟩
    · rename_i l s1 notF notT run
      simp only [Semantics.Outcome.trapped.injEq] at h
      obtain ⟨rfl, rfl⟩ := h
      refine ⟨j, rfl, .inr (.inl ⟨l, run, fun x e => ?_, rfl⟩)⟩
      subst e
      cases x
      · exact notF rfl
      · exact notT rfl
    · rename_i reason s1 run
      simp only [Semantics.Outcome.trapped.injEq] at h
      obtain ⟨rfl, rfl⟩ := h
      exact ⟨j, rfl, .inl run⟩
    all_goals simp at h

theorem logicalOr_trap_inv {a b : Core.Expr} (h : evalExpr k P st (.binary .logicalOr a b) = .trapped r st') :
    ∃ j, k = j + 1 ∧ (evalExpr j P st a = .trapped r st' ∨
      (∃ l, evalExpr j P st a = .done l st' ∧ (∀ x, l ≠ .boolean x) ∧ r = .typeMismatch) ∨
      ∃ s1, evalExpr j P st a = .done (.boolean false) s1 ∧ evalExpr j P s1 b = .trapped r st') := by
  cases k with
  | zero => simp [evalExpr] at h
  | succ j =>
    simp only [evalExpr] at h
    split at h
    · simp at h
    · rename_i s1 run
      exact ⟨j, rfl, .inr (.inr ⟨s1, run, h⟩)⟩
    · rename_i l s1 notT notF run
      simp only [Semantics.Outcome.trapped.injEq] at h
      obtain ⟨rfl, rfl⟩ := h
      refine ⟨j, rfl, .inr (.inl ⟨l, run, fun x e => ?_, rfl⟩)⟩
      subst e
      cases x
      · exact notF rfl
      · exact notT rfl
    · rename_i reason s1 run
      simp only [Semantics.Outcome.trapped.injEq] at h
      obtain ⟨rfl, rfl⟩ := h
      exact ⟨j, rfl, .inl run⟩
    all_goals simp at h

/-- A field of a local struct with that field does not trap. -/
theorem field_local_trap {id index sid : Nat} {fields : List Value} {x : Value}
    (known : st.local? id = some (.structure sid fields)) (found : fields[index]? = some x)
    (h : evalExpr k P st (.field (.local id) index) = .trapped r st') : False := by
  cases k with
  | zero => simp [evalExpr] at h
  | succ j =>
    simp only [evalExpr] at h
    split at h
    · rename_i sid' fields' next run
      obtain ⟨e, rfl⟩ := local_inv run
      rw [known, Option.some.injEq, Value.structure.injEq] at e
      obtain ⟨rfl, rfl⟩ := e
      rw [found] at h
      simp at h
    · rename_i v next notStruct run
      obtain ⟨e, rfl⟩ := local_inv run
      rw [known, Option.some.injEq] at e
      subst e
      exact notStruct _ _ rfl
    · rename_i reason next run
      exact local_trap known run
    all_goals simp at h

theorem exprs_nil_trap (h : evalExprs k P st [] = .trapped r st') : False := by
  cases k <;> simp [evalExprs] at h

theorem exprs_cons_trap_inv {e : Core.Expr} {es : List Core.Expr}
    (h : evalExprs k P st (e :: es) = .trapped r st') :
    ∃ j, k = j + 1 ∧ (evalExpr j P st e = .trapped r st' ∨
      ∃ v s1, evalExpr j P st e = .done v s1 ∧ evalExprs j P s1 es = .trapped r st') := by
  cases k with
  | zero => simp [evalExprs] at h
  | succ j =>
    simp only [evalExprs] at h
    split at h
    · rename_i v s1 run
      split at h
      · simp at h
      · rename_i reason s2 runRest
        simp only [Semantics.Outcome.trapped.injEq] at h
        obtain ⟨rfl, rfl⟩ := h
        exact ⟨j, rfl, .inr ⟨v, s1, run, runRest⟩⟩
      all_goals simp at h
    · rename_i reason s1 run
      simp only [Semantics.Outcome.trapped.injEq] at h
      obtain ⟨rfl, rfl⟩ := h
      exact ⟨j, rfl, .inl run⟩
    all_goals simp at h

theorem structValue_trap_inv {id : Nat} {es : List Core.Expr} (h : evalExpr k P st (.structValue id es) = .trapped r st') :
    ∃ j, k = j + 1 ∧ evalExprs j P st es = .trapped r st' := by
  cases k with
  | zero => simp [evalExpr] at h
  | succ j =>
    simp only [evalExpr] at h
    split at h
    · simp at h
    · rename_i reason s1 run
      simp only [Semantics.Outcome.trapped.injEq] at h
      obtain ⟨rfl, rfl⟩ := h
      exact ⟨j, rfl, run⟩
    all_goals simp at h

theorem enumValue_trap_inv {id variant : Nat} {es : List Core.Expr}
    (h : evalExpr k P st (.enumValue id variant es) = .trapped r st') :
    ∃ j, k = j + 1 ∧ evalExprs j P st es = .trapped r st' := by
  cases k with
  | zero => simp [evalExpr] at h
  | succ j =>
    simp only [evalExpr] at h
    split at h
    · simp at h
    · rename_i reason s1 run
      simp only [Semantics.Outcome.trapped.injEq] at h
      obtain ⟨rfl, rfl⟩ := h
      exact ⟨j, rfl, run⟩
    all_goals simp at h

theorem matchValue_trap_inv {s : Core.Expr} {arms : List (Core.Pattern × Core.Expr)}
    (h : evalExpr k P st (.matchValue s arms) = .trapped r st') :
    ∃ j, k = j + 1 ∧ (evalExpr j P st s = .trapped r st' ∨
      ∃ sv s1, evalExpr j P st s = .done sv s1 ∧ evalMatchArms j P s1 sv arms = .trapped r st') := by
  cases k with
  | zero => simp [evalExpr] at h
  | succ j =>
    simp only [evalExpr] at h
    split at h
    · rename_i sv next run
      exact ⟨j, rfl, .inr ⟨sv, next, run, h⟩⟩
    · rename_i reason s1 run
      simp only [Semantics.Outcome.trapped.injEq] at h
      obtain ⟨rfl, rfl⟩ := h
      exact ⟨j, rfl, .inl run⟩
    all_goals simp at h

theorem arms_nil_trap {sv : Value} (h : evalMatchArms k P st sv [] = .trapped r st') :
    r = .nonExhaustiveMatch ∧ st' = st := by
  cases k with
  | zero => simp [evalMatchArms] at h
  | succ j =>
    simp only [evalMatchArms, Semantics.Outcome.trapped.injEq] at h
    exact ⟨h.1.symm, h.2.symm⟩

theorem arms_cons_trap_inv {sv : Value} {pat : Core.Pattern} {body : Core.Expr} {arms : List (Core.Pattern × Core.Expr)}
    (h : evalMatchArms k P st sv ((pat, body) :: arms) = .trapped r st') :
    ∃ j, k = j + 1 ∧ ((Semantics.matchPattern pat sv = none ∧ evalMatchArms j P st sv arms = .trapped r st') ∨
      ∃ bs s2, Semantics.matchPattern pat sv = some bs ∧ evalExpr j P (st.bindLocals bs) body = .trapped r s2 ∧
        st' = restoreLocals st s2) := by
  cases k with
  | zero => simp [evalMatchArms] at h
  | succ j =>
    simp only [evalMatchArms] at h
    split at h
    · rename_i none
      exact ⟨j, rfl, .inl ⟨none, h⟩⟩
    · rename_i bs found
      cases run : evalExpr j P (st.bindLocals bs) body with
      | done w s2 => simp [run, restoreOutcomeLocals] at h
      | trapped reason s2 =>
        simp only [run, restoreOutcomeLocals, Semantics.Outcome.trapped.injEq] at h
        obtain ⟨rfl, rfl⟩ := h
        exact ⟨j, rfl, .inr ⟨bs, s2, found, run, rfl⟩⟩
      | exited => simp [run, restoreOutcomeLocals] at h
      | outOfFuel => simp [run, restoreOutcomeLocals] at h

theorem assert_trap_inv {e : Core.Expr} (h : evalExpr k P st (.intrinsic .assert e) = .trapped r st') :
    ∃ j, k = j + 1 ∧ (evalExpr j P st e = .trapped r st' ∨
      ∃ v, evalExpr j P st e = .done v st' ∧ (v = .boolean false ∧ r = .assertionFailed ∨
        (∀ x, v ≠ .boolean x) ∧ r = .typeMismatch)) := by
  cases k with
  | zero => simp [evalExpr] at h
  | succ j =>
    simp only [evalExpr] at h
    split at h
    · rename_i v next run
      cases v
      case boolean x =>
        cases x
        · simp only [Semantics.Outcome.trapped.injEq] at h
          obtain ⟨rfl, rfl⟩ := h
          exact ⟨j, rfl, .inr ⟨_, run, .inl ⟨rfl, rfl⟩⟩⟩
        · simp at h
      all_goals
        simp only [Semantics.Outcome.trapped.injEq] at h
        obtain ⟨rfl, rfl⟩ := h
        exact ⟨j, rfl, .inr ⟨_, run, .inr ⟨(fun x e => by cases e), rfl⟩⟩⟩
    · rename_i reason s1 run
      simp only [Semantics.Outcome.trapped.injEq] at h
      obtain ⟨rfl, rfl⟩ := h
      exact ⟨j, rfl, .inl run⟩
    all_goals simp at h

/-! ## Statements -/

theorem skip_trap (h : execStmt k P st .skip = .trapped r st') : False := by
  cases k <;> simp [execStmt] at h

theorem expression_trap_inv {e : Core.Expr} (h : execStmt k P st (.expression e) = .trapped r st') :
    ∃ j, k = j + 1 ∧ evalExpr j P st e = .trapped r st' := by
  cases k with
  | zero => simp [execStmt] at h
  | succ j =>
    simp only [execStmt] at h
    split at h
    · simp at h
    · rename_i reason s1 run
      simp only [Semantics.Outcome.trapped.injEq] at h
      obtain ⟨rfl, rfl⟩ := h
      exact ⟨j, rfl, run⟩
    all_goals simp at h

theorem sequence_trap_inv {a b : Core.Stmt} (h : execStmt k P st (.sequence a b) = .trapped r st') :
    ∃ j, k = j + 1 ∧ (execStmt j P st a = .trapped r st' ∨
      ∃ s1, execStmt j P st a = .done .next s1 ∧ execStmt j P s1 b = .trapped r st') := by
  cases k with
  | zero => simp [execStmt] at h
  | succ j =>
    simp only [execStmt] at h
    split at h
    · rename_i s1 run
      exact ⟨j, rfl, .inr ⟨s1, run, h⟩⟩
    · simp at h
    · rename_i reason s1 run
      simp only [Semantics.Outcome.trapped.injEq] at h
      obtain ⟨rfl, rfl⟩ := h
      exact ⟨j, rfl, .inl run⟩
    all_goals simp at h

theorem letLocal_trap_inv {id : Nat} {ty : Core.Ty} {e : Core.Expr} {body : Core.Stmt}
    (h : execStmt k P st (.letLocal id ty e body) = .trapped r st') :
    ∃ j, k = j + 1 ∧ (evalExpr j P st e = .trapped r st' ∨
      ∃ v s1 s2, evalExpr j P st e = .done v s1 ∧ execStmt j P (s1.bindLocal id v) body = .trapped r s2 ∧
        st' = restoreLocals s1 s2) := by
  cases k with
  | zero => simp [execStmt] at h
  | succ j =>
    simp only [execStmt] at h
    split at h
    · rename_i v s1 run
      cases body' : execStmt j P (s1.bindLocal id v) body with
      | done c s2 => simp [body', restoreOutcomeLocals] at h
      | trapped reason s2 =>
        simp only [body', restoreOutcomeLocals, Semantics.Outcome.trapped.injEq] at h
        obtain ⟨rfl, rfl⟩ := h
        exact ⟨j, rfl, .inr ⟨v, s1, s2, run, body', rfl⟩⟩
      | exited => simp [body', restoreOutcomeLocals] at h
      | outOfFuel => simp [body', restoreOutcomeLocals] at h
    · rename_i reason s1 run
      simp only [Semantics.Outcome.trapped.injEq] at h
      obtain ⟨rfl, rfl⟩ := h
      exact ⟨j, rfl, .inl run⟩
    all_goals simp at h

theorem if_trap_inv {cond : Core.Expr} {a b : Core.Stmt} (h : execStmt k P st (.ifThenElse cond a b) = .trapped r st') :
    ∃ j, k = j + 1 ∧ (evalExpr j P st cond = .trapped r st' ∨
      (∃ v, evalExpr j P st cond = .done v st' ∧ (∀ x, v ≠ .boolean x) ∧ r = .typeMismatch) ∨
      ∃ x s1, evalExpr j P st cond = .done (.boolean x) s1 ∧ execStmt j P s1 (if x then a else b) = .trapped r st') := by
  cases k with
  | zero => simp [execStmt] at h
  | succ j =>
    simp only [execStmt] at h
    split at h
    · rename_i s1 run
      exact ⟨j, rfl, .inr (.inr ⟨true, s1, run, h⟩)⟩
    · rename_i s1 run
      exact ⟨j, rfl, .inr (.inr ⟨false, s1, run, h⟩)⟩
    · rename_i v s1 notT notF run
      simp only [Semantics.Outcome.trapped.injEq] at h
      obtain ⟨rfl, rfl⟩ := h
      refine ⟨j, rfl, .inr (.inl ⟨v, run, fun x e => ?_, rfl⟩)⟩
      subst e
      cases x
      · exact notF rfl
      · exact notT rfl
    · rename_i reason s1 run
      simp only [Semantics.Outcome.trapped.injEq] at h
      obtain ⟨rfl, rfl⟩ := h
      exact ⟨j, rfl, .inl run⟩
    all_goals simp at h

theorem return_trap_inv {e : Core.Expr} (h : execStmt k P st (.returnValue (some e)) = .trapped r st') :
    ∃ j, k = j + 1 ∧ evalExpr j P st e = .trapped r st' := by
  cases k with
  | zero => simp [execStmt] at h
  | succ j =>
    simp only [execStmt] at h
    split at h
    · simp at h
    · rename_i reason s1 run
      simp only [Semantics.Outcome.trapped.injEq] at h
      obtain ⟨rfl, rfl⟩ := h
      exact ⟨j, rfl, run⟩
    all_goals simp at h

theorem returnUnit_trap (h : execStmt k P st (.returnValue none) = .trapped r st') : False := by
  cases k <;> simp [execStmt] at h

end

/-! ## Calls -/

/-- A call of a function of `sp` that trapped: an argument trapped, the
callee or its arity is wrong, its body trapped, or its body ended without the
value the call needs. -/
theorem call_trap_inv {sp : SrcProgram} {k : Nat} {st st' : State} {r : Lanius.Trap} {callee : Nat}
    {args : List Core.Expr} (h : evalExpr k sp.toCore st (.call callee args) = .trapped r st') :
    ∃ j, k = j + 1 ∧ (evalExprs j sp.toCore st args = .trapped r st' ∨
      ∃ values afterArgs, evalExprs j sp.toCore st args = .done values afterArgs ∧
        ((st' = afterArgs ∧ ∀ f, sp.funcs[callee]? = some f → values.length ≠ f.params.length) ∨
         ∃ f completed, sp.funcs[callee]? = some f ∧ values.length = f.params.length ∧
           st' = restoreLocals afterArgs completed ∧
           (execStmt j sp.toCore (({ afterArgs with locals := [] } : State).bindLocals
              (paramBindings f.params values)) f.body.toCore = .trapped r completed ∨
            ∃ c, execStmt j sp.toCore (({ afterArgs with locals := [] } : State).bindLocals
              (paramBindings f.params values)) f.body.toCore = .done c completed ∧
              (r = .missingReturn ∨ ((c = .breakLoop ∨ c = .continueLoop) ∧ r = .typeMismatch))))) := by
  cases k with
  | zero => simp [evalExpr] at h
  | succ j =>
    refine ⟨j, rfl, ?_⟩
    simp only [evalExpr] at h
    split at h
    · rename_i values afterArgs argsRun
      refine .inr ⟨values, afterArgs, argsRun, ?_⟩
      rw [SrcProgram.function?_toCore] at h
      cases found : sp.funcs[callee]? with
      | none =>
        simp only [found, Option.map_none, Semantics.Outcome.trapped.injEq] at h
        exact .inl ⟨h.2.symm, fun f e => by cases e⟩
      | some f =>
        simp only [found, Option.map_some, SrcFunc.toCore] at h
        by_cases len : values.length = f.params.length
        · rw [bindParameters_eq _ _ len] at h
          simp only at h
          refine .inr ⟨f, ?_⟩
          split at h
          · simp at h
          · rename_i completed bodyRun
            split at h
            · simp at h
            · simp only [Semantics.Outcome.trapped.injEq] at h
              obtain ⟨rfl, rfl⟩ := h
              exact ⟨completed, rfl, len, rfl, .inr ⟨_, bodyRun, .inl rfl⟩⟩
          · rename_i completed bodyRun
            split at h
            · simp at h
            · simp only [Semantics.Outcome.trapped.injEq] at h
              obtain ⟨rfl, rfl⟩ := h
              exact ⟨completed, rfl, len, rfl, .inr ⟨_, bodyRun, .inl rfl⟩⟩
          · rename_i c completed notSome notNone notNext bodyRun
            simp only [Semantics.Outcome.trapped.injEq] at h
            obtain ⟨rfl, rfl⟩ := h
            refine ⟨completed, rfl, len, rfl, .inr ⟨c, bodyRun, .inr ⟨?_, rfl⟩⟩⟩
            cases c with
            | next => exact absurd rfl notNext
            | returned v => cases v with
              | none => exact absurd rfl notNone
              | some w => exact absurd rfl (notSome w)
            | breakLoop => exact .inl rfl
            | continueLoop => exact .inr rfl
          · rename_i reason completed bodyRun
            simp only [Semantics.Outcome.trapped.injEq] at h
            obtain ⟨rfl, rfl⟩ := h
            exact ⟨completed, rfl, len, rfl, .inl bodyRun⟩
          all_goals simp at h
        · have : Semantics.bindParameters (f.params.map fun p => (p.id, p.ty.toCore)) values = none := by
            simp [Semantics.bindParameters]; omega
          simp only [this, Semantics.Outcome.trapped.injEq] at h
          exact .inl ⟨h.2.symm, fun f' e => by rw [Option.some.injEq] at e; subst e; exact len⟩
    · rename_i reason s1 run
      simp only [Semantics.Outcome.trapped.injEq] at h
      obtain ⟨rfl, rfl⟩ := h
      exact .inl run
    all_goals simp at h

end Lanius.Faithful
