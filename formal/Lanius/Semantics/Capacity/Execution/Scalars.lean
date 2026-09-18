import Lanius.Semantics.Capacity.Execution.Step

namespace Lanius.Semantics.Capacity.Execution
open Lanius.Core

theorem localExpression {id : VarId} (valid : config.Valid) (ready : Ready config before)
    (evaluated : evalExpr (fuel + 1) program before (.local id) = .done result after) :
    evalExpr (fuel + 1) program (state config before) (.local id) = .done (value config result) (state config after) ∧
      Ready config after ∧ closed config result = true := by
  simp only [evalExpr] at evaluated ⊢
  simp only [show (state config before).cellId? id = before.cellId? id from rfl, cellEntry]
  cases binding : before.cellId? id with
  | none => simp [binding] at evaluated
  | some root =>
    have lower := ready.localCell binding
    have reachable : config.reachable root = true := by simp [Config.reachable, lower]
    have different : root ≠ config.root := Ne.symm (Nat.ne_of_lt (Nat.lt_of_lt_of_le valid.old lower))
    simp only [binding] at evaluated ⊢
    cases selected : before.cellEntry? root with
    | none => simp [selected] at evaluated
    | some entry =>
      have sameId : entry.id = root := by simpa using List.find?_some selected
      rcases entry with ⟨entryId, contents⟩
      change entryId = root at sameId
      cases contents with
      | none => simp [selected] at evaluated
      | some entry =>
        simp only [selected, Outcome.done.injEq] at evaluated
        obtain ⟨rfl, rfl⟩ := evaluated
        exact ⟨by simp [selected, cell, sameId, stored_reachable config reachable different], ready,
          ready.cellClosed reachable (by simp [State.cell?, selected])⟩

theorem castExpression (step : Step fuel config allowed program) (ready : Ready config before)
    (supported : Fragment.expression allowed input = true)
    (evaluated : evalExpr (fuel + 1) program before (.cast op input) = .done result after) :
    evalExpr (fuel + 1) program (state config before) (.cast op input) = .done (value config result) (state config after) ∧
      Ready config after ∧ closed config result = true := by
  simp only [evalExpr] at evaluated ⊢
  cases run : evalExpr fuel program before input with
  | done entry next =>
    obtain ⟨transport, nextReady, _⟩ := step.expression ready supported run
    rw [transport]
    simp only [run] at evaluated
    simp only [cast]
    cases computed : evalScalarCast program.target op entry with
    | error reason => simp [computed] at evaluated
    | ok answer =>
      simp only [computed, Outcome.done.injEq] at evaluated
      obtain ⟨rfl, rfl⟩ := evaluated
      exact ⟨rfl, nextReady, plain_closed config _ (cast_plain computed)⟩
  | _ => simp [run] at evaluated

theorem unaryExpression (step : Step fuel config allowed program) (ready : Ready config before)
    (supported : Fragment.expression allowed input = true)
    (evaluated : evalExpr (fuel + 1) program before (.unary op input) = .done result after) :
    evalExpr (fuel + 1) program (state config before) (.unary op input) = .done (value config result) (state config after) ∧
      Ready config after ∧ closed config result = true := by
  simp only [evalExpr] at evaluated ⊢
  cases run : evalExpr fuel program before input with
  | done entry next =>
    obtain ⟨transport, nextReady, _⟩ := step.expression ready supported run
    rw [transport]
    simp only [run] at evaluated
    simp only [unary]
    cases computed : evalUnaryValue program.target op entry with
    | error reason => simp [computed] at evaluated
    | ok answer =>
      simp only [computed, Outcome.done.injEq] at evaluated
      obtain ⟨rfl, rfl⟩ := evaluated
      exact ⟨rfl, nextReady, plain_closed config _ (unary_plain computed)⟩
  | _ => simp [run] at evaluated

theorem binaryExpression (step : Step fuel config allowed program) (ready : Ready config before)
    (leftSupported : Fragment.expression allowed left = true) (rightSupported : Fragment.expression allowed right = true)
    (evaluated : evalExpr (fuel + 1) program before (.binary op left right) = .done result after) :
    evalExpr (fuel + 1) program (state config before) (.binary op left right) = .done (value config result) (state config after) ∧
      Ready config after ∧ closed config result = true := by
  cases op with
  | logicalAnd =>
    simp only [evalExpr] at evaluated ⊢
    cases run : evalExpr fuel program before left with
    | done entry next =>
      obtain ⟨transport, nextReady, entryClosed⟩ := step.expression ready leftSupported run
      clear entryClosed
      rw [transport]
      cases entry <;> simp only [run] at evaluated
      all_goals try contradiction
      case boolean flag =>
        cases flag <;> simp only [value]
        · obtain ⟨rfl, rfl⟩ := Outcome.done.inj evaluated; exact ⟨rfl, nextReady, rfl⟩
        · exact step.expression nextReady rightSupported evaluated
    | _ => simp [run] at evaluated
  | logicalOr =>
    simp only [evalExpr] at evaluated ⊢
    cases run : evalExpr fuel program before left with
    | done entry next =>
      obtain ⟨transport, nextReady, entryClosed⟩ := step.expression ready leftSupported run
      clear entryClosed
      rw [transport]
      cases entry <;> simp only [run] at evaluated
      all_goals try contradiction
      case boolean flag =>
        cases flag <;> simp only [value]
        · exact step.expression nextReady rightSupported evaluated
        · obtain ⟨rfl, rfl⟩ := Outcome.done.inj evaluated; exact ⟨rfl, nextReady, rfl⟩
    | _ => simp [run] at evaluated
  | _ =>
    simp only [evalExpr] at evaluated ⊢
    cases leftRun : evalExpr fuel program before left with
    | done leftValue afterLeft =>
      obtain ⟨leftTransport, leftReady, _⟩ := step.expression ready leftSupported leftRun
      rw [leftTransport]
      simp only []
      simp only [leftRun] at evaluated
      cases rightRun : evalExpr fuel program afterLeft right with
      | done rightValue afterRight =>
        obtain ⟨rightTransport, rightReady, _⟩ := step.expression leftReady rightSupported rightRun
        rw [rightTransport]
        simp only [rightRun] at evaluated
        simp only [binary]
        split at evaluated
        · rename_i answer computed
          obtain ⟨rfl, rfl⟩ := Outcome.done.inj evaluated
          exact ⟨by simp only [computed, Except.map], rightReady, plain_closed config _ (binary_plain computed)⟩
        · contradiction
      | _ => simp [rightRun] at evaluated
    | _ => simp [leftRun] at evaluated

end Lanius.Semantics.Capacity.Execution
