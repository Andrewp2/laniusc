import Lanius.Extraction.Entry.Path.Initialize
import Lanius.Extraction.Entry.File.Open

namespace Lanius.Extraction.Entry.File

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation

structure PathRelation (read : Path.Read.Stage) (unpack : Input.Unpack.Stage) (opened : Open.Stage) : Prop where
  pointer : opened.pointer = read.pointer
  length : opened.length = unpack.locals.length
  pointerUnshadowed : read.pointer ≠ unpack.locals.cursor
  lengthUnshadowed : opened.handle ≠ unpack.locals.length

def checkPathRelation? (read : Path.Read.Stage) (unpack : Input.Unpack.Stage) (opened : Open.Stage) :
    Option (PLift (PathRelation read unpack opened)) :=
  if valid : opened.pointer = read.pointer ∧ opened.length = unpack.locals.length ∧
      read.pointer ≠ unpack.locals.cursor ∧ opened.handle ≠ unpack.locals.length then
    some ⟨⟨valid.1, valid.2.1, valid.2.2.1, valid.2.2.2⟩⟩ else none

/-- The actual file-body prefix through a successful open. Length checking,
argument copying, path unpacking, synchronization, and the handle guard all
execute here. The remaining execution premise starts at `read_file`. -/
theorem prepare (stage : Path.Length.Stage) (length : Host.CheckedLength program)
    (reader : Host.CheckedExternal program .argRead 3) (read : Path.Read.Stage)
    (readSource : stage.continuation = read.statement reader.function.id) (relation : Path.Relation stage read)
    (unpack : Input.Unpack.Stage) (unpackSource : read.continuation = unpack.statement)
    (supported : unpack.Supported) (unpackRelation : Path.UnpackRelation stage read unpack)
    (opened : Open.Stage) (opener : Host.CheckedExternal program .openRead 2)
    (openSource : unpack.continuation = opened.statement opener.function.id)
    (openRelation : PathRelation read unpack opened)
    (before : State) (initial : Allocation.Registry before) (index : Nat) (path : String)
    (packed output : I32ArrayView)
    (indexRead : before.local? stage.argument = some (.signed .i32 index))
    (pointerRead : before.local? read.pointer = some (.pointer packed.address))
    (packedLocal : before.local? unpack.locals.packed = some
      (.slice (.scalar (.signed .i32)) packed.root [] 0 packed.length))
    (outputLocal : before.local? unpack.locals.output = some
      (.slice (.scalar (.signed .i32)) output.root [] 0 output.length))
    (selected : before.world.arguments[index]? = some path)
    (packedMember : packed ∈ before.i32ArrayViews) (outputMember : output ∈ before.i32ArrayViews)
    (distinct : packed.root ≠ output.root)
    (disjoint : before.i32ArrayViews.Pairwise I32ViewRangesDisjoint)
    (room : (Lanius.World.utf8Bytes path).length ≤ packed.length * 4)
    (capacity : (Lanius.World.utf8Bytes path).length ≤ output.length)
    (bounded : output.length ≤ 2147483647)
    (nonempty : 0 < path.toUTF8.size) (fits : path.toUTF8.size ≤ 1024)
    (sizeFit : (Lanius.World.utf8Bytes path).length < unsignedModulus program.target .usize)
    (fileFound : before.world.file? (Lanius.World.utf8Bytes path) = some file)
    (handleFit : before.world.nextFileHandle ≤ 2147483647)
    (post : Scope.Post)
    (continuationRun : ∀ (original : List Int) middle,
      original.length = output.length → Allocation.Registry middle → Host.RepresentableViews middle →
      middle.cellEntry? output.root = some {
        id := output.root
        value := some (.array (signedI32Values
          ((Lanius.World.utf8Bytes path).map (fun byte => (byte.toNat : Int)) ++
            original.drop (Lanius.World.utf8Bytes path).length))) } →
      middle.world = Host.File.openedWorld
        (Lanius.World.record (Lanius.World.record before.world .argLen) .argRead) (Lanius.World.utf8Bytes path) →
      middle.local? opened.handle = some (.signed .i32 before.world.nextFileHandle) →
      middle.local? stage.length = some (.signed .i32 (Lanius.World.utf8Bytes path).length) →
      middle.i32ArrayViews = before.i32ArrayViews →
      (∀ id, id ≠ stage.length → id ≠ unpack.locals.cursor → id ≠ opened.handle →
        middle.cellId? id = before.cellId? id) →
      (∀ id, id ≠ stage.length → id ≠ unpack.locals.cursor → id ≠ opened.handle → ∀ value,
        (∀ elements, value ≠ .array elements) → before.local? id = some value → middle.local? id = some value) →
      Host.PreservesViews before middle (fun kept => I32ViewRangesDisjoint packed kept ∧ kept.root ≠ output.root) →
      Prefix.Reaches program before (stage.statement length.function.id) middle opened.continuation →
      ∃ completion after, Executes program middle opened.continuation completion after ∧ post completion after) :
    ∃ completion after, Executes program before (stage.statement length.function.id) completion after ∧
      post completion after ∧ after.locals = before.locals := by
  apply stage.withUnpack length reader read readSource relation unpack unpackSource supported unpackRelation
    before initial index path packed output indexRead pointerRead packedLocal outputLocal selected packedMember outputMember
    distinct room capacity bounded nonempty fits sizeFit post
  intro original pathState originalLength registered representable copied contents lengthRead world views bindings kept preserved pathReach
  have pathMember : packed ∈ pathState.i32ArrayViews := by simpa only [views] using packedMember
  have pathOutput : output ∈ pathState.i32ArrayViews := by simpa only [views] using outputMember
  have pointerValue := kept read.pointer (Ne.symm relation.pointerUnshadowed) openRelation.pointerUnshadowed
    _ (by intro elements same; cases same) pointerRead
  have pathFile : pathState.world.file? (Lanius.World.utf8Bytes path) = some file := by
    rw [world]
    exact fileFound
  have pathHandle : pathState.world.nextFileHandle = before.world.nextFileHandle := by
    simp only [world, Lanius.World.record]
  obtain ⟨completion, after, executed, satisfied⟩ := opened.executes opener pathState registered (Lanius.World.utf8Bytes path)
    copied (by simpa only [views] using disjoint) pathMember (openRelation.pointer.symm ▸ pointerValue)
    (openRelation.length.symm ▸ lengthRead) sizeFit pathFile (by simpa only [pathHandle] using handleFit)
    post (by
      intro called calledRegistry frame calledWorld callPreserved middle entered owned openReach
      have atCall := callPreserved (by simpa only [views] using disjoint) output pathOutput trivial _
        (by simp only [readCellProjection, registered.roots output pathOutput, contents, projectedValue])
        (representable output pathOutput _ contents)
      have atEntry := ((bindLocal_effect called opened.handle (.signed .i32 pathState.world.nextFileHandle)).oldCells
        output.root (calledRegistry.root_lt_next (by simpa only [frame.views] using pathOutput))
        (by simp [CellSet.empty])).trans atCall
      apply continuationRun original middle originalLength entered
        (frame.representable.bindLocal calledRegistry opened.handle (.signed .i32 pathState.world.nextFileHandle)) atEntry
      · exact calledWorld.trans (congrArg (fun state => Host.File.openedWorld state (Lanius.World.utf8Bytes path)) world)
      · simpa only [pathHandle] using Assertion.localPointsTo_local _ _ _ _ owned
      · have retained : middle.local? unpack.locals.length = some (.signed .i32 (Lanius.World.utf8Bytes path).length) :=
          (bindLocal_preserves_other_local calledRegistry.wellFormed openRelation.lengthUnshadowed).trans
          (frame.preservesLocal registered lengthRead (by intro elements same; cases same))
        simpa only [unpackRelation.count, relation.count] using retained
      · exact frame.views.trans views
      · intro id notLength notCursor notHandle
        change (called.bindLocal opened.handle (.signed .i32 pathState.world.nextFileHandle)).cellId? id = before.cellId? id
        rw [bindLocal_preserves_other_cellId called opened.handle id _ notHandle.symm]
        simp only [State.cellId?, frame.locals]
        exact bindings id notLength notCursor
      · intro id notLength notCursor notHandle value notArray found
        exact (bindLocal_preserves_other_local calledRegistry.wellFormed (Ne.symm notHandle)).trans
          (frame.preservesLocal registered (kept id notLength notCursor value notArray found) notArray)
      · intro separated view member apart words originalContents range
        have atPath := preserved separated view member apart words originalContents range
        have present : view ∈ pathState.i32ArrayViews := by simpa only [views] using member
        have atOpen := callPreserved (by simpa only [views] using separated) view present trivial words
          (by simp only [readCellProjection, registered.roots view present, atPath, projectedValue]) range
        exact ((bindLocal_effect called opened.handle (.signed .i32 pathState.world.nextFileHandle)).oldCells
          view.root (calledRegistry.root_lt_next (by simpa only [frame.views] using present))
          (by simp [CellSet.empty])).trans atOpen
      · exact pathReach.trans (openSource.symm ▸ openReach))
  exact ⟨completion, after, openSource.symm ▸ executed, satisfied⟩

end Lanius.Extraction.Entry.File
