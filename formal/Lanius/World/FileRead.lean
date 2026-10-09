import Lanius.World

namespace Lanius.World

/-- Independent file/handle facts, not successful read execution. -/
structure FileCursor (world : State) (id : Int) (file : FileEntry) (handle : FileHandle) : Prop where
  found : world.handle? id = some handle
  readable : handle.readable = true
  contents : world.file? handle.path = some file

variable {world : State} {id : Int} {file : FileEntry} {handle replacement : FileHandle}
  {service : Lanius.Core.HostService}

theorem FileCursor.record (cursor : FileCursor world id file handle) :
    FileCursor (World.record world service) id file handle := ⟨cursor.found, cursor.readable, cursor.contents⟩

private theorem handle_replaced (found : world.handle? id = some handle)
    (same : replacement.id = handle.id) :
    ({ world with fileHandles := replaceHandle world.fileHandles replacement } : State).handle? id = some replacement := by
  have selected : handle.id = id := by simpa only [beq_iff_eq] using List.find?_some found
  have replacementId := same.trans selected
  let change := fun (old : FileHandle) => if old.id == replacement.id then replacement else old
  have stable : (fun old : FileHandle => (change old).id == id) = (fun old => old.id == id) := by
    funext old
    dsimp [change]
    split <;> simp_all
  change (world.fileHandles.map change).find? (fun old => old.id == id) = _
  rw [List.find?_map]
  change (world.fileHandles.find? (fun old => (change old).id == id)).map change = _
  rw [stable]
  change (world.handle? id).map change = _
  rw [found]
  simp [change, same]

/-- A read supplies exactly the requested prefix and advances this cursor.
    The map law also covers duplicate IDs; uniqueness is not silently assumed. -/
theorem FileCursor.read (cursor : FileCursor world id file handle) (count : Nat) :
    ∃ next, readFileBytes world id count = some ((file.bytes.drop handle.offset).take count, next) ∧
      FileCursor next id file { handle with offset := handle.offset + ((file.bytes.drop handle.offset).take count).length } ∧
      next.calls = world.calls := by
  let bytes := (file.bytes.drop handle.offset).take count
  let replacement := { handle with offset := handle.offset + bytes.length }
  let next := { world with fileHandles := replaceHandle world.fileHandles replacement }
  refine ⟨next, ?_, ⟨handle_replaced cursor.found rfl, cursor.readable, cursor.contents⟩, rfl⟩
  simp only [readFileBytes, cursor.found, cursor.readable, Bool.not_true, Bool.false_eq_true,
    ↓reduceIte, cursor.contents, next, replacement, bytes]

#print axioms FileCursor.read

end Lanius.World
