// Queue accepted call results and argument contexts as field-closure roots
// (ct_expand.slang), and re-queue deferred imported IDs whose declaration
// page is now resident. Runs at the start of each closure in the inference
// rounds, once per resident page, over the entries 04a listed.
import status;
import dependency_interface;
import type_checker.mutable_checked_type_graph;
import type_checker.canonical.canonical_api;
import type_checker.canonical.canonical_mutable_rows;
import type_checker.substitution.ct_checked;
import type_checker.substitution.ct_expand;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> call_inference_result_tag;
StructuredBuffer<uint> call_inference_result_payload;
StructuredBuffer<uint> argument_expected_ref_tag;
StructuredBuffer<uint> argument_expected_ref_payload;
// The locations listed by 04a, and the instance row last pushed from each.
RWStructuredBuffer<uint4> call_root_list;
StructuredBuffer<uint> call_root_count;
RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint lane = dtid.x + dtid.y * 16776960u;
    ct_expand_begin_run(lane, 1u);
    // The dispatch is 04a's grid over the listed entries.
    uint count = call_root_count[0u];
    uint groups = max((count + 255u) / 256u, 1u);
    uint lanes = min(groups, 65535u) * ((groups + 65534u) / 65535u) * 256u;
    if (lane >= lanes) return;
    // Deferred imported IDs: one lane per entry, striding over the lanes.
    uint deferred = ct_expand_counts[CT_EXPAND_DEFERRED];
    for (uint entry = lane; entry < deferred; entry += lanes)
    {
        uint2 item = ct_expand_deferred[entry];
        uint3 words = ct_words(item.x);
        if (item.x == CT_NONE || dependency_find_declaration(words.x, words.y, words.z) == INVALID)
            continue;
        ct_expand_deferred[entry].x = CT_NONE;
        if (!ct_expand_append(item.x, item.y))
            record_min_token_error(status, ct_expand_token(item.y), 6u, 0x474e0001u);
    }
    uint capacity; uint stride;
    call_root_list.GetDimensions(capacity, stride);
    if (lane >= min(count, capacity)) return;
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
