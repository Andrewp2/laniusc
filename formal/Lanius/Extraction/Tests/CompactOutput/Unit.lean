import Lanius.Extraction.CompactOutput.Unit.Guard
import Lanius.Extraction.CompactOutput.Unit.Entry
import Lanius.Extraction.CompactOutput.Unit.Function
import Lanius.Extraction.CompactOutput.Unit.Call
import Lanius.Extraction.CompactOutput.Unit.Collection
import Lanius.Extraction.CompactOutput.Unit.Lexical
import Lanius.Extraction.CompactOutput.Unit.Arguments
import Lanius.Extraction.CompactOutput.Unit.Pipeline
import Lanius.Extraction.CompactOutput.Unit.Chunks
import Lanius.Extraction.CompactOutput.Unit.Word
import Lanius.Extraction.CompactOutput.Unit.Bytes
import Lanius.Extraction.CompactOutput.Unit.Tokens
import Lanius.Extraction.CompactOutput.Unit.Semantic
import Lanius.Extraction.CompactOutput.Unit.Nodes
import Lanius.Extraction.CompactDecode.Emission
import Lanius.Extraction.CompactDecode.Contracts
import Lanius.Extraction.CompactDecode.Grammar
import Lanius.Extraction.CompactDecode.Acceptance.Semantic
import Lanius.Extraction.CompactDecode.Acceptance.Root
import Lanius.Extraction.CompactDecode.Acceptance.Tokens
import Lanius.Extraction.CompactDecode.Acceptance.Lexical
import Lanius.Extraction.CompactDecode.Acceptance.Nodes
import Lanius.Extraction.CompactDecode.Acceptance.Origins
import Lanius.Extraction.CompactDecode.Acceptance.Assignments
import Lanius.Extraction.CompactDecode.Acceptance.Terminals
import Lanius.Extraction.CompactDecode.Acceptance.Symbols
import Lanius.Extraction.CompactDecode.Acceptance.Unit
import Lanius.Extraction.CompactDecode.Packing
import Lean.Util.CollectAxioms

namespace Lanius.Extraction.Tests.CompactOutput.Unit

run_elab do
  let standard : Array Lean.Name := #[``propext, ``Classical.choice, ``Quot.sound]
  for name in #[``Lanius.Extraction.checkRawTokenTraceFrom_complete,
      ``Lanius.Extraction.checkRawTokenTrace_complete,
      ``Lanius.Extraction.decodeBytes_values,
      ``Lanius.Extraction.decodeTokens_rows,
      ``Lanius.Extraction.CompactDecode.emission_tokens_accepted,
      ``Lanius.Extraction.CompactDecode.completed_lexRaw,
      ``Lanius.Extraction.CompactDecode.frontend_tokens_accepted,
      ``Lanius.Extraction.CompactDecode.collection_node_headers,
      ``Lanius.Extraction.CompactDecode.collection_node_link,
      ``Lanius.Extraction.CompactDecode.children_match_accepted,
      ``Lanius.Extraction.CompactDecode.node_match_accepted,
      ``Lanius.Extraction.CompactDecode.nodes_match_accepted,
      ``Lanius.Extraction.CompactDecode.tree_record_origins,
      ``Lanius.Extraction.CompactDecode.forest_record_origins,
      ``Lanius.Extraction.CompactDecode.collection_record_origins,
      ``Lanius.Extraction.CompactDecode.assignments_lookup,
      ``Lanius.Extraction.CompactDecode.assignment_advance_whole,
      ``Lanius.Extraction.CompactDecode.assignment_advance_first,
      ``Lanius.Extraction.CompactDecode.assignment_advance_second,
      ``Lanius.Extraction.CompactDecode.path_assignment_advance,
      ``Lanius.Extraction.CompactDecode.collection_terminal_advance,
      ``Lanius.Extraction.CompactDecode.ChildSymbol.frame,
      ``Lanius.Extraction.CompactDecode.ChildSymbols.frame,
      ``Lanius.Extraction.CompactDecode.tree_reference_symbol,
      ``Lanius.Extraction.CompactDecode.forest_reference_symbols,
      ``Lanius.Extraction.CompactDecode.RecordSymbols.frame,
      ``Lanius.Extraction.CompactDecode.tree_record_symbols,
      ``Lanius.Extraction.CompactDecode.forest_record_symbols,
      ``Lanius.Extraction.CompactDecode.collection_record_symbols,
      ``Lanius.Extraction.CompactDecode.visit_children_match,
      ``Lanius.Extraction.CompactDecode.collection_node_match,
      ``Lanius.Extraction.CompactDecode.nodes_match_mapped,
      ``Lanius.Extraction.CompactDecode.collection_nodes_accepted,
      ``Lanius.Extraction.CompactDecode.frontend_artifact_accepted,
      ``Lanius.Extraction.CompactDecode.packing_input_prefix,
      ``Lanius.Extraction.CompactDecode.packing_decode_unit,
      ``Lanius.Extraction.CompactOutput.Unit.guard_pass,
      ``Lanius.Extraction.CompactOutput.Unit.Memory.enter,
      ``Lanius.Extraction.CompactOutput.Unit.initialize_cursor,
      ``Lanius.Extraction.CompactOutput.Unit.Inputs.transport,
      ``Lanius.Extraction.CompactOutput.Unit.Owned.combine,
      ``Lanius.Extraction.CompactOutput.Unit.Inputs.execute_tail,
      ``Lanius.Extraction.CompactOutput.Unit.Inputs.execute,
      ``Lanius.Extraction.CompactOutput.Unit.Checked.write,
      ``Lanius.Extraction.SemanticTokens.tree_visits_productions,
      ``Lanius.Extraction.SemanticTokens.forest_visits_productions,
      ``Lanius.Extraction.SemanticTokens.CollectionRecords.assignment_fields,
      ``Lanius.Extraction.SemanticTokens.CollectionRecords.semanticInput,
      ``Lanius.Extraction.SemanticTokens.CollectionRecords.node_fields,
      ``Lanius.Extraction.SemanticTokens.CollectionRecords.nonempty,
      ``Lanius.Extraction.SemanticTokens.CollectionRecords.nodeInput,
      ``Lanius.Extraction.CompactOutput.Unit.kind_fits,
      ``Lanius.Extraction.CompactOutput.Unit.canonical_filter_spans,
      ``Lanius.Extraction.CompactOutput.Unit.inclusive_range_spans,
      ``Lanius.Extraction.CompactOutput.Unit.raw_fields,
      ``Lanius.Extraction.CompactOutput.Unit.canonical_fields,
      ``Lanius.Extraction.CompactOutput.Unit.byteInput,
      ``Lanius.Extraction.CompactOutput.Unit.lexical_storage,
      ``Lanius.Extraction.CompactOutput.Unit.rawInput,
      ``Lanius.Extraction.CompactOutput.Unit.canonicalInput,
      ``Lanius.Extraction.CompactOutput.Unit.lexical_storage_after_collection,
      ``Lanius.Extraction.CompactOutput.Unit.Storage.inputs,
      ``Lanius.Extraction.CompactOutput.Unit.Storage.inputs_nonempty,
      ``Lanius.Extraction.CompactOutput.Unit.Storage.inputs_encoding,
      ``Lanius.Extraction.CompactOutput.Unit.Storage.of_collection,
      ``Lanius.Extraction.CompactOutput.Unit.Storage.write,
      ``Lanius.Extraction.CompactOutput.Unit.collection_then_emit,
      ``Lanius.Extraction.CompactOutput.Unit.following_chunk,
      ``Lanius.Extraction.CompactOutput.Unit.following_nonempty,
      ``Lanius.Extraction.CompactOutput.Unit.Memory.owned,
      ``Lanius.Extraction.CompactOutput.Unit.Owned.local,
      ``Lanius.Extraction.CompactOutput.Unit.Owned.input,
      ``Lanius.Extraction.CompactOutput.Unit.Owned.assign,
      ``Lanius.Extraction.CompactOutput.Unit.Owned.word,
      ``Lanius.Extraction.CompactOutput.Unit.Owned.bytes,
      ``Lanius.Extraction.CompactOutput.Unit.Owned.tokens,
      ``Lanius.Extraction.CompactOutput.Unit.Owned.semantic,
      ``Lanius.Extraction.CompactOutput.Unit.Owned.nodes,
      ``Lanius.Extraction.CompactDecode.byte_hex_encoding,
      ``Lanius.Extraction.CompactDecode.sourceArray_size,
      ``Lanius.Extraction.CompactDecode.sourceArray_values,
      ``Lanius.Extraction.CompactDecode.emission_encoding,
      ``Lanius.Extraction.CompactDecode.emission_decode,
      ``Lanius.Extraction.CompactDecode.nodeInput_encodable,
      ``Lanius.Extraction.CompactDecode.storage_encodable,
      ``Lanius.Extraction.CompactDecode.storage_decode,
      ``Lanius.Extraction.CompactDecode.EncodedAt.of_buffer,
      ``Lanius.Extraction.CompactDecode.EncodedAt.after_append,
      ``Lanius.Extraction.CompactDecode.storage_decode_output,
      ``Lanius.Extraction.CompactDecode.collection_productions,
      ``Lanius.Extraction.CompactDecode.storage_decode_same_grammar,
      ``Lanius.Extraction.CompactDecode.emission_semantic_accepted,
      ``Lanius.Extraction.CompactDecode.collection_root_accepted,
      ``Lanius.Extraction.CompactDecode.emission_root_accepted] do
    unless (← Lean.getEnv).contains name do throwError "Missing unit-emitter theorem {name}"
    for axiomName in ← Lean.collectAxioms name do
      unless standard.contains axiomName do throwError "Unit-emitter theorem {name} depends on {axiomName}"
  Lean.logInfo "Unit-emitter, decoding, and complete syntax-acceptance bridge proofs use standard axioms only; actual I/O byte backing, loaded grammar identity, and whole-extractor contracts remain open."

end Lanius.Extraction.Tests.CompactOutput.Unit
