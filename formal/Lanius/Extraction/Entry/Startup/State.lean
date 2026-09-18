import Lanius.Extraction.Entry.Startup

namespace Lanius.Extraction.Entry.Startup
open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation

/-- The actual state reached by complete startup, independent of how the
remaining main eventually returns. Storage and provenance come from executed
allocations, not from a separately supplied file-loop invariant. -/
structure Ready (entry : CheckedArguments program source) (sequence : Allocation.Sequence)
    (pointers : Pointers.Preparation) (literal : Grammar.LiteralStage)
    (data : Grammar.LiteralEvidence Grammar.indexedLanius literal.text)
    (framing : Framing.Stage) (header : Header.Stage) (before : State) where
  enough : 1 < before.world.arguments.length
  bounded : before.world.arguments.length < 2 ^ 31
  allocated : State
  original : State
  state : State
  history : Allocation.HostReady sequence.buffers (entry.entry.ready before) allocated
  frame : Pointers.AliasFrame pointers.aliases allocated original
  originalRegistry : Allocation.Registry original
  registry : Allocation.Registry state
  retained : Retained literal framing original state
  memory : Grammar.Memory literal.setup.cursor.locals
  selected : memory.values = data.values
  originalGrammar : original.local? literal.setup.cursor.locals.destination = some
    (.slice (.scalar (.signed .i32)) memory.destinationCell [] 0 memory.untouched.length)
  grammarStored : state.cellEntry? memory.destinationCell = some {
    id := memory.destinationCell, value := some (.array (signedI32Values (memory.buffer memory.values))) }
  outputCell : CellId
  positionCell : CellId
  untouched : List Int
  outputCapacity : framing.capacity ≤ untouched.length
  originalOutput : original.local? framing.output = some
    (.slice (.scalar (.signed .i32)) outputCell [] 0 untouched.length)
  outputStored : state.cellEntry? outputCell = some {
    id := outputCell, value := some (.array (signedI32Values
      (Header.contents (Input.copiedBuffer [] untouched Framing.bytes) Framing.bytes.length
        (before.world.arguments.length - 1)))) }
  position : (Assertion.localPointsTo header.position positionCell
    (some (.signed .i32 (Framing.bytes.length + 16 : Nat)))).holds state
  world : state.world = { before.world with
    calls := before.world.calls ++ [.argc] ++ List.replicate sequence.buffers.length .alloc }
  countRead : state.local? header.count = some (.signed .i32 before.world.arguments.length)
  countApart : state.cellId? header.count ≠ state.cellId? header.position
  suffixRead : state.local? framing.closing = some (.string framing.suffixText)
  reached : Prefix.Reaches program before source state header.continuation

/-- Extract startup's reached state from its continuation theorem. The
continuation is used only to retain the already-established prefix; no
execution of the file phase or successful final return is assumed. -/
theorem reaches (entry : CheckedArguments checkedProgram.core source)
    (allocator : Allocation.CheckedAllocator checkedProgram.core) (sequence : Allocation.Sequence)
    (allocationSource : entry.entry.continuation = sequence.statement allocator.function.id)
    (pointers : Pointers.Preparation) (pointerSource : sequence.continuation = pointers.statement)
    (names : (sequence.buffers.map Allocation.Buffer.binding).Nodup)
    (pointerSupport : pointers.Supported (sequence.buffers.map (fun buffer => Pointers.Pointer.slice buffer.binding)))
    (hex : Hex.Checked checkedProgram)
    (literal : Grammar.LiteralStage) (literalSource : pointers.continuation = literal.statement hex.source.function.id)
    (data : Grammar.LiteralEvidence Grammar.indexedLanius literal.text) (literalSupport : literal.Supported data.values.length)
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
    (before : State) (wellFormed : StateWellFormed before) (empty : before.i32ArrayViews = [])
    (enough : 1 < before.world.arguments.length) (bounded : before.world.arguments.length < 2 ^ 31)
    (room : ∀ available, before.heap.remaining = some available → Allocation.byteCount sequence.buffers ≤ available) :
    Nonempty (Ready entry sequence pointers literal data framing header before) := by
  classical
  by_cases found : Nonempty (Ready entry sequence pointers literal data framing header before)
  · exact found
  · -- If startup had no reached state, its continuation would be impossible.
    -- The existing execution theorem then gives a false postcondition.
    obtain ⟨_, _, impossible⟩ := initializeHeader entry allocator sequence allocationSource pointers pointerSource
      names pointerSupport hex rfl literal literalSource data literalSupport grammarBuffer framing text framingSource
      framingSupport outputBuffer preserved header pack headerSource relation countIdentity countPreserved headerRoom
      before .next (fun _ => False) wellFormed empty enough bounded room (by
        intro original originalRegistry allocation memory selected _grammarLength _grammarState _grammarInvariant
          _grammarRegistry originalGrammar _grammarEffect _grammarBindings outputCell untouched outputLength
          originalOutput _framedState positionCell _framedWF _framingEffect _framingBindings _framedRegistry
          state position outputStored _headerEffect registry grammarStored _fullEffect retained world countRead countApart suffixRead reached
        obtain ⟨allocated, history, frame⟩ := allocation
        exact False.elim (found ⟨{
          enough, bounded, allocated, original, state, history, frame, originalRegistry, registry, retained, memory, selected,
          originalGrammar, grammarStored, outputCell, positionCell, untouched,
          outputCapacity := by simpa only [outputLength] using outputBuffer.capacity,
          originalOutput := by simpa only [outputBuffer.destination, outputLength] using originalOutput,
          outputStored, position, world, countRead, countApart, suffixRead, reached }⟩))
    exact False.elim impossible

end Lanius.Extraction.Entry.Startup
