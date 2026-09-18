import Lanius.Extraction.Entry.Startup.State
import Lanius.Extraction.Entry.Files.First
import Lanius.Extraction.Entry.Files.Initialize
import Lanius.Extraction.Entry.File.Oversize

namespace Lanius.Extraction.Entry.Startup
open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Extraction.ExtractorContract

variable {program : CoreSynthesis.Program.CheckedProgram artifacts}
variable {main : Stmt} {entry : CheckedArguments program.core main}

/-- Derive the complete first-file rejection from actual startup, source
typing, and external file conditions. All allocation and reader invariants
are constructed; the file is closed before the main returns 6. -/
theorem rejectsOversized (startup : Nonempty (Ready entry sequence pointers literal data framing header before))
    (checked : File.Checked program) {countId : VarId}
    (source : Files.CheckedSource checked.argument countId checked.body header.continuation)
    (countIdentity : header.count = countId)
    (loading : Files.LoadingSource checked.pipeline sequence.buffers pointers.aliases literal framing)
    (names : (sequence.buffers.map Allocation.Buffer.binding).Nodup)
    (mainTyped : Typing.StmtHasType program.core returnType context inLoop main)
    (beforeTyped : RuntimeStateHasType program.core context before store)
    (request : Files.Request)
    (selected : before.world.arguments[1]? = some request.path)
    (fileFound : before.world.file? (Lanius.World.utf8Bytes request.path) = some request.file)
    (nonempty : 0 < request.path.toUTF8.size) (pathFits : request.path.toUTF8.size ≤ 1024)
    (oversize : 65536 < request.file.bytes.length)
    (handleFit : before.world.nextFileHandle ≤ 2147483647)
    (olderHandles : ∀ handle ∈ before.world.fileHandles, handle.id < (before.world.nextFileHandle : Int))
    (diagnostics : Diagnostics.Read.Checked program checked.pipeline.path.argument checked.pipeline.read.count checked.pipeline.read.failure)
    (sizeFit : 65536 < unsignedModulus program.core.target .usize) :
    ∃ after, Executes program.core before main (.returned (some (.signed .i32 6))) after ∧
      Nonempty (Failure before after 6) ∧ after.world.standardOutput = before.world.standardOutput := by
  obtain ⟨started⟩ := startup
  let pipelineSource : Files.CheckedSource checked.pipeline.path.argument countId checked.body header.continuation := by
    simpa only [checked.advanceRelation.selected] using source
  obtain ⟨loopContext, loopStore, _reached, typed, _bodyTyped, _registered, _representable, _index⟩ :=
    pipelineSource.enter program mainTyped beforeTyped started.reached started.registry
  obtain ⟨available, index, _path, file, _packedLength, _pathLength, _sourceLength, _scratchLength, _storage⟩ :=
    loading.available started.history started.frame started.originalRegistry started.registry names started.retained
      typed started.world request selected fileFound nonempty pathFits handleFit olderHandles sizeFit
  have unshadowed : checked.pipeline.path.argument ∉ [checked.pipeline.path.length, checked.pipeline.unpack.locals.cursor,
      checked.pipeline.opened.handle, checked.pipeline.read.count, checked.pipeline.read.closed] := by
    simpa only [File.Load.Pipeline.boundLocals, checked.advanceRelation.selected] using checked.advanceRelation.loaded
  obtain ⟨after, run, safe, reads, _positive, stderrBytes, afterWorld⟩ := checked.pipeline.rejectsOversized available diagnostics
    unshadowed (by rw [index]; decide) (by rw [file]; exact oversize)
  let first := pipelineSource.first started countIdentity
  obtain ⟨final, mainRun, same⟩ := first.completeReturn run
  have world : final.world = after.world := by
    simpa only [restoreLocals] using congrArg State.world (same before)
  have finalSafe : MemorySafe final := by
    change MemorySafe (restoreLocals before final)
    rw [same before]
    exact safe
  refine ⟨final, mainRun, ⟨⟨by decide, ?_, ?_, ?_, ?_, finalSafe⟩⟩, ?_⟩
  · exact .readOrClose
  all_goals simp only [world, afterWorld, File.Load.Available.loadedWorld, State.bindLocal, State.bindCell, started.world]

end Lanius.Extraction.Entry.Startup
