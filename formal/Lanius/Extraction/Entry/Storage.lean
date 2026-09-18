import Lanius.Extraction.Entry.Aliases
import Lanius.Extraction.Allocation.Storage
import Lanius.Extraction.Allocation.Distinct
import Lanius.Separation.SliceStore

namespace Lanius.Extraction.Entry.Pointers

open Lanius.Core Lanius.Semantics

theorem allocatedBuffer (history : Allocation.HostReady buffers before allocated)
    (retained : AliasFrame aliases allocated after) (registry : Allocation.Registry after)
    (names : (buffers.map Allocation.Buffer.binding).Nodup) (buffer : Allocation.Buffer)
    (member : buffer ∈ buffers) (notShadowed : buffer.binding ∉ aliases.map Alias.name) :
    ∃ cell values, (values : List Int).length = buffer.count ∧
      after.local? buffer.binding = some (.slice (.scalar (.signed .i32)) cell [] 0 values.length) ∧
      after.cellEntry? cell = some {
        id := cell, value := some (.array (signedI32Values values)) } := by
  obtain ⟨view, present, length, read⟩ := history.buffer names member
  have presentAfter : view ∈ after.i32ArrayViews := retained.views.symm ▸ present
  obtain ⟨values, size, contents⟩ := registry.storage presentAfter
  refine ⟨view.root, values, size.trans length, ?_, contents⟩
  rw [retained.locals buffer.binding notShadowed, size]
  simpa only [registry.roots view presentAfter] using read

theorem preservedLiveLocal (effect : Lanius.Separation.CellEffect writes before (restoreLocals before after))
    (wellFormed : Lanius.Properties.StateWellFormed before)
    (read : before.local? binding = some value)
    (untouched : ∀ cell, before.cellId? binding = some cell → ¬ writes cell)
    (sameBinding : after.cellId? binding = before.cellId? binding) :
    after.local? binding = some value := by
  have preserved := effect.preserves_local wellFormed read untouched
  change (after.cellId? binding).bind after.cell? = some value
  rw [sameBinding]
  exact preserved

theorem allocatedRootsDistinct (history : Allocation.HostReady buffers before allocated)
    (retained : AliasFrame aliases allocated ready)
    (names : (buffers.map Allocation.Buffer.binding).Nodup) (left right : Allocation.Buffer)
    (leftMember : left ∈ buffers) (rightMember : right ∈ buffers)
    (different : left.binding ≠ right.binding)
    (leftUnshadowed : left.binding ∉ aliases.map Alias.name)
    (rightUnshadowed : right.binding ∉ aliases.map Alias.name)
    (leftRead : ready.local? left.binding = some (.slice (.scalar (.signed .i32)) leftRoot [] 0 leftLength))
    (rightRead : ready.local? right.binding = some (.slice (.scalar (.signed .i32)) rightRoot [] 0 rightLength)) :
    leftRoot ≠ rightRoot := by
  rw [retained.locals left.binding leftUnshadowed] at leftRead
  rw [retained.locals right.binding rightUnshadowed] at rightRead
  exact history.rootsDistinct names left right leftMember rightMember different leftRead rightRead

theorem preservedBuffer (effect : Lanius.Separation.CellEffect
      (Lanius.Separation.CellSet.singleton written) before (restoreLocals before after))
    (wellFormed : Lanius.Properties.StateWellFormed before)
    (values : List Int) (read : before.local? binding =
      some (.slice (.scalar (.signed .i32)) cell [] 0 values.length))
    (contents : before.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values values)) })
    (writtenContents : before.cellEntry? written = some { id := written, value := some (.array writtenValues) })
    (separate : cell ≠ written) (sameBinding : after.cellId? binding = before.cellId? binding) :
    after.local? binding = some (.slice (.scalar (.signed .i32)) cell [] 0 values.length) ∧
      after.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values values)) } := by
  refine ⟨preservedLiveLocal effect wellFormed read ?_ sameBinding,
    effect.preserves_entry wellFormed contents separate⟩
  intro localCell found
  exact Lanius.Separation.local_cell_ne_of_distinct_value read writtenContents
    (by intro same; cases same) found

theorem carryAllocatedBuffer (history : Allocation.HostReady buffers initial allocated)
    (retained : AliasFrame aliases allocated before) (registry : Allocation.Registry before)
    (names : (buffers.map Allocation.Buffer.binding).Nodup)
    (buffer changed : Allocation.Buffer) (member : buffer ∈ buffers) (changedMember : changed ∈ buffers)
    (different : buffer.binding ≠ changed.binding)
    (notShadowed : buffer.binding ∉ aliases.map Alias.name)
    (changedNotShadowed : changed.binding ∉ aliases.map Alias.name)
    (changedRead : before.local? changed.binding = some (.slice (.scalar (.signed .i32)) written [] 0 changed.count))
    (effect : Lanius.Separation.CellEffect (Lanius.Separation.CellSet.singleton written)
      before (restoreLocals before after))
    (sameBinding : after.cellId? buffer.binding = before.cellId? buffer.binding) :
    ∃ cell values, (values : List Int).length = buffer.count ∧
      before.local? buffer.binding = some (.slice (.scalar (.signed .i32)) cell [] 0 values.length) ∧
      after.local? buffer.binding = some (.slice (.scalar (.signed .i32)) cell [] 0 values.length) ∧
      before.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values values)) } ∧
      after.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values values)) } := by
  obtain ⟨cell, values, length, read, contents⟩ := allocatedBuffer history retained registry names buffer member notShadowed
  obtain ⟨changedCell, changedValues, changedLength, originalChangedRead, changedContents⟩ :=
    allocatedBuffer history retained registry names changed changedMember changedNotShadowed
  rw [changedLength] at originalChangedRead
  rw [originalChangedRead] at changedRead
  cases changedRead
  have separate := allocatedRootsDistinct history retained names buffer changed member changedMember different
    notShadowed changedNotShadowed read originalChangedRead
  obtain ⟨afterRead, afterContents⟩ := preservedBuffer effect registry.wellFormed values read contents changedContents separate sameBinding
  exact ⟨cell, values, length, read, afterRead, contents, afterContents⟩

/-- A non-array local cannot alias an allocated array's backing cell. Recover
that array from the registry to preserve pointers, slices, and scalars across
the scoped write. -/
theorem preserveNonarray {id : Lanius.VarId} (history : Allocation.HostReady buffers initial allocated)
    (retained : AliasFrame aliases allocated before) (registry : Allocation.Registry before)
    (names : (buffers.map Allocation.Buffer.binding).Nodup)
    (buffer : Allocation.Buffer) (member : buffer ∈ buffers)
    (notShadowed : buffer.binding ∉ aliases.map Alias.name)
    (bufferRead : before.local? buffer.binding = some (.slice (.scalar (.signed .i32)) written [] 0 buffer.count))
    (effect : Lanius.Separation.CellEffect (Lanius.Separation.CellSet.singleton written)
      before (restoreLocals before after))
    (read : before.local? id = some value) (notArray : ∀ elements, value ≠ .array elements)
    (sameBinding : after.cellId? id = before.cellId? id) :
    after.local? id = some value := by
  obtain ⟨cell, values, length, sliceRead, contents⟩ :=
    allocatedBuffer history retained registry names buffer member notShadowed
  rw [length] at sliceRead
  have root : cell = written := by
    have same := sliceRead.symm.trans bufferRead
    injection same with same
    injection same
  subst cell
  exact preservedLiveLocal effect registry.wellFormed read
    (fun cell found => Lanius.Separation.local_cell_ne_of_distinct_value read contents
      (notArray _) found) sameBinding

/-- Recover the current contents and the original registered view of an
allocated slice after later phases. The contents need not still be zero:
the grammar and output buffers have already been initialized. -/
theorem retainedBuffer (history : Allocation.HostReady buffers initial allocated)
    (retained : AliasFrame aliases allocated before) (registry : Allocation.Registry before)
    (finalRegistry : Allocation.Registry after)
    (names : (buffers.map Allocation.Buffer.binding).Nodup) (buffer : Allocation.Buffer)
    (member : buffer ∈ buffers) (notShadowed : buffer.binding ∉ aliases.map Alias.name)
    (views : ∀ view ∈ before.i32ArrayViews, view ∈ after.i32ArrayViews)
    (kept : ∀ value, (∀ elements, value ≠ .array elements) →
      before.local? buffer.binding = some value → after.local? buffer.binding = some value) :
    ∃ view values, view ∈ before.i32ArrayViews ∧ view ∈ after.i32ArrayViews ∧
      view.length = buffer.count ∧ (values : List Int).length = buffer.count ∧
      before.local? buffer.binding = some (.slice (.scalar (.signed .i32)) view.root [] 0 buffer.count) ∧
      after.local? buffer.binding = some (.slice (.scalar (.signed .i32)) view.root [] 0 values.length) ∧
      after.cellEntry? view.root = some { id := view.root, value := some (.array (signedI32Values values)) } := by
  obtain ⟨view, present, length, read⟩ := history.buffer names member
  have original : view ∈ before.i32ArrayViews := retained.views.symm ▸ present
  have current := views view original
  obtain ⟨values, size, contents⟩ := finalRegistry.storage current
  have originalRead : before.local? buffer.binding = some
      (.slice (.scalar (.signed .i32)) view.root [] 0 buffer.count) := by
    rw [retained.locals buffer.binding notShadowed]
    simpa only [registry.roots view original, length] using read
  refine ⟨view, values, original, current, length, size.trans length, originalRead, ?_, contents⟩
  simpa only [size, length] using kept _ (by intro elements same; cases same) originalRead

end Lanius.Extraction.Entry.Pointers
