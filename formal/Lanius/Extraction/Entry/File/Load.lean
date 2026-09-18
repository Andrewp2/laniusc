import Lanius.Extraction.Entry.File.Initialize
import Lanius.Extraction.Entry.File.Read

namespace Lanius.Extraction.Entry.File.Load

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation

/-- The reader arguments survive the path prefix and name the freshly opened
handle. These are checked source/binding facts, not execution premises. -/
structure Relation (length : Path.Length.Stage) (unpack : Input.Unpack.Stage)
    (opened : Open.Stage) (read : Read.Stage) : Prop where
  handle : read.handle = opened.handle
  outputLength : read.output ≠ length.length
  outputCursor : read.output ≠ unpack.locals.cursor
  outputHandle : read.output ≠ opened.handle
  packedLength : read.packed ≠ length.length
  packedCursor : read.packed ≠ unpack.locals.cursor
  packedHandle : read.packed ≠ opened.handle
  countPathLength : read.count ≠ length.length
  closedPathLength : read.closed ≠ length.length

def checkRelation? (length : Path.Length.Stage) (unpack : Input.Unpack.Stage)
    (opened : Open.Stage) (read : Read.Stage) : Option (PLift (Relation length unpack opened read)) :=
  if valid : read.handle = opened.handle ∧ read.output ≠ length.length ∧
      read.output ≠ unpack.locals.cursor ∧ read.output ≠ opened.handle ∧
      read.packed ≠ length.length ∧ read.packed ≠ unpack.locals.cursor ∧ read.packed ≠ opened.handle ∧
      read.count ≠ length.length ∧ read.closed ≠ length.length then
    some ⟨⟨valid.1, valid.2.1, valid.2.2.1, valid.2.2.2.1,
      valid.2.2.2.2.1, valid.2.2.2.2.2.1, valid.2.2.2.2.2.2.1,
      valid.2.2.2.2.2.2.2.1, valid.2.2.2.2.2.2.2.2⟩⟩ else none

/-- Authenticated adjacent stages of the existing Lanius file-loop body. -/
structure Pipeline (program : CoreSynthesis.Program.CheckedProgram artifacts) where
  length : Host.CheckedLength program.core
  path : Path.Length.Stage
  argumentReader : Host.CheckedExternal program.core .argRead 3
  argument : Path.Read.Stage
  argumentSource : path.continuation = argument.statement argumentReader.function.id
  argumentRelation : Path.Relation path argument
  unpack : Input.Unpack.Stage
  unpackSource : argument.continuation = unpack.statement
  unpackSupported : unpack.Supported
  unpackRelation : Path.UnpackRelation path argument unpack
  opener : Host.CheckedExternal program.core .openRead 2
  opened : Open.Stage
  openSource : unpack.continuation = opened.statement opener.function.id
  openRelation : File.PathRelation argument unpack opened
  reader : Input.File.Checked program
  closer : Host.CheckedExternal program.core .close 1
  read : Read.Stage
  readSource : opened.continuation = read.statement reader.source.source.function.id closer.function.id
  readSupported : read.Supported
  readRelation : Relation path unpack opened read

variable {program : CoreSynthesis.Program.CheckedProgram artifacts}

/-- Ordinary entry resources and modeled filesystem conditions. In particular,
neither an opened handle nor a successful reader result is supplied by callers. -/
structure Available (pipeline : Pipeline program) (before : State) where
  index : Nat
  path : String
  file : Lanius.World.FileEntry
  packedPath : I32ArrayView
  pathOutput : I32ArrayView
  source : I32ArrayView
  scratch : I32ArrayView
  registry : Allocation.Registry before
  representable : Host.RepresentableViews before
  packedPathMember : packedPath ∈ before.i32ArrayViews
  pathMember : pathOutput ∈ before.i32ArrayViews
  sourceMember : source ∈ before.i32ArrayViews
  scratchMember : scratch ∈ before.i32ArrayViews
  indexRead : before.local? pipeline.path.argument = some (.signed .i32 index)
  pointerRead : before.local? pipeline.argument.pointer = some (.pointer packedPath.address)
  packedPathRead : before.local? pipeline.unpack.locals.packed = some
    (.slice (.scalar (.signed .i32)) packedPath.root [] 0 packedPath.length)
  pathRead : before.local? pipeline.unpack.locals.output = some
    (.slice (.scalar (.signed .i32)) pathOutput.root [] 0 pathOutput.length)
  sourceRead : before.local? pipeline.read.output = some
    (.slice (.scalar (.signed .i32)) source.root [] 0 source.length)
  scratchRead : before.local? pipeline.read.packed = some
    (.slice (.scalar (.signed .i32)) scratch.root [] 0 scratch.length)
  selected : before.world.arguments[index]? = some path
  fileFound : before.world.file? (Lanius.World.utf8Bytes path) = some file
  handleFit : before.world.nextFileHandle ≤ 2147483647
  fresh : ∀ older ∈ before.world.fileHandles, older.id ≠ (before.world.nextFileHandle : Int)
  pathNonempty : 0 < path.toUTF8.size
  pathFits : path.toUTF8.size ≤ 1024
  pathRoom : (Lanius.World.utf8Bytes path).length ≤ packedPath.length * 4
  pathCapacity : (Lanius.World.utf8Bytes path).length ≤ pathOutput.length
  pathBound : pathOutput.length ≤ 2147483647
  pathDistinct : packedPath.root ≠ pathOutput.root
  sourcePackedPathDistinct : source.root ≠ packedPath.root
  sourcePathDistinct : source.root ≠ pathOutput.root
  sourceScratchDistinct : source.root ≠ scratch.root
  pathScratchDistinct : pathOutput.root ≠ scratch.root
  sourceCapacity : 65536 ≤ source.length
  sourceBound : source.length ≤ 2147483647
  scratchCapacity : 65536 ≤ scratch.length * 4
  sizeFit : 65536 < unsignedModulus program.core.target .usize

structure Input (pipeline : Pipeline program) (before : State) extends Available pipeline before where
  fileFits : file.bytes.length ≤ 65536

variable {pipeline : Pipeline program} {before : State}

def Available.openWorld (input : Available pipeline before) : Lanius.World.State :=
  Host.File.openedWorld (Lanius.World.record (Lanius.World.record before.world .argLen) .argRead)
    (Lanius.World.utf8Bytes input.path)

def Available.loadedWorld (_input : Available pipeline before) (reads : Nat) : Lanius.World.State := {
  before.world with
  nextFileHandle := before.world.nextFileHandle + 1
  calls := before.world.calls ++ [.argLen, .argRead, .openRead] ++ List.replicate reads .read ++ [.close] }

/-- Resources at the reader boundary, independent of whether the opened
file fits. The same storage and host facts serve success and rejection. -/
def Available.readerResources (input : Available pipeline before) (original : List Int)
    (length : original.length = input.source.length) : Extraction.Input.File.Resources := {
  output := input.source
  packed := input.scratch
  original := original
  capacity := 65536
  world := input.openWorld
  originalHandles := before.world.fileHandles
  handle := { id := before.world.nextFileHandle, path := Lanius.World.utf8Bytes input.path, readable := true }
  file := input.file
  handles := rfl
  fresh := input.fresh
  readable := rfl
  fileFound := input.fileFound
  originalLength := length
  capacityBound := input.sourceCapacity
  outputBound := input.sourceBound
  scratch := input.scratchCapacity
  outputPacked := input.sourceScratchDistinct }

theorem Available.readerBytes (input : Available pipeline before) (original length) :
    (input.readerResources original length).bytes = input.file.bytes := by
  simp [Extraction.Input.File.Resources.bytes, Available.readerResources]

theorem Available.readerWorld (input : Available pipeline before) (original length reads) :
    Read.closedWorld (input.readerResources original length) reads = input.loadedWorld reads := by
  simp [Read.closedWorld, Extraction.Input.File.Resources.finalWorld, Available.readerResources, Available.openWorld,
    Available.loadedWorld, Host.File.openedWorld, Lanius.World.record, List.append_assoc]

structure Opened (input : Available pipeline before) (state : State) where
  original : List Int
  sourceLength : original.length = input.source.length
  sourceBefore : before.cellEntry? input.source.root = some {
    id := input.source.root, value := some (.array (signedI32Values original)) }
  registry : Allocation.Registry state
  representable : Host.RepresentableViews state
  source : state.cellEntry? input.source.root = some {
    id := input.source.root, value := some (.array (signedI32Values original)) }
  pathOriginal : List Int
  pathLength : pathOriginal.length = input.pathOutput.length
  path : state.cellEntry? input.pathOutput.root = some {
    id := input.pathOutput.root, value := some (.array (signedI32Values
      ((Lanius.World.utf8Bytes input.path).map (fun byte => (byte.toNat : Int)) ++
        pathOriginal.drop (Lanius.World.utf8Bytes input.path).length))) }
  world : state.world = input.openWorld
  handleRead : state.local? pipeline.read.handle = some (.signed .i32 before.world.nextFileHandle)
  sourceRead : state.local? pipeline.read.output = some (.slice (.scalar (.signed .i32)) input.source.root [] 0 input.source.length)
  scratchRead : state.local? pipeline.read.packed = some (.slice (.scalar (.signed .i32)) input.scratch.root [] 0 input.scratch.length)
  pathCount : state.local? pipeline.path.length = some (.signed .i32 (Lanius.World.utf8Bytes input.path).length)
  views : state.i32ArrayViews = before.i32ArrayViews
  bindings : ∀ id, id ≠ pipeline.path.length → id ≠ pipeline.unpack.locals.cursor → id ≠ pipeline.opened.handle →
    state.cellId? id = before.cellId? id
  locals : ∀ id, id ≠ pipeline.path.length → id ≠ pipeline.unpack.locals.cursor → id ≠ pipeline.opened.handle →
    ∀ value, (∀ elements, value ≠ .array elements) → before.local? id = some value → state.local? id = some value
  preserved : Host.PreservesViews before state (fun kept =>
    I32ViewRangesDisjoint input.packedPath kept ∧ kept.root ≠ input.pathOutput.root)
  reached : Prefix.Reaches program.core before (pipeline.path.statement pipeline.length.function.id)
    state (pipeline.read.statement pipeline.reader.source.source.function.id pipeline.closer.function.id)

theorem Pipeline.prepare (pipeline : Pipeline program) (input : Available pipeline before)
    (post : Scope.Post)
    (continuationRun : ∀ ready, Opened input ready →
      ∃ completion after, Executes program.core ready
        (pipeline.read.statement pipeline.reader.source.source.function.id pipeline.closer.function.id)
        completion after ∧ post completion after) :
    ∃ completion after, Executes program.core before (pipeline.path.statement pipeline.length.function.id) completion after ∧
      post completion after ∧ after.locals = before.locals := by
  apply File.prepare pipeline.path pipeline.length pipeline.argumentReader pipeline.argument
    pipeline.argumentSource pipeline.argumentRelation pipeline.unpack pipeline.unpackSource pipeline.unpackSupported
    pipeline.unpackRelation pipeline.opened pipeline.opener pipeline.openSource pipeline.openRelation
    before input.registry input.index input.path input.packedPath input.pathOutput input.indexRead input.pointerRead
    input.packedPathRead input.pathRead input.selected input.packedPathMember input.pathMember input.pathDistinct
    input.registry.disjoint input.pathRoom input.pathCapacity input.pathBound input.pathNonempty input.pathFits
    (by have bound := input.pathFits; have size := input.sizeFit; simpa [Lanius.World.utf8Bytes] using
      (show input.path.toUTF8.size < unsignedModulus program.core.target .usize by omega))
    input.fileFound input.handleFit post
  intro pathOriginal opened pathLength registered representable pathContents openedWorld handleRead pathCount views bindings kept preserved openedReach
  obtain ⟨original, sourceLength, sourceContents⟩ := input.registry.storage input.sourceMember
  have sourceAtOpen := preserved input.registry.disjoint input.source input.sourceMember
    ⟨input.registry.apart input.packedPathMember input.sourceMember (Ne.symm input.sourcePackedPathDistinct),
      input.sourcePathDistinct⟩ original
    (by simp only [readCellProjection, input.registry.roots input.source input.sourceMember, sourceContents, projectedValue])
    (input.representable input.source input.sourceMember original sourceContents)
  obtain ⟨completion, after, run, done⟩ := continuationRun opened {
    original := original
    sourceLength := sourceLength
    sourceBefore := sourceContents
    registry := registered
    representable := representable
    source := sourceAtOpen
    pathOriginal := pathOriginal
    pathLength := pathLength
    path := pathContents
    world := openedWorld
    handleRead := by simpa only [pipeline.readRelation.handle] using handleRead
    sourceRead := kept _ pipeline.readRelation.outputLength pipeline.readRelation.outputCursor pipeline.readRelation.outputHandle
      _ (by intro elements same; cases same) input.sourceRead
    scratchRead := kept _ pipeline.readRelation.packedLength pipeline.readRelation.packedCursor pipeline.readRelation.packedHandle
      _ (by intro elements same; cases same) input.scratchRead
    pathCount := pathCount
    views := views
    bindings := bindings
    locals := kept
    preserved := preserved
    reached := pipeline.readSource ▸ openedReach }
  exact ⟨completion, after, pipeline.readSource.symm ▸ run, done⟩

/-- Facts at the actual `extract_syntax` entry. Both buffers have explicit
physical contents; the separately returned source count is the file length. -/
structure Loaded (input : Input pipeline before) (ready : State) : Prop where
  registry : Allocation.Registry ready
  representable : Host.RepresentableViews ready
  views : ready.i32ArrayViews = before.i32ArrayViews
  source : ∃ original : List Int, original.length = input.source.length ∧
    before.cellEntry? input.source.root = some {
      id := input.source.root, value := some (.array (signedI32Values original)) } ∧
    ready.cellEntry? input.source.root = some {
      id := input.source.root, value := some (.array (signedI32Values (Input.copiedBuffer [] original input.file.bytes))) }
  path : ∃ original : List Int, original.length = input.pathOutput.length ∧
    ready.cellEntry? input.pathOutput.root = some {
      id := input.pathOutput.root, value := some (.array (signedI32Values
        ((Lanius.World.utf8Bytes input.path).map (fun byte => (byte.toNat : Int)) ++
          original.drop (Lanius.World.utf8Bytes input.path).length))) }
  count : ready.local? pipeline.read.count = some (.signed .i32 input.file.bytes.length)
  pathCount : ready.local? pipeline.path.length = some (.signed .i32 (Lanius.World.utf8Bytes input.path).length)
  world : ∃ reads, 0 < reads ∧ ready.world = input.loadedWorld reads
  bindings : ∀ id, id ≠ pipeline.path.length → id ≠ pipeline.unpack.locals.cursor → id ≠ pipeline.opened.handle →
    id ≠ pipeline.read.count → id ≠ pipeline.read.closed → ready.cellId? id = before.cellId? id
  locals : ∀ id, id ≠ pipeline.path.length → id ≠ pipeline.unpack.locals.cursor → id ≠ pipeline.opened.handle →
    id ≠ pipeline.read.count → id ≠ pipeline.read.closed → ∀ value, (∀ elements, value ≠ .array elements) →
    before.local? id = some value → ready.local? id = some value
  preserved : Host.PreservesViews before ready (fun kept =>
    I32ViewRangesDisjoint input.packedPath kept ∧ kept.root ≠ input.pathOutput.root ∧
      kept.root ≠ input.source.root ∧ kept.root ≠ input.scratch.root)
  reached : Prefix.Reaches program.core before (pipeline.path.statement pipeline.length.function.id)
    ready pipeline.read.continuation

theorem Pipeline.executes (pipeline : Pipeline program) (input : Input pipeline before)
    (post : Scope.Post)
    (continuationRun : ∀ ready, Loaded input ready →
      ∃ completion after, Executes program.core ready pipeline.read.continuation completion after ∧ post completion after) :
    ∃ completion after, Executes program.core before (pipeline.path.statement pipeline.length.function.id) completion after ∧
      post completion after ∧ after.locals = before.locals := by
  apply pipeline.prepare input.toAvailable post
  intro opened prepared
  rcases prepared with ⟨sourceOriginal, sourceLength, sourceContents, registered, representable, sourceAtOpen,
    pathOriginal, pathLength, pathContents, openedWorld, handleRead, sourceRead, scratchRead, pathCount,
    views, bindings, kept, preserved, openedReach⟩
  let resources := input.readerResources sourceOriginal sourceLength
  have resourceBytes : resources.bytes = input.file.bytes := input.readerBytes sourceOriginal sourceLength
  have resourceWorld (reads : Nat) : Read.closedWorld resources reads = input.loadedWorld reads :=
    input.readerWorld sourceOriginal sourceLength reads
  obtain ⟨completion, after, run, done⟩ := pipeline.read.executes pipeline.readSupported pipeline.reader pipeline.closer
    resources registered representable registered.disjoint
    (by simpa only [views, resources, Available.readerResources] using input.sourceMember)
    (by simpa only [views, resources, Available.readerResources] using input.scratchMember) sourceAtOpen
    handleRead sourceRead scratchRead
    openedWorld (by rw [resourceBytes]; exact input.fileFits) rfl input.sizeFit
    (fun completion state => post completion state) (by
      intro readState ready _ readyRegistry readyRepresentable readySource readyWorld readyCount readyViews readyBindings readyLocals readyPreserved readReach
      suffices found : ∃ completion after, Executes program.core ready pipeline.read.continuation completion after ∧ post completion after by
        obtain ⟨completion, after, run, done⟩ := found
        exact ⟨completion, after, run, post.restore completion readState after done⟩
      apply continuationRun ready
      refine ⟨readyRegistry, readyRepresentable, readyViews.trans views,
        ⟨sourceOriginal, sourceLength, sourceContents, ?_⟩, ⟨pathOriginal, pathLength, ?_⟩, ?_, ?_, ?_, ?_, ?_, ?_,
        openedReach.trans readReach⟩
      · simpa only [resources, Available.readerResources, Extraction.Input.File.Resources.bytes, List.drop_zero] using readySource
      · have member : input.pathOutput ∈ opened.i32ArrayViews := by simpa only [views] using input.pathMember
        exact readyPreserved registered.disjoint input.pathOutput member
          ⟨Ne.symm input.sourcePathDistinct, input.pathScratchDistinct⟩ _
          (by simp only [readCellProjection, registered.roots input.pathOutput member, pathContents, projectedValue])
          (representable input.pathOutput member _ pathContents)
      · simpa only [resourceBytes] using readyCount
      · exact readyLocals _ (Ne.symm pipeline.readRelation.countPathLength) (Ne.symm pipeline.readRelation.closedPathLength)
          _ (by intro elements same; cases same) pathCount
      · obtain ⟨reads, positive, world⟩ := readyWorld
        exact ⟨reads, positive, world.trans (resourceWorld reads)⟩
      · intro id notLength notCursor notHandle notCount notClosed
        exact (readyBindings id notCount notClosed).trans (bindings id notLength notCursor notHandle)
      · intro id notLength notCursor notHandle notCount notClosed value notArray found
        exact readyLocals id notCount notClosed value notArray (kept id notLength notCursor notHandle value notArray found)
      · intro disjoint view member apart words contents range
        have atOpen := preserved disjoint view member ⟨apart.1, apart.2.1⟩ words contents range
        have atMember : view ∈ opened.i32ArrayViews := by simpa only [views] using member
        exact readyPreserved (by simpa only [views] using disjoint) view atMember apart.2.2 words
          (by simp only [readCellProjection, registered.roots view atMember, atOpen, projectedValue]) range)
  exact ⟨completion, after, run, done⟩

end Lanius.Extraction.Entry.File.Load
