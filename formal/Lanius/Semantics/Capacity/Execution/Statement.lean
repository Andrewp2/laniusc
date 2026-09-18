import Lanius.Semantics.Capacity.Execution.Step

namespace Lanius.Semantics.Capacity.Execution
open Lanius.Core

theorem statement (valid : config.Valid) (step : Step fuel config allowed program) (ready : Ready config before)
    (supported : Fragment.statement allowed body = true)
    (executed : execStmt (fuel + 1) program before body = .done result after) :
    execStmt (fuel + 1) program (state config before) body = .done (completion config result) (state config after) ∧
      Ready config after ∧ completionClosed config result := by
  cases body with
  | skip | breakLoop | continueLoop => cases executed; exact ⟨rfl, ready, trivial⟩
  | expression input =>
    simp only [Fragment.statement] at supported
    simp only [execStmt] at executed ⊢
    cases run : evalExpr fuel program before input with
    | done entry next =>
      obtain ⟨transport, nextReady, _⟩ := step.expression ready supported run
      rw [transport]
      simp only [run, Outcome.done.injEq] at executed
      obtain ⟨rfl, rfl⟩ := executed
      exact ⟨rfl, nextReady, trivial⟩
    | _ => simp [run] at executed
  | sequence first second =>
    simp only [Fragment.statement, Bool.and_eq_true] at supported
    simp only [execStmt] at executed ⊢
    cases run : execStmt fuel program before first with
    | done entry next =>
      obtain ⟨transport, nextReady, resultClosed⟩ := step.statement ready supported.1 run
      rw [transport]
      cases entry <;> simp only [run, completion] at executed ⊢
      all_goals first
        | exact step.statement nextReady supported.2 executed
        | obtain ⟨rfl, rfl⟩ := Outcome.done.inj executed; exact ⟨rfl, nextReady, resultClosed⟩
    | _ => simp [run] at executed
  | letLocal id type initializer body =>
    simp only [Fragment.statement, Bool.and_eq_true] at supported
    simp only [execStmt] at executed ⊢
    cases run : evalExpr fuel program before initializer with
    | done entry next =>
      obtain ⟨transport, nextReady, entryClosed⟩ := step.expression ready supported.1 run
      rw [transport]
      simp only [State.bindLocal]
      have bound : (state config next).bindCell id (some (value config entry)) = state config (next.bindCell id (some entry)) :=
        (bindCell valid next nextReady.frontier id (some entry)).symm
      rw [bound]
      simp only [run] at executed
      exact restoredStatement step nextReady (nextReady.bindLocal valid id entry entryClosed) supported.2 executed
    | _ => simp [run] at executed
  | letUninitialized id type body =>
    simp only [Fragment.statement] at supported
    simp only [execStmt, State.bindUninitialized] at executed ⊢
    have bound : (state config before).bindCell id none = state config (before.bindCell id none) :=
      (bindCell valid before ready.frontier id none).symm
    rw [bound]
    exact restoredStatement step ready (ready.bindCell valid id none (by intro _ impossible; cases impossible)) supported executed
  | ifThenElse condition yes no =>
    simp only [Fragment.statement, Bool.and_eq_true] at supported
    simp only [execStmt] at executed ⊢
    cases run : evalExpr fuel program before condition with
    | done entry next =>
      obtain ⟨transport, nextReady, entryClosed⟩ := step.expression ready supported.1.1 run
      clear entryClosed
      rw [transport]
      cases entry <;> simp only [run] at executed
      all_goals try contradiction
      case boolean flag =>
        cases flag <;> simp only [value]
        · exact step.statement nextReady supported.2 executed
        · exact step.statement nextReady supported.1.2 executed
    | _ => simp [run] at executed
  | whileLoop condition body =>
    have loopSupported := supported
    simp only [Fragment.statement, Bool.and_eq_true] at supported
    simp only [execStmt] at executed ⊢
    cases run : evalExpr fuel program before condition with
    | done entry next =>
      obtain ⟨transport, nextReady, entryClosed⟩ := step.expression ready supported.1 run
      clear entryClosed
      rw [transport]
      cases entry <;> simp only [run] at executed
      all_goals try contradiction
      case boolean flag =>
        cases flag with
        | false =>
          obtain ⟨rfl, rfl⟩ := Outcome.done.inj executed
          exact ⟨rfl, nextReady, trivial⟩
        | true =>
          simp only [value]
          cases bodyRun : execStmt fuel program next body with
          | done entry completed =>
            obtain ⟨bodyTransport, completedReady, resultClosed⟩ := step.statement nextReady supported.2 bodyRun
            rw [bodyTransport]
            cases entry <;> simp only [bodyRun, completion] at executed ⊢
            all_goals first
              | exact step.statement completedReady loopSupported executed
              | obtain ⟨rfl, rfl⟩ := Outcome.done.inj executed; exact ⟨rfl, completedReady, resultClosed⟩
          | _ => simp [bodyRun] at executed
    | _ => simp [run] at executed
  | forValues => contradiction
  | forRange id start stop inclusive body =>
    simp only [Fragment.statement, Bool.and_eq_true] at supported
    simp only [execStmt] at executed ⊢
    cases run : evalExpr fuel program before start with
    | done entry next =>
      obtain ⟨transport, nextReady, entryClosed⟩ := step.expression ready supported.1.1 run
      clear entryClosed
      rw [transport]
      cases entry <;> simp only [run] at executed
      all_goals try contradiction
      case signed type startValue =>
        cases type <;> simp only [] at executed
        all_goals try contradiction
        case i32 =>
          simp only [value]
          cases stop with
          | none => exact step.forRange nextReady supported.2 executed
          | some stopExpression =>
            simp only [] at executed ⊢
            cases stopRun : evalExpr fuel program next stopExpression with
            | done stopEntry completed =>
              obtain ⟨stopTransport, completedReady, entryClosed⟩ := step.expression nextReady
                (show Fragment.expression allowed stopExpression = true from supported.1.2) stopRun
              clear entryClosed
              rw [stopTransport]
              cases stopEntry <;> simp only [stopRun] at executed
              all_goals try contradiction
              case signed type stopValue =>
                cases type <;> simp only [] at executed
                all_goals try contradiction
                exact step.forRange completedReady supported.2 executed
            | _ => simp [stopRun] at executed
    | _ => simp [run] at executed
  | returnValue input =>
    cases input with
    | none => cases executed; exact ⟨rfl, ready, trivial⟩
    | some input =>
      simp only [Fragment.statement, Fragment.optional] at supported
      simp only [execStmt] at executed ⊢
      cases run : evalExpr fuel program before input with
      | done entry next =>
        obtain ⟨transport, nextReady, entryClosed⟩ := step.expression ready supported run
        rw [transport]
        simp only [run, Outcome.done.injEq] at executed
        obtain ⟨rfl, rfl⟩ := executed
        exact ⟨rfl, nextReady, entryClosed⟩
      | _ => simp [run] at executed

end Lanius.Semantics.Capacity.Execution
