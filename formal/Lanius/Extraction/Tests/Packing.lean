import Lanius.Extraction.OutputPacking.Clear
import Lanius.Extraction.OutputPacking.Preparation
import Lanius.Extraction.OutputPacking.Entry
import Lanius.Extraction.OutputPacking.Pipeline
import Lanius.Extraction.OutputPacking.Setup
import Lanius.Extraction.OutputPacking.Stdout
import Lanius.Extraction.OutputPacking.Complete
import Lanius.Extraction.ExtractorContract
import Lanius.Memory.Access
import Lanius.Semantics.I32Views.Allocation
import Lanius.Extraction.Allocation.Execution
import Lanius.Extraction.Allocation.Source
import Lanius.Extraction.Allocation.Host
import Lanius.Extraction.Allocation.Registry
import Lanius.Extraction.Allocation.Sequence
import Lanius.Extraction.Entry.Arguments
import Lanius.Extraction.Entry.Aliases
import Lanius.Extraction.Entry.Hex
import Lanius.Extraction.Entry.Word
import Lanius.Extraction.Entry.Decode
import Lanius.Extraction.Entry.Grammar
import Lanius.Extraction.Entry.GrammarLoop
import Lanius.Extraction.Entry.GrammarString
import Lanius.Extraction.Entry.GrammarCursor
import Lanius.Extraction.Entry.GrammarSetup
import Lanius.Extraction.Entry.GrammarLiteral
import Lanius.Extraction.Entry.Storage
import Lanius.Extraction.Entry.Prefix
import Lanius.Extraction.CompactOutput.Text.Call
import Lanius.Extraction.Entry.Framing
import Lanius.Extraction.Entry.Emission
import Lanius.Extraction.Entry.Header
import Lanius.Extraction.Entry.Startup
import Lanius.Extraction.Allocation.Borrowed
import Lean.Util.CollectAxioms

open Lanius.Core Lanius.Semantics Lanius.Extraction Lanius.Extraction.OutputPacking

#eval show IO Unit from do
  let stage : Entry.Framing.Stage := ⟨30, 31, 12, 23,
    ExtractorContract.modulePrefix ++ "\x00\x00",
    ExtractorContract.moduleSuffix ++ "\x00\x00\x00", 16777216, .skip⟩
  unless stage.checkSupported?.isSome && (Entry.Framing.check? 42 (stage.statement 42)).isSome do
    throw (IO.userError "supported exact framing rejected")
  if (Entry.Framing.check? 43 (stage.statement 42)).isSome then
    throw (IO.userError "framing with a different text helper accepted")
  for invalid in [
      { stage with prefixText := ExtractorContract.modulePrefix },
      { stage with suffixText := ExtractorContract.moduleSuffix },
      { stage with capacity := 145 },
      { stage with closing := stage.opening },
      { stage with opening := stage.output }] do
    if invalid.checkSupported?.isSome then
      throw (IO.userError "unsafe framing storage, capacity, or shadowing accepted")
  let header : Entry.Header.Stage := ⟨0, 12, 23, 16777216, .skip⟩
  unless (Entry.Header.check? 42 (header.statement 42)).isSome do
    throw (IO.userError "exact compact-header call and guard rejected")
  if (Entry.Header.check? 43 (header.statement 42)).isSome then
    throw (IO.userError "compact header calling a different function accepted")

#eval show IO Unit from do
  let loop := (⟨1, 2, 3, 4, 2179⟩ : Entry.Grammar.Locals).loop 7
  unless (Entry.Grammar.checkLoop? 7 loop).isSome do
    throw (IO.userError "exact grammar loop rejected")
  -- A different helper cannot inherit the checked decoder proof.
  if (Entry.Grammar.checkLoop? 8 loop).isSome then
    throw (IO.userError "grammar loop with wrong decoder accepted")

-- Aliases may feed later aliases; shadowing a slice cannot leave it available.
example : (Entry.Pointers.Preparation.checkSupported?
    ⟨[⟨2, .slice 1⟩, ⟨3, .localValue 2⟩], .skip⟩
    [.slice 1]).isSome = true := by decide

example : (Entry.Pointers.Preparation.checkSupported?
    ⟨[⟨1, .slice 1⟩, ⟨2, .slice 1⟩], .skip⟩
    [.slice 1]).isSome = false := by decide

example : (Entry.Pointers.Preparation.checkSupported?
    ⟨[⟨2, .slice 9⟩], .skip⟩
    [.slice 1]).isSome = false := by decide

run_elab do
  for name in #[``CompactOutput.Text.readValue, ``CompactOutput.Text.appendValue,
      ``CompactOutput.Text.stepSuccess, ``CompactOutput.Text.advance,
      ``CompactOutput.Text.executesLoop, ``CompactOutput.Text.executes,
      ``CompactOutput.Text.preservesRegistry,
      ``CompactOutput.Text.rejectsLength, ``CompactOutput.Text.Checked.append,
      ``Entry.Framing.bytes_length, ``Entry.Framing.Stage.executes,
      ``Entry.Framing.Stage.checkSupported?, ``Entry.Framing.check?,
      ``Entry.initializeFraming, ``Entry.framingPreserved?, ``Entry.checkBuffer?,
      ``Entry.Header.encoding_length, ``Entry.Header.contents_length, ``Entry.Header.Stage.executes, ``Entry.Header.check?,
      ``Entry.Framing.Stage.withHeader, ``Entry.Framing.checkHeaderRelation?,
      ``Entry.Arguments.readyWellFormed, ``Entry.Arguments.readyCount,
      ``Entry.Pointers.preserveNonarray, ``Entry.Pointers.retainedBuffer,
      ``Entry.initializeHeader, ``Entry.countPreserved?,
      ``Allocation.Registry.borrowed,
      ``Allocation.Registry.bindLocals, ``Allocation.Registry.enterCall, ``Allocation.Registry.restoreLocals,
      ``Allocation.Registry.transport, ``Allocation.Registry.updateArrayAndScalar,
      ``Allocation.Registry.unchanged, ``Allocation.Registry.arrayLength, ``Allocation.Registry.notScalar,
      ``Entry.Grammar.preservesRegistry, ``Lanius.Separation.CellEffect.modifiesOnly,
      ``output_word_bounds, ``evaluates_output_words, ``clear_cursor_entry,
      ``packing_cursor_entry, ``cleared_packing_entry, ``clear_then_pack,
      ``clear_cursor_frame, ``clear_cursor_input, ``clear_setup_then_pack, ``prepare_buffers,
      ``Lanius.Extraction.ExtractorContract.evaluates_workspace_stdout,
      ``Lanius.Memory.Heap.containingBlock_exists, ``Lanius.Memory.Heap.loadByte_exists,
      ``Lanius.Memory.loadBytesFrom_exists, ``Lanius.Memory.Heap.loadBytes_exists,
      ``Lanius.Memory.Heap.storeByte_exists, ``Lanius.Memory.storeBytesFrom_view_exists,
      ``Lanius.Memory.Heap.storeBytes_view_exists,
      ``encodeI32Array_exists, ``syncI32ViewsToHeapFrom_exists, ``syncI32ViewsToHeap_exists,
      ``Lanius.Memory.loadBytesFrom_length, ``Lanius.Memory.Heap.loadBytes_length,
      ``decodeI32Array_exists, ``loadI32View_exists, ``syncI32RootViewsFromHeapFrom_exists,
      ``syncI32ViewsToHeapFrom_preserves_storage,
      ``Lanius.Extraction.ExtractorContract.workspace_stdout_exists, ``packing_then_continue,
      ``clear_then_continue, ``clear_setup_then_continue, ``prepare_with_continuation,
      ``stdout_from_completed_packing, ``syncI32RootViewsFromHeapFrom_preserves_other_cell,
      ``syncI32RootViewsFromHeapFrom_preserves_locals,
      ``i32Result_byte_count, ``stdout_check_returns_zero,
      ``evaluates_output_size, ``output_size_scope, ``stdout_tail_returns_zero,
      ``stdout_arguments, ``StdoutTail.executes, ``LoopInvariant.workspace_view,
      ``preserved_projection, ``LoopInvariant.registered_arrays, ``preparation_effect,
      ``preparation_local_binding, ``preserved_local, ``prepare_and_write,
      ``Preparation.checked_stdout_statement, ``mapRawI32Slice_exists, ``decodeI32Array_shape,
      ``Lanius.Memory.Heap.allocated_block, ``mapAllocatedI32Slice_exists,
      ``Lanius.Memory.Heap.allocate_exists, ``allocateI32Slice_exists,
      ``Lanius.Memory.Heap.allocate_remaining, ``Lanius.Memory.Heap.allocate_leaves_room,
      ``evaluatesAlloc, ``evaluatesAllocatedI32Slice, ``evaluatesAllocatedI32Slice_resources,
      ``Lanius.Extraction.Allocation.executes, ``Allocation.Ready.wellFormed,
      ``Allocation.Ready.world, ``Allocation.Ready.validViews, ``Allocation.Ready.remaining,
      ``Lanius.CallContracts.evaluatesHostAllocation,
      ``Lanius.Memory.Heap.storeByte_remaining, ``Lanius.Memory.storeBytesFrom_remaining,
      ``syncI32ViewsToHeapFrom_remaining, ``Allocation.hostAllocation_exists,
      ``syncI32ViewsToHeapFrom_nextCell, ``syncI32RootViewsFromHeapFrom_preserves_structure,
      ``Allocation.Step.initializes, ``Allocation.Step.rejectsExhaustion, ``syncI32RootViewsFromHeapFrom_arrays,
      ``Allocation.Registry.root_lt_next, ``Allocation.Registry.allocateRaw, ``Allocation.Registry.allocationExhausted, ``Allocation.Registry.mapRaw, ``Allocation.Registry.bindLocal,
      ``Allocation.hostSequence_executes, ``Allocation.CheckedAllocator.executes,
      ``Allocation.Registry.of_empty_views, ``Allocation.HostReady.remaining,
      ``Allocation.HostReady.world, ``Allocation.HostReady.nextCell,
      ``Entry.evaluatesArgc, ``Entry.Arguments.executes, ``Entry.CheckedArguments.executes,
      ``Entry.CheckedArguments.allocate, ``evaluatesI32SliceDataPtr,
      ``Allocation.Registry.synchronize, ``Allocation.Registry.findView, ``Allocation.Registry.pointer,
      ``Allocation.Registry.nonnull, ``Allocation.Registry.evaluatesPointer,
      ``Allocation.HostReady.preserves_cell, ``Allocation.HostReady.preserves_binding,
      ``Allocation.HostReady.preserves_local, ``Allocation.HostReady.preserves_view,
      ``Allocation.HostReady.head_read, ``Allocation.HostReady.buffer, ``Allocation.HostReady.pointer,
      ``Entry.Pointers.Frame.localRead, ``Entry.Pointers.Pointer.evaluates,
      ``Entry.Pointers.Pointer.Ready.bindOther, ``Entry.Pointers.Binding.executes,
      ``Entry.Pointers.aliasesExecute, ``Entry.Pointers.Preparation.executes,
      ``Entry.Pointers.availableOfAllocations,
      ``Entry.Pointers.executeEntry,
      ``Entry.Pointers.AliasFrame.allocatedLocal,
      ``Entry.Hex.executes, ``Entry.Hex.Checked.decode,
      ``Entry.Hex.evaluatesWord,
      ``Entry.Hex.Checked.decodeLane, ``Entry.Hex.Checked.decodeWord,
      ``Entry.Hex.Checked.decodePackedWord, ``Entry.Hex.Checked.decodeValue,
      ``Entry.Hex.Checked.storeValue,
      ``Entry.Grammar.bodyStep, ``Entry.Grammar.step, ``Entry.Grammar.executesLoop,
      ``Entry.Grammar.loopSound,
      ``Entry.Grammar.stringInitializer,
      ``Entry.Grammar.cursorInvariant,
      ``Entry.Grammar.initializeAndLoop,
      ``Entry.Grammar.setupAndLoop,
      ``Entry.Grammar.checkEncoding?, ``Entry.Grammar.checkLiteralData?,
      ``Entry.Grammar.LiteralStage.executes,
      ``Allocation.Registry.storage, ``Entry.Pointers.allocatedBuffer,
      ``Entry.initializeGrammar,
      ``Entry.Pointers.preservedLiveLocal,
      ``Allocation.HostReady.rootsDistinct, ``Entry.Pointers.allocatedRootsDistinct,
      ``Entry.Pointers.preservedBuffer,
      ``Entry.Pointers.carryAllocatedBuffer] do
    for dependency in ← Lean.collectAxioms name do
      unless #[``propext, ``Classical.choice, ``Quot.sound].contains dependency do
        throwError "Packing preparation theorem {name} depends on {dependency}"

private def locals : LoopLocals := ⟨8, 12, 36, 23⟩

example : (Allocation.Sequence.distinctNames? ⟨[⟨⟨1, 2⟩, 10, by decide⟩, ⟨⟨2, 3⟩, 11, by decide⟩], .skip⟩).isSome = true := by decide
example : (Allocation.Sequence.distinctNames? ⟨[⟨⟨1, 2⟩, 10, by decide⟩, ⟨⟨1, 3⟩, 11, by decide⟩], .skip⟩).isSome = false := by decide

private def argcProgram : Program := { functions := [{
  id := 0, parameters := [], returnType := .scalar (.signed .i32), body := none,
  external := some (.host .argc) }] }

example : (Entry.checkArguments? argcProgram (Entry.Arguments.statement ⟨0, 1, .skip⟩)).isSome = true := by decide
example : (Entry.checkArguments? argcProgram (Entry.Arguments.statement ⟨2, 1, .skip⟩)).isSome = false := by decide
example : (Entry.checkArguments? argcProgram
    (.letLocal 1 (.scalar (.signed .i32)) (.call 0 [])
      (.sequence (.ifThenElse (.binary .lessEqual (.local 2) (.value (.signed .i32 1)))
        (.sequence (.returnValue (some (.value (.signed .i32 1)))) .skip) .skip) .skip))).isSome = false := by decide

example : (Allocation.checkSequence? 116 [2, 3]
    (Allocation.hostStatement 116 [⟨⟨1, 2⟩, 10, by decide⟩, ⟨⟨2, 3⟩, 11, by decide⟩] .skip)).isSome = true := by decide
example : (Allocation.checkSequence? 116 [2, 4]
    (Allocation.hostStatement 116 [⟨⟨1, 2⟩, 10, by decide⟩, ⟨⟨2, 3⟩, 11, by decide⟩] .skip)).isSome = false := by decide
example : (Allocation.checkSequence? 116 [2] (.letLocal 1 (.slice (.scalar (.signed .i32)))
    (.i32SliceFromRawParts (.call 116 [.value (.unsigned .usize 8),
      .value (.unsigned .usize 4)]) (.value (.signed .i32 2))) .skip)).isSome = false := by decide
example : (Allocation.checkSequence? 116 [2]
    (Allocation.hostStatement 117 [⟨⟨1, 2⟩, 10, by decide⟩] .skip)).isSome = false := by decide

example : (checkStdoutTail? (StdoutTail.statement ⟨37, 23, 16, 120⟩)).isSome = true := by decide
example : (checkStdoutTail? (.returnValue (some (.value (.signed .i32 0))))).isSome = false := by decide

private def mismatchedStdoutSize : Stmt :=
  match StdoutTail.statement ⟨37, 23, 16, 120⟩ with
  | .letLocal _ type initializer body => .letLocal 38 type initializer body
  | statement => statement

example : (checkStdoutTail? mismatchedStdoutSize).isSome = false := by decide

example : (checkPackingLoop? locals.loop).isSome = true := by decide

-- Looking like a packing assignment is insufficient: a different cursor
-- update does not satisfy the loop proof's termination or indexing invariant.
private def wrongCursor : Stmt :=
  .whileLoop (.binary .notEqual (.local locals.cursor) (.local locals.length))
    (.sequence (.expression locals.assignment)
      (.sequence (.expression (.assign .add (.local 99)
        (.value (.signed .i32 1)))) .skip))

example : (checkPackingLoop? wrongCursor).isSome = false := by decide

private def extraEffect : Stmt :=
  .whileLoop (.binary .notEqual (.local locals.cursor) (.local locals.length))
    (.sequence locals.body (.expression (.call 99 [])))

example : (checkPackingLoop? extraEffect).isSome = false := by decide

-- An assignment reading a different cursor is also rejected, even if the
-- enclosing loop's condition and increment agree.
private def wrongReadCursor : Stmt :=
  .whileLoop (.binary .notEqual (.local locals.cursor) (.local locals.length))
    (.sequence (.expression ({ locals with cursor := 99 }.assignment))
      (.sequence (.expression (.assign .add (.local locals.cursor)
        (.value (.signed .i32 1)))) .skip))

example : (checkPackingLoop? wrongReadCursor).isSome = false := by decide

example : (findPackingLoop? (.letLocal 0 (.scalar (.signed .i32))
    (.value (.signed .i32 0)) (.sequence .skip locals.loop))).isSome = true := by decide

example : (findPackingLoop? (.sequence wrongCursor extraEffect)).isSome = false := by decide

example : (checkClearLoop? locals.clearLoop).isSome = true := by decide
example : (checkClearLoop? locals.loop).isSome = false := by decide
example : (checkPackingLoop? locals.clearLoop).isSome = false := by decide
example : (findClearLoop? (.sequence locals.loop locals.clearLoop)).isSome = true := by decide

private def preparation : Preparation := ⟨locals, 34, 35, .returnValue (some (.value (.signed .i32 0)))⟩

example : (checkPreparation? preparation.statement).isSome = true := by decide

private def reversedPhases : Stmt :=
  match preparation.statement with
  | .letLocal words wordsTy wordsValue
      (.letLocal clear clearTy clearValue
        (.sequence clearLoop (.letLocal cursor cursorTy cursorValue (.sequence packLoop rest)))) =>
      .letLocal words wordsTy wordsValue
        (.letLocal clear clearTy clearValue
          (.sequence packLoop (.letLocal cursor cursorTy cursorValue (.sequence clearLoop rest))))
  | _ => .skip

example : (checkPreparation? reversedPhases).isSome = false := by decide

private def wrongWordCount : Stmt :=
  match preparation.statement with
  | .letLocal words type _ rest => .letLocal words type (.value (.signed .i32 0)) rest
  | _ => .skip

example : (checkPreparation? wrongWordCount).isSome = false := by decide

-- Exercise the real loop on a partial word with its sign bit set, with
-- spare capacity in both buffers. Neither unused tail may be overwritten.
private def inputBytes : List UInt8 := [255, 128, 127, 254, 42]
private def inputValues : List Int := [255, 128, 127, 254, 42, 87, 99, 120]
private def packingState : State := {
  locals := [(8, 3), (12, 4), (36, 2), (23, 5)]
  cells := [
    ⟨0, some (.array (signedI32Values [0, 0, 12345]))⟩,
    ⟨1, some (.array (signedI32Values inputValues))⟩,
    ⟨2, some (.signed .i32 0)⟩,
    ⟨3, some (.slice (.scalar (.signed .i32)) 0 [] 0 3)⟩,
    ⟨4, some (.slice (.scalar (.signed .i32)) 1 [] 0 8)⟩,
    ⟨5, some (.signed .i32 5)⟩]
  nextCell := 6
}

private def packingExecutionPreservesTails : Bool :=
  match execStmt 100 { target := .x86_64 } packingState locals.loop with
  | .done .next after =>
      after.cell? 0 == some (.array (pack inputBytes ++ signedI32Values [12345])) &&
      after.cell? 1 == some (.array (signedI32Values inputValues)) &&
      after.local? locals.cursor == some (.signed .i32 5)
  | _ => false

example : packingExecutionPreservesTails = true := by native_decide
