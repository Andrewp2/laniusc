import Lanius.Mini.Grows

/-! # What a Core run that completed did

One lemma per Core construct the pure subset and the prims use: a run that
completed ran its parts, in order, to completion. -/

namespace Lanius.Faithful

open Lanius.Mini
open Lanius.Core (Value)
open Lanius.Semantics (State Completion evalExpr evalExprs evalMatchArms execStmt restoreLocals
  restoreOutcomeLocals)

section
variable {P : Core.Program} {k : Nat} {st st' : State}

/-! ## Statements -/

theorem skip_inv {c : Completion} (h : execStmt k P st .skip = .done c st') : c = .next ∧ st' = st := by
  cases k with
  | zero => simp [execStmt] at h
  | succ j =>
    simp only [execStmt, Semantics.Outcome.done.injEq] at h
    exact ⟨h.1.symm, h.2.symm⟩

theorem expression_inv {e : Core.Expr} {c : Completion} (h : execStmt k P st (.expression e) = .done c st') :
    ∃ j v, k = j + 1 ∧ evalExpr j P st e = .done v st' ∧ c = .next := by
  cases k with
  | zero => simp [execStmt] at h
  | succ j =>
    simp only [execStmt] at h
    split at h
    · rename_i v next run
      simp only [Semantics.Outcome.done.injEq] at h
      obtain ⟨rfl, rfl⟩ := h
      exact ⟨j, v, rfl, run, rfl⟩
    all_goals simp at h

theorem sequence_inv {a b : Core.Stmt} {c : Completion} (h : execStmt k P st (.sequence a b) = .done c st') :
    ∃ j s1 c1, k = j + 1 ∧ execStmt j P st a = .done c1 s1 ∧
      ((c1 = .next ∧ execStmt j P s1 b = .done c st') ∨ (c1 ≠ .next ∧ c = c1 ∧ st' = s1)) := by
  cases k with
  | zero => simp [execStmt] at h
  | succ j =>
    simp only [execStmt] at h
    split at h
    · rename_i next run
      exact ⟨j, next, .next, rfl, run, .inl ⟨rfl, h⟩⟩
    · rename_i c1 next ne run
      simp only [Semantics.Outcome.done.injEq] at h
      obtain ⟨rfl, rfl⟩ := h
      exact ⟨j, next, c1, rfl, run, .inr ⟨fun eq => by subst eq; simp_all, rfl, rfl⟩⟩
    all_goals simp at h

theorem letLocal_inv {id : Nat} {ty : Core.Ty} {e : Core.Expr} {body : Core.Stmt} {c : Completion}
    (h : execStmt k P st (.letLocal id ty e body) = .done c st') :
    ∃ j v s1 s2, k = j + 1 ∧ evalExpr j P st e = .done v s1 ∧
      execStmt j P (s1.bindLocal id v) body = .done c s2 ∧ st' = restoreLocals s1 s2 := by
  cases k with
  | zero => simp [execStmt] at h
  | succ j =>
    simp only [execStmt] at h
    split at h
    · rename_i v next run
      cases bodyRun : execStmt j P (next.bindLocal id v) body with
      | done c' s2 =>
        simp only [bodyRun, restoreOutcomeLocals, Semantics.Outcome.done.injEq] at h
        obtain ⟨rfl, rfl⟩ := h
        exact ⟨j, v, next, s2, rfl, run, bodyRun, rfl⟩
      | trapped => simp [bodyRun, restoreOutcomeLocals] at h
      | exited => simp [bodyRun, restoreOutcomeLocals] at h
      | outOfFuel => simp [bodyRun, restoreOutcomeLocals] at h
    all_goals simp at h

theorem if_inv {cond : Core.Expr} {a b : Core.Stmt} {c : Completion}
    (h : execStmt k P st (.ifThenElse cond a b) = .done c st') :
    ∃ j s1 x, k = j + 1 ∧ evalExpr j P st cond = .done (.boolean x) s1 ∧
      execStmt j P s1 (if x then a else b) = .done c st' := by
  cases k with
  | zero => simp [execStmt] at h
  | succ j =>
    simp only [execStmt] at h
    split at h
    · rename_i next run
      exact ⟨j, next, true, rfl, run, h⟩
    · rename_i next run
      exact ⟨j, next, false, rfl, run, h⟩
    all_goals simp at h

theorem return_inv {e : Core.Expr} {c : Completion}
    (h : execStmt k P st (.returnValue (some e)) = .done c st') :
    ∃ j v, k = j + 1 ∧ evalExpr j P st e = .done v st' ∧ c = .returned (some v) := by
  cases k with
  | zero => simp [execStmt] at h
  | succ j =>
    simp only [execStmt] at h
    split at h
    · rename_i v next run
      simp only [Semantics.Outcome.done.injEq] at h
      obtain ⟨rfl, rfl⟩ := h
      exact ⟨j, v, rfl, run, rfl⟩
    all_goals simp at h

theorem returnUnit_inv {c : Completion} (h : execStmt k P st (.returnValue none) = .done c st') :
    c = .returned none ∧ st' = st := by
  cases k with
  | zero => simp [execStmt] at h
  | succ j =>
    simp only [execStmt, Semantics.Outcome.done.injEq] at h
    exact ⟨h.1.symm, h.2.symm⟩

/-! ## Expressions -/

theorem value_inv {x v : Value} (h : evalExpr k P st (.value x) = .done v st') : v = x ∧ st' = st := by
  cases k with
  | zero => simp [evalExpr] at h
  | succ j =>
    simp only [evalExpr, Semantics.Outcome.done.injEq] at h
    exact ⟨h.1.symm, h.2.symm⟩

theorem local_inv {id : Nat} {v : Value} (h : evalExpr k P st (.local id) = .done v st') :
    st.local? id = some v ∧ st' = st := by
  cases k with
  | zero => simp [evalExpr] at h
  | succ j =>
    simp only [evalExpr] at h
    split at h
    · simp at h
    · rename_i cell found
      split at h
      · simp at h
      · simp at h
      · rename_i w entry
        simp only [Semantics.Outcome.done.injEq] at h
        obtain ⟨rfl, rfl⟩ := h
        simp [State.local?, State.cell?, found, entry]

theorem unary_inv {op : Core.UnaryOp} {e : Core.Expr} {v : Value} (h : evalExpr k P st (.unary op e) = .done v st') :
    ∃ j w, k = j + 1 ∧ evalExpr j P st e = .done w st' ∧ Semantics.evalUnaryValue P.target op w = .ok v := by
  cases k with
  | zero => simp [evalExpr] at h
  | succ j =>
    simp only [evalExpr] at h
    split at h
    · rename_i w next run
      split at h
      · rename_i r ok
        simp only [Semantics.Outcome.done.injEq] at h
        obtain ⟨rfl, rfl⟩ := h
        exact ⟨j, w, rfl, run, ok⟩
      · simp at h
    all_goals simp at h

theorem cast_inv {ty : Core.ScalarTy} {e : Core.Expr} {v : Value} (h : evalExpr k P st (.cast ty e) = .done v st') :
    ∃ j w, k = j + 1 ∧ evalExpr j P st e = .done w st' ∧ Semantics.evalScalarCast P.target ty w = .ok v := by
  cases k with
  | zero => simp [evalExpr] at h
  | succ j =>
    simp only [evalExpr] at h
    split at h
    · rename_i w next run
      split at h
      · rename_i r ok
        simp only [Semantics.Outcome.done.injEq] at h
        obtain ⟨rfl, rfl⟩ := h
        exact ⟨j, w, rfl, run, ok⟩
      · simp at h
    all_goals simp at h

/-- A binary operator other than `&&` and `||`: both sides, then the operator. -/
theorem binary_inv {op : Core.BinaryOp} {a b : Core.Expr} {v : Value}
    (notAnd : op ≠ .logicalAnd) (notOr : op ≠ .logicalOr) (h : evalExpr k P st (.binary op a b) = .done v st') :
    ∃ j l s1 r, k = j + 1 ∧ evalExpr j P st a = .done l s1 ∧ evalExpr j P s1 b = .done r st' ∧
      Semantics.evalBinaryValue P.target op l r = .ok v := by
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
        · rename_i r s2 runR
          split at h
          · rename_i res ok
            simp only [Semantics.Outcome.done.injEq] at h
            obtain ⟨rfl, rfl⟩ := h
            exact ⟨j, l, s1, r, rfl, runL, runR, ok⟩
          · simp at h
        all_goals simp at h
      all_goals simp at h

theorem logicalAnd_inv {a b : Core.Expr} {v : Value} (h : evalExpr k P st (.binary .logicalAnd a b) = .done v st') :
    ∃ j s1 x, k = j + 1 ∧ evalExpr j P st a = .done (.boolean x) s1 ∧
      ((x = false ∧ v = .boolean false ∧ st' = s1) ∨ (x = true ∧ evalExpr j P s1 b = .done v st')) := by
  cases k with
  | zero => simp [evalExpr] at h
  | succ j =>
    simp only [evalExpr] at h
    split at h
    · rename_i s1 run
      simp only [Semantics.Outcome.done.injEq] at h
      obtain ⟨rfl, rfl⟩ := h
      exact ⟨j, s1, false, rfl, run, .inl ⟨rfl, rfl, rfl⟩⟩
    · rename_i s1 run
      exact ⟨j, s1, true, rfl, run, .inr ⟨rfl, h⟩⟩
    all_goals simp at h

theorem logicalOr_inv {a b : Core.Expr} {v : Value} (h : evalExpr k P st (.binary .logicalOr a b) = .done v st') :
    ∃ j s1 x, k = j + 1 ∧ evalExpr j P st a = .done (.boolean x) s1 ∧
      ((x = true ∧ v = .boolean true ∧ st' = s1) ∨ (x = false ∧ evalExpr j P s1 b = .done v st')) := by
  cases k with
  | zero => simp [evalExpr] at h
  | succ j =>
    simp only [evalExpr] at h
    split at h
    · rename_i s1 run
      simp only [Semantics.Outcome.done.injEq] at h
      obtain ⟨rfl, rfl⟩ := h
      exact ⟨j, s1, true, rfl, run, .inl ⟨rfl, rfl, rfl⟩⟩
    · rename_i s1 run
      exact ⟨j, s1, false, rfl, run, .inr ⟨rfl, h⟩⟩
    all_goals simp at h

theorem field_inv {base : Core.Expr} {index : Nat} {v : Value} (h : evalExpr k P st (.field base index) = .done v st') :
    ∃ j id fields, k = j + 1 ∧ evalExpr j P st base = .done (.structure id fields) st' ∧ fields[index]? = some v := by
  cases k with
  | zero => simp [evalExpr] at h
  | succ j =>
    simp only [evalExpr] at h
    split at h
    · rename_i id fields next run
      split at h
      · rename_i w found
        simp only [Semantics.Outcome.done.injEq] at h
        obtain ⟨rfl, rfl⟩ := h
        exact ⟨j, id, fields, rfl, run, found⟩
      · simp at h
    all_goals simp at h

theorem structValue_inv {id : Nat} {es : List Core.Expr} {v : Value}
    (h : evalExpr k P st (.structValue id es) = .done v st') :
    ∃ j vs, k = j + 1 ∧ evalExprs j P st es = .done vs st' ∧ v = .structure id vs := by
  cases k with
  | zero => simp [evalExpr] at h
  | succ j =>
    simp only [evalExpr] at h
    split at h
    · rename_i vs next run
      simp only [Semantics.Outcome.done.injEq] at h
      obtain ⟨rfl, rfl⟩ := h
      exact ⟨j, vs, rfl, run, rfl⟩
    all_goals simp at h

theorem enumValue_inv {id variant : Nat} {es : List Core.Expr} {v : Value}
    (h : evalExpr k P st (.enumValue id variant es) = .done v st') :
    ∃ j vs, k = j + 1 ∧ evalExprs j P st es = .done vs st' ∧ v = .enumeration id variant vs := by
  cases k with
  | zero => simp [evalExpr] at h
  | succ j =>
    simp only [evalExpr] at h
    split at h
    · rename_i vs next run
      simp only [Semantics.Outcome.done.injEq] at h
      obtain ⟨rfl, rfl⟩ := h
      exact ⟨j, vs, rfl, run, rfl⟩
    all_goals simp at h

theorem matchValue_inv {s : Core.Expr} {arms : List (Core.Pattern × Core.Expr)} {v : Value}
    (h : evalExpr k P st (.matchValue s arms) = .done v st') :
    ∃ j sv s1, k = j + 1 ∧ evalExpr j P st s = .done sv s1 ∧ evalMatchArms j P s1 sv arms = .done v st' := by
  cases k with
  | zero => simp [evalExpr] at h
  | succ j =>
    simp only [evalExpr] at h
    split at h
    · rename_i sv next run
      exact ⟨j, sv, next, rfl, run, h⟩
    all_goals simp at h

theorem arms_nil_inv {sv v : Value} (h : evalMatchArms k P st sv [] = .done v st') : False := by
  cases k <;> simp [evalMatchArms] at h

theorem arms_cons_inv {sv v : Value} {pat : Core.Pattern} {body : Core.Expr} {arms : List (Core.Pattern × Core.Expr)}
    (h : evalMatchArms k P st sv ((pat, body) :: arms) = .done v st') :
    ∃ j, k = j + 1 ∧ ((Semantics.matchPattern pat sv = none ∧ evalMatchArms j P st sv arms = .done v st') ∨
      ∃ bs s2, Semantics.matchPattern pat sv = some bs ∧ evalExpr j P (st.bindLocals bs) body = .done v s2 ∧
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
      | done w s2 =>
        simp only [run, restoreOutcomeLocals, Semantics.Outcome.done.injEq] at h
        obtain ⟨rfl, rfl⟩ := h
        exact ⟨j, rfl, .inr ⟨bs, s2, found, run, rfl⟩⟩
      | trapped => simp [run, restoreOutcomeLocals] at h
      | exited => simp [run, restoreOutcomeLocals] at h
      | outOfFuel => simp [run, restoreOutcomeLocals] at h

theorem exprs_nil_inv {vs : List Value} (h : evalExprs k P st [] = .done vs st') : vs = [] ∧ st' = st := by
  cases k with
  | zero => simp [evalExprs] at h
  | succ j =>
    simp only [evalExprs, Semantics.Outcome.done.injEq] at h
    exact ⟨h.1.symm, h.2.symm⟩

theorem exprs_cons_inv {e : Core.Expr} {es : List Core.Expr} {vs : List Value}
    (h : evalExprs k P st (e :: es) = .done vs st') :
    ∃ j v s1 rest, k = j + 1 ∧ evalExpr j P st e = .done v s1 ∧ evalExprs j P s1 es = .done rest st' ∧
      vs = v :: rest := by
  cases k with
  | zero => simp [evalExprs] at h
  | succ j =>
    simp only [evalExprs] at h
    split at h
    · rename_i v s1 run
      split at h
      · rename_i rest s2 runRest
        simp only [Semantics.Outcome.done.injEq] at h
        obtain ⟨rfl, rfl⟩ := h
        exact ⟨j, v, s1, rest, rfl, run, runRest, rfl⟩
      all_goals simp at h
    all_goals simp at h

theorem assert_inv {e : Core.Expr} {v : Value} (h : evalExpr k P st (.intrinsic .assert e) = .done v st') :
    ∃ j, k = j + 1 ∧ evalExpr j P st e = .done (.boolean true) st' ∧ v = .unit := by
  cases k with
  | zero => simp [evalExpr] at h
  | succ j =>
    simp only [evalExpr] at h
    split at h
    · rename_i w next run
      split at h
      all_goals first
        | (simp only [Semantics.Outcome.done.injEq] at h
           obtain ⟨rfl, rfl⟩ := h
           exact ⟨j, rfl, run, rfl⟩)
        | simp_all
    all_goals simp at h

theorem stride_inv {e : Core.Expr} {v : Value} (h : evalExpr k P st (.intrinsic .sliceStride e) = .done v st') :
    ∃ j w s, k = j + 1 ∧ evalExpr j P st e = .done w st' ∧ Semantics.rawSliceStride? P w = some s ∧
      v = .signed .isize s := by
  cases k with
  | zero => simp [evalExpr] at h
  | succ j =>
    simp only [evalExpr] at h
    split at h
    · rename_i w next run
      split at h
      all_goals first
        | (split at h
           · rename_i s found
             simp only [Semantics.Outcome.done.injEq] at h
             obtain ⟨rfl, rfl⟩ := h
             exact ⟨j, w, s, rfl, run, found, rfl⟩
           · simp at h)
        | simp_all
    all_goals simp at h

theorem typedSlice_inv {el : Core.Ty} {p n : Core.Expr} {v : Value}
    (h : evalExpr k P st (.typedSliceFromRawParts el p n) = .done v st') :
    ∃ j a s1 c s2, k = j + 1 ∧ evalExpr j P st p = .done (.pointer a) s1 ∧
      evalExpr j P s1 n = .done (.signed .i32 c) s2 ∧ Semantics.mapRawNominalSlice P s2 el a c = .done v st' := by
  cases k with
  | zero => simp [evalExpr] at h
  | succ j =>
    simp only [evalExpr] at h
    split at h
    · rename_i a s1 runP
      split at h
      · rename_i c s2 runN
        exact ⟨j, a, s1, c, s2, rfl, runP, runN, h⟩
      all_goals simp at h
    all_goals simp at h

/-- A call: its arguments, then the callee's body on fresh locals. -/
theorem call_inv' {sp : SrcProgram} {callee : Nat} {args : List Core.Expr} {v : Value}
    (h : evalExpr k sp.toCore st (.call callee args) = .done v st') :
    ∃ j f values afterArgs completed c, k = j + 1 ∧ evalExprs j sp.toCore st args = .done values afterArgs ∧
      sp.funcs[callee]? = some f ∧ values.length = f.params.length ∧
      execStmt j sp.toCore (({ afterArgs with locals := [] } : State).bindLocals
        (paramBindings f.params values)) f.body.toCore = .done c completed ∧ CallResult f.ret c v ∧
      st' = restoreLocals afterArgs completed := by
  cases k with
  | zero => simp [evalExpr] at h
  | succ j =>
    obtain ⟨f, values, afterArgs, completed, c, a, b, d, e, g, i⟩ := call_inv h
    exact ⟨j, f, values, afterArgs, completed, c, rfl, a, b, d, e, g, i⟩

end

end Lanius.Faithful
