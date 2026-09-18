import Lanius.Extraction.Entry.File.Load
import Lanius.Extraction.Entry.Path.Buffers
import Lanius.Extraction.ExtractorContract

namespace Lanius.Extraction.Entry.File.Load
open Lanius.Core Lanius.Semantics Lanius.Properties

/-- A missing file is rejected by the complete length/copy/unpack/open
prefix. All host calls and memory accesses are derived from entry resources;
there is no assumed execution, readable-file premise, or handle bound. -/
theorem Pipeline.rejectsMissing (pipeline : Pipeline program)
    (buffers : Path.Buffers pipeline.argument pipeline.unpack before)
    (initial : Allocation.Registry before) (index : Nat) (path : String)
    (indexRead : before.local? pipeline.path.argument = some (.signed .i32 index))
    (selected : before.world.arguments[index]? = some path)
    (nonempty : 0 < path.toUTF8.size) (fits : path.toUTF8.size ≤ 1024)
    (missing : before.world.file? (Lanius.World.utf8Bytes path) = none)
    (sizeFit : 65536 < unsignedModulus program.core.target .usize) :
    ∃ after, Executes program.core before (pipeline.path.statement pipeline.length.function.id)
        (.returned (some (.signed .i32 5))) after ∧
      ExtractorContract.MemorySafe after ∧ after.world = { before.world with
        calls := before.world.calls ++ [.argLen, .argRead, .openRead] } := by
  let post : Scope.Post := {
    holds := fun completion after => completion = .returned (some (.signed .i32 5)) ∧
      ExtractorContract.MemorySafe after ∧ after.world = { before.world with
        calls := before.world.calls ++ [.argLen, .argRead, .openRead] }
    restore := fun _ _ _ proved => proved }
  obtain ⟨completion, final, executed, satisfied, _⟩ := pipeline.path.withUnpack
    pipeline.length pipeline.argumentReader pipeline.argument pipeline.argumentSource pipeline.argumentRelation
    pipeline.unpack pipeline.unpackSource pipeline.unpackSupported pipeline.unpackRelation
    before initial index path buffers.packed buffers.output indexRead buffers.pointerRead
    buffers.packedRead buffers.outputRead selected buffers.packedMember buffers.outputMember buffers.distinct
    (by simpa [buffers.packedLength, Lanius.World.utf8Bytes] using fits)
    (by simpa [buffers.outputLength, Lanius.World.utf8Bytes] using fits)
    (by rw [buffers.outputLength]; decide) nonempty fits
    (by simpa [Lanius.World.utf8Bytes] using (show path.toUTF8.size < unsignedModulus program.core.target .usize by omega)) post (by
      intro original middle originalLength registered representable copied contents lengthRead world views bindings kept preserved reached
      have pointerRead := kept pipeline.argument.pointer (Ne.symm pipeline.argumentRelation.pointerUnshadowed)
        pipeline.openRelation.pointerUnshadowed _ (by intro elements same; cases same) buffers.pointerRead
      have absent : middle.world.file? (Lanius.World.utf8Bytes path) = none := by
        rw [world]
        exact missing
      obtain ⟨after, run, valid, _, afterWorld⟩ := pipeline.opened.rejectsMissing pipeline.opener middle registered
        (Lanius.World.utf8Bytes path) copied (by simpa only [views] using buffers.packedMember)
        (pipeline.openRelation.pointer.symm ▸ pointerRead) (pipeline.openRelation.length.symm ▸ lengthRead)
        (by simpa [Lanius.World.utf8Bytes] using (show path.toUTF8.size < unsignedModulus program.core.target .usize by omega)) absent
      refine ⟨.returned (some (.signed .i32 5)), after, pipeline.openSource.symm ▸ run, rfl,
        ⟨valid.wellFormed.heapWellFormed, valid.blocks⟩, ?_⟩
      simp [afterWorld, world, Lanius.World.record, List.append_assoc])
  exact ⟨final, satisfied.1 ▸ executed, satisfied.2⟩

end Lanius.Extraction.Entry.File.Load
