import Lanius.Extraction.Entry.Startup.Complete

namespace Lanius.Extraction.Entry.Startup
open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Extraction.ExtractorContract

variable {program : CoreSynthesis.Program.CheckedProgram artifacts}
variable {main : Stmt} {entry : CheckedArguments program.core main}

/-- Finite execution of the complete source-linked main on the ordinary
loading/resource domain. A zero return establishes the public `Success`
contract; every nonzero return establishes `Failure`, including memory safety.
Syntax acceptance, successful extraction, intermediate resources, and later
phase executions are conclusions, not assumptions. The source-only success
domain additionally rules out every remaining error return. -/
theorem executes
    (startup : Nonempty (Ready entry sequence pointers literal data framing header before))
    (checked : File.Checked program) {countId : VarId}
    (fileSource : Files.CheckedSource checked.argument countId checked.body header.continuation)
    (countIdentity : header.count = countId)
    (loading : Files.LoadingSource checked.pipeline sequence.buffers pointers.aliases literal framing)
    (frontend : Files.FrontendSource checked.pipeline checked.syntaxStage sequence.buffers pointers.aliases literal framing)
    (output : Files.OutputSource checked.pipeline checked.syntaxStage checked.collectStage checked.emitStage header
      sequence.buffers pointers.aliases literal framing)
    (carried : File.Carried checked.pipeline checked.syntaxStage checked.resultsStage countId)
    (names : (sequence.buffers.map Allocation.Buffer.binding).Nodup)
    (finalSource : Output.Source program.core stage)
    (supported : Suffix.Supported stage framing) (framingSupport : Framing.Supported framing)
    (text : CompactOutput.Text.Checked program byte)
    (suffixSource : fileSource.continuation = stage.statement text.source.function.id)
    (headerRelation : Framing.HeaderRelation framing header)
    (workspace : Files.BufferSource sequence.buffers pointers.aliases literal framing checked.pipeline.path.argument
      finalSource.preparation.packing.workspace 4194304)
    (pointer : Files.PointerSource pointers.aliases literal framing checked.pipeline.path.argument
      finalSource.stdout.pointer finalSource.preparation.packing.workspace)
    (workspaceOutput : finalSource.preparation.packing.workspace ≠ checked.emitStage.output)
    (argumentClosing : checked.pipeline.path.argument ≠ framing.closing)
    (carriedClosing : File.Carried checked.pipeline checked.syntaxStage checked.resultsStage framing.closing)
    (carriedWorkspace : File.Carried checked.pipeline checked.syntaxStage checked.resultsStage finalSource.preparation.packing.workspace)
    (carriedPointer : File.Carried checked.pipeline checked.syntaxStage checked.resultsStage finalSource.stdout.pointer)
    (mainTyped : Typing.StmtHasType program.core returnType context inLoop main)
    (beforeTyped : RuntimeStateHasType program.core context before store)
    (pending : Files.Pending before.world 1 (request :: rest))
    (endpoint : 1 + (request :: rest).length = before.world.arguments.length)
    (handles : before.world.nextFileHandle + rest.length ≤ 2147483647)
    (olderHandles : ∀ handle ∈ before.world.fileHandles, handle.id < (before.world.nextFileHandle : Int))
    (usizeFit : 16777216 < unsignedModulus program.core.target .usize) :
    ∃ code after, Executes program.core before main (.returned (some (.signed .i32 code))) after ∧
      (code = 0 → Nonempty (Success before after)) ∧
      (code ≠ 0 → Nonempty (Failure before after code)) ∧
      (SuccessDomain before.world → code = 0) := by
  obtain ⟨started, loopContext, completion, after, _reached, _loop, result, progress, reachedSuffix, completeError⟩ :=
    runFiles startup checked fileSource countIdentity loading frontend output carried names mainTyped beforeTyped
      pending endpoint handles olderHandles (by omega)
  have loopSuccess (admitted : SuccessDomain before.world) : completion = .next ∧
      ∃ cursor : Nat, after.local? checked.emitStage.position = some (.signed .i32 cursor) ∧
        cursor + Suffix.bytes.length ≤ 16777216 := by
    obtain ⟨sources, bounds, sourcesFound, supportedSources, room⟩ := admitted
    have same := Option.some.inj (sourcesFound.symm.trans (pending.sources endpoint))
    subst sources
    have framingBytes : moduleFramingBytes = Framing.bytes.length + 16 + Suffix.bytes.length := by
      simp only [moduleFramingBytes, Framing.bytes, Suffix.bytes, Lanius.World.utf8Bytes,
        Array.length_toList, ByteArray.size_data]
    rw [framingBytes] at room
    obtain ⟨finished, cursor, read, bound⟩ := progress bounds supportedSources (by omega)
      (by simp only [Int.toNat_natCast]; omega)
    simp only [Int.toNat_natCast] at bound
    exact ⟨finished, cursor, read, by omega⟩
  have external : File.Result before completion after := by
    refine ⟨result.external.completion, ?_, ?_, ?_, ?_, ?_⟩
    · simpa only [State.bindLocal, State.bindCell, started.world] using result.external.arguments
    · simpa only [State.bindLocal, State.bindCell, started.world] using result.external.files
    · simpa only [State.bindLocal, State.bindCell, started.world] using result.external.handles
    · simpa only [State.bindLocal, State.bindCell, started.world] using result.external.stdout
    · intro completed
      simpa only [State.bindLocal, State.bindCell, started.world] using result.external.stderr completed
  have safe {exit : Option Value} {final : State}
      (run : Executes program.core before main (.returned exit) final) : MemorySafe final := by
    obtain ⟨_, typed⟩ := Host.checked_statement_type program mainTyped beforeTyped run
    exact memorySafe_of_runtimeStateHasType typed
  have failed {code : Int} (completed : completion = .returned (some (.signed .i32 code)))
      (nonzero : code ≠ 0) (classified : FailureCode code) :
      ∃ final, Executes program.core before main (.returned (some (.signed .i32 code))) final ∧
        Nonempty (Failure before final code) := by
    obtain ⟨final, run, scopes⟩ := completeError _ completed
    have world : final.world = after.world := by
      simpa only [restoreLocals] using congrArg State.world (scopes before)
    exact ⟨final, run, ⟨⟨nonzero, classified,
      (congrArg (fun world : Lanius.World.State => world.arguments) world).trans external.arguments,
      (congrArg (fun world : Lanius.World.State => world.files) world).trans external.files,
      (congrArg (fun world : Lanius.World.State => world.fileHandles) world).trans external.handles, safe run⟩⟩⟩
  rcases result.external.completion with completed | encoded | extracted
  · have positive : 0 < before.world.arguments.length - 1 := by have := started.enough; omega
    have countFit : before.world.arguments.length - 1 < 4294967296 := by have := started.bounded; omega
    obtain ⟨units, _count, certificate, exit, final, run, outcome, outputSuccess⟩ :=
      started.completeOutput finalSource supported framingSupport text headerRelation output workspace pointer names
        workspaceOutput argumentClosing carriedClosing carriedWorkspace carriedPointer result completed
        (by simpa only [suffixSource] using reachedSuffix completed) positive countFit usizeFit
    rcases outcome with ⟨returned, world⟩ | ⟨returned, world⟩
    · have identity := Completion.returned.inj returned
      subst exit
      refine ⟨25, final, run, (by intro impossible; contradiction), fun _ => ?_, ?_⟩
      · exact ⟨⟨by decide, .writeSuffix,
          (congrArg (fun world : Lanius.World.State => world.arguments) world).trans external.arguments,
          (congrArg (fun world : Lanius.World.State => world.files) world).trans external.files,
          (congrArg (fun world : Lanius.World.State => world.fileHandles) world).trans external.handles, safe run⟩⟩
      · intro admitted
        obtain ⟨_, cursor, read, room⟩ := loopSuccess admitted
        have impossible := outputSuccess cursor read room
        cases impossible
    · have identity := Completion.returned.inj returned
      subst exit
      refine ⟨0, final, run, fun _ => ?_, (by intro impossible; exact False.elim (impossible rfl)), fun _ => rfl⟩
      refine ⟨{
        encoded := CompactDecode.renderedPack (before.world.arguments.length - 1) units
        sources := (request :: rest).map Files.Request.source
        sourcesFound := pending.sources endpoint
        certificate
        stdout := ?_
        stderr := ?_
        arguments := ?_
        files := ?_
        handles := ?_
        memorySafe := safe run }⟩
      · simpa only [world, external.stdout]
      · simpa only [world] using external.stderr completed
      · simpa only [world] using external.arguments
      · simpa only [world] using external.files
      · simpa only [world] using external.handles
  · obtain ⟨final, run, failure⟩ := failed encoded (by decide) .encodeUnit
    refine ⟨21, final, run, (by intro impossible; contradiction), fun _ => failure, ?_⟩
    intro admitted
    have impossible := encoded.symm.trans (loopSuccess admitted).1
    cases impossible
  · obtain ⟨final, run, failure⟩ := failed extracted (by decide) .extraction
    refine ⟨28, final, run, (by intro impossible; contradiction), fun _ => failure, ?_⟩
    intro admitted
    have impossible := extracted.symm.trans (loopSuccess admitted).1
    cases impossible

end Lanius.Extraction.Entry.Startup
