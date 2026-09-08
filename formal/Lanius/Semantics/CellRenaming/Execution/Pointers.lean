import Lanius.Semantics.CellRenaming.Execution.Step
import Lanius.Semantics.CellRenaming.Execution.Bounds

namespace Lanius.Semantics.CellRenaming.Execution
open Lanius.Core

theorem stringPointerExpression {rename : Permutation boundary} (step : Step fuel rename program)
    (before : State) (input : Expr) (result : Value) (after : State)
    (ready : boundary ≤ before.nextCell)
    (evaluated : evalExpr (fuel + 1) program before (.stringDataPtr input) = .done result after) :
    evalExpr (fuel + 1) program (state rename.forward before)
        (.stringDataPtr (CellRenaming.expression rename.forward input)) =
      .done (value rename.forward result) (state rename.forward after) ∧ boundary ≤ after.nextCell := by
  simp only [evalExpr] at evaluated ⊢
  cases run : evalExpr fuel program before input with
  | done entry next =>
      obtain ⟨transport, nextReady⟩ := step.expression ready run
      rw [transport]
      cases entry <;> simp only [run] at evaluated
      all_goals try contradiction
      case string text =>
        simp only [value, CellRenaming.mapStringDataPtr, evaluated, outcome]
        exact ⟨trivial, (stringPointer_nextCell next after text result evaluated) ▸ nextReady⟩
  | _ => simp [run] at evaluated

theorem slicePointerExpression {rename : Permutation boundary} (step : Step fuel rename program)
    (before : State) (input : Expr) (result : Value) (after : State)
    (ready : boundary ≤ before.nextCell)
    (evaluated : evalExpr (fuel + 1) program before (.i32SliceDataPtr input) = .done result after) :
    evalExpr (fuel + 1) program (state rename.forward before)
        (.i32SliceDataPtr (CellRenaming.expression rename.forward input)) =
      .done (value rename.forward result) (state rename.forward after) ∧ boundary ≤ after.nextCell := by
  simp only [evalExpr] at evaluated ⊢
  cases run : evalExpr fuel program before input with
  | done entry next =>
      obtain ⟨transport, nextReady⟩ := step.expression ready run
      rw [transport]
      cases entry <;> simp only [run] at evaluated
      all_goals try contradiction
      case slice type root path start length =>
        cases type <;> try simp only [] at evaluated
        all_goals try contradiction
        case scalar type =>
          cases type <;> try simp only [] at evaluated
          all_goals try contradiction
          case signed type =>
            cases type <;> try simp only [] at evaluated
            all_goals try contradiction
            simp only [value, CellRenaming.mapI32SliceDataPtr, evaluated, outcome]
            exact ⟨trivial, (slicePointer_nextCell next after root path start length result evaluated) ▸ nextReady⟩
  | _ => simp [run] at evaluated

theorem rawSliceExpression {rename : Permutation boundary} (step : Step fuel rename program)
    (before : State) (pointer length : Expr) (result : Value) (after : State)
    (ready : boundary ≤ before.nextCell)
    (evaluated : evalExpr (fuel + 1) program before (.i32SliceFromRawParts pointer length) = .done result after) :
    evalExpr (fuel + 1) program (state rename.forward before)
        (.i32SliceFromRawParts (CellRenaming.expression rename.forward pointer)
          (CellRenaming.expression rename.forward length)) =
      .done (value rename.forward result) (state rename.forward after) ∧ boundary ≤ after.nextCell := by
  simp only [evalExpr] at evaluated ⊢
  cases pointerRun : evalExpr fuel program before pointer with
  | done entry next =>
      obtain ⟨transport, nextReady⟩ := step.expression ready pointerRun
      rw [transport]
      cases entry <;> simp only [pointerRun] at evaluated
      all_goals try contradiction
      case pointer address =>
        simp only [value]
        cases lengthRun : evalExpr fuel program next length with
        | done entry afterLength =>
            obtain ⟨lengthTransport, lengthReady⟩ := step.expression nextReady lengthRun
            rw [lengthTransport]
            cases entry <;> simp only [lengthRun] at evaluated
            all_goals try contradiction
            case signed type size =>
              cases type <;> simp only [] at evaluated
              all_goals try contradiction
              simp only [value, CellRenaming.mapRawI32Slice rename afterLength lengthReady,
                evaluated, outcome]
              exact ⟨trivial, (rawSlice_nextCell afterLength after address size result evaluated) ▸
                Nat.le_trans lengthReady (Nat.le_succ afterLength.nextCell)⟩
        | _ => simp [lengthRun] at evaluated
  | _ => simp [pointerRun] at evaluated

end Lanius.Semantics.CellRenaming.Execution
