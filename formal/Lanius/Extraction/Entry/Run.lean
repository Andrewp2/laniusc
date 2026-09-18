import Lanius.Extraction.Entry.Startup.Run

namespace Lanius.Extraction.Entry.Run
open Lanius Lanius.Core Lanius.Semantics Lanius.Properties Lanius.CallContracts
open Lanius.Extraction.CoreSynthesis.Program Lanius.Extraction.EntrypointAnalysis
open Lanius.Extraction.ExtractorContract

variable {program : CheckedProgram artifacts}
variable {entrypoint : CheckedEntrypoint program modulePath name}

/-- The accepted source entrypoint supplies the body typing needed by the
whole-main theorem. It is not a separate assumption on an arbitrary statement. -/
theorem body_typed (analysis : AnalyzedEntrypoint program entrypoint) :
    Typing.StmtHasType program.core entrypoint.function.returnType
      Typing.Context.empty false analysis.body := by
  have member : entrypoint.function ∈ program.core.functions :=
    List.mem_of_find?_eq_some entrypoint.found
  have typed := program.typed.2 entrypoint.function member
  simp only [Typing.FunctionWellTyped, analysis.bodyPresent] at typed
  simpa only [entrypoint.noParameters, Typing.parameterContext, List.foldl_nil] using typed.2.1

/-- Transfer an actual main-body execution through its checked zero-argument
call boundary. This applies to early rejection as well as successful loading. -/
theorem call (analysis : AnalyzedEntrypoint program entrypoint)
    (empty : before.locals = [])
    (executed : Executes program.core before analysis.body
      (.returned (some value)) completed) :
    Evaluates program.core before (.call entrypoint.source.id []) value
      (restoreLocals before completed) := by
  have identity : entrypoint.function.id = entrypoint.source.id := by
    simpa using (List.find?_some entrypoint.found)
  have entered : Lanius.Separation.enterCall before [] = before := by
    simp only [Lanius.Separation.enterCall, State.bindLocals, List.foldl_nil]
    rw [← empty]
  have called := evaluatesCallReturned (ArgumentsEvaluateTo.nil program.core before)
    (by simpa only [identity] using entrypoint.found)
    (show bindParameters entrypoint.function.parameters [] = some [] by
      simp [entrypoint.noParameters, bindParameters])
    analysis.bodyPresent (by simpa only [entered] using executed)
  simpa only [identity] using called

/-- Invoke the actual zero-argument entrypoint using its complete body proof.
The checked function lookup and ABI establish the call; restoring the caller's
locals preserves the exact I/O and memory portions of both public contracts. -/
theorem evaluates (analysis : AnalyzedEntrypoint program entrypoint)
    (empty : before.locals = [])
    (body : ∃ code after,
      Executes program.core before analysis.body (.returned (some (.signed .i32 code))) after ∧
      (code = 0 → Nonempty (Success before after)) ∧
      (code ≠ 0 → Nonempty (Failure before after code)) ∧
      (SuccessDomain before.world → code = 0)) :
    ∃ code after,
      Evaluates program.core before (.call entrypoint.source.id []) (.signed .i32 code) after ∧
      (code = 0 → Nonempty (Success before after)) ∧
      (code ≠ 0 → Nonempty (Failure before after code)) ∧
      (SuccessDomain before.world → code = 0) := by
  obtain ⟨code, completed, executed, success, failure, complete⟩ := body
  refine ⟨code, restoreLocals before completed, call analysis empty executed, ?_, ?_, complete⟩
  · intro zero
    obtain ⟨post⟩ := success zero
    exact ⟨{ post with memorySafe := post.memorySafe }⟩
  · intro nonzero
    obtain ⟨post⟩ := failure nonzero
    exact ⟨{ post with memorySafe := post.memorySafe }⟩

theorem observation_of_evaluates
    (evaluated : Evaluates core before expression value after) (fuel : Nat) :
    evalExpr fuel core before expression = .outOfFuel ∨
      evalExpr fuel core before expression = .done value after := by
  by_cases exhausted : evalExpr fuel core before expression = .outOfFuel
  · exact .inl exhausted
  · right
    obtain ⟨bound, witnessed⟩ := evaluated
    have terminal : Lanius.Fuel.Terminal (evalExpr fuel core before expression) := by
      cases outcome : evalExpr fuel core before expression <;>
        simp_all [Lanius.Fuel.Terminal]
    have stable := Lanius.Fuel.evalExpr_more_fuel (extra := max fuel bound - fuel) terminal
    rw [Nat.sub_add_cancel (Nat.le_max_left _ _)] at stable
    exact stable.symm.trans
      (Lanius.Fuel.evalExpr_done_at_larger_fuel (Nat.le_max_right _ _) witnessed)

/-- A proved entrypoint run gives the public contracts at every fuel bound.
There is a finite bound above which the exact process result is stable. Below
it the only alternative is fuel exhaustion: traps, host exits, different
return values, and different final states are excluded by fuel stability. -/
theorem observations (entrypoint : CheckedEntrypoint program modulePath name)
    (verified : ∃ code after,
      Evaluates program.core before (.call entrypoint.source.id []) (.signed .i32 code) after ∧
      (code = 0 → Nonempty (Success before after)) ∧
      (code ≠ 0 → Nonempty (Failure before after code)) ∧
      (SuccessDomain before.world → code = 0)) :
    ∃ code after bound,
      (∀ fuel, bound ≤ fuel → Lanius.Execution.run fuel entrypoint.executable before =
        .returned (.signed .i32 code) after) ∧
      (∀ fuel, Lanius.Execution.run fuel entrypoint.executable before = .outOfFuel ∨
        Lanius.Execution.run fuel entrypoint.executable before = .returned (.signed .i32 code) after) ∧
      (∀ fuel,
        RunSound before (evalExpr fuel program.core before (.call entrypoint.source.id [])) ∧
        RunFailureSafe before (evalExpr fuel program.core before (.call entrypoint.source.id []))) ∧
      (SuccessDomain before.world → code = 0) := by
  obtain ⟨code, after, evaluated, success, failure, complete⟩ := verified
  obtain ⟨bound, witnessed⟩ := evaluated
  refine ⟨code, after, bound, ?_, ?_, ?_, complete⟩
  · intro fuel enough
    have done := Lanius.Fuel.evalExpr_done_at_larger_fuel enough witnessed
    simp only [entrypoint.executableDefinition, Lanius.Execution.run, done]
  · intro fuel
    rcases observation_of_evaluates ⟨bound, witnessed⟩ fuel with exhausted | done
    · exact .inl (by simp only [entrypoint.executableDefinition, Lanius.Execution.run, exhausted])
    · exact .inr (by simp only [entrypoint.executableDefinition, Lanius.Execution.run, done])
  · intro fuel
    rcases observation_of_evaluates ⟨bound, witnessed⟩ fuel with exhausted | done
    · constructor <;> intro result final returned <;> rw [exhausted] at returned <;> contradiction
    · constructor
      · intro result final returned zero
        rw [done] at returned
        cases returned
        exact success zero
      · intro result final returned nonzero
        rw [done] at returned
        cases returned
        exact failure nonzero

end Lanius.Extraction.Entry.Run
