import Lanius.Extraction.Entry.Files.Entry
import Lanius.Extraction.Entry.Files.Input

namespace Lanius.Extraction.Entry.Files
open Lanius.Core Lanius.Semantics Lanius.Properties

variable {program : CoreSynthesis.Program.CheckedProgram artifacts}
variable {pipeline : File.Load.Pipeline program}

/-- Enter the actual checked file loop and construct its first loader input.
Runtime typing at the file entry follows from the main program and retained
startup execution, rather than being supplied as an independent invariant. -/
theorem CheckedSource.loading {countId : VarId} {continuation : Stmt}
    (source : CheckedSource pipeline.path.argument countId
      (pipeline.path.statement pipeline.length.function.id) continuation)
    (loading : LoadingSource pipeline buffers aliases literal framing)
    (history : Allocation.HostReady buffers initial allocated)
    (frame : Pointers.AliasFrame aliases allocated original)
    (registry : Allocation.Registry original) (readyRegistry : Allocation.Registry ready)
    (names : (buffers.map Allocation.Buffer.binding).Nodup)
    (retained : Retained literal framing original ready)
    (mainTyped : Typing.StmtHasType program.core returnType context inLoop main)
    (beforeTyped : RuntimeStateHasType program.core context before store)
    (startup : Prefix.Reaches program.core before main ready continuation)
    (world : ready.world = { initialWorld with calls := calls })
    (pending : Pending initialWorld 1 (request :: rest))
    (handleFit : initialWorld.nextFileHandle ≤ 2147483647)
    (olderHandles : ∀ handle ∈ initialWorld.fileHandles, handle.id < (initialWorld.nextFileHandle : Int))
    (sizeFit : 65536 < unsignedModulus program.core.target .usize) :
    ∃ loopContext loopStore,
      ∃ input : File.Load.Input pipeline (ready.bindLocal pipeline.path.argument (.signed .i32 1)),
        Prefix.Reaches program.core before main (ready.bindLocal pipeline.path.argument (.signed .i32 1))
          (.whileLoop (condition pipeline.path.argument countId) (pipeline.path.statement pipeline.length.function.id)) ∧
        RuntimeStateHasType program.core loopContext
          (ready.bindLocal pipeline.path.argument (.signed .i32 1)) loopStore ∧
        Typing.StmtHasType program.core returnType loopContext true
          (pipeline.path.statement pipeline.length.function.id) ∧
        input.index = 1 ∧ input.path = request.path ∧ input.file = request.file ∧
        input.packedPath.length = 256 ∧ input.pathOutput.length = 1024 ∧
        input.source.length = 65536 ∧ input.scratch.length = 16384 ∧ Nonempty (InputStorage original input.toAvailable) := by
  obtain ⟨loopContext, loopStore, reached, typed, bodyTyped, _registered, _representable, _index⟩ :=
    source.enter program mainTyped beforeTyped startup readyRegistry
  obtain ⟨input, index, path, file, packedPath, pathLength, sourceLength, scratch, inputStorage⟩ :=
    loading.input history frame registry readyRegistry names retained typed world pending handleFit olderHandles sizeFit
  exact ⟨loopContext, loopStore, input, reached, typed, bodyTyped, index, path, file,
    packedPath, pathLength, sourceLength, scratch, inputStorage⟩

end Lanius.Extraction.Entry.Files
