import Lanius.Semantics.CellRenaming.Execution.Step
import Lanius.Semantics.CellRenaming.Projection
import Lanius.Semantics.CellRenaming.Execution.Bounds
import Std.Tactic

namespace Lanius.Semantics.CellRenaming.Execution
open Lanius.Core

theorem arrayExpression {rename : Permutation boundary} (step : Step fuel rename program)
    (before : State) (type : Ty) (input : List Expr) (result : Value) (after : State)
    (ready : boundary ≤ before.nextCell)
    (evaluated : evalExpr (fuel + 1) program before (.array type input) = .done result after) :
    evalExpr (fuel + 1) program (state rename.forward before)
        (.array type (CellRenaming.expressions rename.forward input)) =
      .done (value rename.forward result) (state rename.forward after) ∧ boundary ≤ after.nextCell := by
  simp only [evalExpr] at evaluated ⊢
  cases run : evalExprs fuel program before input with
  | done entries next =>
      obtain ⟨transport, nextReady⟩ := step.expressions ready run
      rw [transport]
      simp only [run, Outcome.done.injEq] at evaluated
      obtain ⟨rfl, rfl⟩ := evaluated
      exact ⟨rfl, nextReady⟩
  | _ => simp [run] at evaluated

theorem structExpression {rename : Permutation boundary} (step : Step fuel rename program)
    (before : State) (id : TypeId) (input : List Expr) (result : Value) (after : State)
    (ready : boundary ≤ before.nextCell)
    (evaluated : evalExpr (fuel + 1) program before (.structValue id input) = .done result after) :
    evalExpr (fuel + 1) program (state rename.forward before)
        (.structValue id (CellRenaming.expressions rename.forward input)) =
      .done (value rename.forward result) (state rename.forward after) ∧ boundary ≤ after.nextCell := by
  simp only [evalExpr] at evaluated ⊢
  cases run : evalExprs fuel program before input with
  | done entries next =>
      obtain ⟨transport, nextReady⟩ := step.expressions ready run
      rw [transport]
      simp only [run, Outcome.done.injEq] at evaluated
      obtain ⟨rfl, rfl⟩ := evaluated
      exact ⟨rfl, nextReady⟩
  | _ => simp [run] at evaluated

theorem enumExpression {rename : Permutation boundary} (step : Step fuel rename program)
    (before : State) (id : TypeId) (variant : VariantId) (input : List Expr) (result : Value) (after : State)
    (ready : boundary ≤ before.nextCell)
    (evaluated : evalExpr (fuel + 1) program before (.enumValue id variant input) = .done result after) :
    evalExpr (fuel + 1) program (state rename.forward before)
        (.enumValue id variant (CellRenaming.expressions rename.forward input)) =
      .done (value rename.forward result) (state rename.forward after) ∧ boundary ≤ after.nextCell := by
  simp only [evalExpr] at evaluated ⊢
  cases run : evalExprs fuel program before input with
  | done entries next =>
      obtain ⟨transport, nextReady⟩ := step.expressions ready run
      rw [transport]
      simp only [run, Outcome.done.injEq] at evaluated
      obtain ⟨rfl, rfl⟩ := evaluated
      exact ⟨rfl, nextReady⟩
  | _ => simp [run] at evaluated

theorem matchExpression {rename : Permutation boundary} (step : Step fuel rename program)
    (before : State) (input : Expr) (branches : List (Pattern × Expr)) (result : Value) (after : State)
    (ready : boundary ≤ before.nextCell)
    (evaluated : evalExpr (fuel + 1) program before (.matchValue input branches) = .done result after) :
    evalExpr (fuel + 1) program (state rename.forward before)
        (.matchValue (CellRenaming.expression rename.forward input) (CellRenaming.arms rename.forward branches)) =
      .done (value rename.forward result) (state rename.forward after) ∧ boundary ≤ after.nextCell := by
  simp only [evalExpr] at evaluated ⊢
  cases run : evalExpr fuel program before input with
  | done entry next =>
      obtain ⟨transport, nextReady⟩ := step.expression ready run
      rw [transport]
      simp only [run] at evaluated
      exact step.arms nextReady evaluated
  | _ => simp [run] at evaluated

theorem fieldExpression {rename : Permutation boundary} (step : Step fuel rename program)
    (before : State) (input : Expr) (field : FieldId) (result : Value) (after : State)
    (ready : boundary ≤ before.nextCell)
    (evaluated : evalExpr (fuel + 1) program before (.field input field) = .done result after) :
    evalExpr (fuel + 1) program (state rename.forward before)
        (.field (CellRenaming.expression rename.forward input) field) =
      .done (value rename.forward result) (state rename.forward after) ∧ boundary ≤ after.nextCell := by
  simp only [evalExpr] at evaluated ⊢
  cases run : evalExpr fuel program before input with
  | done entry next =>
      obtain ⟨transport, nextReady⟩ := step.expression ready run
      rw [transport]
      cases entry <;> simp only [run] at evaluated
      all_goals try contradiction
      case «structure» id fields =>
        cases selected : fields[field]? with
        | none => simp [selected] at evaluated
        | some entry =>
            simp only [selected, Outcome.done.injEq] at evaluated
            obtain ⟨rfl, rfl⟩ := evaluated
            exact ⟨by simp [value, values_eq_map, List.getElem?_map, selected], nextReady⟩
  | _ => simp [run] at evaluated

theorem indexExpression {rename : Permutation boundary} (step : Step fuel rename program)
    (before : State) (base index : Expr) (result : Value) (after : State)
    (ready : boundary ≤ before.nextCell)
    (evaluated : evalExpr (fuel + 1) program before (.index base index) = .done result after) :
    evalExpr (fuel + 1) program (state rename.forward before)
        (.index (CellRenaming.expression rename.forward base) (CellRenaming.expression rename.forward index)) =
      .done (value rename.forward result) (state rename.forward after) ∧ boundary ≤ after.nextCell := by
  simp only [evalExpr] at evaluated ⊢
  cases baseRun : evalExpr fuel program before base with
  | done entry afterBase =>
      obtain ⟨transport, baseReady⟩ := step.expression ready baseRun
      rw [transport]
      cases entry <;> simp only [baseRun] at evaluated
      all_goals try contradiction
      all_goals
        simp only [value, values_eq_map]
        cases indexRun : evalExpr fuel program afterBase index with
        | done indexValue afterIndex =>
            obtain ⟨indexTransport, indexReady⟩ := step.expression baseReady indexRun
            rw [indexTransport]
            simp only [indexRun] at evaluated
            simp only [integerIndex, CellRenaming.sliceValues, List.getElem?_map]
            repeat' first
              | split at evaluated
              | simp_all only [Option.map, Except.map, List.getElem?_map,
                  values_eq_map, Outcome.done.injEq]
            all_goals grind only
        | _ => simp [indexRun] at evaluated
  | _ => simp [baseRun] at evaluated

end Lanius.Semantics.CellRenaming.Execution

