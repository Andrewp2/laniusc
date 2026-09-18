import Lanius.Extraction.Entry.Startup.State
import Lanius.Extraction.Entry.Files.Run
import Lanius.Semantics.Prefix.Return

namespace Lanius.Extraction.Entry.Startup
open Lanius.Core Lanius.Semantics Lanius.Properties

variable {program : CoreSynthesis.Program.CheckedProgram artifacts}
variable {main : Stmt} {entry : CheckedArguments program.core main}

/-- Connect the state produced by `Startup.reaches` to the complete file
phase. There is no independently supplied startup execution, file resource,
parser invariant, successful parse, or accepted output. External assumptions
describe requested files, handle availability, target width, and main typing. -/
theorem runFiles (startup : Nonempty (Ready entry sequence pointers literal data framing header before))
    (checked : File.Checked program) {countId : VarId}
    (source : Files.CheckedSource checked.argument countId checked.body header.continuation)
    (countIdentity : header.count = countId)
    (loading : Files.LoadingSource checked.pipeline sequence.buffers pointers.aliases literal framing)
    (frontend : Files.FrontendSource checked.pipeline checked.syntaxStage sequence.buffers pointers.aliases literal framing)
    (output : Files.OutputSource checked.pipeline checked.syntaxStage checked.collectStage checked.emitStage header
      sequence.buffers pointers.aliases literal framing)
    (carried : File.Carried checked.pipeline checked.syntaxStage checked.resultsStage countId)
    (names : (sequence.buffers.map Allocation.Buffer.binding).Nodup)
    (mainTyped : Typing.StmtHasType program.core returnType context inLoop main)
    (beforeTyped : RuntimeStateHasType program.core context before store)
    (pending : Files.Pending before.world 1 (request :: rest))
    (endpoint : 1 + (request :: rest).length = before.world.arguments.length)
    (handles : before.world.nextFileHandle + rest.length ≤ 2147483647)
    (olderHandles : ∀ handle ∈ before.world.fileHandles, handle.id < (before.world.nextFileHandle : Int))
    (sizeFit : 65536 < unsignedModulus program.core.target .usize) :
    ∃ started : Ready entry sequence pointers literal data framing header before,
    ∃ loopContext completion after,
      Prefix.Reaches program.core before main (started.state.bindLocal checked.pipeline.path.argument (.signed .i32 1))
        (Files.statement checked countId) ∧
      Executes program.core (started.state.bindLocal checked.pipeline.path.argument (.signed .i32 1))
        (Files.statement checked countId) completion after ∧
      Files.Result checked loopContext countId (before.world.arguments.length - 1)
        ((request :: rest).map Files.Request.source) started.outputCell
        (started.state.bindLocal checked.pipeline.path.argument (.signed .i32 1)) completion after ∧
      Files.Progress ((request :: rest).map Files.Request.source) checked.emitStage.position
        (Framing.bytes.length + 16 : Nat) completion after ∧
      (completion = .next → Prefix.Reaches program.core before main after source.continuation) ∧
      (∀ value, completion = .returned value →
        ∃ final, Executes program.core before main (.returned value) final ∧
          ∀ caller, restoreLocals caller final = restoreLocals caller after) := by
  obtain ⟨started⟩ := startup
  refine ⟨started, ?_⟩
  have count : before.world.arguments.length - 1 + 1 = before.world.arguments.length := by
    have enough := started.enough
    omega
  obtain ⟨loopContext, completion, after, reached, run, result, progress⟩ :=
    Files.CheckedSource.runFromStartup checked source loading frontend output carried
    started.history started.frame started.originalRegistry started.registry names started.retained
    data started.memory started.selected started.originalGrammar started.grammarStored
    started.untouched (before.world.arguments.length - 1) (by have bound := started.bounded; rw [count]; omega)
    started.originalOutput started.outputStored started.position
    (by simpa only [countIdentity, count] using started.countRead)
    (by simpa only [countIdentity] using started.countApart)
    mainTyped beforeTyped started.reached started.world pending (by simpa only [count] using endpoint)
    handles olderHandles sizeFit
  refine ⟨loopContext, completion, after, reached, run, result, progress, ?_, ?_⟩
  · intro completed
    apply source.afterLoop started.reached
    simpa only [Files.statement, checked.advanceRelation.selected, completed] using run
  · intro value completed
    exact reached.completeReturn (completed ▸ run)

end Lanius.Extraction.Entry.Startup
