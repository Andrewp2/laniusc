import Lanius.Semantics.Capacity.Execution.Step

namespace Lanius.Semantics.Capacity.Execution
open Lanius.Core

theorem expressions (step : Step fuel config allowed program) (ready : Ready config before)
    (supported : Fragment.expressions allowed input = true)
    (evaluated : evalExprs (fuel + 1) program before input = .done result after) :
    evalExprs (fuel + 1) program (state config before) input = .done (values config result) (state config after) ∧
      Ready config after ∧ closeds config result = true := by
  cases input with
  | nil => cases evaluated; exact ⟨rfl, ready, rfl⟩
  | cons first rest =>
    have parts : Fragment.expression allowed first = true ∧ Fragment.expressions allowed rest = true := by
      simpa only [Fragment.expressions, Bool.and_eq_true] using supported
    simp only [evalExprs] at evaluated
    cases headRun : evalExpr fuel program before first with
    | done head next =>
      obtain ⟨headTransport, nextReady, headClosed⟩ := step.expression ready parts.1 headRun
      simp only [headRun] at evaluated
      cases tailRun : evalExprs fuel program next rest with
      | done tail completed =>
        obtain ⟨tailTransport, completedReady, tailClosed⟩ := step.expressions nextReady parts.2 tailRun
        simp only [tailRun, Outcome.done.injEq] at evaluated
        obtain ⟨rfl, rfl⟩ := evaluated
        exact ⟨by simp only [evalExprs, headTransport, tailTransport, values], completedReady,
          by simp only [closeds, headClosed, tailClosed, Bool.and_self]⟩
      | _ => simp [tailRun] at evaluated
    | _ => simp [headRun] at evaluated

def bindings (config : Config) (entries : List (VarId × Value)) : List (VarId × Value) :=
  entries.map fun entry => (entry.1, value config entry.2)

theorem parameters (config : Config) (parameters : List (VarId × Ty)) (entries : List Value) :
    bindParameters parameters (values config entries) = (bindParameters parameters entries).map (bindings config) := by
  simp only [bindParameters, values_length]
  split
  · simp only [Option.map_some, bindings, List.map_map, values_eq_map, List.zip_map_right]
    rfl
  · rfl

theorem parameters_closed {parameters : List (VarId × Ty)} (entriesClosed : closeds config entries = true)
    (bound : bindParameters parameters entries = some locals) :
    ∀ binding ∈ locals, closed config binding.2 = true := by
  simp only [bindParameters] at bound
  split at bound
  · cases bound
    intro binding member
    obtain ⟨pair, pairMember, rfl⟩ := List.mem_map.mp member
    exact (closeds_iff config entries).mp entriesClosed pair.2 (List.of_mem_zip pairMember).2
  · contradiction

theorem bindLocals (valid : config.Valid) (ready : Ready config before)
    (entriesClosed : ∀ binding ∈ entries, closed config binding.2 = true) :
    (state config before).bindLocals (bindings config entries) = state config (before.bindLocals entries) ∧
      Ready config (before.bindLocals entries) := by
  induction entries generalizing before with
  | nil => exact ⟨rfl, ready⟩
  | cons first rest ih =>
    have firstClosed := entriesClosed first (by simp)
    have restClosed : ∀ binding ∈ rest, closed config binding.2 = true :=
      fun binding member => entriesClosed binding (List.mem_cons_of_mem _ member)
    obtain ⟨transport, afterReady⟩ := ih (ready.bindLocal valid first.1 first.2 firstClosed) restClosed
    refine ⟨?_, afterReady⟩
    simpa only [State.bindLocals, bindings, List.map_cons, List.foldl_cons, State.bindLocal, bindCell valid before ready.frontier,
      Option.map_some] using transport

end Lanius.Semantics.Capacity.Execution
