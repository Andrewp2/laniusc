import Lanius.Extraction.Entry.Emission
import Lanius.Extraction.Entry.Framing.Header
import Lanius.Extraction.Entry.Retained

namespace Lanius.Extraction.Entry

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation

def countPreserved? (count : Lanius.VarId) (sequence : Allocation.Sequence)
    (pointers : Pointers.Preparation) (literal : Grammar.LiteralStage) :
    Option (PLift (count ∉ sequence.buffers.map Allocation.Buffer.binding ∧
      count ∉ pointers.aliases.map Pointers.Alias.name ∧ count ≠ literal.setup.text ∧
      count ≠ literal.setup.cursor.locals.source ∧ count ≠ literal.setup.cursor.locals.cursor)) :=
  if valid : count ∉ sequence.buffers.map Allocation.Buffer.binding ∧
      count ∉ pointers.aliases.map Pointers.Alias.name ∧ count ≠ literal.setup.text ∧
      count ≠ literal.setup.cursor.locals.source ∧ count ≠ literal.setup.cursor.locals.cursor then
    some ⟨valid⟩ else none

/-- The checked extractor's complete startup reaches its ordered-file phase
with the exact Lean prefix and compact pack header. Argument count and both
buffers are derived from the actual argc call and allocation sequence. -/
theorem initializeHeader (entry : CheckedArguments program source)
    (allocator : Allocation.CheckedAllocator program) (sequence : Allocation.Sequence)
    (allocationSource : entry.entry.continuation = sequence.statement allocator.function.id)
    (pointers : Pointers.Preparation) (pointerSource : sequence.continuation = pointers.statement)
    (names : (sequence.buffers.map Allocation.Buffer.binding).Nodup)
    (pointerSupport : pointers.Supported (sequence.buffers.map (fun buffer => Pointers.Pointer.slice buffer.binding)))
    (hex : Hex.Checked checkedProgram) (sameProgram : checkedProgram.core = program)
    (literal : Grammar.LiteralStage) (literalSource : pointers.continuation = literal.statement hex.source.function.id)
    (data : Grammar.LiteralEvidence grammar literal.text) (literalSupport : literal.Supported data.values.length)
    (grammarBuffer : BufferSelection sequence.buffers pointers.aliases literal.setup.cursor.locals.destination data.values.length)
    (framing : Framing.Stage) (text : CompactOutput.Text.Checked checkedProgram byte)
    (framingSource : literal.setup.cursor.continuation = framing.statement text.source.function.id)
    (framingSupport : Framing.Supported framing)
    (outputBuffer : BufferSelection sequence.buffers pointers.aliases framing.output framing.capacity)
    (preserved : outputBuffer.buffer.binding ≠ grammarBuffer.buffer.binding ∧
      outputBuffer.buffer.binding ≠ literal.setup.text ∧ outputBuffer.buffer.binding ≠ literal.setup.cursor.locals.source ∧
      outputBuffer.buffer.binding ≠ literal.setup.cursor.locals.cursor)
    (header : Header.Stage) (pack : CompactOutput.PackHeader.Checked checkedProgram byte digit word)
    (headerSource : framing.continuation = header.statement pack.source.function.id)
    (relation : Framing.HeaderRelation framing header) (countIdentity : header.count = entry.entry.count)
    (countPreserved : entry.entry.count ∉ sequence.buffers.map Allocation.Buffer.binding ∧
      entry.entry.count ∉ pointers.aliases.map Pointers.Alias.name ∧ entry.entry.count ≠ literal.setup.text ∧
      entry.entry.count ≠ literal.setup.cursor.locals.source ∧ entry.entry.count ≠ literal.setup.cursor.locals.cursor)
    (headerRoom : Framing.bytes.length + 16 ≤ framing.capacity)
    (before : State) (completion : Completion) (post : Lanius.World.State → Prop)
    (wellFormed : StateWellFormed before) (empty : before.i32ArrayViews = [])
    (enough : 1 < before.world.arguments.length) (bounded : before.world.arguments.length < 2 ^ 31)
    (room : ∀ available, before.heap.remaining = some available → Allocation.byteCount sequence.buffers ≤ available)
    (continuationRun : ∀ prefixState, Allocation.Registry prefixState →
      (∃ allocated, Allocation.HostReady sequence.buffers (entry.entry.ready before) allocated ∧
        Pointers.AliasFrame pointers.aliases allocated prefixState) →
      ∀ memory : Grammar.Memory literal.setup.cursor.locals,
      memory.values = data.values → memory.untouched.length = grammarBuffer.buffer.count →
      ∀ grammarState, Grammar.Invariant memory memory.values grammarState →
      Allocation.Registry grammarState →
      prefixState.local? literal.setup.cursor.locals.destination = some (.slice (.scalar (.signed .i32))
        memory.destinationCell [] 0 memory.untouched.length) →
      CellEffect (CellSet.singleton memory.destinationCell) prefixState (restoreLocals prefixState grammarState) →
      (∀ id, id ≠ literal.setup.text → id ≠ literal.setup.cursor.locals.source →
        id ≠ literal.setup.cursor.locals.cursor → grammarState.cellId? id = prefixState.cellId? id) →
      ∀ outputCell untouched, (untouched : List Int).length = outputBuffer.buffer.count →
      prefixState.local? outputBuffer.buffer.binding = some
        (.slice (.scalar (.signed .i32)) outputCell [] 0 outputBuffer.buffer.count) →
      ∀ framedState positionCell, StateWellFormed framedState →
      CellEffect (CellSet.singleton outputCell) grammarState (restoreLocals grammarState framedState) →
      (∀ id, id ≠ framing.opening → id ≠ framing.closing → id ≠ framing.position →
        framedState.cellId? id = grammarState.cellId? id) →
      Allocation.Registry framedState →
      ∀ middle,
      (Assertion.localPointsTo header.position positionCell (some (.signed .i32 (Framing.bytes.length + 16 : Nat)))).holds middle →
      middle.cellEntry? outputCell = some {
        id := outputCell, value := some (.array (signedI32Values
          (Header.contents (Input.copiedBuffer [] untouched Framing.bytes) Framing.bytes.length
            (before.world.arguments.length - 1)))) } →
      CellEffect (CellSet.union (CellSet.singleton outputCell) (CellSet.singleton positionCell)) framedState middle →
      Allocation.Registry middle →
      middle.cellEntry? memory.destinationCell = some {
        id := memory.destinationCell, value := some (.array (signedI32Values (memory.buffer memory.values))) } →
      CellEffect (CellSet.singleton outputCell) grammarState (restoreLocals grammarState middle) →
      Retained literal framing prefixState middle →
      middle.world = { before.world with
        calls := before.world.calls ++ [.argc] ++ List.replicate sequence.buffers.length .alloc } →
      middle.local? header.count = some (.signed .i32 before.world.arguments.length) →
      middle.cellId? header.count ≠ middle.cellId? header.position →
      middle.local? framing.closing = some (.string framing.suffixText) →
      Prefix.Reaches program before source middle header.continuation →
      ∃ after, Executes program middle header.continuation completion after ∧ post after.world) :
    ∃ after, Executes program before source completion after ∧ post after.world := by
  apply initializeGrammar entry allocator sequence allocationSource pointers pointerSource names pointerSupport
    hex sameProgram literal literalSource data literalSupport grammarBuffer.buffer grammarBuffer.member
    grammarBuffer.destination grammarBuffer.notShadowed grammarBuffer.capacity grammarBuffer.fits
    before completion post wellFormed empty enough bounded room
  intro prefixState registry retained memory selected grammarLength grammarState invariant grammarRegistry grammarRead grammarEffect bindings grammarViews grammarReached
  obtain ⟨allocated, history, frame⟩ := retained
  obtain ⟨outputCell, untouched, outputLength, originalRead, outputRead, originalContents, outputContents⟩ :=
    Pointers.carryAllocatedBuffer history frame registry names outputBuffer.buffer grammarBuffer.buffer
      outputBuffer.member grammarBuffer.member preserved.1 outputBuffer.notShadowed grammarBuffer.notShadowed
      grammarRead grammarEffect (bindings _ preserved.2.1 preserved.2.2.1 preserved.2.2.2)
  have outputGrammar := Pointers.allocatedRootsDistinct history frame names outputBuffer.buffer grammarBuffer.buffer
    outputBuffer.member grammarBuffer.member preserved.1 outputBuffer.notShadowed grammarBuffer.notShadowed
    originalRead grammarRead
  have initialCount := entry.entry.readyCount before wellFormed
  have prefixCount := frame.allocatedLocal history (entry.entry.readyWellFormed before wellFormed)
    (by simpa [Arguments.ready, State.bindLocal, State.bindCell] using empty)
    entry.entry.count countPreserved.1 countPreserved.2.1 initialCount
  have grammarCount := Pointers.preserveNonarray history frame registry names grammarBuffer.buffer grammarBuffer.member
    grammarBuffer.notShadowed grammarRead grammarEffect prefixCount
    (by intro elements same; cases same)
    (bindings _ countPreserved.2.2.1 countPreserved.2.2.2.1 countPreserved.2.2.2.2)
  have countRead : grammarState.local? header.count =
      some (.signed .i32 (before.world.arguments.length - 1 + 1 : Nat)) := by
    simpa only [countIdentity, Nat.sub_add_cancel (show 1 ≤ before.world.arguments.length by omega)] using grammarCount
  have framingRead : grammarState.local? framing.output = some
      (.slice (.scalar (.signed .i32)) outputCell [] 0 untouched.length) := outputBuffer.destination ▸ outputRead
  obtain ⟨after, executed, satisfied⟩ := framing.withHeader text framingSupport header pack headerSource relation
    grammarState untouched (before.world.arguments.length - 1) invariant.wellFormed framingRead outputContents
    countRead (by omega) (by simpa only [outputLength] using outputBuffer.capacity) headerRoom completion post
    (fun framedState positionCell framedWF framingEffect framingBindings registered middle owned contents headerEffect headerRegistry
        views fullFramingEffect fullFramingBindings finalCount countApart suffixRead reached => by
      have combinedViews : ∃ fresh, middle.i32ArrayViews = prefixState.i32ArrayViews ++ fresh := by
        obtain ⟨earlier, earlierViews⟩ := grammarViews
        obtain ⟨later, laterViews⟩ := views
        exact ⟨earlier ++ later, by rw [laterViews, earlierViews, List.append_assoc]⟩
      have retained : Retained literal framing prefixState middle := by
        refine ⟨?_, ?_, ?_⟩
        · intro view member
          obtain ⟨fresh, same⟩ := combinedViews
          rw [same]
          exact List.mem_append_left _ member
        · intro id unshadowed
          have distinct : id ≠ literal.setup.text ∧ id ≠ literal.setup.cursor.locals.source ∧
              id ≠ literal.setup.cursor.locals.cursor ∧ id ≠ framing.opening ∧ id ≠ framing.closing ∧
              id ≠ framing.position := by simpa only [startupLocals, List.mem_cons, List.not_mem_nil,
                or_false, not_or] using unshadowed
          exact (fullFramingBindings _ distinct.2.2.2.1 distinct.2.2.2.2.1 distinct.2.2.2.2.2).trans
            (bindings _ distinct.1 distinct.2.1 distinct.2.2.1)
        · intro id unshadowed value notArray read
          have distinct : id ≠ literal.setup.text ∧ id ≠ literal.setup.cursor.locals.source ∧
              id ≠ literal.setup.cursor.locals.cursor ∧ id ≠ framing.opening ∧ id ≠ framing.closing ∧
              id ≠ framing.position := by simpa only [startupLocals, List.mem_cons, List.not_mem_nil,
                or_false, not_or] using unshadowed
          have afterGrammar := Pointers.preserveNonarray history frame registry names grammarBuffer.buffer
            grammarBuffer.member grammarBuffer.notShadowed grammarRead grammarEffect read notArray
            (bindings _ distinct.1 distinct.2.1 distinct.2.2.1)
          exact Pointers.preservedLiveLocal fullFramingEffect invariant.wellFormed afterGrammar
            (fun cell found => local_cell_ne_of_distinct_value afterGrammar outputContents (notArray _) found)
            (fullFramingBindings _ distinct.2.2.2.1 distinct.2.2.2.2.1 distinct.2.2.2.2.2)
      obtain ⟨after, continued, satisfied⟩ := continuationRun prefixState registry ⟨allocated, history, frame⟩
        memory selected grammarLength grammarState invariant grammarRegistry
        (by simpa only [grammarBuffer.destination, grammarLength] using grammarRead)
        grammarEffect bindings outputCell untouched outputLength
        (by simpa only [outputLength] using originalRead)
        framedState positionCell framedWF framingEffect framingBindings (registered grammarRegistry) middle owned contents headerEffect
        (headerRegistry (registered grammarRegistry))
        (fullFramingEffect.preserves_entry invariant.wellFormed invariant.destinationContents outputGrammar.symm)
        fullFramingEffect retained
        (by rw [show middle.world = grammarState.world from fullFramingEffect.world,
              show grammarState.world = prefixState.world from grammarEffect.world,
              frame.world, history.world]
            rfl)
        (by simpa only [Nat.sub_add_cancel (show 1 ≤ before.world.arguments.length by omega)] using finalCount) countApart suffixRead
        (grammarReached.trans (by simpa only [sameProgram, framingSource] using reached))
      exact ⟨after, sameProgram.symm ▸ continued, satisfied⟩)
  rw [sameProgram] at executed
  exact ⟨after, framingSource.symm ▸ executed, satisfied⟩

end Lanius.Extraction.Entry
