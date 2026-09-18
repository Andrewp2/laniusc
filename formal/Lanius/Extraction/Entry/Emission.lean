import Lanius.Extraction.Entry.Prefix
import Lanius.Extraction.Entry.Framing

namespace Lanius.Extraction.Entry

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation

/-- The output binding must survive grammar initialization, and its buffer
must differ from the grammar destination. This is checked from static IDs. -/
def framingPreserved? (output grammar : Allocation.Buffer) (literal : Grammar.LiteralStage) :
    Option (PLift (output.binding ≠ grammar.binding ∧
      output.binding ≠ literal.setup.text ∧ output.binding ≠ literal.setup.cursor.locals.source ∧
      output.binding ≠ literal.setup.cursor.locals.cursor)) :=
  if valid : output.binding ≠ grammar.binding ∧
      output.binding ≠ literal.setup.text ∧ output.binding ≠ literal.setup.cursor.locals.source ∧
      output.binding ≠ literal.setup.cursor.locals.cursor then some ⟨valid⟩ else none

/-- Compose the checked main entry all the way through its initial Lean
module framing. Both grammar and output storage are derived from the actual
allocations. The remaining execution premise starts at compact-header output. -/
theorem initializeFraming (entry : CheckedArguments program source)
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
    (before : State) (completion : Completion) (post : Lanius.World.State → Prop)
    (wellFormed : StateWellFormed before) (empty : before.i32ArrayViews = [])
    (enough : 1 < before.world.arguments.length) (bounded : before.world.arguments.length < 2 ^ 31)
    (room : ∀ available, before.heap.remaining = some available → Allocation.byteCount sequence.buffers ≤ available)
    (continuationRun : ∀ prefixState, Allocation.Registry prefixState →
      (∃ allocated, Allocation.HostReady sequence.buffers (entry.entry.ready before) allocated ∧
        Pointers.AliasFrame pointers.aliases allocated prefixState) →
      ∀ memory : Grammar.Memory literal.setup.cursor.locals,
      memory.values = data.values → ∀ grammarState, Grammar.Invariant memory memory.values grammarState →
      Allocation.Registry grammarState →
      CellEffect (CellSet.singleton memory.destinationCell) prefixState (restoreLocals prefixState grammarState) →
      (∀ id, id ≠ literal.setup.text → id ≠ literal.setup.cursor.locals.source →
        id ≠ literal.setup.cursor.locals.cursor → grammarState.cellId? id = prefixState.cellId? id) →
      ∀ outputCell untouched, (untouched : List Int).length = outputBuffer.buffer.count →
      ∀ middle positionCell,
      StateWellFormed middle →
      (Assertion.localPointsTo framing.position positionCell (some (.signed .i32 Framing.bytes.length))).holds middle →
      middle.cellEntry? outputCell = some {
        id := outputCell, value := some (.array (signedI32Values (Input.copiedBuffer [] untouched Framing.bytes))) } →
      CellEffect (CellSet.singleton outputCell) grammarState (restoreLocals grammarState middle) →
      (∀ id, id ≠ framing.opening → id ≠ framing.closing → id ≠ framing.position →
        middle.cellId? id = grammarState.cellId? id) →
      Allocation.Registry middle →
      (∃ fresh, middle.i32ArrayViews = prefixState.i32ArrayViews ++ fresh) →
      Prefix.Reaches program before source middle framing.continuation →
      ∃ after, Executes program middle framing.continuation completion after ∧ post after.world) :
    ∃ after, Executes program before source completion after ∧ post after.world := by
  apply initializeGrammar entry allocator sequence allocationSource pointers pointerSource names pointerSupport
    hex sameProgram literal literalSource data literalSupport grammarBuffer.buffer grammarBuffer.member
    grammarBuffer.destination grammarBuffer.notShadowed grammarBuffer.capacity grammarBuffer.fits
    before completion post wellFormed empty enough bounded room
  intro prefixState registry retained memory selected grammarLength grammarState invariant grammarRegistry grammarRead grammarEffect bindings grammarViews grammarReached
  obtain ⟨allocated, history, frame⟩ := retained
  obtain ⟨outputCell, untouched, outputLength, _originalRead, outputRead, originalContents, outputContents⟩ :=
    Pointers.carryAllocatedBuffer history frame registry names outputBuffer.buffer grammarBuffer.buffer
      outputBuffer.member grammarBuffer.member preserved.1 outputBuffer.notShadowed grammarBuffer.notShadowed
      grammarRead grammarEffect (bindings _ preserved.2.1 preserved.2.2.1 preserved.2.2.2)
  have framingRead : grammarState.local? framing.output = some
      (.slice (.scalar (.signed .i32)) outputCell [] 0 untouched.length) := outputBuffer.destination ▸ outputRead
  obtain ⟨after, executed, satisfied⟩ := framing.executes text framingSupport grammarState untouched
    invariant.wellFormed framingRead outputContents (by simpa only [outputLength] using outputBuffer.capacity)
    completion post (fun middle positionCell middleWF owned contents effect framingBindings registered views _freshPosition _suffixRead reached => by
      have combinedViews : ∃ fresh, middle.i32ArrayViews = prefixState.i32ArrayViews ++ fresh := by
        obtain ⟨earlier, earlierViews⟩ := grammarViews
        obtain ⟨later, laterViews⟩ := views
        exact ⟨earlier ++ later, by rw [laterViews, earlierViews, List.append_assoc]⟩
      obtain ⟨after, continued, satisfied⟩ := continuationRun prefixState registry ⟨allocated, history, frame⟩
        memory selected grammarState invariant grammarRegistry grammarEffect bindings outputCell untouched outputLength
        middle positionCell middleWF owned contents effect framingBindings (registered grammarRegistry) combinedViews
        (grammarReached.trans (by simpa only [sameProgram, framingSource] using reached))
      exact ⟨after, sameProgram.symm ▸ continued, satisfied⟩)
  rw [sameProgram] at executed
  exact ⟨after, framingSource.symm ▸ executed, satisfied⟩

end Lanius.Extraction.Entry
