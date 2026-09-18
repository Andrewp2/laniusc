import Lanius.Extraction.Entry.Run
import Lanius.Extraction.Entry.Files.First
import Lanius.Extraction.Entry.File.Rejection

namespace Lanius.Extraction.Entry
open Lanius Lanius.Core Lanius.Semantics
open Lanius.Extraction.EntrypointAnalysis Lanius.Extraction.ExtractorContract

/-- External inputs covered by the current whole-extractor execution proof.
This is a loading domain, not a claim that the files have valid syntax or that
extraction succeeds. The process starts with an empty, unlimited-budget heap. -/
structure LoadingDomain (world : Lanius.World.State) : Prop where
  enough : 1 < world.arguments.length
  bounded : world.arguments.length < 2 ^ 31
  requests : ∃ request rest, Files.Pending world 1 (request :: rest) ∧
    1 + (request :: rest).length = world.arguments.length ∧
    world.nextFileHandle + rest.length ≤ 2147483647
  olderHandles : ∀ handle ∈ world.fileHandles, handle.id < (world.nextFileHandle : Int)

/-- A nonempty loadable prefix followed by an invalid/missing path or an oversized file.
The prefix may have arbitrary source syntax; an earlier frontend/output
rejection is permitted. Arguments after the rejected file are unrestricted. -/
structure LaterFailureDomain (world : Lanius.World.State) : Prop where
  bounded : world.arguments.length < 2 ^ 31
  requests : ∃ request rest code, Files.Pending world 1 (request :: rest) ∧
    File.Rejection world (1 + (request :: rest).length) code ∧
    world.nextFileHandle + rest.length + File.Rejection.additionalHandles code ≤ 2147483647
  olderHandles : ∀ handle ∈ world.fileHandles, handle.id < (world.nextFileHandle : Int)

/-- An existing first file whose bytes exceed the source allocation. Its
syntax and all later arguments are unrestricted. The ordinary initial heap
is empty with an unlimited allocation budget. -/
structure OversizedFileDomain (world : Lanius.World.State) : Prop where
  bounded : world.arguments.length < 2 ^ 31
  request : ∃ path file, world.arguments[1]? = some path ∧
    world.file? (Lanius.World.utf8Bytes path) = some file ∧
    0 < path.toUTF8.size ∧ path.toUTF8.size ≤ 1024 ∧ 65536 < file.bytes.length
  handleFit : world.nextFileHandle ≤ 2147483647
  olderHandles : ∀ handle ∈ world.fileHandles, handle.id < (world.nextFileHandle : Int)

/-- Finite classified rejection with unchanged stdout. The accepted entrypoint
is executed; this is not merely an implication from an assumed error return. -/
def ExecutionRejects (executable : Lanius.Execution.Executable) (world : Lanius.World.State) : Prop :=
  ∃ code after, Evaluates executable.program ({ world } : State)
      (.call executable.entrypoint []) (.signed .i32 code) after ∧
    Nonempty (Failure ({ world } : State) after code) ∧ after.world.standardOutput = world.standardOutput

/-- Whole-executable soundness, finite termination, and successful-input
completeness. Invalid or undersized inputs may return classified failures;
the source-only success domain guarantees a zero return. -/
def ExecutionCorrect (executable : Lanius.Execution.Executable) (world : Lanius.World.State) : Prop :=
  let before : State := { world }
  ∃ code after bound,
    (∀ fuel, bound ≤ fuel → Lanius.Execution.run fuel executable before =
      .returned (.signed .i32 code) after) ∧
    (∀ fuel, Lanius.Execution.run fuel executable before = .outOfFuel ∨
      Lanius.Execution.run fuel executable before = .returned (.signed .i32 code) after) ∧
    (∀ fuel,
      RunSound before (evalExpr fuel executable.program before (.call executable.entrypoint [])) ∧
      RunFailureSafe before (evalExpr fuel executable.program before (.call executable.entrypoint []))) ∧
    (SuccessDomain world → code = 0)

/-- The reusable result of checking the extractor's actual source. The main
execution theorem is retained as proof, not discarded inside an IO test.
Stage evidence remains available for inspection and focused mutation tests;
correctness refers to the accepted executable itself, not to those metadata
fields or to an independently supplied main body. -/
structure CheckedExecution (accepted : CheckedExtractorCoreSourcePack encoded sources) where
  arguments : CheckedArguments accepted.checked.program.core accepted.analysis.body
  allocator : Allocation.CheckedAllocator accepted.checked.program.core
  allocations : Source.CheckedStatement (Allocation.Sequence.statement allocator.function.id)
    arguments.entry.continuation
  file : File.Checked accepted.checked.program
  firstFile : ∀ world, 1 < world.arguments.length → world.arguments.length < 2 ^ 31 →
    ∃ first : Files.First accepted.checked.program.core accepted.analysis.body
      file.argument arguments.entry.count file.body allocations.locals.buffers.length ({ world } : State),
      Nonempty (Path.Buffers file.pipeline.argument file.pipeline.unpack first.state)
  aliases : List Pointers.Alias
  literal : Grammar.LiteralStage
  framing : Framing.Stage
  header : Header.Stage
  text : CompactOutput.Text.Checked accepted.checked.program file.byte
  suffix : Suffix.Stage
  output : Output.Source accepted.checked.program.core suffix
  correct : ∀ world, LoadingDomain world → ExecutionCorrect accepted.entrypoint.executable world
  rejectsLater : ∀ world, LaterFailureDomain world → ExecutionRejects accepted.entrypoint.executable world
  rejectsOversized : ∀ world, OversizedFileDomain world →
    ∃ after, Evaluates accepted.entrypoint.executable.program ({ world } : State)
      (.call accepted.entrypoint.executable.entrypoint []) (.signed .i32 6) after ∧
      Nonempty (Failure ({ world } : State) after 6) ∧ after.world.standardOutput = world.standardOutput

namespace CheckedExecution

def buffers (checked : CheckedExecution accepted) : List Allocation.Buffer := checked.allocations.locals.buffers

theorem run_sound (checked : CheckedExecution accepted) (supported : LoadingDomain world) (fuel : Nat) :
    RunSound ({ world } : State)
      (evalExpr fuel accepted.entrypoint.executable.program ({ world } : State)
        (.call accepted.entrypoint.executable.entrypoint [])) := by
  obtain ⟨_, _, _, _, _, contracts, _⟩ := checked.correct world supported
  exact (contracts fuel).1

theorem run_failureSafe (checked : CheckedExecution accepted) (supported : LoadingDomain world) (fuel : Nat) :
    RunFailureSafe ({ world } : State)
      (evalExpr fuel accepted.entrypoint.executable.program ({ world } : State)
        (.call accepted.entrypoint.executable.entrypoint [])) := by
  obtain ⟨_, _, _, _, _, contracts, _⟩ := checked.correct world supported
  exact (contracts fuel).2

theorem terminates (checked : CheckedExecution accepted) (supported : LoadingDomain world) :
    ∃ code after fuel, Lanius.Execution.run fuel accepted.entrypoint.executable ({ world } : State) =
      .returned (.signed .i32 code) after := by
  obtain ⟨code, after, fuel, stable, _⟩ := checked.correct world supported
  exact ⟨code, after, fuel, stable fuel (Nat.le_refl _)⟩

/-- At a finite fuel bound the actual accepted executable satisfies the
original successful-extraction contract. The domain is source syntax plus
concrete storage/host conditions, not a premise about an extractor run. -/
theorem run_complete (checked : CheckedExecution accepted) (loading : LoadingDomain world) :
    ∃ bound, ∀ fuel, bound ≤ fuel →
      RunComplete (fun state => SuccessDomain state.world) ({world} : State)
        (evalExpr fuel accepted.entrypoint.executable.program ({world} : State)
          (.call accepted.entrypoint.executable.entrypoint [])) := by
  obtain ⟨code, after, bound, stable, _, contracts, complete⟩ := checked.correct world loading
  refine ⟨bound, ?_⟩
  intro fuel enough admitted
  have zero := complete admitted
  subst code
  have finished := stable fuel enough
  have done : evalExpr fuel accepted.entrypoint.executable.program ({world} : State)
      (.call accepted.entrypoint.executable.entrypoint []) = .done (.signed .i32 0) after := by
    cases observed : evalExpr fuel accepted.entrypoint.executable.program ({world} : State)
        (.call accepted.entrypoint.executable.entrypoint []) with
    | done value final =>
      rw [Lanius.Execution.run, observed] at finished
      cases finished
      rfl
    | exited code final =>
      simp only [Lanius.Execution.run, observed] at finished
      cases finished
    | trapped reason final =>
      simp only [Lanius.Execution.run, observed] at finished
      cases finished
    | outOfFuel =>
      simp only [Lanius.Execution.run, observed] at finished
      cases finished
  exact ⟨after, done, (contracts fuel).1 0 after done rfl⟩

/-- A consumer with checked source and loading conditions obtains successful
extraction, rather than merely termination with an unspecified return code. -/
theorem succeeds (checked : CheckedExecution accepted) (loading : LoadingDomain world)
    (supported : SuccessDomain world) :
    ∃ bound, ∀ fuel, bound ≤ fuel →
      ∃ after,
        evalExpr fuel accepted.entrypoint.executable.program ({world} : State)
          (.call accepted.entrypoint.executable.entrypoint []) = .done (.signed .i32 0) after ∧
        Nonempty (Success ({world} : State) after) := by
  obtain ⟨bound, complete⟩ := checked.run_complete loading
  exact ⟨bound, fun fuel enough => complete fuel enough supported⟩

end CheckedExecution
end Lanius.Extraction.Entry
