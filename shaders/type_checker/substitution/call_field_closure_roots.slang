// Queue accepted call results and argument contexts as field-closure roots
// (field_closure.slang), and re-queue deferred imported IDs whose declaration
// page is now resident. Runs at the start of each closure in the inference
// rounds, once per resident page, over the entries list_call_field_closure_roots listed.
import shared.buffers.status;
import shared.semantics.dependency_interface;
import type_checker.checked_types.mutable_checked_type_graph;
import type_checker.canonicalization.canonical_api;
import type_checker.canonicalization.canonical_mutable_rows;
import type_checker.substitution.checked_operand_ids;
import type_checker.substitution.field_closure;

StructuredBuffer<uint> call_inference_result_tag;
StructuredBuffer<uint> call_inference_result_payload;
StructuredBuffer<uint> argument_expected_ref_tag;
StructuredBuffer<uint> argument_expected_ref_payload;
// The locations listed by list_call_field_closure_roots, and the instance row last pushed from each.
RWStructuredBuffer<uint4> call_root_list;
public StructuredBuffer<uint> call_root_count;

static const uint INVALID = 0xffffffffu;

public void queue_call_field_closure_root(uint lane, RWStructuredBuffer<uint> status)
{
    // Family 0 is a call result, family 1 an argument context.
    uint4 root = call_root_list[lane];
    bool argument = (root.y >> 31u) != 0u;
    uint token = root.y & 0x7fffffffu;
    uint tag = argument ? argument_expected_ref_tag[root.x] : call_inference_result_tag[root.x];
    uint row = argument ? argument_expected_ref_payload[root.x] : call_inference_result_payload[root.x];
    // A row interns to one ID for the job, whose mark is set once pushed.
    if (tag != 3u || row == root.z || row >= mutable_type_capacity()) return;
    uint spare = CT_NONE;
    uint id = ct_intern_checked<CtMutableRows>(3u, row, spare);
    if (!ct_is_resolved(id)) return;
    if (ct_expand_push(id, ct_expand_word(token, 0u, argument))) call_root_list[lane].z = row;
    else record_min_token_error(status, token, 6u, 0x474e0001u);
}


// A deferred entry belongs to one lane within this run.
public void requeue_call_field_closure_root(uint entry, RWStructuredBuffer<uint> status)
{
    uint2 item = ct_expand_deferred[entry];
    if (item.x == CT_NONE) return;
    uint3 words = ct_words(item.x);
    if (dependency_find_declaration(words.x, words.y, words.z) == INVALID) return;
    ct_expand_deferred[entry].x = CT_NONE;
    if (!ct_expand_append(item.x, item.y))
        record_min_token_error(status, ct_expand_token(item.y), 6u, 0x474e0001u);
}

public uint call_field_closure_root_count()
{
    uint capacity; uint stride;
    call_root_list.GetDimensions(capacity, stride);
    return min(call_root_count[0u], capacity);
}
