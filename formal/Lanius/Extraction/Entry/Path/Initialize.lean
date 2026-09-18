import Lanius.Extraction.Entry.Path.Prefix
import Lanius.Extraction.Input.Unpack.Initialize

namespace Lanius.Extraction.Entry.Path

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation

structure UnpackRelation (length : Length.Stage) (read : Read.Stage) (unpack : Input.Unpack.Stage) : Prop where
  direct : unpack.locals.total = none
  count : unpack.locals.length = read.length
  packedUnshadowed : unpack.locals.packed ≠ length.length
  outputUnshadowed : unpack.locals.output ≠ length.length

def checkUnpackRelation? (length : Length.Stage) (read : Read.Stage) (unpack : Input.Unpack.Stage) :
    Option (PLift (UnpackRelation length read unpack)) :=
  if valid : unpack.locals.total = none ∧ unpack.locals.length = read.length ∧ unpack.locals.packed ≠ length.length ∧
      unpack.locals.output ≠ length.length then some ⟨⟨valid.1, valid.2.1, valid.2.2.1, valid.2.2.2⟩⟩ else none

/-- The complete argument-path prefix: validate its byte length, copy it,
and materialize the exact bytes in the path array. No successful host call,
scratch decoding, or unpacking invariant is assumed. The next execution
premise begins at the file-open statement. -/
theorem Length.Stage.withUnpack (stage : Length.Stage) (length : Host.CheckedLength program)
    (reader : Host.CheckedExternal program .argRead 3) (read : Read.Stage)
    (readSource : stage.continuation = read.statement reader.function.id) (relation : Relation stage read)
    (unpack : Input.Unpack.Stage) (unpackSource : read.continuation = unpack.statement)
    (supported : unpack.Supported) (unpackRelation : UnpackRelation stage read unpack)
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
    (room : (Lanius.World.utf8Bytes path).length ≤ packed.length * 4)
    (capacity : (Lanius.World.utf8Bytes path).length ≤ output.length)
    (bounded : output.length ≤ 2147483647)
    (nonempty : 0 < path.toUTF8.size) (fits : path.toUTF8.size ≤ 1024)
    (sizeFit : (Lanius.World.utf8Bytes path).length < unsignedModulus program.target .usize)
    (post : Scope.Post)
    (continuationRun : ∀ (original : List Int) middle,
      original.length = output.length → Allocation.Registry middle → Host.RepresentableViews middle →
      Host.Copied packed (Lanius.World.utf8Bytes path) middle →
      middle.cellEntry? output.root = some {
        id := output.root
        value := some (.array (signedI32Values
          ((Lanius.World.utf8Bytes path).map (fun byte => (byte.toNat : Int)) ++
            original.drop (Lanius.World.utf8Bytes path).length))) } →
      middle.local? unpack.locals.length = some (.signed .i32 (Lanius.World.utf8Bytes path).length) →
      middle.world = Lanius.World.record (Lanius.World.record before.world .argLen) .argRead →
      middle.i32ArrayViews = before.i32ArrayViews →
      (∀ id, id ≠ stage.length → id ≠ unpack.locals.cursor → middle.cellId? id = before.cellId? id) →
      (∀ id, id ≠ stage.length → id ≠ unpack.locals.cursor → ∀ value,
        (∀ elements, value ≠ .array elements) → before.local? id = some value → middle.local? id = some value) →
      Host.PreservesViews before middle (fun kept => I32ViewRangesDisjoint packed kept ∧ kept.root ≠ output.root) →
      Prefix.Reaches program before (stage.statement length.function.id) middle unpack.continuation →
      ∃ completion after, Executes program middle unpack.continuation completion after ∧ post completion after) :
    ∃ completion after, Executes program before (stage.statement length.function.id) completion after ∧
      post completion after ∧ after.locals = before.locals := by
  apply stage.withRead length reader read readSource relation before initial index path indexRead pointerRead selected
    packedMember room nonempty fits sizeFit post
  intro copiedState copiedRegistry copied copiedWorld copiedViews copiedLength representable bindings kept copyPreserved copyReach
  have packedRead := kept _ unpackRelation.packedUnshadowed _ (by intro elements same; cases same) packedLocal
  have outputRead := kept _ unpackRelation.outputUnshadowed _ (by intro elements same; cases same) outputLocal
  have lengthRead : copiedState.local? unpack.locals.length =
      some (.signed .i32 (Lanius.World.utf8Bytes path).length) := unpackRelation.count.symm ▸ copiedLength
  obtain ⟨completion, after, executed, satisfied⟩ := unpack.executes supported program copiedState copiedRegistry representable packed output
    (Lanius.World.utf8Bytes path) 0 (by simp [Input.UnpackLocals.Offset, unpackRelation.direct]) copied (by simpa only [copiedViews] using packedMember)
    (by simpa only [copiedViews] using outputMember) distinct packedRead outputRead lengthRead (by simpa using capacity) bounded
    (fun completion state => post completion state) (by
      intro original middle originalLength originalContents middleRegistry middleRepresentable middleCopied outputContents effect localsKept unpackReach
      suffices found : ∃ completion after, Executes program middle unpack.continuation completion after ∧ post completion after by
        obtain ⟨completion, after, run, done⟩ := found
        exact ⟨completion, after, run, post.restore completion copiedState after done⟩
      apply continuationRun original middle originalLength middleRegistry middleRepresentable middleCopied
        (by simpa only [List.take_zero, List.nil_append, Nat.zero_add] using outputContents)
      · exact localsKept _ (Ne.symm supported.length) _ (by intro elements same; cases same) lengthRead
      · exact effect.world.trans copiedWorld
      · exact effect.views.trans copiedViews
      · intro id notLength notCursor
        simp only [State.cellId?, effect.locals]
        change (copiedState.bindLocal unpack.locals.cursor (.signed .i32 0)).cellId? id = before.cellId? id
        rw [bindLocal_preserves_other_cellId copiedState unpack.locals.cursor id _ notCursor.symm]
        exact bindings id notLength
      · intro id notLength notCursor value notArray found
        exact localsKept id notCursor value notArray (kept id notLength value notArray found)
      · intro disjoint view member apart words contents range
        have atCopy := copyPreserved disjoint view member apart.1 words contents range
        have old := copiedRegistry.root_lt_next (by simpa only [copiedViews] using member)
        have atEntry := ((bindLocal_effect copiedState unpack.locals.cursor (.signed .i32 0)).oldCells
          view.root old (by simp [CellSet.empty])).trans atCopy
        exact effect.preserves_entry (copiedRegistry.bindLocal unpack.locals.cursor (.signed .i32 0)).wellFormed
          atEntry (by
            intro written
            exact written.elim apart.2 (Nat.ne_of_lt old))
      · exact copyReach.trans (unpackSource.symm ▸ unpackReach))
  exact ⟨completion, after, unpackSource.symm ▸ executed, satisfied⟩

end Lanius.Extraction.Entry.Path
