import Lanius.Extraction.Entry.Storage
import Lanius.Extraction.Entry.GrammarLiteral

namespace Lanius.Extraction.Entry

open Lanius.Core Lanius.Semantics Lanius.Properties

structure BufferSelection (buffers : List Allocation.Buffer) (aliases : List Pointers.Alias)
    (destination : Lanius.VarId) (count : Nat) where
  buffer : Allocation.Buffer
  member : buffer ∈ buffers
  destination : destination = buffer.binding
  notShadowed : buffer.binding ∉ aliases.map Pointers.Alias.name
  capacity : count ≤ buffer.count
  fits : buffer.count ≤ 2147483647

def checkBuffer? (buffers : List Allocation.Buffer) (aliases : List Pointers.Alias)
    (destination : Lanius.VarId) (count : Nat) : Option (BufferSelection buffers aliases destination count) := do
  let selected ← buffers.attach.find? (fun buffer => buffer.val.binding == destination)
  if evidence : destination = selected.val.binding ∧ selected.val.binding ∉ aliases.map Pointers.Alias.name ∧
      count ≤ selected.val.count ∧ selected.val.count ≤ 2147483647 then
    pure ⟨selected.val, selected.property, evidence.1, evidence.2.1, evidence.2.2.1, evidence.2.2.2⟩
  else none

/-- Execute the checked main prefix through grammar initialization. Runtime
grammar-buffer premises are obtained from allocations, not supplied by the
caller. The remaining execution premise starts after grammar initialization. -/
theorem initializeGrammar (entry : CheckedArguments program source)
    (allocator : Allocation.CheckedAllocator program) (sequence : Allocation.Sequence)
    (allocationSource : entry.entry.continuation = sequence.statement allocator.function.id)
    (pointers : Pointers.Preparation) (pointerSource : sequence.continuation = pointers.statement)
    (names : (sequence.buffers.map Allocation.Buffer.binding).Nodup)
    (pointerSupport : pointers.Supported (sequence.buffers.map (fun buffer => Pointers.Pointer.slice buffer.binding)))
    (hex : Hex.Checked checkedProgram)
    (sameProgram : checkedProgram.core = program)
    (literal : Grammar.LiteralStage) (literalSource : pointers.continuation = literal.statement hex.source.function.id)
    (data : Grammar.LiteralEvidence grammar literal.text) (literalSupport : literal.Supported data.values.length)
    (buffer : Allocation.Buffer) (member : buffer ∈ sequence.buffers)
    (destination : literal.setup.cursor.locals.destination = buffer.binding)
    (notShadowed : buffer.binding ∉ pointers.aliases.map Pointers.Alias.name)
    (capacity : data.values.length ≤ buffer.count) (fits : buffer.count ≤ 2147483647)
    (before : State) (completion : Completion) (post : Lanius.World.State → Prop)
    (wellFormed : StateWellFormed before) (empty : before.i32ArrayViews = [])
    (enough : 1 < before.world.arguments.length) (bounded : before.world.arguments.length < 2 ^ 31)
    (room : ∀ available, before.heap.remaining = some available → Allocation.byteCount sequence.buffers ≤ available)
    (continuationRun : ∀ prefixState, Allocation.Registry prefixState →
      (∃ allocated, Allocation.HostReady sequence.buffers (entry.entry.ready before) allocated ∧
        Pointers.AliasFrame pointers.aliases allocated prefixState) →
      ∀ memory : Grammar.Memory literal.setup.cursor.locals,
      memory.values = data.values → memory.untouched.length = buffer.count →
      ∀ middle, Grammar.Invariant memory memory.values middle →
      Allocation.Registry middle →
      prefixState.local? buffer.binding = some (.slice (.scalar (.signed .i32))
        memory.destinationCell [] 0 buffer.count) →
      Lanius.Separation.CellEffect (Lanius.Separation.CellSet.singleton memory.destinationCell)
        prefixState (restoreLocals prefixState middle) →
      (∀ id, id ≠ literal.setup.text → id ≠ literal.setup.cursor.locals.source →
        id ≠ literal.setup.cursor.locals.cursor → middle.cellId? id = prefixState.cellId? id) →
      (∃ fresh, middle.i32ArrayViews = prefixState.i32ArrayViews ++ fresh) →
      Prefix.Reaches program before source middle literal.setup.cursor.continuation →
      ∃ after, Executes program middle literal.setup.cursor.continuation completion after ∧ post after.world) :
    ∃ after, Executes program before source completion after ∧ post after.world := by
  apply Pointers.executeEntry entry allocator sequence allocationSource pointers pointerSource names
    pointerSupport before completion post wellFormed empty enough bounded room
  intro ready registry available retained entryReached
  obtain ⟨allocated, history, frame⟩ := retained
  obtain ⟨cell, values, length, localRead, contents⟩ :=
    Pointers.allocatedBuffer history frame registry names buffer member notShadowed
  have destinationRead : ready.local? literal.setup.cursor.locals.destination =
      some (.slice (.scalar (.signed .i32)) cell [] 0 values.length) := destination ▸ localRead
  obtain ⟨after, executed, satisfied⟩ := literal.executes hex data ready values cell completion post
    registry.wellFormed destinationRead contents (by omega) (by omega) literalSupport
    (fun memory selected untouched target middle invariant world effect bindings registered views reached => by
      obtain ⟨after, continued, satisfied⟩ := continuationRun ready registry ⟨allocated, history, frame⟩ memory selected
        (by simpa [untouched] using length) middle invariant (registered registry)
        (by simpa only [target, length] using localRead) (target.symm ▸ effect) bindings views
        (entryReached.trans (by simpa only [sameProgram, literalSource] using reached))
      exact ⟨after, sameProgram.symm ▸ continued, satisfied⟩)
  rw [sameProgram] at executed
  exact ⟨after, literalSource.symm ▸ executed, satisfied⟩

end Lanius.Extraction.Entry
