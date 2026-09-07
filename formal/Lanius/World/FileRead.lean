import Lanius.World
import Lanius.Memory.Store

namespace Lanius.World

open Lanius Lanius.Core Lanius.Memory

/-- Opening an existing file for reading appends one readable handle, without
changing any input bytes or unrelated world fields. -/
theorem openFile_read_exact
    (found : world.file? path = some file) :
    openFile world path true false false =
      (Int.ofNat world.nextFileHandle, {
        world with
        fileHandles := world.fileHandles ++ [{
          id := Int.ofNat world.nextFileHandle, path := path, readable := true }]
        nextFileHandle := world.nextFileHandle + 1
      }) := by
  simp [openFile, found]

theorem readFileBytes_exact
    {id : Int}
    (handleFound : world.handle? id = some handle)
    (readable : handle.readable = true)
    (fileFound : world.file? handle.path = some file) :
    readFileBytes world id capacity =
      some ((file.bytes.drop handle.offset).take capacity, {
        world with fileHandles := replaceHandle world.fileHandles {
          handle with offset := handle.offset +
            ((file.bytes.drop handle.offset).take capacity).length }
      }) := by
  simp [readFileBytes, handleFound, readable, fileFound]

/-- A successful read can only return the requested prefix of the current
file suffix; it cannot fabricate source bytes or exceed the request. -/
theorem readFileBytes_invert
    {id : Int}
    (read : readFileBytes before id capacity = some (bytes, after)) :
    ∃ handle file,
      before.handle? id = some handle ∧ handle.readable = true ∧
      before.file? handle.path = some file ∧
      bytes = (file.bytes.drop handle.offset).take capacity ∧
      after = { before with fileHandles := replaceHandle before.fileHandles {
        handle with offset := handle.offset + bytes.length } } := by
  cases handleFound : before.handle? id with
  | none => simp [readFileBytes, handleFound] at read
  | some handle =>
      cases readable : handle.readable with
      | false => simp [readFileBytes, handleFound, readable] at read
      | true =>
          cases fileFound : before.file? handle.path with
          | none => simp [readFileBytes, handleFound, readable, fileFound] at read
          | some file =>
              rw [readFileBytes_exact handleFound readable fileFound] at read
              cases read
              refine ⟨handle, file, ?_, ?_, ?_, rfl, rfl⟩ <;> simp_all

theorem readFileBytes_preserves_inputs
    {id : Int}
    (read : readFileBytes before id capacity = some (bytes, after)) :
    bytes.length ≤ capacity ∧ after.files = before.files ∧
      after.arguments = before.arguments ∧ after.standardOutput = before.standardOutput ∧
      after.standardError = before.standardError := by
  obtain ⟨_, _, _, _, _, rfl, rfl⟩ := readFileBytes_invert read
  exact ⟨List.length_take_le _ _, rfl, rfl, rfl, rfl⟩

/-- A positive-size request returning no bytes means the file has been
consumed. The capacity-plus-one probe in `read_file` relies on this distinction
between EOF and a zero-size request. -/
theorem readFileBytes_empty_is_eof
    {id : Int}
    (handleFound : world.handle? id = some handle)
    (readable : handle.readable = true)
    (fileFound : world.file? handle.path = some file)
    (positive : 0 < capacity)
    (read : readFileBytes world id capacity = some ([], after)) :
    file.bytes.length ≤ handle.offset := by
  rw [readFileBytes_exact handleFound readable fileFound] at read
  have empty : (file.bytes.drop handle.offset).take capacity = [] :=
    congrArg Prod.fst (Option.some.inj read)
  have length := congrArg List.length empty
  simp only [List.length_take, List.length_drop, List.length_nil] at length
  omega

/-- Reading through the newly opened handle changes no older handle. This
is the loop invariant needed to close the source handle on either success or
failure without leaking it or closing a caller-owned handle. -/
theorem replaceHandle_appended_fresh
    {original : List FileHandle} {opened : FileHandle} (offset : Nat)
    (fresh : ∀ handle ∈ original, handle.id ≠ opened.id) :
    replaceHandle (original ++ [opened]) { opened with offset } =
      original ++ [{ opened with offset }] := by
  have preserved : original.map (fun handle =>
      if handle.id == opened.id then { opened with offset } else handle) = original := by
    induction original with
    | nil => rfl
    | cons first rest induction =>
        have head := fresh first (by simp)
        have restFresh := fun (handle : FileHandle) (member : handle ∈ rest) =>
          fresh handle (by simp [member])
        simp only [List.map_cons]
        rw [induction restFresh]
        simp [head]
  simpa only [replaceHandle, List.map_append, List.map_cons, List.map_nil,
    BEq.rfl, if_true] using congrArg (· ++ [{ opened with offset }]) preserved

/-- Reading into a valid host buffer writes exactly the current file suffix
prefix and advances the modeled handle offset by that same byte count. -/
theorem read_call_exact
    {id : Int}
    (handleFound : world.handle? id = some handle)
    (readable : handle.readable = true)
    (fileFound : world.file? handle.path = some file)
    (stored : heap.storeBytes pointer ((file.bytes.drop handle.offset).take capacity) = .ok copied) :
    call heap world .read [.signed .i32 id, .pointer pointer, .unsigned .usize capacity] =
      .returned (i32Result ((file.bytes.drop handle.offset).take capacity).length) copied {
        world with
        calls := world.calls ++ [.read]
        fileHandles := replaceHandle world.fileHandles {
          handle with offset := handle.offset + ((file.bytes.drop handle.offset).take capacity).length }
      } := by
  have handleRecorded : (record world .read).handle? id = some handle := handleFound
  have fileRecorded : (record world .read).file? handle.path = some file := fileFound
  simp only [call, callSimple]
  rw [readFileBytes_exact handleRecorded readable fileRecorded]
  simp only [stored]
  rfl

theorem read_call_buffer_contents
    {file : FileEntry}
    (wellFormed : HeapWellFormed heap)
    (stored : heap.storeBytes pointer ((file.bytes.drop offset).take capacity) = .ok copied) :
    copied.loadBytes pointer ((file.bytes.drop offset).take capacity).length =
      .ok ((file.bytes.drop offset).take capacity) :=
  Heap.loadBytes_after_store wellFormed stored

theorem read_call_returned_invert
    {id : Int}
    (handleFound : world.handle? id = some handle)
    (readable : handle.readable = true)
    (fileFound : world.file? handle.path = some file)
    (called : call heap world .read
      [.signed .i32 id, .pointer pointer, .unsigned .usize capacity] =
        .returned result afterHeap afterWorld) :
    result = i32Result ((file.bytes.drop handle.offset).take capacity).length ∧
      heap.storeBytes pointer ((file.bytes.drop handle.offset).take capacity) = .ok afterHeap ∧
      afterWorld = {
        world with
        calls := world.calls ++ [.read]
        fileHandles := replaceHandle world.fileHandles {
          handle with offset := handle.offset + ((file.bytes.drop handle.offset).take capacity).length }
      } := by
  have handleRecorded : (record world .read).handle? id = some handle := handleFound
  have fileRecorded : (record world .read).file? handle.path = some file := fileFound
  simp only [call, callSimple] at called
  rw [readFileBytes_exact handleRecorded readable fileRecorded] at called
  cases stored : heap.storeBytes pointer ((file.bytes.drop handle.offset).take capacity) with
  | error reason => simp [stored] at called
  | ok copied =>
      simp only [stored] at called
      cases called
      exact ⟨rfl, rfl, rfl⟩

theorem handle_appended_fresh
    {world : State} {original : List FileHandle} {opened : FileHandle}
    (fresh : ∀ handle ∈ original, handle.id ≠ opened.id)
    (handles : world.fileHandles = original ++ [opened]) :
    world.handle? opened.id = some opened := by
  unfold State.handle?
  rw [handles, List.find?_append]
  have absent : original.find? (fun handle => handle.id == opened.id) = none := by
    apply List.find?_eq_none.mpr
    intro handle member
    simpa using fresh handle member
  simp [absent]

/-- Each read advances only the newly opened handle. This invariant is
preserved for both nonempty chunks and the final EOF read. -/
theorem readFileBytes_appended_fresh
    (fresh : ∀ handle ∈ original, handle.id ≠ opened.id)
    (handles : world.fileHandles = original ++ [opened])
    (readable : opened.readable = true)
    (fileFound : world.file? opened.path = some file) :
    readFileBytes world opened.id capacity = some (
      (file.bytes.drop opened.offset).take capacity, {
        world with fileHandles := original ++ [{
          opened with offset := opened.offset + ((file.bytes.drop opened.offset).take capacity).length
        }]
      }) := by
  rw [readFileBytes_exact (handle_appended_fresh fresh handles) readable fileFound,
    handles, replaceHandle_appended_fresh _ fresh]

/-- Closing the fresh handle restores the original handle list. Freshness is
an explicit premise: otherwise closing could also delete a pre-existing handle
with the same identifier. -/
theorem closeHandle_appended_fresh
    (fresh : ∀ handle ∈ original, handle.id ≠ opened.id)
    (handles : world.fileHandles = original ++ [opened]) :
    closeHandle world opened.id = some { world with fileHandles := original } := by
  have found := handle_appended_fresh fresh handles
  have preserved : original.filter (fun handle => handle.id != opened.id) = original := by
    apply List.filter_eq_self.mpr
    intro handle member
    simpa using fresh handle member
  simp [closeHandle, found, handles, List.filter_append, preserved]

end Lanius.World
