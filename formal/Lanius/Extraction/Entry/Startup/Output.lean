import Lanius.Extraction.Entry.Startup.Files
import Lanius.Extraction.Entry.Files.Locals

namespace Lanius.Extraction.Entry.Startup
open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation

variable {program : CoreSynthesis.Program.CheckedProgram artifacts}
variable {main : Stmt} {entry : CheckedArguments program.core main}
variable {checked : File.Checked program}

theorem Ready.loopCursors (started : Ready entry sequence pointers literal data framing header before)
    (output : Files.OutputSource checked.pipeline checked.syntaxStage checked.collectStage checked.emitStage header
      sequence.buffers pointers.aliases literal framing) :
    (started.state.bindLocal checked.pipeline.path.argument (.signed .i32 1)).local? checked.argument = some (.signed .i32 1) ∧
    (started.state.bindLocal checked.pipeline.path.argument (.signed .i32 1)).local? checked.emitStage.position =
      some (.signed .i32 (Framing.bytes.length + 16 : Nat)) := by
  refine ⟨?_, ?_⟩
  · rw [checked.advanceRelation.selected]
    exact bindLocal_finds_local _ _ _ started.registry.wellFormed
  · apply (bindLocal_preserves_other_local (value := Value.signed .i32 1)
      started.registry.wellFormed output.argumentPosition).trans
    simpa only [output.positionBinding] using Assertion.localPointsTo_local _ _ _ _ started.position

/-- Recover an actual allocation after all files have run. Its view and
slice remain live; its contents are whatever the completed loop stored, not
the zero-filled allocation or the first iteration's values. -/
theorem Ready.bufferAfterFiles {id : VarId} {capacity : Nat}
    (started : Ready entry sequence pointers literal data framing header before)
    (output : Files.OutputSource checked.pipeline checked.syntaxStage checked.collectStage checked.emitStage header
      sequence.buffers pointers.aliases literal framing)
    (source : Files.BufferSource sequence.buffers pointers.aliases literal framing checked.pipeline.path.argument id capacity)
    (names : (sequence.buffers.map Allocation.Buffer.binding).Nodup)
    (carried : File.Carried checked.pipeline checked.syntaxStage checked.resultsStage id)
    (result : Files.Result checked context countId count sources outputRoot
      (started.state.bindLocal checked.pipeline.path.argument (.signed .i32 1)) completion after)
    (finished : completion = .next) :
    ∃ storage : Files.BufferStorage id capacity started.original after,
      ∀ pointer : VarId,
        Files.PointerSource pointers.aliases literal framing checked.pipeline.path.argument pointer id →
        File.Carried checked.pipeline checked.syntaxStage checked.resultsStage pointer →
        after.local? pointer = some (.pointer storage.view.address) := by
  obtain ⟨storage⟩ := source.storage started.history started.frame started.originalRegistry started.registry names started.retained
  obtain ⟨index, position⟩ := started.loopCursors output
  have read := result.carriedNonScalar finished index position carried storage.read
    (by intro elements same; cases same) (by intro scalar same; cases same)
  obtain ⟨registry, _words, ⟨fresh, views⟩, _output, _index, _argc⟩ := result.completed finished
  have member : storage.view ∈ after.i32ArrayViews := by
    rw [views]
    exact List.mem_append_left _ storage.member
  obtain ⟨values, length, stored⟩ := registry.storage member
  let final : Files.BufferStorage id capacity started.original after := {
    view := storage.view, values, originalMember := storage.originalMember, member,
    length := storage.length, capacity := length.trans storage.length,
    originalRead := storage.originalRead, read, stored }
  refine ⟨final, ?_⟩
  intro pointer source preserved
  have pointerRead := source.read final started.frame started.originalRegistry started.registry started.retained
  exact result.carriedNonScalar finished index position preserved pointerRead
    (by intro elements same; cases same) (by intro scalar same; cases same)

/-- The exact startup suffix literal survives every successful file body;
it is neither reloaded from an assumed buffer nor replaced with another text. -/
theorem Ready.suffixAfterFiles (started : Ready entry sequence pointers literal data framing header before)
    (output : Files.OutputSource checked.pipeline checked.syntaxStage checked.collectStage checked.emitStage header
      sequence.buffers pointers.aliases literal framing)
    (argumentClosing : checked.pipeline.path.argument ≠ framing.closing)
    (carried : File.Carried checked.pipeline checked.syntaxStage checked.resultsStage framing.closing)
    (result : Files.Result checked context countId count sources outputRoot
      (started.state.bindLocal checked.pipeline.path.argument (.signed .i32 1)) completion after)
    (finished : completion = .next) : after.local? framing.closing = some (.string framing.suffixText) := by
  obtain ⟨index, position⟩ := started.loopCursors output
  have read := (bindLocal_preserves_other_local (value := Value.signed .i32 1)
    started.registry.wellFormed argumentClosing).trans started.suffixRead
  exact result.carriedNonScalar finished index position carried read
    (by intro elements same; cases same) (by intro scalar same; cases same)

end Lanius.Extraction.Entry.Startup
