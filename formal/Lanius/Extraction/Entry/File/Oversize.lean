import Lanius.Extraction.Entry.File.Load
import Lanius.Extraction.ExtractorContract
import Lanius.Extraction.Diagnostics.Read

namespace Lanius.Extraction.Entry.File.Read

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Extraction.CompactOutput

/-- An oversized source returns 6 only after the actual read_file call and
mandatory close. The frontend continuation does not execute. -/
theorem Stage.rejectsOversized (stage : Stage) (supported : stage.Supported)
    (diagnostics : Diagnostics.Read.Checked program argument stage.count stage.failure)
    (distinct : stage.count ≠ argument ∧ stage.closed ≠ argument)
    (reader : Input.File.Checked program) (closer : Host.CheckedExternal program.core .close 1)
    (resources : Input.File.Resources) (initial : Allocation.Registry before)
    (representable : Host.RepresentableViews before) (disjoint : before.i32ArrayViews.Pairwise I32ViewRangesDisjoint)
    (outputMember : resources.output ∈ before.i32ArrayViews) (packedMember : resources.packed ∈ before.i32ArrayViews)
    (outputContents : before.cellEntry? resources.output.root = some {
      id := resources.output.root
      value := some (.array (signedI32Values resources.original)) })
    (handleRead : before.local? stage.handle = some (.signed .i32 resources.handle.id))
    (outputRead : before.local? stage.output = some (.slice i32 resources.output.root [] 0 resources.output.length))
    (packedRead : before.local? stage.packed = some (.slice i32 resources.packed.root [] 0 resources.packed.length))
    (argumentRead : before.local? argument = some (.signed .i32 index)) (indexFit : index ≤ 2147483647)
    (world : before.world = resources.world) (oversize : resources.capacity < resources.bytes.length)
    (fixedCapacity : resources.capacity = 65536) (sizeFit : 65536 < unsignedModulus program.core.target .usize) :
    ∃ after, Executes program.core before (stage.statement reader.source.source.function.id closer.function.id)
      (.returned (some (.signed .i32 6))) after ∧ ExtractorContract.MemorySafe after ∧
      ∃ reads, 0 < reads ∧ Host.StderrOnly (closedWorld resources reads) after.world := by
  obtain ⟨readState, closed, readCall, finished, closeCall, closedRegistry, frame, finalWorld, _⟩ :=
    stage.readClose supported reader closer resources initial representable disjoint outputMember packedMember
      outputContents handleRead outputRead packedRead world fixedCapacity sizeFit
  have result : resources.result = -2 := if_neg (Nat.not_le.mpr oversize)
  rw [result] at readCall closeCall frame
  let counted := readState.bindLocal stage.count (.signed .i32 (-2))
  let ready := closed.bindLocal stage.closed (.signed .i32 0)
  have countedRegistry := finished.registry.bindLocal stage.count (.signed .i32 (-2))
  have readyRegistry := closedRegistry.bindLocal stage.closed (.signed .i32 0)
  have countedCount := Assertion.localPointsTo_local _ _ _ _
    (bindLocal_owns_fresh readState stage.count (.signed .i32 (-2)) finished.registry.wellFormed)
  have readyCount : ready.local? stage.count = some (.signed .i32 (-2)) :=
    (bindLocal_preserves_other_local closedRegistry.wellFormed supported.count).trans
      (frame.preservesLocal countedRegistry countedCount (by intro elements same; cases same))
  have first : Evaluates program.core ready (binary .lessEqual (read stage.count) negativeOne) (.boolean true) ready := by
    apply evaluatesEagerBinary (by decide) (by decide) (local_evaluates program.core readyCount)
      (negativeOne_evaluates program.core ready)
    simp [evalBinaryValue, evalSignedBinary]
  have guard : Evaluates program.core ready stage.guard (.boolean true) ready := evaluatesLogicalOrTrue first
  have readyArgument : ready.local? argument = some (.signed .i32 index) :=
    (bindLocal_preserves_other_local closedRegistry.wellFormed distinct.2).trans
      (frame.preservesLocal countedRegistry
        ((bindLocal_preserves_other_local finished.registry.wellFormed distinct.1).trans
          (preservesLocal resources initial outputMember packedMember finished argumentRead (by intro values same; cases same)))
        (by intro values same; cases same))
  obtain ⟨after, stopped, registered, _, _, stderr⟩ := diagnostics.oversized readyRegistry
    (frame.representable.bindLocal closedRegistry stage.closed (.signed .i32 0)) readyArgument indexFit readyCount
  obtain ⟨reads, positive, closeWorld⟩ := finalWorld
  exact ⟨restoreLocals readState (restoreLocals closed after), executesLetLocal readCall
    (executesLetLocal closeCall (executesSequenceReturned (executesIfTrue guard stopped))),
    ⟨registered.wellFormed.heapWellFormed, registered.blocks⟩, reads, positive, closeWorld ▸ stderr⟩

end Lanius.Extraction.Entry.File.Read

namespace Lanius.Extraction.Entry.File.Load

open Lanius.Core Lanius.Semantics Lanius.Properties

/-- The complete path/open/read/close body rejects an oversized file. No
internal reader state, prior successful load, or frontend result is assumed. -/
theorem Pipeline.rejectsOversized (pipeline : Pipeline program) (input : Available pipeline before)
    (diagnostics : Diagnostics.Read.Checked program pipeline.path.argument pipeline.read.count pipeline.read.failure)
    (unshadowed : pipeline.path.argument ∉ [pipeline.path.length, pipeline.unpack.locals.cursor, pipeline.opened.handle,
      pipeline.read.count, pipeline.read.closed])
    (indexFit : input.index ≤ 2147483647)
    (oversize : 65536 < input.file.bytes.length) :
    ∃ after, Executes program.core before (pipeline.path.statement pipeline.length.function.id)
      (.returned (some (.signed .i32 6))) after ∧ ExtractorContract.MemorySafe after ∧
      ∃ reads, 0 < reads ∧ Host.StderrOnly (input.loadedWorld reads) after.world := by
  let post : Scope.Post := {
    holds := fun completion after => completion = .returned (some (.signed .i32 6)) ∧
      ExtractorContract.MemorySafe after ∧ ∃ reads, 0 < reads ∧ Host.StderrOnly (input.loadedWorld reads) after.world
    restore := fun _ _ _ proved => proved }
  obtain ⟨completion, after, run, done, _⟩ := pipeline.prepare input post (by
    intro opened prepared
    let resources := input.readerResources prepared.original prepared.sourceLength
    have different : pipeline.path.argument ≠ pipeline.path.length ∧ pipeline.path.argument ≠ pipeline.unpack.locals.cursor ∧
        pipeline.path.argument ≠ pipeline.opened.handle ∧ pipeline.path.argument ≠ pipeline.read.count ∧
        pipeline.path.argument ≠ pipeline.read.closed := by
      simp only [List.mem_cons, List.not_mem_nil, or_false, not_or] at unshadowed
      exact unshadowed
    have argumentRead := prepared.locals pipeline.path.argument different.1 different.2.1 different.2.2.1
      _ (by intro values same; cases same) input.indexRead
    obtain ⟨after, run, safe, reads, positive, world⟩ := pipeline.read.rejectsOversized pipeline.readSupported diagnostics
      ⟨different.2.2.2.1.symm, different.2.2.2.2.symm⟩
      pipeline.reader pipeline.closer resources prepared.registry prepared.representable prepared.registry.disjoint
      (by simpa only [prepared.views, resources, Available.readerResources] using input.sourceMember)
      (by simpa only [prepared.views, resources, Available.readerResources] using input.scratchMember) prepared.source
      prepared.handleRead prepared.sourceRead prepared.scratchRead argumentRead (Int.ofNat_le.mpr indexFit) prepared.world
      (by change 65536 < resources.bytes.length; rw [input.readerBytes]; exact oversize) rfl input.sizeFit
    exact ⟨.returned (some (.signed .i32 6)), after, run, rfl, safe, reads, positive,
      (input.readerWorld prepared.original prepared.sourceLength reads) ▸ world⟩)
  exact ⟨after, done.1 ▸ run, done.2⟩

end Lanius.Extraction.Entry.File.Load
