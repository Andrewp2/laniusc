import Lanius.CallContracts

namespace Lanius.CallContracts

open Lanius Lanius.Core Lanius.Semantics

/-- Host-call composition follows the actual evaluator boundary, including
both raw-view synchronization passes. A theorem about `World.call` alone does
not establish a source-level call because either synchronization can trap. -/
theorem evaluatesHostCallReturned
    (argumentsResult :
      ArgumentsEvaluateTo program before arguments values afterArguments)
    (functionFound : program.function? function.id = some function)
    (parametersBound : bindParameters function.parameters values = some bindings)
    (noBody : function.body = none)
    (host : function.external = some (.host service))
    (synchronized : syncI32ViewsToHeap afterArguments = .ok ready)
    (called : World.call ready.heap ready.world service values =
      .returned result heap world)
    (refreshed : syncI32ViewsFromHeap { ready with heap, world } = .ok after) :
    Evaluates program before (.call function.id arguments) result after := by
  obtain ⟨fuel, evaluated⟩ := argumentsResult
  refine ⟨fuel + 1, ?_⟩
  rw [Lanius.Semantics.evalExpr.eq_def]
  simp only
  rw [evaluated]
  simp only
  rw [functionFound]
  simp only
  rw [parametersBound, noBody]
  simp only
  rw [host]
  simp only
  rw [synchronized]
  simp only
  rw [called]
  simp [worldCallOutcome, refreshed]

/-- Invert a successful source-level host call. Both synchronization passes
and the returned host effect are consequences of the observed evaluation. -/
theorem evaluatesHostCallReturned_invert
    (argumentsResult : ArgumentsEvaluateTo program before arguments values afterArguments)
    (functionFound : program.function? function.id = some function)
    (parametersBound : bindParameters function.parameters values = some bindings)
    (noBody : function.body = none)
    (host : function.external = some (.host service))
    (actual : Evaluates program before (.call function.id arguments) result after) :
    ∃ ready heap world,
      syncI32ViewsToHeap afterArguments = .ok ready ∧
      World.call ready.heap ready.world service values = .returned result heap world ∧
      syncI32ViewsFromHeap { ready with heap, world } = .ok after := by
  obtain ⟨fuel, executed⟩ := actual
  cases fuel with
  | zero => simp [evalExpr] at executed
  | succ fuel =>
      rw [evalExpr.eq_def] at executed
      simp only at executed
      cases evaluated : evalExprs fuel program before arguments with
      | outOfFuel => simp [evaluated] at executed
      | trapped reason state => simp [evaluated] at executed
      | exited code state => simp [evaluated] at executed
      | done actualValues state =>
          obtain ⟨sameValues, sameState⟩ := argumentsEvaluateTo_deterministic
            (show ArgumentsEvaluateTo program before arguments actualValues state from ⟨fuel, evaluated⟩)
            argumentsResult
          subst actualValues
          subst state
          simp only [evaluated, functionFound, parametersBound, noBody, host] at executed
          cases synced : syncI32ViewsToHeap afterArguments with
          | error reason => simp [synced] at executed
          | ok ready =>
              simp only [synced] at executed
              cases called : World.call ready.heap ready.world service values with
              | exited code heap world =>
                  cases refreshed : syncI32ViewsFromHeap { ready with heap, world } <;>
                    simp [called, worldCallOutcome, refreshed] at executed
              | unavailable unavailableService heap world => simp [called, worldCallOutcome] at executed
              | trapped reason heap world => simp [called, worldCallOutcome] at executed
              | typeMismatch heap world => simp [called, worldCallOutcome] at executed
              | returned value heap world =>
                  simp only [called, worldCallOutcome] at executed
                  cases refreshed : syncI32ViewsFromHeap { ready with heap, world } with
                  | error reason => simp [refreshed] at executed
                  | ok completed =>
                      simp only [refreshed, Outcome.done.injEq] at executed
                      obtain ⟨rfl, rfl⟩ := executed
                      refine ⟨ready, heap, world, ?_, ?_, ?_⟩ <;> first | rfl | assumption

end Lanius.CallContracts
