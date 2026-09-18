import Lanius.Extraction.Entry.Files.Initialize
import Lanius.Extraction.Entry.Files.Output.Resources

namespace Lanius.Extraction.Entry.Files
open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation

variable {program : CoreSynthesis.Program.CheckedProgram artifacts}
variable {pipeline : File.Load.Pipeline program}

/-- Construct the entire first file invocation at the actual checked loop
entry. Startup supplies allocation history, retained views, decoded grammar,
and emitted header; this theorem supplies loading, frontend, collection,
emission, and the empty ordered-certificate history. Main typing and its
execution prefix derive runtime typing, without an independent caller invariant. -/
theorem CheckedSource.resources {countId : VarId} {continuation : Stmt}
    (source : CheckedSource pipeline.path.argument countId
      (pipeline.path.statement pipeline.length.function.id) continuation)
    (loading : LoadingSource pipeline buffers aliases literal framing)
    (frontend : FrontendSource pipeline syntaxStage buffers aliases literal framing)
    (output : OutputSource pipeline syntaxStage collectStage emitStage header buffers aliases literal framing)
    (history : Allocation.HostReady buffers initial allocated)
    (frame : Pointers.AliasFrame aliases allocated original)
    (registry : Allocation.Registry original) (readyRegistry : Allocation.Registry ready)
    (names : (buffers.map Allocation.Buffer.binding).Nodup)
    (retained : Retained literal framing original ready)
    (evidence : Grammar.LiteralEvidence Grammar.indexedLanius literal.text)
    (memory : Grammar.Memory literal.setup.cursor.locals) (selected : memory.values = evidence.values)
    (originalGrammar : original.local? literal.setup.cursor.locals.destination = some
      (.slice (.scalar (.signed .i32)) memory.destinationCell [] 0 memory.untouched.length))
    (initialized : ready.cellEntry? memory.destinationCell = some {
      id := memory.destinationCell, value := some (.array (signedI32Values (memory.buffer memory.values))) })
    (untouched : List Int) (count : Nat)
    (originalOutput : original.local? framing.output = some
      (.slice (.scalar (.signed .i32)) outputCell [] 0 untouched.length))
    (outputStored : ready.cellEntry? outputCell = some {
      id := outputCell, value := some (.array (signedI32Values
        (Header.contents (Input.copiedBuffer [] untouched Framing.bytes) Framing.bytes.length count))) })
    (position : (Assertion.localPointsTo header.position positionCell
      (some (.signed .i32 (Framing.bytes.length + 16 : Nat)))).holds ready)
    (mainTyped : Typing.StmtHasType program.core returnType context inLoop main)
    (beforeTyped : RuntimeStateHasType program.core context before store)
    (startup : Prefix.Reaches program.core before main ready continuation)
    (world : ready.world = { initialWorld with calls := calls })
    (pending : Pending initialWorld 1 (request :: rest))
    (handleFit : initialWorld.nextFileHandle ≤ 2147483647)
    (olderHandles : ∀ handle ∈ initialWorld.fileHandles, handle.id < (initialWorld.nextFileHandle : Int))
    (sizeFit : 65536 < unsignedModulus program.core.target .usize) :
    ∃ loopContext loopStore,
      ∃ resources : File.Resources pipeline syntaxStage collectStage emitStage pipeline.path.argument
          (ready.bindLocal pipeline.path.argument (.signed .i32 1)),
        Prefix.Reaches program.core before main (ready.bindLocal pipeline.path.argument (.signed .i32 1))
          (.whileLoop (condition pipeline.path.argument countId) (pipeline.path.statement pipeline.length.function.id)) ∧
        RuntimeStateHasType program.core loopContext
          (ready.bindLocal pipeline.path.argument (.signed .i32 1)) loopStore ∧
        Typing.StmtHasType program.core returnType loopContext true
          (pipeline.path.statement pipeline.length.function.id) ∧
        resources.input.index = 1 ∧ resources.input.path = request.path ∧ resources.input.file = request.file ∧
        resources.input.packedPath.length = 256 ∧ resources.input.pathOutput.length = 1024 ∧
        resources.input.source.length = 65536 ∧ resources.input.scratch.length = 16384 ∧
        resources.output.view.root = outputCell ∧
        History count [] [] resources.position resources.output.contents := by
  obtain ⟨loopContext, loopStore, input, reached, typed, bodyTyped, index, path, file,
      packedPath, pathLength, sourceLength, scratch, ⟨inputStorage⟩⟩ :=
    source.loading loading history frame registry readyRegistry names retained mainTyped beforeTyped startup
      world pending handleFit olderHandles sizeFit
  obtain ⟨data, valid, capacities, ⟨frontBuffers⟩, reads, grammar⟩ :=
    frontend.prepare loading input inputStorage history frame registry readyRegistry names retained
      evidence memory selected originalGrammar initialized
  obtain ⟨resources, inputEqual, _dataEqual, outputRoot, certificateHistory⟩ :=
    output.resources frontend loading input inputStorage data valid capacities frontBuffers reads grammar
      history frame registry readyRegistry names retained untouched count originalOutput outputStored position
      index (by simpa only [world] using olderHandles)
  refine ⟨loopContext, loopStore, resources, reached, typed, bodyTyped, ?_, ?_, ?_, ?_, ?_, ?_, ?_, outputRoot, certificateHistory⟩
  all_goals simpa only [inputEqual] using (by assumption)

end Lanius.Extraction.Entry.Files
