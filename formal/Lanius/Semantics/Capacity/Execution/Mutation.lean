import Lanius.Semantics.Capacity.Execution.Step

namespace Lanius.Semantics.Capacity.Execution
open Lanius.Core

theorem assignmentExpression (step : Step fuel config allowed program) (ready : Ready config before)
    (placeSupported : Fragment.place allowed target = true) (inputSupported : Fragment.expression allowed input = true)
    (evaluated : evalExpr (fuel + 1) program before (.assign op target input) = .done result after) :
    evalExpr (fuel + 1) program (state config before) (.assign op target input) = .done (value config result) (state config after) ∧
      Ready config after ∧ closed config result = true := by
  simp only [evalExpr] at evaluated ⊢
  cases placeRun : evalPlace fuel program before target with
  | done resolved afterPlace =>
    obtain ⟨placeTransport, afterPlaceReady, placeReady⟩ := step.place ready placeSupported placeRun
    rw [placeTransport]
    simp only [resolvedPlace]
    simp only [placeRun] at evaluated
    cases inputRun : evalExpr fuel program afterPlace input with
    | done right afterInput =>
      obtain ⟨inputTransport, inputReady, rightClosed⟩ := step.expression afterPlaceReady inputSupported inputRun
      rw [inputTransport]
      simp only [inputRun] at evaluated
      simp only [assignment]
      cases assigned : evalAssignValue program.target op resolved.value right with
      | error reason => simp [assigned] at evaluated
      | ok replacement =>
        simp only [assigned, Except.map] at evaluated ⊢
        cases written : Semantics.writeResolvedPlace afterInput resolved replacement with
        | error reason => simp [written] at evaluated
        | ok next =>
          obtain ⟨writeTransport, nextReady⟩ := Capacity.writeResolvedPlace config inputReady placeReady
            (assignment_closed config rightClosed assigned) written
          simp only [resolvedPlace] at writeTransport
          rw [writeTransport]
          simp only [written, Outcome.done.injEq] at evaluated
          obtain ⟨rfl, rfl⟩ := evaluated
          exact ⟨rfl, nextReady, rfl⟩
    | _ => simp [inputRun] at evaluated
  | _ => simp [placeRun] at evaluated

theorem stringExpression (step : Step fuel config allowed program) (ready : Ready config before)
    (supported : Fragment.expression allowed input = true)
    (evaluated : evalExpr (fuel + 1) program before (.stringDataPtr input) = .done result after) :
    evalExpr (fuel + 1) program (state config before) (.stringDataPtr input) = .done (value config result) (state config after) ∧
      Ready config after ∧ closed config result = true := by
  simp only [evalExpr] at evaluated ⊢
  cases run : evalExpr fuel program before input with
  | done entry next =>
    obtain ⟨transport, nextReady, entryClosed⟩ := step.expression ready supported run
    clear entryClosed
    rw [transport]
    cases entry <;> simp only [run] at evaluated
    all_goals try contradiction
    case string text => exact stringDataPtr config nextReady evaluated
  | _ => simp [run] at evaluated

theorem rawSliceExpression (valid : config.Valid) (step : Step fuel config allowed program) (ready : Ready config before)
    (pointerSupported : Fragment.expression allowed pointer = true) (lengthSupported : Fragment.expression allowed length = true)
    (evaluated : evalExpr (fuel + 1) program before (.i32SliceFromRawParts pointer length) = .done result after) :
    evalExpr (fuel + 1) program (state config before) (.i32SliceFromRawParts pointer length) = .done (value config result) (state config after) ∧
      Ready config after ∧ closed config result = true := by
  simp only [evalExpr] at evaluated ⊢
  cases pointerRun : evalExpr fuel program before pointer with
  | done entry afterPointer =>
    obtain ⟨pointerTransport, pointerReady, entryClosed⟩ := step.expression ready pointerSupported pointerRun
    clear entryClosed
    rw [pointerTransport]
    cases entry <;> simp only [pointerRun] at evaluated
    all_goals try contradiction
    case pointer address =>
      simp only [value]
      cases lengthRun : evalExpr fuel program afterPointer length with
      | done entry afterLength =>
        obtain ⟨lengthTransport, lengthReady, entryClosed⟩ := step.expression pointerReady lengthSupported lengthRun
        clear entryClosed
        rw [lengthTransport]
        cases entry <;> simp only [lengthRun] at evaluated
        all_goals try contradiction
        case signed type count =>
          cases type <;> try contradiction
          exact rawI32Slice valid lengthReady evaluated
      | _ => simp [lengthRun] at evaluated
  | _ => simp [pointerRun] at evaluated

end Lanius.Semantics.Capacity.Execution
