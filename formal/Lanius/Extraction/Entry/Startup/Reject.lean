import Lanius.Extraction.Entry.Startup.State
import Lanius.Extraction.Entry.Files.Resources
import Lanius.Extraction.Entry.Files.Reject
import Lanius.Semantics.Prefix.Return

namespace Lanius.Extraction.Entry.Startup
open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Extraction.ExtractorContract

variable {program : CoreSynthesis.Program.CheckedProgram artifacts}
variable {main : Stmt} {entry : CheckedArguments program.core main}

/-- Connect a loadable prefix followed by a rejected file to the actual main.
Startup constructs every resource; the file loop either rejects earlier or
reaches the rejected file. The suffix and stdout phases are never executed. -/
theorem rejectsAfter (startup : Nonempty (Ready entry sequence pointers literal data framing header before))
    (checked : File.Checked program) {countId : VarId}
    (diagnostics : Diagnostics.Read.Checked program checked.pipeline.path.argument checked.pipeline.read.count checked.pipeline.read.failure)
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
    (issue : File.Rejection before.world (1 + (request :: rest).length) rejectedCode)
    (handles : before.world.nextFileHandle + rest.length + File.Rejection.additionalHandles rejectedCode ≤ 2147483647)
    (olderHandles : ∀ handle ∈ before.world.fileHandles, handle.id < (before.world.nextFileHandle : Int))
    (sizeFit : 65536 < unsignedModulus program.core.target .usize) :
    ∃ code after, Executes program.core before main (.returned (some (.signed .i32 code))) after ∧
      Nonempty (Failure before after code) ∧ after.world.standardOutput = before.world.standardOutput := by
  obtain ⟨started⟩ := startup
  let pipelineSource : Files.CheckedSource checked.pipeline.path.argument countId checked.body header.continuation := by
    simpa only [checked.advanceRelation.selected] using source
  obtain ⟨loopContext, loopStore, resources, reached, typed, bodyTyped, index, _path, _file,
      packedPath, pathLength, _sourceLength, _scratch, _outputRoot, _history⟩ :=
    pipelineSource.resources loading frontend output started.history started.frame started.originalRegistry started.registry
      names started.retained data started.memory started.selected started.originalGrammar started.grammarStored
      started.untouched (before.world.arguments.length - 1) started.originalOutput started.outputStored started.position
      mainTyped beforeTyped started.reached started.world pending (by omega) olderHandles sizeFit
  let first : File.Resources checked.pipeline checked.syntaxStage checked.collectStage checked.emitStage checked.argument
      (started.state.bindLocal checked.pipeline.path.argument (.signed .i32 1)) := {
    resources with differentCursors := by simpa only [checked.advanceRelation.selected] using resources.differentCursors }
  have currentCount := (Lanius.Separation.bindLocal_preserves_other_local
    (value := Value.signed .i32 1) started.registry.wellFormed pipelineSource.distinct).trans
      (countIdentity ▸ started.countRead)
  have currentApart : (started.state.bindLocal checked.pipeline.path.argument (.signed .i32 1)).cellId? countId ≠
      (started.state.bindLocal checked.pipeline.path.argument (.signed .i32 1)).cellId? checked.emitStage.position := by
    rw [Lanius.Separation.bindLocal_preserves_other_cellId started.state checked.pipeline.path.argument countId
        (.signed .i32 1) pipelineSource.distinct,
      Lanius.Separation.bindLocal_preserves_other_cellId started.state checked.pipeline.path.argument checked.emitStage.position
        (.signed .i32 1) output.argumentPosition, output.positionBinding]
    exact countIdentity ▸ started.countApart
  have currentPending : Files.Pending (started.state.bindLocal checked.pipeline.path.argument (.signed .i32 1)).world
      first.input.index (request :: rest) := by
    change Files.Pending started.state.world resources.input.index (request :: rest)
    rw [index, started.world]
    exact ⟨pending.selected, pending.files, pending.nonempty, pending.pathFits, pending.fileFits⟩
  have currentIssue : File.Rejection (started.state.bindLocal checked.pipeline.path.argument (.signed .i32 1)).world
      (first.input.index + (request :: rest).length) rejectedCode := by
    change File.Rejection started.state.world (resources.input.index + (request :: rest).length) rejectedCode
    rw [index]
    exact issue.transport (by rw [started.world]) (by rw [started.world])
  obtain ⟨code, after, run, ⟨failure⟩, stdout⟩ := Files.rejectsAfter checked countId diagnostics carried bodyTyped
    before.world.arguments.length (by have bound := started.bounded; omega) first typed request rest currentPending currentIssue
    (by change resources.input.index + (request :: rest).length < _; rw [index]; exact issue.index_lt)
    (by simpa only [State.bindLocal, State.bindCell, started.world] using handles)
    packedPath pathLength currentCount currentApart
  have loopRun : Executes program.core (started.state.bindLocal checked.pipeline.path.argument (.signed .i32 1))
      (.whileLoop (Files.condition checked.pipeline.path.argument countId) checked.body)
      (.returned (some (.signed .i32 code))) after := by
    simpa only [Files.statement, checked.advanceRelation.selected] using run
  obtain ⟨final, mainRun, same⟩ := reached.completeReturn loopRun
  have world : final.world = after.world := by
    simpa only [restoreLocals] using congrArg State.world (same before)
  have safe : MemorySafe final := by
    change MemorySafe (restoreLocals before final)
    rw [same before]
    exact failure.memorySafe
  refine ⟨code, final, mainRun, ⟨⟨failure.nonzero, failure.classified, ?_, ?_, ?_, safe⟩⟩, ?_⟩
  · simpa only [world, State.bindLocal, State.bindCell, started.world] using failure.arguments
  · simpa only [world, State.bindLocal, State.bindCell, started.world] using failure.files
  · simpa only [world, State.bindLocal, State.bindCell, started.world] using failure.handles
  · simpa only [world, State.bindLocal, State.bindCell, started.world] using stdout

end Lanius.Extraction.Entry.Startup
