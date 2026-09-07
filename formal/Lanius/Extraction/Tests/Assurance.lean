import Lanius.Extraction.ExtractorContract
import Lanius.Extraction.OutputPacking.Clear
import Lanius.Extraction.OutputPacking.Stdout
import Lanius.Semantics.I32Views.Registry
import Lanius.World.FileRead
import Lanius.Extraction.Input.Unpacking
import Lanius.Extraction.Input.Read
import Lanius.Extraction.Input.Loop
import Lanius.Extraction.Input.Chunk
import Lanius.Extraction.Input.Preservation
import Lanius.Extraction.Input.Request
import Lanius.Extraction.CanonicalTokens.Ascii.Loop
import Lanius.Extraction.CanonicalTokens.Ascii.Entry
import Lanius.Extraction.CanonicalTokens.Ascii.Function
import Lanius.Extraction.CanonicalTokens.Ascii.Call
import Lanius.Extraction.CanonicalTokens.Dispatch.Checked
import Lanius.Extraction.CanonicalTokens.Dispatch.Lexer
import Lanius.Extraction.CanonicalTokens.Kind.Specification
import Lanius.Extraction.CanonicalTokens.Compaction.Call
import Lanius.Extraction.CanonicalTokens.Compaction.Range.Loop

-- These dependency reports must contain no sorryAx or project-specific axiom.
#print axioms Lanius.Extraction.ExtractorContract.packed_stdout_call_sound
#print axioms Lanius.Extraction.OutputPacking.writes_packed_byte
#print axioms Lanius.Semantics.syncI32ViewsToHeapFrom_reads_view
#print axioms Lanius.Memory.Heap.loadBytes_after_store
#print axioms Lanius.Extraction.OutputPacking.executes_packing_loop
#print axioms Lanius.Extraction.OutputPacking.findPackingLoop?
#print axioms Lanius.Extraction.OutputPacking.executes_clear_loop
#print axioms Lanius.Extraction.OutputPacking.packing_loop_sound
#print axioms Lanius.Extraction.OutputPacking.stdout_after_packing
#print axioms Lanius.Semantics.mapI32SliceDataPtr_preserves_distinct_addresses
#print axioms Lanius.Semantics.mapRawI32Slice_preserves_distinct_addresses
#print axioms Lanius.World.read_call_exact
#print axioms Lanius.World.closeHandle_appended_fresh
#print axioms Lanius.Extraction.Input.evaluates_unpacked_byte
#print axioms Lanius.Extraction.Input.encode_after_decode_i32_array
#print axioms Lanius.CallContracts.evaluatesHostCallReturned_invert
#print axioms Lanius.Extraction.Input.read_call_words
#print axioms Lanius.Semantics.syncI32ViewsFromHeapFrom_reads_view
#print axioms Lanius.Extraction.Input.executes_unpacking_loop
#print axioms Lanius.Extraction.Input.unpacking_loop_sound
#print axioms Lanius.Semantics.evaluatesNatI32Remainder
#print axioms Lanius.Extraction.Input.unpack_after_read
#print axioms Lanius.Extraction.Input.read_preserves_view
#print axioms Lanius.Extraction.Input.decode_i32_array_of_encoding
#print axioms Lanius.Memory.Heap.loadBytes_after_store_disjoint
#print axioms Lanius.Semantics.mapRawI32Slice_preserves_distinct_roots
#print axioms Lanius.Semantics.mapI32SliceDataPtr_existing_registry
#print axioms Lanius.Extraction.Input.executes_request_adjustment
#print axioms Lanius.Extraction.Input.requested_bytes_detect_overflow
#print axioms Lanius.World.readFileBytes_appended_fresh
#print axioms Lanius.Extraction.Input.evaluates_encoded_byte
#print axioms Lanius.Extraction.CanonicalTokens.Ascii.executes_loop
#print axioms Lanius.Extraction.CanonicalTokens.Ascii.loop_sound
#print axioms Lanius.Extraction.CanonicalTokens.Ascii.matchesBytes_iff_span
#print axioms Lanius.Extraction.CanonicalTokens.Ascii.string_words
#print axioms Lanius.Extraction.CanonicalTokens.Ascii.executes_finish
#print axioms Lanius.Memory.Heap.loadBytes_mapped_borrowed
#print axioms Lanius.Memory.Heap.protect_borrowed_identity
#print axioms Lanius.Extraction.Input.decode_whole_words
#print axioms Lanius.Extraction.CanonicalTokens.Ascii.evaluates_wordView
#print axioms Lanius.Extraction.CanonicalTokens.Ascii.executes_sourceBody
#print axioms Lanius.Extraction.CanonicalTokens.Ascii.evaluates_call
#print axioms Lanius.Extraction.CanonicalTokens.Dispatch.executes_choices
#print axioms Lanius.Extraction.CanonicalTokens.Dispatch.executes_branches
#print axioms Lanius.Extraction.CanonicalTokens.Dispatch.executes_body
#print axioms Lanius.Extraction.CanonicalTokens.Dispatch.dispatched_reference
#print axioms Lanius.Extraction.CanonicalTokens.Dispatch.Checked.executes
#print axioms Lanius.Extraction.CanonicalTokens.Dispatch.lookup_reference_lexer
#print axioms Lanius.Extraction.CanonicalTokens.Dispatch.CheckedFunction.evaluates_call
#print axioms Lanius.Extraction.CanonicalTokens.Kind.Checked.executes_body
#print axioms Lanius.Extraction.CanonicalTokens.Kind.Checked.evaluates_call
#print axioms Lanius.Extraction.CanonicalTokens.Kind.result_canonicalKind
#print axioms Lanius.Extraction.CanonicalTokens.Trivia.Checked.evaluates_call
#print axioms Lanius.Extraction.CanonicalTokens.Compaction.checkSource?
#print axioms Lanius.Extraction.CanonicalTokens.Compaction.replacePrefix_push_row
#print axioms Lanius.Extraction.CanonicalTokens.Compaction.replacePrefix_unread
#print axioms Lanius.Extraction.CanonicalTokens.Compaction.executes_row_stores
#print axioms Lanius.Separation.evaluatesSliceStore
#print axioms Lanius.Extraction.CanonicalTokens.Compaction.executes_kept_body
#print axioms Lanius.Extraction.CanonicalTokens.Compaction.executes_input_body
#print axioms Lanius.Extraction.CanonicalTokens.Compaction.executes_input_loop
#print axioms Lanius.Extraction.CanonicalTokens.Compaction.input_loop_sound
#print axioms Lanius.Extraction.CanonicalTokens.Compaction.Range.executes_body
#print axioms Lanius.Extraction.CanonicalTokens.Compaction.Range.executes_loop
#print axioms Lanius.Extraction.CanonicalTokens.Compaction.Range.loop_sound
#print axioms Lanius.Extraction.CanonicalTokens.Compaction.CheckedSource.executes_body
#print axioms Lanius.Extraction.CanonicalTokens.Compaction.CheckedSource.evaluates_call
