import Lanius.Extraction.Entry.Retained

namespace Lanius.Extraction.Entry.Files
open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation

/-- Source-checked allocation and non-shadowing facts for one file-loop
buffer. This record contains no runtime storage or execution assumptions. -/
structure BufferSource (buffers : List Allocation.Buffer) (aliases : List Pointers.Alias)
    (literal : Grammar.LiteralStage) (framing : Framing.Stage) (argument binding : VarId) (count : Nat) where
  selection : BufferSelection buffers aliases binding count
  capacity : selection.buffer.count = count
  startup : binding ∉ startupLocals literal framing
  argument : argument ≠ binding

def checkBufferSource? (buffers : List Allocation.Buffer) (aliases : List Pointers.Alias)
    (literal : Grammar.LiteralStage) (framing : Framing.Stage) (argument binding : VarId) (count : Nat) :
    Option (BufferSource buffers aliases literal framing argument binding count) := do
  let selection ← checkBuffer? buffers aliases binding count
  if valid : selection.buffer.count = count ∧ binding ∉ startupLocals literal framing ∧ argument ≠ binding then
    pure ⟨selection, valid.1, valid.2.1, valid.2.2⟩
  else none

/-- The real allocation's view and current words, with its original binding
retained so distinct buffer declarations imply distinct backing cells. -/
structure BufferStorage (binding : VarId) (count : Nat) (original current : State) where
  view : I32ArrayView
  values : List Int
  originalMember : view ∈ original.i32ArrayViews
  member : view ∈ current.i32ArrayViews
  length : view.length = count
  capacity : values.length = count
  originalRead : original.local? binding = some (.slice (.scalar (.signed .i32)) view.root [] 0 count)
  read : current.local? binding = some (.slice (.scalar (.signed .i32)) view.root [] 0 count)
  stored : current.cellEntry? view.root = some { id := view.root, value := some (.array (signedI32Values values)) }

theorem BufferSource.storage {argument : VarId}
    (source : BufferSource buffers aliases literal framing argument binding count)
    (history : Allocation.HostReady buffers initial allocated)
    (frame : Pointers.AliasFrame aliases allocated original)
    (registry : Allocation.Registry original) (readyRegistry : Allocation.Registry ready)
    (names : (buffers.map Allocation.Buffer.binding).Nodup)
    (retained : Retained literal framing original ready) :
    Nonempty (BufferStorage binding count original (ready.bindLocal argument (.signed .i32 1))) := by
  obtain ⟨view, values, originalMember, member, length, capacity, originalRead, read, stored⟩ :=
    retained.buffer history frame registry readyRegistry names source.selection.buffer source.selection.member
      source.selection.notShadowed (source.selection.destination ▸ source.startup)
  have length : view.length = count := length.trans source.capacity
  have capacity : values.length = count := capacity.trans source.capacity
  have beforeRead : original.local? binding = some (.slice (.scalar (.signed .i32)) view.root [] 0 count) := by
    simpa only [source.selection.destination, source.capacity] using originalRead
  have readyRead : ready.local? binding = some (.slice (.scalar (.signed .i32)) view.root [] 0 count) := by
    simpa only [source.selection.destination, capacity] using read
  have currentRead := (bindLocal_preserves_other_local
    (value := Value.signed .i32 1) readyRegistry.wellFormed source.argument).trans readyRead
  have currentStored := ((bindLocal_effect ready argument (.signed .i32 1)).oldCells view.root
    (StateWellFormed.cell_lt_next_of_entry readyRegistry.wellFormed stored)
    (by simp [CellSet.empty])).trans stored
  exact ⟨⟨view, values, originalMember, member, length, capacity, beforeRead, currentRead, currentStored⟩⟩

theorem BufferStorage.apart (left : BufferStorage leftId leftCount original current)
    (right : BufferStorage rightId rightCount original current)
    (leftSource : BufferSource buffers aliases literal framing argument leftId leftCount)
    (rightSource : BufferSource buffers aliases literal framing argument rightId rightCount)
    (history : Allocation.HostReady buffers initial allocated)
    (frame : Pointers.AliasFrame aliases allocated original)
    (names : (buffers.map Allocation.Buffer.binding).Nodup) (different : leftId ≠ rightId) :
    left.view.root ≠ right.view.root := by
  apply Pointers.allocatedRootsDistinct history frame names leftSource.selection.buffer rightSource.selection.buffer
    leftSource.selection.member rightSource.selection.member
    (by simpa only [← leftSource.selection.destination, ← rightSource.selection.destination] using different)
    leftSource.selection.notShadowed rightSource.selection.notShadowed
  · simpa only [leftSource.selection.destination] using left.originalRead
  · simpa only [rightSource.selection.destination] using right.originalRead

/-- A source-level alias must refer to this slice and remain live until the
file loop. Distinct alias names make its final binding unambiguous. -/
structure PointerSource (aliases : List Pointers.Alias) (literal : Grammar.LiteralStage)
    (framing : Framing.Stage) (argument pointer binding : VarId) where
  alias : Pointers.Alias
  member : alias ∈ aliases
  name : alias.name = pointer
  source : alias.source = .slice binding
  names : (aliases.map Pointers.Alias.name).Nodup
  sliceUnshadowed : binding ∉ aliases.map Pointers.Alias.name
  startup : pointer ∉ startupLocals literal framing
  argument : argument ≠ pointer

def checkPointerSource? (aliases : List Pointers.Alias) (literal : Grammar.LiteralStage)
    (framing : Framing.Stage) (argument pointer binding : VarId) :
    Option (PointerSource aliases literal framing argument pointer binding) := do
  let alias ← aliases.attach.find? (fun alias => alias.val.name == pointer)
  if valid : alias.val.name = pointer ∧ alias.val.source = .slice binding ∧
      (aliases.map Pointers.Alias.name).Nodup ∧ binding ∉ aliases.map Pointers.Alias.name ∧
      pointer ∉ startupLocals literal framing ∧ argument ≠ pointer then
    pure ⟨alias.val, alias.property, valid.1, valid.2.1, valid.2.2.1,
      valid.2.2.2.1, valid.2.2.2.2.1, valid.2.2.2.2.2⟩
  else none

theorem PointerSource.read {argument : VarId}
    (source : PointerSource aliases literal framing argument pointer binding)
    (storage : BufferStorage binding count original current)
    (frame : Pointers.AliasFrame aliases allocated original)
    (registry : Allocation.Registry original) (readyRegistry : Allocation.Registry ready)
    (retained : Retained literal framing original ready) :
    (ready.bindLocal argument (.signed .i32 1)).local? pointer = some (.pointer storage.view.address) := by
  have originalRead : allocated.local? binding = some
      (.slice (.scalar (.signed .i32)) storage.view.root storage.view.projections 0 storage.view.length) := by
    rw [registry.roots storage.view storage.originalMember, storage.length]
    exact (frame.locals binding source.sliceUnshadowed).symm.trans storage.originalRead
  have pointerRead := frame.sliceAlias source.alias source.member source.names binding source.source
    source.sliceUnshadowed storage.view (frame.views ▸ storage.originalMember) originalRead
  have readyRead := retained.locals pointer source.startup (.pointer storage.view.address)
    (by intro elements same; cases same) (source.name ▸ pointerRead)
  exact (bindLocal_preserves_other_local (value := Value.signed .i32 1)
    readyRegistry.wellFormed source.argument).trans readyRead

end Lanius.Extraction.Entry.Files
