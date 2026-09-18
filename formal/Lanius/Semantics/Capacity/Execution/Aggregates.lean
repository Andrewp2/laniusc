import Lanius.Semantics.Capacity.Execution.Step

namespace Lanius.Semantics.Capacity.Execution
open Lanius.Core

theorem arrayExpression (step : Step fuel config allowed program) (ready : Ready config before)
    (supported : Fragment.expressions allowed input = true)
    (evaluated : evalExpr (fuel + 1) program before (.array type input) = .done result after) :
    evalExpr (fuel + 1) program (state config before) (.array type input) = .done (value config result) (state config after) ∧
      Ready config after ∧ closed config result = true := by
  simp only [evalExpr] at evaluated ⊢
  cases run : evalExprs fuel program before input with
  | done entries next =>
    obtain ⟨transport, nextReady, entriesClosed⟩ := step.expressions ready supported run
    rw [transport]
    simp only [run, Outcome.done.injEq] at evaluated
    obtain ⟨rfl, rfl⟩ := evaluated
    exact ⟨rfl, nextReady, entriesClosed⟩
  | _ => simp [run] at evaluated

theorem structExpression {id : TypeId} (step : Step fuel config allowed program) (ready : Ready config before)
    (supported : Fragment.expressions allowed input = true)
    (evaluated : evalExpr (fuel + 1) program before (.structValue id input) = .done result after) :
    evalExpr (fuel + 1) program (state config before) (.structValue id input) = .done (value config result) (state config after) ∧
      Ready config after ∧ closed config result = true := by
  simp only [evalExpr] at evaluated ⊢
  cases run : evalExprs fuel program before input with
  | done entries next =>
    obtain ⟨transport, nextReady, entriesClosed⟩ := step.expressions ready supported run
    rw [transport]
    simp only [run, Outcome.done.injEq] at evaluated
    obtain ⟨rfl, rfl⟩ := evaluated
    exact ⟨rfl, nextReady, entriesClosed⟩
  | _ => simp [run] at evaluated

theorem enumExpression {id : TypeId} (step : Step fuel config allowed program) (ready : Ready config before)
    (supported : Fragment.expressions allowed input = true)
    (evaluated : evalExpr (fuel + 1) program before (.enumValue id variant input) = .done result after) :
    evalExpr (fuel + 1) program (state config before) (.enumValue id variant input) = .done (value config result) (state config after) ∧
      Ready config after ∧ closed config result = true := by
  simp only [evalExpr] at evaluated ⊢
  cases run : evalExprs fuel program before input with
  | done entries next =>
    obtain ⟨transport, nextReady, entriesClosed⟩ := step.expressions ready supported run
    rw [transport]
    simp only [run, Outcome.done.injEq] at evaluated
    obtain ⟨rfl, rfl⟩ := evaluated
    exact ⟨rfl, nextReady, entriesClosed⟩
  | _ => simp [run] at evaluated

theorem fieldExpression (step : Step fuel config allowed program) (ready : Ready config before)
    (supported : Fragment.expression allowed input = true)
    (evaluated : evalExpr (fuel + 1) program before (.field input field) = .done result after) :
    evalExpr (fuel + 1) program (state config before) (.field input field) = .done (value config result) (state config after) ∧
      Ready config after ∧ closed config result = true := by
  simp only [evalExpr] at evaluated ⊢
  cases run : evalExpr fuel program before input with
  | done entry next =>
    obtain ⟨transport, nextReady, entryClosed⟩ := step.expression ready supported run
    rw [transport]
    cases entry <;> simp only [run] at evaluated
    all_goals try contradiction
    case «structure» id fields =>
      cases selected : fields[field]? with
      | none => simp [selected] at evaluated
      | some entry =>
        simp only [selected, Outcome.done.injEq] at evaluated
        obtain ⟨rfl, rfl⟩ := evaluated
        exact ⟨by simp [value, selected], nextReady,
          (closeds_iff config fields).mp entryClosed entry (List.mem_of_getElem? selected)⟩
  | _ => simp [run] at evaluated

theorem indexExpression (step : Step fuel config allowed program) (ready : Ready config before)
    (baseSupported : Fragment.expression allowed base = true) (indexSupported : Fragment.expression allowed indexExpr = true)
    (evaluated : evalExpr (fuel + 1) program before (.index base indexExpr) = .done result after) :
    evalExpr (fuel + 1) program (state config before) (.index base indexExpr) = .done (value config result) (state config after) ∧
      Ready config after ∧ closed config result = true := by
  simp only [evalExpr] at evaluated ⊢
  cases baseRun : evalExpr fuel program before base with
  | done entry afterBase =>
    obtain ⟨transport, baseReady, entryClosed⟩ := step.expression ready baseSupported baseRun
    rw [transport]
    cases entry <;> simp only [baseRun] at evaluated
    all_goals try contradiction
    case array elements =>
      simp only [value]
      cases indexRun : evalExpr fuel program afterBase indexExpr with
      | done indexValue afterIndex =>
        obtain ⟨indexTransport, indexReady, _⟩ := step.expression baseReady indexSupported indexRun
        rw [indexTransport]
        simp only [indexRun] at evaluated
        simp only [integerIndex]
        cases converted : Semantics.integerIndex indexValue with
        | error reason => simp [converted] at evaluated
        | ok index =>
          simp only [converted] at evaluated ⊢
          cases selected : elements[index]? with
          | none => simp [selected] at evaluated
          | some entry =>
            simp only [selected, Outcome.done.injEq] at evaluated
            obtain ⟨rfl, rfl⟩ := evaluated
            exact ⟨by simp [selected], indexReady,
              (closeds_iff config elements).mp entryClosed entry (List.mem_of_getElem? selected)⟩
      | _ => simp [indexRun] at evaluated
    case slice type root path start length =>
      simp only [value]
      cases indexRun : evalExpr fuel program afterBase indexExpr with
      | done indexValue afterIndex =>
        obtain ⟨indexTransport, indexReady, _⟩ := step.expression baseReady indexSupported indexRun
        rw [indexTransport]
        simp only [indexRun] at evaluated
        simp only [integerIndex]
        cases converted : Semantics.integerIndex indexValue with
        | error reason => simp [converted] at evaluated
        | ok index =>
          simp only [converted] at evaluated ⊢
          split at evaluated
          · rename_i inside
            have expandedInside := Nat.lt_of_lt_of_le inside (extent_le config root path length)
            change index < (if root = config.root ∧ path = [] then length + config.tail.length else length) at expandedInside
            rw [if_pos expandedInside]
            cases read : sliceValues afterIndex root path start length with
            | error reason => simp [read] at evaluated
            | ok elements =>
              simp only [read] at evaluated
              cases selected : elements[index]? with
              | none => simp [selected] at evaluated
              | some entry =>
                obtain ⟨expanded, readTransport, selectedTransport, resultClosed⟩ := slice_index config indexReady entryClosed inside read selected
                simp only [extent] at readTransport
                simp only [readTransport, selectedTransport]
                simp only [selected, Outcome.done.injEq] at evaluated
                obtain ⟨rfl, rfl⟩ := evaluated
                exact ⟨rfl, indexReady, resultClosed⟩
          · contradiction
      | _ => simp [indexRun] at evaluated
  | _ => simp [baseRun] at evaluated

end Lanius.Semantics.Capacity.Execution
