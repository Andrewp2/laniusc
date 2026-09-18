import Lanius.Extraction.Entry.Domain.Host
import Lanius.Extraction.Entry.Failure

namespace Lanius.Extraction.Entry
open Lanius.Core Lanius.Semantics Lanius.Extraction.ExtractorContract

/-- Finite normal execution, no traps at any fuel, and the original exact
success/failure contracts. Unlike `ExecutionCorrect`, this does not require
all requested files to be available or fit their buffers. -/
def ExecutionSafe (executable : Lanius.Execution.Executable) (world : Lanius.World.State) : Prop :=
  let before : State := { world }
  ∃ code after bound,
    (∀ fuel, bound ≤ fuel → Lanius.Execution.run fuel executable before =
      .returned (.signed .i32 code) after) ∧
    (∀ fuel, Lanius.Execution.run fuel executable before = .outOfFuel ∨
      Lanius.Execution.run fuel executable before = .returned (.signed .i32 code) after) ∧
    (∀ fuel,
      RunSound before (evalExpr fuel executable.program before (.call executable.entrypoint [])) ∧
      RunFailureSafe before (evalExpr fuel executable.program before (.call executable.entrypoint [])))

theorem ExecutionCorrect.safe (correct : ExecutionCorrect executable world) : ExecutionSafe executable world := by
  obtain ⟨code, after, bound, stable, observations, contracts, _⟩ := correct
  exact ⟨code, after, bound, stable, observations, contracts⟩

theorem RejectedExecution.safe (rejected : RejectedExecution executable ({ world } : State) code) :
    ExecutionSafe executable world := by
  obtain ⟨bound, stable⟩ := rejected.terminates
  exact ⟨code, rejected.after, bound, stable, rejected.observations, rejected.contracts⟩

/-- One actual-executable result covers all host-bounded invocations: no
inputs, arbitrary available file contents, or the first invalid/missing/
oversized file at any position. The host assumptions say nothing about parsing,
extraction success, accepted output, or intermediate caller invariants. -/
theorem CheckedExecution.hostSafe (checked : CheckedExecution accepted) (domain : HostDomain world) :
    ExecutionSafe accepted.entrypoint.executable world := by
  rcases domain.classify with missing | loading | ⟨code, issue⟩ | later
  · exact (checked.noInputs world missing).safe
  · exact (checked.correct world loading).safe
  · have enough : 1 < world.arguments.length := issue.index_lt
    cases issue with
    | path bad =>
      cases bad with
      | invalid path selected size invalid =>
        obtain ⟨rejected, _⟩ := checked.invalidPath world enough domain.bounded path selected size invalid
        exact rejected.safe
      | missing path selected nonempty fits absent =>
        obtain ⟨rejected, _⟩ := checked.missingFile world enough domain.bounded path selected nonempty fits absent
        exact rejected.safe
    | oversized path file selected found nonempty fits oversize =>
      have supported : OversizedFileDomain world := ⟨domain.bounded,
        ⟨path, file, selected, found, nonempty, fits, oversize⟩,
        by have room := domain.handles; omega, domain.olderHandles⟩
      obtain ⟨rejected, _⟩ := checked.oversizedFile supported
      exact rejected.safe
  · obtain ⟨_, rejected, _⟩ := checked.laterFailure later
    exact rejected.safe

end Lanius.Extraction.Entry
