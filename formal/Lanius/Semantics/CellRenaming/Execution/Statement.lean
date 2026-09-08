import Lanius.Semantics.CellRenaming.Execution.Step
import Lanius.Semantics.CellRenaming.Projection

namespace Lanius.Semantics.CellRenaming.Execution
open Lanius.Core

theorem statement {rename : Permutation boundary} (step : Step fuel rename program)
    (before : State) (body : Stmt) (result : Completion) (after : State)
    (ready : boundary ≤ before.nextCell)
    (executed : execStmt (fuel + 1) program before body = .done result after) :
    execStmt (fuel + 1) program (state rename.forward before) (CellRenaming.statement rename.forward body) =
      .done (completion rename.forward result) (state rename.forward after) ∧ boundary ≤ after.nextCell := by
  cases body with
  | skip | breakLoop | continueLoop =>
      cases executed
      exact ⟨rfl, ready⟩
  | expression input =>
      simp only [CellRenaming.statement, execStmt] at executed ⊢
      cases run : evalExpr fuel program before input with
      | done entry next =>
          obtain ⟨transport, nextReady⟩ := step.expression ready run
          rw [transport]
          simp only [run, Outcome.done.injEq] at executed
          obtain ⟨rfl, rfl⟩ := executed
          exact ⟨rfl, nextReady⟩
      | _ => simp [run] at executed
  | sequence first second =>
      simp only [CellRenaming.statement, execStmt] at executed ⊢
      cases run : execStmt fuel program before first with
      | done entry next =>
          obtain ⟨transport, nextReady⟩ := step.statement ready run
          rw [transport]
          cases entry <;> simp only [run, completion] at executed ⊢
          all_goals first
            | exact step.statement nextReady executed
            | obtain ⟨rfl, rfl⟩ := Outcome.done.inj executed; exact ⟨rfl, nextReady⟩
      | _ => simp [run] at executed
  | letLocal id type initializer body =>
      simp only [CellRenaming.statement, execStmt] at executed ⊢
      cases run : evalExpr fuel program before initializer with
      | done entry next =>
          obtain ⟨transport, nextReady⟩ := step.expression ready run
          rw [transport]
          simp only []
          rw [← bindLocal rename next nextReady]
          simp only [run] at executed
          exact restoredStatement step next (next.bindLocal id entry) body result after
            (Nat.le_trans nextReady (Nat.le_succ next.nextCell)) executed
      | _ => simp [run] at executed
  | letUninitialized id type body =>
      simp only [CellRenaming.statement, execStmt, State.bindUninitialized] at executed ⊢
      have bound : (state rename.forward before).bindCell id none =
          state rename.forward (before.bindCell id none) :=
        (bindCell rename before ready id none).symm
      rw [bound]
      exact restoredStatement step before (before.bindCell id none) body result after
        (Nat.le_trans ready (Nat.le_succ before.nextCell)) executed
  | ifThenElse condition yes no =>
      simp only [CellRenaming.statement, execStmt] at executed ⊢
      cases run : evalExpr fuel program before condition with
      | done entry next =>
          obtain ⟨transport, nextReady⟩ := step.expression ready run
          rw [transport]
          cases entry <;> simp only [run] at executed
          all_goals try contradiction
          case boolean flag =>
            cases flag <;> simp only [value] <;> exact step.statement nextReady executed
      | _ => simp [run] at executed
  | whileLoop condition body =>
      simp only [CellRenaming.statement, execStmt] at executed ⊢
      cases run : evalExpr fuel program before condition with
      | done entry next =>
          obtain ⟨transport, nextReady⟩ := step.expression ready run
          rw [transport]
          cases entry <;> simp only [run] at executed
          all_goals try contradiction
          case boolean flag =>
            cases flag with
            | false =>
                obtain ⟨rfl, rfl⟩ := Outcome.done.inj executed
                exact ⟨rfl, nextReady⟩
            | true =>
                simp only [value]
                cases bodyRun : execStmt fuel program next body with
                | done entry completed =>
                    obtain ⟨bodyTransport, completedReady⟩ := step.statement nextReady bodyRun
                    rw [bodyTransport]
                    cases entry <;> simp only [bodyRun, completion] at executed ⊢
                    all_goals first
                      | exact step.statement completedReady executed
                      | obtain ⟨rfl, rfl⟩ := Outcome.done.inj executed; exact ⟨rfl, completedReady⟩
                | _ => simp [bodyRun] at executed
      | _ => simp [run] at executed
  | forValues id iterable body =>
      simp only [CellRenaming.statement, execStmt] at executed ⊢
      cases run : evalExpr fuel program before iterable with
      | done entry next =>
          obtain ⟨transport, nextReady⟩ := step.expression ready run
          rw [transport]
          cases entry <;> simp only [run] at executed
          all_goals try contradiction
          case array entries =>
            exact step.forValues nextReady executed
          case slice type cell path start length =>
            simp only [value, CellRenaming.sliceValues]
            cases loaded : Semantics.sliceValues next cell path start length with
            | error reason => simp [loaded] at executed
            | ok entries =>
                simp only [loaded, Except.map] at executed ⊢
                exact step.forValues nextReady executed
      | _ => simp [run] at executed
  | forRange id start stop inclusive body =>
      simp only [CellRenaming.statement, execStmt] at executed ⊢
      cases run : evalExpr fuel program before start with
      | done entry next =>
          obtain ⟨transport, nextReady⟩ := step.expression ready run
          rw [transport]
          cases entry <;> simp only [run] at executed
          all_goals try contradiction
          case signed type startValue =>
            cases type <;> simp only [] at executed
            all_goals try contradiction
            case i32 =>
              simp only [value]
              cases stop with
              | none => exact step.forRange nextReady executed
              | some stopExpression =>
                  simp only [Option.map] at executed ⊢
                  cases stopRun : evalExpr fuel program next stopExpression with
                  | done stopEntry completed =>
                      obtain ⟨stopTransport, completedReady⟩ := step.expression nextReady stopRun
                      rw [stopTransport]
                      cases stopEntry <;> simp only [stopRun] at executed
                      all_goals try contradiction
                      case signed type stopValue =>
                        cases type <;> simp only [] at executed
                        all_goals try contradiction
                        exact step.forRange completedReady executed
                  | _ => simp [stopRun] at executed
      | _ => simp [run] at executed
  | returnValue input =>
      cases input with
      | none => cases executed; exact ⟨rfl, ready⟩
      | some input =>
          simp only [CellRenaming.statement, Option.map, execStmt] at executed ⊢
          cases run : evalExpr fuel program before input with
          | done entry next =>
              obtain ⟨transport, nextReady⟩ := step.expression ready run
              rw [transport]
              simp only [run, Outcome.done.injEq] at executed
              obtain ⟨rfl, rfl⟩ := executed
              exact ⟨rfl, nextReady⟩
          | _ => simp [run] at executed

end Lanius.Semantics.CellRenaming.Execution
