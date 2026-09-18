import Lanius.Extraction.Entry.Output.Run

namespace Lanius.Extraction.Entry.Startup
open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation

variable {program : CoreSynthesis.Program.CheckedProgram artifacts}
variable {main : Stmt} {entry : CheckedArguments program.core main}
variable {checked : File.Checked program}

/-- Finish main after the actual ordered file phase. Workspace contents,
pointer provenance, buffer separation, certificate bytes, and final execution
are all derived; callers supply only the preceding execution result and its
reached continuation, plus checked source and ordinary input bounds. -/
theorem Ready.completeOutput (started : Ready entry sequence pointers literal data framing header before)
    (source : Output.Source program.core stage)
    (supported : Suffix.Supported stage framing) (framingSupport : Framing.Supported framing)
    (text : CompactOutput.Text.Checked program byte)
    (headerRelation : Framing.HeaderRelation framing header)
    (output : Files.OutputSource checked.pipeline checked.syntaxStage checked.collectStage checked.emitStage header
      sequence.buffers pointers.aliases literal framing)
    (workspace : Files.BufferSource sequence.buffers pointers.aliases literal framing checked.pipeline.path.argument
      source.preparation.packing.workspace 4194304)
    (pointer : Files.PointerSource pointers.aliases literal framing checked.pipeline.path.argument
      source.stdout.pointer source.preparation.packing.workspace)
    (names : (sequence.buffers.map Allocation.Buffer.binding).Nodup)
    (workspaceOutput : source.preparation.packing.workspace ≠ checked.emitStage.output)
    (argumentClosing : checked.pipeline.path.argument ≠ framing.closing)
    (carriedClosing : File.Carried checked.pipeline checked.syntaxStage checked.resultsStage framing.closing)
    (carriedWorkspace : File.Carried checked.pipeline checked.syntaxStage checked.resultsStage source.preparation.packing.workspace)
    (carriedPointer : File.Carried checked.pipeline checked.syntaxStage checked.resultsStage source.stdout.pointer)
    (result : Files.Result checked context countId count sources started.outputCell
      (started.state.bindLocal checked.pipeline.path.argument (.signed .i32 1)) completion after)
    (finished : completion = .next)
    (reached : Prefix.Reaches program.core before main after (stage.statement text.source.function.id))
    (positive : 0 < count) (countFit : count < 4294967296)
    (usizeFit : 16777216 < unsignedModulus program.core.target .usize) :
    ∃ units : List CompactDecode.UnitData, units.length = count ∧
      Nonempty (CheckedCompactSyntaxSourcePack (CompactDecode.renderedPack count units) sources) ∧
      ∃ exit final, Executes program.core before main (.returned exit) final ∧
        Output.Result (Lanius.World.utf8Bytes (ExtractorContract.renderedModule (CompactDecode.renderedPack count units)))
          after.world (.returned exit) final.world ∧
        (∀ cursor : Nat, after.local? checked.emitStage.position = some (.signed .i32 cursor) →
          cursor + Suffix.bytes.length ≤ 16777216 → exit = some (.signed .i32 0)) := by
  obtain ⟨resources, units, countUnits, history⟩ :=
    started.suffixResources stage supported headerRelation output names argumentClosing carriedClosing result finished
  obtain ⟨working, pointers⟩ := started.bufferAfterFiles output workspace names carriedWorkspace result finished
  obtain ⟨outputBuffer, _outputPointers⟩ := started.bufferAfterFiles output output.output names
    (checked.emitRelation.carried _ (by simp [File.Emit.Stage.carriedLocals])) result finished
  have sameRead : started.original.local? checked.emitStage.output = some
      (.slice (.scalar (.signed .i32)) started.outputCell [] 0 started.untouched.length) := by
    simpa only [output.outputBinding] using started.originalOutput
  have outputRoot : outputBuffer.view.root = started.outputCell := by
    have same := outputBuffer.originalRead.symm.trans sameRead
    injection same with same
    injection same
  have separate := working.apart outputBuffer workspace output.output started.history started.frame names workspaceOutput
  rw [outputRoot] at separate
  have pointerRead := pointers source.stdout.pointer pointer carriedPointer
  obtain ⟨certificate, finalCompletion, completed, run, outcome, success⟩ := source.executes supported framingSupport text resources
    history countUnits positive countFit working.view working.values working.member working.capacity
    (by simpa only [working.capacity] using working.read) working.stored pointerRead separate usizeFit
  have returned : ∃ exit, finalCompletion = .returned exit := by
    rcases outcome with failed | success
    · exact ⟨_, failed.1⟩
    · exact ⟨_, success.1⟩
  obtain ⟨exit, equal⟩ := returned
  subst finalCompletion
  obtain ⟨final, completedMain, scopes⟩ := reached.completeReturn run
  have world : final.world = completed.world := by
    simpa only [restoreLocals] using congrArg State.world (scopes before)
  refine ⟨units, countUnits, certificate, exit, final, completedMain, world.symm ▸ outcome, ?_⟩
  intro cursor read room
  have sameRead : after.local? checked.emitStage.position = some (.signed .i32 resources.earlier.length) := by
    simpa only [supported.position, output.positionBinding, headerRelation.position] using resources.positionRead
  have same : resources.earlier.length = cursor := by
    have value := sameRead.symm.trans read
    simpa only [Option.some.injEq, Value.signed.injEq, true_and, Int.natCast_inj] using value
  exact Completion.returned.inj (success (by simpa only [same] using room))

end Lanius.Extraction.Entry.Startup
