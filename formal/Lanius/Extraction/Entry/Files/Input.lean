import Lanius.Extraction.Entry.Files.Allocation
import Lanius.Extraction.Entry.Files.Request
import Lanius.Extraction.Host.Typed
import Lanius.Extraction.Entry.Path.Buffers

namespace Lanius.Extraction.Entry.Files
open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation

variable {program : CoreSynthesis.Program.CheckedProgram artifacts}
variable {pipeline : File.Load.Pipeline program}

/-- The four allocations and one pointer alias consumed by file loading.
All fields are checked against source declarations, not runtime premises. -/
structure LoadingSource (pipeline : File.Load.Pipeline program)
    (buffers : List Allocation.Buffer) (aliases : List Pointers.Alias)
    (literal : Grammar.LiteralStage) (framing : Framing.Stage) where
  packedPath : BufferSource buffers aliases literal framing pipeline.path.argument pipeline.unpack.locals.packed 256
  path : BufferSource buffers aliases literal framing pipeline.path.argument pipeline.unpack.locals.output 1024
  source : BufferSource buffers aliases literal framing pipeline.path.argument pipeline.read.output 65536
  scratch : BufferSource buffers aliases literal framing pipeline.path.argument pipeline.read.packed 16384
  pointer : PointerSource aliases literal framing pipeline.path.argument pipeline.argument.pointer pipeline.unpack.locals.packed
  distinct : pipeline.unpack.locals.packed ≠ pipeline.unpack.locals.output ∧
    pipeline.read.output ≠ pipeline.unpack.locals.packed ∧ pipeline.read.output ≠ pipeline.unpack.locals.output ∧
    pipeline.read.output ≠ pipeline.read.packed ∧ pipeline.unpack.locals.output ≠ pipeline.read.packed

def checkLoadingSource? (pipeline : File.Load.Pipeline program)
    (buffers : List Allocation.Buffer) (aliases : List Pointers.Alias)
    (literal : Grammar.LiteralStage) (framing : Framing.Stage) :
    Option (LoadingSource pipeline buffers aliases literal framing) := do
  let packedPath ← checkBufferSource? buffers aliases literal framing pipeline.path.argument pipeline.unpack.locals.packed 256
  let path ← checkBufferSource? buffers aliases literal framing pipeline.path.argument pipeline.unpack.locals.output 1024
  let source ← checkBufferSource? buffers aliases literal framing pipeline.path.argument pipeline.read.output 65536
  let scratch ← checkBufferSource? buffers aliases literal framing pipeline.path.argument pipeline.read.packed 16384
  let pointer ← checkPointerSource? aliases literal framing pipeline.path.argument pipeline.argument.pointer pipeline.unpack.locals.packed
  if distinct : pipeline.unpack.locals.packed ≠ pipeline.unpack.locals.output ∧
      pipeline.read.output ≠ pipeline.unpack.locals.packed ∧ pipeline.read.output ≠ pipeline.unpack.locals.output ∧
      pipeline.read.output ≠ pipeline.read.packed ∧ pipeline.unpack.locals.output ≠ pipeline.read.packed then
    pure ⟨packedPath, path, source, scratch, pointer, distinct⟩
  else none

/-- The path buffers exist before any filesystem assumptions are made. -/
theorem LoadingSource.pathBuffers (checked : LoadingSource pipeline buffers aliases literal framing)
    (history : Allocation.HostReady buffers initial allocated)
    (frame : Pointers.AliasFrame aliases allocated original)
    (registry : Allocation.Registry original) (readyRegistry : Allocation.Registry ready)
    (names : (buffers.map Allocation.Buffer.binding).Nodup)
    (retained : Retained literal framing original ready) :
    Nonempty (Path.Buffers pipeline.argument pipeline.unpack
      (ready.bindLocal pipeline.path.argument (.signed .i32 1))) := by
  obtain ⟨packed⟩ := checked.packedPath.storage history frame registry readyRegistry names retained
  obtain ⟨output⟩ := checked.path.storage history frame registry readyRegistry names retained
  exact ⟨{
    packed := packed.view
    output := output.view
    packedMember := packed.member
    outputMember := output.member
    pointerRead := checked.pointer.read packed frame registry readyRegistry retained
    packedRead := by simpa only [packed.length] using packed.read
    outputRead := by simpa only [output.length] using output.read
    packedLength := packed.length
    outputLength := output.length
    distinct := packed.apart output checked.packedPath checked.path history frame names checked.distinct.1 }⟩

/-- Keep the allocation witnesses used to construct the loader input. Later
frontend/output resources can prove separation from these same four views. -/
structure InputStorage (original : State) {current : State} (input : File.Load.Available pipeline current) where
  packedPath : BufferStorage pipeline.unpack.locals.packed 256 original current
  path : BufferStorage pipeline.unpack.locals.output 1024 original current
  source : BufferStorage pipeline.read.output 65536 original current
  scratch : BufferStorage pipeline.read.packed 16384 original current
  packedPathView : packedPath.view = input.packedPath
  pathView : path.view = input.pathOutput
  sourceView : source.view = input.source
  scratchView : scratch.view = input.scratch

theorem InputStorage.apart {current : State} {input : File.Load.Available pipeline current}
    (storage : InputStorage original input)
    (loading : LoadingSource pipeline buffers aliases literal framing)
    (buffer : BufferStorage binding count original current)
    (selected : BufferSource buffers aliases literal framing pipeline.path.argument binding count)
    (history : Allocation.HostReady buffers initial allocated)
    (frame : Pointers.AliasFrame aliases allocated original)
    (names : (buffers.map Allocation.Buffer.binding).Nodup)
    (different : binding ≠ pipeline.unpack.locals.packed ∧ binding ≠ pipeline.unpack.locals.output ∧
      binding ≠ pipeline.read.output ∧ binding ≠ pipeline.read.packed) :
    buffer.view.root ≠ input.packedPath.root ∧ buffer.view.root ≠ input.pathOutput.root ∧
      buffer.view.root ≠ input.source.root ∧ buffer.view.root ≠ input.scratch.root := by
  exact ⟨storage.packedPathView ▸ buffer.apart storage.packedPath selected loading.packedPath history frame names different.1,
    storage.pathView ▸ buffer.apart storage.path selected loading.path history frame names different.2.1,
    storage.sourceView ▸ buffer.apart storage.source selected loading.source history frame names different.2.2.1,
    storage.scratchView ▸ buffer.apart storage.scratch selected loading.scratch history frame names different.2.2.2⟩

/-- Derive the first file-loader invocation from actual startup allocations,
preserved aliases, and the ordinary external request. In particular, callers
do not supply buffer ownership, pointer addresses, or root separation. -/
theorem LoadingSource.available {initialWorld : Lanius.World.State}
    (checked : LoadingSource pipeline buffers aliases literal framing)
    (history : Allocation.HostReady buffers initial allocated)
    (frame : Pointers.AliasFrame aliases allocated original)
    (registry : Allocation.Registry original) (readyRegistry : Allocation.Registry ready)
    (names : (buffers.map Allocation.Buffer.binding).Nodup)
    (retained : Retained literal framing original ready)
    (typed : RuntimeStateHasType program.core context
      (ready.bindLocal pipeline.path.argument (.signed .i32 1)) store)
    (world : ready.world = { initialWorld with calls := calls })
    (request : Request)
    (selected : initialWorld.arguments[1]? = some request.path)
    (fileFound : initialWorld.file? (Lanius.World.utf8Bytes request.path) = some request.file)
    (pathNonempty : 0 < request.path.toUTF8.size) (pathFits : request.path.toUTF8.size ≤ 1024)
    (handleFit : initialWorld.nextFileHandle ≤ 2147483647)
    (olderHandles : ∀ handle ∈ initialWorld.fileHandles, handle.id < (initialWorld.nextFileHandle : Int))
    (sizeFit : 65536 < unsignedModulus program.core.target .usize) :
    ∃ input : File.Load.Available pipeline (ready.bindLocal pipeline.path.argument (.signed .i32 1)),
      input.index = 1 ∧ input.path = request.path ∧ input.file = request.file ∧
      input.packedPath.length = 256 ∧ input.pathOutput.length = 1024 ∧
      input.source.length = 65536 ∧ input.scratch.length = 16384 ∧ Nonempty (InputStorage original input) := by
  obtain ⟨packedPath⟩ := checked.packedPath.storage history frame registry readyRegistry names retained
  obtain ⟨path⟩ := checked.path.storage history frame registry readyRegistry names retained
  obtain ⟨source⟩ := checked.source.storage history frame registry readyRegistry names retained
  obtain ⟨scratch⟩ := checked.scratch.storage history frame registry readyRegistry names retained
  have pointerRead := checked.pointer.read packedPath frame registry readyRegistry retained
  have valid := readyRegistry.bindLocal pipeline.path.argument (.signed .i32 1)
  let input : File.Load.Available pipeline (ready.bindLocal pipeline.path.argument (.signed .i32 1)) := {
    index := 1
    path := request.path
    file := request.file
    packedPath := packedPath.view
    pathOutput := path.view
    source := source.view
    scratch := scratch.view
    registry := valid
    representable := Host.RepresentableViews.ofRuntime typed valid.roots
    packedPathMember := packedPath.member
    pathMember := path.member
    sourceMember := source.member
    scratchMember := scratch.member
    indexRead := bindLocal_finds_local _ _ _ readyRegistry.wellFormed
    pointerRead := pointerRead
    packedPathRead := by simpa only [packedPath.length] using packedPath.read
    pathRead := by simpa only [path.length] using path.read
    sourceRead := by simpa only [source.length] using source.read
    scratchRead := by simpa only [scratch.length] using scratch.read
    selected := by simpa only [State.bindLocal, State.bindCell, world, Nat.add_zero] using selected
    fileFound := by
      simpa only [State.bindLocal, State.bindCell, world, Lanius.World.State.file?] using fileFound
    handleFit := by simpa only [State.bindLocal, State.bindCell, world] using handleFit
    fresh := by
      simpa only [State.bindLocal, State.bindCell, world] using
        (show ∀ handle ∈ initialWorld.fileHandles, handle.id ≠ (initialWorld.nextFileHandle : Int) from
          fun handle member => Int.ne_of_lt (olderHandles handle member))
    pathNonempty := pathNonempty
    pathFits := pathFits
    pathRoom := by simpa only [packedPath.length, Lanius.World.utf8Bytes, Array.length_toList, ByteArray.size] using pathFits
    pathCapacity := by simpa only [path.length, Lanius.World.utf8Bytes, Array.length_toList, ByteArray.size] using pathFits
    pathBound := by rw [path.length]; decide
    pathDistinct := packedPath.apart path checked.packedPath checked.path history frame names checked.distinct.1
    sourcePackedPathDistinct := source.apart packedPath checked.source checked.packedPath history frame names checked.distinct.2.1
    sourcePathDistinct := source.apart path checked.source checked.path history frame names checked.distinct.2.2.1
    sourceScratchDistinct := source.apart scratch checked.source checked.scratch history frame names checked.distinct.2.2.2.1
    pathScratchDistinct := path.apart scratch checked.path checked.scratch history frame names checked.distinct.2.2.2.2
    sourceCapacity := by rw [source.length]; decide
    sourceBound := by rw [source.length]; decide
    scratchCapacity := by rw [scratch.length]; decide
    sizeFit := sizeFit }
  exact ⟨input, rfl, rfl, rfl, packedPath.length, path.length, source.length, scratch.length,
    ⟨⟨packedPath, path, source, scratch, rfl, rfl, rfl, rfl⟩⟩⟩

/-- Successful loading adds the external file-size bound to the same actual
allocation witnesses. Oversized files use `available` without that bound. -/
theorem LoadingSource.input (checked : LoadingSource pipeline buffers aliases literal framing)
    (history : Allocation.HostReady buffers initial allocated)
    (frame : Pointers.AliasFrame aliases allocated original)
    (registry : Allocation.Registry original) (readyRegistry : Allocation.Registry ready)
    (names : (buffers.map Allocation.Buffer.binding).Nodup)
    (retained : Retained literal framing original ready)
    (typed : RuntimeStateHasType program.core context
      (ready.bindLocal pipeline.path.argument (.signed .i32 1)) store)
    (world : ready.world = { initialWorld with calls := calls })
    (pending : Pending initialWorld 1 (request :: rest))
    (handleFit : initialWorld.nextFileHandle ≤ 2147483647)
    (olderHandles : ∀ handle ∈ initialWorld.fileHandles, handle.id < (initialWorld.nextFileHandle : Int))
    (sizeFit : 65536 < unsignedModulus program.core.target .usize) :
    ∃ input : File.Load.Input pipeline (ready.bindLocal pipeline.path.argument (.signed .i32 1)),
      input.index = 1 ∧ input.path = request.path ∧ input.file = request.file ∧
      input.packedPath.length = 256 ∧ input.pathOutput.length = 1024 ∧
      input.source.length = 65536 ∧ input.scratch.length = 16384 ∧ Nonempty (InputStorage original input.toAvailable) := by
  obtain ⟨available, index, path, file, packedPath, pathLength, sourceLength, scratch, storage⟩ :=
    checked.available history frame registry readyRegistry names retained typed world request
      (by simpa only [Nat.add_zero] using pending.selected 0 request (by simp))
      (pending.files request List.mem_cons_self) (pending.nonempty request List.mem_cons_self)
      (pending.pathFits request List.mem_cons_self) handleFit olderHandles sizeFit
  let input : File.Load.Input pipeline (ready.bindLocal pipeline.path.argument (.signed .i32 1)) := {
    toAvailable := available
    fileFits := by rw [file]; exact pending.fileFits request List.mem_cons_self }
  exact ⟨input, index, path, file, packedPath, pathLength, sourceLength, scratch, storage⟩

end Lanius.Extraction.Entry.Files
