import Lanius.Extraction.Entry.Path.Read

namespace Lanius.Extraction.Entry.Path

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation

structure Relation (length : Length.Stage) (read : Read.Stage) : Type where
  argument : read.argument = length.argument
  count : read.length = length.length
  argumentUnshadowed : length.length ≠ length.argument
  pointerUnshadowed : length.length ≠ read.pointer

def checkRelation? (length : Length.Stage) (read : Read.Stage) : Option (Relation length read) :=
  if valid : read.argument = length.argument ∧ read.length = length.length ∧
      length.length ≠ length.argument ∧ length.length ≠ read.pointer then
    some ⟨valid.1, valid.2.1, valid.2.2.1, valid.2.2.2⟩
  else none

theorem bytes_length (text : String) : (Lanius.World.utf8Bytes text).length = text.toUTF8.size := by
  simp only [Lanius.World.utf8Bytes, Array.length_toList, ByteArray.size]

/-- The file-body prefix validates the selected argument's byte length,
copies its exact bytes, and passes both source guards. Registry and local
preservation at the read boundary follow from the length stage's result. -/
theorem Length.Stage.withRead (stage : Length.Stage) (length : Host.CheckedLength program)
    (reader : Host.CheckedExternal program .argRead 3) (read : Read.Stage)
    (source : stage.continuation = read.statement reader.function.id) (relation : Relation stage read)
    (before : State) (initial : Allocation.Registry before) (index : Nat) (path : String)
    (indexRead : before.local? stage.argument = some (.signed .i32 index))
    (pointerRead : before.local? read.pointer = some (.pointer view.address))
    (selected : before.world.arguments[index]? = some path)
    (member : view ∈ before.i32ArrayViews)
    (room : (Lanius.World.utf8Bytes path).length ≤ view.length * 4)
    (nonempty : 0 < path.toUTF8.size) (fits : path.toUTF8.size ≤ 1024)
    (sizeFit : (Lanius.World.utf8Bytes path).length < unsignedModulus program.target .usize)
    (post : Scope.Post)
    (continuationRun : ∀ middle, Allocation.Registry middle →
      Host.Copied view (Lanius.World.utf8Bytes path) middle →
      middle.world = Lanius.World.record (Lanius.World.record before.world .argLen) .argRead →
      middle.i32ArrayViews = before.i32ArrayViews →
      middle.local? read.length = some (.signed .i32 (Lanius.World.utf8Bytes path).length) →
      Host.RepresentableViews middle →
      (∀ id, id ≠ stage.length → middle.cellId? id = before.cellId? id) →
      (∀ id, id ≠ stage.length → ∀ value, (∀ elements, value ≠ .array elements) →
        before.local? id = some value → middle.local? id = some value) →
      Host.PreservesViews before middle (I32ViewRangesDisjoint view) →
      Prefix.Reaches program before (stage.statement length.function.id) middle read.continuation →
      ∃ completion after, Executes program middle read.continuation completion after ∧ post completion after) :
    ∃ completion after, Executes program before (stage.statement length.function.id) completion after ∧
      post completion after ∧ after.locals = before.locals := by
  apply stage.executes length before initial index path indexRead selected nonempty fits post
  intro called registered frame world preserved scopedState entered owned lengthReach
  let ready := called.bindLocal stage.length (.signed .i32 path.toUTF8.size)
  have keep {id : VarId} {value : Value} (different : stage.length ≠ id)
      (notArray : ∀ elements, value ≠ .array elements) (found : before.local? id = some value) :
      ready.local? id = some value :=
    (bindLocal_preserves_other_local registered.wellFormed different).trans
      (frame.preservesLocal initial found notArray)
  have readyIndex : ready.local? read.argument = some (.signed .i32 index) := by
    rw [relation.argument]
    exact keep relation.argumentUnshadowed (by intro elements same; cases same) indexRead
  have readyPointer := keep relation.pointerUnshadowed (by intro elements same; cases same) pointerRead
  have readyLength : ready.local? read.length = some (.signed .i32 (Lanius.World.utf8Bytes path).length) := by
    simpa only [relation.count, bytes_length] using Assertion.localPointsTo_local _ _ _ _ owned
  have readySelected : ready.world.arguments[index]? = some path := by
    change called.world.arguments[index]? = some path
    rw [world]
    exact selected
  have readyViews : ready.i32ArrayViews = before.i32ArrayViews := frame.views
  obtain ⟨completion, after, executed, satisfied⟩ := read.executes reader ready entered index path readyIndex readyPointer readyLength
    readySelected (by simpa only [readyViews] using member) room
    (by rw [bytes_length]; omega) sizeFit post (by
      intro middle middleRegistry readFrame readWorld copied readPreserved readReach
      have finalViews := readFrame.views.trans readyViews
      have finalWorld : middle.world = Lanius.World.record (Lanius.World.record before.world .argLen) .argRead := by
        simpa only [ready, State.bindLocal, State.bindCell, world] using readWorld
      have finalLength := readFrame.preservesLocal entered readyLength (by intro elements same; cases same)
      apply continuationRun middle middleRegistry copied finalWorld finalViews finalLength readFrame.representable
      · intro id different
        simp only [State.cellId?, readFrame.locals]
        change ready.cellId? id = before.cellId? id
        rw [show ready.cellId? id = called.cellId? id from
          bindLocal_preserves_other_cellId called stage.length id _ different.symm]
        simp only [State.cellId?, frame.locals]
      · intro id different value notArray found
        exact readFrame.preservesLocal entered (keep (Ne.symm different) notArray found) notArray
      · intro disjoint kept present apart words contents range
        have calledContents := preserved disjoint kept present trivial words contents range
        have readyContents : readCellProjection ready kept.root kept.projections = .ok (.array (signedI32Values words)) := by
          have keptBelow := registered.root_lt_next (by simpa only [frame.views] using present)
          have keptCell := (bindLocal_effect called stage.length (.signed .i32 path.toUTF8.size)).oldCells
            kept.root keptBelow (by simp [CellSet.empty])
          simp only [ready, readCellProjection, keptCell, calledContents, initial.roots kept present, projectedValue]
        exact readPreserved (by simpa only [readyViews] using disjoint) kept
          (by simpa only [readyViews] using present) apart words readyContents range
      · exact lengthReach.trans (source.symm ▸ readReach))
  exact ⟨completion, after, source.symm ▸ executed, satisfied⟩

end Lanius.Extraction.Entry.Path
