import Lanius.Extraction.Entry.Suffix.Call
import Lanius.Extraction.Entry.Startup.Output

namespace Lanius.Extraction.Entry.Suffix
open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation

/-- Ordinary suffix-call resources. `earlier` is precisely the emitted
prefix, while `untouched` is unused output capacity, not certificate data. -/
structure Resources (stage : Stage) (framing : Framing.Stage) (outputCell : CellId) (before : State) where
  earlier : List Int
  untouched : List Int
  registry : Allocation.Registry before
  outputRead : before.local? stage.output = some
    (.slice (.scalar (.signed .i32)) outputCell [] 0 (earlier.length + untouched.length))
  positionRead : before.local? stage.position = some (.signed .i32 earlier.length)
  suffixRead : before.local? stage.closing = some (.string framing.suffixText)
  backing : before.cellEntry? outputCell = some {
    id := outputCell, value := some (.array (signedI32Values (earlier ++ untouched))) }
  capacity : stage.capacity ≤ earlier.length + untouched.length
  positionBound : earlier.length ≤ stage.capacity

end Lanius.Extraction.Entry.Suffix

namespace Lanius.Extraction.Entry.Startup
open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation

variable {program : CoreSynthesis.Program.CheckedProgram artifacts}
variable {main : Stmt} {entry : CheckedArguments program.core main}
variable {checked : File.Checked program}

/-- Derive every input to the actual suffix call from startup and the
completed ordered loop. The output root, slice, current bytes, cursor, and
original suffix literal are connected; no new ownership invariant or assumed
serialization result is supplied. Capacity for the suffix itself is left for
the success/failure branch, not assumed during resource construction. -/
theorem Ready.suffixResources (started : Ready entry sequence pointers literal data framing header before)
    (stage : Suffix.Stage) (supported : Suffix.Supported stage framing)
    (headerRelation : Framing.HeaderRelation framing header)
    (output : Files.OutputSource checked.pipeline checked.syntaxStage checked.collectStage checked.emitStage header
      sequence.buffers pointers.aliases literal framing)
    (names : (sequence.buffers.map Allocation.Buffer.binding).Nodup)
    (argumentClosing : checked.pipeline.path.argument ≠ framing.closing)
    (carried : File.Carried checked.pipeline checked.syntaxStage checked.resultsStage framing.closing)
    (result : Files.Result checked context countId count sources started.outputCell
      (started.state.bindLocal checked.pipeline.path.argument (.signed .i32 1)) completion after)
    (finished : completion = .next) :
    ∃ resources : Suffix.Resources stage framing started.outputCell after,
    ∃ units : List CompactDecode.UnitData,
      units.length = count ∧
      Files.History count units sources resources.earlier.length (resources.earlier ++ resources.untouched) := by
  obtain ⟨storage, _pointers⟩ :=
    started.bufferAfterFiles output output.output names
      (checked.emitRelation.carried _ (by simp [File.Emit.Stage.carriedLocals])) result finished
  have originalRead := storage.originalRead
  have outputRead := storage.read
  have sameRead : started.original.local? checked.emitStage.output = some
      (.slice (.scalar (.signed .i32)) started.outputCell [] 0 started.untouched.length) := by
    simpa only [output.outputBinding] using started.originalOutput
  have root : storage.view.root = started.outputCell := by
    have same := originalRead.symm.trans sameRead
    injection same with same
    injection same
  have outputLength : started.untouched.length = 16777216 := by
    have same := originalRead.symm.trans sameRead
    injection same with same
    injection same
    omega
  obtain ⟨registry, _words, _views, ⟨units, position, contents, history, countUnits, length, backing, positionRead⟩, _index, _argc⟩ :=
    result.completed finished
  have prefixBound : (Files.bytes count units).length ≤ contents.length := by
    have copied := congrArg List.length history.output
    simp only [List.length_take, List.length_map] at copied
    omega
  let earlier := contents.take (Files.bytes count units).length
  let untouched := contents.drop (Files.bytes count units).length
  have earlierLength : earlier.length = (Files.bytes count units).length := by
    simp only [earlier, List.length_take, Nat.min_eq_left prefixBound]
  have whole : earlier ++ untouched = contents := List.take_append_drop _ _
  have total : earlier.length + untouched.length = 16777216 := by
    simpa only [List.length_append] using (congrArg List.length whole).trans length
  have suffixRead := started.suffixAfterFiles output argumentClosing carried result finished
  have outputCapacity : stage.capacity ≤ 16777216 := by
    rw [supported.capacity, ← outputLength]
    exact started.outputCapacity
  let resources : Suffix.Resources stage framing started.outputCell after := {
    earlier, untouched, registry
    outputRead := by simpa only [supported.output, output.outputBinding, root, total] using outputRead
    positionRead := by simpa only [supported.position, output.positionBinding, headerRelation.position,
      history.cursor, earlierLength] using positionRead
    suffixRead := by simpa only [supported.closing] using suffixRead
    backing := by simpa only [whole] using backing
    capacity := by rw [total]; exact outputCapacity
    positionBound := by rw [supported.capacity, output.capacity, earlierLength]; omega }
  refine ⟨resources, units, countUnits, ?_⟩
  change Files.History count units sources earlier.length (earlier ++ untouched)
  rw [whole, earlierLength, ← history.cursor]
  exact history

end Lanius.Extraction.Entry.Startup
