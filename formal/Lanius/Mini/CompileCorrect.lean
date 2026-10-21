import Lanius.Mini.Compile

/-! The compiler against the abstract machine: induction on syntax, with one
invariant — slots below `base` hold the source locals. -/

namespace Lanius.Mini

/-- Slots below `base` hold the source environment. -/
def Agree (base : Nat) (env : Env) (m : Machine) : Prop := ∀ index, index < base → m.slots index = env index

theorem compileExpr_noRet (base : Nat) (e : Expr) (depth : Nat) : Instr.ret ∉ compileExpr base e depth := by
  induction e generalizing depth <;> simp_all [compileExpr]

theorem compileExpr_correct (base : Nat) (e : Expr) (depth : Nat) (env : Env) (m : Machine)
    (agree : Agree base env m) (within : e.within base = true) :
    (Instr.exec (compileExpr base e depth) m).acc = e.eval env ∧
      ∀ slot, slot < base + depth → (Instr.exec (compileExpr base e depth) m).slots slot = m.slots slot := by
  induction e generalizing depth m with
  | lit value => simp [compileExpr, Instr.exec, Instr.step, Expr.eval]
  | var index =>
    simp only [Expr.within, decide_eq_true_eq] at within
    simp [compileExpr, Instr.exec, Instr.step, Expr.eval, agree index within]
  | neg operand ih =>
    obtain ⟨acc, slots⟩ := ih depth m agree within
    simp only [compileExpr, Instr.exec_append, Instr.exec_singleton, Instr.step, Expr.eval]
    exact ⟨by rw [acc], slots⟩
  | binary operation left right ihLeft ihRight =>
    simp only [Expr.within, Bool.and_eq_true] at within
    obtain ⟨leftAcc, leftSlots⟩ := ihLeft depth m agree within.1
    simp only [compileExpr, Instr.exec_append, Instr.exec_singleton, Instr.step]
    generalize storedEq : (Instr.exec (compileExpr base left depth) m).store (base + depth) = stored
    have storedAgree : Agree base env stored := by
      intro index below
      rw [← storedEq]
      simp only [Machine.store, if_neg (show index ≠ base + depth by omega)]
      rw [leftSlots index (by omega)]
      exact agree index below
    obtain ⟨rightAcc, rightSlots⟩ := ihRight (depth + 1) stored storedAgree within.2
    have kept : stored.slots (base + depth) = left.eval env := by
      rw [← storedEq]
      simp [Machine.store, leftAcc]
    refine ⟨?_, ?_⟩
    · simp only [Expr.eval, rightSlots (base + depth) (by omega), kept, rightAcc]
    · intro slot below
      rw [rightSlots slot (by omega), ← storedEq]
      simp only [Machine.store, if_neg (show slot ≠ base + depth by omega)]
      exact leftSlots slot below

theorem compileBody_correct (base : Nat) (body : List Stmt) (env : Env) (m : Machine)
    (agree : Agree base env m) (within : body.all (·.within base) = true) :
    Instr.run (compileBody base body) m = run env body := by
  induction body generalizing env m with
  | nil => rfl
  | cons stmt rest ih =>
    simp only [List.all_cons, Bool.and_eq_true] at within
    obtain ⟨here, restWithin⟩ := within
    cases stmt with
    | assign index value =>
      simp only [Stmt.within, Bool.and_eq_true, decide_eq_true_eq] at here
      obtain ⟨acc, slots⟩ := compileExpr_correct base value 0 env m agree here.2
      simp only [compileBody, compileStmt, List.append_assoc, List.singleton_append,
        Instr.run_append _ _ _ (compileExpr_noRet base value 0), run]
      rw [Instr.run_cons (.store index) _ _ nofun]
      refine ih _ _ ?_ restWithin
      intro other below
      simp only [Instr.step, Machine.store, Env.set]
      split
      · exact acc
      · rw [slots other (by omega)]
        exact agree other below
    | ret value =>
      obtain ⟨acc, _⟩ := compileExpr_correct base value 0 env m agree here
      simp only [compileBody, compileStmt, List.append_assoc, List.singleton_append,
        Instr.run_append _ _ _ (compileExpr_noRet base value 0), run, Instr.run, acc]

/-- Milestone 1, abstract level: the compiled code returns what the source
function returns, from any machine whose local slots hold the arguments. -/
theorem compileFunc_correct (func : Func) (code : Code) (compiled : compileFunc func = some code)
    (args : Env) (m : Machine) (agree : Agree func.locals args m) :
    Instr.run code.instrs m = func.run args := by
  simp only [compileFunc] at compiled
  split at compiled
  · rename_i checks
    cases compiled
    simp only [Bool.and_eq_true] at checks
    exact compileBody_correct func.locals func.body args m agree checks.1
  · contradiction

theorem Instr.fits_mono {i : Instr} {small large : Nat} (fits : i.fits small) (le : small ≤ large) :
    i.fits large := by
  cases i <;> simp only [Instr.fits] at fits ⊢ <;> omega

theorem compileExpr_fits (base : Nat) (e : Expr) (depth : Nat) (within : e.within base = true) :
    ∀ i ∈ compileExpr base e depth, i.fits (base + depth + e.temps) := by
  induction e generalizing depth with
  | lit value => simp [compileExpr, Instr.fits]
  | var index =>
    simp only [Expr.within, decide_eq_true_eq] at within
    simp only [compileExpr, List.mem_singleton, forall_eq, Instr.fits]
    omega
  | neg operand ih =>
    simp only [compileExpr, List.mem_append, List.mem_singleton]
    rintro i (inner | rfl)
    · exact ih depth within i inner
    · trivial
  | binary operation left right ihLeft ihRight =>
    simp only [Expr.within, Bool.and_eq_true] at within
    simp only [compileExpr, List.mem_append, List.mem_singleton, Expr.temps]
    rintro i (((inLeft | rfl) | inRight) | rfl)
    · exact Instr.fits_mono (ihLeft depth within.1 i inLeft) (by omega)
    · simp only [Instr.fits]; omega
    · exact Instr.fits_mono (ihRight (depth + 1) within.2 i inRight) (by omega)
    · simp only [Instr.fits]; omega

theorem compileBody_fits (base : Nat) (body : List Stmt) (within : body.all (·.within base) = true) :
    ∀ i ∈ compileBody base body, i.fits (base + bodyTemps body) := by
  induction body with
  | nil => simp [compileBody]
  | cons stmt rest ih =>
    simp only [List.all_cons, Bool.and_eq_true] at within
    simp only [compileBody, List.mem_append, bodyTemps]
    rintro i (inStmt | inRest)
    · cases stmt with
      | assign index value =>
        simp only [Stmt.within, Bool.and_eq_true, decide_eq_true_eq] at within
        simp only [compileStmt, List.mem_append, List.mem_singleton] at inStmt
        rcases inStmt with inValue | rfl
        · exact Instr.fits_mono (compileExpr_fits base value 0 within.1.2 i inValue)
            (by simp only [Stmt.temps]; omega)
        · simp only [Instr.fits]; omega
      | ret value =>
        simp only [Stmt.within] at within
        simp only [compileStmt, List.mem_append, List.mem_singleton] at inStmt
        rcases inStmt with inValue | rfl
        · exact Instr.fits_mono (compileExpr_fits base value 0 within.1 i inValue)
            (by simp only [Stmt.temps]; omega)
        · trivial
    · exact Instr.fits_mono (ih within.2 i inRest) (by omega)

theorem compileFunc_fits (func : Func) (code : Code) (compiled : compileFunc func = some code) :
    func.locals ≤ code.slots ∧ code.slots ≤ frameLimit ∧ ∀ i ∈ code.instrs, i.fits code.slots := by
  simp only [compileFunc] at compiled
  split at compiled
  · rename_i checks
    cases compiled
    simp only [Bool.and_eq_true, decide_eq_true_eq] at checks
    exact ⟨Nat.le_add_right _ _, checks.2, compileBody_fits func.locals func.body checks.1⟩
  · contradiction

end Lanius.Mini
